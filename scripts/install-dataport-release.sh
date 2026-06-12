#!/usr/bin/env bash
set -euo pipefail

CHANNEL="${1:-}"
REPOSITORY="${DATAPORT_RELEASE_REPOSITORY:-carlossepulveda-dev/dataport}"
API_URL="https://api.github.com/repos/${REPOSITORY}/releases"

case "$CHANNEL" in
  dev) VERSION_PATTERN='^[0-9]+\.[0-9]+\.[0-9]+-dev\.[0-9]+$' ;;
  rc) VERSION_PATTERN='^[0-9]+\.[0-9]+\.[0-9]+-rc\.[0-9]+$' ;;
  final) VERSION_PATTERN='^[0-9]+\.[0-9]+\.[0-9]+$' ;;
  *) echo "Usage: $0 dev|rc|final" >&2; exit 2 ;;
esac

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

if [ "$CHANNEL" = "final" ]; then
  RELEASE_JSON="$(curl --fail --silent --show-error "${API_URL}/latest")"
else
  RELEASE_JSON="$(
    curl --fail --silent --show-error "${API_URL}?per_page=100" |
      jq --arg channel "$CHANNEL" '
        map(select(
          .draft == false and
          .prerelease == true and
          (.tag_name | test("^v?[0-9]+\\.[0-9]+\\.[0-9]+-" + $channel + "\\.[0-9]+$"))
        )) |
        sort_by(.published_at) |
        last
      '
  )"
fi

TAG="$(jq -r '.tag_name // empty' <<<"$RELEASE_JSON")"
VERSION="${TAG#v}"
PRERELEASE="$(jq -r '.prerelease // empty' <<<"$RELEASE_JSON")"

if ! [[ "$VERSION" =~ $VERSION_PATTERN ]]; then
  echo "No valid $CHANNEL release was found." >&2
  exit 1
fi

if { [ "$CHANNEL" = "final" ] && [ "$PRERELEASE" != "false" ]; } ||
   { [ "$CHANNEL" != "final" ] && [ "$PRERELEASE" != "true" ]; }; then
  echo "Release channel metadata does not match $CHANNEL." >&2
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

echo "Installing DataPort $VERSION from the $CHANNEL channel..."
curl --fail --location --show-error --output "$TMP_DIR/$PACKAGE_NAME" "$DOWNLOAD_URL"

# Debian revisions sort after a version without a revision, so moving from
# x.y.z-dev.N or x.y.z-rc.N to the required FINAL x.y.z needs this flag.
sudo apt install -y --allow-downgrades "$TMP_DIR/$PACKAGE_NAME"
