#!/usr/bin/env python3

"""
Test script to check RAG workflow data loading
"""

import sys
import os
import json

# Add the lib path to import Galaxy AI modules
sys.path.insert(0, '/Users/renyuankai/work/biometa/galaxy/lib')

def test_workflow_data_loading():
    """Test loading workflow data from the crawler data directory."""
    
    data_path = '/Users/renyuankai/work/biometa/galaxy/lib/galaxy/ai/data/workflows'
    
    print(f"🔍 Testing workflow data loading from: {data_path}")
    
    if not os.path.exists(data_path):
        print(f"❌ Data path does not exist: {data_path}")
        return
    
    # Count files
    json_files = [f for f in os.listdir(data_path) if f.endswith('.json')]
    print(f"📁 Found {len(json_files)} JSON files")
    
    # Test loading a sample file
    if json_files:
        sample_file = os.path.join(data_path, json_files[0])
        print(f"📄 Testing sample file: {json_files[0]}")
        
        try:
            with open(sample_file, 'r', encoding='utf-8') as f:
                data = json.load(f)
                
            print("✅ Sample file structure:")
            print(f"  - Keys: {list(data.keys())}")
            
            if 'metadata' in data:
                metadata = data['metadata']
                print("  - Metadata keys:", list(metadata.keys()))
                print(f"  - Name: {metadata.get('name', 'N/A')}")
                print(f"  - Tags: {metadata.get('tags', [])}")
                print(f"  - Steps: {metadata.get('number_of_steps', 0)}")
                print(f"  - Owner: {metadata.get('owner', 'N/A')}")
                
                if 'annotations' in metadata:
                    annotations = metadata['annotations']
                    if annotations:
                        print(f"  - First annotation: {annotations[0][:100]}...")
            
        except Exception as e:
            print(f"❌ Error loading sample file: {e}")
            return

def test_rag_workflow_generator():
    """Test RAGWorkflowGenerator initialization and data loading."""
    
    try:
        from galaxy.ai.rag_workflow_generator import RAGWorkflowGenerator, CrawledWorkflowData
        from galaxy.ai.config import DEFAULT_AI_CONFIG
        
        print("\n🔍 Testing RAGWorkflowGenerator...")
        
        # Test CrawledWorkflowData directly first
        print("1️⃣ Testing CrawledWorkflowData...")
        data_path = '/Users/renyuankai/work/biometa/galaxy/lib/galaxy/ai/data/workflows'
        crawled_data = CrawledWorkflowData(data_path)
        crawled_data.load_crawler_data()
        
        print(f"   ✅ Loaded {len(crawled_data.workflows)} workflows")
        print(f"   📚 Index keys: {len(crawled_data.workflow_index)}")
        print(f"   🏷️  Categories: {len(crawled_data.category_index)}")
        
        if crawled_data.workflows:
            sample = crawled_data.workflows[0]
            print(f"   📄 Sample workflow: {sample.get('name', 'N/A')}")
            print(f"   🏷️  Sample tags: {sample.get('tags', [])}")
        
        # Test search functionality
        print("2️⃣ Testing search functionality...")
        results = crawled_data.search_workflows("rna", max_steps=50)
        print(f"   🔍 Search 'rna': {len(results)} results")
        
        if results:
            top_result = results[0]
            print(f"   🥇 Top result: {top_result.get('name', 'N/A')} (score: {top_result.get('relevance_score', 0)})")
        
        # Test RAGWorkflowGenerator
        print("3️⃣ Testing RAGWorkflowGenerator...")
        rag_generator = RAGWorkflowGenerator(DEFAULT_AI_CONFIG, data_path)
        
        print(f"   ✅ RAGWorkflowGenerator initialized")
        print(f"   📚 Workflow data: {len(rag_generator.workflow_data.workflows)} workflows")
        print(f"   🧠 Embeddings: {len(rag_generator.embeddings)} embeddings")
        
        return True
        
    except ImportError as e:
        print(f"❌ Import error: {e}")
        return False
    except Exception as e:
        print(f"❌ Error testing RAGWorkflowGenerator: {e}")
        import traceback
        traceback.print_exc()
        return False

def test_workflow_search():
    """Test workflow search and similarity functionality."""
    
    try:
        from galaxy.ai.rag_workflow_generator import RAGWorkflowGenerator
        from galaxy.ai.config import DEFAULT_AI_CONFIG
        from galaxy.ai.types import UserRequest
        
        print("\n🔍 Testing workflow search...")
        
        data_path = '/Users/renyuankai/work/biometa/galaxy/lib/galaxy/ai/data/workflows'
        rag_generator = RAGWorkflowGenerator(DEFAULT_AI_CONFIG, data_path)
        
        # Test user request
        user_request = UserRequest(
            user_id="test_user",
            request_text="RNA-seq differential expression analysis",
            context={}
        )
        
        print("4️⃣ Testing similarity search...")
        similar_workflows = rag_generator.find_similar_workflows(user_request, top_k=5)
        print(f"   🔍 Found {len(similar_workflows)} similar workflows")
        
        for i, (workflow, similarity) in enumerate(similar_workflows):
            print(f"   {i+1}. {workflow.get('name', 'N/A')} (similarity: {similarity:.3f})")
        
        print("5️⃣ Testing workflow generation...")
        result = rag_generator.generate_workflow(user_request)
        print(f"   📊 Generation result: {result.get('success', False)}")
        
        if result.get('success'):
            workflow = result.get('workflow', {})
            print(f"   📄 Generated workflow: {workflow.get('name', 'N/A')}")
            print(f"   📊 Confidence: {result.get('confidence', 0):.3f}")
            print(f"   🔢 Steps: {len(workflow.get('steps', []))}")
        else:
            print(f"   ❌ Generation failed: {result.get('error', 'Unknown error')}")
        
        return True
        
    except Exception as e:
        print(f"❌ Error testing workflow search: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    print("🚀 Starting RAG system tests...")
    
    # Test 1: Basic data loading
    test_workflow_data_loading()
    
    # Test 2: RAG components
    if test_rag_workflow_generator():
        # Test 3: Search and generation
        test_workflow_search()
    
    print("\n✅ Test completed!")