"""
Workflow Learning Service

Learns from user corrections and workflow outcomes to improve routing and tool selection.

Features:
- Learn from domain corrections → Update user patterns & router keywords
- Learn from tool corrections → Update tool preferences
- Learn from workflow outcomes → Reinforce successful patterns
- Batch learning from historical data
"""

import json
import logging
import sqlite3
import re
from typing import Dict, List, Any, Optional, Tuple
from datetime import datetime, timedelta
from collections import defaultdict

log = logging.getLogger(__name__)


class WorkflowLearningService:
    """
    Learns from user corrections and workflow outcomes.

    Integrates with:
    - UserPatternsAdapter: Update user preferences
    - EnhancedDomainRouter: Add learned keywords
    - WorkflowAuditService: Read correction history
    """

    DEFAULT_DB_PATH = "/home/yzhang/biomate/backend/database/galaxy_ai_tools.db"

    def __init__(
        self,
        user_patterns_adapter=None,
        domain_router=None,
        db_path: str = None
    ):
        """
        Initialize learning service.

        Args:
            user_patterns_adapter: Adapter for user patterns
            domain_router: Enhanced domain router for keyword updates
            db_path: Path to SQLite database
        """
        self.patterns = user_patterns_adapter
        self.router = domain_router
        self.db_path = db_path or self.DEFAULT_DB_PATH

        log.info("WorkflowLearningService initialized")

    def _get_db(self) -> sqlite3.Connection:
        """Get database connection."""
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn

    # ========================================================================
    # CORRECTION LEARNING
    # ========================================================================

    def learn_from_correction(
        self,
        user_id: str,
        audit_id: int,
        correction_type: str,
        original_value: Any,
        corrected_value: Any,
        query_text: str = None
    ) -> Dict[str, Any]:
        """
        Learn from a user correction.

        Args:
            user_id: User who made correction
            audit_id: Audit record ID
            correction_type: Type ('domain', 'tool_selection', 'parameters')
            original_value: Original suggested value
            corrected_value: User's corrected value
            query_text: Original query (for keyword extraction)

        Returns:
            Dict with learning results
        """
        results = {
            'user_id': user_id,
            'correction_type': correction_type,
            'learned': False,
            'actions': []
        }

        try:
            if correction_type == 'domain':
                self._learn_domain_correction(
                    user_id, original_value, corrected_value, query_text, results
                )

            elif correction_type == 'tool_selection':
                self._learn_tool_correction(
                    user_id, original_value, corrected_value, results
                )

            elif correction_type == 'parameters':
                self._learn_parameter_correction(
                    user_id, original_value, corrected_value, results
                )

            results['learned'] = True
            log.info(f"Learned from {correction_type} correction for user {user_id}: "
                    f"{len(results['actions'])} actions taken")

        except Exception as e:
            log.error(f"Error learning from correction: {e}")
            results['error'] = str(e)

        return results

    def _learn_domain_correction(
        self,
        user_id: str,
        original_domain: str,
        corrected_domain: str,
        query_text: str,
        results: Dict
    ):
        """Learn from domain correction."""

        # 1. Update user's domain preference
        if self.patterns:
            self.patterns.update_domain_preference(
                user_id=user_id,
                domain=corrected_domain,
                confidence_boost=0.2  # Stronger boost for explicit correction
            )
            results['actions'].append(f"Updated domain preference: {corrected_domain}")

        # 2. Extract keywords from query and add to corrected domain
        if query_text and self.router:
            keywords = self._extract_domain_keywords(query_text, corrected_domain)
            if keywords:
                self.router.add_learned_keywords(
                    domain=corrected_domain,
                    keywords=keywords,
                    source='user_correction',
                    user_id=user_id
                )
                results['actions'].append(f"Added learned keywords: {keywords}")

        # 3. Record the correction pattern for batch learning
        self._record_correction_pattern(
            user_id=user_id,
            pattern_type='domain_correction',
            pattern_data={
                'original': original_domain,
                'corrected': corrected_domain,
                'query_excerpt': query_text[:100] if query_text else None
            }
        )

    def _learn_tool_correction(
        self,
        user_id: str,
        original_tool: Any,
        corrected_tool: Any,
        results: Dict
    ):
        """Learn from tool selection correction."""

        # Parse tool info
        original_id = original_tool if isinstance(original_tool, str) else original_tool.get('tool_id')
        corrected_id = corrected_tool if isinstance(corrected_tool, str) else corrected_tool.get('tool_id')

        if not original_id or not corrected_id:
            return

        # 1. Record tool preference
        if self.patterns:
            task_type = corrected_tool.get('task_type') if isinstance(corrected_tool, dict) else None
            self.patterns.record_tool_preference(
                user_id=user_id,
                preferred_tool=corrected_id,
                over_tool=original_id,
                for_task=task_type
            )
            results['actions'].append(f"Recorded tool preference: {corrected_id} over {original_id}")

        # 2. Record for batch learning
        self._record_correction_pattern(
            user_id=user_id,
            pattern_type='tool_correction',
            pattern_data={
                'original': original_id,
                'corrected': corrected_id
            }
        )

    def _learn_parameter_correction(
        self,
        user_id: str,
        original_params: Any,
        corrected_params: Any,
        results: Dict
    ):
        """Learn from parameter correction."""

        # Parameter learning is more complex - store for batch analysis
        self._record_correction_pattern(
            user_id=user_id,
            pattern_type='parameter_correction',
            pattern_data={
                'original': original_params,
                'corrected': corrected_params
            }
        )
        results['actions'].append("Recorded parameter correction for batch learning")

    def _extract_domain_keywords(
        self,
        query_text: str,
        target_domain: str
    ) -> List[str]:
        """
        Extract potential keywords from query for a domain.

        Uses simple heuristics to identify domain-relevant terms.
        """
        # Skip if query is too short
        if len(query_text) < 10:
            return []

        # Common words to ignore
        stop_words = {
            'the', 'a', 'an', 'is', 'are', 'was', 'were', 'be', 'been',
            'being', 'have', 'has', 'had', 'do', 'does', 'did', 'will',
            'would', 'could', 'should', 'may', 'might', 'must', 'shall',
            'can', 'need', 'dare', 'ought', 'used', 'to', 'of', 'in',
            'for', 'on', 'with', 'at', 'by', 'from', 'up', 'about',
            'into', 'through', 'during', 'before', 'after', 'above',
            'below', 'between', 'under', 'again', 'further', 'then',
            'once', 'here', 'there', 'when', 'where', 'why', 'how',
            'all', 'each', 'few', 'more', 'most', 'other', 'some',
            'such', 'no', 'nor', 'not', 'only', 'own', 'same', 'so',
            'than', 'too', 'very', 'just', 'and', 'but', 'if', 'or',
            'because', 'as', 'until', 'while', 'i', 'me', 'my', 'myself',
            'we', 'our', 'you', 'your', 'he', 'she', 'it', 'they',
            'what', 'which', 'who', 'whom', 'this', 'that', 'these',
            'those', 'am', 'want', 'run', 'perform', 'analyze', 'help',
            'please', 'data', 'analysis', 'using', 'use', 'file', 'files'
        }

        # Extract words
        words = re.findall(r'\b[a-zA-Z][a-zA-Z0-9_-]+\b', query_text.lower())

        # Filter to potential keywords
        candidates = []
        for word in words:
            # Skip stop words and short words
            if word in stop_words or len(word) < 3:
                continue

            # Skip if it's already a known keyword for any domain
            if self.router:
                is_known = False
                for domain_keywords in self.router.DOMAIN_KEYWORDS.values():
                    if word in domain_keywords:
                        is_known = True
                        break
                if is_known:
                    continue

            candidates.append(word)

        # Return unique candidates (limit to 3)
        return list(set(candidates))[:3]

    def _record_correction_pattern(
        self,
        user_id: str,
        pattern_type: str,
        pattern_data: Dict
    ):
        """Record correction pattern for batch learning."""
        try:
            conn = self._get_db()
            conn.execute("""
                INSERT INTO workflow_user_corrections
                (audit_id, user_id, correction_type, original_value, corrected_value, timestamp)
                VALUES (0, ?, ?, ?, ?, datetime('now'))
            """, (
                user_id,
                pattern_type,
                json.dumps(pattern_data.get('original')),
                json.dumps(pattern_data.get('corrected'))
            ))
            conn.commit()
            conn.close()
        except Exception as e:
            log.warning(f"Failed to record correction pattern: {e}")

    # ========================================================================
    # OUTCOME LEARNING
    # ========================================================================

    def learn_from_workflow_outcome(
        self,
        user_id: str,
        audit_id: int,
        success: bool,
        user_kept: bool = True,
        rating: int = None,
        execution_time_ms: int = None
    ) -> Dict[str, Any]:
        """
        Learn from workflow execution outcome.

        Args:
            user_id: User ID
            audit_id: Audit record ID
            success: Whether workflow executed successfully
            user_kept: Whether user kept/used the workflow
            rating: User rating (1-5) if provided
            execution_time_ms: Execution time

        Returns:
            Learning results
        """
        results = {
            'user_id': user_id,
            'audit_id': audit_id,
            'learned': False,
            'actions': []
        }

        try:
            # Get audit record
            conn = self._get_db()
            cursor = conn.execute("""
                SELECT query_text, routing_decision, routing_method,
                       primary_domain, workflow_id
                FROM workflow_generation_audit
                WHERE audit_id = ?
            """, (audit_id,))

            row = cursor.fetchone()
            conn.close()

            if not row:
                log.warning(f"Audit record {audit_id} not found")
                return results

            query_text = row['query_text']
            routing = json.loads(row['routing_decision']) if row['routing_decision'] else {}
            domain = row['primary_domain']

            # Positive outcome - reinforce patterns
            if success and user_kept:
                confidence_boost = 0.1
                if rating and rating >= 4:
                    confidence_boost = 0.15

                # Reinforce domain preference
                if self.patterns and domain:
                    self.patterns.update_domain_preference(
                        user_id=user_id,
                        domain=domain,
                        confidence_boost=confidence_boost
                    )
                    results['actions'].append(f"Reinforced domain {domain} (+{confidence_boost})")

                # Record successful interaction
                if self.patterns:
                    self.patterns.record_interaction(
                        user_id=user_id,
                        interaction_type='workflow_success',
                        query=query_text,
                        workflow_id=row['workflow_id'],
                        workflow_success=True
                    )

            # Negative outcome - track for analysis
            elif not success or not user_kept:
                if self.patterns:
                    self.patterns.record_interaction(
                        user_id=user_id,
                        interaction_type='workflow_failure' if not success else 'workflow_rejected',
                        query=query_text,
                        workflow_id=row['workflow_id'],
                        workflow_success=False
                    )
                    results['actions'].append("Recorded negative outcome for analysis")

            results['learned'] = True

        except Exception as e:
            log.error(f"Error learning from outcome: {e}")
            results['error'] = str(e)

        return results

    # ========================================================================
    # BATCH LEARNING
    # ========================================================================

    def batch_learn(self, lookback_days: int = 7) -> Dict[str, Any]:
        """
        Periodic batch learning from accumulated data.

        Analyzes patterns across:
        - Domain corrections
        - Tool corrections
        - Success/failure patterns

        Args:
            lookback_days: Number of days to look back

        Returns:
            Batch learning results
        """
        results = {
            'lookback_days': lookback_days,
            'domain_patterns': [],
            'tool_patterns': [],
            'keywords_added': 0,
            'timestamp': datetime.now().isoformat()
        }

        try:
            conn = self._get_db()
            cutoff = (datetime.now() - timedelta(days=lookback_days)).isoformat()

            # Analyze domain correction patterns
            domain_patterns = self._analyze_domain_patterns(conn, cutoff)
            results['domain_patterns'] = domain_patterns

            # Add frequently corrected domains' keywords
            for pattern in domain_patterns:
                if pattern['count'] >= 3 and self.router:
                    # Extract common keywords from corrections
                    keywords = self._extract_batch_keywords(conn, pattern['corrected_domain'], cutoff)
                    if keywords:
                        self.router.add_learned_keywords(
                            domain=pattern['corrected_domain'],
                            keywords=keywords,
                            source='batch_learning'
                        )
                        results['keywords_added'] += len(keywords)

            # Analyze tool correction patterns
            tool_patterns = self._analyze_tool_patterns(conn, cutoff)
            results['tool_patterns'] = tool_patterns

            conn.close()

            log.info(f"Batch learning completed: {len(domain_patterns)} domain patterns, "
                    f"{len(tool_patterns)} tool patterns, {results['keywords_added']} keywords added")

        except Exception as e:
            log.error(f"Batch learning error: {e}")
            results['error'] = str(e)

        return results

    def _analyze_domain_patterns(
        self,
        conn: sqlite3.Connection,
        cutoff: str
    ) -> List[Dict]:
        """Analyze domain correction patterns."""
        cursor = conn.execute("""
            SELECT
                json_extract(original_value, '$') as original,
                json_extract(corrected_value, '$') as corrected,
                COUNT(*) as count
            FROM workflow_user_corrections
            WHERE correction_type = 'domain_correction'
              AND timestamp >= ?
            GROUP BY original, corrected
            HAVING count >= 2
            ORDER BY count DESC
            LIMIT 20
        """, (cutoff,))

        patterns = []
        for row in cursor.fetchall():
            try:
                original = json.loads(row['original']) if row['original'] else None
                corrected = json.loads(row['corrected']) if row['corrected'] else None
                patterns.append({
                    'original_domain': original,
                    'corrected_domain': corrected,
                    'count': row['count']
                })
            except:
                continue

        return patterns

    def _analyze_tool_patterns(
        self,
        conn: sqlite3.Connection,
        cutoff: str
    ) -> List[Dict]:
        """Analyze tool correction patterns."""
        cursor = conn.execute("""
            SELECT
                json_extract(original_value, '$') as original,
                json_extract(corrected_value, '$') as corrected,
                COUNT(*) as count
            FROM workflow_user_corrections
            WHERE correction_type = 'tool_correction'
              AND timestamp >= ?
            GROUP BY original, corrected
            HAVING count >= 2
            ORDER BY count DESC
            LIMIT 20
        """, (cutoff,))

        patterns = []
        for row in cursor.fetchall():
            try:
                original = json.loads(row['original']) if row['original'] else None
                corrected = json.loads(row['corrected']) if row['corrected'] else None
                patterns.append({
                    'original_tool': original,
                    'preferred_tool': corrected,
                    'count': row['count']
                })
            except:
                continue

        return patterns

    def _extract_batch_keywords(
        self,
        conn: sqlite3.Connection,
        domain: str,
        cutoff: str
    ) -> List[str]:
        """Extract common keywords from corrections for a domain."""
        cursor = conn.execute("""
            SELECT a.query_text
            FROM workflow_generation_audit a
            JOIN workflow_user_corrections c ON c.audit_id = a.audit_id
            WHERE c.correction_type = 'domain'
              AND c.corrected_value LIKE ?
              AND c.timestamp >= ?
            LIMIT 50
        """, (f'%{domain}%', cutoff))

        # Collect words from all queries
        word_counts = defaultdict(int)
        for row in cursor.fetchall():
            if row['query_text']:
                words = self._extract_domain_keywords(row['query_text'], domain)
                for word in words:
                    word_counts[word] += 1

        # Return words that appear multiple times
        return [word for word, count in word_counts.items() if count >= 2][:5]

    # ========================================================================
    # ANALYTICS
    # ========================================================================

    def get_learning_statistics(self, user_id: str = None) -> Dict[str, Any]:
        """
        Get statistics about learning activity.

        Args:
            user_id: Optional user ID to filter

        Returns:
            Learning statistics
        """
        try:
            conn = self._get_db()

            stats = {
                'corrections': {},
                'outcomes': {},
                'learned_keywords': 0
            }

            # Correction counts by type
            where_clause = "WHERE user_id = ?" if user_id else ""
            params = (user_id,) if user_id else ()

            cursor = conn.execute(f"""
                SELECT correction_type, COUNT(*) as count
                FROM workflow_user_corrections
                {where_clause}
                GROUP BY correction_type
            """, params)

            for row in cursor.fetchall():
                stats['corrections'][row['correction_type']] = row['count']

            # Success/failure outcomes
            cursor = conn.execute(f"""
                SELECT
                    SUM(CASE WHEN success = 1 THEN 1 ELSE 0 END) as successes,
                    SUM(CASE WHEN success = 0 THEN 1 ELSE 0 END) as failures
                FROM workflow_generation_audit
                {where_clause}
            """, params)

            row = cursor.fetchone()
            if row:
                stats['outcomes']['successes'] = row['successes'] or 0
                stats['outcomes']['failures'] = row['failures'] or 0

            # Learned keywords count
            cursor = conn.execute("SELECT COUNT(*) as count FROM learned_domain_keywords")
            row = cursor.fetchone()
            stats['learned_keywords'] = row['count'] if row else 0

            conn.close()
            return stats

        except Exception as e:
            log.error(f"Error getting learning statistics: {e}")
            return {}

    def get_learning_recommendations(self, user_id: str) -> List[Dict]:
        """
        Get recommendations based on learned patterns.

        Args:
            user_id: User ID

        Returns:
            List of recommendations
        """
        recommendations = []

        try:
            conn = self._get_db()

            # Check for repeated failures
            cursor = conn.execute("""
                SELECT primary_domain, COUNT(*) as failures
                FROM workflow_generation_audit
                WHERE user_id = ? AND success = 0
                GROUP BY primary_domain
                HAVING failures >= 3
            """, (user_id,))

            for row in cursor.fetchall():
                recommendations.append({
                    'type': 'domain_issue',
                    'domain': row['primary_domain'],
                    'message': f"Multiple failures in {row['primary_domain']} domain. "
                              f"Consider reviewing your queries or trying alternative approaches."
                })

            # Check for tool preferences
            cursor = conn.execute("""
                SELECT pattern_data, confidence
                FROM user_patterns
                WHERE user_id = ? AND pattern_type = 'tool_preference'
                ORDER BY confidence DESC
                LIMIT 3
            """, (user_id,))

            for row in cursor.fetchall():
                try:
                    data = json.loads(row['pattern_data'])
                    recommendations.append({
                        'type': 'tool_preference',
                        'preferred': data.get('prefers_tool'),
                        'over': data.get('over'),
                        'confidence': row['confidence']
                    })
                except:
                    continue

            conn.close()

        except Exception as e:
            log.error(f"Error getting recommendations: {e}")

        return recommendations
