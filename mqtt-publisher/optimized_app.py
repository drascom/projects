"""
Optimized MQTT Publisher Application
"""

import json
import time
import ssl
import paho.mqtt.client as mqtt
import signal
import sys
from dotenv import load_dotenv
import os
from modules import loader
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)

logger = logging.getLogger("mqtt-publisher")

# Set debug mode
debug_mode = os.getenv('MQTT_DEBUG', 'False').lower() in ('true', '1', 't')
if debug_mode:
    logger.setLevel(logging.DEBUG)
    logging.getLogger("paho.mqtt").setLevel(logging.DEBUG)
else:
    logging.getLogger("paho.mqtt").setLevel(logging.WARNING)

# Load environment variables
load_dotenv()

BROKER = os.getenv('MQTT_BROKER')
DEVICE_ID = os.getenv('DEVICE_ID', 'default')
INTERVAL = int(os.getenv('MQTT_INTERVAL', 5))
CLIENT_ID = f"device-monitor-{DEVICE_ID}-{time.time()}"
MQTT_PORT = int(os.getenv('MQTT_PORT', 1883))
MQTT_USERNAME = os.getenv('MQTT_USERNAME')
MQTT_PASSWORD = os.getenv('MQTT_PASSWORD')

# Get available modules
AVAILABLE_MODULES = loader.get_available_modules()
logger.info(f"Available monitoring modules: {', '.join(AVAILABLE_MODULES)}")

# Pre-load modules
loaded_modules = {}
for module_name in AVAILABLE_MODULES:
    module = loader.load_module(module_name)
    if module:
        loaded_modules[module_name] = module
        logger.info(f"Loaded module: {module_name}")

def on_connect(_, __, ___, rc):
    if rc == 0:
        logger.info(f"Connected to MQTT broker at {BROKER}")
    else:
        logger.error(f"Failed to connect to MQTT broker, return code: {rc}")

def on_disconnect(_, __, rc):
    if rc != 0:
        logger.warning(f"Unexpected disconnection. Will auto-reconnect")

def on_publish(_, __, mid):
    if debug_mode:
        logger.debug(f"Message {mid} published")

# Initialize MQTT client
client = mqtt.Client(client_id=CLIENT_ID)
client.on_connect = on_connect
client.on_disconnect = on_disconnect
client.on_publish = on_publish

# Configure TLS if using secure port
if MQTT_PORT in [8883, 443, 8443]:
    client.tls_set(cert_reqs=ssl.CERT_NONE)
    client.tls_insecure_set(True)

# Set credentials if provided
if MQTT_USERNAME and MQTT_PASSWORD:
    client.username_pw_set(MQTT_USERNAME, MQTT_PASSWORD)

# Configure reconnect behavior
client.reconnect_delay_set(min_delay=1, max_delay=30)

# Handle Ctrl+C gracefully
running = True

def signal_handler(*_):
    global running
    logger.info("Disconnecting from MQTT broker...")
    running = False
    client.disconnect()
    client.loop_stop()
    sys.exit(0)

signal.signal(signal.SIGINT, signal_handler)

# Connect to MQTT broker
try:
    logger.info(f"Attempting to connect to MQTT broker at {BROKER}")
    client.connect(BROKER, MQTT_PORT, 60)
    client.loop_start()
except Exception as e:
    logger.error(f"Connection error: {e}")
    sys.exit(1)

# Main loop
logger.info(f"Publishing combined stats for device '{DEVICE_ID}' to {BROKER}")
logger.info(f"Topic: devices/{DEVICE_ID}")
logger.info(f"Monitoring modules: {', '.join(loaded_modules.keys())}")
logger.info(f"Interval: {INTERVAL} seconds")
logger.info("Press Ctrl+C to exit")

DEVICE_TOPIC_BASE = f"devices/{DEVICE_ID}"

while running:
    try:
        combined_data = {
            "device_id": DEVICE_ID,
            "timestamp": int(time.time()),
            "modules": {}
        }

        for module_name, module in loaded_modules.items():
            try:
                stats = module.get_stats(DEVICE_ID)
                if "error" in stats:
                    logger.warning(f"Using mock data for {module_name}...")
                    stats = module.get_mock_stats(DEVICE_ID)
            except Exception as e:
                logger.error(f"Error getting {module_name} stats: {e}")
                logger.info(f"Using mock data for {module_name}...")
                stats = module.get_mock_stats(DEVICE_ID)

            stats.pop("device_id", None)
            stats.pop("module", None)

            combined_data["modules"][module_name] = stats

        logger.info(f"Publishing combined stats to {DEVICE_TOPIC_BASE}")
        result = client.publish(
            DEVICE_TOPIC_BASE,
            json.dumps(combined_data, indent=2)  # Pretty JSON for tree view
        )

        if result.rc != 0:
            logger.error(f"Failed to publish to {DEVICE_TOPIC_BASE}, return code: {result.rc}")

        time.sleep(INTERVAL)

    except Exception as e:
        logger.error(f"Error in main loop: {e}")
        time.sleep(INTERVAL)

# Clean up
logger.info("Disconnecting from MQTT broker...")
client.disconnect()
client.loop_stop()
logger.info("MQTT client stopped")
