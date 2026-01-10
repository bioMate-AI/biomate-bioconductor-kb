#!/usr/bin/env python3

"""
Test core RAG functionality after fixes
"""

import sys
import json

# Add the lib path
sys.path.insert(0, '/Users/renyuankai/work/biometa/galaxy/lib')

def test_core_rag_functionality():
    """Test core RAG functionality after fixes."""
    
    try:
        from galaxy.ai.rag_workflow_generator import RAGWorkflowGenerator
        from galaxy.ai.config import DEFAULT_AI_CONFIG
        from galaxy.ai.types import UserRequest
        
        print("🔍 Testing core RAG functionality after fixes...")
        
        data_path = '/Users/renyuankai/work/biometa/galaxy/lib/galaxy/ai/data/workflows'
        rag_generator = RAGWorkflowGenerator(DEFAULT_AI_CONFIG, data_path)
        
        # Test different queries
        test_queries = [
            "variant calling pipeline",
            "differential expression analysis",
            "quality control workflow"
        ]
        
        for query in test_queries:
            print(f"\n🔍 Testing query: '{query}'")
            
            user_request = UserRequest(
                user_id="test_user",
                request_text=query,
                context={}
            )
            
            # 1. Test recommendations
            print("1️⃣ Testing get_workflow_recommendations...")
            recommendations = rag_generator.get_workflow_recommendations(user_request, limit=2)
            
            print(f"Found {len(recommendations)} recommendations")
            for i, rec in enumerate(recommendations):
                print(f"  {i+1}. {rec.get('name', 'N/A')} - {rec.get('actual_tool_steps', 0)} tools")
                tools = rec.get('tools', [])
                if tools:
                    print(f"     Tools: {', '.join(tools[:3])}{'...' if len(tools) > 3 else ''}")
                step_descs = rec.get('step_descriptions', [])
                if step_descs:
                    print(f"     First step: {step_descs[0][:60]}{'...' if len(step_descs[0]) > 60 else ''}")
            
            # 2. Test workflow generation
            print("2️⃣ Testing generate_workflow...")
            result = rag_generator.generate_workflow(user_request)
            
            if result.get('success'):
                workflow = result.get('workflow', {})
                steps = workflow.get('steps', [])
                print(f"   ✅ Generated workflow: {workflow.get('name', 'N/A')}")
                print(f"   📊 Steps: {len(steps)} tool steps")
                
                if steps:
                    print(f"   🔧 Tool chain:")
                    for i, step in enumerate(steps[:5]):  # First 5 steps
                        tool_id = step.get('tool_id', 'Unknown')
                        if '/' in tool_id:
                            tool_id = tool_id.split('/')[-1]
                        annotation = step.get('annotation', 'No description')
                        print(f"      {i+1}. {tool_id}: {annotation[:40]}{'...' if len(annotation) > 40 else ''}")
            else:
                print(f"   ❌ Generation failed: {result.get('error', 'Unknown error')}")
            
            print("-" * 60)
        
        return True
        
    except Exception as e:
        print(f"❌ Error in core functionality test: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    test_core_rag_functionality()