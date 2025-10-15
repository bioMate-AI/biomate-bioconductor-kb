"""
Galaxy Tool Search Index
Provides fast search and lookup of tools from ToolShed crawled data
Thread-safe with proper resource management
"""

import sqlite3
import threading
from typing import List, Dict, Optional, Any
from pathlib import Path
from contextlib import contextmanager
import logging

log = logging.getLogger(__name__)


class ToolSearchIndex:
    """
    Thread-safe searchable index of Galaxy ToolShed tools
    Uses thread-local connections for concurrent access
    """

    def __init__(self, db_path: str = None):
        if db_path is None:
            db_path = str(Path(__file__).parent.parent.parent.parent / "galaxy_ai_tools.db")
        self.db_path = db_path
        self._local = threading.local()
        self._lock = threading.RLock()

        # Verify database exists
        if not Path(self.db_path).exists():
            raise FileNotFoundError(f"Tool search index not found at {self.db_path}")

    def _get_connection(self) -> sqlite3.Connection:
        """Get thread-local database connection"""
        if not hasattr(self._local, 'conn') or self._local.conn is None:
            try:
                self._local.conn = sqlite3.connect(self.db_path)
                self._local.conn.row_factory = sqlite3.Row
                log.debug(f"Created thread-local connection for thread {threading.current_thread().name}")
            except Exception as e:
                log.error(f"Failed to connect to tool search index: {e}")
                raise
        return self._local.conn

    @contextmanager
    def _get_cursor(self):
        """Context manager for cursor with automatic cleanup"""
        conn = self._get_connection()
        cursor = conn.cursor()
        try:
            yield cursor
        finally:
            cursor.close()

    def search(self, query: str, category: Optional[str] = None, limit: int = 50) -> List[Dict[str, Any]]:
        """
        Full-text search for tools (thread-safe)

        Args:
            query: Search query string (non-empty)
            category: Optional category filter
            limit: Maximum results to return (1-1000)

        Returns:
            List of tool dictionaries

        Raises:
            ValueError: If query is empty or limit is invalid
        """
        # Input validation
        if not query or not query.strip():
            raise ValueError("Search query cannot be empty")
        if not isinstance(limit, int) or limit < 1 or limit > 1000:
            raise ValueError("Limit must be between 1 and 1000")

        query = query.strip()

        # Sanitize query for FTS5: quote terms with special characters
        # Replace hyphens with spaces to avoid FTS5 minus operator issues
        query = query.replace('-', ' ')

        with self._get_cursor() as cursor:
            if category:
                sql = '''
                    SELECT t.*,
                           bm25(tools_fts) as rank
                    FROM tools t
                    JOIN tools_fts fts ON t.id = fts.rowid
                    WHERE tools_fts MATCH ? AND t.category = ?
                    ORDER BY rank
                    LIMIT ?
                '''
                cursor.execute(sql, (query, category, limit))
            else:
                sql = '''
                    SELECT t.*,
                           bm25(tools_fts) as rank
                    FROM tools t
                    JOIN tools_fts fts ON t.id = fts.rowid
                    WHERE tools_fts MATCH ?
                    ORDER BY rank
                    LIMIT ?
                '''
                cursor.execute(sql, (query, limit))

            return [dict(row) for row in cursor.fetchall()]

    def get_by_id(self, tool_id: str) -> Optional[Dict[str, Any]]:
        """
        Get tool by exact ID (thread-safe)

        Args:
            tool_id: Tool identifier

        Returns:
            Tool dictionary or None if not found
        """
        if not tool_id:
            return None

        with self._get_cursor() as cursor:
            cursor.execute('SELECT * FROM tools WHERE tool_id = ?', (tool_id,))
            row = cursor.fetchone()
            return dict(row) if row else None

    def get_by_repo(self, owner: str, name: str) -> List[Dict[str, Any]]:
        """
        Get all tools from a specific repository (thread-safe)

        Args:
            owner: Repository owner
            name: Repository name

        Returns:
            List of tool dictionaries
        """
        if not owner or not name:
            return []

        with self._get_cursor() as cursor:
            cursor.execute('''
                SELECT * FROM tools
                WHERE repo_owner = ? AND repo_name = ?
                ORDER BY name
            ''', (owner, name))
            return [dict(row) for row in cursor.fetchall()]

    def get_installed_tools(self) -> List[Dict[str, Any]]:
        """Get list of installed tools (thread-safe)"""
        with self._get_cursor() as cursor:
            cursor.execute('SELECT * FROM tools WHERE is_installed = 1 ORDER BY install_date DESC')
            return [dict(row) for row in cursor.fetchall()]

    def mark_installed(self, tool_id: str, status: str = 'installed'):
        """
        Mark a tool as installed (thread-safe with locking)

        Args:
            tool_id: Tool identifier
            status: Installation status (default: 'installed')
        """
        if not tool_id:
            raise ValueError("tool_id cannot be empty")

        with self._lock:
            conn = self._get_connection()
            cursor = conn.cursor()
            try:
                cursor.execute('''
                    UPDATE tools
                    SET is_installed = 1,
                        install_status = ?,
                        install_date = CURRENT_TIMESTAMP
                    WHERE tool_id = ?
                ''', (status, tool_id))
                conn.commit()
                log.info(f"Marked tool {tool_id} as {status}")
            except Exception as e:
                conn.rollback()
                log.error(f"Failed to mark tool {tool_id} as installed: {e}")
                raise
            finally:
                cursor.close()

    def mark_uninstalled(self, tool_id: str):
        """
        Mark a tool as uninstalled (thread-safe with locking)

        Args:
            tool_id: Tool identifier
        """
        if not tool_id:
            raise ValueError("tool_id cannot be empty")

        with self._lock:
            conn = self._get_connection()
            cursor = conn.cursor()
            try:
                cursor.execute('''
                    UPDATE tools
                    SET is_installed = 0,
                        install_status = 'not_installed',
                        install_date = NULL
                    WHERE tool_id = ?
                ''', (tool_id,))
                conn.commit()
                log.info(f"Marked tool {tool_id} as uninstalled")
            except Exception as e:
                conn.rollback()
                log.error(f"Failed to mark tool {tool_id} as uninstalled: {e}")
                raise
            finally:
                cursor.close()

    def get_categories(self) -> List[str]:
        """Get list of all categories (thread-safe)"""
        with self._get_cursor() as cursor:
            cursor.execute('SELECT DISTINCT category FROM tools ORDER BY category')
            return [row[0] for row in cursor.fetchall()]

    def get_category_stats(self) -> Dict[str, int]:
        """Get tool count per category (thread-safe)"""
        with self._get_cursor() as cursor:
            cursor.execute('''
                SELECT category, COUNT(*) as count
                FROM tools
                GROUP BY category
                ORDER BY count DESC
            ''')
            return {row[0]: row[1] for row in cursor.fetchall()}

    def close(self):
        """Close thread-local connection"""
        if hasattr(self._local, 'conn') and self._local.conn is not None:
            try:
                self._local.conn.close()
                self._local.conn = None
                log.debug(f"Closed connection for thread {threading.current_thread().name}")
            except Exception as e:
                log.error(f"Error closing connection: {e}")

    def __enter__(self):
        """Context manager entry"""
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit - cleanup connection"""
        self.close()
        return False
