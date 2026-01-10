#!/usr/bin/env python3
"""
Test script for new AI components

This script tests whether the new AI components can be imported and initialized
without affecting existing Galaxy functionality.
"""

import sys
import os
sys.path.insert(0, 'lib')

def test_tool_recommender():
    """Test ToolRecommender import and basic functionality"""
    print("Testing ToolRecommender...")
    try:
        from galaxy.ai.tool_recommender import ToolRecommender
        
        # Mock toolbox for testing
        class MockToolbox:
            def get_tool_ids(self):
                return ['fastqc', 'bwa', 'gatk']
            
            def get_tool(self, tool_id):
                class MockTool:
                    def __init__(self, tool_id):
                        self.name = tool_id
                        self.description = f"Mock tool: {tool_id}"
                return MockTool(tool_id)
        
        toolbox = MockToolbox()
        recommender = ToolRecommender(toolbox)
        
        # Test recommendation
        requirements = {
            'analysis_type': 'rna-seq',
            'input_data_types': ['fastq']
        }
        recommendations = recommender.recommend_tools(requirements)
        
        print(f"✓ ToolRecommender works! Generated {len(recommendations)} recommendations")
        return True
        
    except Exception as e:
        print(f"✗ ToolRecommender failed: {e}")
        return False

def test_enhanced_ai_assistant():
    """Test EnhancedAIAssistant import"""
    print("Testing EnhancedAIAssistant...")
    try:
        from galaxy.ai.enhanced_ai_assistant import EnhancedAIAssistant, ConversationContextManager
        
        # Test basic initialization
        context_manager = ConversationContextManager()
        session = context_manager.get_session('test_session')
        
        print(f"✓ EnhancedAIAssistant imports work! Session created: {session}")
        return True
        
    except Exception as e:
        print(f"✗ EnhancedAIAssistant failed: {e}")
        return False

def test_api_components():
    """Test API components import"""
    print("Testing API components...")
    try:
        from galaxy.webapps.galaxy.api.enhanced_ai_assistant import (
            ConversationContext, 
            EnhancedAIRequest,
            ConversationResponse
        )
        
        # Test basic model creation
        context = ConversationContext(session_id="test")
        request = EnhancedAIRequest(message="test message", context=context)
        
        print(f"✓ API components work! Request created: {request.message}")
        return True
        
    except Exception as e:
        print(f"✗ API components failed: {e}")
        return False

def test_galaxy_imports():
    """Test that existing Galaxy imports still work"""
    print("Testing existing Galaxy imports...")
    try:
        # Test basic Galaxy imports
        from galaxy.workflow.modules import ToolModule
        from galaxy.managers.workflows import WorkflowsManager
        
        print("✓ Existing Galaxy imports still work!")
        return True
        
    except Exception as e:
        print(f"✗ Galaxy imports failed: {e}")
        return False

def main():
    """Run all tests"""
    print("🧪 Testing New AI Components for Galaxy")
    print("=" * 50)
    
    tests = [
        test_galaxy_imports,
        test_tool_recommender,
        test_enhanced_ai_assistant,
        test_api_components
    ]
    
    results = []
    for test in tests:
        try:
            result = test()
            results.append(result)
        except Exception as e:
            print(f"Test failed with exception: {e}")
            results.append(False)
        print()
    
    # Summary
    passed = sum(results)
    total = len(results)
    
    print("=" * 50)
    print(f"📊 Test Results: {passed}/{total} tests passed")
    
    if passed == total:
        print("🎉 All tests passed! New components are ready to use.")
        print("\n🚀 Next steps:")
        print("1. Start Galaxy with: PYTHONPATH=lib sh run.sh")
        print("2. Access new AI chat at: http://localhost:8080/workflow/chat")
        print("3. The new components extend existing functionality without changes")
    else:
        print("⚠️  Some tests failed. Check the errors above.")
    
    return passed == total

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)