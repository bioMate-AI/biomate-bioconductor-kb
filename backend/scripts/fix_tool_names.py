#!/usr/bin/env python3
"""
Fix invalid tool names in the tool index.

This script:
1. Identifies tools with "Repository Actions\n" prefix
2. Identifies tools with empty or invalid names
3. Extracts proper tool names from tool_id or rawText
4. Updates the tools table with corrected names
5. Updates FTS index with corrected names
"""
import json
import sqlite3
import os
import re
from datetime import datetime
from typing import Dict, Any, List, Optional
from pathlib import Path

# Configuration
GALAXY_TOOLS_DB = "/Users/jingqiwang/biomate/backend/galaxy_ai_tools.db"
LOG_DIR = "/Users/jingqiwang/biomate/backend/logs"
os.makedirs(LOG_DIR, exist_ok=True)

# Timestamp for this update
UPDATE_TIMESTAMP = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
UPDATE_VERSION = datetime.now().strftime("%Y%m%d_%H%M%S")


class ToolNameFixer:
    """Fixes invalid tool names in the database"""

    def __init__(self, db_path: str):
        self.db_path = db_path
        self.conn = sqlite3.connect(db_path)
        self.cursor = self.conn.cursor()
        self.log_file = os.path.join(LOG_DIR, f"tool_name_fixes_{UPDATE_VERSION}.log")
        self.changes = []
        self.stats = {
            'repository_actions_fixed': 0,
            'empty_names_fixed': 0,
            'failed': 0
        }

    def log(self, message: str, level: str = "INFO"):
        """Log message to both console and file"""
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        log_entry = f"[{timestamp}] [{level}] {message}"
        print(log_entry)
        with open(self.log_file, 'a') as f:
            f.write(log_entry + "\n")
        self.changes.append(log_entry)

    def extract_tool_name_from_text(self, text: str) -> Optional[str]:
        """Extract tool name from rawText or htmlContent"""
        if not text:
            return None

        # Try to find "Tool: <name>" pattern
        match = re.search(r'Tool:\s*(.+?)(?:\n|$)', text, re.IGNORECASE)
        if match:
            name = match.group(1).strip()
            if name and name != 'unknown':
                return name

        # Try to find lines that might be tool names (capitalized, short)
        lines = text.split('\n')
        for line in lines[:10]:  # Check first 10 lines
            line = line.strip()
            if line and len(line) < 100 and not line.startswith(('http', 'Repository:', 'Version:', 'Category:')):
                # Skip common prefixes
                if not any(line.startswith(prefix) for prefix in ['Tool:', 'Owner:', 'Format:']):
                    return line

        return None

    def extract_tool_name_from_tool_id(self, tool_id: str, repo_owner: str, repo_name: str) -> Optional[str]:
        """Extract tool name from tool_id by removing repo_owner and repo_name"""
        if not tool_id:
            return None

        # Tool ID format: owner_repo_toolname_version
        # Remove owner and repo prefix
        parts = tool_id.split('_')

        # Try to find where the tool name starts
        # Skip the owner part
        start_idx = 0
        if repo_owner:
            owner_parts = repo_owner.replace('-', '_').split('_')
            # Check if tool_id starts with owner parts
            for i, part in enumerate(parts):
                if i < len(owner_parts) and part.lower() == owner_parts[i].lower():
                    start_idx = i + 1
                else:
                    break

        # Skip the repo part
        if repo_name and start_idx < len(parts):
            repo_parts = repo_name.replace('-', '_').split('_')
            for i, part in enumerate(parts[start_idx:]):
                if i < len(repo_parts) and part.lower() == repo_parts[i].lower():
                    start_idx += 1
                else:
                    break

        # What's left should be tool name + version
        if start_idx < len(parts):
            remaining = parts[start_idx:]
            # Remove version (usually at the end, contains numbers)
            if len(remaining) > 1:
                # Check if last part looks like a version
                last = remaining[-1]
                if re.match(r'^[\d.+]+', last):
                    remaining = remaining[:-1]

            # Join and clean up
            tool_name = '_'.join(remaining)
            # Convert underscores to spaces for readability
            tool_name = tool_name.replace('_', ' ').strip()
            if tool_name:
                return tool_name

        return None

    def normalize_tool_name(self, name: str) -> str:
        """Normalize tool name by removing common prefixes and cleaning up"""
        if not name:
            return ""

        # Remove "Repository Actions\n" prefix
        if '\n' in name:
            parts = name.split('\n')
            # Filter out "Repository Actions" and error messages
            valid_parts = []
            for part in parts:
                part = part.strip()
                if part and part != "Repository Actions" and not part.startswith('/srv/'):
                    valid_parts.append(part)

            if valid_parts:
                name = valid_parts[0]  # Take first valid part
            else:
                return ""

        # Clean up the name
        name = name.strip()

        # Remove common error prefixes
        if name.startswith('/srv/'):
            return ""

        return name

    def fix_repository_actions_names(self):
        """Fix tools with 'Repository Actions' in their names"""
        self.log("Fixing tools with 'Repository Actions' prefix...")

        self.cursor.execute("""
            SELECT tool_id, name, repo_owner, repo_name, rawText, htmlContent
            FROM tools
            WHERE name LIKE '%Repository Actions%'
        """)

        tools_to_fix = self.cursor.fetchall()
        self.log(f"Found {len(tools_to_fix)} tools with 'Repository Actions'")

        for tool_id, old_name, repo_owner, repo_name, raw_text, html_content in tools_to_fix:
            # Try normalization first
            new_name = self.normalize_tool_name(old_name)

            # If still empty, try extracting from other sources
            if not new_name:
                # Try extracting from tool_id
                new_name = self.extract_tool_name_from_tool_id(tool_id, repo_owner, repo_name)

            if not new_name:
                # Try extracting from rawText
                new_name = self.extract_tool_name_from_text(raw_text)

            if not new_name:
                # Try extracting from htmlContent
                new_name = self.extract_tool_name_from_text(html_content)

            if not new_name:
                # Last resort: use repo_name
                if repo_name:
                    new_name = repo_name.replace('_', ' ').replace('-', ' ').title()

            # Update if we found a valid name
            if new_name and new_name != old_name:
                try:
                    self.cursor.execute("""
                        UPDATE tools
                        SET name = ?, updated_at = ?
                        WHERE tool_id = ?
                    """, (new_name, UPDATE_TIMESTAMP, tool_id))
                    self.stats['repository_actions_fixed'] += 1

                    if self.stats['repository_actions_fixed'] % 100 == 0:
                        self.log(f"Fixed {self.stats['repository_actions_fixed']} tools so far...")
                except Exception as e:
                    self.log(f"Error fixing {tool_id}: {e}", "ERROR")
                    self.stats['failed'] += 1
            else:
                self.log(f"Could not find valid name for {tool_id}", "WARNING")
                self.stats['failed'] += 1

    def fix_empty_names(self):
        """Fix tools with empty names"""
        self.log("Fixing tools with empty names...")

        self.cursor.execute("""
            SELECT tool_id, name, repo_owner, repo_name, rawText, htmlContent
            FROM tools
            WHERE length(trim(COALESCE(name, ''))) = 0
        """)

        tools_to_fix = self.cursor.fetchall()
        self.log(f"Found {len(tools_to_fix)} tools with empty names")

        for tool_id, old_name, repo_owner, repo_name, raw_text, html_content in tools_to_fix:
            new_name = None

            # Try extracting from tool_id
            new_name = self.extract_tool_name_from_tool_id(tool_id, repo_owner, repo_name)

            if not new_name:
                # Try extracting from rawText
                new_name = self.extract_tool_name_from_text(raw_text)

            if not new_name:
                # Try extracting from htmlContent
                new_name = self.extract_tool_name_from_text(html_content)

            if not new_name:
                # Last resort: use repo_name
                if repo_name:
                    new_name = repo_name.replace('_', ' ').replace('-', ' ').title()

            if not new_name:
                # Use tool_id as fallback
                new_name = tool_id.split('_')[-2] if '_' in tool_id else tool_id
                new_name = new_name.replace('_', ' ').title()

            # Update
            if new_name:
                try:
                    self.cursor.execute("""
                        UPDATE tools
                        SET name = ?, updated_at = ?
                        WHERE tool_id = ?
                    """, (new_name, UPDATE_TIMESTAMP, tool_id))
                    self.stats['empty_names_fixed'] += 1
                except Exception as e:
                    self.log(f"Error fixing {tool_id}: {e}", "ERROR")
                    self.stats['failed'] += 1

    def update_fts_index(self):
        """Rebuild FTS index with corrected names"""
        self.log("Rebuilding FTS index...")

        # Clear FTS index
        self.cursor.execute("DELETE FROM tools_fts")

        # Rebuild from tools table
        self.cursor.execute("""
            INSERT INTO tools_fts (tool_id, name, description, category, parameters, help_text)
            SELECT
                tool_id,
                name,
                name || ' ' || COALESCE(category, ''),
                COALESCE(category, ''),
                COALESCE(dataset_metadata, ''),
                COALESCE(rawText, '')
            FROM tools
            WHERE name IS NOT NULL AND length(trim(name)) > 0
        """)

        self.log(f"Rebuilt FTS index with {self.cursor.rowcount} entries")

    def log_update_summary(self):
        """Log the update summary to update_log table"""
        self.cursor.execute("""
            INSERT INTO update_log (
                timestamp, update_version, update_type, description,
                items_added, items_updated, items_deleted, status, details
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            UPDATE_TIMESTAMP,
            UPDATE_VERSION,
            'tool_name_fixes',
            'Fixed invalid tool names (Repository Actions prefix and empty names)',
            0,  # No new items
            self.stats['repository_actions_fixed'] + self.stats['empty_names_fixed'],
            0,  # No deletions
            'success' if self.stats['failed'] == 0 else 'partial',
            json.dumps(self.stats)
        ))
        self.conn.commit()

    def close(self):
        """Close database connection"""
        self.conn.close()


def main():
    print("="*80)
    print("TOOL NAME FIXES")
    print("="*80)
    print(f"Update Version: {UPDATE_VERSION}")
    print(f"Timestamp: {UPDATE_TIMESTAMP}")
    print("="*80)

    # Initialize fixer
    fixer = ToolNameFixer(GALAXY_TOOLS_DB)

    # Fix repository actions names
    print("\n1. Fixing 'Repository Actions' prefix...")
    fixer.fix_repository_actions_names()
    fixer.conn.commit()

    # Fix empty names
    print("\n2. Fixing empty names...")
    fixer.fix_empty_names()
    fixer.conn.commit()

    # Update FTS index
    print("\n3. Rebuilding FTS index...")
    fixer.update_fts_index()
    fixer.conn.commit()

    # Generate summary
    print("\n" + "="*80)
    print("FIX SUMMARY")
    print("="*80)
    print(f"Repository Actions fixed: {fixer.stats['repository_actions_fixed']}")
    print(f"Empty names fixed: {fixer.stats['empty_names_fixed']}")
    print(f"Failed: {fixer.stats['failed']}")
    print(f"\nLog file: {fixer.log_file}")

    # Log update summary
    fixer.log_update_summary()

    # Verify
    print("\n" + "="*80)
    print("VERIFICATION")
    print("="*80)

    fixer.cursor.execute("SELECT COUNT(*) FROM tools WHERE name LIKE '%Repository Actions%'")
    remaining_repo_actions = fixer.cursor.fetchone()[0]
    print(f"Tools with 'Repository Actions': {remaining_repo_actions}")

    fixer.cursor.execute("SELECT COUNT(*) FROM tools WHERE length(trim(COALESCE(name, ''))) = 0")
    remaining_empty = fixer.cursor.fetchone()[0]
    print(f"Tools with empty names: {remaining_empty}")

    fixer.close()

    print("\n" + "="*80)
    print("✅ Tool name fixes completed!")
    print("="*80)


if __name__ == '__main__':
    main()
