"""
Base classes for Auto-Fix framework

Defines the abstract interface that all fixers must implement.
"""

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Any, Dict, List, Optional, Tuple

from galaxy.ai.workflow_ops.types import FixAction, FixPlan


class RiskLevel(str, Enum):
    """Risk level of a fix operation"""
    LOW = "low"         # Auto-apply safe (e.g., typo correction)
    MEDIUM = "medium"   # Requires user confirmation (e.g., increase memory)
    HIGH = "high"       # Requires manual review (e.g., AWS config change)


class FixStatus(str, Enum):
    """Status of a fix operation"""
    PENDING = "pending"           # Fix identified but not yet applied
    APPROVED = "approved"         # User/system approved
    APPLYING = "applying"         # Currently being applied
    APPLIED = "applied"           # Successfully applied
    FAILED = "failed"             # Application failed
    ROLLED_BACK = "rolled_back"   # Reverted due to failure
    REJECTED = "rejected"         # User rejected


@dataclass
class FixContext:
    """
    Context information for a fix operation

    Contains all necessary information to execute a fix safely,
    including user preferences, budget limits, and current state.
    """
    # User context
    user_id: int
    invocation_id: int
    workflow_id: int

    # User preferences (from UserCloudPreferences)
    ai_auto_fix_enabled: bool = True
    ai_auto_fix_mode: str = "safe"  # safe/moderate/aggressive/manual
    ai_require_approval_for_cost: float = 10.0  # USD
    max_memory_gb: int = 64
    max_cpus: int = 16
    max_concurrent_jobs: int = 10

    # Budget tracking
    daily_budget_remaining: float = 50.0
    monthly_budget_remaining: float = 1000.0

    # Current state snapshot (for rollback)
    state_snapshot: Optional[Dict[str, Any]] = None

    # Additional metadata
    metadata: Dict[str, Any] = field(default_factory=dict)

    def can_auto_approve(self, risk: RiskLevel, estimated_cost: float) -> bool:
        """
        Determine if a fix can be auto-approved based on user preferences

        Args:
            risk: Risk level of the fix
            estimated_cost: Estimated cost in USD

        Returns:
            True if fix can be auto-approved without user confirmation
        """
        # Check if auto-fix is enabled
        if not self.ai_auto_fix_enabled:
            return False

        # Check cost threshold
        if estimated_cost > self.ai_require_approval_for_cost:
            return False

        # Check risk level against user's auto-fix mode
        if self.ai_auto_fix_mode == "manual":
            return False
        elif self.ai_auto_fix_mode == "safe":
            return risk == RiskLevel.LOW
        elif self.ai_auto_fix_mode == "moderate":
            return risk in [RiskLevel.LOW, RiskLevel.MEDIUM]
        elif self.ai_auto_fix_mode == "aggressive":
            return risk != RiskLevel.HIGH  # Still require manual approval for high-risk

        return False

    def check_budget(self, estimated_cost: float) -> Tuple[bool, Optional[str]]:
        """
        Check if there's sufficient budget for the fix

        Args:
            estimated_cost: Estimated cost in USD

        Returns:
            (has_budget, error_message)
        """
        if estimated_cost > self.daily_budget_remaining:
            return False, f"Exceeds daily budget (remaining: ${self.daily_budget_remaining:.2f})"

        if estimated_cost > self.monthly_budget_remaining:
            return False, f"Exceeds monthly budget (remaining: ${self.monthly_budget_remaining:.2f})"

        return True, None


@dataclass
class StateSnapshot:
    """
    Snapshot of the state before applying a fix

    Used for rollback in case of failure.
    """
    timestamp: datetime
    invocation_id: int

    # Captured state (serializable)
    parameters: Dict[str, Any] = field(default_factory=dict)
    aws_config: Dict[str, Any] = field(default_factory=dict)
    input_datasets: List[Dict[str, Any]] = field(default_factory=list)

    # Additional context
    metadata: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        """Serialize snapshot to dictionary"""
        return {
            "timestamp": self.timestamp.isoformat(),
            "invocation_id": self.invocation_id,
            "parameters": self.parameters,
            "aws_config": self.aws_config,
            "input_datasets": self.input_datasets,
            "metadata": self.metadata,
        }


@dataclass
class AutoFixResult:
    """
    Result of an auto-fix operation

    Contains the outcome, any errors, and metadata for audit logging.
    """
    # Basic info
    fix_id: Optional[int]  # ID in AIFixAuditLog table
    status: FixStatus

    # Fix details
    fixer_name: str  # Name of the fixer that produced this result
    fix_type: str
    fix_actions: List[FixAction]
    risk_level: RiskLevel

    # Execution results
    success: bool
    error_message: Optional[str] = None

    # State tracking
    state_before: Optional[StateSnapshot] = None
    state_after: Optional[Dict[str, Any]] = None

    # Metadata
    estimated_cost: float = 0.0
    actual_cost: float = 0.0
    execution_time_seconds: float = 0.0
    auto_approved: bool = False
    user_approved: bool = False

    # AI metadata
    llm_model: Optional[str] = None
    llm_cost: float = 0.0
    confidence_score: Optional[float] = None

    # 🆕 原始 issue 信息（用于生成用户指导）
    original_issue: Optional[Dict[str, Any]] = None

    # Timestamps
    created_at: datetime = field(default_factory=datetime.now)
    applied_at: Optional[datetime] = None

    def to_dict(self) -> Dict[str, Any]:
        """Serialize result to dictionary for API response"""
        return {
            "fix_id": self.fix_id,
            "status": self.status.value,
            "fix_type": self.fix_type,
            "fix_actions": [action.to_dict() for action in self.fix_actions],
            "risk_level": self.risk_level.value,
            "success": self.success,
            "error_message": self.error_message,
            "estimated_cost": round(self.estimated_cost, 2),
            "actual_cost": round(self.actual_cost, 2),
            "execution_time_seconds": round(self.execution_time_seconds, 2),
            "auto_approved": self.auto_approved,
            "user_approved": self.user_approved,
            "confidence_score": self.confidence_score,
            "created_at": self.created_at.isoformat(),
            "applied_at": self.applied_at.isoformat() if self.applied_at else None,
            "original_issue": self.original_issue,  # 🔑 包含 original_issue 以便前端获取 user_guidance
        }


class BaseAutoFixer(ABC):
    """
    Abstract base class for all auto-fixers

    All fixer implementations must inherit from this class and implement
    the required methods. This ensures consistent behavior, safety checks,
    and audit logging across all fix types.

    Safety guarantees enforced by this base class:
        1. User isolation (check_permissions)
        2. Risk evaluation (evaluate_risk)
        3. Cost estimation (estimate_cost)
        4. State snapshot (capture_state)
        5. Rollback support (rollback)

    Example:
        >>> class MyFixer(BaseAutoFixer):
        ...     def detect_issues(self, context):
        ...         # Analyze and detect issues
        ...         pass
        ...
        ...     def generate_fix_plan(self, context, issues):
        ...         # Generate fix plan
        ...         pass
        ...
        ...     def apply_fix(self, context, fix_plan):
        ...         # Apply the fix
        ...         pass
    """

    def __init__(self):
        self.name = self.__class__.__name__
        self.description = self.__class__.__doc__ or "No description"

    # ========== Abstract Methods (Must Implement) ==========

    @abstractmethod
    def detect_issues(self, context: FixContext) -> List[Dict[str, Any]]:
        """
        Detect issues that this fixer can handle

        Args:
            context: Fix context with user and invocation info

        Returns:
            List of detected issues with details

        Example:
            [
                {
                    "type": "missing_parameter",
                    "parameter": "genome",
                    "severity": "high",
                    "message": "Required parameter 'genome' is missing"
                }
            ]
        """
        pass

    @abstractmethod
    def generate_fix_plan(
        self,
        context: FixContext,
        issues: List[Dict[str, Any]]
    ) -> Optional[FixPlan]:
        """
        Generate a fix plan for the detected issues

        Args:
            context: Fix context
            issues: Detected issues from detect_issues()

        Returns:
            FixPlan if fixable, None otherwise
        """
        pass

    @abstractmethod
    async def apply_fix(
        self,
        context: FixContext,
        fix_plan: FixPlan,
        sa_session: Any,  # SQLAlchemy session
    ) -> AutoFixResult:
        """
        Apply the fix plan

        This method must be idempotent and safe to retry.

        Args:
            context: Fix context
            fix_plan: Generated fix plan
            sa_session: Database session

        Returns:
            AutoFixResult with execution outcome
        """
        pass

    # ========== Optional Override Methods ==========

    def evaluate_risk(
        self,
        context: FixContext,
        fix_plan: FixPlan
    ) -> RiskLevel:
        """
        Evaluate the risk level of a fix plan

        Default implementation uses fix_plan's risk_level from fix_actions.
        Override if you need custom risk evaluation logic.

        Args:
            context: Fix context
            fix_plan: Generated fix plan

        Returns:
            Risk level (LOW/MEDIUM/HIGH)
        """
        # Default: use the highest risk level from all actions
        risk_levels = [action.risk_level for action in fix_plan.fix_actions]

        if "high" in risk_levels:
            return RiskLevel.HIGH
        elif "medium" in risk_levels:
            return RiskLevel.MEDIUM
        else:
            return RiskLevel.LOW

    def estimate_cost(
        self,
        context: FixContext,
        fix_plan: FixPlan
    ) -> float:
        """
        Estimate the cost of applying this fix (in USD)

        Default implementation returns 0.0 (no cost).
        Override for fixes that incur costs (e.g., AWS resource scaling).

        Args:
            context: Fix context
            fix_plan: Generated fix plan

        Returns:
            Estimated cost in USD
        """
        return 0.0

    def capture_state(
        self,
        context: FixContext,
        sa_session: Any
    ) -> StateSnapshot:
        """
        Capture current state for rollback

        Default implementation captures basic invocation parameters.
        Override to capture additional state specific to your fixer.

        Args:
            context: Fix context
            sa_session: Database session

        Returns:
            State snapshot
        """
        from galaxy.model import WorkflowInvocation

        invocation = sa_session.query(WorkflowInvocation).get(context.invocation_id)

        # Convert InstrumentedList to dict
        params_dict = {}
        if invocation.input_parameters:
            for param in invocation.input_parameters:
                if hasattr(param, 'name') and hasattr(param, 'value'):
                    params_dict[param.name] = param.value

        return StateSnapshot(
            timestamp=datetime.now(),
            invocation_id=context.invocation_id,
            parameters=params_dict,
            metadata={"fixer": self.name}
        )

    async def rollback(
        self,
        context: FixContext,
        snapshot: StateSnapshot,
        sa_session: Any
    ) -> bool:
        """
        Rollback to the captured state

        Default implementation restores invocation parameters.
        Override for more complex rollback logic.

        Args:
            context: Fix context
            snapshot: State snapshot from capture_state()
            sa_session: Database session

        Returns:
            True if rollback successful, False otherwise
        """
        try:
            from galaxy.model import WorkflowInvocation

            invocation = sa_session.query(WorkflowInvocation).get(context.invocation_id)
            if not invocation:
                return False

            # Restore parameters
            invocation.input_parameters = snapshot.parameters
            sa_session.commit()

            return True
        except Exception:
            return False

    def check_permissions(
        self,
        context: FixContext,
        sa_session: Any
    ) -> Tuple[bool, Optional[str]]:
        """
        Check if the fix can be applied based on user permissions

        Default implementation checks user_id match.
        Override for more complex permission logic.

        Args:
            context: Fix context
            sa_session: Database session

        Returns:
            (allowed, error_message)
        """
        from galaxy.model import WorkflowInvocation

        invocation = sa_session.query(WorkflowInvocation).get(context.invocation_id)
        if not invocation:
            return False, "Workflow invocation not found"

        # Check user ownership (user is accessed via history.user)
        if not invocation.history or invocation.history.user_id != context.user_id:
            return False, "Access denied: invocation belongs to another user"

        return True, None

    # ========== Utility Methods ==========

    def log_info(self, message: str):
        """Log info message"""
        import logging
        logging.getLogger(self.name).info(f"[{self.name}] {message}")

    def log_warning(self, message: str):
        """Log warning message"""
        import logging
        logging.getLogger(self.name).warning(f"[{self.name}] {message}")

    def log_error(self, message: str):
        """Log error message"""
        import logging
        logging.getLogger(self.name).error(f"[{self.name}] {message}")
