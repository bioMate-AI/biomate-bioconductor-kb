#!/usr/bin/env python3
"""
Add scientific context metadata to all tools for ACE learning system integration.

This script:
1. Adds a scientific_context column to the tools table (if not exists)
2. Extracts scientific context from existing rawText and help_text fields
3. Populates the column with extracted context as JSON

The scientific context enables ACE learning by providing:
- Data type compatibility (DDA vs DIA, etc.)
- Typical use cases
- Common mistakes
- Tool limitations
- Best use scenarios
"""

import sqlite3
import json
from pathlib import Path
from typing import Dict
import sys

# Import the extraction functions
sys.path.insert(0, str(Path(__file__).parent))
from extract_scientific_context import extract_scientific_context


def add_scientific_context_column(db_path: str):
    """Add scientific_context column to tools table if it doesn't exist."""
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Check if column exists
    cursor.execute("PRAGMA table_info(tools)")
    columns = [row[1] for row in cursor.fetchall()]

    if 'scientific_context' not in columns:
        print("Adding scientific_context column to tools table...")
        cursor.execute("ALTER TABLE tools ADD COLUMN scientific_context TEXT")
        conn.commit()
        print("✅ Column added")
    else:
        print("ℹ️  scientific_context column already exists")

    conn.close()


def populate_scientific_context(db_path: str, limit: int = None):
    """
    Populate scientific_context for all tools.

    Args:
        db_path: Path to database
        limit: Optional limit for testing (e.g., 100 tools)
    """
    print("=" * 80)
    print("Populating Scientific Context for All Tools")
    print("=" * 80)
    print()

    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    # Get all tools
    query = "SELECT id, tool_id, name, version, category, description, rawText, help_text FROM tools"
    if limit:
        query += f" LIMIT {limit}"

    cursor.execute(query)
    tools = cursor.fetchall()

    print(f"Processing {len(tools)} tools...")
    if limit:
        print(f"⚠️  Testing mode: Limited to {limit} tools")
    print()

    stats = {
        'total': len(tools),
        'updated': 0,
        'with_rich_context': 0,
        'with_data_types': 0,
        'with_use_cases': 0,
        'errors': 0,
        'by_category': {}
    }

    for i, tool in enumerate(tools, 1):
        try:
            # Extract scientific context
            context = extract_scientific_context(
                tool_name=tool['name'] or '',
                category=tool['category'] or '',
                raw_text=tool['rawText'] or '',
                help_text=tool['help_text'] or '',
                description=tool['description'] or ''
            )

            # Update database
            cursor.execute(
                "UPDATE tools SET scientific_context = ? WHERE id = ?",
                (json.dumps(context), tool['id'])
            )

            # Update stats
            stats['updated'] += 1
            if context['has_rich_context']:
                stats['with_rich_context'] += 1
            if context['data_types']['supported'] or context['data_types']['not_supported']:
                stats['with_data_types'] += 1
            if context['typical_use_cases']:
                stats['with_use_cases'] += 1

            category = tool['category'] or 'Unknown'
            if category not in stats['by_category']:
                stats['by_category'][category] = {
                    'total': 0,
                    'with_context': 0,
                    'with_data_types': 0
                }
            stats['by_category'][category]['total'] += 1
            if context['has_rich_context']:
                stats['by_category'][category]['with_context'] += 1
            if context['data_types']['supported'] or context['data_types']['not_supported']:
                stats['by_category'][category]['with_data_types'] += 1

            # Progress indicator
            if i % 500 == 0:
                print(f"  Processed {i}/{len(tools)} tools...")
                conn.commit()

        except Exception as e:
            stats['errors'] += 1
            if stats['errors'] <= 5:
                print(f"  ⚠️  Error processing {tool['name']}: {str(e)}")

    conn.commit()
    conn.close()

    # Print summary
    print()
    print("=" * 80)
    print("✅ Scientific Context Populated")
    print("=" * 80)
    print(f"   Total processed: {stats['total']}")
    print(f"   Successfully updated: {stats['updated']}")
    print(f"   With rich context: {stats['with_rich_context']} ({stats['with_rich_context']/stats['total']*100:.1f}%)")
    print(f"   With data type info: {stats['with_data_types']} ({stats['with_data_types']/stats['total']*100:.1f}%)")
    print(f"   With use cases: {stats['with_use_cases']} ({stats['with_use_cases']/stats['total']*100:.1f}%)")
    print(f"   Errors: {stats['errors']}")
    print()

    # Print category breakdown
    print("📊 By Category (top 10 with most context):")
    sorted_categories = sorted(
        stats['by_category'].items(),
        key=lambda x: x[1]['with_context'],
        reverse=True
    )
    for category, cat_stats in sorted_categories[:10]:
        pct = cat_stats['with_context'] / cat_stats['total'] * 100 if cat_stats['total'] > 0 else 0
        data_types = cat_stats['with_data_types']
        print(f"   {category:30} {cat_stats['total']:4} tools  →  {cat_stats['with_context']:4} with context ({pct:5.1f}%)  →  {data_types:4} with data types")

    return stats


def show_examples(db_path: str, category: str = "Proteomics", limit: int = 3):
    """Show example tools with extracted context."""
    print()
    print("=" * 80)
    print(f"Example Tools with Scientific Context ({category})")
    print("=" * 80)

    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    cursor.execute("""
        SELECT name, category, scientific_context
        FROM tools
        WHERE category = ? AND scientific_context IS NOT NULL
        LIMIT ?
    """, (category, limit))

    tools = cursor.fetchall()

    for tool in tools:
        print()
        print(f"🔧 {tool['name']}")
        print("-" * 80)
        context = json.loads(tool['scientific_context'])

        if context['data_types']['supported']:
            print(f"   ✅ Supports: {', '.join(context['data_types']['supported'])}")
        if context['data_types']['not_supported']:
            print(f"   ❌ Not for: {', '.join(context['data_types']['not_supported'])}")

        if context['typical_use_cases']:
            print(f"   📋 Use cases: {context['typical_use_cases'][:2]}")

        if context['best_for']:
            print(f"   ⭐ Best for: {context['best_for'][:2]}")

        if context['limitations']:
            print(f"   ⚠️  Limitations: {context['limitations'][:2]}")

    conn.close()


def main():
    """Main function."""
    import argparse

    parser = argparse.ArgumentParser(
        description='Add scientific context to tools for ACE learning system'
    )
    parser.add_argument(
        '--test',
        action='store_true',
        help='Test mode: only process 100 tools'
    )
    parser.add_argument(
        '--examples',
        action='store_true',
        help='Show example tools after processing'
    )
    parser.add_argument(
        '--db',
        type=str,
        default=None,
        help='Path to database (default: ../database/galaxy_ai_tools.db)'
    )

    args = parser.parse_args()

    # Determine database path
    if args.db:
        db_path = Path(args.db)
    else:
        db_path = Path(__file__).parent.parent / "database" / "galaxy_ai_tools.db"

    if not db_path.exists():
        print(f"❌ Database not found at {db_path}")
        return 1

    print(f"📁 Database: {db_path}")
    print()

    try:
        # Add column if needed
        add_scientific_context_column(str(db_path))
        print()

        # Populate context
        limit = 100 if args.test else None
        stats = populate_scientific_context(str(db_path), limit=limit)

        # Show examples
        if args.examples and stats['with_rich_context'] > 0:
            show_examples(str(db_path))

        print()
        print("✅ Done! Scientific context has been added to all tools.")
        print()
        print("This context enables ACE learning system to:")
        print("  • Understand data type compatibility (DDA vs DIA, etc.)")
        print("  • Avoid common mistakes (using wrong tool for data type)")
        print("  • Suggest appropriate tools based on use case")
        print("  • Learn from execution feedback to refine recommendations")

        return 0

    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == '__main__':
    sys.exit(main())
