"""Add AutoFix / Deep Agent tables

Revision ID: a7f3deepagent
Revises: c3f8a1d20260
Create Date: 2026-05-12 00:00:00.000000

Creates the 5 tables that back the autofix v1/v3 framework, ported from
galaxy/dev (Hybrid Strategy, 2026-05-09):

  - user_cloud_preferences   : per-user budgets, AWS config, AI preferences
  - user_resource_usage      : daily resource consumption + cost tracking
  - ai_fix_audit_log         : every autofix attempt and its outcome
  - workflow_parameter_fix   : learned, persisted approved parameter fixes
  - workflow_parameter_template : per-pipeline parameter metadata & defaults
"""

import sqlalchemy as sa
from alembic import op


# revision identifiers, used by Alembic.
revision = "a7f3deepagent"
down_revision = "c3f8a1d20260"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "user_cloud_preferences",
        sa.Column("id", sa.Integer, primary_key=True),
        sa.Column("user_id", sa.Integer, sa.ForeignKey("galaxy_user.id"), unique=True, nullable=False),
        sa.Column("create_time", sa.DateTime, nullable=False),
        sa.Column("update_time", sa.DateTime, nullable=False),
        sa.Column("aws_region", sa.String(64), nullable=False, server_default="us-east-1"),
        sa.Column("aws_s3_bucket", sa.String(255), nullable=True),
        sa.Column("aws_batch_queue", sa.String(255), nullable=True),
        sa.Column("aws_access_key_id", sa.String(128), nullable=True),
        sa.Column("aws_secret_access_key", sa.String(256), nullable=True),
        sa.Column("max_memory_gb", sa.Integer, nullable=False, server_default="64"),
        sa.Column("max_cpus", sa.Integer, nullable=False, server_default="16"),
        sa.Column("max_disk_gb", sa.Integer, nullable=False, server_default="500"),
        sa.Column("max_concurrent_jobs", sa.Integer, nullable=False, server_default="10"),
        sa.Column("max_job_runtime_hours", sa.Integer, nullable=False, server_default="48"),
        sa.Column("daily_budget_usd", sa.Float, nullable=False, server_default="50.0"),
        sa.Column("monthly_budget_usd", sa.Float, nullable=False, server_default="1000.0"),
        sa.Column("enable_budget_alerts", sa.Boolean, nullable=False, server_default=sa.true()),
        sa.Column("budget_alert_threshold", sa.Float, nullable=False, server_default="0.8"),
        sa.Column("ai_auto_fix_enabled", sa.Boolean, nullable=False, server_default=sa.true()),
        sa.Column("ai_auto_fix_mode", sa.String(32), nullable=False, server_default="safe"),
        sa.Column("ai_max_fix_attempts", sa.Integer, nullable=False, server_default="3"),
        sa.Column("ai_require_approval_for_risky_fixes", sa.Boolean, nullable=False, server_default=sa.true()),
        sa.Column("ai_require_approval_for_cost", sa.Float, nullable=False, server_default="10.0"),
    )

    op.create_table(
        "user_resource_usage",
        sa.Column("id", sa.Integer, primary_key=True),
        sa.Column("user_id", sa.Integer, sa.ForeignKey("galaxy_user.id"), nullable=False),
        sa.Column("usage_date", sa.Date, nullable=False),
        sa.Column("create_time", sa.DateTime, nullable=False),
        sa.Column("update_time", sa.DateTime, nullable=False),
        sa.Column("total_memory_gb_hours", sa.Float, nullable=False, server_default="0.0"),
        sa.Column("total_cpu_hours", sa.Float, nullable=False, server_default="0.0"),
        sa.Column("total_disk_gb_hours", sa.Float, nullable=False, server_default="0.0"),
        sa.Column("total_tasks_count", sa.Integer, nullable=False, server_default="0"),
        sa.Column("successful_tasks_count", sa.Integer, nullable=False, server_default="0"),
        sa.Column("failed_tasks_count", sa.Integer, nullable=False, server_default="0"),
        sa.Column("estimated_compute_cost", sa.Float, nullable=False, server_default="0.0"),
        sa.Column("estimated_storage_cost", sa.Float, nullable=False, server_default="0.0"),
        sa.Column("estimated_transfer_cost", sa.Float, nullable=False, server_default="0.0"),
        sa.Column("estimated_total_cost", sa.Float, nullable=False, server_default="0.0"),
        sa.Column("total_ai_fixes_applied", sa.Integer, nullable=False, server_default="0"),
        sa.Column("ai_api_calls_count", sa.Integer, nullable=False, server_default="0"),
        sa.Column("ai_total_tokens", sa.Integer, nullable=False, server_default="0"),
        sa.Column("ai_estimated_cost", sa.Float, nullable=False, server_default="0.0"),
        sa.UniqueConstraint("user_id", "usage_date", name="uq_user_resource_usage_user_date"),
    )
    op.create_index("ix_user_resource_usage_user_id", "user_resource_usage", ["user_id"])
    op.create_index("ix_user_resource_usage_date", "user_resource_usage", ["usage_date"])

    op.create_table(
        "ai_fix_audit_log",
        sa.Column("id", sa.Integer, primary_key=True),
        sa.Column("user_id", sa.Integer, sa.ForeignKey("galaxy_user.id"), nullable=False),
        sa.Column("invocation_id", sa.Integer, sa.ForeignKey("workflow_invocation.id"), nullable=False),
        sa.Column("create_time", sa.DateTime, nullable=False),
        sa.Column("fix_type", sa.String(64), nullable=False),
        sa.Column("fix_details", sa.JSON, nullable=False),
        sa.Column("fix_reason", sa.Text, nullable=True),
        sa.Column("risk_level", sa.String(32), nullable=False),
        sa.Column("auto_approved", sa.Boolean, nullable=False, server_default=sa.false()),
        sa.Column("user_approved", sa.Boolean, nullable=False, server_default=sa.false()),
        sa.Column("approval_time", sa.DateTime, nullable=True),
        sa.Column("execution_start_time", sa.DateTime, nullable=True),
        sa.Column("execution_end_time", sa.DateTime, nullable=True),
        sa.Column("applied", sa.Boolean, nullable=False, server_default=sa.false()),
        sa.Column("success", sa.Boolean, nullable=False, server_default=sa.false()),
        sa.Column("error_message", sa.Text, nullable=True),
        sa.Column("execution_time", sa.DateTime, nullable=True),
        sa.Column("duration_seconds", sa.Float, nullable=True),
        sa.Column("resources_before", sa.JSON, nullable=True),
        sa.Column("resources_after", sa.JSON, nullable=True),
        sa.Column("llm_model", sa.String(64), nullable=True),
        sa.Column("llm_tokens", sa.Integer, nullable=False, server_default="0"),
        sa.Column("llm_cost", sa.Float, nullable=False, server_default="0.0"),
    )
    op.create_index("ix_ai_fix_audit_log_user_id", "ai_fix_audit_log", ["user_id"])
    op.create_index("ix_ai_fix_audit_log_invocation_id", "ai_fix_audit_log", ["invocation_id"])
    op.create_index("ix_ai_fix_audit_log_create_time", "ai_fix_audit_log", ["create_time"])

    op.create_table(
        "workflow_parameter_fix",
        sa.Column("id", sa.Integer, primary_key=True),
        sa.Column("workflow_id", sa.Integer, sa.ForeignKey("workflow.id"), nullable=False),
        sa.Column("source_invocation_id", sa.Integer, sa.ForeignKey("workflow_invocation.id"), nullable=True),
        sa.Column("parameter_name", sa.String(255), nullable=False),
        sa.Column("fix_type", sa.String(64), nullable=False),
        sa.Column("current_value", sa.Text, nullable=True),
        sa.Column("recommended_value", sa.Text, nullable=False),
        sa.Column("reason", sa.Text, nullable=False),
        sa.Column("ai_analysis", sa.JSON, nullable=True),
        sa.Column("status", sa.String(32), nullable=False, server_default="pending"),
        sa.Column("risk_level", sa.String(32), nullable=False),
        sa.Column("auto_apply", sa.Boolean, nullable=False, server_default=sa.false()),
        sa.Column("applied_count", sa.Integer, nullable=False, server_default="0"),
        sa.Column("last_applied", sa.DateTime, nullable=True),
        sa.Column("create_time", sa.DateTime, nullable=False),
        sa.Column("update_time", sa.DateTime, nullable=False),
        sa.Column("user_id", sa.Integer, sa.ForeignKey("galaxy_user.id"), nullable=False),
    )
    op.create_index("ix_workflow_parameter_fix_workflow_id", "workflow_parameter_fix", ["workflow_id"])

    op.create_table(
        "workflow_parameter_template",
        sa.Column("id", sa.Integer, primary_key=True),
        sa.Column("pipeline_name", sa.String(128), nullable=False),
        sa.Column("pipeline_version", sa.String(32), nullable=True),
        sa.Column("parameter_name", sa.String(255), nullable=False),
        sa.Column("is_required", sa.Boolean, nullable=False, server_default=sa.false()),
        sa.Column("parameter_type", sa.String(64), nullable=True),
        sa.Column("default_value", sa.Text, nullable=True),
        sa.Column("description", sa.Text, nullable=True),
        sa.Column("validation_rules", sa.JSON, nullable=True),
        sa.Column("common_errors", sa.JSON, nullable=True),
        sa.Column("aws_defaults", sa.JSON, nullable=True),
        sa.Column("create_time", sa.DateTime, nullable=False),
        sa.Column("update_time", sa.DateTime, nullable=False),
    )
    op.create_index("ix_workflow_parameter_template_pipeline_name", "workflow_parameter_template", ["pipeline_name"])


def downgrade():
    op.drop_table("workflow_parameter_template")
    op.drop_table("workflow_parameter_fix")
    op.drop_table("ai_fix_audit_log")
    op.drop_table("user_resource_usage")
    op.drop_table("user_cloud_preferences")
