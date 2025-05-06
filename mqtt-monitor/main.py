#!/usr/bin/env python3
"""
MQTT Device Monitor - Main Entry Point

This script serves as the main entry point for the MQTT Device Monitor application.
It can run either the MQTT client, the GUI, or both components.

Usage:
    python main.py --mqtt     # Run only the MQTT client
    python main.py --gui      # Run only the GUI
    python main.py            # Run both components

Debugging can be enabled by setting MQTT_DEBUG=True in the .env file.
"""

import argparse
import os
import sys
import threading
import time
import logging
import socket
import signal
from dotenv import load_dotenv

# Configure logging
def configure_logging():
    # Load environment variables first to ensure we have access to MQTT_DEBUG
    load_dotenv()

    # Check if debug mode is enabled in .env file
    debug_mode = os.getenv('MQTT_DEBUG', 'False').lower() in ('true', '1', 't')

    log_level = logging.DEBUG if debug_mode else logging.INFO

    logging.basicConfig(
        level=log_level,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        handlers=[
            logging.StreamHandler(sys.stdout)
        ]
    )
    logger = logging.getLogger("mqtt-monitor")

    # Set logger level based on debug mode
    if debug_mode:
        logger.setLevel(logging.DEBUG)
        print(f"Debug mode enabled - verbose logging activated (MQTT_DEBUG=True)")
    else:
        # Silence various logs in non-debug mode
        logging.getLogger('werkzeug').setLevel(logging.ERROR)
        logging.getLogger('socketio').setLevel(logging.ERROR)
        logging.getLogger('engineio').setLevel(logging.ERROR)

        # In non-debug mode, reduce verbosity of our logger
        logger.setLevel(logging.WARNING)

    return logger

# Initialize logger with default settings (will be reconfigured in main)
logger = logging.getLogger("mqtt-monitor")

# Load environment variables
load_dotenv()

def is_port_in_use(port):
    """Check if a port is in use"""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        return s.connect_ex(('localhost', port)) == 0

def find_available_port(start_port, max_attempts=10):
    """Find an available port starting from start_port"""
    port = start_port
    for _ in range(max_attempts):
        if not is_port_in_use(port):
            return port
        port += 1
    return None

def run_mqtt_client(in_thread=False):
    """Run the MQTT client component"""
    try:
        logger.info("Starting MQTT client...")
        # Import here to avoid circular imports
        sys.path.append(os.path.join(os.path.dirname(__file__), 'mqtt'))

        if in_thread:
            # Use the thread-safe version without signal handlers
            from mqtt.mqtt_client import run_mqtt_client_thread
            run_mqtt_client_thread()
        else:
            # Use the original version with signal handlers
            from mqtt import app as mqtt_app
            # The mqtt_app module runs automatically when imported

        logger.info("MQTT client started")
    except Exception as e:
        logger.error(f"Failed to start MQTT client: {e}")
        return False
    return True

def run_gui():
    """Run the GUI component"""
    try:
        logger.info("Starting GUI...")
        # Import here to avoid circular imports
        sys.path.append(os.path.join(os.path.dirname(__file__), 'gui'))
        from gui import app as gui_app

        # Get configuration from environment
        host = os.getenv('GUI_HOST', '0.0.0.0')
        port = int(os.getenv('GUI_PORT', 9876))
        debug = os.getenv('DEBUG', 'False').lower() in ('true', '1', 't')

        # Check if the specified port is available, find an alternative if not
        if is_port_in_use(port):
            logger.warning(f"Port {port} is already in use, searching for an available port")
            available_port = find_available_port(port + 1)
            if available_port:
                logger.info(f"Found available port: {available_port}")
                port = available_port
            else:
                logger.error("Could not find an available port")
                return False

        # Run the Flask app
        try:
            logger.info(f"Starting GUI on port {port}")
            gui_app.socketio.run(gui_app.app, host=host, port=port, debug=debug, log_output=False)
            logger.info(f"GUI started successfully on port {port}")
            return True
        except Exception as e:
            logger.error(f"Failed to start GUI: {e}")
            return False
    except Exception as e:
        logger.error(f"Failed to start GUI: {e}")
        return False

def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(description='MQTT Device Monitor')
    parser.add_argument('--mqtt', action='store_true', help='Run only the MQTT client')
    parser.add_argument('--gui', action='store_true', help='Run only the GUI')
    parser.add_argument('--port', type=int, help='Port for the GUI (overrides .env setting)')
    args = parser.parse_args()

    # Configure logging based on MQTT_DEBUG in .env
    global logger
    logger = configure_logging()

    # If port is specified via command line, set it in the environment
    if args.port:
        os.environ['GUI_PORT'] = str(args.port)
        logger.info(f"Using port {args.port} from command line arguments")

    # If no arguments provided, run both components
    if not args.mqtt and not args.gui:
        args.mqtt = True
        args.gui = True

    mqtt_thread = None

    try:
        # Start MQTT client if requested
        if args.mqtt:
            if args.gui:
                # Run MQTT client in a separate thread if we're also running the GUI
                mqtt_thread = threading.Thread(target=lambda: run_mqtt_client(in_thread=True))
                mqtt_thread.daemon = True
                mqtt_thread.start()
                logger.info("MQTT client started in background thread")
                # Give the MQTT client a moment to initialize before starting the GUI
                time.sleep(2)
            else:
                # Run MQTT client in the main thread
                run_mqtt_client(in_thread=False)

        # Start GUI if requested
        if args.gui:
            run_gui()

    except KeyboardInterrupt:
        logger.info("Shutting down...")
    except Exception as e:
        logger.error(f"An error occurred: {e}")

    # Stop the MQTT client if it's running in a thread
    if mqtt_thread and mqtt_thread.is_alive():
        try:
            from mqtt.mqtt_client import stop_mqtt_client
            stop_mqtt_client()
            mqtt_thread.join(timeout=5)
        except Exception as e:
            logger.error(f"Error stopping MQTT client: {e}")

    logger.info("Shutdown complete")

def signal_handler(sig, frame):
    """Handle Ctrl+C and other signals"""
    logger.info("Received shutdown signal, exiting...")
    try:
        from mqtt.mqtt_client import stop_mqtt_client
        stop_mqtt_client()
    except Exception as e:
        logger.error(f"Error stopping MQTT client: {e}")
    sys.exit(0)

if __name__ == "__main__":
    # Register signal handlers in the main thread
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    main()
