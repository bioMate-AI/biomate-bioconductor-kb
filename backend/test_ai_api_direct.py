#!/usr/bin/env python3
"""
Direct test of AI Assistant API module without full Galaxy startup
"""

import sys
import os

def test_ai_api():
    """Test AI Assistant API components directly"""
    try:
        # Add Galaxy lib to path
        galaxy_lib_path = os.path.join(os.path.dirname(__file__), 'lib')
        sys.path.insert(0, galaxy_lib_path)
        
        print("✅ Galaxy lib path added")
        
        # Test AI types import
        from galaxy.ai.types import UserRequest, IntentType, TaskType
        print("✅ AI types imported successfully")
        
        # Test AI configuration import
        from galaxy.ai.config import AIConfig
        print("✅ AI config imported successfully")
        
        # Test API module import
        from galaxy.webapps.galaxy.api.ai_assistant import router
        print("✅ AI Assistant API router imported successfully")
        
        # Check if router has our endpoints
        routes = []
        for route in router.routes:
            routes.append(f"{route.methods} {route.path}")
        
        print(f"📋 Available API routes:")
        for route in routes:
            print(f"   {route}")
        
        # Test basic AI config creation
        test_config = {
            'llm_api_key': 'test-key',
            'llm_model': 'gpt-4',
            'llm_provider': 'openai'
        }
        
        ai_config = AIConfig(test_config)
        print(f"✅ AI Configuration created: {ai_config.llm_provider} - {ai_config.llm_model}")
        
        # Test UserRequest creation
        user_request = UserRequest(
            user_id='test-user',
            request_text='Test RNA-seq analysis',
            context={},
            available_datasets=[],
            preferred_tools=[],
            constraints={}
        )
        
        print(f"✅ UserRequest created: {user_request.request_text}")
        
        print("\n🎉 All AI Assistant components loaded successfully!")
        return True
        
    except Exception as e:
        print(f"❌ Error testing AI components: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    print("🧪 Testing Galaxy AI Assistant Components")
    print("=" * 50)
    
    success = test_ai_api()
    
    if success:
        print("\n✅ Direct API test passed!")
        print("🔧 Next steps:")
        print("   1. Wait for Galaxy to finish starting")
        print("   2. Test API endpoints via HTTP")
        print("   3. Verify frontend integration")
    else:
        print("\n❌ Direct API test failed!")