#!/usr/bin/env python3

"""
Debug script to check workflow_index vs embeddings ID mismatch
"""

import sys

# Add the lib path
sys.path.insert(0, '/Users/renyuankai/work/biometa/galaxy/lib')

def debug_index_mismatch():
    """Debug the ID mismatch between workflow_index and embeddings."""
    
    try:
        from galaxy.ai.rag_workflow_generator import RAGWorkflowGenerator
        from galaxy.ai.config import DEFAULT_AI_CONFIG
        
        print("🔍 Debugging index mismatch...")
        
        data_path = '/Users/renyuankai/work/biometa/galaxy/lib/galaxy/ai/data/workflows'
        rag_generator = RAGWorkflowGenerator(DEFAULT_AI_CONFIG, data_path)
        
        print(f"📚 Workflow data workflows: {len(rag_generator.workflow_data.workflows)}")
        print(f"📚 Workflow index: {len(rag_generator.workflow_data.workflow_index)}")
        print(f"🧠 Embeddings: {len(rag_generator.embeddings)}")
        
        # Check sample workflow data
        if rag_generator.workflow_data.workflows:
            sample_workflow = rag_generator.workflow_data.workflows[0]
            workflow_id = sample_workflow.get('id', '')
            print(f"📄 Sample workflow ID: '{workflow_id}'")
            print(f"📄 Sample workflow name: {sample_workflow.get('name', 'N/A')}")
            
            # Check if it's in the index
            in_index = workflow_id in rag_generator.workflow_data.workflow_index
            print(f"📚 In workflow_index: {in_index}")
            
            # Check if it's in embeddings
            in_embeddings = workflow_id in rag_generator.embeddings
            print(f"🧠 In embeddings: {in_embeddings}")
            
        # Check first few IDs from each collection
        print("\n🔍 Sample workflow_index IDs:")
        index_ids = list(rag_generator.workflow_data.workflow_index.keys())[:5]
        for i, wid in enumerate(index_ids):
            print(f"  {i+1}. '{wid}'")
        
        print("\n🔍 Sample embeddings IDs:")
        embedding_ids = list(rag_generator.embeddings.keys())[:5]
        for i, wid in enumerate(embedding_ids):
            print(f"  {i+1}. '{wid}'")
        
        # Check for exact matches
        index_set = set(rag_generator.workflow_data.workflow_index.keys())
        embedding_set = set(rag_generator.embeddings.keys())
        
        intersection = index_set.intersection(embedding_set)
        print(f"\n📊 ID intersection: {len(intersection)} common IDs")
        print(f"📊 Index-only IDs: {len(index_set - embedding_set)}")
        print(f"📊 Embedding-only IDs: {len(embedding_set - index_set)}")
        
        # Check if empty IDs are the issue
        empty_index_ids = [wid for wid in index_ids if not wid]
        empty_embedding_ids = [wid for wid in embedding_ids if not wid]
        
        print(f"📊 Empty index IDs: {len(empty_index_ids)}")
        print(f"📊 Empty embedding IDs: {len(empty_embedding_ids)}")
        
        return intersection, index_set, embedding_set
        
    except Exception as e:
        print(f"❌ Error in index mismatch debug: {e}")
        import traceback
        traceback.print_exc()
        return None, None, None

if __name__ == "__main__":
    debug_index_mismatch()