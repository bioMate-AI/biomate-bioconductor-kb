#!/usr/bin/env python3
"""
Test that tool_auto_installer can find auto-discovered tools.
"""

import sys
from pathlib import Path

# Add backend to path
backend_path = Path(__file__).parent.parent / "backend"
sys.path.insert(0, str(backend_path))

from lib.galaxy.ai.tool_auto_installer import ToolAutoInstaller

def test_find_auto_discovered_tool():
    """Test that auto_discovered tools can be found."""

    # Initialize installer
    galaxy_root = "/home/yzhang/biomate/backend"  # Not used for this test
    tools_root = "/home/yzhang/biomate/backend/tools"

    installer = ToolAutoInstaller(
        galaxy_root=galaxy_root,
        biomate_tools_root=tools_root
    )

    # Test finding auto_dash
    print("Testing auto-discovered tool finding...")
    print(f"Tools root: {installer.biomate_tools_root}")
    print()

    # Try to find auto_dash
    result = installer._find_tool_in_biomate_repo("auto_dash")

    if result:
        print(f"✅ Found auto_dash at: {result}")
        print(f"   File exists: {result.exists()}")
        print(f"   File size: {result.stat().st_size} bytes")
        return True
    else:
        print(f"❌ Could not find auto_dash")
        return False

if __name__ == '__main__':
    success = test_find_auto_discovered_tool()
    sys.exit(0 if success else 1)
