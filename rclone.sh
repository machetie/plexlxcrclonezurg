#!/usr/bin/env bash

source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y curl sudo mc wget unzip
msg_ok "Installed Dependencies"

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

msg_info "Installing fuse3"
$STD apt-get install -y fuse3
if [ -f /etc/fuse.conf ]; then
    sed -i 's/#user_allow_other/user_allow_other/' /etc/fuse.conf
else
    echo "user_allow_other" > /etc/fuse.conf
fi
msg_ok "Installed fuse3"

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

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"

msg_ok "Rclone setup completed successfully"
echo -e "Rclone is now configured and mounted at ${MOUNT_POINT}"