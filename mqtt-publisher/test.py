"""
Test script for MQTT Uploader
"""

import logging
import sys
import time

# Configure logging
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)

logger = logging.getLogger("mqtt-test")

# Import the app module
try:
    import app
    logger.info("Successfully imported app module")
except Exception as e:
    logger.error(f"Error importing app module: {e}")
    sys.exit(1)

# Run for a short time and then exit
logger.info("Running MQTT uploader test for 30 seconds...")
try:
    time.sleep(30)
    logger.info("Test completed successfully")
except KeyboardInterrupt:
    logger.info("Test interrupted by user")
except Exception as e:
    logger.error(f"Error during test: {e}")
finally:
    logger.info("Test finished")
