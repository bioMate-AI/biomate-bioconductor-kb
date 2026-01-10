"""
Workflow Audit Service

Records all workflow generation attempts with full context for:
- Debugging failed generations
- Learning from patterns of success/failure
- User behavior analysis
- Performance monitoring
"""

import json
import logging
import sqlite3
import hashlib
import traceback
import uuid
from typing import Dict, List, Any, Optional
from dataclasses import dataclass, field, asdict
from datetime import datetime

log = logging.getLogger(__name__)


@dataclass
class AuditRecord:
    """Complete audit record for a workflow generation attempt."""
    audit_id: Optional[int] = None
    request_id: str = ""
    user_id: str = ""
    session_id: Optional[str] = None

    # Input
    query_text: str = ""
    query_hash: str = ""
    user_context: Optional[Dict] = None

    # Routing
    routing_decision: Optional[Dict] = None
    routing_method: str = ""
    routing_latency_ms: int = 0

    # Specialists
    domains_consulted: List[str] = field(default_factory=list)
    specialist_recommendations: Optional[Dict] = None
    specialist_latency_ms: int = 0

    # Assembly
    assembly_result: Optional[Dict] = None
    assembly_latency_ms: int = 0

    # Result
    success: bool = False
    workflow_id: Optional[str] = None
    workflow_steps_count: int = 0
    confidence: float = 0.0
    generation_source: str = ""

    # Errors
    error_type: Optional[str] = None
    error_message: Optional[str] = None
    error_traceback: Optional[str] = None

    # Performance
    total_latency_ms: int = 0
    llm_calls_count: int = 0
    llm_tokens_used: int = 0

    created_at: str = ""

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


class WorkflowAuditService:
    """
    Service for auditing workflow generation attempts.

    Records all generation attempts with full context for:
    - Debugging failed generations
    - Learning from patterns of success/failure
    - User behavior analysis
    - Performance monitoring
    """

    DEFAULT_DB_PATH = "/home/yzhang/biomate/backend/database/galaxy_ai_tools.db"

    def __init__(self, db_path: str = None):
        """
        Initialize audit service.

        Args:
            db_path: Path to SQLite database
        """
        self.db_path = db_path or self.DEFAULT_DB_PATH
        self._active_audits: Dict[str, AuditRecord] = {}

    def _get_db(self) -> sqlite3.Connection:
        """Get database connection with row factory."""
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn

    def _hash_query(self, query: str) -> str:
        """Create hash for query deduplication analysis."""
        normalized = query.lower().strip()
        return hashlib.md5(normalized.encode()).hexdigest()[:16]

    # ========================================================================
    # RECORDING METHODS
    # ========================================================================

    def start_audit(
        self,
        user_id: str,
        query: str,
        session_id: str = None,
        user_context: Dict = None
    ) -> str:
        """
        Start auditing a workflow generation attempt.

        Args:
            user_id: User identifier
            query: Original query text
            session_id: Optional session ID
            user_context: Optional user context at time of request

        Returns:
            request_id for tracking this audit
        """
        request_id = str(uuid.uuid4())

        record = AuditRecord(
            request_id=request_id,
            user_id=user_id or 'anonymous',
            session_id=session_id,
            query_text=query,
            query_hash=self._hash_query(query),
            user_context=user_context,
            created_at=datetime.now().isoformat()
        )

        self._active_audits[request_id] = record

        log.debug(f"Started audit {request_id} for user {user_id}")

        return request_id

    def record_routing(
        self,
        request_id: str,
        routing_decision: Any,
        routing_method: str,
        latency_ms: int
    ):
        """
        Record routing decision.

        Args:
            request_id: Audit request ID
            routing_decision: RoutingDecision object or dict
            routing_method: Method used ('keyword', 'llm', 'hybrid')
            latency_ms: Time taken for routing
        """
        if request_id not in self._active_audits:
            log.warning(f"Unknown audit request: {request_id}")
            return

        record = self._active_audits[request_id]

        # Convert routing decision to dict if needed
        if hasattr(routing_decision, '__dict__'):
            routing_dict = {
                'primary_domain': getattr(routing_decision, 'primary_domain', ''),
                'secondary_domains': getattr(routing_decision, 'secondary_domains', []),
                'confidence': getattr(routing_decision, 'confidence', 0.0),
                'complexity': getattr(routing_decision, 'complexity', 'standard'),
                'matched_keywords': getattr(routing_decision, 'matched_keywords', []),
                'routing_method': getattr(routing_decision, 'routing_method', routing_method)
            }
        else:
            routing_dict = routing_decision

        record.routing_decision = routing_dict
        record.routing_method = routing_method
        record.routing_latency_ms = latency_ms

        log.debug(f"Recorded routing for {request_id}: {routing_method} -> {routing_dict.get('primary_domain', 'unknown')}")

    def record_specialists(
        self,
        request_id: str,
        domains_consulted: List[str],
        recommendations: Dict[str, Any],
        latency_ms: int
    ):
        """
        Record specialist consultation results.

        Args:
            request_id: Audit request ID
            domains_consulted: List of domains that were consulted
            recommendations: Recommendations from each domain
            latency_ms: Time taken for specialist consultation
        """
        if request_id not in self._active_audits:
            log.warning(f"Unknown audit request: {request_id}")
            return

        record = self._active_audits[request_id]
        record.domains_consulted = domains_consulted
        record.specialist_recommendations = self._serialize_recommendations(recommendations)
        record.specialist_latency_ms = latency_ms

        log.debug(f"Recorded specialists for {request_id}: {domains_consulted}")

    def _serialize_recommendations(self, recommendations: Dict) -> Dict:
        """Serialize recommendations for storage."""
        result = {}
        for domain, rec in recommendations.items():
            if hasattr(rec, 'to_dict'):
                result[domain] = rec.to_dict() if hasattr(rec, 'to_dict') else str(rec)
            elif hasattr(rec, '__dict__'):
                result[domain] = {
                    'recommended_tools': [
                        {'tool_id': t.tool_id, 'tool_name': t.tool_name, 'confidence': t.confidence}
                        for t in getattr(rec, 'recommended_tools', [])
                    ],
                    'workflow_steps': [
                        {'step_number': s.step_number, 'tool_id': s.tool_id, 'description': s.description}
                        for s in getattr(rec, 'workflow_steps', [])
                    ],
                    'domain_notes': getattr(rec, 'domain_notes', ''),
                    'confidence': getattr(rec, 'confidence', 0.0)
                }
            else:
                result[domain] = rec
        return result

    def record_assembly(
        self,
        request_id: str,
        assembly_result: Any,
        latency_ms: int
    ):
        """
        Record workflow assembly result.

        Args:
            request_id: Audit request ID
            assembly_result: AssembledWorkflow object or dict
            latency_ms: Time taken for assembly
        """
        if request_id not in self._active_audits:
            log.warning(f"Unknown audit request: {request_id}")
            return

        record = self._active_audits[request_id]

        if hasattr(assembly_result, '__dict__'):
            record.assembly_result = {
                'workflow_steps_count': len(getattr(assembly_result, 'workflow_steps', [])),
                'confidence': getattr(assembly_result, 'confidence', 0.0),
                'domain_sources': getattr(assembly_result, 'domain_sources', []),
                'validation': getattr(assembly_result, 'validation', None)
            }
        else:
            record.assembly_result = assembly_result

        record.assembly_latency_ms = latency_ms

    def complete_audit(
        self,
        request_id: str,
        success: bool,
        workflow_id: str = None,
        workflow_steps_count: int = 0,
        confidence: float = 0.0,
        generation_source: str = None,
        error_type: str = None,
        error_message: str = None,
        total_latency_ms: int = 0,
        llm_calls_count: int = 0,
        assembly_result: Any = None
    ) -> Optional[int]:
        """
        Complete the audit record and persist to database.

        Args:
            request_id: Audit request ID
            success: Whether generation succeeded
            workflow_id: Generated workflow ID if successful
            workflow_steps_count: Number of steps in workflow
            confidence: Overall confidence score
            generation_source: Source of generation
            error_type: Error type if failed
            error_message: Error message if failed
            total_latency_ms: Total time taken
            llm_calls_count: Number of LLM calls made
            assembly_result: Optional assembled workflow result

        Returns:
            audit_id if successful, None otherwise
        """
        if request_id not in self._active_audits:
            log.warning(f"Unknown audit request: {request_id}")
            return None

        record = self._active_audits[request_id]
        record.success = success
        record.workflow_id = workflow_id
        record.workflow_steps_count = workflow_steps_count
        record.confidence = confidence
        record.generation_source = generation_source or ''
        record.error_type = error_type
        record.error_message = error_message
        record.total_latency_ms = total_latency_ms
        record.llm_calls_count = llm_calls_count

        # Record assembly result if provided
        if assembly_result:
            self.record_assembly(request_id, assembly_result, 0)

        if error_message:
            record.error_traceback = traceback.format_exc()

        # Persist to database and get audit_id
        audit_id = self._persist_audit(record)

        # Remove from active audits
        del self._active_audits[request_id]

        status = "SUCCESS" if success else f"FAILED ({error_type})"
        log.info(f"Completed audit {request_id}: {status} in {total_latency_ms}ms")

        return audit_id

    def _persist_audit(self, record: AuditRecord) -> Optional[int]:
        """
        Persist audit record to database.

        Returns:
            audit_id if successful, None otherwise
        """
        try:
            conn = self._get_db()

            # Extract primary_domain from routing_decision
            primary_domain = None
            if record.routing_decision:
                primary_domain = record.routing_decision.get('primary_domain')

            cursor = conn.execute("""
                INSERT INTO workflow_generation_audit (
                    request_id, user_id, session_id,
                    query_text, query_hash, user_context,
                    routing_decision, routing_method, routing_latency_ms,
                    primary_domain,
                    domains_consulted, specialist_recommendations, specialist_latency_ms,
                    assembly_result, assembly_latency_ms,
                    success, workflow_id, workflow_steps_count, confidence, generation_source,
                    error_type, error_message, error_traceback,
                    total_latency_ms, llm_calls_count, llm_tokens_used,
                    created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                record.request_id,
                record.user_id,
                record.session_id,
                record.query_text,
                record.query_hash,
                json.dumps(record.user_context) if record.user_context else None,
                json.dumps(record.routing_decision) if record.routing_decision else None,
                record.routing_method,
                record.routing_latency_ms,
                primary_domain,
                json.dumps(record.domains_consulted) if record.domains_consulted else None,
                json.dumps(record.specialist_recommendations) if record.specialist_recommendations else None,
                record.specialist_latency_ms,
                json.dumps(record.assembly_result) if record.assembly_result else None,
                record.assembly_latency_ms,
                1 if record.success else 0,
                record.workflow_id,
                record.workflow_steps_count,
                record.confidence,
                record.generation_source,
                record.error_type,
                record.error_message,
                record.error_traceback,
                record.total_latency_ms,
                record.llm_calls_count,
                record.llm_tokens_used,
                record.created_at
            ))

            audit_id = cursor.lastrowid
            conn.commit()
            conn.close()

            return audit_id

        except Exception as e:
            log.error(f"Failed to persist audit record: {e}")
            return None

    # ========================================================================
    # CORRECTION RECORDING
    # ========================================================================

    def record_correction(
        self,
        request_id: str,
        user_id: str,
        correction_type: str,
        original_value: Any,
        corrected_value: Any,
        reason: str = None
    ) -> Optional[int]:
        """
        Record a user correction to a generated workflow.

        Args:
            request_id: Original request ID (maps to audit_id)
            user_id: User who made correction
            correction_type: Type of correction ('domain', 'tool_selection', 'parameters')
            original_value: What was originally generated
            corrected_value: What user changed to
            reason: Optional explanation

        Returns:
            correction_id if successful
        """
        try:
            conn = self._get_db()

            # Get audit_id from request_id
            cursor = conn.execute(
                "SELECT audit_id FROM workflow_generation_audit WHERE request_id = ?",
                (request_id,)
            )
            row = cursor.fetchone()

            if not row:
                log.warning(f"No audit record found for request_id: {request_id}")
                conn.close()
                return None

            audit_id = row['audit_id']

            cursor = conn.execute("""
                INSERT INTO workflow_user_corrections (
                    audit_id, user_id, correction_type,
                    original_value, corrected_value, correction_reason,
                    timestamp
                ) VALUES (?, ?, ?, ?, ?, ?, datetime('now'))
            """, (
                audit_id,
                user_id,
                correction_type,
                json.dumps(original_value) if not isinstance(original_value, str) else original_value,
                json.dumps(corrected_value) if not isinstance(corrected_value, str) else corrected_value,
                reason
            ))

            correction_id = cursor.lastrowid
            conn.commit()
            conn.close()

            log.info(f"Recorded correction {correction_id} for audit {audit_id}: {correction_type}")

            return correction_id

        except Exception as e:
            log.error(f"Failed to record correction: {e}")
            return None

    # ========================================================================
    # QUERY METHODS
    # ========================================================================

    def get_audit_by_request_id(self, request_id: str) -> Optional[Dict[str, Any]]:
        """Get audit record by request ID."""
        try:
            conn = self._get_db()
            cursor = conn.execute(
                "SELECT * FROM workflow_generation_audit WHERE request_id = ?",
                (request_id,)
            )
            row = cursor.fetchone()
            conn.close()

            if row:
                return self._row_to_dict(row)
            return None

        except Exception as e:
            log.error(f"Error getting audit: {e}")
            return None

    def _row_to_dict(self, row: sqlite3.Row) -> Dict[str, Any]:
        """Convert row to dict and parse JSON fields."""
        result = dict(row)
        json_fields = [
            'user_context', 'routing_decision', 'domains_consulted',
            'specialist_recommendations', 'assembly_result'
        ]
        for field in json_fields:
            if field in result and result[field]:
                try:
                    result[field] = json.loads(result[field])
                except (json.JSONDecodeError, TypeError):
                    pass
        return result

    def get_user_audit_history(
        self,
        user_id: str,
        limit: int = 50,
        success_only: bool = False
    ) -> List[Dict[str, Any]]:
        """
        Get audit history for a specific user.

        Args:
            user_id: User identifier
            limit: Maximum records to return
            success_only: Only return successful generations

        Returns:
            List of audit records
        """
        try:
            conn = self._get_db()

            query = """
                SELECT audit_id, request_id, query_text, routing_method,
                       success, workflow_steps_count, confidence, generation_source,
                       error_type, total_latency_ms, created_at
                FROM workflow_generation_audit
                WHERE user_id = ?
            """

            if success_only:
                query += " AND success = 1"

            query += " ORDER BY created_at DESC LIMIT ?"

            cursor = conn.execute(query, (user_id, limit))
            results = [dict(row) for row in cursor.fetchall()]
            conn.close()

            return results

        except Exception as e:
            log.error(f"Error getting user audit history: {e}")
            return []

    def get_failure_patterns(
        self,
        limit: int = 100,
        error_type: str = None,
        days_back: int = 30
    ) -> List[Dict[str, Any]]:
        """
        Analyze common failure patterns.

        Args:
            limit: Maximum records to analyze
            error_type: Filter by specific error type
            days_back: How many days to look back

        Returns:
            List of failure patterns with counts
        """
        try:
            conn = self._get_db()

            query = """
                SELECT error_type, error_message, COUNT(*) as count,
                       AVG(total_latency_ms) as avg_latency
                FROM workflow_generation_audit
                WHERE success = 0
                  AND created_at >= datetime('now', ?)
            """
            params = [f'-{days_back} days']

            if error_type:
                query += " AND error_type = ?"
                params.append(error_type)

            query += " GROUP BY error_type, error_message ORDER BY count DESC LIMIT ?"
            params.append(limit)

            cursor = conn.execute(query, params)
            results = [dict(row) for row in cursor.fetchall()]
            conn.close()

            return results

        except Exception as e:
            log.error(f"Error getting failure patterns: {e}")
            return []

    def get_audit_statistics(
        self,
        user_id: Optional[str] = None,
        days_back: int = 30
    ) -> Dict[str, Any]:
        """
        Get overall audit statistics.

        Args:
            user_id: Optional user ID to filter by
            days_back: How many days to analyze

        Returns:
            Dict with statistics
        """
        try:
            conn = self._get_db()

            if user_id:
                cursor = conn.execute("""
                    SELECT
                        COUNT(*) as total_attempts,
                        SUM(CASE WHEN success = 1 THEN 1 ELSE 0 END) as successful,
                        SUM(CASE WHEN success = 0 THEN 1 ELSE 0 END) as failed,
                        AVG(total_latency_ms) as avg_latency_ms,
                        AVG(CASE WHEN success = 1 THEN confidence ELSE NULL END) as avg_confidence,
                        AVG(llm_calls_count) as avg_llm_calls
                    FROM workflow_generation_audit
                    WHERE user_id = ? AND created_at >= datetime('now', ?)
                """, (user_id, f'-{days_back} days'))
            else:
                cursor = conn.execute("""
                    SELECT
                        COUNT(*) as total_attempts,
                        SUM(CASE WHEN success = 1 THEN 1 ELSE 0 END) as successful,
                        SUM(CASE WHEN success = 0 THEN 1 ELSE 0 END) as failed,
                        AVG(total_latency_ms) as avg_latency_ms,
                        AVG(CASE WHEN success = 1 THEN confidence ELSE NULL END) as avg_confidence,
                        AVG(llm_calls_count) as avg_llm_calls
                    FROM workflow_generation_audit
                    WHERE created_at >= datetime('now', ?)
                """, (f'-{days_back} days',))

            row = cursor.fetchone()
            conn.close()

            if row:
                stats = dict(row)
                total = stats['total_attempts'] or 1
                stats['success_rate'] = (stats['successful'] or 0) / total
                return stats

            return {}

        except Exception as e:
            log.error(f"Error getting audit statistics: {e}")
            return {}

    def get_corrections_for_learning(
        self,
        limit: int = 100,
        days_back: int = 7
    ) -> List[Dict[str, Any]]:
        """
        Get corrections for learning analysis.

        Args:
            limit: Maximum corrections to return
            days_back: How many days to look back

        Returns:
            List of corrections with audit context
        """
        try:
            conn = self._get_db()

            cursor = conn.execute("""
                SELECT c.*, a.query_text, a.routing_decision
                FROM workflow_user_corrections c
                JOIN workflow_generation_audit a ON c.audit_id = a.audit_id
                WHERE c.timestamp >= datetime('now', ?)
                ORDER BY c.timestamp DESC
                LIMIT ?
            """, (f'-{days_back} days', limit))

            results = []
            for row in cursor.fetchall():
                record = dict(row)
                # Parse JSON fields
                for field in ['original_value', 'corrected_value', 'routing_decision']:
                    if field in record and record[field]:
                        try:
                            record[field] = json.loads(record[field])
                        except (json.JSONDecodeError, TypeError):
                            pass
                results.append(record)

            conn.close()
            return results

        except Exception as e:
            log.error(f"Error getting corrections: {e}")
            return []
