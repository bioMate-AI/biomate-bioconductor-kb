#!/usr/bin/env python3
"""
Migrate Tool Availability Schema

Adds availability_status and execution_info fields to track tool readiness:

availability_status:
- 'ready': Immediately available (query APIs, built-in)
- 'docker': Available via local Docker container
- 'installable': Requires ToolShed installation
- 'api': External API service
- 'dataset': Data source (not executable tool)

execution_info: JSON with location details:
- For docker: {"image": "biomate/chai1:latest", "gpu": true}
- For api: {"endpoint": "https://api.example.com/predict"}
- For installable: {"toolshed_url": "toolshed.g2.bx.psu.edu/repos/..."}

Usage:
    python migrate_tool_availability.py [--db-path PATH]
"""

import sqlite3
import argparse
import logging
import json
from pathlib import Path

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
log = logging.getLogger(__name__)


def get_default_db_path() -> str:
    """Get default database path."""
    # Try multiple locations
    paths = [
        Path(__file__).parent.parent.parent.parent / "database" / "galaxy_ai_tools.db",
        Path(__file__).parent.parent.parent.parent / "galaxy_ai_tools.db",
        Path("/home/yzhang/biomate/backend/database/galaxy_ai_tools.db"),
    ]
    for p in paths:
        if p.exists():
            return str(p)
    return str(paths[0])


def add_availability_columns(db_path: str):
    """Add availability_status and execution_info columns if they don't exist."""
    log.info(f"Adding availability columns to: {db_path}")

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Check existing columns
    cursor.execute("PRAGMA table_info(tools)")
    columns = {row[1] for row in cursor.fetchall()}

    # Add availability_status column
    if 'availability_status' not in columns:
        cursor.execute('''
            ALTER TABLE tools ADD COLUMN availability_status TEXT DEFAULT 'installable'
        ''')
        log.info("Added availability_status column")
    else:
        log.info("availability_status column already exists")

    # Add execution_info column (JSON)
    if 'execution_info' not in columns:
        cursor.execute('''
            ALTER TABLE tools ADD COLUMN execution_info TEXT
        ''')
        log.info("Added execution_info column")
    else:
        log.info("execution_info column already exists")

    # Add priority_score column for search ranking
    if 'priority_score' not in columns:
        cursor.execute('''
            ALTER TABLE tools ADD COLUMN priority_score INTEGER DEFAULT 0
        ''')
        log.info("Added priority_score column")
    else:
        log.info("priority_score column already exists")

    conn.commit()
    conn.close()
    log.info("Schema migration complete")


def classify_tools(db_path: str):
    """
    Classify existing tools based on their tool_id patterns.

    Priority scores:
    - ready (query APIs): 1000
    - docker (local containers): 800
    - api (external APIs): 600
    - installable (ToolShed): 100
    - dataset: 50
    """
    log.info("Classifying tools by availability...")

    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    # Define classification rules
    classifications = [
        # Biomni query/API tools - immediately ready
        {
            'pattern': "tool_id LIKE 'biomni/%query%' OR tool_id LIKE 'biomni/database/%' OR tool_id LIKE 'biomni/literature/%'",
            'status': 'ready',
            'priority': 1000,
            'info': json.dumps({"type": "biomni_query", "install_required": False})
        },
        # Biomni other tools (may need local setup but not ToolShed)
        {
            'pattern': "tool_id LIKE 'biomni/%' AND tool_id NOT LIKE 'biomni/%query%' AND tool_id NOT LIKE 'biomni/database/%' AND tool_id NOT LIKE 'biomni/literature/%'",
            'status': 'ready',
            'priority': 900,
            'info': json.dumps({"type": "biomni_local", "install_required": False})
        },
        # Biomate AI Tools with Docker (protein structure prediction, etc.)
        {
            'pattern': "tool_id LIKE 'biomate_ai_tools/%'",
            'status': 'docker',
            'priority': 800,
            'info': json.dumps({"type": "biomate_docker", "install_required": False, "gpu_recommended": True})
        },
        # Data lake datasets
        {
            'pattern': "tool_id LIKE 'biomate_dm_%' OR tool_id LIKE '%data_lake%'",
            'status': 'dataset',
            'priority': 50,
            'info': json.dumps({"type": "data_source", "install_required": False})
        },
        # ToolShed tools - require installation
        {
            'pattern': "tool_id LIKE 'toolshed.%'",
            'status': 'installable',
            'priority': 100,
            'info': json.dumps({"type": "toolshed", "install_required": True})
        },
    ]

    total_updated = 0

    for rule in classifications:
        cursor.execute(f'''
            UPDATE tools
            SET availability_status = ?,
                priority_score = ?,
                execution_info = ?
            WHERE {rule['pattern']}
        ''', (rule['status'], rule['priority'], rule['info']))

        updated = cursor.rowcount
        total_updated += updated
        log.info(f"  {rule['status']}: {updated} tools (priority={rule['priority']})")

    conn.commit()

    # Report stats
    cursor.execute('''
        SELECT availability_status, COUNT(*) as count, AVG(priority_score) as avg_priority
        FROM tools
        GROUP BY availability_status
        ORDER BY avg_priority DESC
    ''')

    log.info("\nAvailability summary:")
    for row in cursor.fetchall():
        log.info(f"  {row[0]}: {row[1]} tools (avg priority: {row[2]:.0f})")

    conn.close()
    return total_updated


def update_docker_tools_info(db_path: str):
    """
    Update execution_info for known Docker-based tools with specific image names.
    """
    log.info("Updating Docker tool execution info...")

    # Known Docker images for biomate_ai_tools
    docker_images = {
        'chai1': {"image": "biomate/chai1:latest", "gpu": True, "memory": "16GB"},
        'boltz': {"image": "biomate/boltz:latest", "gpu": True, "memory": "16GB"},
        'boltz2': {"image": "biomate/boltz:latest", "gpu": True, "memory": "16GB"},
        'drugclip': {"image": "biomate/drugclip:latest", "gpu": True, "memory": "8GB"},
        'protrek': {"image": "biomate/protrek:latest", "gpu": True, "memory": "8GB"},
        'profam': {"image": "biomate/profam:latest", "gpu": False, "memory": "4GB"},
        'scfv_pmpnn': {"image": "biomate/scfv-pmpnn:latest", "gpu": True, "memory": "8GB"},
        'syncraft': {"image": "biomate/syncraft:latest", "gpu": False, "memory": "4GB"},
        'state': {"image": "biomate/state:latest", "gpu": False, "memory": "4GB"},
        'evo2': {"image": "biomate/evo2:latest", "gpu": True, "memory": "32GB"},
        'alphafold3': {"image": "biomate/alphafold3:latest", "gpu": True, "memory": "32GB"},
        'genmol': {"image": "biomate/genmol:latest", "gpu": True, "memory": "8GB"},
        'mammal': {"image": "biomate/mammal:latest", "gpu": True, "memory": "16GB"},
        'omnigenome': {"image": "biomate/omnigenome:latest", "gpu": True, "memory": "16GB"},
        'cambrian1': {"image": "biomate/cambrian1:latest", "gpu": True, "memory": "16GB"},
    }

    # API-based tools (external services)
    api_tools = {
        'alphafold_api': {"endpoint": "https://alphafold.ebi.ac.uk/api", "type": "external_api"},
        'esmfold_api': {"endpoint": "https://api.esmatlas.com/foldSequence/v1", "type": "external_api"},
        'chai1_api': {"endpoint": "https://lab.chaidiscovery.com/api", "type": "external_api"},
        'boltz2_api': {"endpoint": "https://boltz.mit.edu/api", "type": "external_api"},
        'evo2_api': {"endpoint": "https://evo2.arc.io/api", "type": "external_api"},
    }

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Update Docker tools
    for tool_name, info in docker_images.items():
        info['type'] = 'biomate_docker'
        info['install_required'] = False
        cursor.execute('''
            UPDATE tools
            SET execution_info = ?,
                availability_status = 'docker',
                priority_score = 800
            WHERE tool_id LIKE ? OR name LIKE ?
        ''', (json.dumps(info), f'%{tool_name}%', f'%{tool_name}%'))
        if cursor.rowcount > 0:
            log.info(f"  Updated {tool_name}: {cursor.rowcount} tools")

    # Update API tools
    for tool_name, info in api_tools.items():
        info['install_required'] = False
        cursor.execute('''
            UPDATE tools
            SET execution_info = ?,
                availability_status = 'api',
                priority_score = 600
            WHERE tool_id LIKE ? OR name LIKE ?
        ''', (json.dumps(info), f'%{tool_name}%', f'%{tool_name}%'))
        if cursor.rowcount > 0:
            log.info(f"  Updated {tool_name} (API): {cursor.rowcount} tools")

    conn.commit()
    conn.close()


def rebuild_fts5_index(db_path: str):
    """Rebuild FTS5 index to include new availability columns."""
    log.info("Rebuilding FTS5 index with availability data...")

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Check existing columns
    cursor.execute("PRAGMA table_info(tools)")
    columns = {row[1] for row in cursor.fetchall()}

    # Drop and recreate FTS5
    cursor.execute('DROP TABLE IF EXISTS tools_fts')

    # Include availability_status in FTS5 for searchability
    fts_columns = ['tool_id', 'name', 'description', 'category', 'parameters',
                   'help_text', 'availability_status']

    optional_columns = ['keywords', 'tags', 'edam_operations', 'edam_topics']
    for col in optional_columns:
        if col in columns:
            fts_columns.append(col)

    fts_columns_str = ', '.join(fts_columns)
    cursor.execute(f'''
        CREATE VIRTUAL TABLE tools_fts USING fts5(
            {fts_columns_str},
            tokenize='porter unicode61'
        )
    ''')

    # Build INSERT query with COALESCE for NULL handling
    select_parts = []
    for col in fts_columns:
        if col in ['description', 'parameters', 'help_text', 'keywords', 'tags',
                   'edam_operations', 'edam_topics', 'availability_status']:
            select_parts.append(f"COALESCE({col}, '')")
        else:
            select_parts.append(col)

    select_str = ', '.join(select_parts)
    cursor.execute(f'''
        INSERT INTO tools_fts
        SELECT {select_str}
        FROM tools
    ''')

    cursor.execute('SELECT COUNT(*) FROM tools_fts')
    count = cursor.fetchone()[0]

    conn.commit()
    conn.close()

    log.info(f"FTS5 index rebuilt: {count} tools indexed")
    return count


def main():
    parser = argparse.ArgumentParser(description='Migrate tool availability schema')
    parser.add_argument('--db-path', help='Path to database', default=None)
    parser.add_argument('--skip-fts', action='store_true', help='Skip FTS5 rebuild')
    args = parser.parse_args()

    db_path = args.db_path or get_default_db_path()

    if not Path(db_path).exists():
        log.error(f"Database not found: {db_path}")
        return 1

    log.info(f"Migrating database: {db_path}")

    # Step 1: Add columns
    add_availability_columns(db_path)

    # Step 2: Classify existing tools
    classify_tools(db_path)

    # Step 3: Update Docker tools with specific info
    update_docker_tools_info(db_path)

    # Step 4: Rebuild FTS5 index
    if not args.skip_fts:
        rebuild_fts5_index(db_path)

    log.info("\nMigration complete!")
    return 0


if __name__ == '__main__':
    exit(main())
