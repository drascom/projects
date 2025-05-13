__version__ = "1.3.0"

from flask import Flask, render_template, request, jsonify, send_from_directory
from flask_socketio import SocketIO, emit
from datetime import datetime
import os
import sys
from debug_bar import debug_bar, debug_bar_middleware
import logging
import time
from dotenv import load_dotenv
from logging.handlers import RotatingFileHandler
from werkzeug.serving import run_simple

# Add the parent directory to the path so we can import shared modules
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from shared.message_broker import message_broker

# Load environment variables
load_dotenv()

# Configuration
DEBUG = os.getenv('DEBUG', 'False').lower() in ('true', '1', 't')
HOST = os.getenv('GUI_HOST', '0.0.0.0')
PORT = int(os.getenv('GUI_PORT', 9876))
MQTT_BROKER = os.getenv('MQTT_BROKER', 'localhost')
MQTT_PORT = int(os.getenv('MQTT_PORT', 1883))
MQTT_USERNAME = os.getenv('MQTT_USERNAME')
MQTT_PASSWORD = os.getenv('MQTT_PASSWORD')
MQTT_KEEPALIVE = int(os.getenv('MQTT_KEEPALIVE', 60))
MQTT_VERSION = os.getenv('MQTT_VERSION', '3.1.1')

# Set up logging
log_level = logging.DEBUG if DEBUG else logging.INFO
logging.basicConfig(level=log_level)
if not DEBUG:
    handler = RotatingFileHandler('mqttui.log', maxBytes=10000, backupCount=1)
    handler.setLevel(logging.INFO)
    logging.getLogger('').addHandler(handler)

# Silence Werkzeug request logs
logging.getLogger('werkzeug').setLevel(logging.ERROR)

app = Flask(__name__, static_url_path='/static')
app.config['SECRET_KEY'] = os.getenv('SECRET_KEY', 'your-secret-key')

# Configure SocketIO with logging disabled
socketio = SocketIO(app, async_mode='threading', logger=False, engineio_logger=False)

MQTT_RC_CODES = {
    0: "Connection successful",
    1: "Connection refused - incorrect protocol version",
    2: "Connection refused - invalid client identifier",
    3: "Connection refused - server unavailable",
    4: "Connection refused - bad username or password",
    5: "Connection refused - not authorised",
    # MQTT v5 specific codes
    16: "Connection refused - no matching subscribers",
    17: "Connection refused - no subscription existed",
    128: "Connection refused - unspecified error",
    129: "Connection refused - malformed packet",
    130: "Connection refused - protocol error",
    131: "Connection refused - implementation specific error",
    132: "Connection refused - unsupported protocol version",
    133: "Connection refused - client identifier not valid",
    134: "Connection refused - bad user name or password",
    135: "Connection refused - not authorized",
    136: "Connection refused - server unavailable",
    137: "Connection refused - server busy",
    138: "Connection refused - banned",
    139: "Connection refused - server shutting down",
    140: "Connection refused - bad authentication method",
    141: "Connection refused - topic name invalid",
    142: "Connection refused - packet too large",
    143: "Connection refused - quota exceeded",
    144: "Connection refused - payload format invalid",
    145: "Connection refused - retain not supported",
    146: "Connection refused - QoS not supported",
    147: "Connection refused - use another server",
    148: "Connection refused - server moved",
    149: "Connection refused - connection rate exceeded"
}

app.before_request(debug_bar_middleware)

@app.after_request
def after_request(response):
    debug_bar.record('request', 'status_code', response.status_code)
    debug_bar.end_request()
    return response

# Initialize message broker for communication with MQTT client
logging.info("Using shared message broker for MQTT communication")

# Track active WebSocket connections
active_websockets = 0

@socketio.on('connect')
def handle_connect():
    global active_websockets
    active_websockets += 1
    debug_bar.record('performance', 'active_websockets', active_websockets)
    logging.info(f"WebSocket connected. Total active: {active_websockets}")

@socketio.on('disconnect')
def handle_disconnect():
    global active_websockets
    active_websockets -= 1
    debug_bar.record('performance', 'active_websockets', active_websockets)
    logging.info(f"WebSocket disconnected. Total active: {active_websockets}")

# Function to forward MQTT messages to WebSocket clients
def forward_mqtt_message(message):
    socketio.emit('mqtt_message', message)
    debug_bar.record('mqtt', 'last_message', message)
    logging.debug(f"Forwarded MQTT message to WebSocket: {message}")

# Subscribe to messages from the message broker
message_broker.subscribe(forward_mqtt_message)

@app.route('/')
def index():
    # Get recent messages and topics from the message broker
    messages = message_broker.get_recent_messages()
    topics = message_broker.get_topics()
    return render_template('index.html', messages=messages, topics=topics)

@app.route('/publish', methods=['POST'])
def publish_message():
    topic = request.form['topic']
    message = request.form['message']
    # Queue the message for publishing by the MQTT client
    message_broker.queue_message_for_publish(topic, message)
    debug_bar.record('mqtt', 'last_publish', {'topic': topic, 'message': message})
    return jsonify(success=True)

@app.route('/stats')
def get_stats():
    # Get stats from the message broker
    return jsonify(message_broker.get_stats())

@app.route('/static/<path:path>')
def send_static(path):
    return send_from_directory('static', path)

@app.route('/debug-bar')
def get_debug_bar_data():
    try:
        data = debug_bar.get_data()
        return jsonify(data)
    except Exception as e:
        logging.error(f"Error fetching debug bar data: {e}")
        return jsonify({"error": "Failed to fetch debug bar data"}), 500

@app.route('/toggle-debug-bar', methods=['POST'])
def toggle_debug_bar():
    if debug_bar.enabled:
        debug_bar.disable()
    else:
        debug_bar.enable()
    return jsonify(enabled=debug_bar.enabled)

@app.route('/record-client-performance', methods=['POST'])
def record_client_performance():
    data = request.json
    debug_bar.record('performance', 'page_load_time', f"{data['pageLoadTime']}ms")
    debug_bar.record('performance', 'dom_ready_time', f"{data['domReadyTime']}ms")
    return jsonify(success=True)

@app.route('/version')
def get_version():
    return jsonify({'version': __version__})

@app.route('/device-info')
def get_device_info():
    # Get the device ID from environment variables
    device_id = os.getenv('DEVICE_ID', 'unknown')
    return jsonify({'device_id': device_id})

if __name__ == '__main__' or __name__ == 'app':
    # No need to connect to MQTT broker directly, the MQTT client handles that
    socketio.run(app, host=HOST, port=PORT, debug=DEBUG)
