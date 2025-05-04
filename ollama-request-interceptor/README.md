# Ollama Request Interceptor

A tool to intercept and monitor API requests between clients and Ollama server using mitmproxy.

## Overview

This tool sets up a proxy server that sits between your client applications and the Ollama API server. It allows you to:

- Monitor all API requests and responses
- Debug client-server interactions
- Understand the Ollama API format
- Troubleshoot issues with client applications
- Support remote monitoring with client-server setup

### Architecture

The tool supports two deployment modes:

1. **Local Mode**: The interceptor runs on the same machine as your Ollama server and client applications.
2. **Client-Server Mode**: The interceptor runs on a server machine, and client machines can connect remotely to view the intercepted requests.

In client-server mode, the architecture looks like this:

```
Server Machine:                          Client Machine:
+------------------+                     +------------------+
| Ollama Server    |                     | Browser          |
| (API: 11434)     |                     | (Web UI via SSH) |
+------------------+                     +------------------+
         ↑                                        ↑
         |                                        |
+------------------+     SSH Tunnel      +------------------+
| Mitmproxy        | <------------------ | SSH Client       |
| (Interceptor)    |                     | (Secure Tunnel)  |
+------------------+                     +------------------+
```

The SSH tunnel provides a secure encrypted connection between the client and server.

## Installation

### Prerequisites

- macOS or Linux (Ubuntu/Debian)
- Python 3.x
- For macOS: Homebrew (will be installed if missing)
- For Linux: apt package manager
- For client-server setup: SSH client on client machines

### Server Installation

Run the installation script on the server machine:

```bash
# Clone the repository (if you haven't already)
git clone https://github.com/drascom/projects.git
cd projects/ollama-request-interceptor
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

### Client Installation

To set up a client that can connect to a remote server:

```bash
# Clone the repository (if you haven't already)
git clone https://github.com/drascom/projects.git
cd projects/ollama-request-interceptor

# Make all scripts executable
chmod +x install-client.sh uninstall-client.sh

# Run the installer
./install-client.sh
```

The client installer will:
1. Create a configuration file for connecting to the server
2. Set up an SSH tunnel script to securely connect to the server

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

If your Ollama server is running on a different port or host, edit the `.env` file:

```bash
nano ~/ollama-interceptor/.env
```

Change the `TARGET_URL` variable to your desired URL.

### Setting Up Remote Access (Server)

To enable remote access to the web UI, edit the `.env` file:

```bash
nano ~/ollama-interceptor/.env
```

Set the following options:

```
ALLOW_REMOTE=true
ENABLE_AUTH=true
AUTH_USERNAME=your_username
AUTH_PASSWORD=your_secure_password
SERVER_HOST=your_server_hostname_or_ip  # Optional, will auto-detect if not set
```

Then restart the service:

```bash
# For Linux
sudo systemctl restart mitmweb

# For macOS
launchctl stop com.ollama.interceptor
launchctl start com.ollama.interceptor
```

### Configuring Client Connection

To configure a client to connect to a remote server, edit the client configuration:

```bash
nano ~/ollama-interceptor-client/client.env
```

Set the following options:

```
SERVER_HOST=your_server_hostname_or_ip
SERVER_WEB_UI_PORT=8081  # Match the server's WEB_UI_PORT
AUTH_USERNAME=your_username  # If authentication is enabled on the server
AUTH_PASSWORD=your_password  # If authentication is enabled on the server
LOCAL_PORT=8082  # The local port to use for the SSH tunnel
```

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

## Client-Server Usage

### Setting Up the Server

1. Install the interceptor on the server machine using the server installation instructions
2. Edit the `.env` file to enable remote access and authentication
3. Restart the service to apply the changes
4. Make sure the server's firewall allows connections to the Web UI port (default: 8081)

### Connecting from a Client

1. Install the client component using the client installation instructions
2. Edit the client configuration to point to your server
3. Run the connection script:

```bash
~/ollama-interceptor-client/client-connect.sh
```

This will establish an SSH tunnel to the server and open the web UI in your browser.

## Uninstallation

### Server Uninstallation

#### macOS

```bash
launchctl unload ~/Library/LaunchAgents/com.ollama.interceptor.plist
rm ~/Library/LaunchAgents/com.ollama.interceptor.plist
rm -rf ~/ollama-interceptor
```

#### Linux

```bash
sudo systemctl stop mitmweb
sudo systemctl disable mitmweb
sudo rm /etc/systemd/system/mitmweb.service
sudo systemctl daemon-reload
rm -rf ~/ollama-interceptor
```

### Client Uninstallation

```bash
rm -rf ~/ollama-interceptor-client
```

Or use the uninstall script:

```bash
chmod +x uninstall-client.sh
./uninstall-client.sh
```

## Security Considerations

### Local Usage

When used locally, this tool is relatively safe as it only listens on localhost by default.

### Remote Usage

When enabling remote access, consider the following security measures:

1. **Always enable authentication** when allowing remote access
2. Use strong, unique passwords for the web UI
3. Consider using a firewall to restrict access to the web UI port
4. The SSH tunnel used by the client provides an encrypted connection to the server
5. For production environments, consider setting up a VPN or other secure network instead of exposing the web UI directly

This tool is intended for development and debugging purposes only. Even with authentication enabled, it should be used with caution in production environments.

## Changelog

### Latest Updates
- Added client-server support for remote monitoring
- Added authentication for web UI access
- Added SSH tunnel for secure remote connections
- Improved documentation with architecture diagram and security considerations

## Last Updated

May 15, 2025