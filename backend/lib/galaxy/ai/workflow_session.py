"""
WorkflowSession — persists multi-turn workflow pipeline state in Redis.

Stored per session_id. Enables:
  - Context persistence across chat turns ("change padj" knows what workflow is active)
  - Multi-step pipeline state (steps[], output_types per step)
  - Modification history
"""

import json
import time
from dataclasses import dataclass, field, asdict
from typing import Any, Dict, List, Optional

try:
    import redis
    _REDIS_AVAILABLE = True
except ImportError:
    _REDIS_AVAILABLE = False


@dataclass
class WorkflowStep:
    index: int
    workflow_name: str
    nextflow_path: str
    params: Dict[str, Any]
    status: str = "pending"          # pending|running|completed|failed
    run_id: Optional[str] = None
    input_from: Optional[int] = None # step index providing input
    input_type: Optional[str] = None
    output_types: List[str] = field(default_factory=list)
    skipped_steps: List[str] = field(default_factory=list)  # nf-core skip flags applied


@dataclass
class WorkflowSession:
    session_id: str
    user_intent: str = ""
    data_format: str = ""            # "raw_fastq" | "count_matrix" | "bam" | ...
    steps: List[WorkflowStep] = field(default_factory=list)
    created_at: float = field(default_factory=time.time)
    updated_at: float = field(default_factory=time.time)
    chain_run_id: Optional[str] = None

    # ── Serialization ──────────────────────────────────────────────────────

    def to_dict(self) -> Dict:
        d = asdict(self)
        return d

    @classmethod
    def from_dict(cls, d: Dict) -> "WorkflowSession":
        steps = [WorkflowStep(**s) for s in d.pop("steps", [])]
        sess = cls(**{k: v for k, v in d.items() if k != "steps"})
        sess.steps = steps
        return sess

    # ── Convenience ────────────────────────────────────────────────────────

    def add_step(self, workflow_name: str, nextflow_path: str,
                 params: Dict[str, Any], output_types: Optional[List[str]] = None) -> WorkflowStep:
        """Append a new step, auto-wiring input_from from previous step's output_types."""
        step = WorkflowStep(
            index=len(self.steps),
            workflow_name=workflow_name,
            nextflow_path=nextflow_path,
            params=params,
            output_types=output_types or [],
        )
        # Auto-wire: if previous step has output_types that match this step's likely inputs,
        # set input_from
        if self.steps:
            prev = self.steps[-1]
            if prev.output_types:
                step.input_from = prev.index
                step.input_type = prev.output_types[0] if prev.output_types else None
        self.steps.append(step)
        self.updated_at = time.time()
        return step

    def apply_modification(self, modification: "WorkflowModification") -> bool:
        """Apply a parsed modification to the appropriate step. Returns True if applied."""
        if modification.step_index is not None and modification.step_index < len(self.steps):
            target = self.steps[modification.step_index]
        elif self.steps:
            target = self.steps[-1]  # default: last step
        else:
            return False

        if modification.type == "value_change":
            target.params.update(modification.param_changes)
        elif modification.type == "skip_step":
            for flag in modification.skip_flags:
                if flag not in target.skipped_steps:
                    target.skipped_steps.append(flag)
        elif modification.type == "add_workflow":
            # Handled by caller — this adds a new step
            pass
        self.updated_at = time.time()
        return True

    def get_active_params(self, step_index: Optional[int] = None) -> Dict[str, Any]:
        """Get merged params for a step with skip flags applied."""
        idx = step_index if step_index is not None else (len(self.steps) - 1)
        if idx < 0 or idx >= len(self.steps):
            return {}
        step = self.steps[idx]
        params = dict(step.params)
        for flag in step.skipped_steps:
            params[flag] = "true"
        return params


@dataclass
class WorkflowModification:
    type: str                                    # "value_change" | "skip_step" | "add_workflow"
    step_index: Optional[int] = None            # None = last step
    param_changes: Dict[str, Any] = field(default_factory=dict)   # for value_change
    skip_flags: List[str] = field(default_factory=list)            # for skip_step
    new_workflow_name: Optional[str] = None      # for add_workflow
    new_nextflow_path: Optional[str] = None      # for add_workflow
    raw_message: str = ""                        # original user text


# ── Redis store ────────────────────────────────────────────────────────────────

_SESSION_TTL_SECONDS = 7 * 24 * 3600  # 7 days

class WorkflowSessionStore:
    """
    Thin Redis-backed store for WorkflowSession objects.
    Falls back to an in-process dict when Redis is unavailable.
    """

    def __init__(self, redis_url: Optional[str] = None):
        self._memory: Dict[str, Dict] = {}   # fallback when Redis unavailable
        self._redis: Optional[Any] = None
        if _REDIS_AVAILABLE and redis_url:
            try:
                # Use a short connect + socket timeout so a missing Redis server
                # does NOT block the worker for tens of seconds on startup.
                self._redis = redis.from_url(
                    redis_url,
                    decode_responses=True,
                    socket_connect_timeout=2,
                    socket_timeout=2,
                )
                self._redis.ping()
            except Exception:
                self._redis = None

    def get(self, session_id: str) -> Optional[WorkflowSession]:
        if self._redis:
            raw = self._redis.get(f"wfsess:{session_id}")
            if raw:
                try:
                    return WorkflowSession.from_dict(json.loads(raw))
                except Exception:
                    return None
        raw_dict = self._memory.get(session_id)
        return WorkflowSession.from_dict(dict(raw_dict)) if raw_dict else None

    def save(self, session: WorkflowSession) -> None:
        session.updated_at = time.time()
        data = json.dumps(session.to_dict())
        if self._redis:
            self._redis.setex(f"wfsess:{session.session_id}", _SESSION_TTL_SECONDS, data)
        else:
            self._memory[session.session_id] = session.to_dict()

    def delete(self, session_id: str) -> None:
        if self._redis:
            self._redis.delete(f"wfsess:{session_id}")
        self._memory.pop(session_id, None)

    def get_or_create(self, session_id: str, user_intent: str = "") -> WorkflowSession:
        sess = self.get(session_id)
        if sess is None:
            sess = WorkflowSession(session_id=session_id, user_intent=user_intent)
        return sess
