#!/usr/bin/env bash
set -euo pipefail

REPOSITORY="carlossepulveda-dev/dataport"
API_URL="https://api.github.com/repos/${REPOSITORY}/releases"
VERSION_PATTERN='^[0-9]+\.[0-9]+\.[0-9]+$'

for command in curl sudo; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Required command not found: $command" >&2
    exit 1
  }
done

if ! command -v jq >/dev/null 2>&1; then
  echo "Installing required dependency: jq"
  sudo apt-get update
  sudo apt-get install -y jq ca-certificates
fi

RELEASE_JSON="$(curl --fail --silent --show-error "${API_URL}/latest")"

TAG="$(jq -r '.tag_name // empty' <<<"$RELEASE_JSON")"
VERSION="${TAG#v}"
PRERELEASE="$(jq -r '.prerelease // empty' <<<"$RELEASE_JSON")"

if ! [[ "$VERSION" =~ $VERSION_PATTERN ]] || [ "$PRERELEASE" != "false" ]; then
  echo "No valid FINAL release was found." >&2
  exit 1
fi

PACKAGE_NAME="dataport_${VERSION}_all.deb"
DOWNLOAD_URL="$(
  jq -r --arg name "$PACKAGE_NAME" '
    .assets[]? | select(.name == $name) | .browser_download_url
  ' <<<"$RELEASE_JSON" | head -n 1
)"

if [ -z "$DOWNLOAD_URL" ]; then
  echo "Release $TAG does not contain $PACKAGE_NAME." >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Installing DataPort $VERSION from the FINAL channel..."
curl --fail --location --show-error --output "$TMP_DIR/$PACKAGE_NAME" "$DOWNLOAD_URL"
sudo apt install -y --allow-downgrades "$TMP_DIR/$PACKAGE_NAME"
