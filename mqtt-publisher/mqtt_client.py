import json
import time
import ssl
import paho.mqtt.client as mqtt
import sys
from dotenv import load_dotenv
import os
from modules import loader
import threading
import logging
from datetime import datetime

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from shared.message_broker import message_broker

debug_mode = os.getenv('MQTT_DEBUG', 'False').lower() in ('true', '1', 't')
if debug_mode:
    logging.getLogger("paho.mqtt").setLevel(logging.DEBUG)
else:
    logging.getLogger("paho.mqtt").setLevel(logging.WARNING)

logger = logging.getLogger("mqtt-monitor")

running = True

def run_mqtt_client_thread():
    global running
    load_dotenv()

    BROKER = os.getenv('MQTT_BROKER')
    DEVICE_ID = os.getenv('DEVICE_ID', 'default')
    INTERVAL = int(os.getenv('MQTT_INTERVAL', 5))
    CLIENT_ID = f"device-monitor-{DEVICE_ID}-{time.time()}"
    MQTT_PORT = int(os.getenv('MQTT_PORT', 1883))
    MQTT_USERNAME = os.getenv('MQTT_USERNAME')
    MQTT_PASSWORD = os.getenv('MQTT_PASSWORD')

    AVAILABLE_MODULES = loader.get_available_modules()
    logger.info(f"Available monitoring modules: {', '.join(AVAILABLE_MODULES)}")

    def on_message(client, userdata, msg):
        try:
            payload = msg.payload.decode()
        except UnicodeDecodeError:
            payload = msg.payload.hex()

        message = {
            'topic': msg.topic,
            'payload': payload,
            'timestamp': datetime.now().isoformat()
        }
        message_broker.add_mqtt_message(message)
        logger.debug(f"MQTT message received on topic: {message['topic']}")

    def on_connect(client, userdata, flags, rc):
        if rc == 0:
            logger.info(f"Connected to MQTT broker at {BROKER}")
            client.subscribe("#")
            message_broker.update_connection_count(1)
        else:
            logger.error(f"Failed to connect to MQTT broker, return code: {rc}")
            message_broker.add_error(f"Failed to connect to MQTT broker, return code: {rc}")

    def on_disconnect(client, userdata, rc):
        if rc != 0:
            logger.warning(f"Unexpected disconnection. Will auto-reconnect")
            message_broker.add_error(f"Unexpected disconnection from MQTT broker, return code: {rc}")
        message_broker.update_connection_count(0)

    def on_publish(client, userdata, mid):
        logger.debug(f"Message {mid} published")

    client = mqtt.Client(client_id=CLIENT_ID, transport="websockets")
    client.on_connect = on_connect
    client.on_disconnect = on_disconnect
    client.on_publish = on_publish
    client.on_message = on_message

    if MQTT_PORT in [8883, 443, 8443]:
        client.tls_set(cert_reqs=ssl.CERT_NONE)
        client.tls_insecure_set(True)

    if MQTT_USERNAME and MQTT_PASSWORD:
        client.username_pw_set(MQTT_USERNAME, MQTT_PASSWORD)

    client.ws_set_options(path="/mqtt")
    client.reconnect_delay_set(min_delay=1, max_delay=30)

    try:
        logger.info(f"Attempting to connect to MQTT broker at {BROKER} using WebSockets")
        client.connect(BROKER, MQTT_PORT, 60)
        client.loop_start()
    except Exception as e:
        logger.error(f"Connection error: {e}")
        return

    logger.info(f"Publishing combined stats for device '{DEVICE_ID}' to {BROKER}")
    logger.info(f"Monitoring modules: {', '.join(AVAILABLE_MODULES)}")
    logger.info(f"Interval: {INTERVAL} seconds")

    DEVICE_TOPIC = f"devices/{DEVICE_ID}"

    def publish_handler():
        while running:
            try:
                message = message_broker.get_message_for_publish(timeout=1.0)
                if message and running:
                    topic = message['topic']
                    payload = message['payload']
                    logger.info(f"Publishing message from GUI to {topic}")
                    result = client.publish(topic, payload)
                    if result.rc != 0:
                        logger.error(f"Failed to publish message from GUI, return code: {result.rc}")
                        message_broker.add_error(f"Failed to publish to {topic}, return code: {result.rc}")
            except Exception as e:
                logger.error(f"Error in publish handler: {e}")
                time.sleep(1)

    publish_thread = threading.Thread(target=publish_handler)
    publish_thread.daemon = True
    publish_thread.start()

    while running:
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
                        logger.warning(f"Using mock data for {module_name}...")
                        stats = module.get_mock_stats(DEVICE_ID)
                except Exception as e:
                    logger.error(f"Error getting {module_name} stats: {e}")
                    logger.info(f"Using mock data for {module_name}...")
                    stats = module.get_mock_stats(DEVICE_ID)

                stats.pop("device_id", None)
                stats.pop("module", None)

                combined_data["modules"][module_name] = stats

            logger.info(f"Publishing combined stats to {DEVICE_TOPIC}")
            result = client.publish(DEVICE_TOPIC, json.dumps(combined_data, indent=2))  # Pretty print here

            if result.rc != 0:
                logger.error(f"Failed to publish to {DEVICE_TOPIC}, return code: {result.rc}")

            time.sleep(INTERVAL)

        except Exception as e:
            logger.error(f"Error in main loop: {e}")
            time.sleep(INTERVAL)

    logger.info("Disconnecting from MQTT broker...")
    client.disconnect()
    client.loop_stop()

    if publish_thread.is_alive():
        publish_thread.join(timeout=2.0)

    logger.info("MQTT client stopped")

def stop_mqtt_client():
    global running
    running = False
