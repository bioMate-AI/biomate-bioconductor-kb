#!/usr/bin/env python3
"""
Create Test Database for Auto-Update Pipeline

Creates a separate test database to validate new tools before merging into
the main AI tool index. This prevents invalid entries from polluting the
production database.

Usage:
    python create_test_database.py
    python create_test_database.py --db-path ../backend/galaxy_ai_tools_test.db
"""

import argparse
import shutil
import sqlite3
from pathlib import Path
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def create_test_database(source_db: Path, test_db: Path, copy_schema_only: bool = True):
    """
    Create test database with same schema as main database.

    Args:
        source_db: Path to main database (for schema)
        test_db: Path to test database to create
        copy_schema_only: If True, copy schema only; if False, copy all data
    """

    if test_db.exists():
        logger.warning(f"Test database already exists: {test_db}")
        response = input("Overwrite? (y/N): ")
        if response.lower() != 'y':
            logger.info("Aborted")
            return False
        test_db.unlink()

    if copy_schema_only:
        # Copy entire database then clear data
        logger.info(f"Copying database and clearing data from: {source_db}")
        shutil.copy2(source_db, test_db)

        # Clear all data from tools table
        test_conn = sqlite3.connect(test_db)
        test_cursor = test_conn.cursor()

        # Get list of tables
        test_cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")
        tables = [row[0] for row in test_cursor.fetchall()]

        # Delete all data from each table
        for table in tables:
            if table.startswith('tools_fts'):
                continue  # Skip FTS tables
            try:
                logger.info(f"Clearing data from: {table}")
                test_cursor.execute(f"DELETE FROM {table}")
            except sqlite3.OperationalError as e:
                logger.warning(f"Could not clear {table}: {e}")

        test_conn.commit()
        test_conn.close()

        logger.info(f"✓ Created test database with empty tables: {test_db}")

    else:
        # Copy entire database
        logger.info(f"Copying entire database to: {test_db}")
        shutil.copy2(source_db, test_db)
        logger.info(f"✓ Copied database: {test_db}")

    # Verify
    test_conn = sqlite3.connect(test_db)
    test_cursor = test_conn.cursor()

    test_cursor.execute("SELECT name FROM sqlite_master WHERE type='table'")
    tables = test_cursor.fetchall()

    test_cursor.execute("SELECT COUNT(*) FROM tools")
    count = test_cursor.fetchone()[0]

    test_conn.close()

    logger.info(f"✓ Test database ready:")
    logger.info(f"  Tables: {len(tables)}")
    logger.info(f"  Tools count: {count}")
    logger.info(f"  Path: {test_db}")

    return True


def verify_enhanced_metadata_schema(db_path: Path):
    """Verify that enhanced metadata columns exist"""

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute("PRAGMA table_info(tools)")
    columns = {row[1] for row in cursor.fetchall()}

    required_columns = {
        'dependencies',
        'test_commands',
        'install_commands',
        'container_info'
    }

    missing = required_columns - columns

    if missing:
        logger.error(f"❌ Missing enhanced metadata columns: {missing}")
        logger.error(f"   Run: python add_enhanced_metadata_columns.py {db_path}")
        conn.close()
        return False

    logger.info(f"✓ All enhanced metadata columns present")
    conn.close()
    return True


if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description='Create test database for auto-update pipeline'
    )
    parser.add_argument(
        '--source-db',
        type=str,
        default='../backend/galaxy_ai_tools.db',
        help='Source database path (for schema)'
    )
    parser.add_argument(
        '--test-db',
        type=str,
        default='../backend/galaxy_ai_tools_test.db',
        help='Test database path to create'
    )
    parser.add_argument(
        '--copy-data',
        action='store_true',
        help='Copy data too (not just schema)'
    )

    args = parser.parse_args()

    source_db = Path(__file__).parent.parent / args.source_db
    test_db = Path(__file__).parent.parent / args.test_db

    if not source_db.exists():
        logger.error(f"Source database not found: {source_db}")
        exit(1)

    logger.info("="*60)
    logger.info("Creating Test Database for Auto-Update Pipeline")
    logger.info("="*60)
    logger.info(f"Source: {source_db}")
    logger.info(f"Test DB: {test_db}")
    logger.info(f"Copy data: {args.copy_data}")
    logger.info("")

    success = create_test_database(
        source_db,
        test_db,
        copy_schema_only=not args.copy_data
    )

    if success:
        logger.info("")
        logger.info("="*60)
        logger.info("Verifying Enhanced Metadata Schema")
        logger.info("="*60)
        verify_enhanced_metadata_schema(test_db)

        logger.info("")
        logger.info("="*60)
        logger.info("✓ Test Database Ready")
        logger.info("="*60)
        logger.info("")
        logger.info("Next steps:")
        logger.info("1. Update run_pipeline.py to use test database")
        logger.info("2. Run pipeline with test database")
        logger.info("3. Verify tools with: python verify_enhanced_metadata.py {test_db}")
        logger.info("4. Merge to main DB when ready: python merge_test_to_main.py")
