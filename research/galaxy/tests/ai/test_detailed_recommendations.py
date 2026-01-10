#!/usr/bin/env python3

"""
Test script for detailed workflow recommendations
"""

import sys
import json

# Add the lib path
sys.path.insert(0, '/Users/renyuankai/work/biometa/galaxy/lib')

def test_detailed_recommendations():
    """Test detailed workflow recommendations."""
    
    try:
        from galaxy.ai.rag_workflow_generator import RAGWorkflowGenerator
        from galaxy.ai.config import DEFAULT_AI_CONFIG
        from galaxy.ai.types import UserRequest
        
        print("🔍 Testing detailed workflow recommendations...")
        
        data_path = '/Users/renyuankai/work/biometa/galaxy/lib/galaxy/ai/data/workflows'
        rag_generator = RAGWorkflowGenerator(DEFAULT_AI_CONFIG, data_path)
        
        # Test different queries to find workflows with more content
        test_queries = [
            "RNA-seq analysis",
            "variant calling",
            "genome assembly",
            "quality control fastqc",
            "differential expression"
        ]
        
        for query in test_queries:
            print(f"\n🔍 Testing query: '{query}'")
            
            user_request = UserRequest(
                user_id="test_user",
                request_text=query,
                context={}
            )
            
            recommendations = rag_generator.get_workflow_recommendations(user_request, limit=2)
            
            for i, rec in enumerate(recommendations):
                print(f"\n📄 Recommendation {i+1}: {rec.get('name', 'N/A')}")
                print(f"  - Actual tool steps: {rec.get('actual_tool_steps', 0)}")
                print(f"  - Tools: {rec.get('tools', [][:3])}")  # First 3 tools
                print(f"  - Step descriptions: {len(rec.get('step_descriptions', []))}")
                
                # Show first few step descriptions
                step_descs = rec.get('step_descriptions', [])
                if step_descs:
                    print(f"  - First steps:")
                    for j, desc in enumerate(step_descs[:3]):
                        print(f"    {j+1}. {desc[:60]}{'...' if len(desc) > 60 else ''}")
            
            # Test workflow generation for this query
            result = rag_generator.generate_workflow(user_request)
            if result.get('success'):
                workflow = result.get('workflow', {})
                steps = workflow.get('steps', [])
                print(f"\n🎯 Generated workflow has {len(steps)} tool steps")
                if steps:
                    for j, step in enumerate(steps[:3]):
                        tool_name = step.get('tool_id', 'Unknown')
                        if '/' in tool_name:
                            tool_name = tool_name.split('/')[-1]
                        annotation = step.get('annotation', 'No description')
                        print(f"    {j+1}. {tool_name}: {annotation[:50]}{'...' if len(annotation) > 50 else ''}")
            
            print("-" * 60)
        
        return True
        
    except Exception as e:
        print(f"❌ Error in detailed recommendations test: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    test_detailed_recommendations()