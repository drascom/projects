#!/usr/bin/env bash
###############################################################################
# MQTT‑Device‑Monitor unified installer / un‑installer                        #
#                                                                            #
# Supports:  • Debian / Ubuntu   • macOS (intel & Apple Silicon)             #
# Usage:    curl -fsSL https://raw.githubusercontent.com/drascom/projects/main/mqtt-monitor/manage.sh | bash
#                                                                            #
#  – If the software is **not installed**, the script performs a full        #
#    installation.                                                           #
#  – If the software **is already installed** (detected by its install dir   #
#    or active service), running the same one‑liner **without flags**        #
#    performs a complete clean un‑install.                                   #
#                                                                            #
# Optional flags (advanced users):
#   --install       Force install (even if an old copy exists – it will be
#                   overwritten).
#   --uninstall     Force removal only.
#   --help          Print this help.
###############################################################################
set -Eeuo pipefail
shopt -s inherit_errexit   # modern bash – propagate error from subshells

################################################################################
# Constants & Globals                                                          #
################################################################################
INSTALL_DIR="/opt/mqtt-device-monitor"           # installation root
REPO_URL="https://github.com/drascom/projects.git"
SYSTEMD_UNIT="/etc/systemd/system/mqtt-device-monitor.service"
LAUNCHD_PLIST="$HOME/Library/LaunchAgents/com.mqtt-device-monitor.plist"
PYTHON="python3"                                 # overridable by env
OS=""                                            # linux|macos
DISTRO=""                                        # debian|ubuntu|arch|unknown
ACTUAL_USER=${SUDO_USER:-$(id -un)}              # user who invoked sudo / root

################################################################################
# Colours & helpers                                                            #
################################################################################
RED="\033[0;31m"; GREEN="\033[0;32m"; YELLOW="\033[0;33m"; BLUE="\033[0;34m"; NC="\033[0m"
msg() { printf "%b%s%b\n" "${2:-$GREEN}" "$1" "$NC" >&2 ; }
require_root() { (( EUID == 0 )) || { msg "❌  Must be run as root" "$RED"; exit 1; }; }
cmd_exists()  { command -v "$1" &>/dev/null; }
run_as_user() { sudo -u "$ACTUAL_USER" "$@"; }

################################################################################
# OS Detection                                                                 #
################################################################################
detect_os() {
  case $(uname -s) in
    Linux*)  OS="linux" ;;
    Darwin*) OS="macos" ;;
    *)       msg "Unsupported OS $(uname -s)" "$RED"; exit 1 ;;
  esac

  if [[ $OS == linux ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release || true
    DISTRO=${ID:-unknown}
  fi

  msg "Detected $OS ${DISTRO:-}" "$BLUE"
}

################################################################################
# System packages                                                              #
################################################################################
install_deps() {
  msg "Installing OS dependencies …" "$BLUE"

  if [[ $OS == linux ]]; then
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       git curl build-essential mosquitto mosquitto-clients $PYTHON $PYTHON-venv
  else
    if ! cmd_exists brew; then
      msg "Installing Homebrew … (may prompt for password)" "$YELLOW"
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      eval "$(/opt/homebrew/bin/brew shellenv || /usr/local/bin/brew shellenv)"
    fi
    brew update
    brew install git mosquitto $PYTHON || true
    brew services start mosquitto || true
  fi
}

################################################################################
# Mosquitto configuration (auth + websockets)                                  #
################################################################################
configure_mosquitto() {
  msg "Configuring Mosquitto broker …" "$BLUE"

  local conf passwd
  if [[ $OS == linux ]]; then
    conf="/etc/mosquitto/conf.d/mqtt-monitor.conf"
    passwd="/etc/mosquitto/passwd"
    mkdir -p /etc/mosquitto/conf.d
  else
    conf="$(brew --prefix)/etc/mosquitto/mqtt-monitor.conf"
    passwd="$(brew --prefix)/etc/mosquitto/passwd"
  fi

  # authentication prompt
  read -rp "MQTT username (leave blank for anonymous): " USERNAME </dev/tty || true
  if [[ -n "$USERNAME" ]]; then
    # Interactive password twice for safety
    local p1 p2
    while true; do
      read -srp "Password for $USERNAME: " p1 </dev/tty && echo
      read -srp "Confirm   password: " p2 </dev/tty && echo
      [[ "$p1" == "$p2" && -n "$p1" ]] && break
      msg "Passwords don't match – try again" "$YELLOW"
    done
    mosquitto_passwd -c -b "$passwd" "$USERNAME" "$p1"
    chown mosquitto:mosquitto "$passwd"
    chmod 600 "$passwd"
  fi

  cat >"$conf" <<EOF
# Auto‑generated by manage.sh
listener 1883
protocol mqtt
listener 9001
protocol websockets
allow_anonymous $([[ -z "$USERNAME" ]] && echo true || echo false)
$( [[ -n "$USERNAME" ]] && echo "password_file $passwd" )
EOF

  if [[ $OS == linux ]]; then
    systemctl restart mosquitto
    systemctl enable  mosquitto
  else
    brew services restart mosquitto
  fi

  msg "Mosquitto ready (MQTT :1883, WS :9001)" "$GREEN"
}

################################################################################
# Git clone                                                                    #
################################################################################
fetch_repo() {
  if [[ -d $INSTALL_DIR ]]; then
    msg "Existing installation detected in $INSTALL_DIR – overwriting" "$YELLOW"
    rm -rf "$INSTALL_DIR"
  fi
  git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
  # we only need mqtt-monitor subdir
  if [[ ! -f "$INSTALL_DIR/mqtt-monitor/main.py" ]]; then
    msg "Repository layout changed – aborting" "$RED"; exit 1
  fi
}

################################################################################
# Python virtualenv & requirements                                             #
################################################################################
setup_venv() {
  cd "$INSTALL_DIR/mqtt-monitor"
  $PYTHON -m venv .venv
  . .venv/bin/activate
  pip install --upgrade pip
  [[ -f requirements.txt ]] && pip install -r requirements.txt
  deactivate
}

################################################################################
# .env interactive wizard                                                      #
################################################################################
create_env_file() {
  cd "$INSTALL_DIR/mqtt-monitor"
  local env=.env
  msg "Creating $env …" "$BLUE"
  local broker="localhost" port="9001" gui_port="9876" dev_id="$(hostname)" user="$USERNAME" pass="${p1:-}"
  read -rp "MQTT broker [$broker]: " tmp </dev/tty || true; broker=${tmp:-$broker}
  read -rp "MQTT port   [$port]  : " tmp </dev/tty || true; port=${tmp:-$port}
  read -rp "GUI  port   [$gui_port]: " tmp </dev/tty || true; gui_port=${tmp:-$gui_port}
  cat >"$env" <<EOF
MQTT_BROKER=$broker
MQTT_PORT=$port
MQTT_USERNAME=$user
MQTT_PASSWORD=$pass
DEVICE_ID=$dev_id
GUI_HOST=0.0.0.0
GUI_PORT=$gui_port
EOF
  chmod 600 "$env"
}

################################################################################
# Service files                                                                #
################################################################################
create_service() {
  if [[ $OS == linux ]]; then
    cat >"$SYSTEMD_UNIT" <<EOF
[Unit]
Description=MQTT Device Monitor
After=network.target mosquitto.service

[Service]
Type=simple
User=$ACTUAL_USER
WorkingDirectory=$INSTALL_DIR/mqtt-monitor
ExecStart=$INSTALL_DIR/mqtt-monitor/.venv/bin/python main.py
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now mqtt-device-monitor.service
  else
    cat >"$LAUNCHD_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.mqtt-device-monitor</string>
  <key>ProgramArguments</key><array>
    <string>$INSTALL_DIR/mqtt-monitor/.venv/bin/python</string>
    <string>$INSTALL_DIR/mqtt-monitor/main.py</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>WorkingDirectory</key><string>$INSTALL_DIR/mqtt-monitor</string>
</dict></plist>
EOF
    chown "$ACTUAL_USER" "$LAUNCHD_PLIST"
    launchctl unload "$LAUNCHD_PLIST" 2>/dev/null || true
    launchctl load   "$LAUNCHD_PLIST"
  fi
}

remove_everything() {
  msg "Removing MQTT‑Device‑Monitor …" "$BLUE"
  if [[ -f $SYSTEMD_UNIT ]]; then
    systemctl disable --now mqtt-device-monitor.service || true
    rm -f "$SYSTEMD_UNIT"
    systemctl daemon-reload
  fi
  if [[ -f $LAUNCHD_PLIST ]]; then
    launchctl unload "$LAUNCHD_PLIST" || true
    rm -f "$LAUNCHD_PLIST"
  fi
  rm -rf "$INSTALL_DIR"
  msg "Removal complete" "$GREEN"
}

################################################################################
# Main                                                                         #
################################################################################
require_root
OPERATION="auto"   # auto‑toggle
[[ ${1:-} == --install ]]   && OPERATION="install"
[[ ${1:-} == --uninstall ]] && OPERATION="uninstall"
[[ ${1:-} == --help || ${1:-} == -h ]] && {
  grep -m1 -A99 "^###############################################################################" "$0" | sed '1,2d;/^###############################################################################/q'; exit 0; }

if [[ $OPERATION == auto ]]; then
  if [[ -d $INSTALL_DIR ]]; then OPERATION="uninstall"; else OPERATION="install"; fi
fi

detect_os

if [[ $OPERATION == uninstall ]]; then
  remove_everything
  exit 0
fi

install_deps
configure_mosquitto
fetch_repo
setup_venv
create_env_file
create_service

msg "✅  Installation complete. Access GUI on http://$(hostname -I 2>/dev/null | awk '{print $1}'):${gui_port:-9876}" "$GREEN"
