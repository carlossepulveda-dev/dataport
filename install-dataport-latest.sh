#!/usr/bin/env bash
set -euo pipefail

CHANNEL="FINAL"
REPOSITORY="carlossepulveda-dev/dataport"
API_URL="https://api.github.com/repos/${REPOSITORY}/releases"
RELEASE_API_URL="${API_URL}/latest"
VERSION_PATTERN='^[0-9]+\.[0-9]+\.[0-9]+$'
DRY_RUN="${DATAPORT_DRY_RUN:-false}"

if [ "${1:-}" = "--dry-run" ]; then
  DRY_RUN="true"
elif [ "$#" -gt 0 ]; then
  echo "Usage: $0 [--dry-run]" >&2
  exit 2
fi

echo "Selected channel: $CHANNEL" >&2
echo "GitHub API URL: $RELEASE_API_URL" >&2

command -v curl >/dev/null 2>&1 || {
  echo "Required command not found: curl" >&2
  exit 1
}

if ! command -v jq >/dev/null 2>&1; then
  command -v sudo >/dev/null 2>&1 || {
    echo "Required command not found: jq. Automatic installation also requires sudo." >&2
    exit 1
  }
  command -v apt-get >/dev/null 2>&1 || {
    echo "Required command not found: jq. Automatic installation requires apt-get." >&2
    exit 1
  }
  echo "Installing required dependency: jq" >&2
  sudo apt-get update </dev/null
  sudo apt-get install -y jq ca-certificates </dev/null
fi

if ! RELEASE_JSON="$(
  curl --fail-with-body --silent --show-error --location \
    --connect-timeout 20 --retry 3 --retry-delay 2 \
    --header "Accept: application/vnd.github+json" \
    --header "X-GitHub-Api-Version: 2022-11-28" \
    --header "User-Agent: dataport-installer" \
    "$RELEASE_API_URL"
)"; then
  echo "GitHub API request failed: $RELEASE_API_URL" >&2
  echo "No FINAL release may be published, GitHub may be unavailable, or the API rate limit may have been reached." >&2
  exit 1
fi

TAG="$(jq -r '.tag_name // empty' <<<"$RELEASE_JSON")"
VERSION="${TAG#v}"
PRERELEASE="$(jq -r '.prerelease // empty' <<<"$RELEASE_JSON")"

echo "Matched release tag: ${TAG:-none}" >&2

if ! [[ "$VERSION" =~ $VERSION_PATTERN ]] || [ "$PRERELEASE" != "false" ]; then
  echo "No valid FINAL release was found. FINAL requires a non-prerelease tag such as v2.2.0." >&2
  exit 1
fi

PACKAGE_NAME="dataport_${VERSION}_all.deb"
echo "Expected asset name: $PACKAGE_NAME" >&2

DOWNLOAD_URL="$(
  jq -r --arg name "$PACKAGE_NAME" '
    .assets[]? | select(.name == $name) | .browser_download_url
  ' <<<"$RELEASE_JSON" | head -n 1
)"
MATCHED_ASSET="$(jq -r --arg url "$DOWNLOAD_URL" '.assets[]? | select(.browser_download_url == $url) | .name' <<<"$RELEASE_JSON" | head -n 1)"

if [ -z "$DOWNLOAD_URL" ]; then
  echo "Release $TAG does not contain the required asset $PACKAGE_NAME." >&2
  echo "Available assets: $(jq -r '[.assets[]?.name] | if length == 0 then "none" else join(", ") end' <<<"$RELEASE_JSON")" >&2
  exit 1
fi

echo "Matched asset name: $MATCHED_ASSET" >&2
echo "Download URL: $DOWNLOAD_URL" >&2

if [ "$DRY_RUN" = "true" ]; then
  echo "$DOWNLOAD_URL"
  exit 0
fi

command -v sudo >/dev/null 2>&1 || {
  echo "Required command not found: sudo" >&2
  exit 1
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Installing DataPort $VERSION from the $CHANNEL channel..."
curl --fail --location --show-error --connect-timeout 20 --retry 3 --retry-delay 2 \
  --output "$TMP_DIR/$PACKAGE_NAME" "$DOWNLOAD_URL"
sudo apt install -y --allow-downgrades "$TMP_DIR/$PACKAGE_NAME" </dev/null
