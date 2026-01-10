#!/usr/bin/env python3

"""
Debug script to check workflow content generation
"""

import sys
import json

# Add the lib path
sys.path.insert(0, '/Users/renyuankai/work/biometa/galaxy/lib')

def debug_workflow_content():
    """Debug workflow content generation."""
    
    try:
        from galaxy.ai.rag_workflow_generator import RAGWorkflowGenerator
        from galaxy.ai.config import DEFAULT_AI_CONFIG
        from galaxy.ai.types import UserRequest
        
        print("🔍 Debugging workflow content generation...")
        
        data_path = '/Users/renyuankai/work/biometa/galaxy/lib/galaxy/ai/data/workflows'
        rag_generator = RAGWorkflowGenerator(DEFAULT_AI_CONFIG, data_path)
        
        # Test user request
        user_request = UserRequest(
            user_id="test_user",
            request_text="RNA-seq differential expression analysis",
            context={}
        )
        
        print(f"📊 User request: '{user_request.request_text}'")
        
        # 1. Check recommendations
        print("\n1️⃣ Testing get_workflow_recommendations...")
        recommendations = rag_generator.get_workflow_recommendations(user_request, limit=3)
        print(f"Found {len(recommendations)} recommendations")
        
        for i, rec in enumerate(recommendations):
            print(f"\n📄 Recommendation {i+1}:")
            print(f"  - ID: {rec.get('workflow_id', 'N/A')}")
            print(f"  - Name: {rec.get('name', 'N/A')}")
            print(f"  - Step count: {rec.get('step_count', 0)}")
            print(f"  - Owner: {rec.get('owner', 'N/A')}")
            print(f"  - Confidence: {rec.get('confidence', 0):.3f}")
            
            # Check if this workflow has detailed steps
            workflow_id = rec.get('workflow_id', '')
            if workflow_id in rag_generator.workflow_data.workflow_index:
                original_workflow = rag_generator.workflow_data.workflow_index[workflow_id]
                print(f"  - Original workflow steps: {type(original_workflow.get('steps', {}))}")
                
                steps = original_workflow.get('steps', {})
                if isinstance(steps, dict):
                    print(f"  - Step keys: {list(steps.keys())[:5]}")
                    if steps:
                        first_step = steps[list(steps.keys())[0]]
                        print(f"  - First step tool: {first_step.get('tool_id', 'N/A')}")
                elif isinstance(steps, list):
                    print(f"  - Step count: {len(steps)}")
        
        # 2. Check workflow generation
        print("\n2️⃣ Testing generate_workflow...")
        result = rag_generator.generate_workflow(user_request)
        print(f"Generation result: {result.get('success', False)}")
        
        if result.get('success'):
            workflow = result.get('workflow', {})
            print(f"\n📄 Generated workflow:")
            print(f"  - Name: {workflow.get('name', 'N/A')}")
            print(f"  - Description length: {len(workflow.get('description', ''))}")
            
            steps = workflow.get('steps', [])
            print(f"  - Steps type: {type(steps)}")
            print(f"  - Steps count: {len(steps)}")
            
            if steps:
                print(f"  - First 3 steps:")
                for i, step in enumerate(steps[:3]):
                    print(f"    {i+1}. {step.get('tool_id', 'N/A')} - {step.get('annotation', 'No description')}")
            
            inputs = workflow.get('inputs', [])
            outputs = workflow.get('outputs', [])
            print(f"  - Inputs: {len(inputs)}")
            print(f"  - Outputs: {len(outputs)}")
        else:
            print(f"Generation failed: {result.get('error', 'Unknown error')}")
        
        # 3. Check source workflow data in detail
        print("\n3️⃣ Checking source workflow data...")
        if recommendations:
            workflow_id = recommendations[0]['workflow_id']
            source_workflow = rag_generator.workflow_data.workflow_index[workflow_id]
            
            print(f"Source workflow structure:")
            print(f"  - Keys: {list(source_workflow.keys())}")
            
            steps = source_workflow.get('steps', {})
            print(f"  - Steps type: {type(steps)}")
            
            if isinstance(steps, dict) and steps:
                step_key = list(steps.keys())[0]
                step_data = steps[step_key]
                print(f"  - Sample step data:")
                print(f"    - Keys: {list(step_data.keys())}")
                print(f"    - Tool ID: {step_data.get('tool_id', 'N/A')}")
                print(f"    - Type: {step_data.get('type', 'N/A')}")
                print(f"    - Annotation: {step_data.get('annotation', 'N/A')}")
        
        return True
        
    except Exception as e:
        print(f"❌ Error in workflow content debug: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    debug_workflow_content()