#!/usr/bin/env python3
"""
Cleanup Dummy Parameters - Remove placeholder/dummy parameters from auto-discovered tools

Identifies and removes dummy parameters that block quality validation:
- Generic names: help, version, output, input, m
- Placeholder names: all underscores, single letters
- Auto-discovered markers: source="auto_discovered" with generic help text

Usage:
    # Preview changes (dry run)
    python cleanup_dummy_parameters.py --dry-run

    # Apply cleanup to database
    python cleanup_dummy_parameters.py --apply

    # Clean specific tool
    python cleanup_dummy_parameters.py --tool-id auto_dash --apply
"""

import argparse
import json
import logging
import re
import sqlite3
from pathlib import Path
from typing import Dict, List, Tuple

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)


class DummyParameterCleaner:
    """Remove dummy/placeholder parameters from auto-discovered tools."""

    # Patterns that indicate dummy parameters
    DUMMY_NAME_PATTERNS = [
        r'^help$',           # Generic help
        r'^version$',        # Generic version
        r'^output$',         # Generic output
        r'^input$',          # Generic input
        r'^m$',              # Single letter
        r'^_+$',             # All underscores
        r'^[a-z]$',          # Single lowercase letter
    ]

    # Help text patterns that indicate placeholder
    DUMMY_HELP_PATTERNS = [
        r'^Parameter for',   # Generic placeholder help
        r'requires the following packages',  # Not a real parameter
    ]

    def __init__(self, db_path: Path):
        self.db_path = db_path
        self.conn = None

    def connect(self):
        """Connect to database."""
        self.conn = sqlite3.connect(self.db_path)
        self.conn.row_factory = sqlite3.Row

    def close(self):
        """Close database connection."""
        if self.conn:
            self.conn.close()

    def is_dummy_parameter(self, param: Dict) -> bool:
        """Check if parameter is a dummy/placeholder."""
        name = param.get('name', '').lower()
        help_text = param.get('help', '')
        source = param.get('source', '')

        # Check name patterns
        for pattern in self.DUMMY_NAME_PATTERNS:
            if re.match(pattern, name, re.IGNORECASE):
                return True

        # Check help text patterns
        for pattern in self.DUMMY_HELP_PATTERNS:
            if re.search(pattern, help_text, re.IGNORECASE):
                return True

        # Auto-discovered with generic help is likely dummy
        if source == 'auto_discovered':
            if help_text.startswith('Parameter for'):
                return True

        return False

    def clean_parameters(self, parameters: List[Dict]) -> Tuple[List[Dict], List[Dict]]:
        """
        Remove dummy parameters from list.

        Returns:
            Tuple of (cleaned_params, removed_params)
        """
        cleaned = []
        removed = []

        for param in parameters:
            if self.is_dummy_parameter(param):
                removed.append(param)
            else:
                cleaned.append(param)

        return cleaned, removed

    def get_auto_discovered_tools(self) -> List[Dict]:
        """Get all auto-discovered tools."""
        cursor = self.conn.cursor()
        cursor.execute("""
            SELECT tool_id, name, parameters
            FROM tools
            WHERE tool_id LIKE 'auto_%'
        """)

        tools = []
        for row in cursor.fetchall():
            tool = dict(row)
            try:
                tool['parameters'] = json.loads(tool['parameters']) if tool['parameters'] else []
            except json.JSONDecodeError:
                tool['parameters'] = []
            tools.append(tool)

        return tools

    def get_tool(self, tool_id: str) -> Dict:
        """Get single tool by ID."""
        cursor = self.conn.cursor()
        cursor.execute("""
            SELECT tool_id, name, parameters
            FROM tools
            WHERE tool_id = ?
        """, (tool_id,))

        row = cursor.fetchone()
        if not row:
            return None

        tool = dict(row)
        try:
            tool['parameters'] = json.loads(tool['parameters']) if tool['parameters'] else []
        except json.JSONDecodeError:
            tool['parameters'] = []

        return tool

    def update_parameters(self, tool_id: str, parameters: List[Dict]):
        """Update tool parameters in database."""
        cursor = self.conn.cursor()
        cursor.execute("""
            UPDATE tools
            SET parameters = ?
            WHERE tool_id = ?
        """, (json.dumps(parameters), tool_id))
        self.conn.commit()

    def cleanup_tool(self, tool: Dict, apply: bool = False) -> Dict:
        """
        Clean up dummy parameters for a single tool.

        Returns:
            Dict with cleanup results
        """
        tool_id = tool['tool_id']
        original_params = tool['parameters']

        cleaned_params, removed_params = self.clean_parameters(original_params)

        result = {
            'tool_id': tool_id,
            'name': tool['name'],
            'original_count': len(original_params),
            'cleaned_count': len(cleaned_params),
            'removed_count': len(removed_params),
            'removed_params': [p.get('name', 'unknown') for p in removed_params],
            'applied': False
        }

        if removed_params and apply:
            self.update_parameters(tool_id, cleaned_params)
            result['applied'] = True

        return result

    def cleanup_all(self, apply: bool = False) -> List[Dict]:
        """
        Clean up all auto-discovered tools.

        Returns:
            List of cleanup results
        """
        tools = self.get_auto_discovered_tools()
        results = []

        for tool in tools:
            result = self.cleanup_tool(tool, apply)
            results.append(result)

        return results


def main():
    parser = argparse.ArgumentParser(
        description='Clean up dummy parameters from auto-discovered tools'
    )
    parser.add_argument(
        '--db-path',
        type=Path,
        default=Path('/home/yzhang/biomate/backend/database/galaxy_ai_tools.db'),
        help='Path to database'
    )
    parser.add_argument(
        '--tool-id',
        type=str,
        help='Clean specific tool by ID'
    )
    parser.add_argument(
        '--apply',
        action='store_true',
        help='Apply changes to database (default is dry run)'
    )
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Preview changes without applying'
    )

    args = parser.parse_args()

    # Default to dry run if neither specified
    apply = args.apply and not args.dry_run

    cleaner = DummyParameterCleaner(args.db_path)
    cleaner.connect()

    try:
        if args.tool_id:
            # Clean single tool
            tool = cleaner.get_tool(args.tool_id)
            if not tool:
                logger.error(f"Tool not found: {args.tool_id}")
                return 1

            results = [cleaner.cleanup_tool(tool, apply)]
        else:
            # Clean all auto-discovered tools
            results = cleaner.cleanup_all(apply)

        # Print results
        print("=" * 80)
        print("DUMMY PARAMETER CLEANUP REPORT")
        print("=" * 80)
        print()

        total_removed = 0
        tools_affected = 0

        for result in results:
            if result['removed_count'] > 0:
                tools_affected += 1
                total_removed += result['removed_count']

                status = "✅ Applied" if result['applied'] else "⚠️  Preview"
                print(f"{status} {result['tool_id']}")
                print(f"   Original: {result['original_count']} → Cleaned: {result['cleaned_count']}")
                print(f"   Removed: {result['removed_params']}")
                print()

        print("=" * 80)
        print("SUMMARY")
        print("=" * 80)
        print(f"Total tools scanned: {len(results)}")
        print(f"Tools with dummy params: {tools_affected}")
        print(f"Total params removed: {total_removed}")

        if apply:
            print(f"\n✅ Changes applied to database")
        else:
            print(f"\n⚠️  Dry run - no changes made. Use --apply to update database")

    finally:
        cleaner.close()

    return 0


if __name__ == '__main__':
    exit(main())
