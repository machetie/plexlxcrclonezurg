#!/bin/bash

# Remove or comment out these lines as they are not defined
# source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
# color
# verb_ip6
# catch_errors
# setting_up_container
# network_check
# update_os

msg_info() {
    echo -e "\e[1;32m[INFO]\e[0m $1"
}
msg_ok() {
    echo -e "\e[1;32m[OK]\e[0m $1"
}
msg_error() {
    echo -e "\e[1;31m[ERROR]\e[0m $1"
}

ORIGIN_REPO="https://downloads.rclone.org/rclone-current-linux-amd64.zip"
INSTALL_DIR="/usr/local/bin"
CONFIGFILE="/etc/rclone.conf" # default options
AUTOINSTALL=yes

# Function to install required packages
install() {
    msg_info "'$1' is required but not installed, attempting to install..."
    sleep 1
    [ -z "$DISTRO_INSTALL" ] && check_distro
    $DISTRO_INSTALL $1 || msg_error "Failed while trying to install '$1'. Please install it manually and try again."
}

# Function to detect the Linux distribution
check_distro() {
    if [ -f /etc/redhat-release ] && hash dnf 2>/dev/null; then
        DISTRO="redhat"
        DISTRO_INSTALL="dnf -y install"
    elif [ -f /etc/redhat-release ] && hash yum 2>/dev/null; then
        DISTRO="redhat"
        DISTRO_INSTALL="yum -y install"
    elif hash apt 2>/dev/null; then
        DISTRO="debian"
        DISTRO_INSTALL="apt install"
    elif hash apt-get 2>/dev/null; then
        DISTRO="debian"
        DISTRO_INSTALL="apt-get install"
    else
        DISTRO="unknown"
    fi
}

# Function to prompt for yes/no
yesno() {
    case "$1" in
        "") default="Y" ;;
        yes|true) default="Y" ;;
        no|false) default="N" ;;
        *) default="$1" ;;
    esac
    default="$(tr "[:lower:]" "[:upper:]" <<< "$default")"
    if [ "$default" == "Y" ]; then
        prompt="[Y/n] "
    else
        prompt="[N/y] "
    fi
    while true; do
        read -n 1 -p "$prompt" answer
        answer=${answer:-$default}
        answer="$(tr "[:lower:]" "[:upper:]" <<< "$answer")"
        if [ "$answer" == "Y" ]; then
            echo
            return 0
        elif [ "$answer" == "N" ]; then
            echo
            return 1
        fi
    done
}

# Function to abort the script execution
abort() {
    msg_error "$@"
    exit 1
}

# Function to install rclone
install_rclone() {
    msg_info "Installing rclone into '$INSTALL_DIR'..."
    # Download and extract rclone
    temp_dir=$(mktemp -d)
    cd "$temp_dir"
    wget "$ORIGIN_REPO" -O rclone.zip || abort "Failed to download rclone."
    unzip rclone.zip || abort "Failed to unzip rclone."
    # Move rclone binary to /usr/local/bin
    cd rclone-*-linux-amd64
    cp rclone "$INSTALL_DIR" || abort "Failed to copy rclone to $INSTALL_DIR."
    chown root:root "$INSTALL_DIR/rclone"
    chmod 755 "$INSTALL_DIR/rclone"
    msg_ok "rclone installed successfully in '$INSTALL_DIR'."
    # Clean up
    cd ~
    rm -rf "$temp_dir"
}

## Function to configure rclone
configure_rclone() {
    msg_info "Configuring rclone..."
    if [ ! -f "$CONFIGFILE" ]; then
        msg_info "Creating default rclone config..."
        cat << EOF > "$CONFIGFILE"
[zurg]
type = webdav
url = http://zurg:9999/dav
vendor = other
pacer_min_sleep = 0
EOF
        msg_ok "Default rclone config created at '$CONFIGFILE'."
    fi

    # Create a symbolic link to the default config location
    mkdir -p /root/.config/rclone
    ln -sf "$CONFIGFILE" /root/.config/rclone/rclone.conf

    rclone config --config "$CONFIGFILE" || abort "Failed to configure rclone."
    msg_ok "Configuration complete."
}


# Function to install fuse3 and modify fuse.conf
install_fuse3() {
    if ! dpkg -s fuse3 >/dev/null 2>&1; then
        install fuse3
    fi
    if [ -f /etc/fuse.conf ]; then
        sed -i 's/#user_allow_other/user_allow_other/' /etc/fuse.conf || abort "Failed to modify /etc/fuse.conf"
        msg_info "/etc/fuse.conf has been updated."
    else
        echo "user_allow_other" > /etc/fuse.conf
        msg_info "/etc/fuse.conf created and updated."
    fi
}

# Function to create a mount point and systemd service
create_mount_and_service() {
    echo
    read -p "Enter the mount point path (e.g., /mnt/zurg): " MOUNT_POINT
    if [ -z "$MOUNT_POINT" ]; then
        abort "Mount point cannot be empty."
    fi

    if [ -d "$MOUNT_POINT" ]; then
        msg_info "Mount point '$MOUNT_POINT' already exists."
    else
        mkdir -p "$MOUNT_POINT" || abort "Failed to create mount point '$MOUNT_POINT'."
        msg_ok "Mount point '$MOUNT_POINT' created successfully."
    fi

    msg_info "Would you like to create a systemd service for this mount?"
    if yesno; then
        create_systemd_service "$MOUNT_POINT"
    else
        msg_info "Systemd service creation skipped."
    fi
}

# Placeholder function to create a systemd service
create_systemd_service() {
    MOUNT_POINT=$1
    SERVICE_NAME=$(basename "$MOUNT_POINT")
    
    # Example service configuration (to be updated with default settings)
    tee /etc/systemd/system/rclone-${SERVICE_NAME}.service > /dev/null << EOF
[Unit]
Description=RClone Mount for ${SERVICE_NAME}
After=network-online.target

[Service]
Type=notify
ExecStart=/usr/local/bin/rclone mount zurg: ${MOUNT_POINT} \
   --config ${CONFIGFILE} \
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
    systemctl enable rclone-${SERVICE_NAME}.service || abort "Failed to enable systemd service."
    systemctl start rclone-${SERVICE_NAME}.service || abort "Failed to start systemd service."
    msg_ok "Systemd service 'rclone-${SERVICE_NAME}.service' created and started."
}

for req in wget unzip; do
    if ! hash $req 2>/dev/null; then
        install $req
    fi
done

msg_info "Installing fuse3"
install_fuse3
msg_ok "Installed fuse3"

msg_info "Installing rclone"
install_rclone
msg_ok "Installed rclone"

msg_info "Configuring rclone"
configure_rclone
msg_ok "Configured rclone"

msg_info "Creating mount point and service"
create_mount_and_service
msg_ok "Created mount point and service"

echo
msg_info "Would you like to check the rclone version now?"
if yesno; then
    rclone version || abort "Failed to verify rclone installation."
fi

msg_ok "Rclone setup completed successfully"

exit 0