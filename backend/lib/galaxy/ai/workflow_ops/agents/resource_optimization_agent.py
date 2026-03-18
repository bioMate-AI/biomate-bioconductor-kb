"""
Resource Optimization Agent

专门处理资源相关问题：
- OOM (Out of Memory)
- CPU 利用率过低/过高
- 磁盘空间不足
- 资源配置建议
"""

import re
import logging
from typing import Dict, List, Any
from ..agent_system import (
    BaseAgent,
    AgentCapability,
    AgentTriggerCondition,
    AgentPriority
)

log = logging.getLogger(__name__)


class ResourceOptimizationAgent(BaseAgent):
    """资源优化专家 Agent"""

    @property
    def name(self) -> str:
        return "ResourceOptimizationAgent"

    @property
    def capability(self) -> AgentCapability:
        return AgentCapability.RESOURCE_OPTIMIZATION

    @property
    def trigger_conditions(self) -> List[AgentTriggerCondition]:
        return [
            AgentTriggerCondition.ON_ERROR,
            AgentTriggerCondition.ON_COMPLETION  # 完成后也可以提供优化建议
        ]

    @property
    def priority(self) -> AgentPriority:
        return AgentPriority.HIGH  # 资源问题优先级较高

    @property
    def requires_llm(self) -> bool:
        return False  # 不需要 LLM，基于规则即可

    def can_handle(self, issue: Dict[str, Any]) -> bool:
        """判断是否能处理该问题"""
        message = issue.get('message', '').lower()
        issue_type = issue.get('type', '')

        # 检测关键词
        resource_keywords = [
            'out of memory', 'oom', 'memory', '内存',
            'cpu', 'disk', '磁盘',
            'resource', '资源'
        ]

        for keyword in resource_keywords:
            if keyword in message or keyword in issue_type:
                return True

        return False

    async def analyze(self, context: Dict[str, Any]) -> Dict[str, Any]:
        """分析资源问题"""
        invocation = context.get('invocation')
        logs = context.get('logs', '')

        analysis = {
            'issue_type': None,
            'current_config': {},
            'resource_usage': {},
            'recommendations': []
        }

        # 1. 检测 OOM
        if 'out of memory' in logs.lower() or 'oom' in logs.lower():
            analysis['issue_type'] = 'out_of_memory'

            # 提取当前内存配置
            memory_match = re.search(r'memory\s*[=:]\s*["\']?(\d+)\s*(GB|MB|G|M)', logs, re.IGNORECASE)
            if memory_match:
                value = int(memory_match.group(1))
                unit = memory_match.group(2).upper()
                if unit in ['GB', 'G']:
                    current_memory_gb = value
                else:  # MB or M
                    current_memory_gb = value / 1024

                analysis['current_config']['memory'] = f'{current_memory_gb} GB'

                # 建议增加 2倍内存
                recommended_memory = current_memory_gb * 2
                analysis['recommendations'].append({
                    'type': 'increase_memory',
                    'current': f'{current_memory_gb} GB',
                    'suggested': f'{recommended_memory} GB',
                    'reason': 'Process exceeded memory limit'
                })
            else:
                # 默认建议
                analysis['recommendations'].append({
                    'type': 'increase_memory',
                    'suggested': '16 GB',
                    'reason': 'Memory limit exceeded, no current config found'
                })

        # 2. 检测 CPU 问题
        cpu_pattern = r'cpu\s*[=:]\s*(\d+)'
        cpu_match = re.search(cpu_pattern, logs, re.IGNORECASE)
        if cpu_match:
            current_cpu = int(cpu_match.group(1))
            analysis['current_config']['cpu'] = current_cpu

            # 如果 CPU < 4，建议增加
            if current_cpu < 4:
                analysis['recommendations'].append({
                    'type': 'increase_cpu',
                    'current': current_cpu,
                    'suggested': 4,
                    'reason': 'Low CPU count may cause slow execution'
                })

        # 3. 检测磁盘空间问题
        if 'disk' in logs.lower() or 'no space' in logs.lower():
            analysis['issue_type'] = 'disk_space'
            analysis['recommendations'].append({
                'type': 'increase_disk',
                'suggested': '100 GB',
                'reason': 'Insufficient disk space detected'
            })

        log.info(f"Resource analysis completed: {analysis['issue_type']}")
        return analysis

    async def suggest_fix(self, context: Dict[str, Any]) -> List[Dict[str, Any]]:
        """提供修复建议"""
        analysis = await self.analyze(context)
        suggestions = []

        for recommendation in analysis['recommendations']:
            if recommendation['type'] == 'increase_memory':
                suggestions.append({
                    'action': 'update_memory_config',
                    'description': f"增加内存至 {recommendation['suggested']}",
                    'risk_level': 'low',
                    'config_change': {
                        'memory': recommendation['suggested']
                    },
                    'before': recommendation.get('current', 'Not set'),
                    'after': recommendation['suggested']
                })

            elif recommendation['type'] == 'increase_cpu':
                suggestions.append({
                    'action': 'update_cpu_config',
                    'description': f"增加 CPU 至 {recommendation['suggested']}",
                    'risk_level': 'low',
                    'config_change': {
                        'cpu': recommendation['suggested']
                    },
                    'before': recommendation.get('current', 'Not set'),
                    'after': recommendation['suggested']
                })

            elif recommendation['type'] == 'increase_disk':
                suggestions.append({
                    'action': 'increase_disk_space',
                    'description': f"增加磁盘空间至 {recommendation['suggested']}",
                    'risk_level': 'medium',
                    'config_change': {
                        'disk': recommendation['suggested']
                    }
                })

        return suggestions

    async def apply_fix(self, fix_plan: Dict[str, Any], context: Dict[str, Any]) -> bool:
        """
        应用修复

        注意：这里只是记录修复建议，实际的配置修改需要：
        1. 更新 nextflow.config (但会被覆盖)
        2. 更新 Galaxy 的 job_conf.yml
        3. 重新启动 workflow

        所以这里只返回指导信息
        """
        action = fix_plan.get('action')
        config_change = fix_plan.get('config_change', {})

        try:
            if action == 'update_memory_config':
                memory = config_change.get('memory')
                log.info(f"Resource optimization: Recommend setting memory to {memory}")

                # 生成配置指导
                guidance = f"""
✅ 资源优化建议已生成

📋 问题：内存不足
💡 建议：增加内存至 {memory}

🔧 修复步骤：

方法1: 在 Galaxy Workflow 编辑器中设置
  1. 打开 Galaxy → Workflows
  2. 找到该 workflow，点击 "编辑"
  3. 找到失败的 tool step
  4. 在右侧参数面板找到 "Resources" 部分
  5. 设置 Memory: {memory}
  6. 保存并重新运行

方法2: 修改 job_conf.yml（管理员）
  编辑 config/job_conf.yml:
  ```yaml
  tools:
    - id: your_tool_id
      resources:
        memory: {memory}
  ```

方法3: 在 Nextflow 配置中设置（高级）
  如果使用 Nextflow，添加到 process 配置：
  ```groovy
  process {{
      withName: 'YOUR_PROCESS_NAME' {{
          memory = '{memory}'
      }}
  }}
  ```

⚠️ 注意：修改后需要重新运行 workflow
"""
                # 将指导信息保存到 context，前端可以显示
                if 'fix_guidance' not in context:
                    context['fix_guidance'] = []
                context['fix_guidance'].append(guidance)

                return True  # 表示建议已生成

            elif action == 'update_cpu_config':
                cpu = config_change.get('cpu')
                log.info(f"Resource optimization: Recommend setting CPU to {cpu}")

                guidance = f"""
✅ 资源优化建议已生成

📋 问题：CPU 配置过低
💡 建议：增加 CPU 至 {cpu} 核

🔧 修复步骤：
  参考内存配置方法，设置 CPU 参数为 {cpu}
"""
                if 'fix_guidance' not in context:
                    context['fix_guidance'] = []
                context['fix_guidance'].append(guidance)

                return True

            else:
                log.warning(f"Unknown action: {action}")
                return False

        except Exception as e:
            log.error(f"Failed to apply resource fix: {e}")
            return False

    def get_cost_estimate(self) -> float:
        """资源优化不需要 LLM，成本为 0"""
        return 0.0
