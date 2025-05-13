"""
Shared message broker for communication between MQTT client and GUI
"""

import threading
import queue
import time
from collections import deque
import logging

logger = logging.getLogger("message-broker")

class MessageBroker:
    """
    A shared message broker for communication between MQTT client and GUI
    """
    def __init__(self, max_messages=100):
        """
        Initialize the message broker
        
        Args:
            max_messages (int): Maximum number of messages to store
        """
        self.messages = deque(maxlen=max_messages)
        self.topics = set()
        self.subscribers = []
        self.publish_queue = queue.Queue()
        self.lock = threading.Lock()
        self.connection_count = 0
        self.errors = deque(maxlen=10)
        self.stats = {
            'messages_received': 0,
            'messages_published': 0,
            'last_message_time': None,
            'connection_status': 'disconnected'
        }
    
    def add_mqtt_message(self, message):
        """
        Add a message received from MQTT
        
        Args:
            message (dict): Message with topic, payload, and timestamp
        """
        with self.lock:
            self.messages.append(message)
            self.topics.add(message['topic'])
            self.stats['messages_received'] += 1
            self.stats['last_message_time'] = message['timestamp']
            
            # Notify subscribers
            for subscriber in self.subscribers:
                try:
                    subscriber(message)
                except Exception as e:
                    logger.error(f"Error notifying subscriber: {e}")
    
    def get_recent_messages(self, limit=None):
        """
        Get recent messages
        
        Args:
            limit (int): Maximum number of messages to return
            
        Returns:
            list: Recent messages
        """
        with self.lock:
            if limit:
                return list(self.messages)[-limit:]
            return list(self.messages)
    
    def get_topics(self):
        """
        Get all topics
        
        Returns:
            list: All topics
        """
        with self.lock:
            return list(self.topics)
    
    def subscribe(self, callback):
        """
        Subscribe to messages
        
        Args:
            callback (function): Function to call when a message is received
        """
        with self.lock:
            self.subscribers.append(callback)
    
    def unsubscribe(self, callback):
        """
        Unsubscribe from messages
        
        Args:
            callback (function): Function to unsubscribe
        """
        with self.lock:
            if callback in self.subscribers:
                self.subscribers.remove(callback)
    
    def queue_message_for_publish(self, topic, payload):
        """
        Queue a message for publishing
        
        Args:
            topic (str): Topic to publish to
            payload (str): Message payload
        """
        self.publish_queue.put({
            'topic': topic,
            'payload': payload
        })
        logger.debug(f"Queued message for publishing to {topic}")
    
    def get_message_for_publish(self, timeout=None):
        """
        Get a message for publishing
        
        Args:
            timeout (float): Timeout in seconds
            
        Returns:
            dict: Message with topic and payload
        """
        try:
            message = self.publish_queue.get(block=True, timeout=timeout)
            self.stats['messages_published'] += 1
            return message
        except queue.Empty:
            return None
    
    def update_connection_count(self, count):
        """
        Update the connection count
        
        Args:
            count (int): New connection count
        """
        with self.lock:
            self.connection_count = count
            self.stats['connection_status'] = 'connected' if count > 0 else 'disconnected'
    
    def add_error(self, error):
        """
        Add an error
        
        Args:
            error (str): Error message
        """
        with self.lock:
            self.errors.append({
                'message': error,
                'timestamp': time.time()
            })
    
    def get_stats(self):
        """
        Get broker statistics
        
        Returns:
            dict: Broker statistics
        """
        with self.lock:
            stats = self.stats.copy()
            stats['connection_count'] = self.connection_count
            stats['errors'] = list(self.errors)
            stats['queue_size'] = self.publish_queue.qsize()
            return stats

# Create a singleton instance
message_broker = MessageBroker()
