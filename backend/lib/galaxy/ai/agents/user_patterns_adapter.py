"""
User Patterns Adapter

Bridges UserPatternsService to the multi-agent system.
Provides lightweight read methods for routing decisions and
write methods for recording outcomes and learning.
"""

import json
import logging
import sqlite3
from typing import Dict, List, Any, Optional
from datetime import datetime

log = logging.getLogger(__name__)


class UserPatternsAdapter:
    """
    Adapter to make UserPatternsService usable by agents.

    Provides:
    - Lightweight read methods for fast routing decisions
    - Write methods for recording workflow outcomes
    - Pattern update logic for learning from corrections
    """

    DEFAULT_DB_PATH = "/home/yzhang/biomate/backend/database/galaxy_ai_tools.db"

    def __init__(self, db_path: str = None):
        """
        Initialize adapter.

        Args:
            db_path: Path to SQLite database
        """
        self.db_path = db_path or self.DEFAULT_DB_PATH

    def _get_db(self) -> sqlite3.Connection:
        """Get database connection with row factory."""
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn

    def _parse_json_field(self, value: str) -> Any:
        """Safely parse JSON field."""
        if not value:
            return None
        try:
            return json.loads(value)
        except (json.JSONDecodeError, TypeError):
            return value

    # ========================================================================
    # READ METHODS - For routing decisions
    # ========================================================================

    def get_routing_context(self, user_id: str) -> Dict[str, Any]:
        """
        Get minimal context for fast routing decisions.

        Returns:
            Dict with:
            - domain_preference: str (highest confidence domain)
            - domain_confidence: float
            - tool_preferences: List[Dict] (preferred tools)
            - expertise_level: str (beginner/intermediate/expert)
            - recent_domains: List[str] (domains from recent interactions)
        """
        if not user_id:
            return {}

        try:
            conn = self._get_db()

            # Get domain preference pattern
            domain_pref = self._get_domain_preference(conn, user_id)

            # Get tool preferences
            tool_prefs = self._get_tool_preferences(conn, user_id)

            # Get recent domains from interactions
            recent_domains = self._get_recent_domains(conn, user_id)

            # Infer expertise level
            expertise = self._infer_expertise(conn, user_id)

            conn.close()

            return {
                'domain_preference': domain_pref.get('domain'),
                'domain_confidence': domain_pref.get('confidence', 0.0),
                'tool_preferences': tool_prefs,
                'expertise_level': expertise,
                'recent_domains': recent_domains
            }

        except Exception as e:
            log.error(f"Error getting routing context for user {user_id}: {e}")
            return {}

    def _get_domain_preference(self, conn: sqlite3.Connection, user_id: str) -> Dict:
        """Get user's primary domain preference."""
        cursor = conn.execute("""
            SELECT pattern_data, confidence
            FROM user_patterns
            WHERE user_id = ? AND pattern_type = 'domain_preference'
            ORDER BY confidence DESC, last_observed DESC
            LIMIT 1
        """, (user_id,))

        row = cursor.fetchone()
        if row:
            pattern_data = self._parse_json_field(row['pattern_data'])
            if isinstance(pattern_data, dict):
                return {
                    'domain': pattern_data.get('domain'),
                    'confidence': row['confidence']
                }
        return {}

    def _get_tool_preferences(self, conn: sqlite3.Connection, user_id: str, limit: int = 5) -> List[Dict]:
        """Get user's tool preferences."""
        cursor = conn.execute("""
            SELECT pattern_data, confidence
            FROM user_patterns
            WHERE user_id = ? AND pattern_type = 'tool_preference'
            ORDER BY confidence DESC
            LIMIT ?
        """, (user_id, limit))

        prefs = []
        for row in cursor.fetchall():
            pattern_data = self._parse_json_field(row['pattern_data'])
            if isinstance(pattern_data, dict):
                prefs.append({
                    'tool_id': pattern_data.get('prefers_tool'),
                    'over_tool': pattern_data.get('over'),
                    'for_task': pattern_data.get('when'),
                    'confidence': row['confidence']
                })
        return prefs

    def _get_recent_domains(self, conn: sqlite3.Connection, user_id: str, limit: int = 5) -> List[str]:
        """Get domains from recent user interactions."""
        cursor = conn.execute("""
            SELECT DISTINCT inferred_domain
            FROM context_inferences
            WHERE user_id = ? AND inferred_domain IS NOT NULL
            ORDER BY timestamp DESC
            LIMIT ?
        """, (user_id, limit))

        return [row['inferred_domain'] for row in cursor.fetchall()]

    def _infer_expertise(self, conn: sqlite3.Connection, user_id: str) -> str:
        """Infer user expertise level from interaction patterns."""
        # Check for explicit complexity pattern
        cursor = conn.execute("""
            SELECT pattern_data, confidence
            FROM user_patterns
            WHERE user_id = ? AND pattern_type = 'complexity_level'
            ORDER BY confidence DESC
            LIMIT 1
        """, (user_id,))

        row = cursor.fetchone()
        if row:
            pattern_data = self._parse_json_field(row['pattern_data'])
            if isinstance(pattern_data, dict):
                pref = pattern_data.get('complexity_preference', 'standard')
                if pref == 'complex':
                    return 'expert'
                elif pref == 'simple':
                    return 'beginner'
                return 'intermediate'

        # Fallback: check interaction count
        cursor = conn.execute("""
            SELECT COUNT(*) as count FROM user_interactions WHERE user_id = ?
        """, (user_id,))

        row = cursor.fetchone()
        if row:
            count = row['count']
            if count > 50:
                return 'expert'
            elif count > 10:
                return 'intermediate'

        return 'beginner'

    def get_user_insights(self, user_id: str) -> Dict[str, Any]:
        """
        Get comprehensive user insights.

        More detailed than get_routing_context(), useful for
        personalization beyond routing.
        """
        if not user_id:
            return {}

        try:
            conn = self._get_db()

            # Get all patterns
            cursor = conn.execute("""
                SELECT pattern_type, pattern_data, confidence, evidence_count
                FROM user_patterns
                WHERE user_id = ?
                ORDER BY confidence DESC
            """, (user_id,))

            patterns = []
            for row in cursor.fetchall():
                patterns.append({
                    'type': row['pattern_type'],
                    'data': self._parse_json_field(row['pattern_data']),
                    'confidence': row['confidence'],
                    'evidence_count': row['evidence_count']
                })

            # Get interaction stats
            cursor = conn.execute("""
                SELECT
                    COUNT(*) as total_interactions,
                    SUM(CASE WHEN workflow_success = 1 THEN 1 ELSE 0 END) as successful_workflows,
                    AVG(user_feedback_rating) as avg_rating
                FROM user_interactions
                WHERE user_id = ?
            """, (user_id,))

            stats = dict(cursor.fetchone()) if cursor.fetchone() else {}

            conn.close()

            return {
                'user_id': user_id,
                'patterns': patterns,
                'interaction_stats': stats,
                'routing_context': self.get_routing_context(user_id)
            }

        except Exception as e:
            log.error(f"Error getting user insights for {user_id}: {e}")
            return {}

    # ========================================================================
    # WRITE METHODS - For recording outcomes
    # ========================================================================

    def update_domain_preference(
        self,
        user_id: str,
        domain: str,
        confidence_boost: float = 0.1
    ):
        """
        Update user's domain preference from feedback.

        Args:
            user_id: User identifier
            domain: Domain to boost
            confidence_boost: Amount to increase confidence
        """
        if not user_id or not domain:
            return

        try:
            conn = self._get_db()

            # Check if pattern exists
            cursor = conn.execute("""
                SELECT pattern_id, confidence, evidence_count, pattern_data
                FROM user_patterns
                WHERE user_id = ? AND pattern_type = 'domain_preference'
                  AND json_extract(pattern_data, '$.domain') = ?
            """, (user_id, domain))

            row = cursor.fetchone()

            if row:
                # Update existing pattern
                new_confidence = min(1.0, row['confidence'] + confidence_boost)
                new_evidence = row['evidence_count'] + 1
                conn.execute("""
                    UPDATE user_patterns
                    SET confidence = ?,
                        evidence_count = ?,
                        last_observed = datetime('now'),
                        last_updated = datetime('now')
                    WHERE pattern_id = ?
                """, (new_confidence, new_evidence, row['pattern_id']))
            else:
                # Insert new pattern
                pattern_data = json.dumps({'domain': domain})
                conn.execute("""
                    INSERT INTO user_patterns
                    (user_id, pattern_type, pattern_data, confidence, evidence_count,
                     first_observed, last_observed, last_updated)
                    VALUES (?, 'domain_preference', ?, ?, 1,
                            datetime('now'), datetime('now'), datetime('now'))
                """, (user_id, pattern_data, confidence_boost))

            conn.commit()
            conn.close()

            log.info(f"Updated domain preference for user {user_id}: {domain} (+{confidence_boost})")

        except Exception as e:
            log.error(f"Error updating domain preference: {e}")

    def record_tool_preference(
        self,
        user_id: str,
        preferred_tool: str,
        over_tool: str,
        for_task: str = None
    ):
        """
        Record tool preference from user's correction.

        Args:
            user_id: User identifier
            preferred_tool: Tool user preferred
            over_tool: Tool that was originally suggested
            for_task: Context/task type for this preference
        """
        if not user_id or not preferred_tool:
            return

        try:
            conn = self._get_db()

            pattern_data = json.dumps({
                'prefers_tool': preferred_tool,
                'over': over_tool,
                'when': for_task
            })

            # Check if similar pattern exists
            cursor = conn.execute("""
                SELECT pattern_id, confidence, evidence_count
                FROM user_patterns
                WHERE user_id = ? AND pattern_type = 'tool_preference'
                  AND json_extract(pattern_data, '$.prefers_tool') = ?
                  AND json_extract(pattern_data, '$.over') = ?
            """, (user_id, preferred_tool, over_tool))

            row = cursor.fetchone()

            if row:
                # Update existing
                new_confidence = min(1.0, row['confidence'] + 0.1)
                new_evidence = row['evidence_count'] + 1
                conn.execute("""
                    UPDATE user_patterns
                    SET confidence = ?,
                        evidence_count = ?,
                        last_observed = datetime('now'),
                        last_updated = datetime('now')
                    WHERE pattern_id = ?
                """, (new_confidence, new_evidence, row['pattern_id']))
            else:
                # Insert new
                conn.execute("""
                    INSERT INTO user_patterns
                    (user_id, pattern_type, pattern_data, confidence, evidence_count,
                     first_observed, last_observed, last_updated)
                    VALUES (?, 'tool_preference', ?, 0.5, 1,
                            datetime('now'), datetime('now'), datetime('now'))
                """, (user_id, pattern_data))

            conn.commit()
            conn.close()

            log.info(f"Recorded tool preference for user {user_id}: {preferred_tool} over {over_tool}")

        except Exception as e:
            log.error(f"Error recording tool preference: {e}")

    def record_interaction(
        self,
        user_id: str,
        interaction_type: str,
        query: str = None,
        selected_tool_id: str = None,
        workflow_id: str = None,
        workflow_success: bool = None,
        detected_context: Dict = None
    ):
        """
        Record a user interaction.

        Args:
            user_id: User identifier
            interaction_type: Type of interaction ('workflow_generation', 'tool_select', etc.)
            query: Query text if applicable
            selected_tool_id: Selected tool if applicable
            workflow_id: Workflow ID if applicable
            workflow_success: Whether workflow succeeded
            detected_context: Detected context/metadata
        """
        if not user_id:
            return

        try:
            conn = self._get_db()

            conn.execute("""
                INSERT INTO user_interactions
                (user_id, interaction_type, query, selected_tool_id,
                 workflow_id, workflow_success, detected_context, timestamp)
                VALUES (?, ?, ?, ?, ?, ?, ?, datetime('now'))
            """, (
                user_id,
                interaction_type,
                query,
                selected_tool_id,
                workflow_id,
                1 if workflow_success else (0 if workflow_success is False else None),
                json.dumps(detected_context) if detected_context else None
            ))

            conn.commit()
            conn.close()

        except Exception as e:
            log.error(f"Error recording interaction: {e}")

    def record_context_inference(
        self,
        user_id: str,
        query_text: str,
        inferred_domain: str,
        domain_confidence: float,
        inferred_data_type: str = None,
        inference_method: str = 'llm'
    ):
        """
        Record a context inference for learning.

        Args:
            user_id: User identifier
            query_text: Original query
            inferred_domain: Domain that was inferred
            domain_confidence: Confidence of inference
            inferred_data_type: Inferred data type if applicable
            inference_method: Method used for inference
        """
        if not user_id:
            return

        try:
            conn = self._get_db()

            conn.execute("""
                INSERT INTO context_inferences
                (user_id, query_text, inferred_domain, domain_confidence,
                 inferred_data_type, inference_method, timestamp)
                VALUES (?, ?, ?, ?, ?, ?, datetime('now'))
            """, (
                user_id,
                query_text,
                inferred_domain,
                domain_confidence,
                inferred_data_type,
                inference_method
            ))

            conn.commit()
            conn.close()

        except Exception as e:
            log.error(f"Error recording context inference: {e}")

    # ========================================================================
    # LEARNED KEYWORDS - For dynamic routing enhancement
    # ========================================================================

    def get_learned_keywords(self, domain: str = None) -> Dict[str, List[str]]:
        """
        Get learned keywords for domain(s).

        Args:
            domain: Specific domain or None for all

        Returns:
            Dict mapping domain -> list of keywords
        """
        try:
            conn = self._get_db()

            if domain:
                cursor = conn.execute("""
                    SELECT domain, keyword, weight
                    FROM learned_domain_keywords
                    WHERE domain = ?
                    ORDER BY weight DESC
                """, (domain,))
            else:
                cursor = conn.execute("""
                    SELECT domain, keyword, weight
                    FROM learned_domain_keywords
                    ORDER BY domain, weight DESC
                """)

            result = {}
            for row in cursor.fetchall():
                d = row['domain']
                if d not in result:
                    result[d] = []
                result[d].append(row['keyword'])

            conn.close()
            return result

        except Exception as e:
            log.error(f"Error getting learned keywords: {e}")
            return {}

    def add_learned_keyword(
        self,
        domain: str,
        keyword: str,
        source: str = 'user_correction',
        user_id: str = None,
        weight: float = 1.0
    ):
        """
        Add a learned keyword for a domain.

        Args:
            domain: Target domain
            keyword: Keyword to add
            source: Source of learning
            user_id: User who triggered learning
            weight: Initial weight
        """
        if not domain or not keyword:
            return

        try:
            conn = self._get_db()

            # Try to insert or update
            cursor = conn.execute("""
                SELECT keyword_id, evidence_count, weight
                FROM learned_domain_keywords
                WHERE domain = ? AND keyword = ?
            """, (domain, keyword.lower()))

            row = cursor.fetchone()

            if row:
                # Update existing
                new_evidence = row['evidence_count'] + 1
                new_weight = min(2.0, row['weight'] + 0.1)
                conn.execute("""
                    UPDATE learned_domain_keywords
                    SET evidence_count = ?,
                        weight = ?,
                        updated_at = datetime('now')
                    WHERE keyword_id = ?
                """, (new_evidence, new_weight, row['keyword_id']))
            else:
                # Insert new
                conn.execute("""
                    INSERT INTO learned_domain_keywords
                    (domain, keyword, weight, source, user_id, evidence_count, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, 1, datetime('now'), datetime('now'))
                """, (domain, keyword.lower(), weight, source, user_id))

            conn.commit()
            conn.close()

            log.info(f"Added learned keyword '{keyword}' for domain '{domain}'")

        except Exception as e:
            log.error(f"Error adding learned keyword: {e}")
