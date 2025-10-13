#!/usr/bin/env python3
"""
Add datasets to tool index with version tracking and logging.

This script:
1. Adds timestamp columns to tools table for version tracking
2. Creates an update_log table for tracking all changes
3. Adds datasets as tools (both standalone and as parameters)
4. Populates tool_compatibility table with dataset-tool mappings
5. Updates FTS index for full-text search
"""
import json
import sqlite3
import os
from datetime import datetime
from typing import Dict, Any, List
from pathlib import Path

# Configuration
GALAXY_TOOLS_DB = "/Users/jingqiwang/biomate/backend/galaxy_ai_tools.db"
REFERENCE_DATA_JSON = "/Users/jingqiwang/biomate/backend/reference_data_with_compatible_tools.json"
LOG_DIR = "/Users/jingqiwang/biomate/backend/logs"
os.makedirs(LOG_DIR, exist_ok=True)

# Timestamp for this update
UPDATE_TIMESTAMP = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
UPDATE_VERSION = datetime.now().strftime("%Y%m%d_%H%M%S")


class ToolIndexUpdater:
    """Manages dataset integration into tool index with version tracking"""

    def __init__(self, db_path: str):
        self.db_path = db_path
        self.conn = sqlite3.connect(db_path)
        self.cursor = self.conn.cursor()
        self.log_file = os.path.join(LOG_DIR, f"tool_index_update_{UPDATE_VERSION}.log")
        self.changes = []

    def log(self, message: str, level: str = "INFO"):
        """Log message to both console and file"""
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        log_entry = f"[{timestamp}] [{level}] {message}"
        print(log_entry)
        with open(self.log_file, 'a') as f:
            f.write(log_entry + "\n")
        self.changes.append(log_entry)

    def enhance_schema(self):
        """Add version tracking columns and update log table"""
        self.log("Enhancing database schema for version tracking...")

        # Check if columns already exist
        self.cursor.execute("PRAGMA table_info(tools)")
        columns = {col[1] for col in self.cursor.fetchall()}

        # Add timestamp columns if they don't exist (SQLite doesn't allow CURRENT_TIMESTAMP in ALTER)
        if 'created_at' not in columns:
            self.cursor.execute("ALTER TABLE tools ADD COLUMN created_at TEXT")
            self.log("Added 'created_at' column to tools table")

        if 'updated_at' not in columns:
            self.cursor.execute("ALTER TABLE tools ADD COLUMN updated_at TEXT")
            self.log("Added 'updated_at' column to tools table")

        if 'data_version' not in columns:
            self.cursor.execute("ALTER TABLE tools ADD COLUMN data_version TEXT")
            self.log("Added 'data_version' column to tools table")

        if 'is_dataset' not in columns:
            self.cursor.execute("ALTER TABLE tools ADD COLUMN is_dataset INTEGER")
            # Update existing rows to have is_dataset = 0
            self.cursor.execute("UPDATE tools SET is_dataset = 0 WHERE is_dataset IS NULL")
            self.log("Added 'is_dataset' column to tools table")

        if 'dataset_metadata' not in columns:
            self.cursor.execute("ALTER TABLE tools ADD COLUMN dataset_metadata TEXT")
            self.log("Added 'dataset_metadata' column for JSON metadata")

        # Create update_log table if it doesn't exist
        self.cursor.execute("""
            CREATE TABLE IF NOT EXISTS update_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT,
                update_version TEXT,
                update_type TEXT,
                description TEXT,
                items_added INTEGER DEFAULT 0,
                items_updated INTEGER DEFAULT 0,
                items_deleted INTEGER DEFAULT 0,
                status TEXT,
                details TEXT
            )
        """)
        self.log("Created/verified update_log table")

        # Create dataset_tool_mapping table for explicit dataset-as-parameter relationships
        self.cursor.execute("""
            CREATE TABLE IF NOT EXISTS dataset_tool_mapping (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                dataset_tool_id TEXT,
                target_tool_id TEXT,
                parameter_name TEXT,
                confidence REAL,
                reasoning TEXT,
                created_at TEXT,
                FOREIGN KEY (dataset_tool_id) REFERENCES tools (tool_id),
                FOREIGN KEY (target_tool_id) REFERENCES tools (tool_id)
            )
        """)
        self.log("Created/verified dataset_tool_mapping table")

        self.conn.commit()

    def add_dataset_as_tool(self, dataset_key: str, dataset: Dict[str, Any]) -> str:
        """
        Add dataset as a standalone tool entry.
        Returns the tool_id.
        """
        # Generate tool_id
        access_method = dataset.get('access_method', 'unknown')
        if access_method == 'local_file':
            tool_id = f"biomate_dataset_{dataset_key}"
            category = 'Data Management'
        else:
            tool_id = f"biomate_datasource_{dataset_key}"
            category = 'Data Source'

        # Build description
        description_parts = [
            f"Dataset: {dataset['name']}",
            f"Format: {dataset.get('format', 'unknown')}",
            f"Category: {dataset.get('category', 'unknown')}",
            f"Access: {access_method}",
        ]

        if dataset.get('use_cases'):
            description_parts.append(f"Use cases: {', '.join(dataset.get('use_cases', [])[:5])}")

        if dataset.get('index_columns'):
            description_parts.append(f"Columns: {', '.join(dataset.get('index_columns', [])[:10])}")

        raw_text = "\n".join(description_parts)

        # Prepare dataset metadata as JSON
        metadata = {
            'dataset_key': dataset_key,
            'format': dataset.get('format'),
            'category': dataset.get('category'),
            'use_cases': dataset.get('use_cases', []),
            'index_columns': dataset.get('index_columns', []),
            'source': dataset.get('source'),
            'access_method': access_method,
            'compatible_tools_count': len(dataset.get('compatible_tools', []))
        }

        # Insert or update
        try:
            self.cursor.execute("""
                INSERT INTO tools (
                    tool_id, name, version, repo_owner, repo_name, category,
                    rawText, htmlContent, url,
                    is_dataset, dataset_metadata, data_version, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(tool_id) DO UPDATE SET
                    updated_at = ?,
                    data_version = ?,
                    dataset_metadata = ?
            """, (
                tool_id,
                dataset['name'],
                '1.0.0',
                'biomate',
                'biomate_datasets',
                category,
                raw_text,
                '',
                dataset.get('source', ''),
                1,  # is_dataset
                json.dumps(metadata),
                UPDATE_VERSION,
                UPDATE_TIMESTAMP,
                UPDATE_TIMESTAMP,
                # For ON CONFLICT UPDATE
                UPDATE_TIMESTAMP,
                UPDATE_VERSION,
                json.dumps(metadata)
            ))

            return tool_id

        except Exception as e:
            self.log(f"Error adding dataset {dataset_key}: {e}", "ERROR")
            raise

    def add_dataset_tool_mappings(self, dataset_tool_id: str, dataset: Dict[str, Any]):
        """Add mappings for dataset used as parameter in other tools"""
        compatible_tools = dataset.get('compatible_tools', [])

        if not compatible_tools:
            return

        for tool in compatible_tools:
            try:
                self.cursor.execute("""
                    INSERT INTO dataset_tool_mapping (
                        dataset_tool_id, target_tool_id, parameter_name,
                        confidence, reasoning, created_at
                    ) VALUES (?, ?, ?, ?, ?, ?)
                """, (
                    dataset_tool_id,
                    tool['tool_id'],
                    tool.get('parameter_name'),
                    tool.get('confidence', 0.0),
                    tool.get('reasoning', ''),
                    UPDATE_TIMESTAMP
                ))
            except Exception as e:
                self.log(f"Warning: Failed to add mapping {dataset_tool_id} -> {tool['tool_id']}: {e}", "WARNING")

    def update_fts_index(self):
        """Update full-text search index with new dataset entries"""
        self.log("Updating FTS index...")

        # Clear and rebuild FTS index for biomate entries
        self.cursor.execute("DELETE FROM tools_fts WHERE tool_id IN (SELECT tool_id FROM tools WHERE repo_owner = 'biomate')")

        # Insert all biomate tools into FTS
        self.cursor.execute("""
            INSERT INTO tools_fts (tool_id, name, description, category, parameters, help_text)
            SELECT
                tool_id,
                name,
                name || ' ' || category,
                category,
                COALESCE(dataset_metadata, ''),
                rawText
            FROM tools
            WHERE repo_owner = 'biomate'
        """)

        self.log(f"Updated FTS index with {self.cursor.rowcount} entries")
        self.conn.commit()

    def log_update_summary(self, stats: Dict[str, int]):
        """Log the update summary to update_log table"""
        self.cursor.execute("""
            INSERT INTO update_log (
                timestamp, update_version, update_type, description,
                items_added, items_updated, items_deleted, status, details
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            UPDATE_TIMESTAMP,
            UPDATE_VERSION,
            'dataset_integration',
            'Added datasets as tools with version tracking and parameter mappings',
            stats['added'],
            stats['updated'],
            stats['deleted'],
            'success',
            json.dumps(self.changes)
        ))
        self.conn.commit()

    def close(self):
        """Close database connection"""
        self.conn.close()


def main():
    print("="*80)
    print("DATASET TOOL INDEX INTEGRATION")
    print("="*80)
    print(f"Update Version: {UPDATE_VERSION}")
    print(f"Timestamp: {UPDATE_TIMESTAMP}")
    print("="*80)

    # Load reference data
    print("\n1. Loading reference data...")
    with open(REFERENCE_DATA_JSON, 'r') as f:
        reference_data = json.load(f)

    datasets = reference_data['datasets']
    print(f"   Loaded {len(datasets)} datasets")

    # Initialize updater
    updater = ToolIndexUpdater(GALAXY_TOOLS_DB)

    # Enhance schema
    print("\n2. Enhancing database schema...")
    updater.enhance_schema()

    # Process datasets
    print("\n3. Adding datasets to tool index...")
    stats = {
        'added': 0,
        'updated': 0,
        'deleted': 0,
        'mappings': 0
    }

    for dataset_key, dataset in datasets.items():
        try:
            # Add as standalone tool
            tool_id = updater.add_dataset_as_tool(dataset_key, dataset)
            stats['added'] += 1

            # Add parameter mappings
            compatible_count = len(dataset.get('compatible_tools', []))
            if compatible_count > 0:
                updater.add_dataset_tool_mappings(tool_id, dataset)
                stats['mappings'] += compatible_count

            updater.log(f"✓ Added {dataset['name']} with {compatible_count} tool mappings")

        except Exception as e:
            updater.log(f"✗ Failed to process {dataset_key}: {e}", "ERROR")
            continue

    updater.conn.commit()

    # Update FTS index
    print("\n4. Updating full-text search index...")
    updater.update_fts_index()

    # Generate summary
    print("\n" + "="*80)
    print("UPDATE SUMMARY")
    print("="*80)

    # Query statistics
    updater.cursor.execute("SELECT COUNT(*) FROM tools WHERE is_dataset = 1")
    total_datasets = updater.cursor.fetchone()[0]

    updater.cursor.execute("SELECT COUNT(*) FROM dataset_tool_mapping")
    total_mappings = updater.cursor.fetchone()[0]

    updater.cursor.execute("SELECT category, COUNT(*) FROM tools WHERE is_dataset = 1 GROUP BY category")
    category_counts = updater.cursor.fetchall()

    print(f"\nDatasets added to index: {total_datasets}")
    print(f"Dataset-tool mappings created: {total_mappings}")
    print("\nBreakdown by category:")
    for category, count in category_counts:
        print(f"  - {category}: {count}")

    print(f"\nVersion: {UPDATE_VERSION}")
    print(f"Timestamp: {UPDATE_TIMESTAMP}")
    print(f"Log file: {updater.log_file}")

    # Log update summary
    updater.log_update_summary(stats)

    # Verify search functionality
    print("\n" + "="*80)
    print("VERIFICATION: Testing search functionality")
    print("="*80)

    test_queries = ['BindingDB', 'proteomics', 'drug discovery']
    for query in test_queries:
        updater.cursor.execute("""
            SELECT name, category, is_dataset
            FROM tools
            WHERE tool_id IN (
                SELECT tool_id FROM tools_fts WHERE tools_fts MATCH ?
            )
            LIMIT 3
        """, (query,))
        results = updater.cursor.fetchall()
        print(f"\nQuery '{query}': {len(results)} results")
        for name, category, is_dataset in results:
            ds_marker = "📊" if is_dataset else "🔧"
            print(f"  {ds_marker} {name} ({category})")

    updater.close()

    print("\n" + "="*80)
    print("✅ Dataset integration completed successfully!")
    print("="*80)


if __name__ == '__main__':
    main()
