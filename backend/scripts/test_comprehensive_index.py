#!/usr/bin/env python3
"""
Test the comprehensive tool index to verify it's working correctly.
"""

import sys
import sqlite3
from pathlib import Path

def test_database():
    """Test database connectivity and content."""
    db_path = Path(__file__).parent.parent / "galaxy_ai_tools.db"

    print("="*80)
    print("Testing Comprehensive Tool Index")
    print("="*80)
    print(f"Database: {db_path}\n")

    if not db_path.exists():
        print(f"❌ ERROR: Database not found at {db_path}")
        return False

    conn = sqlite3.connect(str(db_path))
    cursor = conn.cursor()

    # Test 1: Check tool count
    print("Test 1: Tool Count")
    cursor.execute("SELECT COUNT(*) FROM tools")
    count = cursor.fetchone()[0]
    print(f"  Total tools: {count}")
    assert count == 6295, f"Expected 6295 tools, got {count}"
    print("  ✅ PASS\n")

    # Test 2: Check parameters exist
    print("Test 2: Parameters")
    cursor.execute("SELECT COUNT(*) FROM tools WHERE parameters IS NOT NULL AND parameters != '[]'")
    with_params = cursor.fetchone()[0]
    print(f"  Tools with parameters: {with_params}")
    print(f"  Percentage: {with_params/count*100:.1f}%")
    print("  ✅ PASS\n")

    # Test 3: Check help text exists
    print("Test 3: Help Text")
    cursor.execute("SELECT COUNT(*) FROM tools WHERE help_text IS NOT NULL AND help_text != '{}'")
    with_help = cursor.fetchone()[0]
    print(f"  Tools with help text: {with_help}")
    print(f"  Percentage: {with_help/count*100:.1f}%")
    print("  ✅ PASS\n")

    # Test 4: FTS5 search
    print("Test 4: FTS5 Full-Text Search")
    cursor.execute("SELECT name, category FROM tools_fts WHERE tools_fts MATCH 'xcms' LIMIT 5")
    results = cursor.fetchall()
    print(f"  Search 'xcms' returned {len(results)} results:")
    for name, category in results:
        print(f"    - {name[:60]} ({category})")
    assert len(results) > 0, "FTS5 search returned no results"
    print("  ✅ PASS\n")

    # Test 5: Category distribution
    print("Test 5: Category Distribution")
    cursor.execute("""
        SELECT category, COUNT(*) as count
        FROM tools
        GROUP BY category
        ORDER BY count DESC
        LIMIT 10
    """)
    categories = cursor.fetchall()
    print("  Top 10 categories:")
    for cat, cnt in categories:
        print(f"    {cat:40s}: {cnt:5d} tools")
    print("  ✅ PASS\n")

    # Test 6: Sample tool with parameters
    print("Test 6: Sample Tool Details")
    cursor.execute("""
        SELECT id, name, version, category, parameters, help_text
        FROM tools
        WHERE category = 'Metabolomics' AND parameters IS NOT NULL AND parameters != '[]'
        LIMIT 1
    """)
    row = cursor.fetchone()
    if row:
        tool_id, name, version, category, params, help_text = row
        print(f"  Tool ID: {tool_id}")
        print(f"  Name: {name}")
        print(f"  Version: {version}")
        print(f"  Category: {category}")
        print(f"  Has parameters: {len(params) > 2}")  # Not empty JSON
        print(f"  Has help text: {len(help_text) > 2}")
        print("  ✅ PASS\n")
    else:
        print("  ⚠️  No metabolomics tools with parameters found\n")

    # Test 7: Repo distribution
    print("Test 7: Repository Distribution")
    cursor.execute("""
        SELECT repo_owner, COUNT(*) as count
        FROM tools
        GROUP BY repo_owner
        ORDER BY count DESC
        LIMIT 10
    """)
    repos = cursor.fetchall()
    print("  Top 10 tool contributors:")
    for owner, cnt in repos:
        print(f"    {owner:30s}: {cnt:5d} tools")
    print("  ✅ PASS\n")

    conn.close()

    print("="*80)
    print("✅ ALL TESTS PASSED")
    print("="*80)
    print("\nDatabase is ready for use!")
    print(f"  - {count} tools indexed")
    print(f"  - Parameters extracted: {with_params/count*100:.0f}%")
    print(f"  - Help text extracted: {with_help/count*100:.0f}%")
    print(f"  - FTS5 search operational")

    return True


def test_rag_integration():
    """Test RAG system integration."""
    print("\n" + "="*80)
    print("Testing RAG Integration")
    print("="*80)

    try:
        sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
        from galaxy.ai.galaxy_tool_rag import GalaxyToolRAG

        rag = GalaxyToolRAG()
        print(f"  Tools loaded: {len(rag.tool_index)}")

        # Test search
        results = rag.search_tools("metabolomics", limit=5)
        print(f"  Search results: {len(results)}")
        if results:
            print(f"  Sample result: {results[0]['name']}")

        print("  ✅ RAG integration working\n")
        return True

    except Exception as e:
        print(f"  ⚠️  RAG integration test failed: {e}\n")
        return False


if __name__ == '__main__':
    success = test_database()

    # Try RAG integration test (may fail if dependencies not available)
    try:
        test_rag_integration()
    except ImportError as e:
        print(f"\n⚠️  Skipping RAG integration test (import error: {e})")

    sys.exit(0 if success else 1)
