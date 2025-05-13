# MQTT GUI

A web-based graphical user interface for monitoring and interacting with MQTT messages.

## Overview

MQTT GUI provides a real-time dashboard for visualizing MQTT messages, publishing messages to topics, and monitoring device statistics. It features a responsive web interface with charts, network visualization, and a debug bar for troubleshooting.

## Features

- Real-time message monitoring
- Interactive topic visualization
- Message publishing interface
- Device statistics dashboard
- Debug bar for troubleshooting
- WebSocket-based real-time updates

## Requirements

- Python 3.6+
- Flask and Flask-SocketIO
- MQTT broker (e.g., Mosquitto)
- Modern web browser

## Installation

1. Clone the repository
2. Install dependencies:
   ```
   pip install -r requirements.txt
   ```
3. Configure environment variables (see Configuration section)
4. Run the application:
   ```
   python app.py
   ```

## Configuration

Create a `.env` file in the project directory with the following variables:

```
DEBUG=False
GUI_HOST=0.0.0.0
GUI_PORT=9876
MQTT_BROKER=localhost
MQTT_PORT=1883
MQTT_USERNAME=your_username
MQTT_PASSWORD=your_password
MQTT_KEEPALIVE=60
MQTT_VERSION=3.1.1
DEVICE_ID=your_device_id
SECRET_KEY=your_secret_key
```

## Usage

1. Open a web browser and navigate to `http://localhost:9876` (or the configured host/port)
2. The dashboard will display real-time MQTT messages
3. Use the publish form to send messages to topics
4. View device statistics in the dashboard
5. Toggle the debug bar for troubleshooting information

## Architecture

The application consists of:
- Flask web server with SocketIO for real-time communication
- Shared message broker for communication with MQTT client
- Debug bar for performance monitoring
- Frontend with Tailwind CSS, Chart.js, and vis-network

## License

[MIT License](LICENSE)
