"""
API for managing user profiles and search session context
Provides endpoints for storing user preferences and auto-injecting context into enhanced search
"""

import logging
import json
import uuid
from datetime import datetime, timedelta
from typing import Optional, Dict, Any

from fastapi import (
    Body,
    HTTPException,
    status,
)
from pydantic import Field, constr

from galaxy.managers.context import ProvidesUserContext
from galaxy.webapps.galaxy.api import (
    depends,
    DependsOnTrans,
    Router,
)

log = logging.getLogger(__name__)

router = Router(tags=["user_profiles"])


@router.cbv
class FastAPIUserProfiles:
    """User profile and session management API"""

    @router.post(
        "/api/user_profiles",
        summary="Create or update user profile",
    )
    def create_or_update_profile(
        self,
        trans: ProvidesUserContext = DependsOnTrans,
        email: constr(min_length=3) = Body(..., description="User email"),
        research_domain: Optional[str] = Body(None, description="Primary research domain (proteomics, genomics, etc.)"),
        expertise_level: Optional[str] = Body(None, description="Expertise level (beginner, intermediate, expert)"),
        default_data_type: Optional[str] = Body(None, description="Default data type (DIA-LCMS, RNA-seq, etc.)"),
        organism: Optional[str] = Body(None, description="Default organism (human, mouse, etc.)"),
        typical_num_samples: Optional[int] = Body(None, description="Typical number of samples"),
        typical_num_replicates: Optional[int] = Body(None, description="Typical number of replicates"),
        preferences: Optional[Dict[str, Any]] = Body(None, description="Additional preferences (JSON)"),
    ):
        """
        Create or update user profile with research preferences

        These preferences will be automatically used in enhanced tool search
        to provide personalized, contextually relevant recommendations.
        """
        try:
            import sqlite3

            db_path = "/home/yzhang/biomate/backend/database/galaxy_ai_tools.db"
            conn = sqlite3.connect(db_path)
            cursor = conn.cursor()

            # Check if user exists
            cursor.execute("SELECT user_id FROM user_profiles WHERE email = ?", (email,))
            existing_user = cursor.fetchone()

            if existing_user:
                # Update existing profile
                user_id = existing_user[0]

                update_fields = []
                params = []

                if research_domain:
                    update_fields.append("research_domain = ?")
                    params.append(research_domain)
                if expertise_level:
                    update_fields.append("expertise_level = ?")
                    params.append(expertise_level)
                if default_data_type:
                    update_fields.append("default_data_type = ?")
                    params.append(default_data_type)
                if organism:
                    update_fields.append("organism = ?")
                    params.append(organism)
                if typical_num_samples is not None:
                    update_fields.append("typical_num_samples = ?")
                    params.append(typical_num_samples)
                if typical_num_replicates is not None:
                    update_fields.append("typical_num_replicates = ?")
                    params.append(typical_num_replicates)
                if preferences:
                    update_fields.append("preferences = ?")
                    params.append(json.dumps(preferences))

                update_fields.append("last_login = datetime('now')")
                params.append(user_id)

                sql = f"UPDATE user_profiles SET {', '.join(update_fields)} WHERE user_id = ?"
                cursor.execute(sql, params)
                conn.commit()

                message = "Profile updated successfully"
            else:
                # Create new profile
                user_id = f"user-{uuid.uuid4().hex[:8]}"

                cursor.execute("""
                    INSERT INTO user_profiles
                    (user_id, email, research_domain, expertise_level, default_data_type,
                     organism, typical_num_samples, typical_num_replicates, preferences, last_login)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
                """, (
                    user_id, email, research_domain, expertise_level, default_data_type,
                    organism, typical_num_samples, typical_num_replicates,
                    json.dumps(preferences or {})
                ))
                conn.commit()

                message = "Profile created successfully"

            # Fetch the complete profile
            cursor.execute("""
                SELECT user_id, email, research_domain, expertise_level, default_data_type,
                       organism, typical_num_samples, typical_num_replicates, preferences,
                       created_at, updated_at, last_login
                FROM user_profiles WHERE user_id = ?
            """, (user_id,))

            row = cursor.fetchone()
            conn.close()

            if row:
                return {
                    "success": True,
                    "message": message,
                    "profile": {
                        "user_id": row[0],
                        "email": row[1],
                        "research_domain": row[2],
                        "expertise_level": row[3],
                        "default_data_type": row[4],
                        "organism": row[5],
                        "typical_num_samples": row[6],
                        "typical_num_replicates": row[7],
                        "preferences": json.loads(row[8]) if row[8] else {},
                        "created_at": row[9],
                        "updated_at": row[10],
                        "last_login": row[11]
                    }
                }
            else:
                raise HTTPException(status_code=500, detail="Failed to retrieve profile")

        except Exception as e:
            log.error(f"Error creating/updating user profile: {e}", exc_info=True)
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Failed to save profile: {str(e)}"
            )

    @router.get(
        "/api/user_profiles/{user_id}",
        summary="Get user profile by ID",
    )
    def get_profile(
        self,
        user_id: str,
        trans: ProvidesUserContext = DependsOnTrans,
    ):
        """Get user profile by user_id"""
        try:
            import sqlite3

            db_path = "/home/yzhang/biomate/backend/database/galaxy_ai_tools.db"
            conn = sqlite3.connect(db_path)
            cursor = conn.cursor()

            cursor.execute("""
                SELECT user_id, email, research_domain, expertise_level, default_data_type,
                       organism, typical_num_samples, typical_num_replicates, preferences,
                       created_at, updated_at, last_login
                FROM user_profiles WHERE user_id = ?
            """, (user_id,))

            row = cursor.fetchone()
            conn.close()

            if not row:
                raise HTTPException(status_code=404, detail="User profile not found")

            return {
                "success": True,
                "profile": {
                    "user_id": row[0],
                    "email": row[1],
                    "research_domain": row[2],
                    "expertise_level": row[3],
                    "default_data_type": row[4],
                    "organism": row[5],
                    "typical_num_samples": row[6],
                    "typical_num_replicates": row[7],
                    "preferences": json.loads(row[8]) if row[8] else {},
                    "created_at": row[9],
                    "updated_at": row[10],
                    "last_login": row[11]
                }
            }
        except HTTPException:
            raise
        except Exception as e:
            log.error(f"Error fetching user profile: {e}", exc_info=True)
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Failed to fetch profile: {str(e)}"
            )

    @router.post(
        "/api/search_sessions",
        summary="Create a new search session",
    )
    def create_session(
        self,
        user_id: str = Body(..., description="User ID"),
        context_override: Optional[Dict[str, Any]] = Body(None, description="Optional context override"),
        trans: ProvidesUserContext = DependsOnTrans,
    ):
        """
        Create a new search session for a user

        Context is auto-populated from user profile unless overridden.
        Session expires in 7 days by default.
        """
        try:
            import sqlite3

            db_path = "/home/yzhang/biomate/backend/database/galaxy_ai_tools.db"
            conn = sqlite3.connect(db_path)
            cursor = conn.cursor()

            # Get user profile
            cursor.execute("""
                SELECT research_domain, expertise_level, default_data_type,
                       organism, typical_num_samples, typical_num_replicates
                FROM user_profiles WHERE user_id = ?
            """, (user_id,))

            profile = cursor.fetchone()

            if not profile:
                raise HTTPException(status_code=404, detail="User profile not found")

            # Build context from profile
            context = {
                "research_domain": profile[0],
                "expertise_level": profile[1],
                "data_type": profile[2],
                "organism": profile[3],
                "num_samples": profile[4],
                "num_replicates": profile[5]
            }

            # Apply overrides if provided
            if context_override:
                context.update(context_override)

            # Create session
            session_id = f"session-{uuid.uuid4().hex[:16]}"
            expires_at = (datetime.now() + timedelta(days=7)).isoformat()

            cursor.execute("""
                INSERT INTO search_sessions (session_id, user_id, context, expires_at)
                VALUES (?, ?, ?, ?)
            """, (session_id, user_id, json.dumps(context), expires_at))

            conn.commit()
            conn.close()

            return {
                "success": True,
                "message": "Session created successfully",
                "session": {
                    "session_id": session_id,
                    "user_id": user_id,
                    "context": context,
                    "expires_at": expires_at
                }
            }
        except HTTPException:
            raise
        except Exception as e:
            log.error(f"Error creating search session: {e}", exc_info=True)
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Failed to create session: {str(e)}"
            )

    @router.get(
        "/api/search_sessions/{session_id}",
        summary="Get search session",
    )
    def get_session(
        self,
        session_id: str,
        trans: ProvidesUserContext = DependsOnTrans,
    ):
        """Get search session by session_id"""
        try:
            import sqlite3

            db_path = "/home/yzhang/biomate/backend/database/galaxy_ai_tools.db"
            conn = sqlite3.connect(db_path)
            cursor = conn.cursor()

            cursor.execute("""
                SELECT session_id, user_id, context, created_at, last_active, expires_at, is_active
                FROM search_sessions WHERE session_id = ?
            """, (session_id,))

            row = cursor.fetchone()
            conn.close()

            if not row:
                raise HTTPException(status_code=404, detail="Session not found")

            return {
                "success": True,
                "session": {
                    "session_id": row[0],
                    "user_id": row[1],
                    "context": json.loads(row[2]),
                    "created_at": row[3],
                    "last_active": row[4],
                    "expires_at": row[5],
                    "is_active": bool(row[6])
                }
            }
        except HTTPException:
            raise
        except Exception as e:
            log.error(f"Error fetching session: {e}", exc_info=True)
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Failed to fetch session: {str(e)}"
            )

    @router.post(
        "/api/search_feedback",
        summary="Submit search feedback",
    )
    def submit_feedback(
        self,
        session_id: str = Body(..., description="Session ID"),
        query: str = Body(..., description="Search query"),
        tool_id: str = Body(..., description="Tool ID"),
        tool_rank: int = Body(..., description="Tool rank in results"),
        was_selected: bool = Body(..., description="Was this tool selected?"),
        was_helpful: Optional[bool] = Body(None, description="Was this tool helpful?"),
        feedback_comment: Optional[str] = Body(None, description="Optional feedback comment"),
        trans: ProvidesUserContext = DependsOnTrans,
    ):
        """
        Submit feedback on tool search results

        Used for ACE learning to improve future recommendations.
        """
        try:
            import sqlite3

            db_path = "/home/yzhang/biomate/backend/database/galaxy_ai_tools.db"
            conn = sqlite3.connect(db_path)
            cursor = conn.cursor()

            # Get session info
            cursor.execute("SELECT user_id, context FROM search_sessions WHERE session_id = ?", (session_id,))
            session = cursor.fetchone()

            if not session:
                raise HTTPException(status_code=404, detail="Session not found")

            user_id, search_context = session

            # Insert feedback
            cursor.execute("""
                INSERT INTO search_feedback
                (session_id, user_id, query, search_context, tool_id, tool_rank,
                 was_selected, was_helpful, feedback_comment)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                session_id, user_id, query, search_context, tool_id, tool_rank,
                1 if was_selected else 0,
                1 if was_helpful is True else (0 if was_helpful is False else None),
                feedback_comment
            ))

            feedback_id = cursor.lastrowid
            conn.commit()
            conn.close()

            return {
                "success": True,
                "message": "Feedback submitted successfully",
                "feedback_id": feedback_id
            }
        except HTTPException:
            raise
        except Exception as e:
            log.error(f"Error submitting feedback: {e}", exc_info=True)
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Failed to submit feedback: {str(e)}"
            )
