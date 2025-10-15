#!/usr/bin/env python3
"""Test AI Assistant API module imports"""

import sys
sys.path.insert(0, 'lib')

print("Testing AI Assistant API imports...")

try:
    from galaxy.webapps.galaxy.api import ai_assistant
    print("✓ ai_assistant API module imported successfully")
    print(f"  Module path: {ai_assistant.__file__}")
    print(f"  Router: {ai_assistant.router}")
except ImportError as e:
    print(f"✗ Failed to import ai_assistant API: {e}")
    import traceback
    traceback.print_exc()
except Exception as e:
    print(f"✗ Error during import: {e}")
    import traceback
    traceback.print_exc()

print("\nChecking router endpoints...")
try:
    from galaxy.webapps.galaxy.api import ai_assistant
    print(f"Router routes: {[route.path for route in ai_assistant.router.routes]}")
except Exception as e:
    print(f"✗ Failed to list routes: {e}")
    import traceback
    traceback.print_exc()

print("\nAll tests completed!")
