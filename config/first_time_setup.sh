#!/bin/bash

# Prompt for Toughcam ID
read -p "Enter Toughcam ID (1, 2, 3, etc.): " TOUGHCAM_ID

# Format the ID as tc001, tc002, etc.
FORMATTED_ID=$(printf "tc%03d" $TOUGHCAM_ID)

# Create the configuration directory and file
CONFIG_DIR="/home/crosstech/toughcam-release/config"
CONFIG_FILE="$CONFIG_DIR/config.txt"
mkdir -p $CONFIG_DIR
echo "TOUGHCAM_ID=$FORMATTED_ID" > $CONFIG_FILE

# Update and upgrade the system
sudo apt-get update && sudo apt-get upgrade -y

# Install necessary packages
sudo apt-get install -y apt-transport-https ca-certificates gnupg curl openvpn

# Add Google Cloud SDK repository
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg

echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list

# Update package list and install Google Cloud SDK
sudo apt-get update && sudo apt-get install -y google-cloud-cli

# Install GStreamer and plugins
sudo apt-get install -y gstreamer1.0-tools gstreamer1.0-plugins-base \
                        gstreamer1.0-plugins-good gstreamer1.0-plugins-bad \
                        gstreamer1.0-plugins-ugly gstreamer1.0-libav

# Install FFmpeg
sudo apt-get install -y ffmpeg

# Install other necessary packages
sudo apt-get install -y python3-pip quota

# Install Python gpiozero library
pip3 install gpiozero

# Create necessary directories
mkdir -p /home/crosstech/toughcam-release/temp_videos
mkdir -p /home/crosstech/toughcam-release/output_videos

# Set permissions for the scripts
chmod +x /home/crosstech/toughcam-release/new_record.sh
chmod +x /home/crosstech/toughcam-release/reset_gps_usb.sh

# Quota setup script
echo "#!/bin/bash

# Ensure the script is run as root
if [ \"\$(id -u)\" -ne 0 ]; then
    echo \"This script must be run as root\" >&2
    exit 1
fi

# Backup the existing /etc/fstab
cp /etc/fstab /etc/fstab.bak

# Modify /etc/fstab to add usrquota
if grep -q \"usrquota\" /etc/fstab; then
    echo \"usrquota already set in /etc/fstab\"
else
    sed -i 's/\\(PARTUUID=.*-02.*defaults,noatime\\)/\\1,usrquota/' /etc/fstab
    echo \"usrquota added to /etc/fstab\"
fi

# Remount the root filesystem
mount -o remount /

# Create quota files and enable quotas
quotacheck -cum /
quotaon /

# Set a 900GB quota for the root user
setquota -u root 0 900000000 0 0 /

# Verify quotas
repquota /

echo \"Quota setup complete.\"" > /home/crosstech/toughcam-release/setup_quota.sh

# Make the quota setup script executable
chmod +x /home/crosstech/toughcam-release/setup_quota.sh

# Run the quota setup script
sudo /home/crosstech/toughcam-release/setup_quota.sh

# Reload systemd to reflect any changes
sudo systemctl daemon-reload

# Set up a systemd service to run the main Python script at startup as root
echo "[Unit]
Description=Run ToughCam Recording Service
After=network.target

[Service]
ExecStart=/usr/bin/python3 /home/crosstech/toughcam-release/launch_record.py
WorkingDirectory=/home/crosstech/toughcam-release
StandardOutput=journal
StandardError=journal
Restart=always
User=root

[Install]
WantedBy=multi-user.target" | sudo tee /etc/systemd/system/toughcam-recording-service.service

# Set up a systemd service to run the upload Python script at startup as root
echo "[Unit]
Description=Run ToughCam Upload Service
After=network.target

[Service]
ExecStart=/usr/bin/python3 /home/crosstech/toughcam-release/upload_service.py
WorkingDirectory=/home/crosstech/toughcam-release
StandardOutput=journal
StandardError=journal
Restart=always
User=root

[Install]
WantedBy=multi-user.target" | sudo tee /etc/systemd/system/toughcam-upload-service.service

# Install and configure dhcpcd
sudo apt-get install -y dhcpcd5

# Backup existing dhcpcd.conf
if [ -f /etc/dhcpcd.conf ]; then
    echo "Backing up existing /etc/dhcpcd.conf to /etc/dhcpcd.conf.bak"
    sudo cp /etc/dhcpcd.conf /etc/dhcpcd.conf.bak
fi

# Configure dhcpcd.conf with interface metrics
echo "Configuring /etc/dhcpcd.conf with interface metrics..."
sudo bash -c 'cat << EOF > /etc/dhcpcd.conf
# Custom dhcpcd.conf with interface metrics
interface wlan0
metric 100

interface usb0
metric 200
EOF'

# Enable and start dhcpcd service
echo "Enabling and starting dhcpcd service..."
sudo systemctl enable dhcpcd
sudo systemctl start dhcpcd

# Confirm configuration
echo "Configuration complete. Current routing table:"
ip route

# Create OpenVPN startup script
echo "Creating OpenVPN startup script..."
sudo bash -c 'cat << EOF > /etc/network/if-up.d/connect_openvpn
#!/bin/sh

# Path to OpenVPN configuration file
CONFIG="/home/crosstech/config/client.ovpn"

# Check if the interface is up
if [ "$IFACE" = "eth0" ] || [ "$IFACE" = "wlan0" ] || [ "$IFACE" = "usb0" ]; then
    # Start OpenVPN with the configuration file
    /usr/sbin/openvpn --config "$CONFIG" --daemon --log /var/log/openvpn.log
fi
EOF'

# Make the OpenVPN startup script executable
sudo chmod +x /etc/network/if-up.d/connect_openvpn

# Enable and start the systemd services
sudo systemctl enable toughcam-recording-service.service
sudo systemctl start toughcam-recording-service.service

sudo systemctl enable toughcam-upload-service.service
sudo systemctl start toughcam-upload-service.service

echo "Installation complete. Rebooting the system..."
sudo reboot
