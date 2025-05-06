# MQTT Device Monitor

A modular application that monitors various device components and publishes statistics to an MQTT broker, with an integrated web interface for visualization.

## Features

- **GPU Monitoring**: GPU statistics (utilization, memory, temperature)
  - NVIDIA GPUs on Linux/Windows
  - Apple Silicon GPUs on macOS
- **GPU Fan Control**: Automatic fan speed control for NVIDIA GPUs
  - Customizable temperature-based profiles
  - Hysteresis support to prevent oscillation
  - JSON configuration file for easy customization
- **CPU Monitoring**: CPU usage, frequency, and temperature
  - Cross-platform support (Linux, Windows, macOS)
  - Apple Silicon optimized on macOS ARM64
- **Web Interface**: Real-time visualization of MQTT messages and device statistics

## Quick Installation

The easiest way to install MQTT Device Monitor is using the unified management script:

```bash
curl -fsSL https://raw.githubusercontent.com/drascom/projects/main/mqtt-monitor/manage.sh | bash
```

This single command will:
- Detect your operating system (Linux or macOS)
- Install required dependencies
- Clone the repository to your home directory
- Set up a Python virtual environment using uv
- Configure MQTT connection settings interactively
- Create a system service for automatic startup

If you need to install system packages on Linux, run with sudo:

```bash
curl -fsSL https://raw.githubusercontent.com/drascom/projects/main/mqtt-monitor/manage.sh | sudo bash
```

### Management Commands

The `manage.sh` script provides several options:

```bash
# Install or update the application (default)
./manage.sh

# Reconfigure the application (update .env settings)
./manage.sh --reconfigure

# Uninstall the application
./manage.sh --uninstall

# Show help
./manage.sh --help
```

### One-Line Uninstallation

You can also uninstall the application with a single command:

```bash
curl -fsSL https://raw.githubusercontent.com/drascom/projects/main/mqtt-monitor/manage.sh | bash -s -- --uninstall
```

If you installed with sudo (on Linux), use:

```bash
curl -fsSL https://raw.githubusercontent.com/drascom/projects/main/mqtt-monitor/manage.sh | sudo bash -s -- --uninstall
```

This will:
- Stop and remove the service
- Prompt you to optionally delete the installation directory

### Configure Mosquitto Broker (if using local broker)

If you're running Mosquitto on the same machine, configure it for WebSockets:

```bash
# Edit configuration
sudo nano /etc/mosquitto/conf.d/default.conf

# Add these lines:
listener 1883
protocol mqtt

listener 9001
protocol websockets

# For authentication (recommended)
allow_anonymous false
password_file /etc/mosquitto/passwd

# Create a user
sudo mosquitto_passwd -c /etc/mosquitto/passwd <username>
sudo chown mosquitto:mosquitto /etc/mosquitto/passwd

# Restart Mosquitto
sudo systemctl restart mosquitto
```

**Important:** The GUI requires WebSockets (port 9001) to function properly.

## Configuration

The installation script will automatically create a `.env` file with your configuration settings. If you need to modify these settings later, you can either:

1. Run the reconfiguration command:
   ```bash
   ./manage.sh --reconfigure
   ```

2. Or manually edit the `.env` file:
   ```bash
   nano ~/projects/mqtt-monitor/.env
   ```

Example configuration:
```
# Common MQTT settings
MQTT_BROKER=localhost
MQTT_PORT=9001  # Use 9001 for WebSockets (GUI) or 1883 for standard MQTT
MQTT_USERNAME=your_username
MQTT_PASSWORD=your_password
MQTT_DEBUG=False

# MQTT client settings
DEVICE_ID=computer1  # Automatically set to your hostname
MQTT_INTERVAL=5
MQTT_VERSION=3.1.1
MQTT_KEEPALIVE=60

# GUI settings
GUI_HOST=0.0.0.0
GUI_PORT=9876
DEBUG=False
```

3. The application will automatically detect and use all available monitoring modules (currently gpu and cpu).

4. The application publishes statistics to the following topics:
   - **Combined Data**: All module data is combined into a single message and published to `devices/{DEVICE_ID}` (e.g., `devices/computer1`)
   - **Module Data**: Each module's data is published to `devices/{DEVICE_ID}/{MODULE}` (e.g., `devices/computer1/gpu`)

   This device-first approach organizes all data by device, making it easy to subscribe to all data for a specific device or just specific modules for a device.

### GPU Fan Control Configuration

The application includes a GPU fan control module for NVIDIA GPUs that automatically adjusts fan speeds based on temperature. This feature helps optimize cooling and noise levels.

To configure the fan control, you can edit the `fan_config.json` file:

```json
{
    "time_to_update": 5,
    "temperature_ranges": [
        {
            "min_temperature": 0,
            "max_temperature": 40,
            "fan_speed": 30,
            "hysteresis": 2
        },
        {
            "min_temperature": 40,
            "max_temperature": 50,
            "fan_speed": 40,
            "hysteresis": 2
        },
        {
            "min_temperature": 50,
            "max_temperature": 60,
            "fan_speed": 50,
            "hysteresis": 2
        },
        {
            "min_temperature": 60,
            "max_temperature": 70,
            "fan_speed": 70,
            "hysteresis": 2
        },
        {
            "min_temperature": 70,
            "max_temperature": 80,
            "fan_speed": 85,
            "hysteresis": 2
        },
        {
            "min_temperature": 80,
            "max_temperature": 100,
            "fan_speed": 100,
            "hysteresis": 2
        }
    ]
}
```

**Configuration Parameters:**
- `time_to_update`: Time in seconds between fan speed updates (default: 5)
- `temperature_ranges`: Array of temperature range objects with the following properties:
  - `min_temperature`: Minimum temperature in Celsius (inclusive)
  - `max_temperature`: Maximum temperature in Celsius (inclusive)
  - `fan_speed`: Fan speed percentage (0-100) to set when temperature is in this range
  - `hysteresis`: Temperature change required to trigger a fan speed update (prevents rapid oscillation)

For more detailed information, see [README_fan.md](./README_fan.md).

### Running the Application

The application can run in several modes:

#### Run both MQTT client and GUI simultaneously (recommended)

```bash
python main.py
```

This is the recommended way to run the application. It will start the MQTT client in a background thread and the GUI in the main thread. The application will automatically ensure the MQTT client is properly connected before the GUI becomes fully operational.

#### Run MQTT client and GUI separately

If needed, you can also start the MQTT client and GUI in separate terminals:

```bash
# Terminal 1: Start the MQTT client
python main.py --mqtt

# Terminal 2: Start the GUI (after MQTT client is running)
python main.py --gui
```

#### Run only the MQTT client

```bash
python main.py --mqtt
```

#### Run only the GUI

```bash
python main.py --gui
```

#### Specify a custom port

```bash
python main.py --port 8080
```

If the specified port is already in use, the application will automatically find an available port. The default port is 9876.

#### Enable debug mode

To enable debug mode, set `MQTT_DEBUG=True` in your `.env` file:

```
# In your .env file
MQTT_DEBUG=True
```

This enables verbose logging, showing detailed information about module loading, MQTT connections, and data processing. Useful for troubleshooting issues.

#### Service Management

The installation script automatically sets up a system service. Here are the commands to manage it:

**For Linux (systemd):**

```bash
# Start the service
sudo systemctl start projects/mqtt-monitor@<username>.service

# Stop the service
sudo systemctl stop projects/mqtt-monitor@<username>.service

# Check status
sudo systemctl status projects/mqtt-monitor@<username>.service

# View logs
journalctl -u projects/mqtt-monitor@<username>.service -f
```
Replace `<username>` with your actual username.

**For macOS (launchd):**

```bash
# Start the service
launchctl load ~/Library/LaunchAgents/com.projects/mqtt-monitor.plist

# Stop the service
launchctl unload ~/Library/LaunchAgents/com.projects/mqtt-monitor.plist

# Check status
launchctl list | grep projects/mqtt-monitor
```

## Platform Support

The application is designed to work across multiple platforms:

- **Linux**: Full support for CPU and NVIDIA GPU monitoring
- **macOS**:
  - Intel: CPU monitoring with limited GPU support
  - Apple Silicon (ARM64): Optimized CPU and GPU monitoring
- **Windows**: Basic CPU monitoring with NVIDIA GPU support

## Architecture

The application uses a modular architecture with the following components:

### MQTT Client

The MQTT client is responsible for:
- Collecting system metrics from various modules (CPU, GPU, etc.)
- Publishing metrics to the MQTT broker
- Subscribing to all topics on the MQTT broker
- Forwarding received messages to the GUI via a message broker

### GUI

The GUI provides a web interface for:
- Visualizing MQTT messages in real-time
- Displaying device statistics
- Publishing custom MQTT messages
- Monitoring connection status

### Message Broker

A central message broker handles communication between the MQTT client and GUI:
- The MQTT client handles all MQTT communication with the external broker
- The GUI receives data from the MQTT client via the message broker
- The GUI sends publish requests to the MQTT client via the message broker

This architecture centralizes all MQTT logic in the MQTT client component, making the system more maintainable and reducing the number of connections to the MQTT broker.

### Debug Bar

The application includes a debug bar that provides real-time information about:
- MQTT connection status
- Message statistics
- Performance metrics
- Request details

To toggle the debug bar, click the 🪲 Debug button in the bottom right corner of the web interface.

## Logging

The application uses a configurable logging system:

- Set `DEBUG=true` in the .env file to enable detailed logging
- In non-debug mode, only warnings and errors are logged
- Request logs from the web interface are suppressed by default
- MQTT message details are not logged to keep the console clean

## MQTT Message Format

The application publishes JSON messages in two formats:

### Combined Data Format (Topic: `devices/{DEVICE_ID}`)

```json
{
  "device_id": "computer1",
  "timestamp": 1623456789,
  "modules": {
    "gpu": {
      "gpu_util": 45,
      "mem_util": 30,
      "mem_total": 8192,
      "mem_used": 2458,
      "temp": 65
    },
    "cpu": {
      "cpu_util": 25,
      "per_cpu_util": [20, 30, 25, 22],
      "cpu_freq": 2500,
      "temp": 45
    },
    "fan": {
      "gpus": [
        {
          "index": 0,
          "name": "NVIDIA GeForce RTX 3080",
          "temperature": 65,
          "fans": [
            {
              "index": 0,
              "speed": 70,
              "target_speed": 70
            },
            {
              "index": 1,
              "speed": 70,
              "target_speed": 70
            }
          ]
        }
      ]
    }
  }
}
```

### Module-Specific Format (Topic: `devices/{DEVICE_ID}/{MODULE}`)

#### GPU Module (Topic: `devices/computer1/gpu`)

```json
{
  "gpu_util": 45,
  "mem_util": 30,
  "mem_total": 8192,
  "mem_used": 2458,
  "temp": 65
}
```

#### CPU Module (Topic: `devices/computer1/cpu`)

```json
{
  "cpu_util": 25,
  "per_cpu_util": [20, 30, 25, 22],
  "cpu_freq": 2500,
  "temp": 45
}
```

#### Fan Control Module (Topic: `devices/computer1/fan`)

```json
{
  "gpus": [
    {
      "index": 0,
      "name": "NVIDIA GeForce RTX 3080",
      "temperature": 65,
      "fans": [
        {
          "index": 0,
          "speed": 70,
          "target_speed": 70
        },
        {
          "index": 1,
          "speed": 70,
          "target_speed": 70
        }
      ]
    }
  ]
}
```

### Subscribing to Monitors

You can subscribe to different levels using MQTT wildcards:

- All devices and all modules: `devices/#`
- All data for a specific device: `devices/computer1/#`
- A specific module on all devices: `devices/+/gpu`
- A specific module on a specific device: `devices/computer1/gpu`
