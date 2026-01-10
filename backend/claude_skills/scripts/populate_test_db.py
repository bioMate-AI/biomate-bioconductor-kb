#!/usr/bin/env python3
"""
Populate test database with Claude Skills resources.

Usage:
    python populate_test_db.py              # Create test_tools.db
    python populate_test_db.py --merge      # Merge into galaxy_ai_tools.db
"""

import json
import sqlite3
import argparse
from pathlib import Path
from datetime import datetime

# Paths
SCRIPT_DIR = Path(__file__).parent
DATA_DIR = SCRIPT_DIR.parent / "data"
CLAUDE_SKILLS_DIR = SCRIPT_DIR.parent
BACKEND_DIR = SCRIPT_DIR.parent.parent

TEST_DB = CLAUDE_SKILLS_DIR / "test_tools.db"
PROD_DB = BACKEND_DIR / "galaxy_ai_tools.db"


def get_schema():
    """Get schema from production database."""
    conn = sqlite3.connect(PROD_DB)
    cursor = conn.cursor()
    cursor.execute("SELECT sql FROM sqlite_master WHERE type='table' AND name='tools'")
    schema = cursor.fetchone()[0]
    conn.close()
    return schema


def create_test_db():
    """Create test database with same schema as production."""
    if TEST_DB.exists():
        TEST_DB.unlink()

    schema = get_schema()
    conn = sqlite3.connect(TEST_DB)
    cursor = conn.cursor()
    cursor.execute(schema)
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_tools_category ON tools (category)")
    conn.commit()
    conn.close()
    print(f"Created test database: {TEST_DB}")


def load_json_data():
    """Load all JSON data files."""
    data = {"databases": [], "packages": [], "integrations": []}

    for filename in ["databases.json", "packages.json", "integrations.json"]:
        filepath = DATA_DIR / filename
        if filepath.exists():
            with open(filepath) as f:
                content = json.load(f)
                key = filename.replace(".json", "")
                data[key] = content.get(key, [])

    return data


def insert_tool(cursor, tool_data):
    """Insert a tool into the database."""
    now = datetime.now().isoformat()

    cursor.execute("""
        INSERT INTO tools (
            tool_id, name, category, description,
            inputs, outputs, requirements, help_text,
            scientific_context, tags, examples,
            created_at, updated_at, data_version,
            auto_discovered, discovery_date, quality_score
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, (
        tool_data.get("tool_id"),
        tool_data.get("name"),
        tool_data.get("category"),
        tool_data.get("description"),
        tool_data.get("inputs"),
        tool_data.get("outputs"),
        tool_data.get("requirements"),
        tool_data.get("help_text"),
        tool_data.get("scientific_context"),
        tool_data.get("tags"),
        tool_data.get("examples"),
        now,
        now,
        "claude_skills_v1",
        True,
        now,
        0.8  # Default quality score
    ))


def populate_test_db():
    """Populate test database with all tools."""
    data = load_json_data()

    conn = sqlite3.connect(TEST_DB)
    cursor = conn.cursor()

    counts = {"databases": 0, "packages": 0, "integrations": 0}

    for category, tools in data.items():
        for tool in tools:
            try:
                insert_tool(cursor, tool)
                counts[category] += 1
            except Exception as e:
                print(f"Error inserting {tool.get('tool_id')}: {e}")

    conn.commit()
    conn.close()

    print(f"\nPopulated test database:")
    print(f"  Databases:    {counts['databases']}")
    print(f"  Packages:     {counts['packages']}")
    print(f"  Integrations: {counts['integrations']}")
    print(f"  Total:        {sum(counts.values())}")


def validate_test_db():
    """Run validation queries on test database."""
    conn = sqlite3.connect(TEST_DB)
    cursor = conn.cursor()

    print("\n=== Validation ===")

    # Count by category
    cursor.execute("SELECT category, COUNT(*) FROM tools GROUP BY category ORDER BY COUNT(*) DESC")
    print("\nTools by category:")
    for row in cursor.fetchall():
        print(f"  {row[0]}: {row[1]}")

    # Check tool_id patterns
    cursor.execute("SELECT tool_id, name FROM tools WHERE tool_id LIKE 'biomni/database/%'")
    print("\nDatabase tools:")
    for row in cursor.fetchall():
        print(f"  {row[0]} -> {row[1]}")

    cursor.execute("SELECT tool_id, name FROM tools WHERE tool_id LIKE 'biomni/package/%'")
    print("\nPackage tools:")
    for row in cursor.fetchall():
        print(f"  {row[0]} -> {row[1]}")

    cursor.execute("SELECT tool_id, name FROM tools WHERE tool_id LIKE 'biomni/integration/%'")
    print("\nIntegration tools:")
    for row in cursor.fetchall():
        print(f"  {row[0]} -> {row[1]}")

    # Test a query
    cursor.execute("SELECT * FROM tools WHERE name LIKE '%DeepChem%'")
    result = cursor.fetchone()
    if result:
        print("\nSample query (DeepChem):")
        print(f"  tool_id: {result[1]}")
        print(f"  name: {result[2]}")
        print(f"  category: {result[6]}")

    conn.close()
    print("\n✓ Validation complete")


def merge_to_production():
    """Merge test database into production."""
    # Check for duplicates first
    test_conn = sqlite3.connect(TEST_DB)
    prod_conn = sqlite3.connect(PROD_DB)

    test_cursor = test_conn.cursor()
    prod_cursor = prod_conn.cursor()

    # Get tool_ids from test db
    test_cursor.execute("SELECT tool_id FROM tools")
    test_ids = [row[0] for row in test_cursor.fetchall()]

    # Check for existing
    existing = []
    for tid in test_ids:
        prod_cursor.execute("SELECT tool_id FROM tools WHERE tool_id = ?", (tid,))
        if prod_cursor.fetchone():
            existing.append(tid)

    if existing:
        print(f"Warning: {len(existing)} tools already exist in production:")
        for tid in existing:
            print(f"  - {tid}")
        response = input("Skip duplicates and continue? [y/N]: ")
        if response.lower() != 'y':
            print("Aborted.")
            return

    # Copy non-duplicate tools
    test_cursor.execute("SELECT * FROM tools")
    columns = [desc[0] for desc in test_cursor.description]

    inserted = 0
    for row in test_cursor.fetchall():
        tool_id = row[1]  # tool_id is second column
        if tool_id in existing:
            continue

        placeholders = ",".join(["?" for _ in columns])
        col_names = ",".join(columns)
        prod_cursor.execute(f"INSERT INTO tools ({col_names}) VALUES ({placeholders})", row)
        inserted += 1

    prod_conn.commit()

    test_conn.close()
    prod_conn.close()

    print(f"\n✓ Merged {inserted} tools into production database")

    # Verify
    prod_conn = sqlite3.connect(PROD_DB)
    prod_cursor = prod_conn.cursor()
    prod_cursor.execute("SELECT COUNT(*) FROM tools WHERE tool_id LIKE 'biomni/%'")
    total = prod_cursor.fetchone()[0]
    prod_conn.close()
    print(f"  Total biomni tools in production: {total}")


def main():
    parser = argparse.ArgumentParser(description="Populate test database with Claude Skills")
    parser.add_argument("--merge", action="store_true", help="Merge test db into production")
    parser.add_argument("--validate", action="store_true", help="Only run validation")
    args = parser.parse_args()

    if args.validate:
        if not TEST_DB.exists():
            print(f"Error: Test database not found at {TEST_DB}")
            return
        validate_test_db()
        return

    if args.merge:
        if not TEST_DB.exists():
            print(f"Error: Test database not found at {TEST_DB}")
            return
        merge_to_production()
        return

    # Default: create and populate test db
    create_test_db()
    populate_test_db()
    validate_test_db()


if __name__ == "__main__":
    main()
