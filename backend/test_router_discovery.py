#!/usr/bin/env python3
"""Test router discovery for AI Assistant API"""

import sys
sys.path.insert(0, 'lib')

from galaxy.web.framework.base import walk_controller_modules

print("Testing router discovery for galaxy.webapps.galaxy.api...")
print("=" * 60)

found_ai_assistant = False
for name, module in walk_controller_modules("galaxy.webapps.galaxy.api"):
    router = getattr(module, "router", None)
    if name == "ai_assistant":
        found_ai_assistant = True
        print(f"\n✓ Found AI Assistant module: {name}")
        print(f"  Module: {module}")
        print(f"  Has router: {router is not None}")
        if router:
            print(f"  Router: {router}")
            print(f"  Routes: {[route.path for route in router.routes]}")
    elif router:
        print(f"  {name}: {len(router.routes)} routes")

print("\n" + "=" * 60)
if found_ai_assistant:
    print("✓ AI Assistant module discovered successfully!")
else:
    print("✗ AI Assistant module NOT found!")
    print("\nChecking if module can be imported manually...")
    try:
        from galaxy.webapps.galaxy.api import ai_assistant
        print(f"✓ Manual import successful: {ai_assistant}")
        print(f"  Has router: {hasattr(ai_assistant, 'router')}")
    except Exception as e:
        print(f"✗ Manual import failed: {e}")
