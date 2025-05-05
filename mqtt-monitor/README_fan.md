# GPU Fan Control Module

This module provides automatic fan speed control for NVIDIA GPUs based on temperature thresholds. It allows you to define custom temperature ranges and corresponding fan speeds to optimize cooling and noise levels.

## Requirements

- NVIDIA GPU with driver support
- py3nvml Python library (included in requirements.txt)
- Linux operating system (Windows support may be limited)

## Configuration

The fan control module uses a JSON configuration file to define temperature ranges and fan speeds. You can place this file in one of the following locations:

1. `config.json` in the current working directory
2. `/etc/mqtt-device-monitor/fan_config.json`
3. `~/.config/mqtt-device-monitor/fan_config.json`

### Configuration Format

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

### Configuration Parameters

- `time_to_update`: Time in seconds between fan speed updates (default: 5)
- `temperature_ranges`: Array of temperature range objects with the following properties:
  - `min_temperature`: Minimum temperature in Celsius (inclusive)
  - `max_temperature`: Maximum temperature in Celsius (inclusive)
  - `fan_speed`: Fan speed percentage (0-100) to set when temperature is in this range
  - `hysteresis`: Temperature change required to trigger a fan speed update (prevents rapid oscillation)

## MQTT Data Format

The fan control module publishes data in the following format:

```json
{
    "device_id": "your-device-id",
    "module": "fan",
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

## Troubleshooting

- Check the log file at `/tmp/nvidia_fan_control.log` for error messages
- Ensure the NVIDIA drivers are properly installed and functioning
- Verify that the py3nvml library is installed
- Make sure your user has permission to control the GPU fans (may require running as root)

## Notes

- Fan control requires administrative privileges on most systems
- Not all GPUs support fan speed control
- The module assumes each GPU has 2 fans by default
