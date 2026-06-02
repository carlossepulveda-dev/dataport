$ErrorActionPreference = "Stop"

$Version = "2.0.0"
$Arch = "all"

$SourceRoot = "C:\Dev\DTDATAPLUS"
$ReleaseRoot = "C:\Dev\dataport"

$PackageRoot = "$ReleaseRoot\package\dataport"
$DebName = "dataport_${Version}_${Arch}.deb"

function Write-LinuxFile {
    param (
        [string]$Path,
        [string]$Content
    )

    $Utf8NoBom = New-Object System.Text.UTF8Encoding $false
    $Content = $Content -replace "`r`n", "`n"
    if (-not $Content.EndsWith("`n")) {
        $Content += "`n"
    }
    [System.IO.File]::WriteAllText($Path, $Content, $Utf8NoBom)
}

Write-Host "====================================================="
Write-Host " Building DataPort Debian Package"
Write-Host " Source:  $SourceRoot"
Write-Host " Output:  $ReleaseRoot\$DebName"
Write-Host "====================================================="

if (!(Test-Path $SourceRoot)) {
    throw "Source folder not found: $SourceRoot"
}

if (!(Test-Path $ReleaseRoot)) {
    throw "Release folder not found: $ReleaseRoot"
}

Write-Host "Cleaning previous package..."
Remove-Item "$ReleaseRoot\package" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "$ReleaseRoot\*.deb" -Force -ErrorAction SilentlyContinue

Write-Host "Building source app..."
Push-Location $SourceRoot
npm install
npm run build
Pop-Location

Write-Host "Creating package structure..."
New-Item -ItemType Directory -Force "$PackageRoot\DEBIAN" | Out-Null
New-Item -ItemType Directory -Force "$PackageRoot\opt\dataport" | Out-Null
New-Item -ItemType Directory -Force "$PackageRoot\usr\local\bin" | Out-Null
New-Item -ItemType Directory -Force "$PackageRoot\etc\systemd\system" | Out-Null

Write-Host "Copying app files..."
Copy-Item "$SourceRoot\dist" "$PackageRoot\opt\dataport\dist" -Recurse -Force
Copy-Item "$SourceRoot\server" "$PackageRoot\opt\dataport\server" -Recurse -Force
Copy-Item "$SourceRoot\shared" "$PackageRoot\opt\dataport\shared" -Recurse -Force
Copy-Item "$SourceRoot\public" "$PackageRoot\opt\dataport\public" -Recurse -Force
Copy-Item "$SourceRoot\server.cjs" "$PackageRoot\opt\dataport\server.cjs" -Force
Copy-Item "$SourceRoot\package.json" "$PackageRoot\opt\dataport\package.json" -Force
Copy-Item "$SourceRoot\package-lock.json" "$PackageRoot\opt\dataport\package-lock.json" -Force

Write-Host "Creating DEBIAN/control..."
Write-LinuxFile "$PackageRoot\DEBIAN\control" @"
Package: dataport
Version: $Version
Section: utils
Priority: optional
Architecture: all
Maintainer: Carlos Sepulveda
Depends: nodejs, npm, nginx, sqlite3, mosquitto, mosquitto-clients, openssh-server, socat, curl, ca-certificates, jq, rsync, libnss3-tools
Description: DataPort local web application for BMO and DT5 workflows

"@

Write-Host "Creating install.sh..."
Write-LinuxFile "$PackageRoot\opt\dataport\install.sh" @'
#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="dataport"
SERVICE_NAME="dataport.service"
APP_DIR="$(cd "$(dirname "$0")" && pwd)"

ENABLE_SSL="${ENABLE_SSL:-true}"
PI_STATIC_IP="${PI_STATIC_IP:-10.0.0.1}"

PORT="${PORT:-3001}"
NODE_PORT="$PORT"

APP_USER="${SUDO_USER:-$USER}"

SHARED_FOLDER="/home/admin/DT5/BPEX"
BMO_MIRROR_FOLDER="/home/admin/DT5/BMO"
BMO_SFTP_FOLDER="/home/Davey/BMO"

SSL_DIR="/etc/ssl/dataport"
SERVER_KEY="$SSL_DIR/dataport.key"
SERVER_CERT="$SSL_DIR/dataport.crt"

BMO_STATUS_DIR="/var/lib/dataport"
BMO_USB_STATUS_FILE="$BMO_STATUS_DIR/bmo-usb-status.json"

echo "========================================================="
echo " Installing $PROJECT_NAME"
echo " App directory: $APP_DIR"
echo " Service user: $APP_USER"
echo "========================================================="

sudo apt update

sudo apt install -y \
  nodejs \
  npm \
  nginx \
  curl \
  ca-certificates \
  libnss3-tools \
  mosquitto \
  mosquitto-clients \
  openssh-server \
  socat \
  jq \
  rsync

sudo mkdir -p "$BMO_STATUS_DIR"
sudo mkdir -p "$SHARED_FOLDER"
sudo mkdir -p "$BMO_MIRROR_FOLDER"
sudo mkdir -p "$BMO_SFTP_FOLDER"

sudo chown -R "$APP_USER:$APP_USER" "$BMO_STATUS_DIR"
sudo chmod 775 "$BMO_STATUS_DIR"

sudo chown -R "$APP_USER:$APP_USER" "$SHARED_FOLDER"
sudo chmod -R 775 "$SHARED_FOLDER"

sudo chown -R admin:admin /home/admin/DT5 || true
sudo chmod -R u+rwX,g+rwX,o+rX /home/admin/DT5 || true

sudo chown -R Davey:Davey /home/Davey/BMO || true
sudo chmod -R 775 /home/Davey/BMO || true

sudo tee "$BMO_USB_STATUS_FILE" > /dev/null <<EOF
{
  "connected": false,
  "event": "initialised",
  "timestamp": "$(date -Iseconds)"
}
EOF

sudo chown "$APP_USER:$APP_USER" "$BMO_USB_STATUS_FILE"
sudo chmod 664 "$BMO_USB_STATUS_FILE"

cd "$APP_DIR"

if [ -f "package-lock.json" ]; then
  npm ci
else
  npm install
fi

npm install mqtt ssh2-sftp-client

npm run build

sudo tee "/etc/systemd/system/$SERVICE_NAME" > /dev/null <<EOF
[Unit]
Description=DataPort Local Web Application
After=network-online.target mosquitto.service
Wants=network-online.target mosquitto.service

[Service]
Type=simple
WorkingDirectory=$APP_DIR
ExecStart=/usr/bin/npm start
Restart=always
RestartSec=5
User=$APP_USER

Environment=NODE_ENV=production
Environment=PORT=$PORT
Environment=SHARED_FOLDER=$SHARED_FOLDER
Environment=BMO_MIRROR_FOLDER=$BMO_MIRROR_FOLDER
Environment=BMO_SFTP_FOLDER=$BMO_SFTP_FOLDER
Environment=JWT_SECRET=dataport-local-change-this
Environment=COOKIE_SECURE=false

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable mosquitto
sudo systemctl restart mosquitto
sudo systemctl enable "$SERVICE_NAME"
sudo systemctl restart "$SERVICE_NAME"

if [ "$ENABLE_SSL" = "true" ]; then
  ARCH="$(uname -m)"

  if [ "$ARCH" = "aarch64" ]; then
    MKCERT_URL="https://github.com/FiloSottile/mkcert/releases/download/v1.4.4/mkcert-v1.4.4-linux-arm64"
  elif [ "$ARCH" = "armv7l" ] || [ "$ARCH" = "armv6l" ]; then
    MKCERT_URL="https://github.com/FiloSottile/mkcert/releases/download/v1.4.4/mkcert-v1.4.4-linux-arm"
  else
    MKCERT_URL="https://github.com/FiloSottile/mkcert/releases/download/v1.4.4/mkcert-v1.4.4-linux-amd64"
  fi

  if ! command -v mkcert >/dev/null 2>&1; then
    curl -L "$MKCERT_URL" -o /tmp/mkcert
    chmod +x /tmp/mkcert
    sudo mv /tmp/mkcert /usr/local/bin/mkcert
  fi

  mkcert -install

  sudo mkdir -p "$SSL_DIR"
  TMP_CERT_DIR="$(mktemp -d)"

  mkcert \
    -cert-file "$TMP_CERT_DIR/dataport.crt" \
    -key-file "$TMP_CERT_DIR/dataport.key" \
    "$PI_STATIC_IP" \
    localhost \
    127.0.0.1 \
    dt5pi.local \
    dataport.local

  sudo cp "$TMP_CERT_DIR/dataport.crt" "$SERVER_CERT"
  sudo cp "$TMP_CERT_DIR/dataport.key" "$SERVER_KEY"

  sudo chmod 644 "$SERVER_CERT"
  sudo chmod 600 "$SERVER_KEY"

  CA_ROOT="$(mkcert -CAROOT)"
  sudo cp "$CA_ROOT/rootCA.pem" "$APP_DIR/dist/dataport-ca.crt"
  sudo chmod 644 "$APP_DIR/dist/dataport-ca.crt"

  sudo tee /etc/nginx/sites-available/dataport > /dev/null <<EOF
server {
    listen 80;
    server_name $PI_STATIC_IP dt5pi.local dataport.local;

    location /dataport-ca.crt {
        alias $APP_DIR/dist/dataport-ca.crt;
        default_type application/x-x509-ca-cert;
        add_header Content-Disposition "attachment; filename=dataport-ca.crt";
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name $PI_STATIC_IP dt5pi.local dataport.local;

    ssl_certificate $SERVER_CERT;
    ssl_certificate_key $SERVER_KEY;

    client_max_body_size 500M;

    location /dataport-ca.crt {
        alias $APP_DIR/dist/dataport-ca.crt;
        default_type application/x-x509-ca-cert;
        add_header Content-Disposition "attachment; filename=dataport-ca.crt";
    }

    location / {
        proxy_pass http://127.0.0.1:$NODE_PORT;
        proxy_http_version 1.1;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
        send_timeout 300s;
    }
}
EOF

  sudo rm -f /etc/nginx/sites-enabled/default
  sudo ln -sf /etc/nginx/sites-available/dataport /etc/nginx/sites-enabled/dataport

  sudo nginx -t
  sudo systemctl enable nginx
  sudo systemctl restart nginx
fi

echo "========================================================="
echo "DataPort installation complete."
echo "Open: https://$PI_STATIC_IP or https://dataport.local"
echo "========================================================="
'@

Write-Host "Creating bmo-multicast.sh..."
Write-LinuxFile "$PackageRoot\usr\local\bin\bmo-multicast.sh" @'
#!/bin/bash
set -u

INTERFACE="usb1"
MULTICAST_IP="239.255.43.21"
MULTICAST_PORT="1901"
MQTT_PORT="1883"
SFTP_PORT="2222"
SFTP_USER="Davey"
SFTP_HOME="/home/Davey"

DATAPORT_USER="admin"
DATAPORT_MIRROR_ROOT="/home/admin/DT5/BMO"

LOG_PREFIX="[BMO AutoConnect]"

RUN_DIR="/run/bmo"
DEVICE_ID_FILE="$RUN_DIR/device-id"
PI_IP_FILE="$RUN_DIR/pi-ip"
BMO_IP_FILE="$RUN_DIR/bmo-ip"

mkdir -p "$RUN_DIR"

log() {
  echo "$LOG_PREFIX $*"
}

ensure_sftp_base() {
  local device_id="$1"

  mkdir -p "$SFTP_HOME/BMO/$device_id/BREX"
  mkdir -p "$SFTP_HOME/BMO/$device_id/HISTO"
  mkdir -p "$SFTP_HOME/BMO/$device_id/LOG"

  mkdir -p "$DATAPORT_MIRROR_ROOT/$device_id/BREX"
  mkdir -p "$DATAPORT_MIRROR_ROOT/$device_id/HISTO"
  mkdir -p "$DATAPORT_MIRROR_ROOT/$device_id/LOG"

  chown -R "$SFTP_USER:$SFTP_USER" "$SFTP_HOME/BMO"
  chmod -R 775 "$SFTP_HOME/BMO"

  chown -R "$DATAPORT_USER:$DATAPORT_USER" "$DATAPORT_MIRROR_ROOT"
  chmod -R u+rwX,g+rwX,o+rX "$DATAPORT_MIRROR_ROOT"
}

ensure_ssh_key() {
  local public_key="$1"

  [ -z "$public_key" ] && return 0

  mkdir -p "$SFTP_HOME/.ssh"
  touch "$SFTP_HOME/.ssh/authorized_keys"

  if ! grep -qxF "$public_key" "$SFTP_HOME/.ssh/authorized_keys"; then
    echo "$public_key" >> "$SFTP_HOME/.ssh/authorized_keys"
    log "Added BMO public key"
  else
    log "BMO public key already registered"
  fi

  chown -R "$SFTP_USER:$SFTP_USER" "$SFTP_HOME/.ssh"
  chmod 700 "$SFTP_HOME/.ssh"
  chmod 600 "$SFTP_HOME/.ssh/authorized_keys"
}

sync_bmo_files_to_dataport() {
  local device_id="$1"

  [ -z "$device_id" ] && return 0
  [ ! -d "$SFTP_HOME/BMO/$device_id" ] && return 0

  mkdir -p "$DATAPORT_MIRROR_ROOT/$device_id/BREX"
  mkdir -p "$DATAPORT_MIRROR_ROOT/$device_id/HISTO"
  mkdir -p "$DATAPORT_MIRROR_ROOT/$device_id/LOG"

  rsync -a "$SFTP_HOME/BMO/$device_id/BREX/" "$DATAPORT_MIRROR_ROOT/$device_id/BREX/" 2>/dev/null || true
  rsync -a "$SFTP_HOME/BMO/$device_id/HISTO/" "$DATAPORT_MIRROR_ROOT/$device_id/HISTO/" 2>/dev/null || true
  rsync -a "$SFTP_HOME/BMO/$device_id/LOG/" "$DATAPORT_MIRROR_ROOT/$device_id/LOG/" 2>/dev/null || true

  chown -R "$DATAPORT_USER:$DATAPORT_USER" "$DATAPORT_MIRROR_ROOT/$device_id"
  chmod -R u+rwX,g+rwX,o+rX "$DATAPORT_MIRROR_ROOT/$device_id"
}

sync_loop() {
  while true; do
    if [ -f "$DEVICE_ID_FILE" ]; then
      device_id="$(cat "$DEVICE_ID_FILE" 2>/dev/null || true)"

      if [ -n "$device_id" ]; then
        sync_bmo_files_to_dataport "$device_id"
      fi
    fi

    sleep 2
  done
}

clear_retained_topic() {
  local topic="$1"
  mosquitto_pub -h localhost -r -n -t "$topic" >/dev/null 2>&1 || true
}

cleanup_bmo_session() {
  local device_id=""

  if [ -f "$DEVICE_ID_FILE" ]; then
    device_id="$(cat "$DEVICE_ID_FILE" 2>/dev/null || true)"
  fi

  log "Cleaning volatile BMO session state"

  if [ -n "$device_id" ]; then
    sync_bmo_files_to_dataport "$device_id"

    clear_retained_topic "devices/${device_id}/postBlastReport"
    clear_retained_topic "devices/${device_id}/connection/status"
    clear_retained_topic "devices/register/${device_id}"
  fi

  clear_retained_topic "DSS/plugins/EQPT"
  clear_retained_topic "DSS/Plugin/EQPT"

  rm -f "$DEVICE_ID_FILE"
  rm -f "$PI_IP_FILE"
  rm -f "$BMO_IP_FILE"
}

handle_registration_loop() {
  mosquitto_sub -h localhost -t 'devices/register/+' -F '%t|%p' | while IFS='|' read -r topic payload; do
    device_id="${topic##*/}"

    public_key="$(echo "$payload" | jq -r '.publicKey // empty' 2>/dev/null || true)"

    ensure_sftp_base "$device_id"
    ensure_ssh_key "$public_key"

    echo "$device_id" > "$DEVICE_ID_FILE"

    sync_bmo_files_to_dataport "$device_id"

    log "Prepared folders for device $device_id"
  done
}

publish_plugin_loop() {
  while true; do
    mosquitto_pub -h localhost -r \
      -t 'DSS/plugins/EQPT' \
      -m '{"lang":"en","nameId":"blastReport"}' >/dev/null 2>&1 || true

    mosquitto_pub -h localhost -r \
      -t 'DSS/Plugin/EQPT' \
      -m '{"nameId":"blastReport"}' >/dev/null 2>&1 || true

    sleep 10
  done
}

start_background_loops() {
  handle_registration_loop &
  publish_plugin_loop &
  sync_loop &
}

start_background_loops

WAS_CONNECTED=0

while true; do
  if ! ip link show "$INTERFACE" >/dev/null 2>&1; then
    if [ "$WAS_CONNECTED" -eq 1 ]; then
      log "$INTERFACE disconnected"
      cleanup_bmo_session
      WAS_CONNECTED=0
    fi

    sleep 2
    continue
  fi

  USB_IP="$(ip -4 addr show "$INTERFACE" 2>/dev/null | grep -oP '(?<=inet\s)10\.\d+\.\d+\.\d+' | head -1 || true)"

  if [ -z "$USB_IP" ]; then
    if [ "$WAS_CONNECTED" -eq 1 ]; then
      log "$INTERFACE lost 10.x.y.z IP"
      cleanup_bmo_session
      WAS_CONNECTED=0
    fi

    sleep 2
    continue
  fi

  if [ "$WAS_CONNECTED" -eq 0 ]; then
    log "$INTERFACE connected"
    WAS_CONNECTED=1
  fi

  BMO_IP="$(echo "$USB_IP" | awk -F. '{print $1"."$2"."$3".2"}')"

  echo "$USB_IP" > "$PI_IP_FILE"
  echo "$BMO_IP" > "$BMO_IP_FILE"

  PAYLOAD="$(printf '{"MQTTBrokerPort":%s,"SFTPPort":%s,"ipAddress":["%s","192.168.165.1"],"userName":"%s"}' \
    "$MQTT_PORT" "$SFTP_PORT" "$USB_IP" "$SFTP_USER")"

  log "PI IP: $USB_IP | Expected BMO IP: $BMO_IP"
  log "Advertising DSS payload: $PAYLOAD"

  printf '%s' "$PAYLOAD" \
    | socat - UDP-DATAGRAM:${MULTICAST_IP}:${MULTICAST_PORT},ip-multicast-if=${USB_IP}

  sleep 1
done
'@

Write-Host "Creating usb1-alias.sh..."
Write-LinuxFile "$PackageRoot\usr\local\bin\usb1-alias.sh" @'
#!/bin/bash

INTERFACE="usb1"
ALIAS_IP="192.168.165.1/24"
ALIAS_CHECK="192.168.165.1"

while true; do
  if ip link show "$INTERFACE" >/dev/null 2>&1; then
    ip link set "$INTERFACE" up 2>/dev/null || true

    if ! ip -4 addr show "$INTERFACE" | grep -q "$ALIAS_CHECK"; then
      ip addr add "$ALIAS_IP" dev "$INTERFACE" 2>/dev/null || true
    fi
  fi

  sleep 2
done
'@

Write-Host "Creating bmo-multicast.service..."
Write-LinuxFile "$PackageRoot\etc\systemd\system\bmo-multicast.service" @'
[Unit]
Description=BMO Multicast Discovery and DSS Advertisement Service
After=network.target mosquitto.service ssh.service
Wants=mosquitto.service ssh.service

[Service]
Type=simple
ExecStart=/usr/local/bin/bmo-multicast.sh
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
'@

Write-Host "Creating usb1-alias.service..."
Write-LinuxFile "$PackageRoot\etc\systemd\system\usb1-alias.service" @'
[Unit]
Description=USB1 Alias IP Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/usb1-alias.sh
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
'@

Write-Host "Creating postinst..."
Write-LinuxFile "$PackageRoot\DEBIAN\postinst" @'
#!/bin/bash
set -e

echo "Installing DataPort package..."

chmod +x /opt/dataport/install.sh
chmod +x /usr/local/bin/bmo-multicast.sh
chmod +x /usr/local/bin/usb1-alias.sh

cd /opt/dataport
./install.sh

systemctl daemon-reload

systemctl enable usb1-alias.service
systemctl restart usb1-alias.service

systemctl enable bmo-multicast.service
systemctl restart bmo-multicast.service

echo "DataPort package installation complete."

exit 0
'@

Write-Host "Creating prerm..."
Write-LinuxFile "$PackageRoot\DEBIAN\prerm" @'
#!/bin/bash
set -e

systemctl stop bmo-multicast.service || true
systemctl stop usb1-alias.service || true
systemctl stop dataport.service || true

systemctl disable bmo-multicast.service || true
systemctl disable usb1-alias.service || true
systemctl disable dataport.service || true

exit 0
'@

Write-Host "Creating postrm..."
Write-LinuxFile "$PackageRoot\DEBIAN\postrm" @'
#!/bin/bash
set -e

systemctl daemon-reload || true
systemctl reset-failed || true

if [ "$1" = "purge" ]; then
  rm -rf /opt/dataport
  rm -f /usr/local/bin/bmo-multicast.sh
  rm -f /usr/local/bin/usb1-alias.sh
  rm -f /etc/systemd/system/bmo-multicast.service
  rm -f /etc/systemd/system/usb1-alias.service
fi

exit 0
'@

Write-Host "Building .deb using WSL..."

$WslSourcePackage = "/mnt/c/Dev/dataport/package/dataport"
$WslBuildRoot = "/tmp/dataport-build"
$WslDebName = $DebName
$WslOutput = "/mnt/c/Dev/dataport/$DebName"

$Commands = @(
    "rm -rf $WslBuildRoot",
    "mkdir -p $WslBuildRoot",
    "cp -a $WslSourcePackage $WslBuildRoot/",
    "cd $WslBuildRoot",

    "find dataport -type d -exec chmod 755 {} \;",
    "find dataport -type f -exec chmod 644 {} \;",

    "chmod 755 dataport/DEBIAN",
    "chmod 755 dataport/DEBIAN/postinst",
    "chmod 755 dataport/DEBIAN/prerm",
    "chmod 755 dataport/DEBIAN/postrm",
    "chmod 755 dataport/opt/dataport/install.sh",
    "chmod 755 dataport/usr/local/bin/bmo-multicast.sh",
    "chmod 755 dataport/usr/local/bin/usb1-alias.sh",

    "dpkg-deb --build dataport $WslDebName",
    "cp $WslDebName $WslOutput"
)

$WslCommand = ($Commands -join " && ")

wsl bash -lc "$WslCommand"

if ($LASTEXITCODE -ne 0) {
    throw "Debian package build failed."
}

Write-Host "====================================================="
Write-Host "Package created:"
Write-Host "$ReleaseRoot\$DebName"
Write-Host "====================================================="