#!/usr/bin/env python3
"""
Add enhanced metadata columns to tools table

Adds columns for:
- dependencies (JSON): List of dependencies with package manager info
- test_commands (JSON): Test commands extracted from CI/docs
- install_commands (JSON): Installation instructions
- usage_examples (TEXT): Usage examples from docs (separate from examples field)
"""

import sqlite3
import logging
from pathlib import Path

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def add_enhanced_metadata_columns(db_path: Path):
    """Add enhanced metadata columns to tools table"""

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Check which columns already exist
    cursor.execute("PRAGMA table_info(tools)")
    existing_columns = {row[1] for row in cursor.fetchall()}

    columns_to_add = {
        'dependencies': 'TEXT',  # JSON: [{package_manager: pip, dependency: numpy}, ...]
        'test_commands': 'TEXT',  # JSON: [pytest, make test, ...]
        'install_commands': 'TEXT',  # JSON: [pip install, conda install, ...]
        'container_info': 'TEXT',  # JSON: {type: docker, image: ..., tested: true}
    }

    added = 0
    for column_name, column_type in columns_to_add.items():
        if column_name not in existing_columns:
            try:
                logger.info(f"Adding column: {column_name} ({column_type})")
                cursor.execute(f"ALTER TABLE tools ADD COLUMN {column_name} {column_type}")
                added += 1
                logger.info(f"✓ Added column: {column_name}")
            except sqlite3.OperationalError as e:
                logger.warning(f"Could not add column {column_name}: {e}")
        else:
            logger.info(f"Column {column_name} already exists")

    conn.commit()
    conn.close()

    logger.info(f"Schema update complete: {added} columns added")
    return added


if __name__ == '__main__':
    import sys

    if len(sys.argv) > 1:
        db_path = Path(sys.argv[1])
    else:
        db_path = Path(__file__).parent.parent.parent / 'backend' / 'galaxy_ai_tools.db'

    if not db_path.exists():
        logger.error(f"Database not found: {db_path}")
        sys.exit(1)

    logger.info(f"Updating database: {db_path}")
    added = add_enhanced_metadata_columns(db_path)

    if added > 0:
        logger.info(f"✓ Successfully added {added} columns to tools table")
    else:
        logger.info("No changes needed - all columns already exist")
