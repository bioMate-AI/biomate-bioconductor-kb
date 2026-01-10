"""
User Context for Benchmark Evaluation

Provides per-user, per-project, and per-dataset context for the test harness.
Each user has their own benchmark configuration, results, and evaluation history.
"""

import logging
import json
import sqlite3
from typing import Dict, List, Any, Optional
from dataclasses import dataclass, field, asdict
from datetime import datetime
from pathlib import Path
from enum import Enum

log = logging.getLogger(__name__)


class EvaluationDomain(str, Enum):
    """Scientific domains for evaluation (aligned with SGI-Bench)."""
    LIFE_SCIENCE = "life_science"
    CHEMISTRY = "chemistry"
    PHYSICS = "physics"
    ASTRONOMY = "astronomy"
    GENERAL = "general"


class EvaluationTask(str, Enum):
    """Evaluation task types (aligned with SGI-Bench PIM model)."""
    # Deliberation
    DEEP_RESEARCH = "deep_research"

    # Conception
    IDEA_GENERATION = "idea_generation"

    # Action
    DRY_EXPERIMENT = "dry_experiment"  # Code generation
    WET_EXPERIMENT = "wet_experiment"  # Lab protocols

    # Perception
    REASONING = "reasoning"


@dataclass
class UserDataset:
    """A user's dataset for benchmarking."""
    dataset_id: str
    name: str
    path: str
    domain: EvaluationDomain
    data_type: str  # e.g., "scRNA-seq", "proteomics", "imaging"
    species: str = ""
    sample_count: int = 0
    size_mb: float = 0.0
    ground_truth_path: Optional[str] = None
    metadata: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        return {
            **asdict(self),
            "domain": self.domain.value
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "UserDataset":
        data = data.copy()
        if isinstance(data.get("domain"), str):
            data["domain"] = EvaluationDomain(data["domain"])
        return cls(**data)


@dataclass
class UserProject:
    """A user's project containing multiple datasets and benchmark configurations."""
    project_id: str
    name: str
    description: str = ""
    domain: EvaluationDomain = EvaluationDomain.LIFE_SCIENCE
    datasets: List[UserDataset] = field(default_factory=list)
    default_tools: List[str] = field(default_factory=list)
    created_at: str = field(default_factory=lambda: datetime.now().isoformat())
    metadata: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "project_id": self.project_id,
            "name": self.name,
            "description": self.description,
            "domain": self.domain.value,
            "datasets": [d.to_dict() for d in self.datasets],
            "default_tools": self.default_tools,
            "created_at": self.created_at,
            "metadata": self.metadata
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "UserProject":
        data = data.copy()
        if isinstance(data.get("domain"), str):
            data["domain"] = EvaluationDomain(data["domain"])
        if "datasets" in data:
            data["datasets"] = [UserDataset.from_dict(d) for d in data["datasets"]]
        return cls(**data)

    def add_dataset(self, dataset: UserDataset):
        """Add a dataset to this project."""
        self.datasets.append(dataset)

    def get_dataset(self, dataset_id: str) -> Optional[UserDataset]:
        """Get a dataset by ID."""
        for dataset in self.datasets:
            if dataset.dataset_id == dataset_id:
                return dataset
        return None


@dataclass
class EvaluationCriteria:
    """Evaluation criteria for a specific task type (aligned with SGI-Bench)."""
    task_type: EvaluationTask
    metrics: List[str]
    rubric: Dict[str, str] = field(default_factory=dict)
    few_shot_examples: List[Dict[str, Any]] = field(default_factory=list)
    scoring_weights: Dict[str, float] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "task_type": self.task_type.value,
            "metrics": self.metrics,
            "rubric": self.rubric,
            "few_shot_examples": self.few_shot_examples,
            "scoring_weights": self.scoring_weights
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "EvaluationCriteria":
        data = data.copy()
        if isinstance(data.get("task_type"), str):
            data["task_type"] = EvaluationTask(data["task_type"])
        return cls(**data)


@dataclass
class UserBenchmarkContext:
    """
    Per-user benchmark context containing:
    - User identification
    - Projects with datasets
    - Evaluation criteria
    - Benchmark history
    """
    user_id: str
    username: str = ""
    projects: Dict[str, UserProject] = field(default_factory=dict)
    evaluation_criteria: Dict[str, EvaluationCriteria] = field(default_factory=dict)
    preferences: Dict[str, Any] = field(default_factory=dict)
    created_at: str = field(default_factory=lambda: datetime.now().isoformat())

    def to_dict(self) -> Dict[str, Any]:
        return {
            "user_id": self.user_id,
            "username": self.username,
            "projects": {k: v.to_dict() for k, v in self.projects.items()},
            "evaluation_criteria": {k: v.to_dict() for k, v in self.evaluation_criteria.items()},
            "preferences": self.preferences,
            "created_at": self.created_at
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "UserBenchmarkContext":
        data = data.copy()
        if "projects" in data:
            data["projects"] = {
                k: UserProject.from_dict(v) for k, v in data["projects"].items()
            }
        if "evaluation_criteria" in data:
            data["evaluation_criteria"] = {
                k: EvaluationCriteria.from_dict(v) for k, v in data["evaluation_criteria"].items()
            }
        return cls(**data)

    def add_project(self, project: UserProject):
        """Add a project to this user's context."""
        self.projects[project.project_id] = project

    def get_project(self, project_id: str) -> Optional[UserProject]:
        """Get a project by ID."""
        return self.projects.get(project_id)

    def set_evaluation_criteria(self, task_type: EvaluationTask, criteria: EvaluationCriteria):
        """Set evaluation criteria for a task type."""
        self.evaluation_criteria[task_type.value] = criteria

    def get_evaluation_criteria(self, task_type: EvaluationTask) -> Optional[EvaluationCriteria]:
        """Get evaluation criteria for a task type."""
        return self.evaluation_criteria.get(task_type.value)


class UserContextDB:
    """Database for storing user benchmark contexts."""

    def __init__(self, db_path: str = None):
        if db_path is None:
            db_path = Path(__file__).parent.parent.parent.parent.parent / "database" / "user_benchmark_context.db"

        self.db_path = str(db_path)
        self._init_schema()

    def _init_schema(self):
        """Initialize database schema."""
        conn = sqlite3.connect(self.db_path)
        try:
            cursor = conn.cursor()

            cursor.execute("""
                CREATE TABLE IF NOT EXISTS user_contexts (
                    user_id TEXT PRIMARY KEY,
                    username TEXT,
                    context_json JSON NOT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)

            cursor.execute("""
                CREATE TABLE IF NOT EXISTS user_evaluation_history (
                    id INTEGER PRIMARY KEY,
                    user_id TEXT NOT NULL,
                    project_id TEXT,
                    dataset_id TEXT,
                    task_type TEXT,
                    evaluation_json JSON NOT NULL,
                    score FLOAT,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    FOREIGN KEY (user_id) REFERENCES user_contexts(user_id)
                )
            """)

            cursor.execute("""
                CREATE INDEX IF NOT EXISTS idx_user_eval_history_user
                ON user_evaluation_history(user_id)
            """)

            cursor.execute("""
                CREATE INDEX IF NOT EXISTS idx_user_eval_history_project
                ON user_evaluation_history(user_id, project_id)
            """)

            conn.commit()
        finally:
            conn.close()

    def save_context(self, context: UserBenchmarkContext) -> bool:
        """Save or update a user's benchmark context."""
        conn = sqlite3.connect(self.db_path)
        try:
            cursor = conn.cursor()

            cursor.execute("""
                INSERT OR REPLACE INTO user_contexts (user_id, username, context_json, updated_at)
                VALUES (?, ?, ?, CURRENT_TIMESTAMP)
            """, (
                context.user_id,
                context.username,
                json.dumps(context.to_dict())
            ))

            conn.commit()
            return True
        except Exception as e:
            log.error(f"Failed to save user context: {e}")
            return False
        finally:
            conn.close()

    def load_context(self, user_id: str) -> Optional[UserBenchmarkContext]:
        """Load a user's benchmark context."""
        conn = sqlite3.connect(self.db_path)
        try:
            cursor = conn.cursor()

            cursor.execute("""
                SELECT context_json FROM user_contexts WHERE user_id = ?
            """, (user_id,))

            row = cursor.fetchone()
            if not row:
                return None

            data = json.loads(row[0])
            return UserBenchmarkContext.from_dict(data)
        except Exception as e:
            log.error(f"Failed to load user context: {e}")
            return None
        finally:
            conn.close()

    def save_evaluation(
        self,
        user_id: str,
        project_id: str,
        dataset_id: str,
        task_type: EvaluationTask,
        evaluation: Dict[str, Any],
        score: float
    ) -> int:
        """Save an evaluation result for a user."""
        conn = sqlite3.connect(self.db_path)
        try:
            cursor = conn.cursor()

            cursor.execute("""
                INSERT INTO user_evaluation_history
                (user_id, project_id, dataset_id, task_type, evaluation_json, score)
                VALUES (?, ?, ?, ?, ?, ?)
            """, (
                user_id,
                project_id,
                dataset_id,
                task_type.value,
                json.dumps(evaluation),
                score
            ))

            conn.commit()
            return cursor.lastrowid
        except Exception as e:
            log.error(f"Failed to save evaluation: {e}")
            return -1
        finally:
            conn.close()

    def get_evaluation_history(
        self,
        user_id: str,
        project_id: str = None,
        task_type: EvaluationTask = None,
        limit: int = 100
    ) -> List[Dict[str, Any]]:
        """Get evaluation history for a user."""
        conn = sqlite3.connect(self.db_path)
        try:
            cursor = conn.cursor()

            query = """
                SELECT id, project_id, dataset_id, task_type, evaluation_json, score, created_at
                FROM user_evaluation_history
                WHERE user_id = ?
            """
            params = [user_id]

            if project_id:
                query += " AND project_id = ?"
                params.append(project_id)

            if task_type:
                query += " AND task_type = ?"
                params.append(task_type.value)

            query += " ORDER BY created_at DESC LIMIT ?"
            params.append(limit)

            cursor.execute(query, params)

            results = []
            for row in cursor.fetchall():
                results.append({
                    "id": row[0],
                    "project_id": row[1],
                    "dataset_id": row[2],
                    "task_type": row[3],
                    "evaluation": json.loads(row[4]),
                    "score": row[5],
                    "created_at": row[6]
                })

            return results
        except Exception as e:
            log.error(f"Failed to get evaluation history: {e}")
            return []
        finally:
            conn.close()

    def list_users(self, limit: int = 100) -> List[Dict[str, Any]]:
        """List all users with contexts."""
        conn = sqlite3.connect(self.db_path)
        try:
            cursor = conn.cursor()

            cursor.execute("""
                SELECT user_id, username, created_at, updated_at
                FROM user_contexts
                ORDER BY updated_at DESC
                LIMIT ?
            """, (limit,))

            results = []
            for row in cursor.fetchall():
                results.append({
                    "user_id": row[0],
                    "username": row[1],
                    "created_at": row[2],
                    "updated_at": row[3]
                })

            return results
        except Exception as e:
            log.error(f"Failed to list users: {e}")
            return []
        finally:
            conn.close()


def create_default_evaluation_criteria() -> Dict[str, EvaluationCriteria]:
    """
    Create default evaluation criteria aligned with SGI-Bench.
    These serve as templates that users can customize.
    """
    criteria = {}

    # Deep Research (Deliberation)
    criteria[EvaluationTask.DEEP_RESEARCH.value] = EvaluationCriteria(
        task_type=EvaluationTask.DEEP_RESEARCH,
        metrics=["step_accuracy", "final_answer_accuracy", "reasoning_validity"],
        rubric={
            "step_accuracy": "Accuracy at each reasoning step (0-100%)",
            "final_answer_accuracy": "Strict match of final conclusion (0-100%)",
            "reasoning_validity": "Logical validity of the reasoning chain (0-100%)"
        },
        scoring_weights={
            "step_accuracy": 0.3,
            "final_answer_accuracy": 0.5,
            "reasoning_validity": 0.2
        }
    )

    # Idea Generation (Conception)
    criteria[EvaluationTask.IDEA_GENERATION.value] = EvaluationCriteria(
        task_type=EvaluationTask.IDEA_GENERATION,
        metrics=["novelty", "feasibility", "workflow_coherence"],
        rubric={
            "novelty": "Originality of the proposed idea (0-100)",
            "feasibility": "Practical implementability (0-100)",
            "workflow_coherence": "Interface alignment and step dependencies (0-100)"
        },
        scoring_weights={
            "novelty": 0.3,
            "feasibility": 0.5,
            "workflow_coherence": 0.2
        }
    )

    # Dry Experiment (Code Generation)
    criteria[EvaluationTask.DRY_EXPERIMENT.value] = EvaluationCriteria(
        task_type=EvaluationTask.DRY_EXPERIMENT,
        metrics=["execution_success", "unit_test_pass_rate", "scientific_correctness"],
        rubric={
            "execution_success": "Code runs without errors (0-100%)",
            "unit_test_pass_rate": "Percentage of unit tests passing (0-100%)",
            "scientific_correctness": "Correctness of scientific logic (0-100%)"
        },
        scoring_weights={
            "execution_success": 0.2,
            "unit_test_pass_rate": 0.4,
            "scientific_correctness": 0.4
        }
    )

    # Wet Experiment (Lab Protocols)
    criteria[EvaluationTask.WET_EXPERIMENT.value] = EvaluationCriteria(
        task_type=EvaluationTask.WET_EXPERIMENT,
        metrics=["sequence_similarity", "parameter_accuracy", "temporal_coherence"],
        rubric={
            "sequence_similarity": "Action sequence matches reference (0-100%)",
            "parameter_accuracy": "Correct parameter values (0-100%)",
            "temporal_coherence": "Proper timing and branching logic (0-100%)"
        },
        scoring_weights={
            "sequence_similarity": 0.4,
            "parameter_accuracy": 0.3,
            "temporal_coherence": 0.3
        }
    )

    # Reasoning (Perception)
    criteria[EvaluationTask.REASONING.value] = EvaluationCriteria(
        task_type=EvaluationTask.REASONING,
        metrics=["answer_accuracy", "reasoning_validity", "comparative_ability"],
        rubric={
            "answer_accuracy": "Correctness of final answer (0-100%)",
            "reasoning_validity": "Validity of reasoning process (0-100%)",
            "comparative_ability": "Cross-sample comparison capability (0-100%)"
        },
        scoring_weights={
            "answer_accuracy": 0.5,
            "reasoning_validity": 0.3,
            "comparative_ability": 0.2
        }
    )

    return criteria


def get_or_create_user_context(user_id: str, username: str = "") -> UserBenchmarkContext:
    """
    Get an existing user context or create a new one with defaults.

    Args:
        user_id: The user's ID
        username: Optional username

    Returns:
        UserBenchmarkContext for the user
    """
    db = UserContextDB()

    # Try to load existing context
    context = db.load_context(user_id)

    if context is None:
        # Create new context with default evaluation criteria
        context = UserBenchmarkContext(
            user_id=user_id,
            username=username,
            evaluation_criteria=create_default_evaluation_criteria()
        )
        db.save_context(context)

    return context
