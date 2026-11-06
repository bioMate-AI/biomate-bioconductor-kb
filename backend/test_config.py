#!/usr/bin/env python3
"""
Simple test to verify Galaxy AI configuration

MANUAL DIAGNOSTIC — print-based script, not a real pytest test. It loads the
full GalaxyAppConfiguration from config/galaxy.yml (needs the Galaxy runtime)
and only prints what it finds; `test_config()` returns True/False with NO
assertions, so pytest would collect it and report GREEN regardless. The
module-level skip below gates it honestly. Run directly
(`python3 test_config.py`) inside a Galaxy container with a real galaxy.yml.
"""

import pytest

pytestmark = pytest.mark.skip(
    reason="manual diagnostic: prints config values, no assertions; "
    "requires full Galaxy runtime + config/galaxy.yml"
)


def test_config():
    """Test if Galaxy configuration includes AI settings"""
    try:
        import sys
        import os
        
        # Add Galaxy lib to path
        galaxy_lib_path = os.path.join(os.path.dirname(__file__), 'lib')
        sys.path.insert(0, galaxy_lib_path)
        
        # Test configuration loading
        from galaxy.config import GalaxyAppConfiguration
        
        print("✅ Configuration module imported successfully")
        
        # Load the config file
        config_file = 'config/galaxy.yml'
        config = GalaxyAppConfiguration(config_file)
        
        print(f"✅ Configuration loaded from: {config_file}")
        
        # Test AI settings
        ai_enabled = getattr(config, 'enable_ai_assistant', False)
        ai_api_key = getattr(config, 'ai_api_key', None)
        ai_model = getattr(config, 'ai_model', 'gpt-4')
        
        print(f"🤖 AI Assistant Enabled: {ai_enabled}")
        print(f"🔑 AI API Key Configured: {'Yes' if ai_api_key else 'No'}")
        print(f"🧠 AI Model: {ai_model}")
        
        # Test config serialization 
        from galaxy.managers.configuration import ConfigSerializer
        
        # Create a mock app object for testing
        class MockApp:
            def __init__(self, config):
                self.config = config
        
        mock_app = MockApp(config)
        serializer = ConfigSerializer(mock_app)
        
        # Get the serializable configuration
        serialized_config = serializer.serialize_to_view(config)
        
        if 'enable_ai_assistant' in serialized_config:
            print(f"✅ AI Assistant in serialized config: {serialized_config['enable_ai_assistant']}")
        else:
            print("❌ AI Assistant not found in serialized config")
            
        if 'ai_assistant_available' in serialized_config:
            print(f"✅ AI Assistant Available: {serialized_config['ai_assistant_available']}")
        else:
            print("❌ AI Assistant Available not found in serialized config")
        
        return True
        
    except Exception as e:
        print(f"❌ Error testing configuration: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    print("🧪 Testing Galaxy AI Configuration")
    print("=" * 50)
    
    success = test_config()
    
    if success:
        print("\n🎉 Configuration test passed!")
    else:
        print("\n⚠️  Configuration test failed!")