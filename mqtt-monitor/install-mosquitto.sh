#!/bin/bash

set -e

if [ $# -ne 2 ]; then
    echo "Usage: $0 <username> <password>"
    exit 1
fi

MQTT_USER="$1"
MQTT_PASS="$2"

# Install Mosquitto and its clients
sudo apt update
sudo apt install -y mosquitto mosquitto-clients

# Create Mosquitto password file
sudo mosquitto_passwd -c -b /etc/mosquitto/passwd "$MQTT_USER" "$MQTT_PASS"

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

echo "Mosquitto installed and configured with authentication and WebSockets support on port 9001."
