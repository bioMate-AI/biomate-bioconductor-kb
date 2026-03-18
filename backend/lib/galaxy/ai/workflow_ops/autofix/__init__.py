"""
Auto-Fix Framework for Workflow AI Operations

This module provides a secure, auditable, and extensible framework for automatically
fixing workflow execution issues at the user level.

Architecture:
    - BaseAutoFixer: Abstract base class for all fixers
    - RiskEvaluator: Evaluates fix risk (low/medium/high)
    - PermissionChecker: Ensures user isolation and access control
    - CostEstimator: Estimates cost impact of fixes
    - Executor: Applies fixes with rollback support
    - AuditLogger: Records all fix operations

Safety Guarantees:
    1. User Isolation: All fixes are scoped to the requesting user
    2. Risk-Based Approval: High-risk fixes require user confirmation
    3. Cost Control: Expensive fixes require budget approval
    4. Audit Trail: All operations are logged with before/after state
    5. Rollback Support: Failed fixes can be automatically reverted

Example Usage:
    >>> from galaxy.ai.workflow_ops.autofix import AutoFixOrchestrator
    >>> from galaxy.ai.workflow_ops.autofix.fixers import NextflowParameterFixer
    >>>
    >>> orchestrator = AutoFixOrchestrator(trans)
    >>> fixer = NextflowParameterFixer()
    >>> result = await orchestrator.apply_fix(
    ...     invocation_id=123,
    ...     fixer=fixer,
    ...     auto_approve_low_risk=True
    ... )
"""

from galaxy.ai.workflow_ops.autofix.base import (
    BaseAutoFixer,
    AutoFixResult,
    FixContext,
    RiskLevel,
    FixStatus,
    StateSnapshot,
)

# AutoFixOrchestrator depends on galaxy.model (full Galaxy stack).
# Guard the import so the autofix package can be loaded without the Galaxy web
# process running (e.g. during standalone testing or worker processes).
try:
    from galaxy.ai.workflow_ops.autofix.orchestrator import AutoFixOrchestrator
    _ORCHESTRATOR_AVAILABLE = True
except ImportError:
    AutoFixOrchestrator = None  # type: ignore[assignment,misc]
    _ORCHESTRATOR_AVAILABLE = False

__all__ = [
    "BaseAutoFixer",
    "AutoFixResult",
    "FixContext",
    "RiskLevel",
    "FixStatus",
    "StateSnapshot",
    "AutoFixOrchestrator",
]
