#!/usr/bin/env bash
# Test script for OS detection only

# Import only the necessary functions
RED="\033[0;31m"; GREEN="\033[0;32m"; YELLOW="\033[0;33m"; BLUE="\033[0;34m"; NC="\033[0m"
print_msg() { local c="${2:-$GREEN}"; printf "%b%s%b\n" "$c" "$1" "$NC"; }
command_exists() { command -v "$1" &>/dev/null; }

# OS detection function
OS=""; DISTRO=""
detect_os() {
  # Add debugging output
  print_msg "Detecting operating system..." "$BLUE"
  
  # Get OS type with error handling
  local os_type
  os_type=$(uname -s 2>/dev/null) || {
    print_msg "Failed to execute 'uname -s'" "$RED"
    print_msg "Trying alternative detection methods..." "$YELLOW"
    
    # Try alternative detection methods
    if [[ -f /proc/version ]]; then
      if grep -qi "linux" /proc/version; then
        os_type="Linux"
      fi
    elif [[ -d /System/Library/CoreServices ]]; then
      os_type="Darwin"
    fi
    
    # If still no detection, try a simple check
    if [[ -z "$os_type" ]]; then
      if [[ "$(uname 2>/dev/null)" == "Darwin" ]]; then
        os_type="Darwin"
      elif [[ "$(uname 2>/dev/null)" == "Linux" ]]; then
        os_type="Linux"
      fi
    fi
    
    # If all else fails
    if [[ -z "$os_type" ]]; then
      print_msg "Could not detect OS type" "$RED"
      return 1
    fi
  }
  
  print_msg "Detected system type: $os_type" "$GREEN"
  
  # Set OS based on detected type
  case "$os_type" in
    Darwin*) 
      OS="macos"
      print_msg "Identified as macOS" "$GREEN"
      ;;
    Linux*)  
      OS="linux"
      print_msg "Identified as Linux" "$GREEN"
      ;;
    *) 
      print_msg "Unsupported OS: $os_type" "$RED"
      return 1
      ;;
  esac
  
  # For Linux, detect distribution
  if [[ $OS == "linux" ]]; then
    if [[ -e /etc/os-release ]]; then
      # shellcheck disable=SC1091
      . /etc/os-release
      DISTRO=$ID
      print_msg "Linux distribution: $DISTRO" "$GREEN"
    else
      print_msg "Could not detect Linux distribution" "$YELLOW"
      DISTRO="unknown"
    fi
  fi
  
  return 0
}

# Run the test
print_msg "=== Testing OS Detection ===" "$BLUE"
detect_os
print_msg "=== Test Results ===" "$BLUE"
print_msg "OS: $OS" "$GREEN"
print_msg "DISTRO: $DISTRO" "$GREEN"
