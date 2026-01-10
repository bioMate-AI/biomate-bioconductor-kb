#!/usr/bin/env python3

"""
Debug script to check similarity search issues
"""

import sys
import numpy as np

# Add the lib path
sys.path.insert(0, '/Users/renyuankai/work/biometa/galaxy/lib')

def debug_similarity_search():
    """Debug the similarity search functionality."""
    
    try:
        from galaxy.ai.rag_workflow_generator import RAGWorkflowGenerator
        from galaxy.ai.config import DEFAULT_AI_CONFIG
        from galaxy.ai.types import UserRequest
        
        print("🔍 Debugging similarity search...")
        
        data_path = '/Users/renyuankai/work/biometa/galaxy/lib/galaxy/ai/data/workflows'
        rag_generator = RAGWorkflowGenerator(DEFAULT_AI_CONFIG, data_path)
        
        # Test user request
        user_request = UserRequest(
            user_id="test_user",
            request_text="RNA-seq differential expression analysis",
            context={}
        )
        
        print(f"📊 User request: '{user_request.request_text}'")
        
        # Create query embedding
        query_text = f"{user_request.request_text} {' '.join(user_request.context.get('tags', []))}"
        query_embedding = rag_generator._simple_text_embedding(query_text)
        
        print(f"🧠 Query embedding shape: {query_embedding.shape}")
        print(f"🧠 Query embedding values: {query_embedding[:10]}")  # First 10 values
        print(f"🧠 Query embedding norm: {np.linalg.norm(query_embedding)}")
        
        # Check workflow embeddings
        print(f"📚 Total embeddings: {len(rag_generator.embeddings)}")
        
        if rag_generator.embeddings:
            # Get a sample embedding
            sample_id = list(rag_generator.embeddings.keys())[0]
            sample_embedding = rag_generator.embeddings[sample_id]
            
            print(f"📄 Sample workflow: {sample_embedding.name}")
            print(f"🧠 Sample embedding shape: {sample_embedding.embedding.shape}")
            print(f"🧠 Sample embedding values: {sample_embedding.embedding[:10]}")
            print(f"🧠 Sample embedding norm: {np.linalg.norm(sample_embedding.embedding)}")
            
            # Test similarity calculation
            similarity = np.dot(query_embedding, sample_embedding.embedding)
            print(f"🎯 Test similarity: {similarity}")
        
        # Calculate similarities for all workflows
        similarities = []
        for workflow_id, workflow_emb in rag_generator.embeddings.items():
            similarity = np.dot(query_embedding, workflow_emb.embedding)
            similarities.append((workflow_id, similarity, workflow_emb.name))
        
        print(f"🔢 Total similarities calculated: {len(similarities)}")
        
        # Sort and get top results
        similarities.sort(key=lambda x: x[1], reverse=True)
        
        print("🏆 Top 10 similarities:")
        for i, (workflow_id, similarity, name) in enumerate(similarities[:10]):
            print(f"  {i+1}. {name[:60]} (similarity: {similarity:.6f})")
        
        print("🏮 Bottom 10 similarities:")
        for i, (workflow_id, similarity, name) in enumerate(similarities[-10:]):
            print(f"  {len(similarities)-9+i}. {name[:60]} (similarity: {similarity:.6f})")
        
        # Check if any similarities are > 0
        positive_similarities = [s for _, s, _ in similarities if s > 0]
        print(f"📊 Positive similarities: {len(positive_similarities)}")
        print(f"📊 Max similarity: {max(s for _, s, _ in similarities) if similarities else 'N/A'}")
        print(f"📊 Min similarity: {min(s for _, s, _ in similarities) if similarities else 'N/A'}")
        
    except Exception as e:
        print(f"❌ Error in similarity debug: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    debug_similarity_search()