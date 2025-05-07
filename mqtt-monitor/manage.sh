#!/usr/bin/env bash
###############################################################################
# MQTT‑Device‑Monitor : non‑interactive installer / remover                   #
###############################################################################
set -Eeuo pipefail

INSTALL_DIR="/opt/mqtt-device-monitor"
REPO_URL="https://github.com/drascom/projects.git"
REPO_SUBPATH="mqtt-monitor"
SYSTEMD_UNIT="/etc/systemd/system/mqtt-device-monitor.service"
PYTHON="python3"
OS="" DISTRO=""
ACTUAL_USER=${SUDO_USER:-$(id -un)}

MQTT_USER="admin"
MQTT_PASS="admin"

RED="\033[0;31m"; GREEN="\033[0;32m"; YELLOW="\033[0;33m"; BLUE="\033[0;34m"; NC="\033[0m"
msg() { printf "%b%s%b\n" "${2:-$GREEN}" "$1" "$NC" >&2; }
require_root() { ((EUID==0)) || { msg "❌  Must run as root" "$RED"; exit 1; }; }
cmd_exists()  { command -v "$1" &>/dev/null; }
run_as_user() { sudo -u "$ACTUAL_USER" "$@"; }

detect_os() {
  case $(uname -s) in
    Linux*)  OS="linux" ;;
    Darwin*) OS="macos" ;;
    *) msg "Unsupported OS $(uname -s)" "$RED"; exit 1 ;;
  esac
  if [[ $OS == linux ]]; then source /etc/os-release; DISTRO=${ID:-unknown}; fi
  msg "Detected $OS${DISTRO:+/$DISTRO}" "$BLUE"
}

install_deps() {
  msg "Installing packages …" "$BLUE"
  if [[ $OS == linux ]]; then
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      git curl build-essential $PYTHON $PYTHON-venv
  else
    if ! cmd_exists brew; then
      msg "Installing Homebrew …" "$YELLOW"
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      eval "$(/opt/homebrew/bin/brew shellenv || /usr/local/bin/brew shellenv)"
    fi
    brew update
    brew install git $PYTHON || true
  fi
}

fetch_repo() {
  [[ -d $INSTALL_DIR ]] && { msg "Replacing previous install" "$YELLOW"; rm -rf "$INSTALL_DIR"; }
  mkdir -p "$INSTALL_DIR"
  git clone --depth 1 "$REPO_URL" "$INSTALL_DIR/tmpclone"
  mv "$INSTALL_DIR/tmpclone/$REPO_SUBPATH"/* "$INSTALL_DIR"/
  rm -rf "$INSTALL_DIR/tmpclone"
  [[ -f "$INSTALL_DIR/main.py" ]] || { msg "Repo layout unexpected" "$RED"; exit 1; }
}

setup_venv() {
  cd "$INSTALL_DIR"
  $PYTHON -m venv .venv
  . .venv/bin/activate
  pip install --upgrade pip
  [[ -f requirements.txt ]] && pip install -r requirements.txt
  deactivate
}

create_env() {
  cd "$INSTALL_DIR"
  local env=.env broker="localhost" port=9001 gui_port=9876 id="$(hostname)"
  cat >"$env" <<EOF
MQTT_BROKER=$broker
MQTT_PORT=$port
MQTT_USERNAME=$MQTT_USER
MQTT_PASSWORD=$MQTT_PASS
DEVICE_ID=$id
GUI_HOST=0.0.0.0
GUI_PORT=$gui_port
EOF
  chmod 600 "$env"

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
}

create_service() {
  cat >"$SYSTEMD_UNIT" <<EOF
[Unit]
Description=MQTT Device Monitor
After=network.target
[Service]
Type=simple
User=$ACTUAL_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/.venv/bin/python main.py
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now mqtt-device-monitor.service
}

remove_all() {
  msg "Removing installation …" "$BLUE"
  [[ -f $SYSTEMD_UNIT ]] && { systemctl disable --now mqtt-device-monitor.service || true; rm -f "$SYSTEMD_UNIT"; systemctl daemon-reload; }
  rm -rf "$INSTALL_DIR"
  msg "Uninstall complete" "$GREEN"
}

############################ CLI #############################################
OP=auto
case "${1:-}" in
  --install)   OP=install ;;
  --uninstall) OP=uninstall ;;
  -h|--help)   grep -m1 -A99 "^###############################################################################" "$0" | sed '1,2d;/^###############################################################################/q'; exit 0 ;;
esac

require_root
detect_os

if [[ $OP == auto ]]; then
  if [[ -d $INSTALL_DIR ]]; then
    OP="uninstall"
  else
    OP="install"
  fi
fi

if [[ $OP == uninstall ]]; then
  remove_all
  exit 0
fi

install_deps
fetch_repo
setup_venv
create_env
run_as_user bash "$INSTALL_DIR/update.sh"
create_service
msg "✅  Installation complete – GUI on http://$(hostname -I 2>/dev/null | awk '{print $1}'):${gui_port:-9876} (admin/admin)" "$GREEN"
