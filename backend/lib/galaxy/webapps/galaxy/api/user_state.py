"""
API operations for user state persistence and synchronization.

Handles syncing user state across devices including:
- Workflow drafts and editor state
- AI conversation history
- Favorites (tools and datasets)
- Tool/dataset usage history
- UI preferences and layout
"""

import json
import logging
import sqlite3
from datetime import datetime
from typing import Dict, List, Any, Optional

from fastapi import (
    Body,
    HTTPException,
    Path,
    Query,
    status,
)
from pydantic import BaseModel, Field

from galaxy.exceptions import (
    ActionInputError,
    ObjectNotFound,
)
from . import (
    depends,
    Router,
)

log = logging.getLogger(__name__)

router = Router(tags=["user_state"])


# ============================================================================
# REQUEST/RESPONSE MODELS
# ============================================================================

class WorkflowStateUpdate(BaseModel):
    """Workflow state update"""
    workflow_uuid: str = Field(..., description="Workflow UUID")
    workflow_name: Optional[str] = None
    workflow_data: Dict[str, Any] = Field(..., description="Workflow definition JSON")
    editor_state: Optional[Dict[str, Any]] = Field(None, description="Editor state (zoom, position)")
    status: str = Field("draft", description="Workflow status")
    is_favorite: bool = Field(False)


class AIConversationUpdate(BaseModel):
    """AI conversation update"""
    session_id: str = Field(..., description="Conversation session ID")
    title: Optional[str] = None
    context_type: Optional[str] = Field(None, description="Conversation context type")
    messages: List[Dict[str, Any]] = Field([], description="New messages to add")


class FavoriteUpdate(BaseModel):
    """Favorite item update"""
    item_id: str = Field(..., description="Tool or dataset ID")
    item_type: str = Field(..., description="'tool' or 'dataset'")
    is_favorite: bool = Field(..., description="Add or remove favorite")
    notes: Optional[str] = None
    tags: Optional[List[str]] = None


class UsageUpdate(BaseModel):
    """Usage tracking update"""
    item_id: str = Field(..., description="Tool or dataset ID")
    item_type: str = Field(..., description="'tool' or 'dataset'")
    context_workflow_id: Optional[str] = None
    context_dataset_id: Optional[str] = None
    execution_time_seconds: Optional[float] = None
    success: bool = Field(True)


class BatchStateUpdate(BaseModel):
    """Batch state update request"""
    workflows: Optional[List[WorkflowStateUpdate]] = None
    ai_conversations: Optional[List[AIConversationUpdate]] = None
    favorites: Optional[List[FavoriteUpdate]] = None
    usage: Optional[List[UsageUpdate]] = None


class StateResponse(BaseModel):
    """State response"""
    success: bool
    message: str
    timestamp: str


class UserStateResponse(BaseModel):
    """Complete user state response"""
    workflows: List[Dict[str, Any]]
    ai_conversations: List[Dict[str, Any]]
    tool_favorites: List[Dict[str, Any]]
    dataset_favorites: List[Dict[str, Any]]
    tool_usage: List[Dict[str, Any]]
    dataset_usage: List[Dict[str, Any]]
    timestamp: str


# ============================================================================
# USER STATE SERVICE
# ============================================================================

class UserStateService:
    """Service for managing user state persistence"""

    def __init__(self, db_path: str = "galaxy_ai_tools.db"):
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
        for key in ['workflow_data', 'editor_state', 'inputs', 'outputs',
                    'parameters', 'message_data', 'tags', 'usage_context']:
            if key in result and result[key]:
                try:
                    result[key] = json.loads(result[key])
                except (json.JSONDecodeError, TypeError):
                    pass
        return result

    # ========================================================================
    # WORKFLOW STATE
    # ========================================================================

    def get_user_workflows(self, user_id: int, limit: int = 100) -> List[Dict[str, Any]]:
        """Get user's workflow states"""
        conn = self._get_db()
        try:
            cursor = conn.execute("""
                SELECT id, user_id, workflow_id, workflow_uuid, workflow_name,
                       workflow_data, status, editor_state, is_favorite,
                       last_opened_at, last_saved_at, created_at, updated_at
                FROM user_workflow_state
                WHERE user_id = ?
                ORDER BY last_opened_at DESC
                LIMIT ?
            """, (user_id, limit))

            return [self._row_to_dict(row) for row in cursor.fetchall()]
        finally:
            conn.close()

    def update_workflow_state(
        self,
        user_id: int,
        workflow_uuid: str,
        workflow_data: Dict[str, Any],
        workflow_name: str = None,
        editor_state: Dict[str, Any] = None,
        status: str = "draft",
        is_favorite: bool = False
    ) -> Dict[str, Any]:
        """Update or create workflow state"""
        conn = self._get_db()
        try:
            now = datetime.utcnow().isoformat()

            # Check if workflow exists
            existing = conn.execute("""
                SELECT id FROM user_workflow_state
                WHERE user_id = ? AND workflow_uuid = ?
            """, (user_id, workflow_uuid)).fetchone()

            if existing:
                # Update existing
                conn.execute("""
                    UPDATE user_workflow_state
                    SET workflow_name = COALESCE(?, workflow_name),
                        workflow_data = ?,
                        editor_state = COALESCE(?, editor_state),
                        status = ?,
                        is_favorite = ?,
                        last_opened_at = ?,
                        last_saved_at = ?
                    WHERE id = ?
                """, (
                    workflow_name,
                    json.dumps(workflow_data),
                    json.dumps(editor_state) if editor_state else None,
                    status,
                    1 if is_favorite else 0,
                    now,
                    now,
                    existing['id']
                ))
                workflow_id = existing['id']
            else:
                # Insert new
                cursor = conn.execute("""
                    INSERT INTO user_workflow_state (
                        user_id, workflow_uuid, workflow_name, workflow_data,
                        editor_state, status, is_favorite, last_opened_at,
                        last_saved_at, created_at, updated_at
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, (
                    user_id, workflow_uuid, workflow_name,
                    json.dumps(workflow_data),
                    json.dumps(editor_state) if editor_state else None,
                    status,
                    1 if is_favorite else 0,
                    now, now, now, now
                ))
                workflow_id = cursor.lastrowid

            conn.commit()

            return {
                'id': workflow_id,
                'workflow_uuid': workflow_uuid,
                'updated_at': now
            }

        finally:
            conn.close()

    # ========================================================================
    # AI CONVERSATIONS
    # ========================================================================

    def get_user_ai_conversations(
        self,
        user_id: int,
        include_archived: bool = False,
        limit: int = 50
    ) -> List[Dict[str, Any]]:
        """Get user's AI conversations"""
        conn = self._get_db()
        try:
            query = """
                SELECT id, user_id, session_id, title, context_type, context_id,
                       created_at, last_message_at, is_archived
                FROM user_ai_conversations
                WHERE user_id = ?
            """
            params = [user_id]

            if not include_archived:
                query += " AND is_archived = 0"

            query += " ORDER BY last_message_at DESC LIMIT ?"
            params.append(limit)

            cursor = conn.execute(query, params)
            conversations = [self._row_to_dict(row) for row in cursor.fetchall()]

            # Get messages for each conversation
            for conv in conversations:
                messages = conn.execute("""
                    SELECT id, conversation_id, message_type, message_text,
                           message_data, timestamp, read_status
                    FROM user_ai_messages
                    WHERE conversation_id = ?
                    ORDER BY timestamp ASC
                """, (conv['id'],)).fetchall()
                conv['messages'] = [self._row_to_dict(msg) for msg in messages]

            return conversations

        finally:
            conn.close()

    def update_ai_conversation(
        self,
        user_id: int,
        session_id: str,
        title: str = None,
        context_type: str = None,
        messages: List[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """Update or create AI conversation"""
        conn = self._get_db()
        try:
            now = datetime.utcnow().isoformat()

            # Check if conversation exists
            existing = conn.execute("""
                SELECT id FROM user_ai_conversations
                WHERE user_id = ? AND session_id = ?
            """, (user_id, session_id)).fetchone()

            if existing:
                # Update existing
                conn.execute("""
                    UPDATE user_ai_conversations
                    SET title = COALESCE(?, title),
                        context_type = COALESCE(?, context_type),
                        last_message_at = ?
                    WHERE id = ?
                """, (title, context_type, now, existing['id']))
                conversation_id = existing['id']
            else:
                # Insert new
                cursor = conn.execute("""
                    INSERT INTO user_ai_conversations (
                        user_id, session_id, title, context_type,
                        created_at, last_message_at, is_archived
                    )
                    VALUES (?, ?, ?, ?, ?, ?, 0)
                """, (user_id, session_id, title, context_type, now, now))
                conversation_id = cursor.lastrowid

            # Add new messages
            if messages:
                for msg in messages:
                    conn.execute("""
                        INSERT INTO user_ai_messages (
                            conversation_id, message_type, message_text,
                            message_data, timestamp, read_status
                        )
                        VALUES (?, ?, ?, ?, ?, ?)
                    """, (
                        conversation_id,
                        msg.get('message_type', 'user'),
                        msg.get('message_text', ''),
                        json.dumps(msg.get('message_data', {})),
                        msg.get('timestamp', now),
                        msg.get('read_status', 0)
                    ))

            conn.commit()

            return {
                'id': conversation_id,
                'session_id': session_id,
                'updated_at': now
            }

        finally:
            conn.close()

    # ========================================================================
    # FAVORITES
    # ========================================================================

    def get_user_favorites(self, user_id: int) -> Dict[str, List[Dict[str, Any]]]:
        """Get user's favorites (tools and datasets)"""
        conn = self._get_db()
        try:
            # Tool favorites
            tool_cursor = conn.execute("""
                SELECT id, user_id, tool_id, display_order, last_used_at,
                       notes, tags, created_at
                FROM user_tool_favorites
                WHERE user_id = ?
                ORDER BY display_order, created_at DESC
            """, (user_id,))
            tool_favorites = [self._row_to_dict(row) for row in tool_cursor.fetchall()]

            # Dataset favorites
            dataset_cursor = conn.execute("""
                SELECT id, user_id, dataset_id, display_order, last_used_at,
                       notes, tags, created_at
                FROM user_dataset_favorites
                WHERE user_id = ?
                ORDER BY display_order, created_at DESC
            """, (user_id,))
            dataset_favorites = [self._row_to_dict(row) for row in dataset_cursor.fetchall()]

            return {
                'tools': tool_favorites,
                'datasets': dataset_favorites
            }

        finally:
            conn.close()

    def update_favorite(
        self,
        user_id: int,
        item_id: str,
        item_type: str,
        is_favorite: bool,
        notes: str = None,
        tags: List[str] = None
    ) -> Dict[str, Any]:
        """Add or remove favorite"""
        if item_type not in ('tool', 'dataset'):
            raise ActionInputError("item_type must be 'tool' or 'dataset'")

        conn = self._get_db()
        try:
            now = datetime.utcnow().isoformat()
            table = 'user_tool_favorites' if item_type == 'tool' else 'user_dataset_favorites'
            id_column = 'tool_id' if item_type == 'tool' else 'dataset_id'

            if is_favorite:
                # Add favorite (or update if exists)
                existing = conn.execute(f"""
                    SELECT id FROM {table}
                    WHERE user_id = ? AND {id_column} = ?
                """, (user_id, item_id)).fetchone()

                if existing:
                    # Update
                    conn.execute(f"""
                        UPDATE {table}
                        SET last_used_at = ?,
                            notes = COALESCE(?, notes),
                            tags = COALESCE(?, tags)
                        WHERE id = ?
                    """, (
                        now,
                        notes,
                        json.dumps(tags) if tags else None,
                        existing['id']
                    ))
                    fav_id = existing['id']
                else:
                    # Insert
                    cursor = conn.execute(f"""
                        INSERT INTO {table} (
                            user_id, {id_column}, display_order,
                            last_used_at, notes, tags, created_at
                        )
                        VALUES (?, ?, 0, ?, ?, ?, ?)
                    """, (
                        user_id, item_id, now, notes,
                        json.dumps(tags) if tags else None, now
                    ))
                    fav_id = cursor.lastrowid

                conn.commit()
                return {'id': fav_id, 'action': 'added', 'item_id': item_id}

            else:
                # Remove favorite
                conn.execute(f"""
                    DELETE FROM {table}
                    WHERE user_id = ? AND {id_column} = ?
                """, (user_id, item_id))
                conn.commit()
                return {'action': 'removed', 'item_id': item_id}

        finally:
            conn.close()

    # ========================================================================
    # USAGE TRACKING
    # ========================================================================

    def get_user_usage(self, user_id: int, limit: int = 50) -> Dict[str, List[Dict[str, Any]]]:
        """Get user's usage history (tools and datasets)"""
        conn = self._get_db()
        try:
            # Tool usage
            tool_cursor = conn.execute("""
                SELECT id, user_id, tool_id, usage_count, last_used_at,
                       first_used_at, context_workflow_id, context_dataset_id,
                       execution_time_avg, success_rate, total_successes, total_failures
                FROM user_tool_usage
                WHERE user_id = ?
                ORDER BY last_used_at DESC
                LIMIT ?
            """, (user_id, limit))
            tool_usage = [self._row_to_dict(row) for row in tool_cursor.fetchall()]

            # Dataset usage
            dataset_cursor = conn.execute("""
                SELECT id, user_id, dataset_id, usage_count, last_used_at,
                       first_used_at, usage_context, total_workflows, total_analyses
                FROM user_dataset_usage
                WHERE user_id = ?
                ORDER BY last_used_at DESC
                LIMIT ?
            """, (user_id, limit))
            dataset_usage = [self._row_to_dict(row) for row in dataset_cursor.fetchall()]

            return {
                'tools': tool_usage,
                'datasets': dataset_usage
            }

        finally:
            conn.close()

    def track_usage(
        self,
        user_id: int,
        item_id: str,
        item_type: str,
        context_workflow_id: str = None,
        context_dataset_id: str = None,
        execution_time_seconds: float = None,
        success: bool = True
    ) -> Dict[str, Any]:
        """Track tool or dataset usage"""
        if item_type not in ('tool', 'dataset'):
            raise ActionInputError("item_type must be 'tool' or 'dataset'")

        conn = self._get_db()
        try:
            now = datetime.utcnow().isoformat()

            if item_type == 'tool':
                # Check if usage record exists
                existing = conn.execute("""
                    SELECT id, usage_count, execution_time_avg,
                           total_successes, total_failures
                    FROM user_tool_usage
                    WHERE user_id = ? AND tool_id = ?
                """, (user_id, item_id)).fetchone()

                if existing:
                    # Calculate new averages
                    new_count = existing['usage_count'] + 1
                    if execution_time_seconds and existing['execution_time_avg']:
                        new_avg_time = (
                            (existing['execution_time_avg'] * existing['usage_count'] +
                             execution_time_seconds) / new_count
                        )
                    else:
                        new_avg_time = execution_time_seconds or existing['execution_time_avg']

                    new_successes = existing['total_successes'] + (1 if success else 0)
                    new_failures = existing['total_failures'] + (0 if success else 1)
                    new_success_rate = new_successes / new_count

                    # Update
                    conn.execute("""
                        UPDATE user_tool_usage
                        SET usage_count = ?,
                            last_used_at = ?,
                            context_workflow_id = COALESCE(?, context_workflow_id),
                            context_dataset_id = COALESCE(?, context_dataset_id),
                            execution_time_avg = ?,
                            success_rate = ?,
                            total_successes = ?,
                            total_failures = ?
                        WHERE id = ?
                    """, (
                        new_count, now, context_workflow_id, context_dataset_id,
                        new_avg_time, new_success_rate, new_successes, new_failures,
                        existing['id']
                    ))
                    usage_id = existing['id']
                else:
                    # Insert
                    cursor = conn.execute("""
                        INSERT INTO user_tool_usage (
                            user_id, tool_id, usage_count, last_used_at, first_used_at,
                            context_workflow_id, context_dataset_id, execution_time_avg,
                            success_rate, total_successes, total_failures
                        )
                        VALUES (?, ?, 1, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, (
                        user_id, item_id, now, now, context_workflow_id,
                        context_dataset_id, execution_time_seconds,
                        1.0 if success else 0.0,
                        1 if success else 0,
                        0 if success else 1
                    ))
                    usage_id = cursor.lastrowid

            else:  # dataset
                # Check if usage record exists
                existing = conn.execute("""
                    SELECT id, usage_count
                    FROM user_dataset_usage
                    WHERE user_id = ? AND dataset_id = ?
                """, (user_id, item_id)).fetchone()

                if existing:
                    # Update
                    conn.execute("""
                        UPDATE user_dataset_usage
                        SET usage_count = usage_count + 1,
                            last_used_at = ?
                        WHERE id = ?
                    """, (now, existing['id']))
                    usage_id = existing['id']
                else:
                    # Insert
                    cursor = conn.execute("""
                        INSERT INTO user_dataset_usage (
                            user_id, dataset_id, usage_count,
                            last_used_at, first_used_at,
                            total_workflows, total_analyses
                        )
                        VALUES (?, ?, 1, ?, ?, 0, 0)
                    """, (user_id, item_id, now, now))
                    usage_id = cursor.lastrowid

            conn.commit()

            return {
                'id': usage_id,
                'item_id': item_id,
                'item_type': item_type,
                'timestamp': now
            }

        finally:
            conn.close()

    # ========================================================================
    # BATCH OPERATIONS
    # ========================================================================

    def get_all_user_state(self, user_id: int) -> UserStateResponse:
        """Get complete user state"""
        workflows = self.get_user_workflows(user_id)
        conversations = self.get_user_ai_conversations(user_id)
        favorites = self.get_user_favorites(user_id)
        usage = self.get_user_usage(user_id)

        return UserStateResponse(
            workflows=workflows,
            ai_conversations=conversations,
            tool_favorites=favorites['tools'],
            dataset_favorites=favorites['datasets'],
            tool_usage=usage['tools'],
            dataset_usage=usage['datasets'],
            timestamp=datetime.utcnow().isoformat()
        )

    def batch_update_state(self, user_id: int, updates: BatchStateUpdate) -> StateResponse:
        """Batch update multiple state categories"""
        try:
            # Update workflows
            if updates.workflows:
                for wf in updates.workflows:
                    self.update_workflow_state(
                        user_id=user_id,
                        workflow_uuid=wf.workflow_uuid,
                        workflow_data=wf.workflow_data,
                        workflow_name=wf.workflow_name,
                        editor_state=wf.editor_state,
                        status=wf.status,
                        is_favorite=wf.is_favorite
                    )

            # Update AI conversations
            if updates.ai_conversations:
                for conv in updates.ai_conversations:
                    self.update_ai_conversation(
                        user_id=user_id,
                        session_id=conv.session_id,
                        title=conv.title,
                        context_type=conv.context_type,
                        messages=conv.messages
                    )

            # Update favorites
            if updates.favorites:
                for fav in updates.favorites:
                    self.update_favorite(
                        user_id=user_id,
                        item_id=fav.item_id,
                        item_type=fav.item_type,
                        is_favorite=fav.is_favorite,
                        notes=fav.notes,
                        tags=fav.tags
                    )

            # Update usage
            if updates.usage:
                for usage in updates.usage:
                    self.track_usage(
                        user_id=user_id,
                        item_id=usage.item_id,
                        item_type=usage.item_type,
                        context_workflow_id=usage.context_workflow_id,
                        context_dataset_id=usage.context_dataset_id,
                        execution_time_seconds=usage.execution_time_seconds,
                        success=usage.success
                    )

            return StateResponse(
                success=True,
                message="State updated successfully",
                timestamp=datetime.utcnow().isoformat()
            )

        except Exception as e:
            log.error(f"Batch state update failed: {e}")
            raise


# ============================================================================
# API ENDPOINTS
# ============================================================================

# Global service instance
user_state_service: Optional[UserStateService] = None


def get_user_state_service() -> UserStateService:
    """Dependency to get user state service"""
    global user_state_service
    if user_state_service is None:
        user_state_service = UserStateService()
    return user_state_service


@router.get(
    "/api/users/{user_id}/state/all",
    summary="Get complete user state",
    response_model=UserStateResponse,
)
def get_all_state(
    user_id: int = Path(..., description="User ID"),
    service: UserStateService = depends(get_user_state_service)
) -> UserStateResponse:
    """
    Get complete user state including:
    - Workflow drafts and editor state
    - AI conversation history
    - Tool and dataset favorites
    - Usage history

    Returns all state needed to restore user's session.
    """
    try:
        return service.get_all_user_state(user_id)
    except Exception as e:
        log.error(f"Failed to get user state: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve user state"
        )


@router.post(
    "/api/users/{user_id}/state/batch",
    summary="Batch update user state",
    response_model=StateResponse,
)
def batch_update(
    user_id: int = Path(..., description="User ID"),
    updates: BatchStateUpdate = Body(...),
    service: UserStateService = depends(get_user_state_service)
) -> StateResponse:
    """
    Batch update multiple state categories at once.

    Accepts updates for:
    - Workflows (drafts, editor state)
    - AI conversations (messages)
    - Favorites (add/remove)
    - Usage tracking

    This endpoint is designed for efficient syncing of accumulated changes.
    """
    try:
        return service.batch_update_state(user_id, updates)
    except ActionInputError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))
    except Exception as e:
        log.error(f"Batch update failed: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Batch update failed"
        )


@router.get(
    "/api/users/{user_id}/state/workflows",
    summary="Get user workflows",
    response_model=List[Dict[str, Any]],
)
def get_workflows(
    user_id: int = Path(..., description="User ID"),
    limit: int = Query(100, description="Maximum number of workflows to return"),
    service: UserStateService = depends(get_user_state_service)
) -> List[Dict[str, Any]]:
    """Get user's workflow drafts and saved workflows"""
    try:
        return service.get_user_workflows(user_id, limit)
    except Exception as e:
        log.error(f"Failed to get workflows: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve workflows"
        )


@router.get(
    "/api/users/{user_id}/state/favorites",
    summary="Get user favorites",
    response_model=Dict[str, List[Dict[str, Any]]],
)
def get_favorites(
    user_id: int = Path(..., description="User ID"),
    service: UserStateService = depends(get_user_state_service)
) -> Dict[str, List[Dict[str, Any]]]:
    """Get user's favorite tools and datasets"""
    try:
        return service.get_user_favorites(user_id)
    except Exception as e:
        log.error(f"Failed to get favorites: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve favorites"
        )


@router.post(
    "/api/users/{user_id}/state/track-usage",
    summary="Track tool/dataset usage",
    response_model=Dict[str, Any],
)
def track_usage(
    user_id: int = Path(..., description="User ID"),
    usage: UsageUpdate = Body(...),
    service: UserStateService = depends(get_user_state_service)
) -> Dict[str, Any]:
    """Track tool or dataset usage"""
    try:
        return service.track_usage(
            user_id=user_id,
            item_id=usage.item_id,
            item_type=usage.item_type,
            context_workflow_id=usage.context_workflow_id,
            context_dataset_id=usage.context_dataset_id,
            execution_time_seconds=usage.execution_time_seconds,
            success=usage.success
        )
    except ActionInputError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))
    except Exception as e:
        log.error(f"Failed to track usage: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to track usage"
        )
