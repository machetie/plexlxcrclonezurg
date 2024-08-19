#!/usr/bin/env bash

# Copyright (c) 2021-2024 tteck
# Author: tteck (tteckster)
# License: MIT
# https://github.com/tteck/Proxmox/raw/main/LICENSE

source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y curl
$STD apt-get install -y sudo
$STD apt-get install -y mc
$STD apt-get install -y wget
$STD apt-get install -y unzip
$STD apt-get install -y git
$STD apt-get install -y gh
$STD apt-get install -y jq
$STD apt-get install -y fuse3
msg_ok "Installed Dependencies"

msg_info "Setting Up Hardware Acceleration"
$STD apt-get -y install {va-driver-all,ocl-icd-libopencl1,intel-opencl-icd,vainfo,intel-gpu-tools}
if [[ "$CTTYPE" == "0" ]]; then
  chgrp video /dev/dri
  chmod 755 /dev/dri
  chmod 660 /dev/dri/*
  $STD adduser $(id -u -n) video
  $STD adduser $(id -u -n) render
fi
msg_ok "Set Up Hardware Acceleration"

msg_info "Setting Up Plex Media Server Repository"
wget -qO- https://downloads.plex.tv/plex-keys/PlexSign.key >/usr/share/keyrings/PlexSign.asc
echo "deb [signed-by=/usr/share/keyrings/PlexSign.asc] https://downloads.plex.tv/repo/deb/ public main" >/etc/apt/sources.list.d/plexmediaserver.list
msg_ok "Set Up Plex Media Server Repository"

msg_info "Installing Plex Media Server"
$STD apt-get update
$STD apt-get -o Dpkg::Options::="--force-confold" install -y plexmediaserver
if [[ "$CTTYPE" == "0" ]]; then
  sed -i -e 's/^ssl-cert:x:104:plex$/render:x:104:root,plex/' -e 's/^render:x:108:root$/ssl-cert:x:108:plex/' /etc/group
else
  sed -i -e 's/^ssl-cert:x:104:plex$/render:x:104:plex/' -e 's/^render:x:108:$/ssl-cert:x:108:/' /etc/group
fi
msg_ok "Installed Plex Media Server"

read -r -p "Do you want to install Zurg from private repo? [y/N] " response
if [[ "${response,,}" =~ ^(y|yes)$ ]]; then
  msg_info "Installing Zurg from private repository"
  
# Prompt for GitHub token with white text
  echo -e "\e[1;37mEnter your GitHub token:\e[0m"
  read -r GITHUB_TOKEN
  
  # Authenticate with GitHub
  msg_info "Authenticating with GitHub..."
  if ! gh auth login --with-token <<< "$GITHUB_TOKEN"; then
    msg_error "GitHub authentication failed. Please check your token and try again."
    exit 1
  fi
  msg_ok "GitHub authentication successful."

  # List available releases
  msg_info "Available Zurg releases:"
  gh release list -R debridmediamanager/zurg --limit 10

  # Prompt user to select a release
  read -p "Enter the tag of the release you want to download (or press Enter for latest): " RELEASE_TAG

  # Download the release
  if [ -z "$RELEASE_TAG" ]; then
    msg_info "Downloading latest release..."
    gh release download -R debridmediamanager/zurg -p "*${SYSTEM_INFO}*" --clobber
  else
    msg_info "Downloading release ${RELEASE_TAG}..."
    gh release download -R debridmediamanager/zurg ${RELEASE_TAG} -p "*${SYSTEM_INFO}*" --clobber
  fi

  # Find the downloaded file
  BINARY_FILE=$(ls zurg* 2>/dev/null | grep -v '\.zip$' | head -n1)
else
  msg_info "Installing Zurg from public repository"
  DOWNLOAD_URL="https://github.com/debridmediamanager/zurg-testing/releases/download/v0.9.3-final/zurg-v0.9.3-final-linux-amd64.zip"
  FILENAME="zurg-v0.9.3-final-linux-amd64.zip"

  msg_info "Downloading Zurg..."
  if wget "$DOWNLOAD_URL" -O "$FILENAME"; then
    msg_ok "Downloaded Zurg successfully"
    
    msg_info "Extracting Zurg..."
    if unzip -o "$FILENAME"; then
      msg_ok "Extracted Zurg successfully"
      
      BINARY_FILE=$(ls zurg* 2>/dev/null | grep -v '\.zip$' | head -n1)
    else
      msg_error "Failed to extract Zurg. Installation unsuccessful."
    fi
    
    rm "$FILENAME"
  else
    msg_error "Failed to download Zurg. Installation unsuccessful."
  fi
fi
if [ -n "$BINARY_FILE" ]; then

  chmod +x "$BINARY_FILE"
  mv "$BINARY_FILE" /usr/local/bin/zurg
  msg_ok "Zurg installed successfully"
else
  msg_error "Failed to find Zurg binary. Installation unsuccessful."
fi

# Prompt user for adding default config and systemd service
read -p "Would you like to add default config for zurg and add to systemd service? (y/n): " ADD_CONFIG_AND_SERVICE
if [[ "$ADD_CONFIG_AND_SERVICE" =~ ^[Yy]$ ]]; then
  # Create default config
  msg_info "Creating default config for Zurg..."
  mkdir -p /etc/zurg
  # Prompt for Real-Debrid API token
  read -p "Enter your Real-Debrid API token: " RD_TOKEN
  cat > /etc/zurg/config.yaml <<EOL
lzurg: v1
token: ${RD_TOKEN} # https://real-debrid.com/apitoken
api_rate_limit_per_minute: 60
torrents_rate_limit_per_minute: 25
concurrent_workers: 32
check_for_changes_every_secs: 10
# repair_every_mins: 60
ignore_renames: true
retain_rd_torrent_name: true
retain_folder_name_extension: true
enable_repair: false
auto_delete_rar_torrents: false
get_torrents_count: 5000
directories:
  torrents:
    group: 1
    filters:
      - regex: /.*/
EOL
  msg_ok "Default config created at /etc/zurg/config.yaml"

  # Create systemd service
  msg_info "Creating systemd service for Zurg..."
  cat > /etc/systemd/system/zurg.service <<EOL
[[Unit]
Description=zurg
After=network.target
Wants=network-online.target
[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/zurg
WorkingDirectory=/etc/zurg
StandardOutput=file:/var/log/zurg.log
StandardError=file:/var/log/zurg.log
Restart=on-abort
RestartSec=10
StartLimitInterval=45
StartLimitBurst=5
[Install]
WantedBy=multi-user.target
EOL

  # Reload systemd and enable the service
  systemctl daemon-reload
  systemctl enable zurg.service
  systemctl start zurg.service

  msg_ok "Zurg systemd service created and started"
else
  msg_info "Skipping default config and systemd service setup"
fi

msg_info "Installing Rclone"
RCLONE_LATEST_VERSION=$(curl -s https://api.github.com/repos/rclone/rclone/releases/latest | grep 'tag_name' | cut -d '"' -f4)

$STD curl -O https://downloads.rclone.org/rclone-current-linux-amd64.zip
$STD unzip rclone-current-linux-amd64.zip
$STD cd rclone-*-linux-amd64
$STD cp rclone /usr/local/bin/
$STD chown root:root /usr/local/bin/rclone
$STD chmod 755 /usr/local/bin/rclone

msg_ok "Installed rclone $RCLONE_LATEST_VERSION"

msg_info "Configuring rclone"
mkdir -p /etc/rclone
cat << EOF > /etc/rclone/rclone.conf
[zurg]
type = webdav
url = http://zurg:9999/dav
vendor = other
pacer_min_sleep = 0
EOF

mkdir -p /root/.config/rclone
ln -sf /etc/rclone/rclone.conf /root/.config/rclone/rclone.conf

msg_ok "Configured rclone"

# Setup fuse3
msg_info "Setting up fuse3"
if [ -f /etc/fuse.conf ]; then
    sed -i 's/#user_allow_other/user_allow_other/' /etc/fuse.conf
else
    echo "user_allow_other" > /etc/fuse.conf
fi
msg_ok "Configured fuse3"

read -p "Enter the mount point path (e.g., /mnt/zurg): " MOUNT_POINT
mkdir -p "$MOUNT_POINT"
# Create systemd service for rcloned
msg_info "Creating systemd service for rclone..."
cat > /etc/systemd/system/rclone.service <<EOL
[Unit]
Description=rclone
After=network.target zurg.service
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/rclone mount zurg: ${MOUNT_POINT} \
    --allow-other \
    --dir-cache-time 96h \
    --vfs-cache-mode writes \
    --vfs-cache-max-size 100G \
    --vfs-read-chunk-size 128M \
    --vfs-read-chunk-size-limit off \
    --buffer-size 256M \
    --log-level INFO \
    --log-file /var/log/rclone.log
ExecStop=/bin/fusermount -uz ${MOUNT_POINT}
Restart=on-abort
RestartSec=5
StartLimitInterval=60s
StartLimitBurst=3

[Install]
WantedBy=multi-user.target
EOL

# Reload systemd and enable the service
systemctl daemon-reload
systemctl enable rclone.service
systemctl start rclone.service

msg_ok "Rclone systemd service created and started"


motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"

msg_ok "Plex Media Server installation completed successfully!"
echo -e "Plex should be reachable at http://${IP}:32400/web"