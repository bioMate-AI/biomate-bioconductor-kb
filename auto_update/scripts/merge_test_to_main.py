#!/usr/bin/env python3
"""
Merge Test Database to Main Database

Merges validated tools from the test database into the main AI tool index.
Performs verification before merging to ensure data integrity.

Usage:
    python merge_test_to_main.py
    python merge_test_to_main.py --dry-run
    python merge_test_to_main.py --tool-ids auto_tool1 auto_tool2
"""

import argparse
import json
import sqlite3
from pathlib import Path
import logging
from typing import List, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_tool(conn: sqlite3.Connection, tool_id: str) -> bool:
    """Verify tool has complete enhanced metadata"""

    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    cursor.execute("""
        SELECT
            tool_id, name, version,
            dependencies, test_commands, install_commands, container_info
        FROM tools
        WHERE tool_id = ?
    """, (tool_id,))

    tool = cursor.fetchone()

    if not tool:
        logger.error(f"❌ Tool not found: {tool_id}")
        return False

    # Check enhanced metadata
    has_deps = bool(tool['dependencies'])
    has_tests = bool(tool['test_commands'])
    has_install = bool(tool['install_commands'])
    has_container = bool(tool['container_info'])

    logger.info(f"Tool: {tool['name']} (v{tool['version']})")
    logger.info(f"  Dependencies: {'✓' if has_deps else '✗'}")
    logger.info(f"  Test commands: {'✓' if has_tests else '✗'}")
    logger.info(f"  Install commands: {'✓' if has_install else '✗'}")
    logger.info(f"  Container info: {'✓' if has_container else '✗'}")

    if not (has_deps or has_tests or has_install):
        logger.warning(f"⚠️  Tool {tool_id} has minimal enhanced metadata")
        return False

    return True


def get_all_fields(cursor: sqlite3.Cursor, table: str = 'tools') -> List[str]:
    """Get all column names from table"""
    cursor.execute(f"PRAGMA table_info({table})")
    return [row[1] for row in cursor.fetchall()]


def merge_tool(test_conn: sqlite3.Connection, main_conn: sqlite3.Connection, tool_id: str, dry_run: bool = False) -> bool:
    """Merge single tool from test to main database"""

    test_cursor = test_conn.cursor()
    main_cursor = main_conn.cursor()

    # Get all field names
    fields = get_all_fields(test_cursor)

    # Get tool data from test database
    fields_str = ', '.join(fields)
    test_cursor.execute(f"SELECT {fields_str} FROM tools WHERE tool_id = ?", (tool_id,))
    tool_data = test_cursor.fetchone()

    if not tool_data:
        logger.error(f"❌ Tool {tool_id} not found in test database")
        return False

    # Check if tool already exists in main database
    main_cursor.execute("SELECT tool_id, version FROM tools WHERE tool_id = ?", (tool_id,))
    existing = main_cursor.fetchone()

    if existing:
        logger.warning(f"⚠️  Tool {tool_id} already exists in main database (version: {existing[1]})")
        response = input("Overwrite? (y/N): ") if not dry_run else 'n'
        if response.lower() != 'y':
            logger.info(f"Skipped {tool_id}")
            return False

        # Delete existing
        if not dry_run:
            main_cursor.execute("DELETE FROM tools WHERE tool_id = ?", (tool_id,))
            logger.info(f"Deleted existing entry for {tool_id}")

    # Prepare insert
    placeholders = ', '.join(['?' for _ in fields])
    insert_sql = f"INSERT INTO tools ({fields_str}) VALUES ({placeholders})"

    if dry_run:
        logger.info(f"[DRY RUN] Would insert tool: {tool_id}")
        return True

    # Insert tool
    try:
        main_cursor.execute(insert_sql, tool_data)
        main_conn.commit()
        logger.info(f"✓ Merged tool: {tool_id}")
        return True
    except sqlite3.IntegrityError as e:
        logger.error(f"❌ Failed to merge {tool_id}: {e}")
        main_conn.rollback()
        return False


def merge_tools(test_db: Path, main_db: Path, tool_ids: Optional[List[str]] = None, dry_run: bool = False):
    """
    Merge tools from test database to main database.

    Args:
        test_db: Path to test database
        main_db: Path to main database
        tool_ids: Specific tool IDs to merge (None = all)
        dry_run: If True, show what would be done without actually doing it
    """

    test_conn = sqlite3.connect(test_db)
    main_conn = sqlite3.connect(main_db)

    test_cursor = test_conn.cursor()

    # Get tools to merge
    if tool_ids:
        logger.info(f"Merging specific tools: {tool_ids}")
        tools_to_merge = tool_ids
    else:
        test_cursor.execute("SELECT tool_id FROM tools WHERE auto_discovered = 1 ORDER BY discovery_date DESC")
        tools_to_merge = [row[0] for row in test_cursor.fetchall()]
        logger.info(f"Found {len(tools_to_merge)} auto-discovered tools in test database")

    if not tools_to_merge:
        logger.warning("No tools to merge")
        test_conn.close()
        main_conn.close()
        return

    # Verify and merge each tool
    success_count = 0
    failed_count = 0

    for tool_id in tools_to_merge:
        logger.info(f"\n{'='*60}")
        logger.info(f"Processing: {tool_id}")
        logger.info(f"{'='*60}")

        # Verify tool
        if not verify_tool(test_conn, tool_id):
            logger.warning(f"Skipping {tool_id} - verification failed")
            failed_count += 1
            continue

        # Merge tool
        if merge_tool(test_conn, main_conn, tool_id, dry_run):
            success_count += 1
        else:
            failed_count += 1

    test_conn.close()
    main_conn.close()

    # Summary
    logger.info(f"\n{'='*60}")
    logger.info("MERGE SUMMARY")
    logger.info(f"{'='*60}")
    logger.info(f"Total tools: {len(tools_to_merge)}")
    logger.info(f"Successfully merged: {success_count}")
    logger.info(f"Failed/Skipped: {failed_count}")

    if dry_run:
        logger.info("\n[DRY RUN] No changes were made")
        logger.info("Run without --dry-run to actually merge tools")


if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description='Merge validated tools from test database to main database'
    )
    parser.add_argument(
        '--test-db',
        type=str,
        default='../backend/galaxy_ai_tools_test.db',
        help='Test database path'
    )
    parser.add_argument(
        '--main-db',
        type=str,
        default='../backend/galaxy_ai_tools.db',
        help='Main database path'
    )
    parser.add_argument(
        '--tool-ids',
        nargs='+',
        help='Specific tool IDs to merge'
    )
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Show what would be done without actually doing it'
    )

    args = parser.parse_args()

    test_db = Path(__file__).parent.parent / args.test_db
    main_db = Path(__file__).parent.parent / args.main_db

    if not test_db.exists():
        logger.error(f"Test database not found: {test_db}")
        exit(1)

    if not main_db.exists():
        logger.error(f"Main database not found: {main_db}")
        exit(1)

    logger.info("="*60)
    logger.info("Merge Test Database to Main Database")
    logger.info("="*60)
    logger.info(f"Test DB: {test_db}")
    logger.info(f"Main DB: {main_db}")
    logger.info(f"Dry run: {args.dry_run}")
    logger.info("")

    merge_tools(test_db, main_db, args.tool_ids, args.dry_run)
