import json
import paho.mqtt.client as mqtt
from mitmproxy import ctx, http

# MQTT Broker Configuration
MQTT_BROKER_ADDRESS = "192.168.1.213"
MQTT_BROKER_PORT = 1883
MQTT_TOPIC = "traffic/ai"
MQTT_USERNAME = "admin"
MQTT_PASSWORD = "admin" # Be cautious with hardcoding credentials

# Global MQTT client instance
mqtt_client = None

def load(loader):
    global mqtt_client
    mqtt_client = mqtt.Client(client_id="mitmproxy_publisher")
    if MQTT_USERNAME and MQTT_PASSWORD:
        mqtt_client.username_pw_set(MQTT_USERNAME, MQTT_PASSWORD)
    
    try:
        mqtt_client.connect(MQTT_BROKER_ADDRESS, MQTT_BROKER_PORT, 60)
        mqtt_client.loop_start() # Start a background thread to handle network traffic
        ctx.log.info(f"Successfully connected to MQTT broker at {MQTT_BROKER_ADDRESS}:{MQTT_BROKER_PORT}")
    except Exception as e:
        ctx.log.error(f"Failed to connect to MQTT broker: {e}")
        mqtt_client = None # Ensure client is None if connection failed

def request(flow: http.HTTPFlow) -> None:
    """
    Called when a client request has been received.
    """
    if not mqtt_client:
        ctx.log.warn("MQTT client not connected. Skipping request publishing.")
        return

    try:
        request_data = {
            "type": "request",
            "method": flow.request.method,
            "url": flow.request.pretty_url,
            "headers": dict(flow.request.headers),
            "content": flow.request.get_text(strict=False) if flow.request.content else None,
            "timestamp": flow.request.timestamp_start
        }
        payload = json.dumps(request_data, indent=2)
        result = mqtt_client.publish(MQTT_TOPIC + "/request", payload)
        if result.rc == mqtt.MQTT_ERR_SUCCESS:
            ctx.log.info(f"Published request to {flow.request.pretty_url} to {MQTT_TOPIC}/request")
        else:
            ctx.log.error(f"Failed to publish request to MQTT. Return code: {result.rc}")
    except Exception as e:
        ctx.log.error(f"Error processing or publishing request: {e}")

def response(flow: http.HTTPFlow) -> None:
    """
    Called when a server response has been received.
    """
    if not mqtt_client:
        ctx.log.warn("MQTT client not connected. Skipping response publishing.")
        return

    # Ensure request is present, which should always be the case in a response handler
    if not flow.request:
        ctx.log.warn("No request associated with this response. Skipping.")
        return

    try:
        response_data = {
            "type": "response",
            "url": flow.request.pretty_url, # Include URL for context
            "status_code": flow.response.status_code,
            "reason": flow.response.reason,
            "headers": dict(flow.response.headers),
            "content": flow.response.get_text(strict=False) if flow.response.content else None,
            "timestamp": flow.response.timestamp_end,
            "duration_ms": int((flow.response.timestamp_end - flow.request.timestamp_start) * 1000) if flow.request.timestamp_start and flow.response.timestamp_end else None
        }
        payload = json.dumps(response_data, indent=2)
        result = mqtt_client.publish(MQTT_TOPIC + "/response", payload)
        if result.rc == mqtt.MQTT_ERR_SUCCESS:
            ctx.log.info(f"Published response from {flow.request.pretty_url} to {MQTT_TOPIC}/response")
        else:
            ctx.log.error(f"Failed to publish response to MQTT. Return code: {result.rc}")

    except Exception as e:
        ctx.log.error(f"Error processing or publishing response: {e}")

def done():
    """
    Called when mitmproxy is shutting down.
    """
    global mqtt_client
    if mqtt_client:
        mqtt_client.loop_stop()
        mqtt_client.disconnect()
        ctx.log.info("Disconnected from MQTT broker.")

addons = [
    load # Call load function to initialize
]

# To run mitmproxy with this script:
# mitmweb --mode reverse:127.0.0.1@11434 -p 11434 --web-port 8080 --web-host 0.0.0.0 --allow-hosts ".*" -s /path/to/this/script/mqtt_publisher.py
# Example:
# mitmweb --mode reverse:127.0.0.1@11434 -p 11434 --web-port 8080 --web-host 0.0.0.0 --allow-hosts ".*" -s ./ollama-request-interceptor/mqtt_publisher.py