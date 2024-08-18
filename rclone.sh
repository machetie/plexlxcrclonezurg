#!/bin/bash

ORIGIN_REPO="https://downloads.rclone.org/rclone-current-linux-amd64.zip"
INSTALL_DIR="/usr/local/bin"
CONFIGFILE="/etc/rclone.conf" # default options
AUTOINSTALL=yes

# Function to install required packages
install() {
    echo "'$1' is required but not installed, attempting to install..."
    sleep 1
    [ -z "$DISTRO_INSTALL" ] && check_distro
    if [ $EUID -ne 0 ]; then
        sudo $DISTRO_INSTALL $1 || abort "Failed while trying to install '$1'. Please install it manually and try again."
    else
        $DISTRO_INSTALL $1 || abort "Failed while trying to install '$1'. Please install it manually and try again."
    fi
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
    echo "$@"
    exit 1
}

# Function to install rclone
install_rclone() {
    echo "Installing rclone into '$INSTALL_DIR'..."
    # Download and extract rclone
    temp_dir=$(mktemp -d)
    cd "$temp_dir"
    wget "$ORIGIN_REPO" -O rclone.zip || abort "Failed to download rclone."
    unzip rclone.zip || abort "Failed to unzip rclone."
    # Move rclone binary to /usr/local/bin
    cd rclone-*-linux-amd64
    sudo cp rclone "$INSTALL_DIR" || abort "Failed to copy rclone to $INSTALL_DIR."
    sudo chown root:root "$INSTALL_DIR/rclone"
    sudo chmod 755 "$INSTALL_DIR/rclone"
    echo "rclone installed successfully in '$INSTALL_DIR'."
    # Clean up
    cd ~
    rm -rf "$temp_dir"
}

## Function to configure rclone
configure_rclone() {
    echo "Configuring rclone..."
    if [ ! -f "$CONFIGFILE" ]; then
        echo "Creating default rclone config..."
        cat << EOF | sudo tee "$CONFIGFILE" > /dev/null
[zurg]
type = webdav
url = http://zurg:9999/dav
vendor = other
pacer_min_sleep = 0
EOF
        echo "Default rclone config created at '$CONFIGFILE'."
    fi

    # Create a symbolic link to the default config location
    mkdir -p /root/.config/rclone
    ln -sf "$CONFIGFILE" /root/.config/rclone/rclone.conf

    rclone config --config "$CONFIGFILE" || abort "Failed to configure rclone."
    echo "Configuration complete."
}


# Function to install fuse3 and modify fuse.conf
install_fuse3() {
    if ! dpkg -s fuse3 >/dev/null 2>&1; then
        install fuse3
    fi
    if [ -f /etc/fuse.conf ]; then
        sudo sed -i 's/#user_allow_other/user_allow_other/' /etc/fuse.conf || abort "Failed to modify /etc/fuse.conf"
        echo "/etc/fuse.conf has been updated."
    else
        echo "user_allow_other" | sudo tee -a /etc/fuse.conf > /dev/null
        echo "/etc/fuse.conf created and updated."
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
        echo "Mount point '$MOUNT_POINT' already exists."
    else
        sudo mkdir -p "$MOUNT_POINT" || abort "Failed to create mount point '$MOUNT_POINT'."
        echo "Mount point '$MOUNT_POINT' created successfully."
    fi

    echo -n "Would you like to create a systemd service for this mount? "
    if yesno; then
        create_systemd_service "$MOUNT_POINT"
    else
        echo "Systemd service creation skipped."
    fi
}

# Placeholder function to create a systemd service
create_systemd_service() {
    MOUNT_POINT=$1
    SERVICE_NAME=$(basename "$MOUNT_POINT")
    
    # Example service configuration (to be updated with default settings)
    sudo tee /etc/systemd/system/rclone-${SERVICE_NAME}.service > /dev/null << EOF
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

    sudo systemctl daemon-reload
    sudo systemctl enable rclone-${SERVICE_NAME}.service || abort "Failed to enable systemd service."
    sudo systemctl start rclone-${SERVICE_NAME}.service || abort "Failed to start systemd service."
    echo "Systemd service 'rclone-${SERVICE_NAME}.service' created and started."
}

if [ $EUID -ne 0 ]; then
    echo
    echo "This script needs to install files in system locations and will ask for sudo/root permissions now."
    sudo -v || abort "Root permissions are required for setup, cannot continue."
elif [ ! -z "$SUDO_USER" ]; then
    echo
    abort "This script will ask for sudo as necessary, but you should not run it as sudo. Please try again."
fi

for req in wget unzip sudo; do
    if ! hash $req 2>/dev/null; then
        install $req
    fi
done

install_fuse3
install_rclone
configure_rclone
create_mount_and_service

echo
echo -n "Would you like to check the rclone version now? "
if yesno; then
    rclone version || abort "Failed to verify rclone installation."
fi
