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
$STD apt-get install -y curl sudo mc wget unzip git gh jq fuse3
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

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"

# Add prompt for Zurg and Rclone installation
read -r -p "Would you like to add Zurg and Rclone? <y/N> " prompt
if [[ ${prompt,,} =~ ^(y|yes)$ ]]; then
    msg_info "Installing Zurg and Rclone"
    echo
    
    # Zurg Installation
    install_zurg() {
        msg_info "Zurg Installation"
        echo
        read -r -p "Do you want to install from the private repository? <y/N> " use_private_repo
        if [[ ${use_private_repo,,} =~ ^(y|yes)$ ]]; then
            msg_info "Installing from private repository"
            echo
            read -p "Enter your GitHub token: " GITHUB_TOKEN
            echo
            
            # Authenticate with GitHub
            msg_info "Authenticating with GitHub..."
            gh auth login --with-token <<< "$GITHUB_TOKEN"
            if [ $? -ne 0 ]; then
                msg_error "GitHub authentication failed. Please check your token and try again."
                exit 1
            fi
            msg_ok "GitHub authentication successful."
            echo

            # List available releases without pager
            msg_info "Available Zurg releases:"
            gh release list -R debridmediamanager/zurg --limit 10 | cat
            echo

            # Prompt user to select a release
            read -p "Enter the tag of the release you want to download (or press Enter for latest): " RELEASE_TAG
            echo

            # Download the release
            if [ -z "$RELEASE_TAG" ]; then
                msg_info "Downloading latest release..."
                gh release download -R debridmediamanager/zurg -p "*linux-amd64*" --clobber
            else
                msg_info "Downloading release ${RELEASE_TAG}..."
                gh release download -R debridmediamanager/zurg ${RELEASE_TAG} -p "*linux-amd64*" --clobber
            fi
        else
            msg_info "Installing from public repository"
            DOWNLOAD_URL="https://github.com/debridmediamanager/zurg-testing/releases/download/v0.9.3-final/zurg-v0.9.3-final-linux-amd64.zip"
            FILENAME="zurg-v0.9.3-final-linux-amd64.zip"

            msg_info "Downloading Zurg from public repository..."
            wget $DOWNLOAD_URL -O $FILENAME

            if [ ! -f "$FILENAME" ]; then
                msg_error "Failed to download the file. Please check your internet connection and try again."
                exit 1
            fi

            msg_ok "File downloaded successfully: $FILENAME"

            # Extract the zip file
            unzip -o "$FILENAME"
            rm "$FILENAME"
        fi

        # Find the downloaded file
        BINARY_FILE=$(ls zurg* 2>/dev/null | grep -v '\.zip$' | head -n1)

        if [ -z "$BINARY_FILE" ]; then
            msg_error "Unable to find the Zurg binary file."
            exit 1
        fi

        # Make the binary executable
        chmod +x "$BINARY_FILE"

        # Move the binary to a directory in PATH
        mv "$BINARY_FILE" /usr/local/bin/zurg

        msg_ok "Zurg has been installed. You can now run it by typing 'zurg' in the terminal."
    }

    install_zurg

    # Zurg Configuration
    configure_zurg() {
        msg_info "Creating Zurg Config"
        mkdir -p /etc/zurg
        read -p "Enter your Real-Debrid API token: " RD_TOKEN

        cat > /etc/zurg/config.yml << EOL
# Zurg configuration version
zurg: v1
token: ${RD_TOKEN} # https://real-debrid.com/apitoken
# host: "[::]"
# port: 9999
# username:
# password:
# proxy:
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
# api_timeout_secs: 15
# download_timeout_secs: 10
# enable_download_mount: false
# rate_limit_sleep_secs: 6
# retries_until_failed: 2
# network_buffer_size: 4194304 # 4MB
# serve_from_rclone: false
# verify_download_link: false
# force_ipv6: false
directories:
  torrents:
    group: 1
    filters:
      - regex: /.*/
EOL

        msg_ok "Created Zurg Config"
    }

    configure_zurg

    # Zurg Systemd Service
    setup_zurg_service() {
        msg_info "Setting Up Zurg Systemd Service"
        cat << EOF | tee /etc/systemd/system/zurg.service
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

        msg_ok "Zurg systemd service has been created and started."
    }

    setup_zurg_service

    # Rclone Installation and Configuration
    install_configure_rclone() {
        msg_info "Installing rclone"
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
    }

    install_configure_rclone

    # Setup fuse3
    setup_fuse3() {
        msg_info "Setting up fuse3"
        if [ -f /etc/fuse.conf ]; then
            sed -i 's/#user_allow_other/user_allow_other/' /etc/fuse.conf
        else
            echo "user_allow_other" > /etc/fuse.conf
        fi
        msg_ok "Set up fuse3"
    }

    setup_fuse3

    # Create mount point and service
    create_mount_service() {
        msg_info "Creating mount point and service"
        read -p "Enter the mount point path (e.g., /mnt/zurg): " MOUNT_POINT
        mkdir -p "$MOUNT_POINT"

        cat << EOF > /etc/systemd/system/rclone-zurg.service
[Unit]
Description=RClone Mount for Zurg
After=network-online.target

[Service]
Type=notify
ExecStart=/usr/local/bin/rclone mount zurg: ${MOUNT_POINT} \
   --config /etc/rclone/rclone.conf \
   --allow-other \
   --dir-cache-time 1000h \
   --vfs-read-chunk-size 128M \
   --vfs-cache-mode writes
ExecStop=/bin/fusermount -u ${MOUNT_POINT}
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

        systemctl daemon-reload
        systemctl enable rclone-zurg.service
        systemctl start rclone-zurg.service

        msg_ok "Created mount point and service"
    }

    create_mount_service
    
    msg_ok "Installed Zurg and Rclone"

    # Add prompt for Docker installation
    read -p "Would you like to install Docker? (Y/n): " install_docker
    install_docker=${install_docker:-Y}
    if [[ $install_docker =~ ^[Yy]$ ]]; then
        msg_info "Installing Docker"
        
        # Download and execute the Docker installation script
        curl -sSL https://raw.githubusercontent.com/machetie/plexlxcrclonezurg/main/Docker-install.sh -o docker_install.sh
        chmod +x docker_install.sh
        ./docker_install.sh
        rm docker_install.sh
        
        msg_ok "Installed Docker"
    fi
fi

msg_ok "Plex Media Server installation completed successfully!"
echo -e "Plex should be reachable at http://${IP}:32400/web"