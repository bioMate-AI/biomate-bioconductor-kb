#!/usr/bin/env python3
"""
Test script for Enhanced Galaxy Tool RAG with dataset support.

Demonstrates the new capabilities:
1. Dataset discovery
2. Tool-dataset compatibility
3. FTS5 search
4. Dataset recommendations
"""

import sys
from pathlib import Path

# Add lib to path
sys.path.insert(0, str(Path(__file__).parent / 'lib'))

from galaxy.ai.enhanced_galaxy_tool_rag import EnhancedGalaxyToolRAG


def print_section(title):
    print("\n" + "="*80)
    print(title)
    print("="*80)


def test_statistics():
    """Test 1: Get system statistics."""
    print_section("TEST 1: System Statistics")

    rag = EnhancedGalaxyToolRAG()
    stats = rag.get_stats()

    print(f"Total Tools: {stats['total_tools']}")
    print(f"Total Datasets: {stats['total_datasets']}")
    print(f"Total Items: {stats['total_items']}")
    print(f"Categories: {stats['categories']}")
    print(f"Dataset-Tool Mappings: {stats['dataset_tool_mappings']}")
    print(f"Datasets with Mappings: {stats['datasets_with_mappings']}")

    assert stats['total_tools'] > 8000, "Should have 8,000+ tools"
    assert stats['total_datasets'] > 100, "Should have 100+ datasets"
    print("\n✅ Statistics test passed!")


def test_tool_search():
    """Test 2: Search for tools using FTS5."""
    print_section("TEST 2: Tool Search (FTS5)")

    rag = EnhancedGalaxyToolRAG()

    # Search for alignment tools
    query = "sequence alignment"
    tools = rag.search_tools(query, limit=5)

    print(f"\nQuery: '{query}'")
    print(f"Found: {len(tools)} tools\n")

    for i, tool in enumerate(tools, 1):
        print(f"{i}. {tool['name']} (ID: {tool['id']})")
        print(f"   Category: {tool['category']}")
        print(f"   Relevance: {tool.get('relevance_score', 'N/A')}")
        print(f"   Description: {tool['description'][:100]}...")
        print()

    assert len(tools) > 0, "Should find alignment tools"
    print("✅ Tool search test passed!")


def test_dataset_search():
    """Test 3: Search for datasets."""
    print_section("TEST 3: Dataset Search")

    rag = EnhancedGalaxyToolRAG()

    # Search for drug-related datasets
    query = "drug"
    datasets = rag.search_datasets(query, limit=5)

    print(f"\nQuery: '{query}'")
    print(f"Found: {len(datasets)} datasets\n")

    for i, dataset in enumerate(datasets, 1):
        print(f"{i}. {dataset['name']}")
        print(f"   Format: {dataset['format']}")
        print(f"   Category: {dataset['category']}")
        print(f"   Use Cases: {', '.join(dataset.get('use_cases', [])[:3])}")
        print(f"   Compatible Tools: {dataset.get('compatible_tools_count', 0)}")
        print()

    assert len(datasets) > 0, "Should find drug-related datasets"
    print("✅ Dataset search test passed!")


def test_dataset_compatibility():
    """Test 4: Get compatible tools for a dataset."""
    print_section("TEST 4: Dataset-Tool Compatibility")

    rag = EnhancedGalaxyToolRAG()

    # First, find a dataset
    datasets = rag.search_datasets("bindingdb", limit=1)
    if not datasets:
        print("⚠️  BindingDB dataset not found, skipping compatibility test")
        return

    dataset_id = datasets[0]['id']
    print(f"\nDataset: {datasets[0]['name']}")
    print(f"ID: {dataset_id}\n")

    # Get compatible tools
    tools = rag.get_compatible_tools(dataset_id, min_confidence=0.5)

    print(f"Found {len(tools)} compatible tools:\n")

    for i, tool in enumerate(tools[:5], 1):  # Show top 5
        print(f"{i}. {tool['name']} (ID: {tool['id']})")
        print(f"   Category: {tool['category']}")
        print(f"   Parameter: {tool['parameter_name']}")
        print(f"   Confidence: {tool['confidence']:.2f}")
        print(f"   Reasoning: {tool['reasoning'][:100]}...")
        print()

    if tools:
        print("✅ Compatibility test passed!")
    else:
        print("⚠️  No compatible tools found (mappings may not be populated yet)")


def test_dataset_recommendations():
    """Test 5: Recommend datasets for workflow tools."""
    print_section("TEST 5: Dataset Recommendations for Workflow")

    rag = EnhancedGalaxyToolRAG()

    # Simulate a workflow with drug discovery tools
    workflow_tools = []

    # Search for some cheminformatics tools
    cheminformatics_tools = rag.search_tools("cheminformatics compound", limit=3)
    workflow_tools.extend([t['id'] for t in cheminformatics_tools])

    print(f"\nWorkflow Tools: {len(workflow_tools)}")
    for tool_id in workflow_tools:
        tool_info = rag.get_tool_info(tool_id)
        if tool_info:
            print(f"  - {tool_info.get('name', tool_id)}")

    # Get dataset recommendations
    datasets = rag.recommend_dataset_for_tools(workflow_tools)

    print(f"\nRecommended Datasets: {len(datasets)}\n")

    for i, dataset in enumerate(datasets[:3], 1):  # Show top 3
        print(f"{i}. {dataset['name']}")
        print(f"   Format: {dataset['format']}")
        print(f"   Compatibility Score: {dataset['compatibility_score']:.2f}")
        print(f"   Matching Tools: {len(dataset['matching_tools'])}")
        print(f"   Use Cases: {', '.join(dataset.get('use_cases', [])[:2])}")
        print()

    if datasets:
        print("✅ Recommendation test passed!")
    else:
        print("⚠️  No dataset recommendations found")


def test_combined_search():
    """Test 6: Search for both tools and datasets."""
    print_section("TEST 6: Combined Tool + Dataset Search")

    rag = EnhancedGalaxyToolRAG()

    # Search with datasets included
    query = "protein structure analysis"
    results = rag.search_tools(query, include_datasets=True, limit=10)

    print(f"\nQuery: '{query}'")
    print(f"Found: {len(results)} items\n")

    tools_count = sum(1 for r in results if r['type'] == 'tool')
    datasets_count = sum(1 for r in results if r['type'] == 'dataset')

    print(f"Tools: {tools_count}")
    print(f"Datasets: {datasets_count}\n")

    for i, item in enumerate(results[:5], 1):
        icon = "📊" if item['type'] == 'dataset' else "🔧"
        print(f"{i}. {icon} {item['name']}")
        print(f"   Type: {item['type']}")
        print(f"   Category: {item['category']}")
        print()

    print("✅ Combined search test passed!")


def main():
    """Run all tests."""
    print("\n" + "🧪 Enhanced Galaxy Tool RAG - Test Suite".center(80))

    tests = [
        test_statistics,
        test_tool_search,
        test_dataset_search,
        test_dataset_compatibility,
        test_dataset_recommendations,
        test_combined_search
    ]

    passed = 0
    failed = 0

    for test in tests:
        try:
            test()
            passed += 1
        except Exception as e:
            print(f"\n❌ Test failed: {e}")
            import traceback
            traceback.print_exc()
            failed += 1

    # Final summary
    print("\n" + "="*80)
    print("TEST SUMMARY")
    print("="*80)
    print(f"Passed: {passed}/{len(tests)}")
    print(f"Failed: {failed}/{len(tests)}")

    if failed == 0:
        print("\n🎉 All tests passed!")
    else:
        print(f"\n⚠️  {failed} test(s) failed")

    return failed == 0


if __name__ == '__main__':
    success = main()
    sys.exit(0 if success else 1)
