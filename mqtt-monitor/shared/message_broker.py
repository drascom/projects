"""
Message Broker for Inter-Component Communication

This module provides a simple message broker for communication between
the MQTT client and GUI components.
"""

import threading
import queue
import logging
import time
from collections import deque

logger = logging.getLogger("mqtt-monitor")

# Set debug level for message broker to reduce noise
logging.getLogger("shared.message_broker").setLevel(logging.WARNING)

class MessageBroker:
    """
    A simple message broker for inter-component communication
    """
    _instance = None
    _lock = threading.Lock()

    def __new__(cls):
        with cls._lock:
            if cls._instance is None:
                cls._instance = super(MessageBroker, cls).__new__(cls)
                cls._instance._initialized = False
            return cls._instance

    def __init__(self):
        if self._initialized:
            return

        # Initialize the broker
        self.mqtt_messages = deque(maxlen=100)  # Store last 100 messages
        self.publish_queue = queue.Queue()  # Queue for messages to be published
        self.subscribers = []  # List of callback functions
        self.topics = set()  # Set of unique topics
        self.stats = {
            'connection_count': 0,
            'topic_count': 0,
            'message_count': 0,
            'errors': []
        }
        self._lock = threading.Lock()
        self._initialized = True
        logger.info("Message broker initialized")

    def add_mqtt_message(self, message):
        """
        Add a received MQTT message to the broker

        Args:
            message (dict): Message with topic, payload, and timestamp
        """
        with self._lock:
            self.mqtt_messages.append(message)
            self.topics.add(message['topic'])
            self.stats['message_count'] += 1
            self.stats['topic_count'] = len(self.topics)

        # Notify subscribers
        for callback in self.subscribers:
            try:
                callback(message)
            except Exception as e:
                logger.error(f"Error in subscriber callback: {e}")

    def queue_message_for_publish(self, topic, payload):
        """
        Queue a message to be published to the MQTT broker

        Args:
            topic (str): MQTT topic
            payload (str): Message payload
        """
        self.publish_queue.put({
            'topic': topic,
            'payload': payload
        })
        logger.debug(f"Queued message for publishing to {topic}")

    def get_message_for_publish(self, block=True, timeout=None):
        """
        Get the next message to be published

        Args:
            block (bool): Whether to block until a message is available
            timeout (float): Timeout in seconds if blocking

        Returns:
            dict or None: Message with topic and payload, or None if timeout
        """
        try:
            return self.publish_queue.get(block=block, timeout=timeout)
        except queue.Empty:
            return None

    def subscribe(self, callback):
        """
        Subscribe to receive MQTT messages

        Args:
            callback (callable): Function to call with each new message
        """
        if callback not in self.subscribers:
            self.subscribers.append(callback)
            logger.debug(f"Added subscriber, total: {len(self.subscribers)}")

    def unsubscribe(self, callback):
        """
        Unsubscribe from receiving MQTT messages

        Args:
            callback (callable): Function to remove from subscribers
        """
        if callback in self.subscribers:
            self.subscribers.remove(callback)
            logger.debug(f"Removed subscriber, total: {len(self.subscribers)}")

    def get_recent_messages(self, count=None):
        """
        Get recent MQTT messages

        Args:
            count (int): Number of messages to return, or None for all

        Returns:
            list: Recent messages
        """
        with self._lock:
            if count is None:
                return list(self.mqtt_messages)
            return list(self.mqtt_messages)[-count:]

    def get_topics(self):
        """
        Get all unique topics

        Returns:
            list: List of topics
        """
        with self._lock:
            return list(self.topics)

    def get_stats(self):
        """
        Get broker statistics

        Returns:
            dict: Statistics about messages and connections
        """
        with self._lock:
            return self.stats.copy()

    def update_connection_count(self, count):
        """
        Update the MQTT connection count

        Args:
            count (int): New connection count
        """
        with self._lock:
            self.stats['connection_count'] = count

    def add_error(self, error):
        """
        Add an error message to the log

        Args:
            error (str): Error message
        """
        with self._lock:
            self.stats['errors'].append(error)
            # Keep only the last 10 errors
            if len(self.stats['errors']) > 10:
                self.stats['errors'] = self.stats['errors'][-10:]

# Create a singleton instance
message_broker = MessageBroker()
