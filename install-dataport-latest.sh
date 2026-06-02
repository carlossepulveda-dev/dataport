#!/bin/bash
set -e

REPO="carlossepulveda-dev/dataport"
PACKAGE="dataport-latest.deb"
SERVICE_NAME="dataport.service"

echo "Downloading latest DataPort release..."

DOWNLOAD_URL=$(curl -s "https://api.github.com/repos/${REPO}/releases/latest" \
  | grep browser_download_url \
  | grep '\.deb"' \
  | head -n 1 \
  | cut -d '"' -f 4)

if [ -z "$DOWNLOAD_URL" ]; then
  echo "No .deb found in latest final release. Checking prereleases/RC builds..."

  DOWNLOAD_URL=$(curl -s "https://api.github.com/repos/${REPO}/releases" \
    | grep browser_download_url \
    | grep '\.deb"' \
    | head -n 1 \
    | cut -d '"' -f 4)
fi

if [ -z "$DOWNLOAD_URL" ]; then
  echo "Error: No .deb package found in any release."
  exit 1
fi

echo "Latest package:"
echo "$DOWNLOAD_URL"

rm -f "$PACKAGE"

wget -O "$PACKAGE" "$DOWNLOAD_URL"

echo "Installing DataPort..."

sudo apt update
sudo apt install -y "./$PACKAGE"

echo "Restarting DataPort service..."

sudo systemctl restart "$SERVICE_NAME" || true

echo "Cleaning up..."

rm -f "$PACKAGE"

echo "Done."
echo "DataPort installed/updated successfully."
