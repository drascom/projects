"""
CPU monitoring module for macOS systems (including Apple Silicon)
"""
import subprocess
import re
import psutil
import platform
import os

# Print debug message when this module is imported if debug mode is enabled
debug_mode = os.getenv('MQTT_DEBUG', 'False').lower() in ('true', '1', 't')
if debug_mode:
    print("DEBUG CPU_MACOS: Module loaded")

def get_stats(device_id):
    """
    Get CPU statistics for macOS

    Args:
        device_id (str): The device identifier

    Returns:
        dict: CPU statistics
    """
    # Check if debug mode is enabled
    debug_mode = os.getenv('MQTT_DEBUG', 'False').lower() in ('true', '1', 't')
    if debug_mode:
        print(f"DEBUG CPU_MACOS: get_stats called for device {device_id}")
    try:
        # Get CPU usage as a percentage using psutil (works on all platforms)
        cpu_percent = psutil.cpu_percent(interval=1)

        # Get per-core CPU usage
        per_cpu_percent = psutil.cpu_percent(interval=1, percpu=True)

        # Get CPU model information
        try:
            cpu_model = subprocess.check_output(["sysctl", "-n", "machdep.cpu.brand_string"]).decode().strip()
        except:
            cpu_model = platform.processor()

        # Get CPU frequency - on Apple Silicon, we need to use a different approach
        if platform.processor() == 'arm':
            # For Apple Silicon, use sysctl to get CPU frequency
            try:
                # Get CPU frequency from sysctl
                freq_output = subprocess.check_output(
                    ["sysctl", "-n", "hw.cpufrequency_max"],
                    stderr=subprocess.DEVNULL
                ).decode("utf-8").strip()
                current_freq = int(freq_output) / 1000000  # Convert Hz to MHz
            except:
                # Fallback to a reasonable default for Apple Silicon chips
                current_freq = 3200  # 3.2 GHz is common for M1/M2/M3/M4
        else:
            # For Intel Macs, use psutil
            cpu_freq = psutil.cpu_freq()
            if cpu_freq:
                current_freq = cpu_freq.current
            else:
                current_freq = 0

        # Get CPU temperature
        # macOS doesn't expose CPU temperature through standard APIs
        # We'll use the 'osx-cpu-temp' utility if available, otherwise estimate
        try:
            temp_output = subprocess.check_output(
                ["osx-cpu-temp"],
                stderr=subprocess.DEVNULL
            ).decode("utf-8").strip()
            # Extract the temperature value using regex
            match = re.search(r'(\d+\.\d+)°C', temp_output)
            if match:
                temp = float(match.group(1))
            else:
                temp = 45  # Fallback to a reasonable default
        except:
            # If osx-cpu-temp is not available, use a reasonable estimate based on CPU load
            # This is not accurate but better than nothing
            temp = 35 + (cpu_percent / 100 * 30)  # Estimate between 35°C (idle) and 65°C (full load)

        # Get number of cores
        try:
            physical_cores = int(subprocess.check_output(["sysctl", "-n", "hw.physicalcpu"]).decode().strip())
            logical_cores = int(subprocess.check_output(["sysctl", "-n", "hw.logicalcpu"]).decode().strip())
        except:
            physical_cores = psutil.cpu_count(logical=False)
            logical_cores = psutil.cpu_count(logical=True)

        return {
            "device_id": device_id,
            "module": "cpu",
            "cpu_util": cpu_percent,
            "per_cpu_util": per_cpu_percent,
            "cpu_freq": current_freq,
            "temp": temp,
            "model": cpu_model,
            "physical_cores": physical_cores,
            "logical_cores": logical_cores
        }
    except Exception as e:
        print(f"Error getting macOS CPU stats: {e}")
        return {"error": str(e)}

def get_mock_stats(device_id):
    """
    Get mock CPU statistics for testing

    Args:
        device_id (str): The device identifier

    Returns:
        dict: Mock CPU statistics
    """
    return {
        "device_id": device_id,
        "module": "cpu",
        "cpu_util": 25,
        "per_cpu_util": [20, 30, 25, 22],
        "cpu_freq": 3200,  # Common for M1/M2/M3/M4 chips
        "temp": 45,
        "model": "Apple M4 Pro",
        "physical_cores": 10,
        "logical_cores": 10
    }
