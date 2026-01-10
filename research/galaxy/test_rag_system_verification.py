#!/usr/bin/env python3
"""
Verify RAG system actual working status.
"""

import sys
sys.path.insert(0, 'lib')

from galaxy.ai.rag_assistant_init import create_rag_enabled_assistant, get_rag_stats
from galaxy.ai.config import DEFAULT_AI_CONFIG

def verify_rag_system():
    """Verify RAG system is working correctly."""

    print("=== RAG SYSTEM VERIFICATION ===\n")

    try:
        # Create RAG-enabled assistant
        print("1. Creating RAG-enabled AI assistant...")
        assistant = create_rag_enabled_assistant()

        print(f"   ✅ Assistant created: {type(assistant).__name__}")

        # Check RAG stats
        print("\n2. Checking RAG system statistics...")
        rag_stats = get_rag_stats(assistant)

        print(f"   📊 RAG Status: {rag_stats}")

        if rag_stats.get("status") == "available":
            print(f"   ✅ RAG Engine: {rag_stats.get('rag_engine')}")
            print(f"   📚 Workflow Count: {rag_stats.get('workflow_count')}")
        else:
            print(f"   ❌ RAG Error: {rag_stats.get('error')}")

        # Test RAG workflow search
        print("\n3. Testing RAG workflow search functionality...")
        if hasattr(assistant, 'rag_recommender') and assistant.rag_recommender:
            try:
                # Test search
                test_query = "RNA-seq differential expression analysis"
                results = assistant.rag_recommender.find_similar_workflows(test_query, top_k=3)

                print(f"   🔍 Search Query: '{test_query}'")
                print(f"   📋 Results Found: {len(results)}")

                for i, result in enumerate(results[:3], 1):
                    name = result.get('name', 'Unknown')[:50]
                    score = result.get('similarity_score', 0)
                    print(f"     {i}. {name}... (Score: {score:.3f})")

                print("   ✅ RAG search functionality working")

            except Exception as search_error:
                print(f"   ❌ RAG search error: {str(search_error)}")
        else:
            print("   ❌ RAG recommender not available")

        # Check crawler data path
        print("\n4. Checking crawler data availability...")
        from galaxy.ai.rag_assistant_init import CRAWLER_DATA_PATH
        import os

        if os.path.exists(CRAWLER_DATA_PATH):
            print(f"   ✅ Crawler data path exists: {CRAWLER_DATA_PATH}")

            # Check for workflow files
            try:
                files = os.listdir(CRAWLER_DATA_PATH)
                workflow_files = [f for f in files if f.endswith('.json')]
                print(f"   📁 JSON files found: {len(workflow_files)}")

                if workflow_files:
                    print(f"   📄 Sample files: {workflow_files[:3]}")
                else:
                    print("   ⚠️  No JSON workflow files found")

            except Exception as dir_error:
                print(f"   ❌ Error reading directory: {str(dir_error)}")
        else:
            print(f"   ❌ Crawler data path not found: {CRAWLER_DATA_PATH}")

        # Overall status
        print(f"\n=== RAG SYSTEM VERIFICATION SUMMARY ===")

        rag_available = rag_stats.get("status") == "available"
        search_working = hasattr(assistant, 'rag_recommender') and assistant.rag_recommender
        data_available = os.path.exists(CRAWLER_DATA_PATH)

        print(f"✅ RAG Engine Available: {rag_available}")
        print(f"✅ Search Functionality: {search_working}")
        print(f"✅ Crawler Data Available: {data_available}")

        overall_status = "FULLY OPERATIONAL" if all([rag_available, search_working, data_available]) else "PARTIALLY OPERATIONAL"
        print(f"\n🎯 Overall RAG Status: {overall_status}")

        return overall_status == "FULLY OPERATIONAL"

    except Exception as e:
        print(f"❌ RAG verification failed: {str(e)}")
        print(f"🔧 Error type: {type(e).__name__}")
        return False

if __name__ == "__main__":
    success = verify_rag_system()
    exit_code = 0 if success else 1
    sys.exit(exit_code)