"""
API Controller for Chat Session Management
Provides persistence layer for frontend chat sessions
"""

import logging
import json
from typing import List, Optional, Dict, Any
from datetime import datetime

from fastapi import Body, Query
from pydantic import BaseModel, Field
from sqlalchemy import text

from galaxy.managers.context import ProvidesUserContext
from galaxy.model import User
from galaxy.webapps.galaxy.api import (
    depends,
    DependsOnTrans,
    DependsOnUser,
    Router,
)

log = logging.getLogger(__name__)

router = Router(tags=["sessions"])


# Pydantic models for request/response
class MessageModel(BaseModel):
    message_id: str
    role: str  # 'user', 'assistant', 'system'
    content: str
    timestamp: str
    token_count: Optional[int] = 0
    suggestions: Optional[List[str]] = None
    workflow_id: Optional[str] = None
    thinking_content: Optional[str] = None
    thinking_level: Optional[str] = None
    error_code: Optional[int] = None
    error_message: Optional[str] = None


class WorkflowModel(BaseModel):
    workflow_id: str
    workflow_name: Optional[str] = None
    workflow_description: Optional[str] = None
    invocation_id: Optional[str] = None
    status: Optional[str] = None
    success: Optional[int] = None
    error_message: Optional[str] = None


class DatasetModel(BaseModel):
    dataset_id: Optional[str] = None
    dataset_name: str
    dataset_type: str  # 'input', 'output', 'intermediate'
    storage_type: str  # 's3', 'local', 'replit_storage', 'galaxy'
    storage_path: Optional[str] = None
    format: Optional[str] = None
    size_bytes: Optional[int] = None
    description: Optional[str] = None


class SessionCreatePayload(BaseModel):
    session_id: str
    title: str = "New Chat"
    session_type: str = "chat"


class SessionUpdatePayload(BaseModel):
    title: Optional[str] = None
    status: Optional[str] = None
    message_count: Optional[int] = None
    token_count: Optional[int] = None
    messages: Optional[List[MessageModel]] = None
    workflows: Optional[List[WorkflowModel]] = None
    datasets: Optional[List[DatasetModel]] = None


class SessionResponse(BaseModel):
    session_id: str
    user_id: int
    title: str
    created_at: str
    last_activity: str
    status: str
    message_count: int
    token_count: int
    session_type: str


class SessionDetailResponse(SessionResponse):
    messages: List[MessageModel]
    workflows: List[WorkflowModel]
    datasets: List[DatasetModel]
    compression_count: int


@router.cbv
class SessionsAPI:
    """API for managing chat sessions with backend persistence"""

    @router.post("/api/sessions")
    def create_session(
        self,
        payload: SessionCreatePayload,
        trans: ProvidesUserContext = DependsOnTrans,
        user: User = DependsOnUser,
    ) -> SessionResponse:
        """Create a new chat session"""

        db = trans.sa_session

        # Check if session already exists
        existing = db.execute(
            text("SELECT session_id FROM chat_sessions WHERE session_id = :session_id"),
            {"session_id": payload.session_id}
        ).fetchone()

        if existing:
            return self.get_session(payload.session_id, trans, user)

        # Create new session
        db.execute(
            text("""
            INSERT INTO chat_sessions (session_id, user_id, title, session_type)
            VALUES (:session_id, :user_id, :title, :session_type)
            """),
            {"session_id": payload.session_id, "user_id": user.id, "title": payload.title, "session_type": payload.session_type}
        )
        db.commit()

        log.info(f"Created session {payload.session_id} for user {user.id}")

        return self.get_session(payload.session_id, trans, user)

    @router.get("/api/sessions/{session_id}")
    def get_session(
        self,
        session_id: str,
        trans: ProvidesUserContext = DependsOnTrans,
        user: User = DependsOnUser,
    ) -> SessionDetailResponse:
        """Get a session with all messages, workflows, and datasets"""

        db = trans.sa_session

        # Get session
        session = db.execute(
            text("""
            SELECT session_id, user_id, title, created_at, last_activity,
                   status, message_count, token_count, session_type
            FROM chat_sessions
            WHERE session_id = :session_id AND user_id = :user_id
            """),
            {"session_id": session_id, "user_id": user.id}
        ).fetchone()

        if not session:
            raise Exception(f"Session {session_id} not found")

        # Get messages
        messages = db.execute(
            text("""
            SELECT message_id, role, content, timestamp, token_count,
                   suggestions, workflow_id, thinking_content, thinking_level,
                   error_code, error_message
            FROM chat_messages
            WHERE session_id = :session_id
            ORDER BY timestamp ASC
            """),
            {"session_id": session_id}
        ).fetchall()

        # Get workflows
        workflows = db.execute(
            text("""
            SELECT workflow_id, workflow_name, workflow_description,
                   invocation_id, status, success, error_message
            FROM session_workflows
            WHERE session_id = :session_id
            ORDER BY created_at ASC
            """),
            {"session_id": session_id}
        ).fetchall()

        # Get datasets
        datasets = db.execute(
            text("""
            SELECT dataset_id, dataset_name, dataset_type, storage_type,
                   storage_path, format, size_bytes, description
            FROM session_datasets
            WHERE session_id = :session_id
            ORDER BY created_at ASC
            """),
            {"session_id": session_id}
        ).fetchall()

        # Get compression count
        compression_count = db.execute(
            text("SELECT COUNT(*) FROM session_compressions WHERE session_id = :session_id"),
            {"session_id": session_id}
        ).fetchone()[0]

        return SessionDetailResponse(
            session_id=session[0],
            user_id=session[1],
            title=session[2],
            created_at=session[3],
            last_activity=session[4],
            status=session[5],
            message_count=session[6],
            token_count=session[7],
            session_type=session[8],
            messages=[
                MessageModel(
                    message_id=m[0],
                    role=m[1],
                    content=m[2],
                    timestamp=m[3],
                    token_count=m[4],
                    suggestions=json.loads(m[5]) if m[5] else None,
                    workflow_id=m[6],
                    thinking_content=m[7],
                    thinking_level=m[8],
                    error_code=m[9],
                    error_message=m[10],
                )
                for m in messages
            ],
            workflows=[
                WorkflowModel(
                    workflow_id=w[0],
                    workflow_name=w[1],
                    workflow_description=w[2],
                    invocation_id=w[3],
                    status=w[4],
                    success=w[5],
                    error_message=w[6],
                )
                for w in workflows
            ],
            datasets=[
                DatasetModel(
                    dataset_id=d[0],
                    dataset_name=d[1],
                    dataset_type=d[2],
                    storage_type=d[3],
                    storage_path=d[4],
                    format=d[5],
                    size_bytes=d[6],
                    description=d[7],
                )
                for d in datasets
            ],
            compression_count=compression_count,
        )

    @router.put("/api/sessions/{session_id}")
    def update_session(
        self,
        session_id: str,
        payload: SessionUpdatePayload,
        trans: ProvidesUserContext = DependsOnTrans,
        user: User = DependsOnUser,
    ) -> SessionResponse:
        """Update session metadata and content"""

        db = trans.sa_session

        # Update session metadata
        updates = []
        params_dict = {
            "session_id": session_id,
            "user_id": user.id
        }

        if payload.title is not None:
            updates.append("title = :title")
            params_dict["title"] = payload.title

        if payload.status is not None:
            updates.append("status = :status")
            params_dict["status"] = payload.status

        if payload.message_count is not None:
            updates.append("message_count = :message_count")
            params_dict["message_count"] = payload.message_count

        if payload.token_count is not None:
            updates.append("token_count = :token_count")
            params_dict["token_count"] = payload.token_count

        # Always update last_activity
        updates.append("last_activity = datetime('now')")

        if updates:
            updates_str = ', '.join(updates)
            db.execute(
                text(f"UPDATE chat_sessions SET {updates_str} WHERE session_id = :session_id AND user_id = :user_id"),
                params_dict
            )

        # Update messages if provided
        if payload.messages is not None:
            # Clear existing messages
            db.execute(text("DELETE FROM chat_messages WHERE session_id = :session_id"), {"session_id": session_id})

            # Insert new messages
            for msg in payload.messages:
                db.execute(
                    text("""
                    INSERT INTO chat_messages
                    (message_id, session_id, role, content, timestamp, token_count,
                     suggestions, workflow_id, thinking_content, thinking_level,
                     error_code, error_message)
                    VALUES (:message_id, :session_id, :role, :content, :timestamp, :token_count,
                     :suggestions, :workflow_id, :thinking_content, :thinking_level,
                     :error_code, :error_message)
                    """),
                    {
                        "message_id": msg.message_id, "session_id": session_id, "role": msg.role, "content": msg.content,
                        "timestamp": msg.timestamp, "token_count": msg.token_count,
                        "suggestions": json.dumps(msg.suggestions) if msg.suggestions else None,
                        "workflow_id": msg.workflow_id, "thinking_content": msg.thinking_content, "thinking_level": msg.thinking_level,
                        "error_code": msg.error_code, "error_message": msg.error_message
                    }
                )

        # Update workflows if provided
        if payload.workflows is not None:
            # Clear existing workflows
            db.execute(text("DELETE FROM session_workflows WHERE session_id = :session_id"), {"session_id": session_id})

            # Insert new workflows
            for wf in payload.workflows:
                db.execute(
                    text("""
                    INSERT INTO session_workflows
                    (session_id, workflow_id, workflow_name, workflow_description,
                     invocation_id, status, success, error_message)
                    VALUES (:session_id, :workflow_id, :workflow_name, :workflow_description,
                     :invocation_id, :status, :success, :error_message)
                    """),
                    {
                        "session_id": session_id, "workflow_id": wf.workflow_id, "workflow_name": wf.workflow_name,
                        "workflow_description": wf.workflow_description, "invocation_id": wf.invocation_id,
                        "status": wf.status, "success": wf.success, "error_message": wf.error_message
                    }
                )

        # Update datasets if provided
        if payload.datasets is not None:
            # Clear existing datasets
            db.execute(text("DELETE FROM session_datasets WHERE session_id = :session_id"), {"session_id": session_id})

            # Insert new datasets
            for ds in payload.datasets:
                db.execute(
                    text("""
                    INSERT INTO session_datasets
                    (session_id, dataset_id, dataset_name, dataset_type,
                     storage_type, storage_path, format, size_bytes, description)
                    VALUES (:session_id, :dataset_id, :dataset_name, :dataset_type,
                     :storage_type, :storage_path, :format, :size_bytes, :description)
                    """),
                    {
                        "session_id": session_id, "dataset_id": ds.dataset_id, "dataset_name": ds.dataset_name, "dataset_type": ds.dataset_type,
                        "storage_type": ds.storage_type, "storage_path": ds.storage_path, "format": ds.format,
                        "size_bytes": ds.size_bytes, "description": ds.description
                    }
                )

        db.commit()

        log.info(f"Updated session {session_id}")

        return self.get_session(session_id, trans, user)

    @router.get("/api/sessions")
    def list_sessions(
        self,
        status: Optional[str] = Query(None, description="Filter by status"),
        limit: int = Query(20, description="Maximum number of sessions to return"),
        trans: ProvidesUserContext = DependsOnTrans,
        user: User = DependsOnUser,
    ) -> List[SessionResponse]:
        """List user's sessions"""

        db = trans.sa_session

        query = """
            SELECT session_id, user_id, title, created_at, last_activity,
                   status, message_count, token_count, session_type
            FROM chat_sessions
            WHERE user_id = :user_id
        """
        params = {"user_id": user.id}

        if status:
            query += " AND status = :status"
            params["status"] = status

        query += " ORDER BY last_activity DESC LIMIT :limit"
        params["limit"] = limit

        sessions = db.execute(text(query), params).fetchall()

        return [
            SessionResponse(
                session_id=s[0],
                user_id=s[1],
                title=s[2],
                created_at=s[3],
                last_activity=s[4],
                status=s[5],
                message_count=s[6],
                token_count=s[7],
                session_type=s[8],
            )
            for s in sessions
        ]

    @router.delete("/api/sessions/{session_id}")
    def delete_session(
        self,
        session_id: str,
        trans: ProvidesUserContext = DependsOnTrans,
        user: User = DependsOnUser,
    ) -> Dict[str, Any]:
        """Delete a session (soft delete - sets status to 'deleted')"""

        db = trans.sa_session

        db.execute(
            text("""
            UPDATE chat_sessions
            SET status = 'deleted', last_activity = datetime('now')
            WHERE session_id = :session_id AND user_id = :user_id
            """),
            {"session_id": session_id, "user_id": user.id}
        )
        db.commit()

        log.info(f"Deleted session {session_id}")

        return {"message": "Session deleted", "session_id": session_id}

    @router.post("/api/sessions/{session_id}/compress")
    def compress_session(
        self,
        session_id: str,
        summary: str = Body(..., description="AI-generated summary of old messages"),
        messages_before: int = Body(..., description="Message count before compression"),
        messages_after: int = Body(..., description="Message count after compression"),
        tokens_before: int = Body(..., description="Token count before compression"),
        tokens_after: int = Body(..., description="Token count after compression"),
        trans: ProvidesUserContext = DependsOnTrans,
        user: User = DependsOnUser,
    ) -> Dict[str, Any]:
        """Record a session compression event"""

        db = trans.sa_session

        # Calculate compression ratio
        compression_ratio = tokens_after / tokens_before if tokens_before > 0 else 0

        # Insert compression record
        db.execute(
            text("""
            INSERT INTO session_compressions
            (session_id, messages_before, messages_after, tokens_before, tokens_after,
             compression_ratio, summary)
            VALUES (:session_id, :messages_before, :messages_after, :tokens_before, :tokens_after,
             :compression_ratio, :summary)
            """),
            {
                "session_id": session_id, "messages_before": messages_before, "messages_after": messages_after,
                "tokens_before": tokens_before, "tokens_after": tokens_after, "compression_ratio": compression_ratio, "summary": summary
            }
        )

        # Update session
        db.execute(
            text("""
            UPDATE chat_sessions
            SET last_compressed_at = datetime('now'),
                token_count = :token_count,
                last_activity = datetime('now')
            WHERE session_id = :session_id AND user_id = :user_id
            """),
            {"token_count": tokens_after, "session_id": session_id, "user_id": user.id}
        )
        db.commit()

        log.info(f"Compressed session {session_id}: {tokens_before} → {tokens_after} tokens")

        return {
            "message": "Session compressed",
            "session_id": session_id,
            "compression_ratio": compression_ratio,
            "tokens_saved": tokens_before - tokens_after
        }
