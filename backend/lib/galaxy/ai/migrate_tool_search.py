#!/usr/bin/env python3
"""
Migrate Tool Search Index

Enhances the FTS5 index and optionally generates vector embeddings.

Usage:
    python migrate_tool_search.py [--db-path PATH] [--skip-embeddings]
"""

import sqlite3
import argparse
import logging
from pathlib import Path

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
log = logging.getLogger(__name__)


def get_default_db_path() -> str:
    """Get default database path."""
    return str(Path(__file__).parent.parent.parent.parent / "galaxy_ai_tools.db")


def migrate_fts5(db_path: str):
    """
    Recreate FTS5 index with more columns and porter stemming.

    Adds to index:
    - keywords
    - tags
    - edam_operations
    - edam_topics

    Uses porter stemming for better matching.
    """
    log.info(f"Migrating FTS5 index: {db_path}")

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Check existing columns in tools table
    cursor.execute("PRAGMA table_info(tools)")
    columns = {row[1] for row in cursor.fetchall()}
    log.info(f"Found {len(columns)} columns in tools table")

    # Drop existing FTS5
    cursor.execute('DROP TABLE IF EXISTS tools_fts')
    log.info("Dropped existing tools_fts table")

    # Determine which columns to include in FTS5
    fts_columns = ['tool_id', 'name', 'description', 'category', 'parameters', 'help_text']

    optional_columns = ['keywords', 'tags', 'edam_operations', 'edam_topics']
    for col in optional_columns:
        if col in columns:
            fts_columns.append(col)
            log.info(f"Including column in FTS5: {col}")

    # Create enhanced FTS5 with porter stemming
    fts_columns_str = ', '.join(fts_columns)
    cursor.execute(f'''
        CREATE VIRTUAL TABLE tools_fts USING fts5(
            {fts_columns_str},
            tokenize='porter unicode61'
        )
    ''')
    log.info(f"Created FTS5 table with columns: {fts_columns_str}")

    # Build INSERT query with COALESCE for NULL handling
    select_parts = []
    for col in fts_columns:
        if col in ['description', 'parameters', 'help_text', 'keywords', 'tags',
                   'edam_operations', 'edam_topics']:
            select_parts.append(f"COALESCE({col}, '')")
        else:
            select_parts.append(col)

    select_str = ', '.join(select_parts)
    cursor.execute(f'''
        INSERT INTO tools_fts
        SELECT {select_str}
        FROM tools
    ''')

    # Get count
    cursor.execute('SELECT COUNT(*) FROM tools_fts')
    count = cursor.fetchone()[0]

    conn.commit()
    conn.close()

    log.info(f"FTS5 index migrated successfully: {count} tools indexed")
    return count


def generate_embeddings(db_path: str, force: bool = False):
    """
    Generate vector embeddings for all tools.

    Requires sentence-transformers package.
    """
    embedding_path = db_path.replace('.db', '_embeddings.npz')

    if Path(embedding_path).exists() and not force:
        log.info(f"Embeddings already exist: {embedding_path}")
        log.info("Use --force to regenerate")
        return

    try:
        from sentence_transformers import SentenceTransformer
        import numpy as np
        from .vector_search import _detect_device_safe
    except ImportError:
        log.warning("sentence-transformers not installed. Skipping embeddings.")
        log.info("Install with: pip install sentence-transformers")
        return

    model_name = 'all-MiniLM-L6-v2'
    device = _detect_device_safe(timeout_seconds=5.0)
    log.info(f"Loading model: {model_name} on device: {device}")
    model = SentenceTransformer(model_name, device=device)

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute('''
        SELECT tool_id, name, description, category, help_text, tags,
               edam_operations, edam_topics
        FROM tools
    ''')

    tool_ids = []
    texts = []

    for row in cursor.fetchall():
        tool_id, name, desc, category, help_text, tags, edam_ops, edam_topics = row
        tool_ids.append(tool_id)

        # Create rich text representation
        parts = [name]
        if desc:
            parts.append(desc[:500])
        if category:
            parts.append(f"Category: {category}")
        if help_text:
            parts.append(f"Help: {help_text[:300]}")
        if tags:
            parts.append(f"Tags: {tags}")
        if edam_ops:
            parts.append(f"Operations: {edam_ops}")
        if edam_topics:
            parts.append(f"Topics: {edam_topics}")

        text = ". ".join(parts)
        texts.append(text)

    conn.close()

    log.info(f"Generating embeddings for {len(texts)} tools...")
    embeddings = model.encode(texts, show_progress_bar=True, batch_size=64)

    log.info(f"Saving embeddings to: {embedding_path}")
    np.savez_compressed(
        embedding_path,
        tool_ids=np.array(tool_ids, dtype=object),
        embeddings=embeddings
    )

    log.info(f"Embeddings saved: shape={embeddings.shape}")


def verify_migration(db_path: str):
    """Verify the migration was successful."""
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Check FTS5 table exists
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='tools_fts'")
    if not cursor.fetchone():
        log.error("FTS5 table not found!")
        return False

    # Test FTS5 search
    test_queries = ['uniprot', 'protein', 'cell', 'image', 'alignment']
    for query in test_queries:
        cursor.execute('''
            SELECT COUNT(*) FROM tools_fts WHERE tools_fts MATCH ?
        ''', (query,))
        count = cursor.fetchone()[0]
        log.info(f"Test query '{query}': {count} results")

    conn.close()

    # Check embeddings
    embedding_path = db_path.replace('.db', '_embeddings.npz')
    if Path(embedding_path).exists():
        import numpy as np
        data = np.load(embedding_path, allow_pickle=True)
        log.info(f"Embeddings: {len(data['tool_ids'])} tools, "
                f"shape={data['embeddings'].shape}")
    else:
        log.info("Embeddings not found (optional)")

    return True


def main():
    parser = argparse.ArgumentParser(description='Migrate tool search index')
    parser.add_argument('--db-path', default=None, help='Path to database')
    parser.add_argument('--skip-embeddings', action='store_true',
                       help='Skip embedding generation')
    parser.add_argument('--force', action='store_true',
                       help='Force regenerate embeddings')
    parser.add_argument('--verify-only', action='store_true',
                       help='Only verify existing migration')

    args = parser.parse_args()

    db_path = args.db_path or get_default_db_path()

    if not Path(db_path).exists():
        log.error(f"Database not found: {db_path}")
        return 1

    log.info(f"Database: {db_path}")

    if args.verify_only:
        verify_migration(db_path)
        return 0

    # Run migration
    migrate_fts5(db_path)

    if not args.skip_embeddings:
        generate_embeddings(db_path, force=args.force)

    # Verify
    verify_migration(db_path)

    log.info("Migration complete!")
    return 0


if __name__ == '__main__':
    exit(main())
