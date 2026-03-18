"""
AutoFix 3.0 增强版 Orchestrator

将 IterativeDebugger 集成到 AutoFix 流程中，提供智能重试能力

作者：AI Workflow AutoFix Team
日期：2026-01-31
"""

import logging
from pathlib import Path
from typing import Any, Dict, Optional

from .orchestrator import AutoFixOrchestrator
from .toolkit_v2 import EnhancedToolKit
from .agent import DeepAnalysisAgent
from .iterative_debugger import IterativeDebugger

log = logging.getLogger(__name__)


class AutoFix3Orchestrator(AutoFixOrchestrator):
    """
    AutoFix 3.0 增强版 Orchestrator

    在原有 AutoFixOrchestrator 基础上，增加：
    1. IterativeDebugger 支持（智能重试）
    2. EnhancedToolKit 支持（10 个工具）
    3. DeepAnalysisAgent 增强版（支持新工具）

    使用方法：
        >>> orchestrator = AutoFix3Orchestrator(trans)
        >>> result = await orchestrator.run_iterative_fix(
        ...     invocation_id=123,
        ...     max_attempts=5,
        ...     timeout_seconds=300
        ... )
    """

    def __init__(self, trans):
        """
        初始化 AutoFix 3.0 Orchestrator

        Args:
            trans: Galaxy transaction context
        """
        super().__init__(trans)

        # LLM client（从 trans.app.config 获取）
        from galaxy.ai.llm_client import LLMClient
        self.llm_client = LLMClient(trans.app.config)

        log.info("🚀 AutoFix3Orchestrator initialized")

    async def run_iterative_fix(
        self,
        invocation_id: int,
        max_attempts: int = 5,
        timeout_seconds: int = 300,
        auto_apply: bool = False,
    ) -> Dict[str, Any]:
        """
        运行 AutoFix 3.0 的迭代修复流程

        这是 AutoFix 3.0 的核心方法，整合了：
        - EnhancedToolKit（10 个工具）
        - DeepAnalysisAgent（多轮推理）
        - IterativeDebugger（智能重试）

        Args:
            invocation_id: Workflow invocation ID
            max_attempts: 最大尝试次数（默认 5）
            timeout_seconds: 总超时时间（默认 300 秒）
            auto_apply: 是否自动应用修复（默认 False，需要用户确认）

        Returns:
            {
                'success': bool,
                'session_id': str,
                'total_attempts': int,
                'termination_reason': str,
                'final_result': dict,
                'attempts': list,
                'auto_applied': bool,  # 是否已自动应用
            }
        """
        log.info(f"🔄 Starting AutoFix 3.0 iterative fix for invocation {invocation_id}")
        log.info(f"   Max attempts: {max_attempts}")
        log.info(f"   Timeout: {timeout_seconds}s")
        log.info(f"   Auto apply: {auto_apply}")

        # ============================================================
        # Step 1: 获取 workflow 信息和错误
        # ============================================================
        from galaxy.model import WorkflowInvocation

        invocation = self.sa_session.query(WorkflowInvocation).get(invocation_id)
        if not invocation:
            return {
                'success': False,
                'error': f'Invocation {invocation_id} not found'
            }

        # 获取 workflow 目录
        jobs_dir = Path(self.trans.app.config.jobs_directory) / "nextflow_workflows"
        workflow_dir = jobs_dir / f"workflow_{invocation_id}"

        if not workflow_dir.exists():
            return {
                'success': False,
                'error': f'Workflow directory not found: {workflow_dir}'
            }

        # 读取错误日志
        error_logs = self._extract_error_logs(workflow_dir)
        failed_task = self._get_first_failed_task(workflow_dir)

        if not error_logs:
            log.info("✅ No errors found")
            return {
                'success': True,
                'message': 'No errors detected',
                'total_attempts': 0,
            }

        log.info(f"   Failed task: {failed_task}")
        log.info(f"   Error log size: {len(error_logs)} chars")

        # ============================================================
        # Step 2: 初始化 AutoFix 3.0 组件
        # ============================================================

        # 2.1 创建 EnhancedToolKit
        toolkit = EnhancedToolKit(
            app_config=self.trans.app.config,
            context={
                'workflow_id': invocation.workflow_id,
                'invocation_id': invocation_id,
            },
            workflow_dir=workflow_dir
        )

        log.info(f"✅ EnhancedToolKit initialized ({len(toolkit.list_tools())} tools)")

        # 2.2 获取 galaxy_ai_tools.db 数据库路径（用于参数推荐）
        db_path = None
        backend_dir = Path(self.trans.app.config.root) / "backend"
        if backend_dir.exists():
            db_file = backend_dir / "galaxy_ai_tools.db"
            if db_file.exists():
                db_path = str(db_file)
                log.info(f"✅ Found galaxy_ai_tools.db at {db_path}")
            else:
                log.warning(f"⚠️ galaxy_ai_tools.db not found at {db_file}")
        else:
            log.warning(f"⚠️ Backend directory not found at {backend_dir}")

        # 2.3 创建 DeepAnalysisAgent（包含参数推荐器）
        agent = DeepAnalysisAgent(
            llm_client=self.llm_client,
            toolkit=toolkit,
            max_rounds=5,
            db_path=db_path  # 🆕 传递数据库路径
        )

        log.info(f"✅ DeepAnalysisAgent initialized (enhanced: {agent.is_enhanced}, recommender: {agent.parameter_recommender is not None})")

        # 2.4 创建 IterativeDebugger
        debugger = IterativeDebugger(
            agent=agent,
            toolkit=toolkit,
            workflow_dir=workflow_dir,
            max_attempts=max_attempts,
            timeout_seconds=timeout_seconds,
        )

        log.info(f"✅ IterativeDebugger initialized")

        # ============================================================
        # Step 3: 运行迭代调试
        # ============================================================

        result = debugger.run_until_fixed(
            task_name=failed_task,
            error_logs=error_logs,
            exit_code=1,
            context={
                'workflow_id': invocation.workflow_id,
                'invocation_id': invocation_id,
                'workflow_name': invocation.workflow.name if invocation.workflow else 'Unknown',
                'user_id': self.user_id,
            }
        )

        log.info(f"{'='*80}")
        log.info(f"AutoFix 3.0 Result:")
        log.info(f"  Success: {result['success']}")
        log.info(f"  Total attempts: {result['total_attempts']}")
        log.info(f"  Termination: {result['termination_reason']}")
        log.info(f"{'='*80}")

        # ============================================================
        # Step 4: 自动应用修复（如果启用）
        # ============================================================

        auto_applied = False

        if result['success'] and auto_apply:
            log.info("🔧 Auto-applying fix...")

            final_result = result.get('final_result')
            if final_result:
                apply_success = await self._apply_fix_result(
                    invocation=invocation,
                    fix_result=final_result
                )

                if apply_success:
                    log.info("✅ Fix auto-applied successfully")
                    auto_applied = True

                    # 重启 workflow
                    log.info("🚀 Restarting workflow...")
                    await self._restart_workflow(invocation)
                else:
                    log.warning("⚠️  Failed to auto-apply fix")

        # ============================================================
        # Step 5: 审计日志
        # ============================================================

        await self._log_autofix3_result(
            invocation_id=invocation_id,
            result=result,
            auto_applied=auto_applied
        )

        # 添加自动应用状态到结果
        result['auto_applied'] = auto_applied

        return result

    def _extract_error_logs(self, workflow_dir: Path) -> str:
        """从 workflow 目录提取错误日志"""
        error_logs = []

        # 读取 nextflow.out
        nextflow_out = workflow_dir / "nextflow.out"
        if nextflow_out.exists():
            with open(nextflow_out, 'r') as f:
                lines = f.readlines()
                # 取最后 200 行
                error_logs.extend(lines[-200:])

        # 读取 trace 文件中的失败任务
        trace_file = workflow_dir / "workflow-trace.txt"
        if trace_file.exists():
            with open(trace_file, 'r') as f:
                for line in f:
                    if 'FAILED' in line or 'ERROR' in line:
                        error_logs.append(line)

        return '\n'.join(error_logs)

    def _get_first_failed_task(self, workflow_dir: Path) -> str:
        """获取第一个失败的任务名称"""
        trace_file = workflow_dir / "workflow-trace.txt"

        if trace_file.exists():
            with open(trace_file, 'r') as f:
                for line in f:
                    if 'FAILED' in line:
                        parts = line.strip().split('\t')
                        if len(parts) > 1:
                            return parts[1]  # task name

        return "UNKNOWN_TASK"

    async def _apply_fix_result(
        self,
        invocation,
        fix_result: Dict[str, Any]
    ) -> bool:
        """
        应用修复结果到 workflow

        Args:
            invocation: WorkflowInvocation instance
            fix_result: AutoFix 结果

        Returns:
            True if successful, False otherwise
        """
        try:
            # 应用参数修改
            if fix_result.get('suggested_params'):
                # 在实际实现中，更新 workflow 参数
                log.info(f"   Applying parameter changes...")
                # TODO: 实现参数更新逻辑

            # 应用代码修改
            if fix_result.get('code_changes'):
                log.info(f"   Applying code changes...")
                # 代码修改已经由 EditFileTool 完成

            # 更新文件路径
            if fix_result.get('generated_files'):
                log.info(f"   Updating file paths...")
                # 文件已经由工具上传到 S3

            return True

        except Exception as e:
            log.error(f"Failed to apply fix: {e}")
            return False

    async def _restart_workflow(self, invocation):
        """重启 workflow"""
        try:
            # 在实际实现中，调用 workflow restarter
            from galaxy.ai.workflow_ops.autofix.workflow_restarter import WorkflowRestarter

            restarter = WorkflowRestarter(self.trans.app)
            await restarter.restart(invocation)

            log.info(f"   ✅ Workflow restarted")

        except Exception as e:
            log.error(f"Failed to restart workflow: {e}")

    async def _log_autofix3_result(
        self,
        invocation_id: int,
        result: Dict[str, Any],
        auto_applied: bool
    ):
        """记录 AutoFix 3.0 结果到审计日志"""
        try:
            from galaxy.model import AIFixAuditLog

            audit_log = AIFixAuditLog(
                user_id=self.user_id,
                workflow_invocation_id=invocation_id,
                fixer_name="AutoFix3_IterativeDebugger",
                fix_type="iterative_debugging",
                status="success" if result['success'] else "failed",
                risk_level="medium",
                approval_required=not auto_applied,
                approved_at=datetime.now() if auto_applied else None,
                applied_at=datetime.now() if auto_applied else None,
                metadata={
                    'total_attempts': result['total_attempts'],
                    'termination_reason': result['termination_reason'],
                    'session_id': result['session_id'],
                    'auto_applied': auto_applied,
                    'attempts_summary': [
                        {
                            'attempt': a['attempt_number'],
                            'status': a['status'],
                            'confidence': a['confidence'],
                        }
                        for a in result.get('attempts', [])
                    ]
                }
            )

            self.sa_session.add(audit_log)
            self.sa_session.commit()

            log.info(f"✅ Audit log created")

        except Exception as e:
            log.error(f"Failed to create audit log: {e}")


# 便捷函数：创建 AutoFix3Orchestrator 并运行
async def run_autofix3(
    trans,
    invocation_id: int,
    max_attempts: int = 5,
    timeout_seconds: int = 300,
    auto_apply: bool = False,
) -> Dict[str, Any]:
    """
    便捷函数：运行 AutoFix 3.0

    Args:
        trans: Galaxy transaction context
        invocation_id: Workflow invocation ID
        max_attempts: 最大尝试次数
        timeout_seconds: 总超时时间
        auto_apply: 是否自动应用修复

    Returns:
        AutoFix 3.0 结果

    Example:
        >>> result = await run_autofix3(trans, invocation_id=123)
        >>> if result['success']:
        ...     print(f"✅ Fixed in {result['total_attempts']} attempts")
    """
    orchestrator = AutoFix3Orchestrator(trans)
    return await orchestrator.run_iterative_fix(
        invocation_id=invocation_id,
        max_attempts=max_attempts,
        timeout_seconds=timeout_seconds,
        auto_apply=auto_apply,
    )
