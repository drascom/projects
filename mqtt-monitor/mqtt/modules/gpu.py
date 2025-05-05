import subprocess

def get_stats(device_id):
    """
    Get NVIDIA GPU statistics
    
    Args:
        device_id (str): The device identifier
        
    Returns:
        dict: GPU statistics or error information
    """
    try:
        output = subprocess.check_output([
            "nvidia-smi",
            "--query-gpu=utilization.gpu,utilization.memory,memory.total,memory.used,temperature.gpu",
            "--format=csv,noheader,nounits"
        ]).decode("utf-8").strip()
        gpu_info = output.split(", ")
        return {
            "device_id": device_id,
            "module": "gpu",
            "gpu_util": int(gpu_info[0]),
            "mem_util": int(gpu_info[1]),
            "mem_total": int(gpu_info[2]),
            "mem_used": int(gpu_info[3]),
            "temp": int(gpu_info[4])
        }
    except Exception as e:
        print(f"Error getting GPU stats: {e}")
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
        "mem_total": 8192,
        "mem_used": 2458,
        "temp": 65
    }
