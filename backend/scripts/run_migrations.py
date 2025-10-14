#!/usr/bin/env python3
"""
Database Migration Runner
Runs SQL migration scripts in order and tracks which migrations have been applied.

Usage:
    python3 scripts/run_migrations.py [--db-path PATH] [--dry-run] [--rollback N]

Options:
    --db-path PATH    Path to database file (default: galaxy_ai_tools.db)
    --dry-run         Show what would be done without applying changes
    --rollback N      Rollback last N migrations
    --list            List all migrations and their status
"""

import sqlite3
import os
import sys
from pathlib import Path
from datetime import datetime
import argparse
import re

class MigrationRunner:
    def __init__(self, db_path='galaxy_ai_tools.db', migrations_dir='scripts/migrations'):
        self.db_path = Path(db_path)
        self.migrations_dir = Path(__file__).parent / '..' / migrations_dir
        self.migrations_dir = self.migrations_dir.resolve()

        if not self.db_path.exists():
            raise FileNotFoundError(f"Database not found: {self.db_path}")

        if not self.migrations_dir.exists():
            self.migrations_dir.mkdir(parents=True, exist_ok=True)

    def _get_connection(self):
        """Get database connection"""
        return sqlite3.connect(str(self.db_path))

    def _init_migrations_table(self):
        """Create migrations tracking table if it doesn't exist"""
        with self._get_connection() as conn:
            conn.execute("""
                CREATE TABLE IF NOT EXISTS schema_migrations (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    migration_name TEXT UNIQUE NOT NULL,
                    applied_at TEXT NOT NULL,
                    status TEXT DEFAULT 'applied'
                )
            """)
            conn.commit()

    def _get_applied_migrations(self):
        """Get list of already applied migrations"""
        with self._get_connection() as conn:
            cursor = conn.execute("""
                SELECT migration_name, applied_at, status
                FROM schema_migrations
                ORDER BY id
            """)
            return [{'name': row[0], 'applied_at': row[1], 'status': row[2]}
                    for row in cursor.fetchall()]

    def _get_migration_files(self):
        """Get list of migration SQL files"""
        if not self.migrations_dir.exists():
            return []

        files = list(self.migrations_dir.glob('*.sql'))
        # Sort by filename (expecting format: 001_description.sql)
        files.sort(key=lambda f: f.name)
        return files

    def _parse_migration_metadata(self, sql_content):
        """Extract metadata from migration comments"""
        lines = sql_content.split('\n')
        metadata = {}

        for line in lines[:10]:  # Check first 10 lines
            if line.startswith('-- Migration:'):
                metadata['title'] = line.replace('-- Migration:', '').strip()
            elif line.startswith('-- Date:'):
                metadata['date'] = line.replace('-- Date:', '').strip()
            elif line.startswith('-- Purpose:'):
                metadata['purpose'] = line.replace('-- Purpose:', '').strip()

        return metadata

    def list_migrations(self):
        """List all migrations with their status"""
        self._init_migrations_table()
        applied = {m['name']: m for m in self._get_applied_migrations()}
        files = self._get_migration_files()

        print("\n" + "="*80)
        print("MIGRATION STATUS")
        print("="*80)
        print(f"Database: {self.db_path}")
        print(f"Migrations directory: {self.migrations_dir}")
        print()

        if not files:
            print("No migration files found.")
            return

        for file in files:
            migration_name = file.name
            is_applied = migration_name in applied

            # Read metadata
            with open(file, 'r') as f:
                content = f.read()
                metadata = self._parse_migration_metadata(content)

            status_icon = "✓" if is_applied else "○"
            status_text = "APPLIED" if is_applied else "PENDING"

            print(f"{status_icon} [{status_text}] {migration_name}")

            if metadata.get('title'):
                print(f"   Title: {metadata['title']}")
            if metadata.get('purpose'):
                print(f"   Purpose: {metadata['purpose']}")

            if is_applied:
                applied_info = applied[migration_name]
                print(f"   Applied: {applied_info['applied_at']}")

            print()

        applied_count = len([f for f in files if f.name in applied])
        print(f"Applied: {applied_count}/{len(files)} migrations")
        print("="*80 + "\n")

    def run_migrations(self, dry_run=False):
        """Run pending migrations"""
        self._init_migrations_table()
        applied = {m['name'] for m in self._get_applied_migrations()}
        files = self._get_migration_files()

        pending = [f for f in files if f.name not in applied]

        if not pending:
            print("✓ No pending migrations. Database is up to date.")
            return True

        print(f"\nFound {len(pending)} pending migration(s):\n")

        for file in pending:
            print(f"  - {file.name}")

        if dry_run:
            print("\n[DRY RUN] No changes will be applied.")
            return True

        print("\nApplying migrations...\n")

        success_count = 0

        for file in pending:
            try:
                print(f"Applying {file.name}...")

                # Read migration SQL
                with open(file, 'r') as f:
                    sql = f.read()

                # Execute migration
                with self._get_connection() as conn:
                    # Execute the migration
                    conn.executescript(sql)

                    # Record migration
                    conn.execute("""
                        INSERT INTO schema_migrations (migration_name, applied_at, status)
                        VALUES (?, ?, 'applied')
                    """, (file.name, datetime.now().isoformat()))

                    conn.commit()

                print(f"  ✓ {file.name} applied successfully")
                success_count += 1

            except Exception as e:
                print(f"  ✗ {file.name} failed: {e}")
                print(f"\nMigration stopped at {file.name}")
                print(f"Successfully applied: {success_count}/{len(pending)}")
                return False

        print(f"\n✓ All {success_count} migrations applied successfully!")
        return True

    def rollback(self, count=1, dry_run=False):
        """Rollback last N migrations"""
        self._init_migrations_table()
        applied = self._get_applied_migrations()

        if not applied:
            print("No migrations to rollback.")
            return True

        to_rollback = applied[-count:] if count <= len(applied) else applied

        print(f"\nWould rollback {len(to_rollback)} migration(s):\n")

        for migration in reversed(to_rollback):
            print(f"  - {migration['name']} (applied: {migration['applied_at']})")

        if dry_run:
            print("\n[DRY RUN] No changes will be applied.")
            return True

        print("\nWARNING: Rollback removes migration records but does NOT undo schema changes.")
        print("You must manually revert database changes if needed.")
        response = input("\nProceed with rollback? (yes/no): ")

        if response.lower() != 'yes':
            print("Rollback canceled.")
            return False

        with self._get_connection() as conn:
            for migration in reversed(to_rollback):
                conn.execute("""
                    DELETE FROM schema_migrations
                    WHERE migration_name = ?
                """, (migration['name'],))
                print(f"  ✓ Rolled back {migration['name']}")

            conn.commit()

        print(f"\n✓ Rolled back {len(to_rollback)} migration(s)")
        print("Note: Schema changes were NOT automatically reverted.")
        return True

def main():
    parser = argparse.ArgumentParser(
        description='BioMate Database Migration Runner',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )

    parser.add_argument('--db-path', default='galaxy_ai_tools.db',
                       help='Path to database file (default: galaxy_ai_tools.db)')
    parser.add_argument('--dry-run', action='store_true',
                       help='Show what would be done without applying changes')
    parser.add_argument('--rollback', type=int, metavar='N',
                       help='Rollback last N migrations')
    parser.add_argument('--list', action='store_true',
                       help='List all migrations and their status')

    args = parser.parse_args()

    try:
        runner = MigrationRunner(db_path=args.db_path)

        if args.list:
            runner.list_migrations()
        elif args.rollback:
            runner.rollback(count=args.rollback, dry_run=args.dry_run)
        else:
            runner.run_migrations(dry_run=args.dry_run)

        sys.exit(0)

    except Exception as e:
        print(f"\n✗ Error: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()
