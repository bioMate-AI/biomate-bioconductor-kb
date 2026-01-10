#!/usr/bin/env python3

"""
Test script to verify the fixed APIs directly (without Galaxy server)
"""

import sys
import json

# Add the lib path
sys.path.insert(0, '/Users/renyuankai/work/biometa/galaxy/lib')

def test_fixed_apis():
    """Test the fixed API functions directly."""
    
    try:
        print("🚀 Testing fixed APIs directly...")
        
        # Mock trans object
        class MockConfig:
            def __init__(self):
                self.enable_ai_assistant = True
                self.ai_crawler_data_path = 'lib/galaxy/ai/data/workflows'
        
        class MockApp:
            def __init__(self):
                self.config = MockConfig()
        
        class MockTrans:
            def __init__(self):
                self.app = MockApp()
                self.user = None
        
        # Set up mock
        trans = MockTrans()
        
        # Test enhanced workflow recommendations (quick level)
        print("\n1️⃣ Testing enhanced workflow recommendations (quick level)...")
        
        from galaxy.webapps.galaxy.api.ai_assistant import get_enhanced_workflow_recommendations, AIRequestModel
        
        request = AIRequestModel(request_text="variant calling workflow", context={})
        
        result = get_enhanced_workflow_recommendations(request, level="quick", trans=trans)
        
        print(f"Quick recommendations status: {result.get('status', 'N/A')}")
        
        if result.get('status') == 'success':
            recommendations = result.get('recommendations', [])
            print(f"Found {len(recommendations)} recommendations")
            
            for i, rec in enumerate(recommendations[:2]):
                print(f"\n📄 Recommendation {i+1}:")
                print(f"  - Name: {rec.get('name', 'N/A')}")
                print(f"  - Step count: {rec.get('step_count', 0)}")
                print(f"  - Tools: {rec.get('tools', [])[:3]}")  # First 3 tools
                print(f"  - Step descriptions: {len(rec.get('step_descriptions', []))}")
        else:
            print(f"Quick recommendations failed: {result.get('error', 'Unknown error')}")
        
        # Test enhanced workflow recommendations (enhanced level)
        print("\n2️⃣ Testing enhanced workflow recommendations (enhanced level)...")
        
        result = get_enhanced_workflow_recommendations(request, level="enhanced", trans=trans)
        
        print(f"Enhanced generation status: {result.get('status', 'N/A')}")
        
        if result.get('status') == 'success':
            workflow = result.get('workflow', {})
            print(f"\n🎯 Generated workflow:")
            print(f"  - Name: {workflow.get('name', 'N/A')}")
            print(f"  - Step count: {workflow.get('step_count', 0)}")
            print(f"  - Tools: {workflow.get('tools', [])}")
            print(f"  - Description length: {len(workflow.get('description', ''))}")
            
            steps = workflow.get('steps', [])
            if steps:
                print(f"  - First 3 steps:")
                for i, step in enumerate(steps[:3]):
                    tool_id = step.get('tool_id', 'Unknown')
                    annotation = step.get('annotation', 'No description')
                    print(f"    {i+1}. {tool_id}: {annotation[:50]}{'...' if len(annotation) > 50 else ''}")
        else:
            print(f"Enhanced generation failed: {result.get('error', 'Unknown error')}")
        
        return True
        
    except Exception as e:
        print(f"❌ Error testing fixed APIs: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    test_fixed_apis()