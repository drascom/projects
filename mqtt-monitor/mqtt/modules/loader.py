import importlib
import os
import sys
import platform

def get_available_modules():
    """
    Get a list of available monitoring modules

    Returns:
        list: List of module names
    """
    # Check if debug mode is enabled
    debug_mode = os.getenv('MQTT_DEBUG', 'False').lower() in ('true', '1', 't')

    modules_dir = os.path.dirname(os.path.abspath(__file__))
    if debug_mode:
        print(f"DEBUG LOADER: Modules directory: {modules_dir}")

    try:
        all_files = os.listdir(modules_dir)
        if debug_mode:
            print(f"DEBUG LOADER: All files in modules directory: {all_files}")

        module_files = [f[:-3] for f in all_files
                      if f.endswith('.py') and f != '__init__.py' and f != 'loader.py']
        if debug_mode:
            print(f"DEBUG LOADER: Found module files: {module_files}")

        # Filter out platform-specific modules (they'll be loaded by the base module if needed)
        base_modules = []
        for module in module_files:
            if not (module.endswith('_macos') or module.endswith('_linux') or module.endswith('_windows')):
                base_modules.append(module)

        if debug_mode:
            print(f"DEBUG LOADER: Base modules: {base_modules}")
        return base_modules
    except Exception as e:
        if debug_mode:
            print(f"DEBUG LOADER ERROR: Exception while getting modules: {e}")
        return []

def load_module(module_name):
    """
    Dynamically load a module by name

    Args:
        module_name (str): Name of the module to load

    Returns:
        module: The loaded module or None if not found
    """
    # Check if debug mode is enabled
    debug_mode = os.getenv('MQTT_DEBUG', 'False').lower() in ('true', '1', 't')

    try:
        # Check if there's a platform-specific version of the module
        system = platform.system().lower()
        is_arm = platform.processor() == 'arm'

        if debug_mode:
            print(f"DEBUG LOADER: Loading module {module_name} for system {system}, is_arm={is_arm}")

        # For macOS (Darwin) on ARM64 (Apple Silicon)
        if system == 'darwin' and is_arm:
            try:
                # Try to load the macOS-specific module first
                if debug_mode:
                    print(f"DEBUG LOADER: Trying to load macOS-specific module: {module_name}_macos")
                module = importlib.import_module(f"mqtt.modules.{module_name}_macos")
                if debug_mode:
                    print(f"DEBUG LOADER: Successfully loaded macOS-specific module: {module_name}_macos")
                return module
            except ImportError as e:
                # Fall back to the generic module
                if debug_mode:
                    print(f"DEBUG LOADER: No macOS-specific module for {module_name}, error: {e}")
                    print(f"DEBUG LOADER: Falling back to generic module: {module_name}")
                module = importlib.import_module(f"mqtt.modules.{module_name}")
                if debug_mode:
                    print(f"DEBUG LOADER: Successfully loaded generic module: {module_name}")
                return module

        # For macOS (Darwin) on Intel
        elif system == 'darwin' and not is_arm:
            try:
                # Try to load the macOS-specific module first
                if debug_mode:
                    print(f"DEBUG LOADER: Trying to load macOS-specific module: {module_name}_macos")
                module = importlib.import_module(f"mqtt.modules.{module_name}_macos")
                if debug_mode:
                    print(f"DEBUG LOADER: Successfully loaded macOS-specific module: {module_name}_macos")
                return module
            except ImportError as e:
                # Fall back to the generic module
                if debug_mode:
                    print(f"DEBUG LOADER: No macOS-specific module for {module_name}, error: {e}")
                    print(f"DEBUG LOADER: Falling back to generic module: {module_name}")
                module = importlib.import_module(f"mqtt.modules.{module_name}")
                if debug_mode:
                    print(f"DEBUG LOADER: Successfully loaded generic module: {module_name}")
                return module

        # For Linux
        elif system == 'linux':
            try:
                # Try to load the Linux-specific module first
                if debug_mode:
                    print(f"DEBUG LOADER: Trying to load Linux-specific module: {module_name}_linux")
                module = importlib.import_module(f"mqtt.modules.{module_name}_linux")
                if debug_mode:
                    print(f"DEBUG LOADER: Successfully loaded Linux-specific module: {module_name}_linux")
                return module
            except ImportError as e:
                # Fall back to the generic module
                if debug_mode:
                    print(f"DEBUG LOADER: No Linux-specific module for {module_name}, error: {e}")
                    print(f"DEBUG LOADER: Falling back to generic module: {module_name}")
                module = importlib.import_module(f"mqtt.modules.{module_name}")
                if debug_mode:
                    print(f"DEBUG LOADER: Successfully loaded generic module: {module_name}")
                return module

        # For Windows
        elif system == 'windows':
            try:
                # Try to load the Windows-specific module first
                if debug_mode:
                    print(f"DEBUG LOADER: Trying to load Windows-specific module: {module_name}_windows")
                module = importlib.import_module(f"mqtt.modules.{module_name}_windows")
                if debug_mode:
                    print(f"DEBUG LOADER: Successfully loaded Windows-specific module: {module_name}_windows")
                return module
            except ImportError as e:
                # Fall back to the generic module
                if debug_mode:
                    print(f"DEBUG LOADER: No Windows-specific module for {module_name}, error: {e}")
                    print(f"DEBUG LOADER: Falling back to generic module: {module_name}")
                module = importlib.import_module(f"mqtt.modules.{module_name}")
                if debug_mode:
                    print(f"DEBUG LOADER: Successfully loaded generic module: {module_name}")
                return module

        # For other platforms, use the generic module
        else:
            if debug_mode:
                print(f"DEBUG LOADER: Using generic module for unknown platform: {module_name}")
            module = importlib.import_module(f"mqtt.modules.{module_name}")
            if debug_mode:
                print(f"DEBUG LOADER: Successfully loaded generic module: {module_name}")
            return module

    except ImportError as e:
        if debug_mode:
            print(f"DEBUG LOADER ERROR: Error loading module {module_name}: {e}")
        return None
    except Exception as e:
        if debug_mode:
            print(f"DEBUG LOADER ERROR: Unexpected error loading module {module_name}: {e}")
        return None
