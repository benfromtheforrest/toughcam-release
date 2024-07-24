#!/bin/bash

# Update and upgrade the system
sudo apt-get update && sudo apt-get upgrade -y

# Install GStreamer and plugins
sudo apt-get install -y gstreamer1.0-tools gstreamer1.0-plugins-base \
                        gstreamer1.0-plugins-good gstreamer1.0-plugins-bad \
                        gstreamer1.0-plugins-ugly gstreamer1.0-libav

# Install FFmpeg
sudo apt-get install -y ffmpeg

# Install other necessary packages
#sudo apt-get install -y python3-pip

# Install Python gpiozero library
pip3 install gpiozero

# Create necessary directories
mkdir -p /home/crosstech/toughcam-release/temp_videos
mkdir -p /home/crosstech/toughcam-release/output_videos

# Set permissions for the scripts
chmod +x /home/crosstech/toughcam-release/new_record.sh
chmod +x /home/crosstech/toughcam-release/upload_service.sh
chmod +x /home/crosstech/toughcam-release/reset_gps_usb.sh

# Set up a systemd service to run the main Python script at startup as root
echo "[Unit]
Description=Run ToughCam Recording Service
After=network.target

[Service]
ExecStart=/usr/bin/python3 /home/crosstech/toughcam-release/launch_record.py
WorkingDirectory=/home/crosstech/toughcam-release
StandardOutput=syslog
StandardError=syslog
Restart=always
User=root

[Install]
WantedBy=multi-user.target" | sudo tee /etc/systemd/system/toughcam-recording-service.service

# Enable and start the systemd service
sudo systemctl enable toughcam-recording-service.service
sudo systemctl start toughcam-recording-service.service

echo "Installation complete. Rebooting the system..."
sudo reboot
