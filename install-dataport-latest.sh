#!/bin/bash
set -e

REPO="carlossepulveda-dev/dataport"
PACKAGE="dataport-latest.deb"

echo "Downloading latest DataPort release..."

DOWNLOAD_URL=$(curl -s "https://api.github.com/repos/${REPO}/releases/latest" \
  | grep browser_download_url \
  | grep '\.deb"' \
  | cut -d '"' -f 4)

if [ -z "$DOWNLOAD_URL" ]; then
  echo "Error: No .deb package found in latest release."
  exit 1
fi

echo "Latest package:"
echo "$DOWNLOAD_URL"

rm -f "$PACKAGE"

wget -O "$PACKAGE" "$DOWNLOAD_URL"

echo "Installing DataPort..."

sudo apt install -y "./$PACKAGE"

echo "Restarting DataPort service..."

sudo systemctl restart dataport.service || true

echo "Done."
echo "DataPort installed/updated successfully."
