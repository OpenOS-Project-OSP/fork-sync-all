#!/usr/bin/env bash
#
# Orchestrate all artifact mirroring from UPSTREAM_OWNER to OSP and OOC.
# Called by the mirror-artifacts workflow on release events and hourly.
#
# For each repo in OSP/OOC:
#   - GitHub Releases + assets  (always)
#   - GHCR images               (if repo has build-ci-images.yml)
#   - PyPI packages             (if repo has publish.yml targeting PyPI)
#   - Flatpak bundles           (if release has .flatpak assets)
#   - RPM packages              (if release has .rpm assets)
#
# Requires: GH_TOKEN, UPSTREAM_OWNER, OSP_ORG, OOC_ORG
# Optional: UPSTREAM_REPO, RELEASE_TAG (if triggered by a specific release)
#
set -uo pipefail

: "${GH_TOKEN:?required}"
: "${UPSTREAM_OWNER:?required}"
: "${OSP_ORG:?required}"
: "${OOC_ORG:?required}"

UPSTREAM_REPO="${UPSTREAM_REPO:-}"
RELEASE_TAG="${RELEASE_TAG:-}"

API="https://api.github.com"
AUTH=(-H "Authorization: token ${GH_TOKEN}" -H "Accept: application/vnd.github+json")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXCLUDED_REPOS=("fork-sync-all" "org-mirror")

api_get() { curl --disable --silent "${AUTH[@]}" "$@"; }

is_excluded() {
  local r="$1"
  for ex in "${EXCLUDED_REPOS[@]}"; do [[ "$r" == "$ex" ]] && return 0; done
  return 1
}

get_org_repos() {
  local org="$1" page=1
  while true; do
    local result count
    result=$(api_get "${API}/orgs/${org}/repos?type=all&per_page=100&page=${page}")
    count=$(echo "$result" | jq 'length' 2>/dev/null || echo 0)
    [[ "$count" == "0" || "$count" == "null" ]] && break
    echo "$result" | jq -r '.[].name'
    (( page++ ))
  done
}

has_workflow() {
  local org="$1" repo="$2" wf="$3"
  local result
  result=$(api_get "${API}/repos/${org}/${repo}/contents/.github/workflows/${wf}")
  echo "$result" | jq -e '.sha' > /dev/null 2>&1
}

# Mirror GitHub Releases for a single repo to a single org
mirror_releases_for_repo() {
  local src_repo="$1" dst_org="$2"
  export GH_TOKEN UPSTREAM_OWNER OSP_ORG OOC_ORG

  # Get upstream releases (or just the specific one if RELEASE_TAG is set)
  local releases
  if [[ -n "$RELEASE_TAG" ]]; then
    releases=$(api_get "${API}/repos/${UPSTREAM_OWNER}/${src_repo}/releases/tags/${RELEASE_TAG}")
    releases="[$releases]"
  else
    releases=$(api_get "${API}/repos/${UPSTREAM_OWNER}/${src_repo}/releases?per_page=100")
  fi

  local count
  count=$(echo "$releases" | jq 'length' 2>/dev/null || echo 0)
  [[ "$count" == "0" ]] && return

  # Get existing tags in mirror
  local existing_tags
  existing_tags=$(api_get "${API}/repos/${dst_org}/${src_repo}/releases?per_page=100" | \
    jq -r '.[].tag_name' 2>/dev/null || echo "")

  local tmpdir
  tmpdir=$(mktemp -d)
  trap "rm -rf '$tmpdir'" RETURN

  while IFS= read -r release; do
    local tag name body prerelease draft
    tag=$(echo "$release" | jq -r '.tag_name')
    name=$(echo "$release" | jq -r '.name // .tag_name')
    body=$(echo "$release" | jq -r '.body // ""')
    prerelease=$(echo "$release" | jq -r '.prerelease')
    draft=$(echo "$release" | jq -r '.draft')

    [[ "$draft" == "true" ]] && continue
    echo "$existing_tags" | grep -qxF "$tag" && continue

    echo "    [releases] ${dst_org}/${src_repo}: creating $tag"

    local mirror_body
    mirror_body="${body}

---
*Mirrored from [${UPSTREAM_OWNER}/${src_repo}](https://github.com/${UPSTREAM_OWNER}/${src_repo}/releases/tag/${tag})*"

    local payload
    payload=$(jq -n \
      --arg tag "$tag" --arg name "$name" --arg body "$mirror_body" \
      --argjson prerelease "$prerelease" \
      '{tag_name:$tag,name:$name,body:$body,prerelease:$prerelease,draft:false}')

    local new_release
    new_release=$(curl --disable --silent -X POST \
      "${AUTH[@]}" -H "Content-Type: application/json" \
      "${API}/repos/${dst_org}/${src_repo}/releases" -d "$payload")

    local upload_url
    upload_url=$(echo "$new_release" | jq -r '.upload_url // empty' | sed 's/{?name,label}//')
    [[ -z "$upload_url" ]] && { echo "    FAILED: $(echo "$new_release" | jq -r '.message')"; continue; }

    # Upload assets
    while IFS= read -r asset_line; do
      [[ -z "$asset_line" ]] && continue
      local aname atype aurl
      aname=$(echo "$asset_line" | jq -r '.name')
      atype=$(echo "$asset_line" | jq -r '.content_type')
      aurl=$(echo "$asset_line" | jq -r '.browser_download_url')
      local afile="${tmpdir}/${aname}"
      curl --disable --silent -L -H "Authorization: token ${GH_TOKEN}" -o "$afile" "$aurl"
      local http
      http=$(curl --disable --silent -o /dev/null -w "%{http_code}" -X POST \
        -H "Authorization: token ${GH_TOKEN}" -H "Content-Type: ${atype}" \
        "${upload_url}?name=${aname}" --data-binary "@${afile}")
      echo "      asset: $aname (HTTP $http)"
      rm -f "$afile"
    done < <(echo "$release" | jq -c '.assets[]')

    # Mirror Flatpak if .flatpak asset present
    if echo "$release" | jq -e '.assets[] | select(.name | endswith(".flatpak"))' > /dev/null 2>&1; then
      echo "    [flatpak] ${dst_org}/${src_repo}: $tag"
      UPSTREAM_REPO="$src_repo" TARGET_ORG="$dst_org" RELEASE_TAG="$tag" \
        bash "${SCRIPT_DIR}/mirror-flatpak.sh" || echo "    flatpak mirror failed (non-fatal)"
    fi

    # Mirror RPM if .rpm asset present
    if echo "$release" | jq -e '.assets[] | select(.name | endswith(".rpm"))' > /dev/null 2>&1; then
      echo "    [rpm] ${dst_org}/${src_repo}: $tag"
      UPSTREAM_REPO="$src_repo" TARGET_ORG="$dst_org" RELEASE_TAG="$tag" \
        bash "${SCRIPT_DIR}/mirror-rpm.sh" || echo "    rpm mirror failed (non-fatal)"
    fi

  done < <(echo "$releases" | jq -c '.[]')
}

# ── main ─────────────────────────────────────────────────────────────────────

echo "Validating token..."
remaining=$(api_get "${API}/rate_limit" | jq -r '.resources.core.remaining // empty')
[[ -z "$remaining" ]] && { echo "ERROR: GH_TOKEN invalid."; exit 1; }
echo "Token valid. Core API requests remaining: $remaining"
echo ""

# GHCR mirror runs once (not per-repo)
echo "========================================"
echo "Mirroring GHCR images"
echo "========================================"
bash "${SCRIPT_DIR}/mirror-ghcr.sh" || echo "GHCR mirror failed (non-fatal)"
echo ""

# Per-repo release + package mirroring
for org in "$OSP_ORG" "$OOC_ORG"; do
  echo "========================================"
  echo "Mirroring releases to ${org}"
  echo "========================================"

  # If triggered by a specific repo release, only process that repo
  if [[ -n "$UPSTREAM_REPO" ]]; then
    repos="$UPSTREAM_REPO"
  else
    repos=$(get_org_repos "$org")
  fi

  while IFS= read -r repo; do
    [[ -z "$repo" ]] && continue
    is_excluded "$repo" && continue
    upstream_name=$(api_get "${API}/repos/${UPSTREAM_OWNER}/${repo}" | jq -r '.name // empty')
    [[ -z "$upstream_name" ]] && continue

    echo "  --- ${org}/${repo} ---"
    mirror_releases_for_repo "$repo" "$org"
    echo ""
  done <<< "$repos"
done

echo "========================================"
echo "Artifact mirror complete."
echo "========================================"
