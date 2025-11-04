"""
API operations for user behavioral patterns and insights.

Provides access to Phase A behavioral user profile data:
- User interaction history (searches, tool selections, file uploads)
- Inferred behavioral patterns (domain preferences, tool preferences)
- Data type detection history
- Context inference logs

This API bridges the behavioral data from Phase A with the TypeScript frontend.
"""

import json
import logging
import sqlite3
from datetime import datetime
from typing import Dict, List, Any, Optional

from fastapi import (
    Query,
    Path,
)
from pydantic import BaseModel, Field

from galaxy.managers.context import ProvidesUserContext
from galaxy.model import User
from . import (
    Router,
    DependsOnTrans,
    DependsOnUser,
)

log = logging.getLogger(__name__)

router = Router(tags=["user_patterns"])


# ============================================================================
# REQUEST/RESPONSE MODELS
# ============================================================================

class UserPattern(BaseModel):
    """User behavioral pattern"""
    pattern_id: int
    user_id: int
    pattern_type: str  # 'domain_preference', 'tool_preference', 'complexity_level', 'data_type_pattern'
    pattern_data: Dict[str, Any]
    confidence: float
    evidence_count: int
    first_observed: str
    last_observed: str
    last_updated: str


class UserInteraction(BaseModel):
    """User interaction record"""
    interaction_id: int
    user_id: int
    interaction_type: str
    query: Optional[str] = None
    detected_context: Optional[Dict[str, Any]] = None
    selected_tool_id: Optional[str] = None
    selected_rank: Optional[int] = None
    file_name: Optional[str] = None
    file_extension: Optional[str] = None
    file_metadata: Optional[Dict[str, Any]] = None
    workflow_id: Optional[str] = None
    workflow_success: Optional[int] = None
    user_clicked: int = 0
    user_kept: Optional[int] = None
    user_feedback_rating: Optional[int] = None
    user_feedback_comment: Optional[str] = None
    timestamp: str


class DataTypeDetection(BaseModel):
    """Data type detection record"""
    detection_id: int
    user_id: int
    file_name: Optional[str] = None
    file_extension: Optional[str] = None
    file_metadata: Optional[Dict[str, Any]] = None
    detected_type: Optional[str] = None
    detection_confidence: Optional[float] = None
    detection_method: Optional[str] = None
    user_confirmed_type: Optional[str] = None
    was_correct: Optional[int] = None
    timestamp: str


class ContextInference(BaseModel):
    """Context inference record"""
    inference_id: int
    user_id: int
    interaction_id: Optional[int] = None
    query_text: Optional[str] = None
    uploaded_file_info: Optional[Dict[str, Any]] = None
    user_history_summary: Optional[Dict[str, Any]] = None
    inferred_domain: Optional[str] = None
    inferred_data_type: Optional[str] = None
    inferred_complexity_need: Optional[str] = None
    domain_confidence: Optional[float] = None
    data_type_confidence: Optional[float] = None
    complexity_confidence: Optional[float] = None
    inference_method: Optional[str] = None
    inference_details: Optional[Dict[str, Any]] = None
    user_accepted: Optional[int] = None
    timestamp: str


class UserInsightsResponse(BaseModel):
    """Aggregated user insights"""
    user_id: int
    patterns: List[UserPattern]
    recent_interactions: List[UserInteraction]
    total_interactions: int
    dominant_domain: Optional[str] = None
    dominant_domain_confidence: Optional[float] = None
    preferred_tools: List[Dict[str, Any]] = []
    data_type_accuracy: Optional[float] = None
    timestamp: str


# ============================================================================
# USER PATTERNS SERVICE
# ============================================================================

class UserPatternsService:
    """Service for accessing user behavioral patterns"""

    def __init__(self, db_path: str = "/home/yzhang/biomate/backend/database/galaxy_ai_tools.db"):
        self.db_path = db_path

    def _get_db(self) -> sqlite3.Connection:
        """Get database connection"""
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn

    def _row_to_dict(self, row: sqlite3.Row) -> Dict[str, Any]:
        """Convert Row to dict and parse JSON fields"""
        result = dict(row)
        # Parse JSON fields
        json_fields = [
            'pattern_data', 'detected_context', 'file_metadata',
            'uploaded_file_info', 'user_history_summary', 'inference_details'
        ]
        for key in json_fields:
            if key in result and result[key]:
                try:
                    result[key] = json.loads(result[key])
                except (json.JSONDecodeError, TypeError):
                    pass
        return result

    # ========================================================================
    # USER PATTERNS
    # ========================================================================

    def get_user_patterns(
        self,
        user_id: int,
        pattern_type: Optional[str] = None,
        min_confidence: float = 0.0,
        limit: int = 100
    ) -> List[Dict[str, Any]]:
        """Get user's behavioral patterns"""
        conn = self._get_db()
        try:
            query = """
                SELECT pattern_id, user_id, pattern_type, pattern_data,
                       confidence, evidence_count, first_observed,
                       last_observed, last_updated
                FROM user_patterns
                WHERE user_id = ? AND confidence >= ?
            """
            params = [user_id, min_confidence]

            if pattern_type:
                query += " AND pattern_type = ?"
                params.append(pattern_type)

            query += " ORDER BY confidence DESC, last_observed DESC LIMIT ?"
            params.append(limit)

            cursor = conn.execute(query, params)
            return [self._row_to_dict(row) for row in cursor.fetchall()]
        finally:
            conn.close()

    def get_pattern_by_id(self, pattern_id: int) -> Optional[Dict[str, Any]]:
        """Get specific pattern by ID"""
        conn = self._get_db()
        try:
            cursor = conn.execute("""
                SELECT pattern_id, user_id, pattern_type, pattern_data,
                       confidence, evidence_count, first_observed,
                       last_observed, last_updated
                FROM user_patterns
                WHERE pattern_id = ?
            """, (pattern_id,))
            row = cursor.fetchone()
            return self._row_to_dict(row) if row else None
        finally:
            conn.close()

    # ========================================================================
    # USER INTERACTIONS
    # ========================================================================

    def get_user_interactions(
        self,
        user_id: int,
        interaction_type: Optional[str] = None,
        limit: int = 100
    ) -> List[Dict[str, Any]]:
        """Get user's interaction history"""
        conn = self._get_db()
        try:
            query = """
                SELECT interaction_id, user_id, interaction_type, query,
                       detected_context, selected_tool_id, selected_rank,
                       file_name, file_extension, file_metadata,
                       workflow_id, workflow_success, user_clicked, user_kept,
                       user_feedback_rating, user_feedback_comment, timestamp
                FROM user_interactions
                WHERE user_id = ?
            """
            params = [user_id]

            if interaction_type:
                query += " AND interaction_type = ?"
                params.append(interaction_type)

            query += " ORDER BY timestamp DESC LIMIT ?"
            params.append(limit)

            cursor = conn.execute(query, params)
            return [self._row_to_dict(row) for row in cursor.fetchall()]
        finally:
            conn.close()

    def get_interaction_stats(self, user_id: int) -> Dict[str, Any]:
        """Get user interaction statistics"""
        conn = self._get_db()
        try:
            cursor = conn.execute("""
                SELECT
                    COUNT(*) as total_interactions,
                    COUNT(DISTINCT interaction_type) as interaction_types,
                    SUM(CASE WHEN user_clicked = 1 THEN 1 ELSE 0 END) as total_clicks,
                    SUM(CASE WHEN user_kept = 1 THEN 1 ELSE 0 END) as kept_selections,
                    AVG(CASE WHEN user_feedback_rating IS NOT NULL THEN user_feedback_rating ELSE NULL END) as avg_rating
                FROM user_interactions
                WHERE user_id = ?
            """, (user_id,))

            row = cursor.fetchone()
            return dict(row) if row else {}
        finally:
            conn.close()

    # ========================================================================
    # DATA TYPE DETECTIONS
    # ========================================================================

    def get_data_type_detections(
        self,
        user_id: int,
        limit: int = 100
    ) -> List[Dict[str, Any]]:
        """Get user's data type detection history"""
        conn = self._get_db()
        try:
            cursor = conn.execute("""
                SELECT detection_id, user_id, file_name, file_extension,
                       file_metadata, detected_type, detection_confidence,
                       detection_method, user_confirmed_type, was_correct,
                       timestamp
                FROM data_type_detections
                WHERE user_id = ?
                ORDER BY timestamp DESC
                LIMIT ?
            """, (user_id, limit))

            return [self._row_to_dict(row) for row in cursor.fetchall()]
        finally:
            conn.close()

    def get_detection_accuracy(self, user_id: int) -> Optional[float]:
        """Get user's data type detection accuracy"""
        conn = self._get_db()
        try:
            cursor = conn.execute("""
                SELECT
                    SUM(CASE WHEN was_correct = 1 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) as accuracy
                FROM data_type_detections
                WHERE user_id = ? AND was_correct IS NOT NULL
            """, (user_id,))

            row = cursor.fetchone()
            return row['accuracy'] if row and row['accuracy'] is not None else None
        finally:
            conn.close()

    # ========================================================================
    # CONTEXT INFERENCES
    # ========================================================================

    def get_context_inferences(
        self,
        user_id: int,
        limit: int = 100
    ) -> List[Dict[str, Any]]:
        """Get user's context inference history"""
        conn = self._get_db()
        try:
            cursor = conn.execute("""
                SELECT inference_id, user_id, interaction_id, query_text,
                       uploaded_file_info, user_history_summary,
                       inferred_domain, inferred_data_type, inferred_complexity_need,
                       domain_confidence, data_type_confidence, complexity_confidence,
                       inference_method, inference_details, user_accepted,
                       timestamp
                FROM context_inferences
                WHERE user_id = ?
                ORDER BY timestamp DESC
                LIMIT ?
            """, (user_id, limit))

            return [self._row_to_dict(row) for row in cursor.fetchall()]
        finally:
            conn.close()

    # ========================================================================
    # AGGREGATED INSIGHTS
    # ========================================================================

    def get_user_insights(self, user_id: int) -> Dict[str, Any]:
        """Get aggregated user insights"""
        patterns = self.get_user_patterns(user_id, limit=50)
        interactions = self.get_user_interactions(user_id, limit=20)
        stats = self.get_interaction_stats(user_id)
        accuracy = self.get_detection_accuracy(user_id)

        # Find dominant domain
        domain_pattern = next(
            (p for p in patterns if p['pattern_type'] == 'domain_preference'),
            None
        )

        # Extract preferred tools
        tool_patterns = [
            p for p in patterns if p['pattern_type'] == 'tool_preference'
        ]

        return {
            'user_id': user_id,
            'patterns': patterns,
            'recent_interactions': interactions,
            'total_interactions': stats.get('total_interactions', 0),
            'dominant_domain': (
                domain_pattern['pattern_data'].get('domain')
                if domain_pattern else None
            ),
            'dominant_domain_confidence': (
                domain_pattern['confidence']
                if domain_pattern else None
            ),
            'preferred_tools': [
                {
                    'tool_id': p['pattern_data'].get('prefers_tool'),
                    'for_task': p['pattern_data'].get('for_task'),
                    'confidence': p['confidence']
                }
                for p in tool_patterns
            ],
            'data_type_accuracy': accuracy,
            'timestamp': datetime.utcnow().isoformat()
        }


# ============================================================================
# API ENDPOINTS
# ============================================================================

# Initialize service
service = UserPatternsService()


@router.cbv
class UserPatternsAPI:
    """API for accessing user behavioral patterns"""

    @router.get("/api/user-patterns/patterns")
    def get_patterns(
        self,
        pattern_type: Optional[str] = Query(None, description="Filter by pattern type"),
        min_confidence: float = Query(0.0, description="Minimum confidence threshold"),
        limit: int = Query(100, description="Maximum number of patterns to return"),
        trans: ProvidesUserContext = DependsOnTrans,
        user: User = DependsOnUser,
    ) -> List[UserPattern]:
        """Get user's behavioral patterns"""
        patterns = service.get_user_patterns(
            user_id=user.id,
            pattern_type=pattern_type,
            min_confidence=min_confidence,
            limit=limit
        )
        return [UserPattern(**p) for p in patterns]

    @router.get("/api/user-patterns/patterns/{pattern_id}")
    def get_pattern(
        self,
        pattern_id: int = Path(..., description="Pattern ID"),
        trans: ProvidesUserContext = DependsOnTrans,
        user: User = DependsOnUser,
    ) -> UserPattern:
        """Get specific pattern by ID"""
        pattern = service.get_pattern_by_id(pattern_id)
        if not pattern:
            raise Exception(f"Pattern {pattern_id} not found")

        # Verify ownership
        if pattern['user_id'] != user.id:
            raise Exception("Access denied")

        return UserPattern(**pattern)

    @router.get("/api/user-patterns/interactions")
    def get_interactions(
        self,
        interaction_type: Optional[str] = Query(None, description="Filter by interaction type"),
        limit: int = Query(100, description="Maximum number of interactions to return"),
        trans: ProvidesUserContext = DependsOnTrans,
        user: User = DependsOnUser,
    ) -> List[UserInteraction]:
        """Get user's interaction history"""
        interactions = service.get_user_interactions(
            user_id=user.id,
            interaction_type=interaction_type,
            limit=limit
        )
        return [UserInteraction(**i) for i in interactions]

    @router.get("/api/user-patterns/interactions/stats")
    def get_interaction_statistics(
        self,
        trans: ProvidesUserContext = DependsOnTrans,
        user: User = DependsOnUser,
    ) -> Dict[str, Any]:
        """Get user interaction statistics"""
        return service.get_interaction_stats(user.id)

    @router.get("/api/user-patterns/detections")
    def get_detections(
        self,
        limit: int = Query(100, description="Maximum number of detections to return"),
        trans: ProvidesUserContext = DependsOnTrans,
        user: User = DependsOnUser,
    ) -> List[DataTypeDetection]:
        """Get user's data type detection history"""
        detections = service.get_data_type_detections(
            user_id=user.id,
            limit=limit
        )
        return [DataTypeDetection(**d) for d in detections]

    @router.get("/api/user-patterns/detections/accuracy")
    def get_detection_accuracy(
        self,
        trans: ProvidesUserContext = DependsOnTrans,
        user: User = DependsOnUser,
    ) -> Dict[str, Any]:
        """Get user's data type detection accuracy"""
        accuracy = service.get_detection_accuracy(user.id)
        return {
            "user_id": user.id,
            "accuracy": accuracy,
            "timestamp": datetime.utcnow().isoformat()
        }

    @router.get("/api/user-patterns/context-inferences")
    def get_context_inferences(
        self,
        limit: int = Query(100, description="Maximum number of inferences to return"),
        trans: ProvidesUserContext = DependsOnTrans,
        user: User = DependsOnUser,
    ) -> List[ContextInference]:
        """Get user's context inference history"""
        inferences = service.get_context_inferences(
            user_id=user.id,
            limit=limit
        )
        return [ContextInference(**i) for i in inferences]

    @router.get("/api/user-patterns/insights")
    def get_insights(
        self,
        trans: ProvidesUserContext = DependsOnTrans,
        user: User = DependsOnUser,
    ) -> UserInsightsResponse:
        """Get aggregated user insights and behavioral patterns"""
        insights = service.get_user_insights(user.id)
        return UserInsightsResponse(**insights)
