#!/usr/bin/env python3
"""
Add v3 crawled tools from lcms-platform to the tool index.

This script:
1. Loads the v3 parallel_crawler_merged.json (3,312 new tools)
2. Deduplicates against existing tool index
3. Adds new tools to galaxy_ai_tools.db
4. Updates FTS index
5. Logs all changes with version tracking
"""
import json
import sqlite3
import os
from datetime import datetime
from typing import Dict, Any, List
from pathlib import Path

# Configuration
GALAXY_TOOLS_DB = "/Users/jingqiwang/biomate/backend/galaxy_ai_tools.db"
V3_CRAWL_DATA = "/Users/jingqiwang/lcms-platform/galaxy_tools/latest_tools_complete/parallel_crawler_merged.json"
LOG_DIR = "/Users/jingqiwang/biomate/backend/logs"
os.makedirs(LOG_DIR, exist_ok=True)

# Timestamp for this update
UPDATE_TIMESTAMP = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
UPDATE_VERSION = datetime.now().strftime("%Y%m%d_%H%M%S")


class V3ToolIndexUpdater:
    """Manages v3 tool integration into tool index"""

    def __init__(self, db_path: str):
        self.db_path = db_path
        self.conn = sqlite3.connect(db_path)
        self.cursor = self.conn.cursor()
        self.log_file = os.path.join(LOG_DIR, f"v3_tool_index_update_{UPDATE_VERSION}.log")
        self.changes = []
        self.existing_tool_ids = set()

    def log(self, message: str, level: str = "INFO"):
        """Log message to both console and file"""
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        log_entry = f"[{timestamp}] [{level}] {message}"
        print(log_entry)
        with open(self.log_file, 'a') as f:
            f.write(log_entry + "\n")
        self.changes.append(log_entry)

    def load_existing_tool_ids(self):
        """Load all existing tool_ids from database for deduplication"""
        self.log("Loading existing tool IDs from database...")
        self.cursor.execute("SELECT tool_id FROM tools WHERE is_dataset IS NULL OR is_dataset = 0")
        self.existing_tool_ids = {row[0] for row in self.cursor.fetchall()}
        self.log(f"Loaded {len(self.existing_tool_ids)} existing tool IDs")

    def generate_tool_id(self, repo_owner: str, repo_name: str, tool_name: str, version: str) -> str:
        """Generate a unique tool_id"""
        # Format: owner/repo/toolname/version (sanitized)
        safe_owner = repo_owner.replace('/', '_').replace(' ', '_')
        safe_repo = repo_name.replace('/', '_').replace(' ', '_')
        safe_name = tool_name.replace('/', '_').replace(' ', '_').replace('\n', '_')
        safe_version = version.replace('/', '_').replace(' ', '_')

        # Create base tool_id
        base_id = f"{safe_owner}_{safe_repo}_{safe_name}"

        # If version exists, append it
        if safe_version:
            return f"{base_id}_{safe_version}"

        return base_id

    def normalize_tool_name(self, name: str) -> str:
        """Normalize tool name for consistency"""
        # Remove "Repository Actions\n" prefix if present
        if '\n' in name:
            name = name.split('\n')[-1].strip()
        return name.strip()

    def add_tool(self, tool: Dict[str, Any], repo: Dict[str, Any], category: str) -> bool:
        """Add a single tool to the index. Returns True if added, False if skipped."""
        repo_owner = repo.get('repoOwner', 'unknown')
        repo_name = repo.get('repoName', 'unknown')
        tool_name = self.normalize_tool_name(tool.get('name', 'unknown'))
        version = tool.get('version', '1.0.0')

        # Generate tool_id
        tool_id = self.generate_tool_id(repo_owner, repo_name, tool_name, version)

        # Skip if already exists
        if tool_id in self.existing_tool_ids:
            return False

        # Build rawText
        raw_text_parts = [
            f"Tool: {tool_name}",
            f"Version: {version}",
            f"Repository: {repo_name}",
            f"Owner: {repo_owner}",
            f"Category: {category}",
        ]

        if tool.get('rawText'):
            raw_text_parts.append(tool['rawText'][:5000])  # Limit size

        raw_text = "\n".join(raw_text_parts)

        # Determine URL
        url = tool.get('url', repo.get('url', ''))

        # Insert into database
        try:
            self.cursor.execute("""
                INSERT INTO tools (
                    tool_id, name, version, repo_owner, repo_name, category,
                    rawText, htmlContent, url,
                    created_at, updated_at, data_version, is_dataset
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                tool_id,
                tool_name,
                version,
                repo_owner,
                repo_name,
                category,
                raw_text,
                tool.get('htmlContent', '')[:10000] if tool.get('htmlContent') else '',
                url,
                UPDATE_TIMESTAMP,
                UPDATE_TIMESTAMP,
                UPDATE_VERSION,
                0  # is_dataset = 0 (regular tool)
            ))

            # Add to existing set
            self.existing_tool_ids.add(tool_id)
            return True

        except Exception as e:
            self.log(f"Error adding tool {tool_id}: {e}", "ERROR")
            return False

    def update_fts_index(self, new_tool_count: int):
        """Update full-text search index with new tools"""
        self.log("Updating FTS index...")

        # Get all tools added in this version
        self.cursor.execute("""
            SELECT tool_id, name, rawText, category
            FROM tools
            WHERE data_version = ?
        """, (UPDATE_VERSION,))

        tools_to_index = self.cursor.fetchall()

        for tool_id, name, raw_text, category in tools_to_index:
            try:
                self.cursor.execute("""
                    INSERT INTO tools_fts (tool_id, name, description, category, parameters, help_text)
                    VALUES (?, ?, ?, ?, ?, ?)
                """, (
                    tool_id,
                    name,
                    f"{name} {category}",
                    category,
                    '',
                    raw_text[:5000] if raw_text else ''
                ))
            except Exception as e:
                # Tool might already be in FTS index
                pass

        self.log(f"Updated FTS index with {len(tools_to_index)} entries")
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
            'v3_tool_integration',
            'Added v3 crawled tools from lcms-platform parallel crawler',
            stats['added'],
            0,  # No updates
            0,  # No deletions
            'success',
            json.dumps(self.changes[-50:])  # Last 50 log entries
        ))
        self.conn.commit()

    def close(self):
        """Close database connection"""
        self.conn.close()


def main():
    print("="*80)
    print("V3 TOOL INDEX INTEGRATION")
    print("="*80)
    print(f"Update Version: {UPDATE_VERSION}")
    print(f"Timestamp: {UPDATE_TIMESTAMP}")
    print("="*80)

    # Load v3 crawl data
    print("\n1. Loading v3 crawl data...")
    with open(V3_CRAWL_DATA, 'r') as f:
        v3_data = json.load(f)

    print(f"   Loaded v3 data:")
    print(f"   - Categories: {v3_data['statistics']['totalCategories']}")
    print(f"   - Repositories: {v3_data['statistics']['totalRepositories']}")
    print(f"   - Tools: {v3_data['statistics']['totalTools']}")

    # Initialize updater
    updater = V3ToolIndexUpdater(GALAXY_TOOLS_DB)
    updater.load_existing_tool_ids()

    # Process tools
    print("\n2. Processing v3 tools...")
    stats = {
        'added': 0,
        'skipped': 0,
        'by_category': {}
    }

    crawled_data = v3_data['crawledData']

    for cat_id, category_data in crawled_data.items():
        category_name = category_data['category']
        repositories = category_data.get('repositories', [])

        print(f"\n   Category: {category_name} ({len(repositories)} repos)")

        category_added = 0
        for repo in repositories:
            tools = repo.get('tools', [])
            for tool in tools:
                if updater.add_tool(tool, repo, category_name):
                    stats['added'] += 1
                    category_added += 1
                else:
                    stats['skipped'] += 1

        stats['by_category'][category_name] = category_added
        print(f"     Added {category_added} tools")

    updater.conn.commit()

    # Update FTS index
    print("\n3. Updating full-text search index...")
    updater.update_fts_index(stats['added'])

    # Generate summary
    print("\n" + "="*80)
    print("UPDATE SUMMARY")
    print("="*80)

    # Query final statistics
    updater.cursor.execute("SELECT COUNT(*) FROM tools WHERE is_dataset IS NULL OR is_dataset = 0")
    total_galaxy_tools = updater.cursor.fetchone()[0]

    updater.cursor.execute("SELECT COUNT(*) FROM tools WHERE data_version = ?", (UPDATE_VERSION,))
    tools_added_this_version = updater.cursor.fetchone()[0]

    print(f"\nV3 Tools processed: {v3_data['statistics']['totalTools']}")
    print(f"New tools added: {stats['added']}")
    print(f"Duplicates skipped: {stats['skipped']}")
    print(f"Total Galaxy tools in index: {total_galaxy_tools}")

    print("\nBreakdown by category:")
    for category, count in sorted(stats['by_category'].items(), key=lambda x: -x[1]):
        if count > 0:
            print(f"  - {category}: {count}")

    print(f"\nVersion: {UPDATE_VERSION}")
    print(f"Timestamp: {UPDATE_TIMESTAMP}")
    print(f"Log file: {updater.log_file}")

    # Log update summary
    updater.log_update_summary(stats)

    # Close
    updater.close()

    print("\n" + "="*80)
    print("✅ V3 tool integration completed successfully!")
    print("="*80)


if __name__ == '__main__':
    main()
