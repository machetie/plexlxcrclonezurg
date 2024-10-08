#!/usr/bin/env bash

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

echo "Installing Dependencies"
$STD apt-get install -y curl sudo mc wget unzip git gh jq
echo "Installed Dependencies"

echo "Determining System Info"
SYSTEM_INFO=$(get_system_info)
echo "System Info: $SYSTEM_INFO"

echo "Zurg Installation"
echo "Do you want to install from the private repository? (Y/N)"
read -r repo_choice

if [[ "$repo_choice" =~ ^[Yy]$ ]]; then
    echo "Installing from private repository"
    read -p "Enter your GitHub token: " GITHUB_TOKEN
    install_zurg
else
    echo "Installing from public repository"
    install_public_repo
fi

echo "Creating Zurg Config"
create_zurg_config_file
echo "Created Zurg Config"

echo "Setting Up Systemd Service"
create_and_start_systemd_service
echo "Set Up Systemd Service"

echo "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
echo "Cleaned"

echo "Zurg installation complete. Your config file is located at /etc/zurg/config.yml"

# Repository details
PRIVATE_OWNER="debridmediamanager"
PRIVATE_REPO="zurg"
PUBLIC_OWNER="debridmediamanager"
PUBLIC_REPO="zurg-testing"

# Function to install packages
install_package() {
    if [ -x "$(command -v apt-get)" ]; then
        apt-get update && apt-get install -y $1
    elif [ -x "$(command -v yum)" ]; then
        yum install -y $1
    elif [ -x "$(command -v brew)" ]; then
        brew install $1
    else
        echo "Unable to install $1. Please install it manually."
        exit 1
    fi
}

# Function to check and install required tools
check_and_install_tools() {
    if ! command -v git &> /dev/null; then
        echo "Git is not installed. Installing..."
        install_package git
    fi

    if ! command -v gh &> /dev/null; then
        echo "GitHub CLI (gh) is not installed. Installing..."
        install_package gh
    fi

    if ! command -v jq &> /dev/null; then
        echo "jq is not installed. Installing..."
        install_package jq
    fi

    if ! command -v unzip &> /dev/null; then
        echo "unzip is not installed. Installing..."
        install_package unzip
    fi
}

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
    echo "Config file created at /etc/zurg/config.yml with your API token."
}

# Function to install Zurg (private repo)
install_zurg() {
    # Authenticate with GitHub
    echo "Authenticating with GitHub..."
    gh auth login --with-token <<< "$GITHUB_TOKEN"
    if [ $? -ne 0 ]; then
        echo "GitHub authentication failed. Please check your token and try again."
        exit 1
    fi
    echo "GitHub authentication successful."

    # List available releases without pager
    echo "Available Zurg releases:"
    gh release list -R ${PRIVATE_OWNER}/${PRIVATE_REPO} --limit 10

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

    if [ -z "$DOWNLOADED_FILE" ]; then
        echo "No matching asset found for your system ($SYSTEM_INFO)"
        echo "Available assets:"
        gh release view -R ${PRIVATE_OWNER}/${PRIVATE_REPO} --json assets --jq '.assets[].name'
        exit 1
    fi

    echo "Asset downloaded successfully: $DOWNLOADED_FILE"

    # Check if the file is a zip archive
    if [[ "$DOWNLOADED_FILE" == *.zip ]]; then
        echo "Extracting zip file..."
        unzip -o "$DOWNLOADED_FILE"
        rm "$DOWNLOADED_FILE"
        BINARY_FILE=$(ls zurg* 2>/dev/null | grep -v '\.zip$' | head -n1)
        if [ -z "$BINARY_FILE" ]; then
            echo "Unable to find the extracted binary file."
            exit 1
        fi
    else
        BINARY_FILE="$DOWNLOADED_FILE"
    fi

    # Make the binary executable
    chmod +x "$BINARY_FILE"

    # Move the binary to a directory in PATH
    mv "$BINARY_FILE" /usr/local/bin/zurg

    echo "Zurg has been installed. You can now run it by typing 'zurg' in the terminal."
}

# Function to install public repo
install_public_repo() {
    DOWNLOAD_URL="https://github.com/debridmediamanager/zurg-testing/releases/download/v0.9.3-final/zurg-v0.9.3-final-linux-amd64.zip"
    FILENAME="zurg-v0.9.3-final-linux-amd64.zip"

    echo "Downloading Zurg from public repository..."
    wget $DOWNLOAD_URL -O $FILENAME

    if [ ! -f "$FILENAME" ]; then
        echo "Failed to download the file. Please check your internet connection and try again."
        exit 1
    fi

    echo "File downloaded successfully: $FILENAME"

    # Extract the zip file
    unzip -o "$FILENAME"
    rm "$FILENAME"

    # Find the extracted binary
    BINARY_FILE=$(ls zurg* 2>/dev/null | grep -v '\.zip$' | head -n1)
    if [ -z "$BINARY_FILE" ]; then
        echo "Unable to find the extracted binary file."
        exit 1
    fi

    # Make the binary executable
    chmod +x "$BINARY_FILE"

    # Move the binary to a directory in PATH
    mv "$BINARY_FILE" /usr/local/bin/zurg

    echo "Zurg has been installed. You can now run it by typing 'zurg' in the terminal."
}

# Function to create and start systemd service
create_and_start_systemd_service() {
    # Create systemd service file
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

    echo "Zurg systemd service has been created and started."
}