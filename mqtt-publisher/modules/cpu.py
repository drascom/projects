import psutil

def get_stats(device_id):
    """
    Get CPU statistics
    
    Args:
        device_id (str): The device identifier
        
    Returns:
        dict: CPU statistics
    """
    try:
        # Get CPU usage as a percentage
        cpu_percent = psutil.cpu_percent(interval=1)
        
        # Get per-core CPU usage
        per_cpu_percent = psutil.cpu_percent(interval=1, percpu=True)
        
        # Get CPU frequency
        cpu_freq = psutil.cpu_freq()
        if cpu_freq:
            current_freq = cpu_freq.current
        else:
            current_freq = 0
            
        # Get CPU temperature if available
        try:
            if hasattr(psutil, "sensors_temperatures"):
                temps = psutil.sensors_temperatures()
                if temps:
                    # Different systems report CPU temp under different keys
                    for name, entries in temps.items():
                        if name.lower() in ['coretemp', 'cpu_thermal', 'k10temp', 'acpitz']:
                            temp = entries[0].current
                            break
                    else:
                        # If no recognized temperature sensor found, use the first one
                        temp = next(iter(temps.values()))[0].current
                else:
                    temp = 0
            else:
                temp = 0
        except Exception:
            temp = 0
            
        return {
            "device_id": device_id,
            "module": "cpu",
            "cpu_util": cpu_percent,
            "per_cpu_util": per_cpu_percent,
            "cpu_freq": current_freq,
            "temp": temp
        }
    except Exception as e:
        print(f"Error getting CPU stats: {e}")
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
        "cpu_freq": 2500,
        "temp": 45
    }
