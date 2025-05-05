"""
GPU Fan Control Module for NVIDIA GPUs

This module controls NVIDIA GPU fan speeds based on temperature thresholds.
It requires the py3nvml library and NVIDIA drivers to be installed.
"""

import json
import os
import time
import logging
from pathlib import Path

# Set up logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler("/tmp/nvidia_fan_control.log"),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger("fan_control")

# Try to import NVML
try:
    import py3nvml.py3nvml as nvml
    NVML_AVAILABLE = True
except ImportError:
    NVML_AVAILABLE = False
    logger.warning("py3nvml not installed. GPU fan control will not be available.")

# Configuration class
class FanConfig:
    def __init__(self, config_file=None):
        self.time_to_update = 5  # Default update interval in seconds
        self.temperature_ranges = [
            {"min_temperature": 0, "max_temperature": 40, "fan_speed": 30, "hysteresis": 2},
            {"min_temperature": 40, "max_temperature": 50, "fan_speed": 40, "hysteresis": 2},
            {"min_temperature": 50, "max_temperature": 60, "fan_speed": 50, "hysteresis": 2},
            {"min_temperature": 60, "max_temperature": 70, "fan_speed": 70, "hysteresis": 2},
            {"min_temperature": 70, "max_temperature": 80, "fan_speed": 85, "hysteresis": 2},
            {"min_temperature": 80, "max_temperature": 100, "fan_speed": 100, "hysteresis": 2}
        ]
        
        # Load from file if provided
        if config_file:
            self.load_from_file(config_file)
    
    def load_from_file(self, config_file):
        """Load configuration from a JSON file"""
        try:
            with open(config_file, 'r') as f:
                config_data = json.load(f)
                
            if 'time_to_update' in config_data:
                self.time_to_update = config_data['time_to_update']
                
            if 'temperature_ranges' in config_data:
                self.temperature_ranges = config_data['temperature_ranges']
                
            logger.info(f"Loaded fan control configuration from {config_file}")
        except Exception as e:
            logger.error(f"Failed to load config file: {e}")

# Fan control class
class FanController:
    def __init__(self, config=None):
        self.config = config or FanConfig()
        self.prev_temps = {}  # {gpu_index: {fan_index: temp}}
        self.prev_speeds = {}  # {gpu_index: {fan_index: speed}}
        self.nvml_initialized = False
        self.device_count = 0
        self.fan_control_enabled = False
        
        # Try to initialize NVML
        if NVML_AVAILABLE:
            try:
                nvml.nvmlInit()
                self.nvml_initialized = True
                self.device_count = nvml.nvmlDeviceGetCount()
                logger.info(f"NVML initialized. Found {self.device_count} GPU(s)")
                
                # Initialize previous temps and speeds
                for i in range(self.device_count):
                    self.prev_temps[i] = {}
                    self.prev_speeds[i] = {}
                
                self.fan_control_enabled = True
            except Exception as e:
                logger.error(f"Failed to initialize NVML: {e}")
    
    def __del__(self):
        """Clean up NVML on destruction"""
        if self.nvml_initialized:
            try:
                nvml.nvmlShutdown()
                logger.info("NVML shutdown successfully")
            except Exception as e:
                logger.error(f"Error shutting down NVML: {e}")
    
    def get_fan_speed_for_temperature(self, temp, prev_temp, prev_speed):
        """Determine appropriate fan speed based on temperature and hysteresis"""
        for r in self.config.temperature_ranges:
            if temp > r['min_temperature'] and temp <= r['max_temperature']:
                # Check if we should change the speed based on hysteresis
                if abs(temp - prev_temp) >= r['hysteresis'] or prev_speed != r['fan_speed']:
                    return r['fan_speed']
        
        # If no range matches or hysteresis prevents change, keep previous speed
        return prev_speed
    
    def update_fan_speeds(self):
        """Update fan speeds based on current temperatures"""
        if not self.fan_control_enabled:
            return {}
        
        fan_data = {}
        
        try:
            for gpu_idx in range(self.device_count):
                device = nvml.nvmlDeviceGetHandleByIndex(gpu_idx)
                
                # Get GPU name
                try:
                    gpu_name = nvml.nvmlDeviceGetName(device)
                except:
                    gpu_name = f"GPU {gpu_idx}"
                
                # Get temperature
                try:
                    temp = nvml.nvmlDeviceGetTemperature(device, nvml.NVML_TEMPERATURE_GPU)
                except Exception as e:
                    logger.error(f"Failed to get temperature for GPU {gpu_idx}: {e}")
                    continue
                
                # Assume 2 fans per GPU (adjust as needed)
                fan_count = 2
                
                # Initialize data structures if needed
                if gpu_idx not in fan_data:
                    fan_data[gpu_idx] = {
                        "name": gpu_name,
                        "temperature": temp,
                        "fans": {}
                    }
                
                # Initialize prev_temps and prev_speeds for this GPU if needed
                if gpu_idx not in self.prev_temps:
                    self.prev_temps[gpu_idx] = {}
                    self.prev_speeds[gpu_idx] = {}
                
                # Update each fan
                for fan_idx in range(fan_count):
                    # Initialize if needed
                    if fan_idx not in self.prev_temps[gpu_idx]:
                        self.prev_temps[gpu_idx][fan_idx] = temp
                        self.prev_speeds[gpu_idx][fan_idx] = 0
                    
                    # Calculate new fan speed
                    new_speed = self.get_fan_speed_for_temperature(
                        temp, 
                        self.prev_temps[gpu_idx][fan_idx],
                        self.prev_speeds[gpu_idx][fan_idx]
                    )
                    
                    # Update fan speed if it changed
                    if new_speed != self.prev_speeds[gpu_idx][fan_idx]:
                        try:
                            # Set manual control mode
                            nvml.nvmlDeviceSetFanControlPolicy(device, fan_idx, 1)
                            
                            # Set the fan speed
                            nvml.nvmlDeviceSetFanSpeed_v2(device, fan_idx, new_speed)
                            
                            logger.info(f"Updated GPU {gpu_idx} Fan {fan_idx}: Temp={temp}°C, Fan Speed={new_speed}%")
                            
                            # Update previous values
                            self.prev_speeds[gpu_idx][fan_idx] = new_speed
                        except Exception as e:
                            logger.error(f"Failed to set fan speed for GPU {gpu_idx} Fan {fan_idx}: {e}")
                    
                    # Store current fan data
                    fan_data[gpu_idx]["fans"][fan_idx] = {
                        "speed": new_speed,
                        "target_speed": new_speed
                    }
                    
                    # Update previous temperature
                    self.prev_temps[gpu_idx][fan_idx] = temp
            
            return fan_data
        
        except Exception as e:
            logger.error(f"Error updating fan speeds: {e}")
            return {}

# Global fan controller instance
_fan_controller = None

def get_fan_controller():
    """Get or create the fan controller singleton"""
    global _fan_controller
    
    if _fan_controller is None:
        # Look for config file in common locations
        config_paths = [
            "config.json",
            "/etc/mqtt-device-monitor/fan_config.json",
            str(Path.home() / ".config/mqtt-device-monitor/fan_config.json")
        ]
        
        config_file = None
        for path in config_paths:
            if os.path.exists(path):
                config_file = path
                break
        
        config = FanConfig(config_file)
        _fan_controller = FanController(config)
    
    return _fan_controller

def get_stats(device_id):
    """
    Get GPU fan statistics and control fan speeds
    
    Args:
        device_id (str): The device identifier
        
    Returns:
        dict: Fan statistics or error information
    """
    if not NVML_AVAILABLE:
        return {
            "device_id": device_id,
            "module": "fan",
            "error": "NVML library not available"
        }
    
    try:
        controller = get_fan_controller()
        fan_data = controller.update_fan_speeds()
        
        # Format the data for MQTT
        result = {
            "device_id": device_id,
            "module": "fan",
            "gpus": []
        }
        
        for gpu_idx, gpu_data in fan_data.items():
            gpu_info = {
                "index": gpu_idx,
                "name": gpu_data["name"],
                "temperature": gpu_data["temperature"],
                "fans": []
            }
            
            for fan_idx, fan_info in gpu_data["fans"].items():
                gpu_info["fans"].append({
                    "index": fan_idx,
                    "speed": fan_info["speed"],
                    "target_speed": fan_info["target_speed"]
                })
            
            result["gpus"].append(gpu_info)
        
        return result
    except Exception as e:
        logger.error(f"Error getting fan stats: {e}")
        return {
            "device_id": device_id,
            "module": "fan",
            "error": str(e)
        }

def get_mock_stats(device_id):
    """
    Get mock GPU fan statistics for testing
    
    Args:
        device_id (str): The device identifier
        
    Returns:
        dict: Mock fan statistics
    """
    return {
        "device_id": device_id,
        "module": "fan",
        "gpus": [
            {
                "index": 0,
                "name": "NVIDIA GeForce RTX 3080",
                "temperature": 65,
                "fans": [
                    {
                        "index": 0,
                        "speed": 70,
                        "target_speed": 70
                    },
                    {
                        "index": 1,
                        "speed": 70,
                        "target_speed": 70
                    }
                ]
            }
        ]
    }
