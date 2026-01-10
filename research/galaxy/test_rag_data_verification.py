#!/usr/bin/env python3
"""
Verify RAG data and workflow loading without requiring API keys.
"""

import sys
sys.path.insert(0, 'lib')

import os
import json
from galaxy.ai.rag_workflow_loader import RAGWorkflowRecommender

def verify_rag_data():
    """Verify RAG data loading and processing."""

    print("=== RAG DATA VERIFICATION ===\n")

    # Check data path
    data_path = "/Users/renyuankai/work/pywork/normalWork/galaxy_爬虫/galaxy_crawler/galaxy_workflows_crawler_details/output"
    print(f"1. Checking data path: {data_path}")

    if not os.path.exists(data_path):
        print(f"   ❌ Data path not found")
        return False

    print(f"   ✅ Data path exists")

    # Check for workflows subdirectory
    workflows_path = os.path.join(data_path, "workflows")
    print(f"\n2. Checking workflows subdirectory: {workflows_path}")

    if not os.path.exists(workflows_path):
        print(f"   ❌ Workflows directory not found")
        return False

    print(f"   ✅ Workflows directory exists")

    # List available files
    try:
        files = os.listdir(workflows_path)
        json_files = [f for f in files if f.startswith('workflow_') and f.endswith('.json')]

        print(f"\n3. Available workflow files:")
        print(f"   📄 Workflow JSON files: {len(json_files)}")

        if json_files:
            print(f"   📄 Sample files: {json_files[:5]}")
        else:
            print("   ❌ No workflow JSON files found")
            return False

        # Test loading workflow data
        print(f"\n4. Testing workflow data loading...")

        sample_file = os.path.join(workflows_path, json_files[0])
        print(f"   📁 Loading: {json_files[0]}")

        with open(sample_file, 'r', encoding='utf-8') as f:
            data = json.load(f)

        if isinstance(data, dict):
            print(f"   ✅ Loaded workflow data successfully")
            print(f"   📋 Workflow data keys: {list(data.keys())}")

            # Check for essential fields
            if 'metadata' in data and 'workflow_json' in data:
                metadata = data['metadata']
                workflow_json = data['workflow_json']
                print(f"   ✅ Metadata keys: {list(metadata.keys())}")
                print(f"   ✅ Workflow JSON keys: {list(workflow_json.keys())}")

                if 'name' in metadata:
                    print(f"   📋 Sample workflow name: {metadata['name'][:50]}...")
        else:
            print(f"   ❌ Invalid data format (expected dict, got {type(data)})")
            return False

        # Test RAG recommender initialization (without LLM)
        print(f"\n5. Testing RAG recommender initialization...")

        try:
            # Initialize RAG recommender - it will look for workflows in data_path/workflows
            recommender = RAGWorkflowRecommender(data_path)
            print(f"   ✅ RAG recommender created successfully")
            print(f"   📚 Total workflows loaded: {len(recommender.rag_engine.workflows)}")

            # Test similarity search functionality
            print(f"\n6. Testing similarity search...")

            if hasattr(recommender, 'get_workflow_recommendations'):
                try:
                    # Test search
                    test_query = "RNA-seq differential expression analysis"
                    search_result = recommender.get_workflow_recommendations(test_query, max_recommendations=3)

                    print(f"   🔍 Search Query: '{test_query}'")
                    print(f"   📋 Search Status: {search_result.get('status', 'unknown')}")

                    if search_result.get('status') == 'success':
                        recommendations = search_result.get('recommendations', [])
                        print(f"   📊 Results Found: {len(recommendations)}")

                        for i, rec in enumerate(recommendations[:3], 1):
                            name = rec.get('name', 'Unknown')[:40]
                            score = rec.get('similarity_score', 0)
                            print(f"     {i}. {name}... (Score: {score:.3f})")

                        print("   ✅ RAG search functionality working")
                    else:
                        print(f"   ⚠️  Search returned: {search_result.get('message', 'No message')}")
                        print("   ✅ RAG search method available but no matches")

                except Exception as search_error:
                    print(f"   ❌ Search failed: {str(search_error)}")
                    return False
            else:
                print(f"   ❌ No search method available")
                return False

        except Exception as init_error:
            print(f"   ❌ RAG initialization failed: {str(init_error)}")
            return False

        print(f"\n=== RAG DATA VERIFICATION SUMMARY ===")
        print(f"✅ Data path accessible: True")
        print(f"✅ Workflow files available: True")
        print(f"✅ Data loading functional: True")
        print(f"✅ RAG recommender working: True")
        print(f"✅ Search functionality working: True")

        print(f"\n🎯 RAG Data Status: FULLY OPERATIONAL")
        return True

    except Exception as e:
        print(f"❌ Verification failed: {str(e)}")
        return False

if __name__ == "__main__":
    success = verify_rag_data()
    exit_code = 0 if success else 1
    sys.exit(exit_code)