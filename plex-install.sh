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

# Function to determine OS and architecture
get_system_info() {
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            ARCH="amd64"
            ;;
        aarch64)
            ARCH="arm64"
            ;;
        armv7l)
            ARCH="arm"
            ;;
    esac
    echo "${OS}-${ARCH}"
}

SYSTEM_INFO=$(get_system_info)
echo "System Info: $SYSTEM_INFO"

# Repository details
PRIVATE_OWNER="debridmediamanager"
PRIVATE_REPO="zurg"
PUBLIC_OWNER="debridmediamanager"
PUBLIC_REPO="zurg-testing"

# Global variable for Real-Debrid API token
RD_TOKEN=""

# Function to get Real-Debrid API token
get_rd_token() {
    if [ -z "$RD_TOKEN" ]; then
        read -p "Enter your Real-Debrid API token: " RD_TOKEN
    fi
}

# Function to create config.yml for Zurg
create_zurg_config_file() {
    get_rd_token

    mkdir -p /etc/zurg
    cat > /etc/zurg/config.yml << EOL
# Zurg configuration version
zurg: v1
token: ${RD_TOKEN} # https://real-debrid.com/apitoken
api_rate_limit_per_minute: 60
torrents_rate_limit_per_minute: 25
concurrent_workers: 32
check_for_changes_every_secs: 10
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
    echo "Config file created at /etc/zurg/config.yml with your API token."
}

# Function to install Zurg
install_zurg() {
    echo "Zurg Installation"
    echo "Do you want to install from the private repository? (Y/N)"
    read -r repo_choice

    if [[ "$repo_choice" =~ ^[Yy]$ ]]; then
        echo "Installing from private repository"
        read -p "Enter your GitHub token: " GITHUB_TOKEN
        
        # Authenticate with GitHub
        echo "Authenticating with GitHub..."
        gh auth login --with-token <<< "$GITHUB_TOKEN"
        if [ $? -ne 0 ]; then
            echo "GitHub authentication failed. Please check your token and try again."
            return 1
        fi
        echo "GitHub authentication successful."

        # List available releases without pager
        echo "Available Zurg releases:"
        gh release list -R ${PRIVATE_OWNER}/${PRIVATE_REPO} --limit 10 | cat

        # Prompt user to select a release
        read -p "Enter the tag of the release you want to download (or press Enter for latest): " RELEASE_TAG

        # Download the release
        if [ -z "$RELEASE_TAG" ]; then
            echo "Downloading latest release..."
            gh release download -R ${PRIVATE_OWNER}/${PRIVATE_REPO} -p "*${SYSTEM_INFO}*" --clobber
        else
            echo "Downloading release ${RELEASE_TAG}..."
            gh release download -R ${PRIVATE_OWNER}/${PRIVATE_REPO} ${RELEASE_TAG} -p "*${SYSTEM_INFO}*" --clobber
        fi

        # Find the downloaded file
        DOWNLOADED_FILE=$(ls -t zurg-* 2>/dev/null | head -n1)
    else
        echo "Installing from public repository"
        DOWNLOAD_URL="https://github.com/debridmediamanager/zurg-testing/releases/download/v0.9.3-final/zurg-v0.9.3-final-linux-amd64.zip"
        DOWNLOADED_FILE="zurg-v0.9.3-final-linux-amd64.zip"

        echo "Downloading Zurg from public repository..."
        wget $DOWNLOAD_URL -O $DOWNLOADED_FILE
    fi

    if [ -z "$DOWNLOADED_FILE" ]; then
        echo "No matching asset found for your system ($SYSTEM_INFO)"
        return 1
    fi

    echo "Asset downloaded successfully: $DOWNLOADED_FILE"

    # Extract if it's a zip file
    if [[ "$DOWNLOADED_FILE" == *.zip ]]; then
        echo "Extracting zip file..."
        unzip -o "$DOWNLOADED_FILE"
        rm "$DOWNLOADED_FILE"
        BINARY_FILE=$(ls zurg* 2>/dev/null | grep -v '\.zip$' | head -n1)
    else
        BINARY_FILE="$DOWNLOADED_FILE"
    fi

    if [ -z "$BINARY_FILE" ]; then
        echo "Unable to find the Zurg binary file."
        return 1
    fi

    # Make the binary executable
    chmod +x "$BINARY_FILE"

    # Move the binary to a directory in PATH
    mv "$BINARY_FILE" /usr/local/bin/zurg

    echo "Zurg has been installed. You can now run it by typing 'zurg' in the terminal."

    # Create and start systemd service
    create_zurg_config_file
    create_and_start_systemd_service
}

# Function to create and start systemd service for Zurg
create_and_start_systemd_service() {
    # Create systemd service file
    cat << EOF | tee /etc/systemd/system/zurg.service > /dev/null
[Unit]
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
EOF

    # Reload systemd to recognize the new service
    systemctl daemon-reload

    # Enable the service to start on boot
    systemctl enable zurg.service

    # Start the service
    systemctl start zurg.service

    echo "Zurg systemd service has been created and started."
}

# Function to check if Zurg is available
check_zurg_availability() {
    local max_attempts=30
    local attempt=1
    local delay=30

    while [ $attempt -le $max_attempts ]; do
        if curl -s "http://localhost:9999/http/__all__" | grep -q ""; then
            echo "Zurg is available."
            return 0
        fi
        echo "Attempt $attempt: Zurg is not yet available. Waiting $delay seconds..."
        sleep $delay
        attempt=$((attempt + 1))
    done

    echo "Zurg is not available after $max_attempts attempts. Exiting."
    return 1
}

install_zurg

# Check Zurg availability before installing rclone
if check_zurg_availability; then
    install_rclone
else
    echo "Skipping rclone installation due to Zurg unavailability."
fi

install_rclone() {
    echo "Installing Rclone"
    RCLONE_LATEST_VERSION=$(curl -s https://api.github.com/repos/rclone/rclone/releases/latest | grep 'tag_name' | cut -d '"' -f4)

    curl -O https://downloads.rclone.org/rclone-current-linux-amd64.zip
    unzip rclone-current-linux-amd64.zip
    cd rclone-*-linux-amd64
    cp rclone /usr/local/bin/
    chown root:root /usr/local/bin/rclone
    chmod 755 /usr/local/bin/rclone

    echo "Installed rclone $RCLONE_LATEST_VERSION"

    echo "Configuring rclone"
    mkdir -p /etc/rclone
    cat << EOF > /etc/rclone/rclone.conf
[zurg]
type = webdav
url = http://localhost:9999/dav
vendor = other
pacer_min_sleep = 0
EOF

    mkdir -p /root/.config/rclone
    ln -sf /etc/rclone/rclone.conf /root/.config/rclone/rclone.conf

    echo "Configured rclone"

    # Setup fuse3
    echo "Setting up fuse3"
    if [ -f /etc/fuse.conf ]; then
        sed -i 's/#user_allow_other/user_allow_other/' /etc/fuse.conf
    else
        echo "user_allow_other" > /etc/fuse.conf
    fi
    echo "Configured fuse3"

    # Ensure FUSE module is loaded
    #modprobe fuse
    echo "fuse" >> /etc/modules-load.d/modules.conf

    read -p "Enter the mount point path (e.g., /mnt/zurg): " MOUNT_POINT
    mkdir -p "$MOUNT_POINT"
    # Create systemd service for rcloned
    echo "Creating systemd service for rclone..."
    cat > /etc/systemd/system/rclone.service <<EOL
[Unit]
Description=rclone
After=network.target zurg.service
Wants=network-online.target
Requires=zurg.service

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/rclone mount zurg: ${MOUNT_POINT} \\
    --allow-other \\
    --dir-cache-time 96h \\
    --vfs-cache-mode writes \\
    --vfs-cache-max-size 100G \\
    --vfs-read-chunk-size 128M \\
    --vfs-read-chunk-size-limit off \\
    --buffer-size 256M \\
    --log-level INFO \\
    --log-file /var/log/rclone.log \\
    --no-modtime \\
    --no-checksum
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

    echo "Rclone systemd service created and started"
}

install_zurg
install_rclone

msg_ok "Installed Plex Media Server"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"