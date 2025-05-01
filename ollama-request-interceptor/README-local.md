# Ollama Request Interceptor

A tool to intercept and monitor API requests between clients and Ollama server using mitmproxy.

## Overview

This tool sets up a proxy server that sits between your client applications and the Ollama API server. It allows you to:

- Monitor all API requests and responses
- Debug client-server interactions
- Understand the Ollama API format
- Troubleshoot issues with client applications

## Installation

### Prerequisites

- macOS or Linux (Ubuntu/Debian)
- Python 3.x
- For macOS: Homebrew (will be installed if missing)
- For Linux: apt package manager

### Automatic Installation

Run the installation script:

```bash
# Clone the repository (if you haven't already)
git clone https://github.com/yourusername/ollama-request-interceptor.git
cd ollama-request-interceptor

# Make the script executable
chmod +x install-interceptor.sh

# Run the installer
./install-interceptor.sh
```

The script will:
1. Install required dependencies
2. Set up a Python virtual environment
3. Install mitmproxy
4. Create necessary configuration files
5. Set up a system service to run the proxy

## Usage

### Connecting to the Proxy

After installation, the proxy will be running at:
- API Proxy: http://localhost:8080/
- Web UI: http://localhost:8081/

To use the proxy with your applications, configure them to connect to Ollama at `http://localhost:8080` instead of the default `http://localhost:11434`.

### Viewing Intercepted Requests

You can view intercepted requests in two ways:

1. **Terminal Output**: The intercepted requests and responses will be printed to the terminal or log files.
2. **Web Interface**: Access the mitmproxy web interface at http://localhost:8081/ to see detailed request/response information.

## Service Management

### macOS

Check service status:
```bash
launchctl list | grep ollama
# or
launchctl list com.ollama.interceptor
```

Stop the service:
```bash
launchctl stop com.ollama.interceptor
```

Disable the service (until next login):
```bash
launchctl unload ~/Library/LaunchAgents/com.ollama.interceptor.plist
```

Start the service:
```bash
launchctl start com.ollama.interceptor
```

Enable the service:
```bash
launchctl load ~/Library/LaunchAgents/com.ollama.interceptor.plist
```

View logs:
```bash
cat ~/ollama-interceptor/output.log
cat ~/ollama-interceptor/error.log
```

### Linux

Check service status:
```bash
sudo systemctl status mitmweb
```

Stop the service:
```bash
sudo systemctl stop mitmweb
```

Disable the service:
```bash
sudo systemctl disable mitmweb
```

Start the service:
```bash
sudo systemctl start mitmweb
```

Enable the service:
```bash
sudo systemctl enable mitmweb
```

View logs:
```bash
sudo journalctl -u mitmweb
```

## Manual Operation

If you prefer to run the proxy manually without using the system service:

```bash
cd ~/ollama-interceptor
./start-mitmweb.sh
```

## Customization

### Changing the Target URL

If your Ollama server is running on a different port or host, edit the `start-mitmweb.sh` script:

```bash
nano ~/ollama-interceptor/start-mitmweb.sh
```

Change the `OLLAMA_TARGET` variable to your desired URL.

### Modifying Interception Logic

To change what requests are intercepted or how they're processed, edit the Python script:

```bash
nano ~/ollama-interceptor/ollama_intercept.py
```

## Troubleshooting

### Port Already in Use

If you see an error about port 8080 being in use:

1. Choose a different port by editing `start-mitmweb.sh`
2. Stop any other services using port 8080
3. Restart the service

### Service Not Starting

Check the logs for errors:
- macOS: `cat ~/ollama-interceptor/error.log`
- Linux: `sudo journalctl -u mitmweb`

## Uninstallation

### macOS

```bash
launchctl unload ~/Library/LaunchAgents/com.ollama.interceptor.plist
rm ~/Library/LaunchAgents/com.ollama.interceptor.plist
rm -rf ~/ollama-interceptor
```

### Linux

```bash
sudo systemctl stop mitmweb
sudo systemctl disable mitmweb
sudo rm /etc/systemd/system/mitmweb.service
sudo systemctl daemon-reload
rm -rf ~/ollama-interceptor
```

## Security Considerations

This tool is intended for development and debugging purposes only. The proxy does not implement any authentication or encryption, so it should only be used in trusted environments.

## Last Updated

May 1, 2025