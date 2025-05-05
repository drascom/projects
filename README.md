# Multi-Project Repository

This repository contains multiple independent projects, each in its own directory.

## Projects

### Ollama Request Interceptor
A tool to intercept and monitor API requests between clients and Ollama server using mitmproxy.
- [Go to project](./ollama-request-interceptor)

### MQTT Device Monitor
A modular application that monitors various device components (CPU, GPU) and publishes statistics to an MQTT broker, with an integrated web interface for visualization.
- [Go to project](./mqtt-monitor)
- **Features**:
  - Cross-platform support (Linux, Windows, macOS)
  - GPU monitoring (NVIDIA, Apple Silicon)
  - CPU monitoring with temperature and frequency tracking
  - GPU fan control with customizable temperature-based profiles
  - Real-time web interface for data visualization
  - Automatic service installation
  - JSON configuration for fan control settings

<!-- Add more projects as they are created -->

## Structure

Each project is contained in its own directory and has its own documentation, dependencies, and configuration.

```
repository/
├── ollama-request-interceptor/
│   ├── README.md
│   ├── install-interceptor.sh
│   └── ...
├── mqtt-monitor/
│   ├── README.md
│   ├── main.py
│   ├── manage.sh
│   ├── mqtt/
│   ├── gui/
│   └── ...
└── ...
```

## Getting Started

Navigate to the specific project directory you're interested in and follow the instructions in that project's README.md file.

### MQTT Device Monitor - Fan Control

The MQTT Device Monitor includes a GPU fan control module for NVIDIA GPUs that allows you to define custom temperature ranges and corresponding fan speeds. This feature helps optimize cooling and noise levels based on your preferences.

#### Fan Configuration

The fan control settings are defined in a JSON configuration file (`fan_config.json`):

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
        // Additional temperature ranges...
    ]
}
```

- `time_to_update`: Time in seconds between fan speed updates
- `temperature_ranges`: Array of temperature range objects with:
  - `min_temperature`: Minimum temperature in Celsius
  - `max_temperature`: Maximum temperature in Celsius
  - `fan_speed`: Fan speed percentage (0-100)
  - `hysteresis`: Temperature change required to trigger a fan speed update

For more details, see the [Fan Control Documentation](./mqtt-monitor/README_fan.md).

## Contributing

When contributing to this repository, please make sure to:

1. Work in the appropriate project directory
2. Follow the contribution guidelines for the specific project
3. Keep project dependencies isolated to their respective directories

## License

Each project may have its own license. Please check the individual project directories for license information.