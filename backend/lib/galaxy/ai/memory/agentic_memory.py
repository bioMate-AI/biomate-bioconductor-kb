"""
Agentic Memory Backend

Python backend for the agentic memory system that mirrors the frontend
LTM schema. Provides persistence for:
- User profiles and preferences
- Project context and knowledge
- Session history
- Episodic memory (interaction outcomes)
- Procedural memory (learned workflows)

Uses SQLAlchemy for database access, compatible with the Drizzle
schema defined in frontend/shared/ltm-schema.ts.
"""

import os
import logging
from datetime import datetime
from typing import Dict, List, Optional, Any, Tuple
from dataclasses import dataclass, field
from contextlib import contextmanager
import json
import uuid

from sqlalchemy import create_engine, Column, String, Text, Integer, Float, Boolean
from sqlalchemy import DateTime, ForeignKey, JSON, ARRAY, Index
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, relationship, Session
from sqlalchemy.sql import func

log = logging.getLogger(__name__)

# Get database URL from environment
DATABASE_URL = os.environ.get("DATABASE_URL", "postgresql://localhost/biomate")

# Create engine
engine = create_engine(DATABASE_URL, echo=False, pool_pre_ping=True)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()


# ============================================================================
# SQLAlchemy Models (matching frontend ltm-schema.ts)
# ============================================================================

class LtmUser(Base):
    """User profile with expertise and preferences."""
    __tablename__ = "ltm_users"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    email = Column(Text, unique=True, nullable=False)
    name = Column(Text)
    expertise_level = Column(String(20), default="intermediate")
    research_domain = Column(String(100))
    affiliation = Column(Text)
    preferred_communication_style = Column(String(20), default="balanced")
    workflow_generation_mode = Column(String(20), default="auto-accept")
    total_workflows = Column(Integer, default=0)
    successful_workflows = Column(Integer, default=0)
    created_at = Column(DateTime, default=datetime.utcnow)
    last_active = Column(DateTime, default=datetime.utcnow)

    # Relationships
    projects = relationship("Project", back_populates="user")
    sessions = relationship("LtmSession", back_populates="user")
    preferences = relationship("UserPreference", back_populates="user")
    corrections = relationship("CorrectionLog", back_populates="user")
    workflows = relationship("LtmWorkflow", back_populates="user")


class Project(Base):
    """Project context with domain-specific metadata."""
    __tablename__ = "projects"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("ltm_users.id", ondelete="CASCADE"))
    name = Column(String(255), nullable=False)
    description = Column(Text)
    research_goal = Column(Text)
    instructions = Column(Text)
    primary_domain = Column(String(100))
    organisms = Column(ARRAY(Text))
    tissue_types = Column(ARRAY(Text))
    conditions = Column(ARRAY(Text))
    data_modalities = Column(ARRAY(Text))
    status = Column(String(20), default="active")
    progress = Column(Integer, default=0)
    storage_path = Column(Text)
    category = Column(String(100))
    tags = Column(ARRAY(Text), default=[])
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    archived_at = Column(DateTime)

    # Relationships
    user = relationship("LtmUser", back_populates="projects")
    sessions = relationship("LtmSession", back_populates="project")
    knowledge = relationship("ProjectKnowledge", back_populates="project")
    workflows = relationship("LtmWorkflow", back_populates="project")
    episodes = relationship("ProjectEpisode", back_populates="project")
    procedures = relationship("ProjectProcedure", back_populates="project")


class LtmSession(Base):
    """Session tracking with summaries."""
    __tablename__ = "sessions"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("ltm_users.id", ondelete="CASCADE"))
    project_id = Column(UUID(as_uuid=True), ForeignKey("projects.id", ondelete="SET NULL"))
    title = Column(Text)
    started_at = Column(DateTime, default=datetime.utcnow)
    ended_at = Column(DateTime)
    duration_seconds = Column(Integer)
    summary = Column(Text)
    key_decisions = Column(JSON)
    tools_discussed = Column(ARRAY(Text))
    workflows_created = Column(Integer, default=0)
    workflows_executed = Column(Integer, default=0)
    transcript_path = Column(Text)
    message_count = Column(Integer, default=0)
    total_tokens = Column(Integer, default=0)

    # Relationships
    user = relationship("LtmUser", back_populates="sessions")
    project = relationship("Project", back_populates="sessions")
    messages = relationship("ConversationMessage", back_populates="session")
    episodes = relationship("ProjectEpisode", back_populates="session")


class ConversationMessage(Base):
    """Full message history."""
    __tablename__ = "conversation_messages"

    id = Column(Integer, primary_key=True, autoincrement=True)
    session_id = Column(UUID(as_uuid=True), ForeignKey("sessions.id", ondelete="CASCADE"))
    role = Column(String(20), nullable=False)
    content = Column(Text, nullable=False)
    tools_used = Column(JSON)
    context_snapshot = Column(JSON)
    token_count = Column(Integer)
    created_at = Column(DateTime, default=datetime.utcnow)
    thinking_content = Column(Text)
    thinking_level = Column(String(20))

    # Relationships
    session = relationship("LtmSession", back_populates="messages")


class UserPreference(Base):
    """Learned preferences with confidence."""
    __tablename__ = "user_preferences"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(UUID(as_uuid=True), ForeignKey("ltm_users.id", ondelete="CASCADE"))
    preference_type = Column(String(50), nullable=False)
    context = Column(JSON)
    preference_key = Column(String(255), nullable=False)
    preference_value = Column(JSON, nullable=False)
    learned_from = Column(String(50))
    confidence = Column(Float, default=1.0)
    usage_count = Column(Integer, default=1)
    created_at = Column(DateTime, default=datetime.utcnow)
    last_used = Column(DateTime, default=datetime.utcnow)

    # Relationships
    user = relationship("LtmUser", back_populates="preferences")


class CorrectionLog(Base):
    """Learning from mistakes."""
    __tablename__ = "correction_log"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(UUID(as_uuid=True), ForeignKey("ltm_users.id", ondelete="CASCADE"))
    session_id = Column(UUID(as_uuid=True), ForeignKey("sessions.id", ondelete="SET NULL"))
    project_id = Column(UUID(as_uuid=True), ForeignKey("projects.id", ondelete="SET NULL"))
    suggested_approach = Column(JSON, nullable=False)
    corrected_approach = Column(JSON, nullable=False)
    workflow_context = Column(JSON)
    user_explanation = Column(Text)
    applied_to_future = Column(Boolean, default=False)
    created_at = Column(DateTime, default=datetime.utcnow)

    # Relationships
    user = relationship("LtmUser", back_populates="corrections")


class ProjectKnowledge(Base):
    """Project-specific knowledge base."""
    __tablename__ = "project_knowledge"

    id = Column(Integer, primary_key=True, autoincrement=True)
    project_id = Column(UUID(as_uuid=True), ForeignKey("projects.id", ondelete="CASCADE"))
    knowledge_type = Column(String(50), nullable=False)
    title = Column(String(255))
    content = Column(Text, nullable=False)
    related_workflows = Column(ARRAY(UUID(as_uuid=True)))
    related_sessions = Column(ARRAY(UUID(as_uuid=True)))
    source = Column(String(50))
    relevance_score = Column(Float, default=1.0)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    project = relationship("Project", back_populates="knowledge")


class LtmWorkflow(Base):
    """Workflow execution history."""
    __tablename__ = "workflows"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("ltm_users.id", ondelete="CASCADE"))
    project_id = Column(UUID(as_uuid=True), ForeignKey("projects.id", ondelete="SET NULL"))
    session_id = Column(UUID(as_uuid=True), ForeignKey("sessions.id", ondelete="SET NULL"))
    name = Column(String(255))
    description = Column(Text)
    workflow_json = Column(JSON, nullable=False)
    domain = Column(String(100))
    data_type = Column(String(100))
    analysis_goal = Column(Text)
    status = Column(String(20), default="draft")
    galaxy_workflow_id = Column(String(255))
    execution_id = Column(String(255))
    execution_started_at = Column(DateTime)
    execution_completed_at = Column(DateTime)
    execution_duration_seconds = Column(Integer)
    success = Column(Boolean)
    error_message = Column(Text)
    output_datasets = Column(ARRAY(UUID(as_uuid=True)))
    workflow_path = Column(Text)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    user = relationship("LtmUser", back_populates="workflows")
    project = relationship("Project", back_populates="workflows")
    episodes = relationship("ProjectEpisode", back_populates="workflow")


class ProjectEpisode(Base):
    """Agentic episodic memory."""
    __tablename__ = "project_episodes"

    id = Column(Integer, primary_key=True, autoincrement=True)
    project_id = Column(UUID(as_uuid=True), ForeignKey("projects.id", ondelete="CASCADE"))
    session_id = Column(UUID(as_uuid=True), ForeignKey("sessions.id", ondelete="SET NULL"))
    user_query = Column(Text, nullable=False)
    assistant_response = Column(Text, nullable=False)
    user_intent = Column(Text)
    tools_used = Column(JSON)
    workflow_generated = Column(Boolean, default=False)
    workflow_id = Column(UUID(as_uuid=True), ForeignKey("workflows.id", ondelete="SET NULL"))
    parameters_set = Column(JSON)
    outcome_success = Column(Boolean)
    user_feedback = Column(Integer)
    error_occurred = Column(Boolean, default=False)
    error_type = Column(String(100))
    error_message = Column(Text)
    what_worked = Column(ARRAY(Text))
    what_failed = Column(ARRAY(Text))
    lessons_learned = Column(ARRAY(Text))
    alternative_approaches = Column(ARRAY(Text))
    importance_score = Column(Float, default=0.5)
    access_count = Column(Integer, default=0)
    last_accessed = Column(DateTime, default=datetime.utcnow)
    created_at = Column(DateTime, default=datetime.utcnow)

    # Relationships
    project = relationship("Project", back_populates="episodes")
    session = relationship("LtmSession", back_populates="episodes")
    workflow = relationship("LtmWorkflow", back_populates="episodes")


class ProjectProcedure(Base):
    """Learned procedures/workflows."""
    __tablename__ = "project_procedures"

    id = Column(Integer, primary_key=True, autoincrement=True)
    project_id = Column(UUID(as_uuid=True), ForeignKey("projects.id", ondelete="CASCADE"))
    name = Column(String(255), nullable=False)
    trigger_pattern = Column(Text, nullable=False)
    description = Column(Text)
    steps = Column(JSON, nullable=False)
    preconditions = Column(ARRAY(Text))
    postconditions = Column(ARRAY(Text))
    success_rate = Column(Float, default=0.5)
    times_used = Column(Integer, default=0)
    last_used = Column(DateTime)
    learned_from = Column(ARRAY(Integer))
    applicable_domains = Column(ARRAY(Text))
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    project = relationship("Project", back_populates="procedures")


# ============================================================================
# Memory Service Classes
# ============================================================================

@contextmanager
def get_db_session():
    """Get a database session with automatic cleanup."""
    session = SessionLocal()
    try:
        yield session
        session.commit()
    except Exception:
        session.rollback()
        raise
    finally:
        session.close()


class UserMemoryService:
    """Service for user-related memory operations."""

    def get_or_create_user(self, email: str, name: Optional[str] = None) -> Dict[str, Any]:
        """Get or create a user profile."""
        with get_db_session() as session:
            user = session.query(LtmUser).filter(LtmUser.email == email).first()
            if user:
                user.last_active = datetime.utcnow()
                session.commit()
                return self._user_to_dict(user)

            new_user = LtmUser(email=email, name=name)
            session.add(new_user)
            session.commit()
            session.refresh(new_user)
            return self._user_to_dict(new_user)

    def get_user(self, user_id: str) -> Optional[Dict[str, Any]]:
        """Get user by ID."""
        with get_db_session() as session:
            user = session.query(LtmUser).filter(LtmUser.id == user_id).first()
            return self._user_to_dict(user) if user else None

    def update_user(self, user_id: str, data: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """Update user profile."""
        with get_db_session() as session:
            user = session.query(LtmUser).filter(LtmUser.id == user_id).first()
            if not user:
                return None
            for key, value in data.items():
                if hasattr(user, key):
                    setattr(user, key, value)
            user.last_active = datetime.utcnow()
            session.commit()
            return self._user_to_dict(user)

    def get_user_preferences(
        self,
        user_id: str,
        preference_type: Optional[str] = None,
        context: Optional[Dict] = None
    ) -> List[Dict[str, Any]]:
        """Get user preferences with optional filtering."""
        with get_db_session() as session:
            query = session.query(UserPreference).filter(
                UserPreference.user_id == user_id
            )
            if preference_type:
                query = query.filter(UserPreference.preference_type == preference_type)

            preferences = query.order_by(UserPreference.confidence.desc()).all()

            # Filter by context if provided
            if context:
                filtered = []
                for pref in preferences:
                    pref_context = pref.context or {}
                    if context.get("domain") and pref_context.get("domain"):
                        if pref_context["domain"] != context["domain"]:
                            continue
                    if context.get("data_type") and pref_context.get("data_type"):
                        if pref_context["data_type"] != context["data_type"]:
                            continue
                    filtered.append(pref)
                preferences = filtered

            return [self._preference_to_dict(p) for p in preferences]

    def record_preference(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Record or update a user preference."""
        with get_db_session() as session:
            # Check for existing
            existing = session.query(UserPreference).filter(
                UserPreference.user_id == data["user_id"],
                UserPreference.preference_key == data["preference_key"]
            ).first()

            if existing:
                existing.preference_value = data["preference_value"]
                existing.usage_count = (existing.usage_count or 0) + 1
                existing.confidence = min(1.0, (existing.confidence or 0.5) + 0.1)
                existing.last_used = datetime.utcnow()
                session.commit()
                return self._preference_to_dict(existing)

            pref = UserPreference(**data)
            session.add(pref)
            session.commit()
            session.refresh(pref)
            return self._preference_to_dict(pref)

    def record_correction(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Record a correction for learning."""
        with get_db_session() as session:
            correction = CorrectionLog(**data)
            session.add(correction)
            session.commit()
            session.refresh(correction)
            return self._correction_to_dict(correction)

    def load_user_context(self, user_id: str) -> Dict[str, Any]:
        """Load complete user context for session initialization."""
        with get_db_session() as session:
            user = session.query(LtmUser).filter(LtmUser.id == user_id).first()
            if not user:
                return {"user": None, "preferences": [], "corrections": [], "sessions": []}

            preferences = session.query(UserPreference).filter(
                UserPreference.user_id == user_id
            ).order_by(UserPreference.confidence.desc()).limit(20).all()

            corrections = session.query(CorrectionLog).filter(
                CorrectionLog.user_id == user_id
            ).order_by(CorrectionLog.created_at.desc()).limit(10).all()

            recent_sessions = session.query(LtmSession).filter(
                LtmSession.user_id == user_id
            ).order_by(LtmSession.started_at.desc()).limit(5).all()

            success_rate = 0.0
            if user.total_workflows and user.total_workflows > 0:
                success_rate = (user.successful_workflows or 0) / user.total_workflows

            return {
                "user": self._user_to_dict(user),
                "preferences": [self._preference_to_dict(p) for p in preferences],
                "corrections": [self._correction_to_dict(c) for c in corrections],
                "sessions": [self._session_to_dict(s) for s in recent_sessions],
                "stats": {
                    "total_workflows": user.total_workflows or 0,
                    "success_rate": success_rate,
                },
            }

    @staticmethod
    def _user_to_dict(user: LtmUser) -> Dict[str, Any]:
        return {
            "id": str(user.id),
            "email": user.email,
            "name": user.name,
            "expertise_level": user.expertise_level,
            "research_domain": user.research_domain,
            "affiliation": user.affiliation,
            "preferred_communication_style": user.preferred_communication_style,
            "workflow_generation_mode": user.workflow_generation_mode,
            "total_workflows": user.total_workflows,
            "successful_workflows": user.successful_workflows,
            "created_at": user.created_at.isoformat() if user.created_at else None,
            "last_active": user.last_active.isoformat() if user.last_active else None,
        }

    @staticmethod
    def _preference_to_dict(pref: UserPreference) -> Dict[str, Any]:
        return {
            "id": pref.id,
            "user_id": str(pref.user_id),
            "preference_type": pref.preference_type,
            "context": pref.context,
            "preference_key": pref.preference_key,
            "preference_value": pref.preference_value,
            "learned_from": pref.learned_from,
            "confidence": pref.confidence,
            "usage_count": pref.usage_count,
            "created_at": pref.created_at.isoformat() if pref.created_at else None,
            "last_used": pref.last_used.isoformat() if pref.last_used else None,
        }

    @staticmethod
    def _correction_to_dict(correction: CorrectionLog) -> Dict[str, Any]:
        return {
            "id": correction.id,
            "user_id": str(correction.user_id),
            "session_id": str(correction.session_id) if correction.session_id else None,
            "project_id": str(correction.project_id) if correction.project_id else None,
            "suggested_approach": correction.suggested_approach,
            "corrected_approach": correction.corrected_approach,
            "workflow_context": correction.workflow_context,
            "user_explanation": correction.user_explanation,
            "applied_to_future": correction.applied_to_future,
            "created_at": correction.created_at.isoformat() if correction.created_at else None,
        }

    @staticmethod
    def _session_to_dict(session: LtmSession) -> Dict[str, Any]:
        return {
            "id": str(session.id),
            "user_id": str(session.user_id) if session.user_id else None,
            "project_id": str(session.project_id) if session.project_id else None,
            "title": session.title,
            "started_at": session.started_at.isoformat() if session.started_at else None,
            "ended_at": session.ended_at.isoformat() if session.ended_at else None,
            "duration_seconds": session.duration_seconds,
            "summary": session.summary,
            "message_count": session.message_count,
        }


class EpisodicMemoryService:
    """Service for episodic memory operations."""

    def record_episode(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Record an interaction episode."""
        with get_db_session() as session:
            episode = ProjectEpisode(**data)
            session.add(episode)
            session.commit()
            session.refresh(episode)
            return self._episode_to_dict(episode)

    def get_similar_episodes(
        self,
        project_id: str,
        intent: Optional[str] = None,
        tools_used: Optional[List[str]] = None,
        limit: int = 10
    ) -> List[Dict[str, Any]]:
        """Get similar episodes for retrieval-augmented reasoning."""
        with get_db_session() as session:
            query = session.query(ProjectEpisode).filter(
                ProjectEpisode.project_id == project_id
            ).order_by(ProjectEpisode.importance_score.desc())

            episodes = query.all()

            # Filter by tools used
            if tools_used:
                filtered = []
                for ep in episodes:
                    if ep.tools_used:
                        ep_tools = [t.get("tool_id") for t in ep.tools_used]
                        if any(t in ep_tools for t in tools_used):
                            filtered.append(ep)
                episodes = filtered

            # Filter by intent similarity
            if intent:
                lower_intent = intent.lower()
                episodes = [
                    ep for ep in episodes
                    if (ep.user_intent and lower_intent in ep.user_intent.lower()) or
                       lower_intent in ep.user_query.lower()
                ]

            return [self._episode_to_dict(ep) for ep in episodes[:limit]]

    def get_successful_episodes(self, project_id: str, limit: int = 20) -> List[Dict[str, Any]]:
        """Get successful episodes for learning."""
        with get_db_session() as session:
            episodes = session.query(ProjectEpisode).filter(
                ProjectEpisode.project_id == project_id,
                ProjectEpisode.outcome_success == True
            ).order_by(ProjectEpisode.importance_score.desc()).limit(limit).all()

            return [self._episode_to_dict(ep) for ep in episodes]

    def get_failed_episodes(self, project_id: str, limit: int = 20) -> List[Dict[str, Any]]:
        """Get failed episodes for learning from mistakes."""
        with get_db_session() as session:
            episodes = session.query(ProjectEpisode).filter(
                ProjectEpisode.project_id == project_id,
                ProjectEpisode.outcome_success == False
            ).order_by(ProjectEpisode.created_at.desc()).limit(limit).all()

            return [self._episode_to_dict(ep) for ep in episodes]

    def update_episode_outcome(
        self,
        episode_id: int,
        success: bool,
        error_type: Optional[str] = None,
        error_message: Optional[str] = None,
        what_worked: Optional[List[str]] = None,
        what_failed: Optional[List[str]] = None,
        lessons_learned: Optional[List[str]] = None
    ) -> Optional[Dict[str, Any]]:
        """Update episode outcome after workflow execution."""
        with get_db_session() as session:
            episode = session.query(ProjectEpisode).filter(
                ProjectEpisode.id == episode_id
            ).first()

            if not episode:
                return None

            episode.outcome_success = success
            episode.error_occurred = not success
            episode.error_type = error_type
            episode.error_message = error_message
            episode.what_worked = what_worked
            episode.what_failed = what_failed
            episode.lessons_learned = lessons_learned
            episode.importance_score = 0.6 if success else 0.8  # Failures more important

            session.commit()
            return self._episode_to_dict(episode)

    def access_episode(self, episode_id: int) -> None:
        """Increment access count for memory importance."""
        with get_db_session() as session:
            episode = session.query(ProjectEpisode).filter(
                ProjectEpisode.id == episode_id
            ).first()
            if episode:
                episode.access_count = (episode.access_count or 0) + 1
                episode.last_accessed = datetime.utcnow()
                session.commit()

    @staticmethod
    def _episode_to_dict(episode: ProjectEpisode) -> Dict[str, Any]:
        return {
            "id": episode.id,
            "project_id": str(episode.project_id) if episode.project_id else None,
            "session_id": str(episode.session_id) if episode.session_id else None,
            "user_query": episode.user_query,
            "assistant_response": episode.assistant_response,
            "user_intent": episode.user_intent,
            "tools_used": episode.tools_used,
            "workflow_generated": episode.workflow_generated,
            "workflow_id": str(episode.workflow_id) if episode.workflow_id else None,
            "outcome_success": episode.outcome_success,
            "error_occurred": episode.error_occurred,
            "error_type": episode.error_type,
            "error_message": episode.error_message,
            "what_worked": episode.what_worked,
            "what_failed": episode.what_failed,
            "lessons_learned": episode.lessons_learned,
            "importance_score": episode.importance_score,
            "access_count": episode.access_count,
            "created_at": episode.created_at.isoformat() if episode.created_at else None,
        }


class ProceduralMemoryService:
    """Service for procedural memory operations."""

    def create_procedure(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Create a learned procedure."""
        with get_db_session() as session:
            procedure = ProjectProcedure(**data)
            session.add(procedure)
            session.commit()
            session.refresh(procedure)
            return self._procedure_to_dict(procedure)

    def find_matching_procedures(
        self,
        project_id: str,
        trigger: str
    ) -> List[Dict[str, Any]]:
        """Find procedures matching a trigger pattern."""
        with get_db_session() as session:
            procedures = session.query(ProjectProcedure).filter(
                ProjectProcedure.project_id == project_id
            ).order_by(ProjectProcedure.success_rate.desc()).all()

            lower_trigger = trigger.lower()
            matching = [
                p for p in procedures
                if lower_trigger in p.trigger_pattern.lower() or
                   p.trigger_pattern.lower() in lower_trigger
            ]

            return [self._procedure_to_dict(p) for p in matching]

    def get_reliable_procedures(
        self,
        project_id: str,
        min_success_rate: float = 0.7
    ) -> List[Dict[str, Any]]:
        """Get procedures with high success rates."""
        with get_db_session() as session:
            procedures = session.query(ProjectProcedure).filter(
                ProjectProcedure.project_id == project_id,
                ProjectProcedure.success_rate >= min_success_rate
            ).order_by(ProjectProcedure.success_rate.desc()).all()

            return [self._procedure_to_dict(p) for p in procedures]

    def record_usage(self, procedure_id: int, success: bool) -> Optional[Dict[str, Any]]:
        """Record procedure usage and update success rate."""
        with get_db_session() as session:
            procedure = session.query(ProjectProcedure).filter(
                ProjectProcedure.id == procedure_id
            ).first()

            if not procedure:
                return None

            times_used = (procedure.times_used or 0) + 1
            current_success_count = (procedure.success_rate or 0) * (procedure.times_used or 0)
            new_success_rate = (current_success_count + (1 if success else 0)) / times_used

            procedure.times_used = times_used
            procedure.success_rate = new_success_rate
            procedure.last_used = datetime.utcnow()

            session.commit()
            return self._procedure_to_dict(procedure)

    @staticmethod
    def _procedure_to_dict(procedure: ProjectProcedure) -> Dict[str, Any]:
        return {
            "id": procedure.id,
            "project_id": str(procedure.project_id) if procedure.project_id else None,
            "name": procedure.name,
            "trigger_pattern": procedure.trigger_pattern,
            "description": procedure.description,
            "steps": procedure.steps,
            "preconditions": procedure.preconditions,
            "postconditions": procedure.postconditions,
            "success_rate": procedure.success_rate,
            "times_used": procedure.times_used,
            "last_used": procedure.last_used.isoformat() if procedure.last_used else None,
            "applicable_domains": procedure.applicable_domains,
            "created_at": procedure.created_at.isoformat() if procedure.created_at else None,
        }


class AgenticMemoryService:
    """
    Unified service for all agentic memory operations.

    Provides access to:
    - User memory (profiles, preferences, corrections)
    - Episodic memory (interaction outcomes)
    - Procedural memory (learned workflows)
    """

    def __init__(self):
        self.users = UserMemoryService()
        self.episodes = EpisodicMemoryService()
        self.procedures = ProceduralMemoryService()

    def initialize_session_context(
        self,
        user_id: str,
        project_id: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Initialize session with full memory context.

        Returns context useful for the AI assistant including:
        - User preferences and expertise
        - Recent corrections (learning from mistakes)
        - Relevant episodes from project history
        - Applicable procedures
        """
        context = {
            "user_context": self.users.load_user_context(user_id),
            "project_context": None,
            "relevant_episodes": [],
            "applicable_procedures": [],
        }

        if project_id:
            context["relevant_episodes"] = self.episodes.get_successful_episodes(project_id, 5)
            context["applicable_procedures"] = self.procedures.get_reliable_procedures(project_id)

        return context

    def record_interaction(
        self,
        project_id: str,
        session_id: str,
        user_query: str,
        assistant_response: str,
        user_intent: Optional[str] = None,
        tools_used: Optional[List[Dict]] = None,
        workflow_generated: bool = False,
        workflow_id: Optional[str] = None
    ) -> Dict[str, Any]:
        """Record a complete interaction as an episode."""
        return self.episodes.record_episode({
            "project_id": project_id,
            "session_id": session_id,
            "user_query": user_query,
            "assistant_response": assistant_response,
            "user_intent": user_intent,
            "tools_used": tools_used,
            "workflow_generated": workflow_generated,
            "workflow_id": workflow_id,
        })

    def learn_from_outcome(
        self,
        episode_id: int,
        success: bool,
        reflection: Optional[Dict[str, Any]] = None
    ) -> Optional[Dict[str, Any]]:
        """Update episode with outcome and AI reflection."""
        return self.episodes.update_episode_outcome(
            episode_id=episode_id,
            success=success,
            error_type=reflection.get("error_type") if reflection else None,
            error_message=reflection.get("error_message") if reflection else None,
            what_worked=reflection.get("what_worked") if reflection else None,
            what_failed=reflection.get("what_failed") if reflection else None,
            lessons_learned=reflection.get("lessons_learned") if reflection else None,
        )


# Singleton instance
agentic_memory = AgenticMemoryService()


def create_tables():
    """Create all database tables."""
    Base.metadata.create_all(bind=engine)
    log.info("Agentic memory tables created")


def get_memory_service() -> AgenticMemoryService:
    """Get the agentic memory service instance."""
    return agentic_memory
