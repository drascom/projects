#!/bin/bash

set -e

# Install Mosquitto and its clients
sudo apt update
sudo apt install -y mosquitto mosquitto-clients

# Prompt for username and password
echo -n "Enter Mosquitto username: "
read MQTT_USER

while true; do
    echo -n "Enter Mosquitto password: "
    read -s MQTT_PASS
    echo
    echo -n "Confirm Mosquitto password: "
    read -s MQTT_PASS_CONFIRM
    echo
    [ "$MQTT_PASS" = "$MQTT_PASS_CONFIRM" ] && break
    echo "Passwords do not match. Please try again."
done

# Create Mosquitto password file (overwrite if exists)
sudo mosquitto_passwd -c -b /etc/mosquitto/passwd "$MQTT_USER" "$MQTT_PASS"

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

echo "Mosquitto installed and configured with authentication and WebSockets support on port 9001."
