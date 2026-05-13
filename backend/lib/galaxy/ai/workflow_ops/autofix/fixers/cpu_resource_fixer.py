"""
CPU Resource Fixer
处理 CPU 资源不足导致的 workflow 失败
"""

import logging
import re
from typing import Dict, List, Optional

from galaxy.ai.workflow_ops.autofix.base import BaseAutoFixer, FixContext, AutoFixResult
from galaxy.ai.workflow_ops.types import (
    ActionType,
    FixAction,
    FixPlan,
)

log = logging.getLogger(__name__)


class CPUResourceFixer(BaseAutoFixer):
    """
    修复 CPU 资源不足问题

    处理场景：
    1. Process requirement exceeds available CPUs
    2. 工具要求的 CPU 超过系统可用 CPU
    3. max_cpus 参数设置不当
    """

    def __init__(self):
        super().__init__()

    def detect_issues(self, context: FixContext) -> List[Dict]:
        """
        检测 CPU 资源问题

        检查：
        1. Nextflow 错误日志中的 CPU 不足错误
        2. trace file 中失败任务的 CPU 需求
        3. 系统可用 CPU vs 任务需求 CPU

        Returns:
            List of detected CPU issues
        """
        log.info(f"🔍 {self.name} 检测 CPU 资源问题...")

        issues = []

        # 1. 检查 nextflow.out 中的 CPU 错误
        nextflow_out = self._read_nextflow_out(context)
        if nextflow_out:
            cpu_errors = self._parse_cpu_errors(nextflow_out)
            if cpu_errors:
                issues.extend(cpu_errors)
                log.info(f"  ✓ 发现 {len(cpu_errors)} 个 CPU 不足错误")

        # 2. 检查 trace file 中的任务失败
        if context.trace_file_path:
            trace_issues = self._check_trace_cpu_issues(context)
            if trace_issues:
                issues.extend(trace_issues)
                log.info(f"  ✓ 从 trace file 发现 {len(trace_issues)} 个 CPU 问题")

        if not issues:
            log.info("  ℹ️  未发现 CPU 资源问题")

        return issues

    def _read_nextflow_out(self, context: FixContext) -> Optional[str]:
        """读取 nextflow.out 文件"""
        import os

        work_dir = context.work_dir
        if not work_dir:
            return None

        out_path = os.path.join(work_dir, 'nextflow.out')
        if not os.path.exists(out_path):
            return None

        try:
            with open(out_path, 'r', encoding='utf-8', errors='ignore') as f:
                return f.read()
        except Exception as e:
            log.warning(f"Failed to read nextflow.out: {e}")
            return None

    def _parse_cpu_errors(self, nextflow_out: str) -> List[Dict]:
        """
        解析 nextflow.out 中的 CPU 错误

        示例错误：
        ERROR ~ Error executing process > 'STAR_GENOMEGENERATE (chr22.fa)'

        Caused by:
          Process requirement exceeds available CPUs -- req: 12; avail: 8
        """
        cpu_errors = []

        # 正则匹配 CPU 不足错误
        pattern = r'Process requirement exceeds available CPUs -- req: (\d+); avail: (\d+)'
        matches = re.finditer(pattern, nextflow_out)

        for match in matches:
            required_cpus = int(match.group(1))
            available_cpus = int(match.group(2))

            # 提取进程名称（向上查找）
            error_start = max(0, match.start() - 500)
            error_context = nextflow_out[error_start:match.end()]

            process_match = re.search(r"Error executing process > '([^']+)'", error_context)
            process_name = process_match.group(1) if process_match else "Unknown"

            cpu_errors.append({
                'type': 'cpu_insufficient',
                'process': process_name,
                'required_cpus': required_cpus,
                'available_cpus': available_cpus,
                'description': f'进程 {process_name} 要求 {required_cpus} CPU，但系统只有 {available_cpus} 可用'
            })

            log.info(f"  ✓ CPU 不足: {process_name} 需要 {required_cpus}, 可用 {available_cpus}")

        return cpu_errors

    def _check_trace_cpu_issues(self, context: FixContext) -> List[Dict]:
        """检查 trace file 中的 CPU 相关问题"""
        import os

        trace_path = context.trace_file_path
        if not os.path.exists(trace_path):
            return []

        try:
            with open(trace_path, 'r') as f:
                lines = f.readlines()

            if len(lines) < 2:
                return []

            # 解析 header
            header = lines[0].strip().split('\t')
            cpus_idx = header.index('cpus') if 'cpus' in header else None
            status_idx = header.index('status') if 'status' in header else None
            name_idx = header.index('name') if 'name' in header else None

            if not all([cpus_idx, status_idx, name_idx]):
                return []

            issues = []
            for line in lines[1:]:
                fields = line.strip().split('\t')
                if len(fields) <= max(cpus_idx, status_idx, name_idx):
                    continue

                status = fields[status_idx]
                if status == 'FAILED':
                    cpus_requested = fields[cpus_idx]
                    task_name = fields[name_idx]

                    # 检查是否是因为 CPU 不足失败
                    # (这需要结合错误日志，这里先记录)
                    log.debug(f"  Failed task {task_name} requested {cpus_requested} CPUs")

            return issues

        except Exception as e:
            log.warning(f"Failed to parse trace file: {e}")
            return []

    def generate_fix_plan(self, context: FixContext, issues: List[Dict]) -> Optional[FixPlan]:
        """
        生成 CPU 资源修复计划

        Args:
            context: Fix context
            issues: Detected CPU issues from detect_issues()

        策略：
        1. 设置 max_cpus 为系统可用 CPU 数量
        2. 如果已经设置了 max_cpus，检查是否合理

        Returns:
            FixPlan or None if no issues
        """
        if not issues:
            return None

        # 找出最小的可用 CPU 数量
        min_available_cpus = min(issue['available_cpus'] for issue in issues)

        fix_actions = []

        # 生成修复动作
        fix_action = FixAction(
            action=ActionType.UPDATE_PARAM,
            params={
                'max_cpus': min_available_cpus
            },
            description=f'限制 CPU 使用到 {min_available_cpus} 核（系统可用）',
            risk_level='low'
        )
        fix_actions.append(fix_action)

        # 汇总说明
        affected_processes = [issue['process'] for issue in issues]
        explanation = (
            f"检测到 {len(issues)} 个进程因 CPU 不足失败：\n\n"
            f"**受影响的进程**：\n"
        )
        for issue in issues[:5]:  # 最多显示 5 个
            explanation += f"- {issue['process']}: 需要 {issue['required_cpus']} CPU, 可用 {issue['available_cpus']}\n"

        if len(issues) > 5:
            explanation += f"- ... 还有 {len(issues) - 5} 个进程\n"

        explanation += f"\n**修复方案**：设置 `max_cpus: {min_available_cpus}` 限制所有进程的 CPU 使用"

        return FixPlan(
            fixer_name=self.name,
            explanation=explanation,
            fix_actions=fix_actions,
            confidence_score=0.95,  # 高置信度
            estimated_cost=0.0,
            risk_level='low'
        )

    async def apply_fix(
        self,
        context: FixContext,
        fix_plan: FixPlan,
        sa_session
    ) -> AutoFixResult:
        """
        应用 CPU 资源修复

        这个 fixer 只生成参数建议，不直接修改配置
        实际的参数应用由 orchestrator 处理

        Args:
            context: Fix context
            fix_plan: Generated fix plan
            sa_session: SQLAlchemy session

        Returns:
            AutoFixResult
        """
        log.info(f"📦 {self.name} applying fix with {len(fix_plan.fix_actions)} actions")

        # 记录修复参数
        fixed_params = {}
        for action in fix_plan.fix_actions:
            if action.params:
                fixed_params.update(action.params)
                for key, value in action.params.items():
                    log.info(f"  ✅ Setting parameter: {key} = {value}")

        return AutoFixResult(
            success=True,
            fix_plan=fix_plan,
            fix_actions=fix_plan.fix_actions,
            risk_level=fix_plan.risk_level,
            message=f"建议设置 max_cpus 参数限制 CPU 使用",
            state_after={
                'fixed_params': fixed_params
            }
        )
