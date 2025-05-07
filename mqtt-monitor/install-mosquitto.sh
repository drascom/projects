#!/bin/bash

set -e

# Install Mosquitto and its clients
sudo apt update
sudo apt install -y mosquitto mosquitto-clients

# Create Mosquitto password file with admin:changeme
sudo mosquitto_passwd -c -b /etc/mosquitto/passwd admin changeme

# Ensure the file is managed by the appropriate user and group
sudo chown mosquitto:mosquitto /etc/mosquitto/passwd

# Configure Mosquitto to use password file, disable anonymous access, and enable websockets
CONF_FILE="/etc/mosquitto/conf.d/auth.conf"
sudo bash -c "cat > $CONF_FILE" <<EOF
allow_anonymous false
password_file /etc/mosquitto/passwd

listener 9001
protocol websockets
EOF

# Restart and enable Mosquitto service
sudo systemctl restart mosquitto
sudo systemctl enable mosquitto

echo "Mosquitto installed and configured with username 'admin' and password 'default'. WebSockets enabled on port 9001."
