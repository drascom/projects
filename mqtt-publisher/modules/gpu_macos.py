"""
GPU monitoring module for macOS systems (Apple Silicon)
"""
import subprocess
import platform
import re
import os

# Print debug message when this module is imported if debug mode is enabled
debug_mode = os.getenv('MQTT_DEBUG', 'False').lower() in ('true', '1', 't')
if debug_mode:
    print("DEBUG GPU_MACOS: Module loaded")

def get_stats(device_id):
    """
    Get Apple Silicon GPU statistics

    Args:
        device_id (str): The device identifier

    Returns:
        dict: GPU statistics or error information
    """
    # Check if debug mode is enabled
    debug_mode = os.getenv('MQTT_DEBUG', 'False').lower() in ('true', '1', 't')
    if debug_mode:
        print(f"DEBUG GPU_MACOS: get_stats called for device {device_id}")
    try:
        # Get GPU information using system_profiler
        try:
            # This works on both Intel and Apple Silicon Macs
            gpu_info = subprocess.check_output(["system_profiler", "SPDisplaysDataType"]).decode()

            # Extract GPU model
            model_match = re.search(r"Chipset Model: (.+)", gpu_info)
            gpu_model = model_match.group(1) if model_match else "Unknown GPU"

            # Extract GPU vendor
            vendor_match = re.search(r"Vendor: (.+?)\s*\(|$", gpu_info)
            gpu_vendor = vendor_match.group(1).strip() if vendor_match else "Apple"

            # Extract VRAM if available
            vram_match = re.search(r"VRAM \(Total\): (\d+) MB", gpu_info)
            if vram_match:
                mem_total = int(vram_match.group(1))
            else:
                # For Apple Silicon, estimate based on device type
                if "M1" in gpu_model or "M2" in gpu_model or "M3" in gpu_model or "M4" in gpu_model:
                    if "Pro" in gpu_model or "Max" in gpu_model:
                        mem_total = 16384  # 16GB for Pro/Max models
                    elif "Ultra" in gpu_model:
                        mem_total = 32768  # 32GB for Ultra models
                    else:
                        mem_total = 8192   # 8GB for base models
                else:
                    mem_total = 4096  # Default for older models

            # Use activity monitor data to estimate GPU usage
            # Use ps to get WindowServer process which correlates with GPU activity
            ps_output = subprocess.check_output(
                ["ps", "-A", "-o", "%cpu", "-o", "command"],
                stderr=subprocess.DEVNULL
            ).decode("utf-8")

            # Find WindowServer CPU usage as a proxy for GPU activity
            gpu_util = 0
            for line in ps_output.splitlines():
                if "WindowServer" in line:
                    parts = line.strip().split()
                    if parts and parts[0].replace('.', '').isdigit():
                        window_server_cpu = float(parts[0])
                        # Estimate GPU utilization based on WindowServer CPU usage
                        # This is a rough approximation
                        gpu_util = min(int(window_server_cpu * 2), 100)
                        break

            # For memory usage, estimate based on GPU utilization
            mem_util = min(gpu_util + 10, 100)
            mem_used = int(mem_total * (mem_util / 100))

            # Estimate temperature based on GPU utilization
            temp = 35 + (gpu_util / 100 * 30)  # Estimate between 35°C (idle) and 65°C (full load)

            return {
                "device_id": device_id,
                "module": "gpu",
                "gpu_util": gpu_util,
                "mem_util": mem_util,
                "mem_total": mem_total,
                "mem_used": mem_used,
                "temp": temp,
                "model": gpu_model,
                "vendor": gpu_vendor
            }
        except Exception as e:
            print(f"Error getting GPU stats from activity monitor: {e}")
            return {"error": str(e)}
    except Exception as e:
        print(f"Error getting Apple Silicon GPU stats: {e}")
        return {"error": str(e)}

def get_mock_stats(device_id):
    """
    Get mock GPU statistics for testing

    Args:
        device_id (str): The device identifier

    Returns:
        dict: Mock GPU statistics
    """
    return {
        "device_id": device_id,
        "module": "gpu",
        "gpu_util": 45,
        "mem_util": 30,
        "mem_total": 16384,  # 16GB for Pro models
        "mem_used": 4915,
        "temp": 65,
        "model": "Apple M4 Pro",
        "vendor": "Apple"
    }
