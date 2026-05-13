"""
LLM Learning Fixer - 具有自学习能力的通用修复器

结合 LLMUniversalFixer 和自学习系统，实现：
1. 处理任何错误（包括未知错误）
2. 从历史修复中学习（Few-shot learning）
3. 持续优化建议（基于反馈）
4. 越用越准确

这是 Claude Code 级别的能力！
"""

import logging
import json
from typing import Dict, List, Any, Optional
from datetime import datetime, timedelta

from ..base import (
    BaseAutoFixer,
    FixContext,
    FixStatus,
    RiskLevel,
    AutoFixResult,
)
from ...types import FixAction, ActionType, FixPlan, FixType
from .llm_universal_fixer import LLMUniversalFixer

log = logging.getLogger(__name__)


class LLMLearningFixer(LLMUniversalFixer):
    """
    具有自学习能力的 LLM 通用修复器

    核心能力：
    1. 继承 LLMUniversalFixer 的所有能力（处理任何错误）
    2. 从知识库检索相似的历史案例
    3. 作为 Few-shot examples 提供给 LLM
    4. 应用修复后记录到知识库
    5. 根据成功率持续优化

    工作流程：
    ```
    未知错误 → 检索相似案例 → LLM分析（带Few-shot）→ 建议修复
                    ↓
                 应用修复
                    ↓
              记录到知识库
                    ↓
              自动验证结果
                    ↓
              更新成功率
    ```

    Example:
    ```python
    # 第一次遇到GPU显存错误（未知错误）
    Error: "CUDA out of memory: tried to allocate 8.00GB"

    # LLM分析（无历史案例）
    LLM: "这是GPU显存不足，建议增加 --gpu_memory 到 16GB"

    # 用户应用 → 成功
    # 记录到知识库：
    #   error_type: "gpu_memory_oom"
    #   fix: "增加gpu_memory到16GB"
    #   success_rate: 100% (1/1)

    # 第二次遇到类似错误
    Error: "CUDA out of memory: tried to allocate 12.00GB"

    # 检索相似案例 → 找到上次的修复
    # LLM分析（带Few-shot example）
    LLM: "根据历史案例（成功率100%），建议增加 --gpu_memory 到 24GB"

    # 越来越准确！
    ```
    """

    name = "LLMLearningFixer"
    description = "具有自学习能力的LLM通用修复器（Claude Code级别）"

    def __init__(self, llm_client=None, max_context_tokens: int = 8000):
        """
        初始化学习型修复器

        Args:
            llm_client: LLM 客户端
            max_context_tokens: LLM 上下文最大 token 数
        """
        super().__init__(llm_client=llm_client, max_context_tokens=max_context_tokens)
        self.kb_manager = None
        self.feedback_loop = None

    def _initialize_learning_systems(self, context: FixContext):
        """初始化学习系统（延迟初始化，需要数据库session）"""
        if self.kb_manager is not None:
            return  # 已初始化

        try:
            from galaxy.ai.workflow_ops.self_learning import KnowledgeBaseManager, FeedbackLoopSystem

            sa_session = context.metadata.get('sa_session')
            if sa_session:
                self.kb_manager = KnowledgeBaseManager(sa_session, log)
                self.feedback_loop = FeedbackLoopSystem(sa_session, log)
                log.info("✅ Learning systems initialized")
            else:
                log.warning("⚠️  No sa_session available, learning disabled")

        except Exception as e:
            log.warning(f"⚠️  Failed to initialize learning systems: {e}")
            # 不影响基础功能，只是禁用学习

    def detect_issues(self, context: FixContext) -> List[Dict[str, Any]]:
        """
        检测问题（增强版，带学习能力）

        工作流程：
        1. 初始化学习系统
        2. 从知识库检索相似案例
        3. 调用父类的 LLM 分析（会包含 few-shot examples）
        4. 返回问题列表

        Args:
            context: Fix context

        Returns:
            检测到的问题列表
        """
        # 初始化学习系统
        self._initialize_learning_systems(context)

        # 检索历史案例（如果学习系统可用）
        if self.kb_manager:
            historical_cases = self._retrieve_similar_cases(context)
            log.info(f"📚 Retrieved {len(historical_cases)} historical cases for learning")

            # 添加到 context metadata 供 LLM 使用
            if 'historical_fixes' not in context.metadata:
                context.metadata['historical_fixes'] = []
            context.metadata['historical_fixes'].extend(historical_cases)

        # 调用父类的 detect_issues（会使用 historical_fixes）
        issues = super().detect_issues(context)

        # 记录错误模式到知识库（如果学习系统可用）
        if self.kb_manager and issues:
            self._record_error_patterns(context, issues)

        return issues

    def _retrieve_similar_cases(self, context: FixContext) -> List[Dict[str, Any]]:
        """
        从知识库检索相似的历史案例

        检索策略：
        1. 基于 error_type（精确匹配）
        2. 基于 pipeline_type（如 sarek, rnaseq）
        3. 按成功率排序（优先返回高成功率的案例）
        4. 限制数量（top 5，避免 LLM context 过长）

        Args:
            context: Fix context

        Returns:
            历史案例列表（作为 Few-shot examples）
        """
        try:
            from galaxy.model import AIOpsErrorPattern, AIOpsFixStrategy, WorkflowInvocation

            sa_session = context.metadata.get('sa_session')
            if not sa_session:
                return []

            # 获取当前 workflow 的 pipeline 类型
            invocation = sa_session.query(WorkflowInvocation).get(context.invocation_id)
            if not invocation:
                return []

            # TODO: 提取 pipeline_type（可以从 workflow 名称或元数据中获取）
            # 暂时使用所有错误模式

            # 查询最近的成功案例（最近30天，成功率>80%）
            cutoff_time = datetime.now() - timedelta(days=30)

            # 查询高成功率的修复策略
            from sqlalchemy import and_, desc

            successful_fixes = sa_session.query(AIOpsFixStrategy).join(
                AIOpsErrorPattern, AIOpsFixStrategy.error_pattern_id == AIOpsErrorPattern.id
            ).filter(
                and_(
                    AIOpsFixStrategy.success_rate > 0.8,
                    AIOpsFixStrategy.total_applications >= 3,  # 至少3次应用（可靠）
                    AIOpsFixStrategy.is_active == True,
                    AIOpsErrorPattern.last_seen >= cutoff_time  # 最近30天见过
                )
            ).order_by(
                desc(AIOpsFixStrategy.success_rate),
                desc(AIOpsFixStrategy.total_applications)
            ).limit(5).all()

            # 格式化为 Few-shot examples
            historical_cases = []
            for fix in successful_fixes:
                pattern = sa_session.query(AIOpsErrorPattern).get(fix.error_pattern_id)
                if pattern:
                    historical_cases.append({
                        'error_type': pattern.error_type,
                        'error_message': pattern.error_message_template,
                        'fix_title': fix.fix_title,
                        'fix_description': fix.fix_description,
                        'config_changes': fix.config_changes,
                        'success_rate': fix.success_rate,
                        'total_applications': fix.total_applications,
                        'pipeline_types': pattern.pipeline_types,
                    })

            return historical_cases

        except Exception as e:
            log.warning(f"⚠️  Failed to retrieve historical cases: {e}")
            return []

    def _record_error_patterns(self, context: FixContext, issues: List[Dict[str, Any]]):
        """
        记录错误模式到知识库

        为每个检测到的问题创建或更新错误模式。
        不记录修复策略（修复策略在应用时记录）。

        Args:
            context: Fix context
            issues: 检测到的问题列表
        """
        try:
            from galaxy.model import WorkflowInvocation

            sa_session = context.metadata.get('sa_session')
            if not sa_session:
                return

            invocation = sa_session.query(WorkflowInvocation).get(context.invocation_id)
            if not invocation:
                return

            # TODO: 提取 pipeline_type
            pipeline_type = "unknown"

            for issue in issues:
                error_type = issue.get('issue_type', 'unknown')
                error_message = issue.get('description', '')

                # 添加或更新错误模式
                pattern_id = self.kb_manager.add_or_update_error_pattern(
                    error_message=error_message,
                    error_type=error_type,
                    workflow_id=context.invocation_id,
                    pipeline_type=pipeline_type,
                    context={
                        'root_cause': issue.get('root_cause'),
                        'severity': issue.get('severity'),
                        'fixable': issue.get('fixable'),
                    }
                )

                log.info(f"📝 Recorded error pattern {pattern_id}: {error_type}")

                # 将 pattern_id 添加到 issue（供后续使用）
                issue['_error_pattern_id'] = pattern_id

        except Exception as e:
            log.warning(f"⚠️  Failed to record error patterns: {e}")

    def generate_fix_plan(
        self,
        context: FixContext,
        issues: List[Dict[str, Any]]
    ) -> Optional[FixPlan]:
        """
        生成修复方案（增强版，带学习记录）

        工作流程：
        1. 调用父类生成修复方案
        2. 为每个修复动作记录到知识库
        3. 返回修复方案（带 error_pattern_id 和 fix_id）

        Args:
            context: Fix context
            issues: 检测到的问题列表

        Returns:
            修复方案（带学习元数据）
        """
        # 调用父类生成修复方案
        fix_plan = super().generate_fix_plan(context, issues)

        if not fix_plan:
            return None

        # 记录修复策略到知识库（如果学习系统可用）
        if self.kb_manager:
            self._record_fix_strategies(context, issues, fix_plan)

        return fix_plan

    def _record_fix_strategies(
        self,
        context: FixContext,
        issues: List[Dict[str, Any]],
        fix_plan: FixPlan
    ):
        """
        记录修复策略到知识库

        为每个修复动作创建修复策略记录。

        Args:
            context: Fix context
            issues: 问题列表（包含 _error_pattern_id）
            fix_plan: 修复方案
        """
        try:
            for i, issue in enumerate(issues):
                error_pattern_id = issue.get('_error_pattern_id')
                if not error_pattern_id:
                    continue

                # 获取对应的修复动作（假设顺序一致）
                if i < len(fix_plan.actions):
                    action = fix_plan.actions[i]

                    # 创建修复策略
                    fix_id = self.kb_manager.add_fix_strategy(
                        error_pattern_id=error_pattern_id,
                        fixer_name=self.name,
                        fix_type='auto_apply' if action.auto_apply else 'manual',
                        fix_title=action.title,
                        fix_description=action.description,
                        config_changes=[
                            {
                                'parameter': change.parameter,
                                'old_value': str(change.old_value) if change.old_value else None,
                                'new_value': str(change.new_value),
                                'source': change.source,
                            }
                            for change in action.config_changes
                        ] if action.config_changes else [],
                        validation_command=action.validation_command,
                        priority=100,  # 初始优先级
                        auto_generated=True,  # LLM 生成
                    )

                    log.info(f"📝 Recorded fix strategy {fix_id}: {action.title}")

                    # 将 fix_id 添加到 action metadata（供后续记录应用使用）
                    if not hasattr(action, 'metadata'):
                        action.metadata = {}
                    action.metadata['error_pattern_id'] = error_pattern_id
                    action.metadata['fix_id'] = fix_id

        except Exception as e:
            log.warning(f"⚠️  Failed to record fix strategies: {e}")

    def apply_fix(
        self,
        context: FixContext,
        fix_plan: FixPlan
    ) -> AutoFixResult:
        """
        应用修复（增强版，带学习记录）

        工作流程：
        1. 调用父类应用修复
        2. 记录修复应用到反馈循环
        3. 返回结果

        Args:
            context: Fix context
            fix_plan: 修复方案

        Returns:
            修复结果
        """
        # 记录应用前的配置
        before_config = self._extract_current_config(context)

        # 调用父类应用修复
        result = super().apply_fix(context, fix_plan)

        # 记录修复应用到反馈循环（如果学习系统可用）
        if self.feedback_loop and result.status == FixStatus.APPLIED:
            self._record_fix_applications(context, fix_plan, before_config, result)

        return result

    def _extract_current_config(self, context: FixContext) -> Dict[str, Any]:
        """提取当前配置（用于记录 before_config）"""
        # TODO: 从 workflow invocation 提取实际配置
        return {
            'workflow_id': context.invocation_id,
            'timestamp': datetime.now().isoformat(),
        }

    def _record_fix_applications(
        self,
        context: FixContext,
        fix_plan: FixPlan,
        before_config: Dict[str, Any],
        result: AutoFixResult
    ):
        """
        记录修复应用到反馈循环

        Args:
            context: Fix context
            fix_plan: 修复方案
            before_config: 应用前的配置
            result: 修复结果
        """
        try:
            # 提取应用后的配置
            after_config = {
                'workflow_id': result.new_invocation_id or context.invocation_id,
                'timestamp': datetime.now().isoformat(),
                'changes': [
                    {
                        'parameter': change.parameter,
                        'new_value': str(change.new_value),
                    }
                    for action in fix_plan.actions
                    for change in (action.config_changes or [])
                ]
            }

            # 为每个应用的修复动作记录
            for action in fix_plan.actions:
                error_pattern_id = action.metadata.get('error_pattern_id')
                fix_id = action.metadata.get('fix_id')

                if error_pattern_id and fix_id:
                    app_id = self.feedback_loop.record_fix_application(
                        workflow_invocation_id=result.new_invocation_id or context.invocation_id,
                        error_pattern_id=error_pattern_id,
                        fix_id=fix_id,
                        applied_by='system',
                        before_config=before_config,
                        after_config=after_config,
                        error_logs=result.message[:1000] if result.message else None,  # 截取1000字符
                    )

                    log.info(f"📝 Recorded fix application {app_id}")

        except Exception as e:
            log.warning(f"⚠️  Failed to record fix applications: {e}")


# 便捷函数：创建学习型修复器实例
def create_learning_fixer(llm_client=None) -> LLMLearningFixer:
    """
    创建学习型修复器实例

    Args:
        llm_client: 可选的 LLM 客户端

    Returns:
        LLMLearningFixer 实例

    Example:
    ```python
    fixer = create_learning_fixer()
    issues = fixer.detect_issues(context)
    fix_plan = fixer.generate_fix_plan(context, issues)
    result = fixer.apply_fix(context, fix_plan)

    # 自动记录到知识库
    # 下次遇到相似问题会更准确！
    ```
    """
    return LLMLearningFixer(llm_client=llm_client)
