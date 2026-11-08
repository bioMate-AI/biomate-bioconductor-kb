#!/usr/bin/env python3
"""Test AI Assistant module imports

MANUAL DIAGNOSTIC — print-based script, not a pytest test. It only reports
whether the galaxy.ai.* modules import; it has no assertions. It also needs
the full Galaxy runtime (a2wsgi/pulsar/webob) available. Run directly
(`python3 test_ai_import.py`) inside a Galaxy container. Under pytest it is
skipped so it cannot masquerade as green coverage.
"""

import sys

import pytest

pytestmark = pytest.mark.skip(
    reason="manual diagnostic: prints import status, no assertions; "
    "requires full Galaxy runtime (galaxy.ai + a2wsgi/pulsar/webob)"
)


def main():
    sys.path.insert(0, 'lib')

    print("Testing AI Assistant imports...")

    try:
        from galaxy.ai.ai_assistant import AIAssistant
        print("✓ AIAssistant imported successfully")
    except ImportError as e:
        print(f"✗ Failed to import AIAssistant: {e}")
        import traceback
        traceback.print_exc()

    try:
        from galaxy.ai.config import AIConfig, DEFAULT_AI_CONFIG
        print("✓ AI Config imported successfully")
        print(f"  DEFAULT_AI_CONFIG: {DEFAULT_AI_CONFIG}")
    except ImportError as e:
        print(f"✗ Failed to import AI Config: {e}")
        import traceback
        traceback.print_exc()

    try:
        from galaxy.ai.galaxy_workflow_generator import GalaxyWorkflowGenerator
        print("✓ GalaxyWorkflowGenerator imported successfully")
    except ImportError as e:
        print(f"✗ Failed to import GalaxyWorkflowGenerator: {e}")
        import traceback
        traceback.print_exc()

    try:
        print("\nTesting GalaxyWorkflowGenerator initialization...")
        from galaxy.ai.config import DEFAULT_AI_CONFIG
        generator = GalaxyWorkflowGenerator(config=DEFAULT_AI_CONFIG)
        print("✓ GalaxyWorkflowGenerator initialized successfully")
    except Exception as e:
        print(f"✗ Failed to initialize GalaxyWorkflowGenerator: {e}")
        import traceback
        traceback.print_exc()

    print("\nAll tests completed!")


if __name__ == "__main__":
    main()
