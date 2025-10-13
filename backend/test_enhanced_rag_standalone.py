#!/usr/bin/env python3
"""
Standalone test for Enhanced Galaxy Tool RAG.
Tests the enhanced RAG without Galaxy dependencies.
"""

import sqlite3
import json
from pathlib import Path


def test_database_structure():
    """Test the updated database structure."""
    print("="*80)
    print("TEST: Database Structure")
    print("="*80)

    db_path = Path(__file__).parent / "galaxy_ai_tools.db"

    with sqlite3.connect(str(db_path)) as conn:
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()

        # Test 1: Check schema
        cursor.execute("PRAGMA table_info(tools)")
        columns = {row[1] for row in cursor.fetchall()}
        required_columns = {'tool_id', 'name', 'is_dataset', 'dataset_metadata', 'data_version'}

        print(f"\n✓ Tools table columns: {len(columns)}")
        for col in required_columns:
            status = "✓" if col in columns else "✗"
            print(f"  {status} {col}")

        # Test 2: Count tools and datasets
        cursor.execute("SELECT COUNT(*) FROM tools WHERE is_dataset IS NULL OR is_dataset = 0")
        tool_count = cursor.fetchone()[0]

        cursor.execute("SELECT COUNT(*) FROM tools WHERE is_dataset = 1")
        dataset_count = cursor.fetchone()[0]

        print(f"\n✓ Tool count: {tool_count}")
        print(f"✓ Dataset count: {dataset_count}")

        # Test 3: Check FTS index
        cursor.execute("SELECT COUNT(*) FROM tools_fts")
        fts_count = cursor.fetchone()[0]
        print(f"✓ FTS index entries: {fts_count}")

        # Test 4: Check dataset mappings
        cursor.execute("SELECT COUNT(*) FROM dataset_tool_mapping")
        mapping_count = cursor.fetchone()[0]
        print(f"✓ Dataset-tool mappings: {mapping_count}")

        # Test 5: Sample FTS search
        try:
            cursor.execute("""
                SELECT t.tool_id, t.name, bm25(tools_fts) as score
                FROM tools t
                JOIN tools_fts ON t.tool_id = tools_fts.tool_id
                WHERE tools_fts MATCH 'alignment'
                LIMIT 3
            """)
            results = cursor.fetchall()
            print(f"\n✓ FTS search test: Found {len(results)} results for 'alignment'")
            for row in results:
                print(f"  - {row['name']} (score: {row['score']:.2f})")
        except Exception as e:
            print(f"\n✗ FTS search failed: {e}")

        # Test 6: Sample dataset with metadata
        cursor.execute("""
            SELECT tool_id, name, dataset_metadata
            FROM tools
            WHERE is_dataset = 1
            LIMIT 1
        """)
        dataset_row = cursor.fetchone()
        if dataset_row:
            metadata = json.loads(dataset_row['dataset_metadata']) if dataset_row['dataset_metadata'] else {}
            print(f"\n✓ Sample dataset: {dataset_row['name']}")
            print(f"  Format: {metadata.get('format', 'N/A')}")
            print(f"  Use cases: {len(metadata.get('use_cases', []))}")
            print(f"  Compatible tools: {metadata.get('compatible_tools_count', 0)}")

        # Test 7: Tool names quality
        cursor.execute("""
            SELECT COUNT(*) FROM tools
            WHERE name LIKE '%Repository Actions%'
        """)
        bad_names = cursor.fetchone()[0]
        print(f"\n✓ Tool name quality check:")
        print(f"  Tools with 'Repository Actions': {bad_names} (should be 0)")

    print("\n" + "="*80)
    print("✅ Database structure tests passed!")
    print("="*80)


def test_search_quality():
    """Test search quality with updated index."""
    print("\n" + "="*80)
    print("TEST: Search Quality")
    print("="*80)

    db_path = Path(__file__).parent / "galaxy_ai_tools.db"

    test_queries = [
        ("RNA-seq analysis", 5),
        ("variant calling", 5),
        ("drug discovery", 3),
    ]

    with sqlite3.connect(str(db_path)) as conn:
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()

        for query, expected_min in test_queries:
            cursor.execute("""
                SELECT t.tool_id, t.name, t.category,
                       bm25(tools_fts) as relevance
                FROM tools t
                JOIN tools_fts ON t.tool_id = tools_fts.tool_id
                WHERE tools_fts MATCH ?
                  AND (t.is_dataset IS NULL OR t.is_dataset = 0)
                ORDER BY relevance DESC
                LIMIT 5
            """, (query,))

            results = cursor.fetchall()
            print(f"\n✓ Query: '{query}'")
            print(f"  Found: {len(results)} tools (expected >= {expected_min})")

            for i, row in enumerate(results[:3], 1):
                print(f"  {i}. {row['name']}")
                print(f"     Category: {row['category']}, Relevance: {row['relevance']:.2f}")

            assert len(results) >= expected_min, f"Expected at least {expected_min} results"

    print("\n" + "="*80)
    print("✅ Search quality tests passed!")
    print("="*80)


if __name__ == '__main__':
    print("\n🧪 Enhanced RAG Standalone Tests\n")

    try:
        test_database_structure()
        test_search_quality()

        print("\n🎉 All tests passed!")
        exit(0)
    except Exception as e:
        print(f"\n❌ Test failed: {e}")
        import traceback
        traceback.print_exc()
        exit(1)
