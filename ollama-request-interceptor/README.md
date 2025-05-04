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
| (API: 11434)     |                     | (Web UI)         |
+------------------+                     +------------------+
         ↑                                        ↑
         |                                        |
+------------------+     Direct HTTP     +------------------+
| Mitmproxy        | <------------------ | Web Browser      |
| (Interceptor)    |     Connection      | (Direct Access)  |
+------------------+                     +------------------+
```

The client connects directly to the server's web interface. For security, it's recommended to enable authentication on the server.

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

# Make the script executable & Run the installer
chmod +x install-interceptor.sh
./install-interceptor.sh


The script will:
1. Install required dependencies
2. Set up a Python virtual environment
3. Install mitmproxy
4. Create necessary configuration files
5. Set up a system service to run the proxy

### Installation for Different Modes

The interceptor can be installed in three different modes:

1. **Local Mode** (default): Run locally without remote access
2. **Server Mode**: Run as a server that can be accessed remotely
3. **Client Mode**: Connect to a remote server

To install in any mode:

```bash
# Clone the repository (if you haven't already)
git clone https://github.com/drascom/projects.git
cd projects/ollama-request-interceptor

# Make the script executable
chmod +x install-interceptor.sh

# Run the installer
./install-interceptor.sh
```

After installation, edit the `.env` file to set your desired mode:

```bash
nano ~/ollama-interceptor/.env
```

Set the `MODE` parameter to one of: `local`, `server`, or `client`. For client mode, you'll also need to set the `SERVER_HOST` parameter.

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

If you prefer to run the interceptor manually without using the system service:

```bash
cd ~/ollama-interceptor
./start-interceptor.sh
```

## Customization

### Changing Basic Configuration

You can customize various settings by editing the `.env` file:

```bash
nano ~/ollama-interceptor/.env
```

Common settings to change:
- `MODE`: Set to `local`, `server`, or `client`
- `TARGET_URL`: The URL of your Ollama server
- `INTERCEPT_PORT`: The port to run the interceptor on
- `WEB_UI_PORT`: The port for the web UI
- `SERVER_HOST`: The hostname or IP of the server (for client mode)
- `ENABLE_AUTH`: Set to `true` to enable authentication (recommended for server mode)
- `AUTH_USERNAME` and `AUTH_PASSWORD`: Credentials for authentication

### Configuring Different Modes

#### Server Mode Configuration

To set up a server that can be accessed remotely, edit the `.env` file:

```bash
nano ~/ollama-interceptor/.env
```

Set the following options:

```
MODE=server
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

#### Client Mode Configuration

To configure a client to connect to a remote server, edit the `.env` file:

```bash
nano ~/ollama-interceptor/.env
```

Set the following options:

```
MODE=client
SERVER_HOST=your_server_hostname_or_ip
WEB_UI_PORT=8081  # Match the server's WEB_UI_PORT
```

If the server has authentication enabled, also set:

```
AUTH_USERNAME=your_username
AUTH_PASSWORD=your_password
```

Then start the interceptor:

```bash
~/ollama-interceptor/start-interceptor.sh
```

This will open your browser directly to the server's web interface.

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

1. Install the interceptor on the server machine
2. Edit the `.env` file to set `MODE=server` and configure authentication
3. Restart the service to apply the changes
4. Make sure the server's firewall allows connections to the Web UI port (default: 8081)

### Connecting from a Client

1. Install the interceptor on the client machine
2. Edit the `.env` file to set `MODE=client` and configure the server connection
3. Run the interceptor:

```bash
~/ollama-interceptor/start-interceptor.sh
```

This will open your browser directly to the server's web interface.

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

### Uninstalling Any Mode

The uninstallation process is the same for all modes:

```bash
chmod +x uninstall-interceptor.sh
./uninstall-interceptor.sh
```

## Security Considerations

### Local Usage

When used locally, this tool is relatively safe as it only listens on localhost by default.

### Remote Usage

When enabling remote access, consider the following security measures:

1. **Always enable authentication** when allowing remote access
2. Use strong, unique passwords for the web UI
3. Consider using a firewall to restrict access to the web UI port
4. For additional security, consider setting up HTTPS using a reverse proxy
5. For production environments, consider setting up a VPN or other secure network instead of exposing the web UI directly

This tool is intended for development and debugging purposes only. Even with authentication enabled, it should be used with caution in production environments.

## Changelog

### Latest Updates
- Added client-server support for remote monitoring
- Added authentication for web UI access
- Implemented direct browser connection to server (no SSH tunnel required)
- Unified configuration with a single .env file for all modes
- Improved documentation with architecture diagram and security considerations

## Last Updated

May 15, 2025