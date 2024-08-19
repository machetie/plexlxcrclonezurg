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
read -p "Would you like to add Zurg and Rclone? (Y/n): " install_zurg_rclone
install_zurg_rclone=${install_zurg_rclone:-Y}
if [[ $install_zurg_rclone =~ ^[Yy]$ ]]; then
    msg_info "Installing Zurg and Rclone"
    
    # Download and execute the Zurg and Rclone installation script
    curl -sSL https://raw.githubusercontent.com/machetie/plexlxcrclonezurg/main/zurg_rclone-install.sh -o zurg_rclone-install.sh
    chmod +x zurg_rclone-install.sh
    ./zurg_rclone-install.sh
    rm zurg_rclone-install.sh
    
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