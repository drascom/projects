import json
import time
import ssl
import paho.mqtt.client as mqtt
import signal
import sys
from dotenv import load_dotenv
import os
from modules import loader

# Load environment variables
load_dotenv()

BROKER = os.getenv('MQTT_BROKER')
DEVICE_ID = os.getenv('DEVICE_ID', 'default')
INTERVAL = int(os.getenv('MQTT_INTERVAL', 5))
CLIENT_ID = f"device-monitor-{DEVICE_ID}-{time.time()}"
MQTT_PORT = int(os.getenv('MQTT_PORT', 443))
MQTT_USERNAME = os.getenv('MQTT_USERNAME')
MQTT_PASSWORD = os.getenv('MQTT_PASSWORD')

AVAILABLE_MODULES = loader.get_available_modules()
print(f"Available monitoring modules: {', '.join(AVAILABLE_MODULES)}")

def on_connect(_, __, ___, rc):
    if rc == 0:
        print(f"Connected to MQTT broker at {BROKER}")
    else:
        print(f"Failed to connect to MQTT broker, return code: {rc}")

def on_disconnect(_, __, rc):
    if rc != 0:
        print(f"Unexpected disconnection. Will auto-reconnect")

def on_publish(_, __, ___):
    pass

client = mqtt.Client(client_id=CLIENT_ID, transport="websockets")
client.on_connect = on_connect
client.on_disconnect = on_disconnect
client.on_publish = on_publish

client.tls_set(cert_reqs=ssl.CERT_NONE)
client.tls_insecure_set(True)

client.username_pw_set(MQTT_USERNAME, MQTT_PASSWORD)
client.ws_set_options(path="/mqtt")
client.reconnect_delay_set(min_delay=1, max_delay=30)

def signal_handler(*_):
    print("Disconnecting from MQTT broker...")
    client.disconnect()
    client.loop_stop()
    sys.exit(0)

signal.signal(signal.SIGINT, signal_handler)

try:
    print(f"Attempting to connect to MQTT broker at {BROKER} using WebSockets")
    client.connect(BROKER, MQTT_PORT, 60)
    client.loop_start()
except Exception as e:
    print(f"Connection error: {e}")
    sys.exit(1)

print(f"Publishing combined stats for device '{DEVICE_ID}' to {BROKER}")
print(f"Topic: devices/{DEVICE_ID}")
print(f"Monitoring modules: {', '.join(AVAILABLE_MODULES)}")
print(f"Interval: {INTERVAL} seconds")
print("Press Ctrl+C to exit")

DEVICE_TOPIC_BASE = f"devices/{DEVICE_ID}"

while True:
    try:
        combined_data = {
            "device_id": DEVICE_ID,
            "timestamp": int(time.time()),
            "modules": {}
        }

        for module_name in AVAILABLE_MODULES:
            module = loader.load_module(module_name)
            if not module:
                continue

            try:
                stats = module.get_stats(DEVICE_ID)
                if "error" in stats:
                    print(f"Using mock data for {module_name}...")
                    stats = module.get_mock_stats(DEVICE_ID)
            except Exception as e:
                print(f"Error getting {module_name} stats: {e}")
                print(f"Using mock data for {module_name}...")
                stats = module.get_mock_stats(DEVICE_ID)

            stats.pop("device_id", None)
            stats.pop("module", None)

            combined_data["modules"][module_name] = stats

        print(f"Publishing combined stats to {DEVICE_TOPIC_BASE}")
        result = client.publish(
            DEVICE_TOPIC_BASE,
            json.dumps(combined_data, indent=2)  # Pretty JSON for tree view
        )

        if result.rc != 0:
            print(f"Failed to publish to {DEVICE_TOPIC_BASE}, return code: {result.rc}")

        time.sleep(INTERVAL)

    except Exception as e:
        print(f"Error in main loop: {e}")
        time.sleep(INTERVAL)
