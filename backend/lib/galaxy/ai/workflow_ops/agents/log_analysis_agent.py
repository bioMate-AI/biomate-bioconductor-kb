"""
Log Analysis Agent

专门分析日志文件：
- 提取错误信息
- 识别警告
- 关联历史问题
- 生成错误摘要
"""

import re
import logging
from typing import Dict, List, Any, Optional
from datetime import datetime
from ..agent_system import (
    BaseAgent,
    AgentCapability,
    AgentTriggerCondition,
    AgentPriority
)

log = logging.getLogger(__name__)


class LogAnalysisAgent(BaseAgent):
    """日志分析专家 Agent"""

    @property
    def name(self) -> str:
        return "LogAnalysisAgent"

    @property
    def capability(self) -> AgentCapability:
        return AgentCapability.LOG_ANALYSIS

    @property
    def trigger_conditions(self) -> List[AgentTriggerCondition]:
        return [
            AgentTriggerCondition.ALWAYS,  # 始终分析日志
            AgentTriggerCondition.ON_ERROR,
            AgentTriggerCondition.ON_WARNING
        ]

    @property
    def priority(self) -> AgentPriority:
        return AgentPriority.MEDIUM

    @property
    def requires_llm(self) -> bool:
        return False  # 基于规则的日志解析

    def can_handle(self, issue: Dict[str, Any]) -> bool:
        """日志分析 Agent 可以处理所有问题"""
        return True  # 总是可以分析日志

    async def analyze(self, context: Dict[str, Any]) -> Dict[str, Any]:
        """分析日志"""
        logs = context.get('logs', '')
        invocation = context.get('invocation')

        analysis = {
            'total_lines': 0,
            'error_count': 0,
            'warning_count': 0,
            'errors': [],
            'warnings': [],
            'key_events': [],
            'execution_timeline': []
        }

        if not logs:
            log.warning("No logs available for analysis")
            return analysis

        lines = logs.split('\n')
        analysis['total_lines'] = len(lines)

        # 1. 提取错误
        error_patterns = [
            r'ERROR[:\s]+(.+)',
            r'FATAL[:\s]+(.+)',
            r'Exception[:\s]+(.+)',
            r'Failed[:\s]+(.+)',
            r'Error executing[:\s]+(.+)'
        ]

        for line in lines:
            for pattern in error_patterns:
                match = re.search(pattern, line, re.IGNORECASE)
                if match:
                    error_msg = match.group(1).strip()
                    if len(error_msg) > 0 and len(error_msg) < 500:  # 过滤太长或太短的
                        analysis['errors'].append({
                            'message': error_msg,
                            'line': line.strip(),
                            'timestamp': self._extract_timestamp(line)
                        })
                        analysis['error_count'] += 1
                    break  # 每行只匹配一次

        # 2. 提取警告
        warning_patterns = [
            r'WARN(?:ING)?[:\s]+(.+)',
            r'CAUTION[:\s]+(.+)',
            r'Ignore this warning[:\s]+(.+)'
        ]

        for line in lines:
            for pattern in warning_patterns:
                match = re.search(pattern, line, re.IGNORECASE)
                if match:
                    warning_msg = match.group(1).strip()
                    if len(warning_msg) > 0 and len(warning_msg) < 500:
                        analysis['warnings'].append({
                            'message': warning_msg,
                            'line': line.strip(),
                            'timestamp': self._extract_timestamp(line)
                        })
                        analysis['warning_count'] += 1
                    break

        # 3. 提取关键事件
        event_patterns = {
            'workflow_started': r'Workflow\s+(?:execution\s+)?started',
            'workflow_completed': r'Workflow\s+(?:execution\s+)?completed',
            'step_started': r'(?:Submitting|Launching)\s+process\s+[>\s]*[\'"]?(\w+)',
            'step_completed': r'(?:Completed|Finished)\s+process\s+[>\s]*[\'"]?(\w+)',
            'file_published': r'Published\s+(?:file|directory)[:\s]+(.+)',
        }

        for line in lines:
            for event_type, pattern in event_patterns.items():
                match = re.search(pattern, line, re.IGNORECASE)
                if match:
                    event_data = match.group(1) if match.groups() else ''
                    analysis['key_events'].append({
                        'type': event_type,
                        'data': event_data,
                        'timestamp': self._extract_timestamp(line),
                        'line': line.strip()[:200]  # 限制长度
                    })

        # 4. 去重错误（相同错误只保留一个）
        unique_errors = []
        seen_messages = set()
        for error in analysis['errors']:
            # 简化消息用于去重
            simplified = re.sub(r'[\d\s\W]+', '', error['message'][:50])
            if simplified not in seen_messages:
                seen_messages.add(simplified)
                unique_errors.append(error)

        analysis['errors'] = unique_errors[:10]  # 最多保留10个不同的错误

        # 5. 去重警告
        unique_warnings = []
        seen_warnings = set()
        for warning in analysis['warnings']:
            simplified = re.sub(r'[\d\s\W]+', '', warning['message'][:50])
            if simplified not in seen_warnings:
                seen_warnings.add(simplified)
                unique_warnings.append(warning)

        analysis['warnings'] = unique_warnings[:10]

        log.info(f"Log analysis: {analysis['error_count']} errors, {analysis['warning_count']} warnings")
        return analysis

    def _extract_timestamp(self, line: str) -> Optional[str]:
        """从日志行中提取时间戳"""
        # 常见时间戳格式
        timestamp_patterns = [
            r'\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}',  # 2024-01-05 12:30:45
            r'\d{2}:\d{2}:\d{2}',  # 12:30:45
            r'\[\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\]',  # [2024-01-05T12:30:45]
        ]

        for pattern in timestamp_patterns:
            match = re.search(pattern, line)
            if match:
                return match.group(0)

        return None

    async def suggest_fix(self, context: Dict[str, Any]) -> List[Dict[str, Any]]:
        """基于日志分析提供建议"""
        analysis = await self.analyze(context)
        suggestions = []

        # 1. 如果有错误，生成错误摘要建议
        if analysis['errors']:
            error_summary = '\n'.join([
                f"  • {error['message'][:100]}"
                for error in analysis['errors'][:5]
            ])

            suggestions.append({
                'action': 'review_errors',
                'description': f"发现 {analysis['error_count']} 个错误，需要review",
                'risk_level': 'high',
                'error_count': analysis['error_count'],
                'guidance': f"""
🔴 日志错误分析报告

📊 统计：
  • 总行数：{analysis['total_lines']}
  • 错误数：{analysis['error_count']}
  • 警告数：{analysis['warning_count']}

🚨 主要错误：
{error_summary}

💡 建议：
  1. 查看完整错误堆栈
  2. 检查相关配置
  3. 参考错误信息调用对应的专项 Agent
"""
            })

        # 2. 如果有警告，生成警告建议
        if analysis['warnings']:
            warning_summary = '\n'.join([
                f"  • {warning['message'][:100]}"
                for warning in analysis['warnings'][:5]
            ])

            suggestions.append({
                'action': 'review_warnings',
                'description': f"发现 {analysis['warning_count']} 个警告",
                'risk_level': 'medium',
                'warning_count': analysis['warning_count'],
                'guidance': f"""
⚠️ 日志警告分析报告

📊 警告数：{analysis['warning_count']}

⚠️ 主要警告：
{warning_summary}

💡 建议：
  • 警告通常不会导致失败，但可能影响结果质量
  • 建议逐一检查并根据情况处理
"""
            })

        # 3. 如果没有错误和警告，说明日志正常
        if not analysis['errors'] and not analysis['warnings']:
            suggestions.append({
                'action': 'log_analysis_clean',
                'description': '日志分析正常，未发现明显问题',
                'risk_level': 'low',
                'guidance': """
✅ 日志分析报告

📊 状态：正常
  • 未发现错误
  • 未发现警告

💡 建议：
  如果 workflow 执行失败，可能是：
  1. 日志未包含完整信息
  2. 问题发生在外部依赖
  3. 配置问题（不会产生日志）
"""
            })

        return suggestions

    async def apply_fix(self, fix_plan: Dict[str, Any], context: Dict[str, Any]) -> bool:
        """应用修复（提供分析报告）"""
        try:
            guidance = fix_plan.get('guidance', '')

            if guidance:
                if 'fix_guidance' not in context:
                    context['fix_guidance'] = []
                context['fix_guidance'].append(guidance)

                # 将分析结果也保存到 context
                if 'log_analysis' not in context:
                    context['log_analysis'] = await self.analyze(context)

                log.info(f"Log analysis completed: {fix_plan.get('action')}")
                return True

            return False

        except Exception as e:
            log.error(f"Failed to apply log analysis: {e}")
            return False

    def get_cost_estimate(self) -> float:
        """无 LLM 成本"""
        return 0.0
