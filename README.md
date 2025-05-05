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
  - Real-time web interface for data visualization
  - Automatic service installation

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

## Contributing

When contributing to this repository, please make sure to:

1. Work in the appropriate project directory
2. Follow the contribution guidelines for the specific project
3. Keep project dependencies isolated to their respective directories

## License

Each project may have its own license. Please check the individual project directories for license information.