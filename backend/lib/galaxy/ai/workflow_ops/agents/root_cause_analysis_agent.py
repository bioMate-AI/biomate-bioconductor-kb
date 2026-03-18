"""
Root Cause Analysis Agent

综合分析多个维度的数据，找到问题的根本原因
使用 LLM 进行深度分析
"""

import logging
from typing import Dict, List, Any
from datetime import datetime
from ..agent_system import (
    BaseAgent,
    AgentCapability,
    AgentTriggerCondition,
    AgentPriority
)

log = logging.getLogger(__name__)


class RootCauseAnalysisAgent(BaseAgent):
    """根因分析专家 Agent - 使用 LLM 进行深度分析"""

    @property
    def name(self) -> str:
        return "RootCauseAnalysisAgent"

    @property
    def capability(self) -> AgentCapability:
        return AgentCapability.ROOT_CAUSE_ANALYSIS

    @property
    def trigger_conditions(self) -> List[AgentTriggerCondition]:
        return [AgentTriggerCondition.ON_DEMAND]  # 只在其他 Agent 失败时调用

    @property
    def priority(self) -> AgentPriority:
        return AgentPriority.CRITICAL

    @property
    def requires_llm(self) -> bool:
        return True  # 需要 LLM

    def can_handle(self, issue: Dict[str, Any]) -> bool:
        """根因分析可以处理所有问题"""
        return True

    async def analyze(self, context: Dict[str, Any]) -> Dict[str, Any]:
        """综合分析问题"""
        issue = context.get('issue', {})
        logs = context.get('logs', '')[:5000]  # 限制长度，避免超过 LLM 限制
        invocation = context.get('invocation')
        agents_tried = context.get('agents_tried', [])

        # 收集所有可用信息
        analysis_data = {
            'issue_type': issue.get('type'),
            'issue_message': issue.get('message', '')[:1000],
            'logs_sample': logs,
            'failed_agents': [agent.get('agent') for agent in agents_tried if not agent.get('success')],
            'root_cause': None,
            'contributing_factors': [],
            'recommended_actions': []
        }

        # 如果有 LLM 客户端，使用 LLM 分析
        if self.llm_client:
            try:
                root_cause = await self._llm_analyze(analysis_data)
                analysis_data['root_cause'] = root_cause.get('root_cause')
                analysis_data['contributing_factors'] = root_cause.get('contributing_factors', [])
                analysis_data['recommended_actions'] = root_cause.get('recommended_actions', [])
            except Exception as e:
                log.error(f"LLM analysis failed: {e}")
                # 降级到规则分析
                analysis_data = self._rule_based_analyze(analysis_data)
        else:
            # 没有 LLM，使用规则分析
            analysis_data = self._rule_based_analyze(analysis_data)

        log.info(f"Root cause analysis completed: {analysis_data['root_cause']}")
        return analysis_data

    async def _llm_analyze(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """使用 LLM 进行根因分析"""
        prompt = f"""你是一个 Workflow 问题诊断专家。请分析以下信息并找出问题的根本原因。

问题类型: {data['issue_type']}
错误消息: {data['issue_message']}
日志样本:
{data['logs_sample']}

已尝试的 Agent: {', '.join(data['failed_agents'])}

请提供：
1. 根本原因（root_cause）：用一句话说明问题的核心原因
2. 贡献因素（contributing_factors）：列出3-5个导致问题的因素
3. 推荐操作（recommended_actions）：列出3-5个具体的修复步骤

请以 JSON 格式返回：
{{
    "root_cause": "根本原因描述",
    "contributing_factors": ["因素1", "因素2", "因素3"],
    "recommended_actions": ["步骤1", "步骤2", "步骤3"]
}}
"""

        messages = [{"role": "user", "content": prompt}]

        try:
            response = self.llm_client.call(
                messages=messages,
                model="claude-3-5-haiku-20241022",  # 使用 Anthropic 的经济模型
                temperature=0.3,
                max_tokens=1000
            )

            # 解析 JSON
            import json
            import re

            # 提取 JSON（可能被 markdown 代码块包围）
            text = response.get('content', '{}')
            json_match = re.search(r'\{.*\}', text, re.DOTALL)
            if json_match:
                result = json.loads(json_match.group(0))
                return result
            else:
                log.warning("LLM response is not valid JSON")
                return {
                    'root_cause': text[:200],
                    'contributing_factors': [],
                    'recommended_actions': []
                }

        except Exception as e:
            log.error(f"LLM call failed: {e}")
            raise

    def _rule_based_analyze(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """基于规则的根因分析（LLM 不可用时的降级方案）"""
        issue_message = data['issue_message'].lower()
        issue_type = data.get('issue_type', '').lower()

        # 简单的规则匹配
        if 'memory' in issue_message or 'oom' in issue_message:
            data['root_cause'] = "内存不足导致进程被终止"
            data['contributing_factors'] = [
                "进程使用的内存超过了配置的限制",
                "可能是数据量过大",
                "或者算法需要更多内存"
            ]
            data['recommended_actions'] = [
                "增加内存配置至当前值的2倍",
                "检查输入数据大小",
                "考虑使用内存优化的算法"
            ]

        elif 'parameter' in issue_message or 'param' in issue_message:
            data['root_cause'] = "缺少必需的参数配置"
            data['contributing_factors'] = [
                "Workflow 定义中未设置必需参数",
                "参数名称或值不正确",
                "Pipeline schema 验证失败"
            ]
            data['recommended_actions'] = [
                "检查 pipeline 文档，了解必需参数",
                "在 Workflow 编辑器中添加缺少的参数",
                "参考示例配置"
            ]

        elif 's3' in issue_message or '403' in issue_message or 'access denied' in issue_message:
            data['root_cause'] = "AWS S3 访问权限不足"
            data['contributing_factors'] = [
                "IAM Role 没有 S3 读写权限",
                "Bucket Policy 阻止了访问",
                "S3 Block Public Access 设置过严"
            ]
            data['recommended_actions'] = [
                "为 Batch Job Role 添加 S3 访问策略",
                "检查 Bucket Policy",
                "验证 IAM 权限配置"
            ]

        elif 'timeout' in issue_message or 'connection' in issue_message:
            data['root_cause'] = "网络连接问题"
            data['contributing_factors'] = [
                "网络延迟过高",
                "目标服务响应慢",
                "防火墙或安全组阻止连接"
            ]
            data['recommended_actions'] = [
                "增加网络超时时间",
                "检查网络连接",
                "验证安全组配置"
            ]

        else:
            data['root_cause'] = "未能识别具体原因，需要人工分析"
            data['contributing_factors'] = [
                "问题较复杂，规则无法识别",
                "可能需要更多上下文信息"
            ]
            data['recommended_actions'] = [
                "查看完整的错误日志",
                "联系技术支持",
                "参考 pipeline 官方文档"
            ]

        return data

    async def suggest_fix(self, context: Dict[str, Any]) -> List[Dict[str, Any]]:
        """提供修复建议"""
        analysis = await self.analyze(context)
        suggestions = []

        # 生成综合修复建议
        factors_text = '\n'.join([f"  {i+1}. {f}" for i, f in enumerate(analysis['contributing_factors'])])
        actions_text = '\n'.join([f"  {i+1}. {a}" for i, a in enumerate(analysis['recommended_actions'])])

        suggestions.append({
            'action': 'root_cause_analysis_report',
            'description': '根因分析报告已生成',
            'risk_level': 'high',
            'root_cause': analysis['root_cause'],
            'guidance': f"""
🔍 根因分析报告

🎯 根本原因：
  {analysis['root_cause']}

📋 贡献因素：
{factors_text}

✅ 推荐操作：
{actions_text}

💡 提示：
  • 这是一个综合分析结果
  • 建议按优先级逐步执行推荐操作
  • 如果问题依然存在，请联系技术支持
  • 提供完整的错误日志将有助于进一步诊断

🤖 分析方式：{'AI 深度分析' if self.llm_client else '规则匹配'}
"""
        })

        return suggestions

    async def apply_fix(self, fix_plan: Dict[str, Any], context: Dict[str, Any]) -> bool:
        """应用修复（生成报告）"""
        try:
            guidance = fix_plan.get('guidance', '')

            if guidance:
                if 'fix_guidance' not in context:
                    context['fix_guidance'] = []
                context['fix_guidance'].append(guidance)

                # 保存根因分析结果
                context['root_cause_analysis'] = {
                    'root_cause': fix_plan.get('root_cause'),
                    'timestamp': str(datetime.now()),
                    'analysis_method': 'LLM' if self.llm_client else 'Rule-based'
                }

                log.info(f"Root cause analysis report generated")
                return True

            return False

        except Exception as e:
            log.error(f"Failed to apply root cause analysis: {e}")
            return False

    def get_cost_estimate(self) -> float:
        """LLM 调用成本"""
        if self.llm_client:
            return 0.01  # 约 $0.01 per analysis
        return 0.0
