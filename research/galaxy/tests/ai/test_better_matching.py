#!/usr/bin/env python3

"""
Test better workflow matching
"""

import sys
import json

# Add the lib path
sys.path.insert(0, '/Users/renyuankai/work/biometa/galaxy/lib')

def test_better_matching():
    """Test workflow matching for specific terms."""
    
    try:
        from galaxy.ai.rag_workflow_generator import RAGWorkflowGenerator
        from galaxy.ai.config import DEFAULT_AI_CONFIG
        from galaxy.ai.types import UserRequest
        
        print("🔍 Testing better workflow matching...")
        
        data_path = '/Users/renyuankai/work/biometa/galaxy/lib/galaxy/ai/data/workflows'
        rag_generator = RAGWorkflowGenerator(DEFAULT_AI_CONFIG, data_path)
        
        # Test with more specific terms
        specific_queries = [
            "COVID variant calling",  # Should match COVID workflows
            "RNA-seq analysis",       # Should match RNA workflows
            "genome assembly",        # Should match assembly workflows
            "fastq quality control",  # Should match QC workflows
        ]
        
        for query in specific_queries:
            print(f"\n🔍 Testing specific query: '{query}'")
            
            user_request = UserRequest(
                user_id="test_user",
                request_text=query,
                context={}
            )
            
            recommendations = rag_generator.get_workflow_recommendations(user_request, limit=3)
            
            print(f"Found {len(recommendations)} recommendations:")
            for i, rec in enumerate(recommendations):
                name = rec.get('name', 'N/A')
                similarity = rec.get('similarity_score', 0)
                tools = rec.get('tools', [])
                step_count = rec.get('actual_tool_steps', 0)
                
                print(f"  {i+1}. {name[:50]}{'...' if len(name) > 50 else ''}")
                print(f"     Similarity: {similarity:.3f}, Tools: {step_count}, First tools: {', '.join(tools[:3])}")
                
                # Show first step description if available
                step_descs = rec.get('step_descriptions', [])
                if step_descs:
                    print(f"     First step: {step_descs[0][:60]}{'...' if len(step_descs[0]) > 60 else ''}")
            
            print("-" * 70)
        
        # Let's also check what workflows contain specific keywords
        print("\n🔍 Searching for workflows with specific keywords...")
        
        # Direct search in workflow data
        all_workflows = rag_generator.workflow_data.workflows
        
        keywords = ["COVID", "RNA", "variant", "assembly", "fastqc"]
        
        for keyword in keywords:
            matching_workflows = []
            for workflow in all_workflows:
                name = workflow.get('name', '').lower()
                annotations = ' '.join(workflow.get('annotations', [])).lower()
                tags = ' '.join(workflow.get('tags', [])).lower()
                
                search_text = f"{name} {annotations} {tags}"
                
                if keyword.lower() in search_text:
                    matching_workflows.append({
                        'name': workflow.get('name', 'N/A'),
                        'steps': workflow.get('number_of_steps', 0),
                        'owner': workflow.get('owner', 'N/A')
                    })
            
            print(f"\n🏷️  Keyword '{keyword}': {len(matching_workflows)} workflows")
            for wf in matching_workflows[:3]:  # Show first 3
                print(f"   - {wf['name'][:50]}{'...' if len(wf['name']) > 50 else ''} ({wf['steps']} steps)")
        
        return True
        
    except Exception as e:
        print(f"❌ Error in better matching test: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    test_better_matching()