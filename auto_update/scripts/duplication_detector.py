#!/usr/bin/env python3
"""
Duplication Detector - Detect duplicate tools before insertion into database

Checks for duplicates by:
1. Repository owner/name (same GitHub repo)
2. Tool name (similar names, case-insensitive)
3. Tool description similarity (fuzzy matching)

Prevents database bloat and maintains data quality.

Usage:
    from duplication_detector import DuplicationDetector
    detector = DuplicationDetector(db_path)
    is_duplicate, existing_tools = detector.check_duplicate(metadata)
"""

import sqlite3
from pathlib import Path
from typing import Dict, List, Tuple, Optional
from difflib import SequenceMatcher

class DuplicationDetector:
    """
    Detects duplicate tools in the database before insertion.
    """

    def __init__(self, db_path: Path):
        """
        Initialize duplication detector.

        Args:
            db_path: Path to galaxy_ai_tools.db
        """
        self.db_path = Path(db_path)

    def check_duplicate(
        self,
        metadata: Dict,
        similarity_threshold: float = 0.85
    ) -> Tuple[bool, List[Dict]]:
        """
        Check if tool is a duplicate of existing tools.

        Args:
            metadata: Tool metadata dictionary containing:
                - full_name (owner/repo)
                - name (tool name)
                - description
                - url (GitHub URL)
            similarity_threshold: Name similarity threshold (0.0-1.0)

        Returns:
            Tuple of (is_duplicate, existing_tools)
            - is_duplicate: Boolean indicating if duplicate found
            - existing_tools: List of similar existing tools with scores
        """
        # Extract key identifiers
        full_name = metadata.get('full_name', '')
        name = metadata.get('name', '')
        description = metadata.get('description', '')
        url = metadata.get('url', '')

        # Parse repo owner/name
        parts = full_name.split('/') if full_name else ['', '']
        repo_owner = parts[0] if len(parts) > 0 else ''
        repo_name = parts[1] if len(parts) > 1 else ''

        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()

        # Check 1: Exact match by repository (owner/name)
        if repo_owner and repo_name:
            cursor.execute("""
                SELECT tool_id, name, repo_owner, repo_name, url, description, version
                FROM tools
                WHERE repo_owner = ? AND repo_name = ?
            """, (repo_owner, repo_name))

            exact_matches = [dict(row) for row in cursor.fetchall()]
            if exact_matches:
                conn.close()
                for match in exact_matches:
                    match['match_type'] = 'exact_repo'
                    match['similarity'] = 1.0
                return True, exact_matches

        # Check 2: Exact match by GitHub URL
        if url:
            cursor.execute("""
                SELECT tool_id, name, repo_owner, repo_name, url, description, version
                FROM tools
                WHERE url = ? OR github_url = ?
            """, (url, url))

            url_matches = [dict(row) for row in cursor.fetchall()]
            if url_matches:
                conn.close()
                for match in url_matches:
                    match['match_type'] = 'exact_url'
                    match['similarity'] = 1.0
                return True, url_matches

        # Check 3: Similar tool name (fuzzy matching)
        if name:
            similar_tools = self._find_similar_names(cursor, name, similarity_threshold)
            if similar_tools:
                conn.close()
                return True, similar_tools

        conn.close()
        return False, []

    def _find_similar_names(
        self,
        cursor,
        name: str,
        threshold: float
    ) -> List[Dict]:
        """Find tools with similar names."""
        # Get all tool names
        cursor.execute("""
            SELECT tool_id, name, repo_owner, repo_name, url, description, version
            FROM tools
        """)

        similar = []
        name_lower = name.lower()

        for row in cursor.fetchall():
            existing_name = row['name'] if row['name'] else ''
            existing_name_lower = existing_name.lower()

            # Calculate similarity
            similarity = self._calculate_similarity(name_lower, existing_name_lower)

            if similarity >= threshold:
                tool_dict = dict(row)
                tool_dict['match_type'] = 'similar_name'
                tool_dict['similarity'] = similarity
                similar.append(tool_dict)

        # Sort by similarity (highest first)
        similar.sort(key=lambda x: x['similarity'], reverse=True)

        return similar

    def _calculate_similarity(self, str1: str, str2: str) -> float:
        """Calculate similarity between two strings."""
        # Use SequenceMatcher for fuzzy string matching
        return SequenceMatcher(None, str1, str2).ratio()

    def get_duplicate_statistics(self) -> Dict:
        """
        Get statistics about duplicates in the database.

        Returns:
            Dictionary with duplicate statistics:
            - total_tools: Total number of tools
            - unique_names: Number of unique tool names
            - duplicate_names: Number of duplicate names
            - duplicate_name_groups: List of duplicate name groups
            - unique_repos: Number of unique repositories
            - duplicate_repos: Number of duplicate repositories
        """
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        # Total tools
        cursor.execute("SELECT COUNT(*) FROM tools")
        total_tools = cursor.fetchone()[0]

        # Unique names
        cursor.execute("SELECT COUNT(DISTINCT name) FROM tools")
        unique_names = cursor.fetchone()[0]

        # Duplicate names
        cursor.execute("""
            SELECT name, COUNT(*) as count
            FROM tools
            GROUP BY name
            HAVING count > 1
            ORDER BY count DESC
        """)
        duplicate_name_groups = [
            {'name': row[0], 'count': row[1]}
            for row in cursor.fetchall()
        ]

        # Unique repositories
        cursor.execute("""
            SELECT COUNT(DISTINCT repo_owner || '/' || repo_name)
            FROM tools
            WHERE repo_owner IS NOT NULL AND repo_name IS NOT NULL
        """)
        unique_repos = cursor.fetchone()[0]

        # Duplicate repositories
        cursor.execute("""
            SELECT repo_owner, repo_name, COUNT(*) as count
            FROM tools
            WHERE repo_owner IS NOT NULL AND repo_name IS NOT NULL
            GROUP BY repo_owner, repo_name
            HAVING count > 1
            ORDER BY count DESC
        """)
        duplicate_repo_groups = [
            {'repo': f"{row[0]}/{row[1]}", 'count': row[2]}
            for row in cursor.fetchall()
        ]

        conn.close()

        return {
            'total_tools': total_tools,
            'unique_names': unique_names,
            'duplicate_names': len(duplicate_name_groups),
            'duplicate_name_groups': duplicate_name_groups[:20],  # Top 20
            'unique_repos': unique_repos,
            'duplicate_repos': len(duplicate_repo_groups),
            'duplicate_repo_groups': duplicate_repo_groups[:20]  # Top 20
        }

    def suggest_action(self, existing_tools: List[Dict], new_metadata: Dict) -> str:
        """
        Suggest action to take when duplicate is found.

        Args:
            existing_tools: List of existing similar tools
            new_metadata: Metadata of new tool being added

        Returns:
            Suggested action: "skip", "update", or "add_as_new"
        """
        if not existing_tools:
            return "add_as_new"

        best_match = existing_tools[0]
        match_type = best_match.get('match_type', '')
        similarity = best_match.get('similarity', 0.0)

        # Exact repository match
        if match_type == 'exact_repo' or match_type == 'exact_url':
            # Same repo - check if version is newer
            existing_version = best_match.get('version', '0.0.0')
            new_version = new_metadata.get('version', '0.0.0')

            if self._is_version_newer(new_version, existing_version):
                return "update"
            else:
                return "skip"

        # High similarity name match
        if match_type == 'similar_name' and similarity >= 0.95:
            # Very similar name - likely duplicate
            return "skip"

        # Moderate similarity
        if similarity >= 0.85:
            # Could be related tool or variant
            return "skip"  # Conservative - don't add

        return "add_as_new"

    def _is_version_newer(self, new_version: str, existing_version: str) -> bool:
        """Check if new version is newer than existing version."""
        try:
            # Simple version comparison (works for semantic versioning)
            new_parts = [int(x) for x in new_version.split('.')]
            existing_parts = [int(x) for x in existing_version.split('.')]

            # Pad shorter version with zeros
            max_len = max(len(new_parts), len(existing_parts))
            new_parts += [0] * (max_len - len(new_parts))
            existing_parts += [0] * (max_len - len(existing_parts))

            return new_parts > existing_parts
        except:
            # If version parsing fails, consider it not newer
            return False


# For command-line testing and statistics
if __name__ == '__main__':
    import sys
    import json

    if len(sys.argv) < 2:
        print("Usage:")
        print("  python duplication_detector.py stats             - Show duplicate statistics")
        print("  python duplication_detector.py check <name>     - Check if tool name is duplicate")
        sys.exit(1)

    db_path = Path(__file__).parent.parent.parent / "backend" / "database" / "galaxy_ai_tools.db"
    detector = DuplicationDetector(db_path)

    command = sys.argv[1]

    if command == "stats":
        print("Duplicate Statistics")
        print("=" * 60)
        stats = detector.get_duplicate_statistics()

        print(f"\nTotal tools: {stats['total_tools']}")
        print(f"Unique names: {stats['unique_names']}")
        print(f"Duplicate names: {stats['duplicate_names']}")
        print(f"Unique repositories: {stats['unique_repos']}")
        print(f"Duplicate repositories: {stats['duplicate_repos']}")

        if stats['duplicate_name_groups']:
            print(f"\nTop duplicate names:")
            for group in stats['duplicate_name_groups'][:10]:
                print(f"  - {group['name']}: {group['count']} instances")

        if stats['duplicate_repo_groups']:
            print(f"\nTop duplicate repositories:")
            for group in stats['duplicate_repo_groups'][:10]:
                print(f"  - {group['repo']}: {group['count']} instances")

    elif command == "check":
        if len(sys.argv) < 3:
            print("Usage: python duplication_detector.py check <tool_name>")
            sys.exit(1)

        tool_name = sys.argv[2]
        metadata = {'name': tool_name, 'full_name': '', 'description': '', 'url': ''}

        is_duplicate, existing_tools = detector.check_duplicate(metadata)

        print(f"\nChecking for duplicates of: {tool_name}")
        print("=" * 60)

        if is_duplicate:
            print(f"\n⚠️  Found {len(existing_tools)} similar tool(s):")
            for i, tool in enumerate(existing_tools[:5], 1):
                print(f"\n{i}. {tool['name']} ({tool['tool_id']})")
                print(f"   Match type: {tool['match_type']}")
                print(f"   Similarity: {tool['similarity']:.2%}")
                if tool.get('repo_owner') and tool.get('repo_name'):
                    print(f"   Repository: {tool['repo_owner']}/{tool['repo_name']}")
                if tool.get('version'):
                    print(f"   Version: {tool['version']}")

            action = detector.suggest_action(existing_tools, metadata)
            print(f"\nSuggested action: {action}")
        else:
            print("\n✅ No duplicates found - safe to add")

    else:
        print(f"Unknown command: {command}")
        sys.exit(1)
