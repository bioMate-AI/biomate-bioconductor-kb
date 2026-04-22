"""
Workflow自动修复系统

分析错误并生成修复方案，支持自动执行修复
"""

import logging
import json
import re
from typing import Dict, List, Optional, Any
from pathlib import Path

from .types import (
    Issue,
    FixPlan,
    FixAction,
    FixType,
    ActionType,
    IssueType,
    IssueSeverity,
)
from .llm_client import UnifiedLLMClient
from .fix_applier import WorkflowFixApplier
from .strategies.gtf_format_fix import GTFFormatFixStrategy

log = logging.getLogger(__name__)


class FixStrategy:
    """修复策略基类"""

    def can_fix(self, issue: Issue, context: Dict[str, Any]) -> bool:
        """判断是否能处理该issue"""
        raise NotImplementedError

    def generate_fix(self, issue: Issue, context: Dict[str, Any]) -> Optional[FixPlan]:
        """生成修复方案"""
        raise NotImplementedError

    def apply_fix(self, fix_plan: FixPlan, context: Dict[str, Any]) -> bool:
        """应用修复"""
        raise NotImplementedError


class ParameterFixStrategy(FixStrategy):
    """参数配置错误修复策略"""

    def can_fix(self, issue: Issue, context: Dict[str, Any]) -> bool:
        return issue.type in [IssueType.INVALID_PARAM, IssueType.MISSING_PARAM]

    def generate_fix(self, issue: Issue, context: Dict[str, Any]) -> Optional[FixPlan]:
        """
        修复参数错误

        常见场景：
        1. 参数值拼写错误（如 genome='hg19' 应为 'hg38'）
        2. 缺少必需参数
        3. 参数值超出范围
        """
        # 提取参数名
        param_name = self._extract_param_name(issue.message)
        if not param_name:
            return None

        # 获取workflow配置
        workflow_config = context.get('workflow_config', {})
        available_params = context.get('available_params', {})

        # 生成修复建议
        fix_actions = []

        if issue.type == IssueType.MISSING_PARAM:
            # 缺少参数 → 添加默认值
            default_value = available_params.get(param_name, {}).get('default')
            if default_value:
                fix_actions.append(FixAction(
                    action=ActionType.UPDATE_PARAM,
                    params={
                        'param_name': param_name,
                        'new_value': default_value,
                    },
                    description=f"添加缺失的参数 {param_name}={default_value}",
                    risk_level='low',
                ))

        elif issue.type == IssueType.INVALID_PARAM:
            # 无效参数 → 修正值
            # 这里需要LLM帮助推断正确值
            pass

        if not fix_actions:
            return None

        return FixPlan(
            fixable=True,
            fix_type=FixType.CONFIG_ADJUSTMENT,
            fix_actions=fix_actions,
            explanation=f"检测到参数配置错误，自动修复参数 {param_name}",
            confidence=0.8,
            estimated_success_rate=0.85,
            requires_user_confirmation=False,  # 低风险，自动执行
        )

    def apply_fix(self, fix_plan: FixPlan, context: Dict[str, Any]) -> bool:
        """应用参数修复 - 使用真正的 WorkflowFixApplier"""
        try:
            app = context.get('app')
            invocation_id = context.get('invocation_id')
            user = context.get('user')  # ← 获取用户信息

            if not app or not invocation_id:
                log.error("Missing app or invocation_id in context")
                return False

            # ✅ 使用真正的修复应用器,传递用户信息
            applier = WorkflowFixApplier(app, user=user)
            success = applier.apply_parameter_fix(invocation_id, fix_plan, context)

            return success

        except PermissionError as e:
            log.error(f"Permission denied: {e}")
            return False
        except Exception as e:
            log.error(f"Failed to apply parameter fix: {e}")
            return False

    def _extract_param_name(self, message: str) -> Optional[str]:
        """从错误消息中提取参数名"""
        patterns = [
            r"parameter\s+['\"]?(\w+)['\"]?",
            r"['\"]?(\w+)['\"]?\s+parameter",
            r"--(\w+)",
        ]

        for pattern in patterns:
            match = re.search(pattern, message, re.IGNORECASE)
            if match:
                return match.group(1)

        return None


class DataConversionFixStrategy(FixStrategy):
    """数据格式转换修复策略"""

    def can_fix(self, issue: Issue, context: Dict[str, Any]) -> bool:
        return issue.type == IssueType.DATA_FORMAT

    def generate_fix(self, issue: Issue, context: Dict[str, Any]) -> Optional[FixPlan]:
        """
        生成数据转换方案

        常见场景：
        1. FASTQ质量分数格式转换（Phred33 ↔ Phred64）
        2. 文件格式转换（BAM → SAM）
        3. 压缩/解压缩
        """
        # 检测需要转换的数据集
        dataset_id = self._extract_dataset_id(issue, context)
        if not dataset_id:
            return None

        # 检测目标格式
        target_format = self._detect_target_format(issue.message)
        if not target_format:
            return None

        fix_actions = [
            FixAction(
                action=ActionType.CONVERT_DATA,
                params={
                    'dataset_id': dataset_id,
                    'target_format': target_format,
                },
                description=f"转换数据集 {dataset_id} 为 {target_format} 格式",
                risk_level='medium',  # 数据转换有风险
            )
        ]

        return FixPlan(
            fixable=True,
            fix_type=FixType.DATA_CONVERSION,
            fix_actions=fix_actions,
            explanation=f"检测到数据格式不兼容，需要转换为 {target_format}",
            confidence=0.7,
            estimated_success_rate=0.75,
            requires_user_confirmation=True,  # 中风险，需要确认
        )

    def apply_fix(self, fix_plan: FixPlan, context: Dict[str, Any]) -> bool:
        """应用数据转换"""
        # TODO: 数据转换需要调用Galaxy的数据类型转换工具
        # 暂时不实现，因为这需要深入了解Galaxy的数据类型系统
        log.warning("Data conversion not yet implemented - requires Galaxy datatype conversion tools")
        return False

    def _extract_dataset_id(self, issue: Issue, context: Dict[str, Any]) -> Optional[int]:
        """提取需要转换的数据集ID"""
        # 从context中获取输入数据集
        input_datasets = context.get('input_datasets', {})
        # 简化实现：返回第一个数据集
        if input_datasets:
            return list(input_datasets.keys())[0]
        return None

    def _detect_target_format(self, message: str) -> Optional[str]:
        """从错误消息推断目标格式"""
        # 常见格式关键词
        formats = ['fastq', 'fasta', 'bam', 'sam', 'vcf', 'bed', 'gff']
        for fmt in formats:
            if fmt in message.lower():
                return fmt
        return None


class ResourceScalingFixStrategy(FixStrategy):
    """资源扩容修复策略"""

    def can_fix(self, issue: Issue, context: Dict[str, Any]) -> bool:
        return issue.type == IssueType.RESOURCE_LIMIT

    def generate_fix(self, issue: Issue, context: Dict[str, Any]) -> Optional[FixPlan]:
        """
        生成资源扩容方案

        常见场景：
        1. 内存不足 → 增加内存
        2. 磁盘满 → 增加存储或清理临时文件
        """
        fix_actions = []

        if 'memory' in issue.message.lower() or 'oom' in issue.message.lower():
            # 内存不足
            current_memory = context.get('current_memory_gb', 4)
            new_memory = current_memory * 2  # 翻倍

            fix_actions.append(FixAction(
                action=ActionType.INCREASE_MEMORY,
                params={
                    'current': current_memory,
                    'new': new_memory,
                },
                description=f"增加内存配置：{current_memory}GB → {new_memory}GB",
                risk_level='low',  # 增加资源是低风险
            ))

        elif 'disk' in issue.message.lower() or 'storage' in issue.message.lower():
            # 磁盘不足
            current_disk = context.get('current_disk_gb', 100)
            new_disk = current_disk + 100

            fix_actions.append(FixAction(
                action=ActionType.INCREASE_DISK,
                params={
                    'current': current_disk,
                    'new': new_disk,
                },
                description=f"增加磁盘空间：{current_disk}GB → {new_disk}GB",
                risk_level='low',
            ))

        if not fix_actions:
            return None

        return FixPlan(
            fixable=True,
            fix_type=FixType.RESOURCE_SCALING,
            fix_actions=fix_actions,
            explanation="检测到资源不足，自动扩容",
            confidence=0.9,
            estimated_success_rate=0.95,
            requires_user_confirmation=False,  # 低风险
        )

    def apply_fix(self, fix_plan: FixPlan, context: Dict[str, Any]) -> bool:
        """应用资源扩容 - 使用真正的 WorkflowFixApplier"""
        try:
            app = context.get('app')
            invocation_id = context.get('invocation_id')
            user = context.get('user')  # ← 获取用户信息

            if not app or not invocation_id:
                log.error("Missing app or invocation_id in context")
                return False

            # ✅ 使用真正的修复应用器,传递用户信息
            applier = WorkflowFixApplier(app, user=user)
            success = applier.apply_resource_scaling_fix(invocation_id, fix_plan, context)

            return success

        except PermissionError as e:
            log.error(f"Permission denied: {e}")
            return False
        except Exception as e:
            log.error(f"Failed to apply resource scaling fix: {e}")
            return False


class SimpleRetryStrategy(FixStrategy):
    """简单重试策略（用于临时性错误）"""

    def can_fix(self, issue: Issue, context: Dict[str, Any]) -> bool:
        return issue.type == IssueType.NETWORK_ERROR

    def generate_fix(self, issue: Issue, context: Dict[str, Any]) -> Optional[FixPlan]:
        """生成重试方案"""
        retry_count = context.get('retry_count', 0)
        max_retries = context.get('max_retries', 3)

        if retry_count >= max_retries:
            return None  # 超过最大重试次数

        fix_actions = [
            FixAction(
                action=ActionType.RETRY_TASK,
                params={
                    'retry_count': retry_count + 1,
                    'delay_seconds': 2 ** retry_count,  # 指数退避
                },
                description=f"重试失败的任务（第{retry_count + 1}次）",
                risk_level='low',
            )
        ]

        return FixPlan(
            fixable=True,
            fix_type=FixType.SIMPLE_RETRY,
            fix_actions=fix_actions,
            explanation="检测到临时性网络错误，自动重试",
            confidence=0.6,
            estimated_success_rate=0.7,
            requires_user_confirmation=False,
        )

    def apply_fix(self, fix_plan: FixPlan, context: Dict[str, Any]) -> bool:
        """应用重试 - 使用真正的 WorkflowFixApplier"""
        try:
            app = context.get('app')
            invocation_id = context.get('invocation_id')
            user = context.get('user')  # ← 获取用户信息

            if not app or not invocation_id:
                log.error("Missing app or invocation_id in context")
                return False

            # ✅ 使用真正的修复应用器,传递用户信息
            applier = WorkflowFixApplier(app, user=user)
            success = applier.apply_retry_fix(invocation_id, fix_plan, context)

            return success

        except PermissionError as e:
            log.error(f"Permission denied: {e}")
            return False
        except Exception as e:
            log.error(f"Failed to apply retry fix: {e}")
            return False


class WorkflowAutoHealer:
    """
    Workflow自动修复系统

    工作流程：
    1. 接收错误信息（issues）
    2. 匹配修复策略
    3. 生成修复方案
    4. （可选）LLM增强分析
    5. 应用修复或请求用户确认
    """

    def __init__(
        self,
        llm_client: Optional[UnifiedLLMClient] = None,
        auto_fix_mode: str = 'safe'
    ):
        """
        Args:
            llm_client: LLM客户端
            auto_fix_mode: 自动修复模式
                - 'safe': 仅自动修复低风险操作
                - 'moderate': 自动修复低/中风险操作
                - 'aggressive': 自动修复所有操作（不推荐）
                - 'manual': 所有修复都需要用户确认
        """
        self.llm_client = llm_client or UnifiedLLMClient()
        self.auto_fix_mode = auto_fix_mode

        # 注册修复策略
        self.strategies: List[FixStrategy] = [
            GTFFormatFixStrategy(),  # GTF 格式错误（高优先级）
            ParameterFixStrategy(),
            DataConversionFixStrategy(),
            ResourceScalingFixStrategy(),
            SimpleRetryStrategy(),
        ]

    def analyze_and_fix(self, error_context: Dict[str, Any]) -> Dict[str, Any]:
        """
        分析错误并生成修复方案

        Args:
            error_context: {
                'invocation_id': int,
                'failed_step': int,
                'issues': List[Issue],
                'error_logs': List[str],
                'workflow_config': {...},
                'input_datasets': {...},
                'app': Galaxy app instance,
                ...
            }

        Returns:
            {
                'fixable': True/False,
                'fix_plans': [FixPlan, ...],
                'applied_fixes': [FixPlan, ...],  # 已自动应用的
                'pending_fixes': [FixPlan, ...],  # 需要用户确认的
                'unfixable_issues': [Issue, ...],
            }
        """
        issues = error_context.get('issues', [])
        if not issues:
            return {
                'fixable': False,
                'fix_plans': [],
                'applied_fixes': [],
                'pending_fixes': [],
                'unfixable_issues': [],
            }

        fix_plans = []
        unfixable_issues = []

        # 为每个issue生成修复方案
        for issue in issues:
            fix_plan = self._generate_fix_plan(issue, error_context)

            if fix_plan:
                fix_plans.append(fix_plan)
            else:
                unfixable_issues.append(issue)

        # 如果有无法修复的issue，尝试LLM增强分析
        if unfixable_issues:
            llm_fix_plans = self._analyze_with_llm(unfixable_issues, error_context)
            fix_plans.extend(llm_fix_plans)

        # 应用修复
        applied_fixes = []
        pending_fixes = []

        for fix_plan in fix_plans:
            if self._should_auto_fix(fix_plan):
                # 自动应用
                success = self._apply_fix_plan(fix_plan, error_context)
                if success:
                    applied_fixes.append(fix_plan)
                else:
                    pending_fixes.append(fix_plan)
            else:
                # 需要用户确认
                pending_fixes.append(fix_plan)

        return {
            'fixable': len(fix_plans) > 0,
            'fix_plans': fix_plans,
            'applied_fixes': applied_fixes,
            'pending_fixes': pending_fixes,
            'unfixable_issues': unfixable_issues,
        }

    def _generate_fix_plan(self, issue: Issue, context: Dict[str, Any]) -> Optional[FixPlan]:
        """使用策略生成修复方案"""
        for strategy in self.strategies:
            if strategy.can_fix(issue, context):
                fix_plan = strategy.generate_fix(issue, context)
                if fix_plan:
                    return fix_plan
        return None

    def _analyze_with_llm(
        self,
        issues: List[Issue],
        context: Dict[str, Any]
    ) -> List[FixPlan]:
        """使用LLM分析无法通过规则修复的错误"""
        error_logs = "\n".join(context.get('error_logs', [])[-50:])
        issues_json = json.dumps([
            {
                'severity': issue.severity.value,
                'type': issue.type.value,
                'message': issue.message,
            }
            for issue in issues
        ], indent=2)

        prompt = f"""你是Nextflow workflow错误修复专家。请分析以下错误并提供修复方案：

**错误日志：**
```
{error_logs}
```

**检测到的Issues：**
```json
{issues_json}
```

**请为每个issue提供：**
1. 是否可以修复（fixable）
2. 修复类型（config_adjustment/data_conversion/resource_scaling/simple_retry）
3. 具体的修复步骤
4. 修复成功率估计
5. 风险级别（low/medium/high）

请以JSON格式返回：
```json
{{
  "fix_plans": [
    {{
      "issue_index": 0,
      "fixable": true,
      "fix_type": "config_adjustment",
      "fix_actions": [
        {{
          "action": "update_param",
          "params": {{"param_name": "genome", "new_value": "hg38"}},
          "description": "修正基因组参数",
          "risk_level": "low"
        }}
      ],
      "explanation": "为什么这样修复",
      "confidence": 0.85,
      "estimated_success_rate": 0.9
    }}
  ]
}}
```
"""

        try:
            result = self.llm_client.call(
                messages=[{"role": "user", "content": prompt}],
                model='gemini-2.5-flash',
                temperature=0.0,
            )

            content = result['content']

            # 解析JSON
            json_match = re.search(r'```json\s*\n(.*?)\n```', content, re.DOTALL)
            if json_match:
                json_str = json_match.group(1)
            else:
                json_str = content

            parsed = json.loads(json_str)

            # 转换为FixPlan对象
            fix_plans = []
            for raw_plan in parsed.get('fix_plans', []):
                try:
                    fix_plan = FixPlan(
                        fixable=raw_plan.get('fixable', False),
                        fix_type=FixType(raw_plan.get('fix_type', 'manual_intervention')),
                        fix_actions=[
                            FixAction(
                                action=ActionType(action_data['action']),
                                params=action_data['params'],
                                description=action_data['description'],
                                risk_level=action_data.get('risk_level', 'medium'),
                            )
                            for action_data in raw_plan.get('fix_actions', [])
                        ],
                        explanation=raw_plan.get('explanation', ''),
                        confidence=raw_plan.get('confidence', 0.5),
                        estimated_success_rate=raw_plan.get('estimated_success_rate', 0.5),
                        requires_user_confirmation=raw_plan.get('risk_level', 'medium') != 'low',
                    )
                    fix_plans.append(fix_plan)
                except (ValueError, KeyError) as e:
                    log.warning(f"Failed to parse LLM fix plan: {e}")

            return fix_plans

        except Exception as e:
            log.error(f"LLM fix analysis failed: {e}")
            return []

    def _should_auto_fix(self, fix_plan: FixPlan) -> bool:
        """判断是否应该自动应用修复"""
        if self.auto_fix_mode == 'manual':
            return False

        if fix_plan.requires_user_confirmation:
            if self.auto_fix_mode == 'safe':
                return False
            elif self.auto_fix_mode == 'moderate':
                # 检查风险级别
                max_risk = max(
                    (action.risk_level for action in fix_plan.fix_actions),
                    default='low'
                )
                return max_risk in ['low', 'medium']
            elif self.auto_fix_mode == 'aggressive':
                return True

        # 低风险、不需要确认的 → 自动应用
        return True

    def _apply_fix_plan(self, fix_plan: FixPlan, context: Dict[str, Any]) -> bool:
        """应用修复方案"""
        # 找到对应的策略并应用
        for strategy in self.strategies:
            # 简化实现：根据fix_type匹配策略
            if isinstance(strategy, ParameterFixStrategy) and fix_plan.fix_type == FixType.CONFIG_ADJUSTMENT:
                return strategy.apply_fix(fix_plan, context)
            elif isinstance(strategy, DataConversionFixStrategy) and fix_plan.fix_type == FixType.DATA_CONVERSION:
                return strategy.apply_fix(fix_plan, context)
            elif isinstance(strategy, ResourceScalingFixStrategy) and fix_plan.fix_type == FixType.RESOURCE_SCALING:
                return strategy.apply_fix(fix_plan, context)
            elif isinstance(strategy, SimpleRetryStrategy) and fix_plan.fix_type == FixType.SIMPLE_RETRY:
                return strategy.apply_fix(fix_plan, context)

        log.warning(f"No strategy found for fix type: {fix_plan.fix_type}")
        return False
