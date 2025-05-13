# MQTT Publisher

A modular system for collecting device statistics and publishing them to an MQTT broker.

## Overview

MQTT Publisher monitors various system components (CPU, GPU, fans, etc.) and publishes their statistics to an MQTT broker at regular intervals. It features a modular architecture that allows for easy extension with new monitoring modules.

## Features

- Modular architecture for easy extension
- Platform-specific optimizations (macOS, Linux, Windows)
- Automatic fallback to mock data when hardware monitoring fails
- WebSocket support for secure connections
- Configurable publishing interval
- Detailed logging

## Requirements

- Python 3.6+
- MQTT broker (e.g., Mosquitto)
- psutil for system monitoring
- Platform-specific tools for hardware monitoring

## Installation

### Automatic Installation (Recommended)

We provide installation scripts that will set up the MQTT Publisher as a system service:

1. Clone the repository:
   ```bash
   git clone https://github.com/drascom/projects.git
   cd projects/mqtt-publisher
   ```

2. Make the installation script executable:
   ```bash
   chmod +x install.sh
   ```

3. Run the installation script:
   ```bash
   ./install.sh
   ```

   You can also use the dry-run option to see what the script would do without making any changes:
   ```bash
   ./install.sh --dry-run
   ```

The script will:
- Install the MQTT Publisher to `~/mqtt-publisher`
- Create a Python virtual environment using `uv`
- Install all dependencies
- Set up a system service (systemd on Linux, LaunchAgent on macOS)
- Start the service automatically

### Manual Installation

If you prefer to install manually:

1. Clone the repository
2. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```
3. Configure environment variables (see Configuration section)
4. Run the application:
   ```bash
   python optimized_app.py
   ```

## Configuration

Create a `.env` file in the project directory with the following variables:

```
MQTT_BROKER=your_broker_address
MQTT_PORT=443
MQTT_USERNAME=your_username
MQTT_PASSWORD=your_password
DEVICE_ID=your_device_id
MQTT_INTERVAL=5
MQTT_DEBUG=False
```

## Available Modules

The following monitoring modules are available:

- **CPU**: Monitors CPU utilization, frequency, and temperature
- **GPU**: Monitors GPU utilization, memory usage, and temperature
- **Fan**: Controls and monitors fan speeds

Each module has platform-specific implementations for optimal performance on different operating systems.

## Module Architecture

To create a new monitoring module:

1. Create a new Python file in the `modules` directory (e.g., `mymodule.py`)
2. Implement the following functions:
   - `get_stats(device_id)`: Returns a dictionary of statistics
   - `get_mock_stats(device_id)`: Returns mock data when hardware monitoring fails
3. Optionally create platform-specific versions (e.g., `mymodule_macos.py`)

## Usage

### Using the Service

If you installed using the installation script, the MQTT Publisher will run as a system service and start automatically when your system boots.

To manage the service:

**On Linux:**
```bash
# Check status
sudo systemctl status mqtt-publisher

# Start the service
sudo systemctl start mqtt-publisher

# Stop the service
sudo systemctl stop mqtt-publisher

# Restart the service
sudo systemctl restart mqtt-publisher

# View logs
sudo journalctl -u mqtt-publisher -f
```

**On macOS:**
```bash
# Start the service
launchctl start com.user.mqtt-publisher

# Stop the service
launchctl stop com.user.mqtt-publisher

# View logs
cat ~/mqtt-publisher/output.log
cat ~/mqtt-publisher/error.log
```

### Running Manually

If you prefer to run the application manually:

```bash
# If installed using the installation script
~/mqtt-publisher/start.sh

# If installed manually
python optimized_app.py
```

The application will publish combined statistics to the topic `devices/{DEVICE_ID}` at the configured interval.

### Uninstallation

To uninstall the MQTT Publisher:

```bash
cd projects/mqtt-publisher
chmod +x uninstall.sh
./uninstall.sh
```

You can also use the dry-run option to see what the uninstallation script would do without making any changes:
```bash
./uninstall.sh --dry-run
```

This will stop the service and remove all installed files.

## License

[MIT License](LICENSE)
