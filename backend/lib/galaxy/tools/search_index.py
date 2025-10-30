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

        # Convert to OR query for broader matching (implicit AND is too restrictive)
        # Split into terms and join with OR operators
        terms = [term.strip() for term in query.split() if term.strip()]
        if len(terms) > 1:
            query = ' OR '.join(terms)
        elif len(terms) == 1:
            query = terms[0]

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
            # Try exact match first
            cursor.execute('SELECT * FROM tools WHERE tool_id = ?', (tool_id,))
            row = cursor.fetchone()

            if row:
                return dict(row)

            # If no exact match, try prefix match (handles tool_ids with newlines and trailing content)
            # This is needed because some tool_ids in the database have format:
            # "toolshed.g2.bx.psu.edu/repos/owner/repo/tool_name\nActual_Tool_Name"
            cursor.execute("SELECT * FROM tools WHERE tool_id LIKE ? || '%'", (tool_id,))
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

    def get_tool_schema(self, tool_id: str) -> Optional[Dict[str, Any]]:
        """
        Get tool parameter schema formatted for frontend consumption

        Args:
            tool_id: Tool identifier

        Returns:
            Structured tool schema with parsed parameters or None if not found
        """
        import json

        tool = self.get_by_id(tool_id)
        if not tool:
            return None

        # Parse JSON fields
        try:
            parameters_raw = tool.get('parameters', '[]')
            parameters = json.loads(parameters_raw) if isinstance(parameters_raw, str) else (parameters_raw or [])

            inputs_raw = tool.get('inputs', '[]')
            inputs = json.loads(inputs_raw) if isinstance(inputs_raw, str) else (inputs_raw or [])

            outputs_raw = tool.get('outputs', '[]')
            outputs = json.loads(outputs_raw) if isinstance(outputs_raw, str) else (outputs_raw or [])

            help_text_raw = tool.get('help_text', '{}')
            help_text = json.loads(help_text_raw) if isinstance(help_text_raw, str) else (help_text_raw or {})
        except (json.JSONDecodeError, TypeError) as e:
            log.warning(f"Failed to parse JSON fields for tool {tool_id}: {e}")
            parameters = []
            inputs = []
            outputs = []
            help_text = {}

        # Convert database parameters to frontend ToolParameter format
        frontend_inputs = []

        # Use parameters from database first
        for param in parameters:
            # Map database parameter format to frontend ToolParameter format
            frontend_param = {
                'name': param.get('name', ''),
                'label': param.get('label', param.get('name', '')),
                'type': self._map_parameter_type(param.get('type', 'text')),
                'help': param.get('help', ''),
                'optional': param.get('optional', True),
            }

            # Add type-specific fields
            if frontend_param['type'] in ['integer', 'float']:
                if 'min' in param:
                    frontend_param['min'] = param['min']
                if 'max' in param:
                    frontend_param['max'] = param['max']

            if frontend_param['type'] == 'select' and 'options' in param:
                frontend_param['options'] = param['options']

            # Set default value if available
            if 'value' in param or 'default' in param:
                frontend_param['value'] = param.get('value', param.get('default'))

            frontend_inputs.append(frontend_param)

        # If no parameters in database, try to use inputs
        if not frontend_inputs and inputs:
            for input_spec in inputs:
                frontend_param = {
                    'name': input_spec.get('name', ''),
                    'label': input_spec.get('label', input_spec.get('name', '')),
                    'type': self._map_parameter_type(input_spec.get('type', 'text')),
                    'help': input_spec.get('help', ''),
                    'optional': input_spec.get('optional', True),
                }
                frontend_inputs.append(frontend_param)

        # Format outputs
        frontend_outputs = []
        for output in outputs:
            frontend_outputs.append({
                'name': output.get('name', ''),
                'format': output.get('format', 'data'),
                'label': output.get('label', output.get('name', '')),
            })

        # Return formatted schema
        return {
            'id': tool.get('tool_id') or tool.get('id'),
            'name': tool.get('name', ''),
            'version': tool.get('version', ''),
            'description': tool.get('description', '') or help_text.get('what_it_does', ''),
            'inputs': frontend_inputs,
            'outputs': frontend_outputs,
        }

    def _map_parameter_type(self, db_type: str) -> str:
        """Map database parameter type to frontend ToolParameter type"""
        type_mapping = {
            'data': 'data',
            'text': 'text',
            'integer': 'integer',
            'int': 'integer',
            'float': 'float',
            'number': 'float',
            'boolean': 'boolean',
            'bool': 'boolean',
            'select': 'select',
            'color': 'color',
            'genomebuild': 'genomebuild',
        }
        return type_mapping.get(db_type.lower(), 'text')

    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit - cleanup connection"""
        self.close()
        return False
