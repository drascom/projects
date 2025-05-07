# Create update.sh
cat >"update.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

ENV_FILE=".env"

read -p "MQTT_BROKER [localhost]: " broker
broker=${broker:-localhost}

read -p "MQTT_PORT [9001]: " port
port=${port:-9001}

read -p "MQTT_USERNAME [admin]: " username
username=${username:-admin}

read -p "MQTT_PASSWORD [admin]: " password
password=${password:-admin}

read -p "GUI_PORT [9876]: " gui_port
gui_port=${gui_port:-9876}

id=$(hostname)

cat >"$ENV_FILE" <<EOL
MQTT_BROKER=$broker
MQTT_PORT=$port
MQTT_USERNAME=$username
MQTT_PASSWORD=$password
DEVICE_ID=$id
GUI_HOST=0.0.0.0
GUI_PORT=$gui_port
EOL

echo "✅ .env updated successfully."
EOF
chmod +x update.sh
