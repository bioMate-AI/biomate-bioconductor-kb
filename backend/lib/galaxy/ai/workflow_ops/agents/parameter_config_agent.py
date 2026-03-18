"""
Parameter Configuration Agent

专门处理参数相关问题：
- 缺少必需参数
- 参数值错误
- 参数类型不匹配
"""

import re
import logging
from typing import Dict, List, Any, Optional
from ..agent_system import (
    BaseAgent,
    AgentCapability,
    AgentTriggerCondition,
    AgentPriority
)

log = logging.getLogger(__name__)


class ParameterConfigAgent(BaseAgent):
    """参数配置专家 Agent"""

    @property
    def name(self) -> str:
        return "ParameterConfigAgent"

    @property
    def capability(self) -> AgentCapability:
        return AgentCapability.PARAMETER_CONFIG

    @property
    def trigger_conditions(self) -> List[AgentTriggerCondition]:
        return [
            AgentTriggerCondition.ON_ERROR,
            AgentTriggerCondition.ON_WARNING
        ]

    @property
    def priority(self) -> AgentPriority:
        return AgentPriority.CRITICAL  # 参数问题优先级最高

    @property
    def requires_llm(self) -> bool:
        return False  # 基于规则即可

    def can_handle(self, issue: Dict[str, Any]) -> bool:
        """判断是否能处理该问题"""
        message = issue.get('message', '').lower()
        issue_type = issue.get('type', '').lower()

        # 检测参数相关关键词
        param_keywords = [
            'parameter', 'param', '参数',
            'schema_ignore_params',
            'missing', 'required',
            'invalid', '错误', '缺少'
        ]

        for keyword in param_keywords:
            if keyword in message or keyword in issue_type:
                return True

        return False

    async def analyze(self, context: Dict[str, Any]) -> Dict[str, Any]:
        """分析参数问题"""
        issue = context.get('issue', {})
        message = issue.get('message', '')
        logs = context.get('logs', '')
        invocation = context.get('invocation')

        analysis = {
            'issue_type': 'parameter_config',
            'missing_params': [],
            'invalid_params': [],
            'unconfigured_params': [],  # 新增：参数已定义但未配置
            'param_suggestions': {},
            'param_states': {}  # 新增：每个参数的实际状态
        }

        # 1. 提取缺少的参数
        param_pattern = r'params\.schema_ignore_params\s*=\s*\[([^\]]+)\]'
        match = re.search(param_pattern, message + logs)

        params_to_check = []
        if match:
            params_str = match.group(1)
            params_to_check = [p.strip().strip('"\'') for p in params_str.split(',')]

        # 同时从错误消息中提取参数（如 "parameter 'ncrna_fasta'"）
        param_mention_pattern = r'parameter\s+["\']?(\w+)["\']?'
        for param_match in re.finditer(param_mention_pattern, message + logs, re.IGNORECASE):
            param_name = param_match.group(1)
            if param_name not in params_to_check:
                params_to_check.append(param_name)

        # 2. 🔑 新增：检查数据库中的参数实际配置状态
        if invocation and params_to_check:
            param_states = self._check_parameter_states(invocation, params_to_check)
            analysis['param_states'] = param_states

            for param_name, state in param_states.items():
                if state['status'] == 'not_defined':
                    # 参数在 Tool XML 中不存在
                    analysis['missing_params'].append(param_name)
                    analysis['param_suggestions'][param_name] = {
                        'value': self._get_default_value(param_name),
                        'note': '⚠️ 该参数不在 Tool XML 中，可能是 pipeline 版本不匹配'
                    }
                elif state['status'] == 'unconfigured':
                    # 参数已定义但用户未配置（值为 None 或空）
                    analysis['unconfigured_params'].append(param_name)
                    analysis['param_suggestions'][param_name] = {
                        'value': self._get_default_value(param_name),
                        'note': f"✏️ 请在 Galaxy UI 中配置该参数（当前值: {state['current_value']}）"
                    }
                    log.info(f"Parameter '{param_name}' is defined but not configured (value={state['current_value']})")
                elif state['status'] == 'configured':
                    # 参数已配置，但可能值不正确
                    analysis['invalid_params'].append({
                        'name': param_name,
                        'current_value': state['current_value'],
                        'suggested_value': self._get_default_value(param_name),
                        'note': '⚠️ 参数已配置但可能值不正确'
                    })
        else:
            # 如果没有 invocation 或没有参数要检查，使用旧的正则匹配逻辑
            for param in params_to_check:
                analysis['missing_params'].append(param)
                analysis['param_suggestions'][param] = {
                    'value': self._get_default_value(param),
                    'note': '(未能检查数据库状态)'
                }

        # 2. 检测无效参数值
        invalid_pattern = r'Invalid\s+(?:value|parameter)\s+["\']?(\w+)["\']?\s*[:=]\s*["\']?([^"\']+)["\']?'
        invalid_matches = re.finditer(invalid_pattern, message + logs, re.IGNORECASE)

        for match in invalid_matches:
            param_name = match.group(1)
            invalid_value = match.group(2)
            analysis['invalid_params'].append({
                'name': param_name,
                'current_value': invalid_value,
                'suggested_value': self._get_default_value(param_name)
            })

        log.info(
            f"Parameter analysis: "
            f"not_defined={len(analysis['missing_params'])}, "
            f"unconfigured={len(analysis['unconfigured_params'])}, "
            f"invalid={len(analysis['invalid_params'])}"
        )
        return analysis

    def _check_parameter_states(self, invocation, param_names: List[str]) -> Dict[str, Dict[str, Any]]:
        """
        检查参数在数据库中的实际配置状态

        返回每个参数的状态:
        - not_defined: 参数在 Tool XML 中不存在
        - unconfigured: 参数已定义但用户未配置（值为 None 或空）
        - configured: 参数已配置
        """
        import json

        param_states = {}

        try:
            # 找到 Engine step (Nextflow tool)
            engine_step = None
            for step in invocation.workflow.steps:
                if step.type == 'tool' and step.tool_id and 'nextflow' in step.tool_id.lower():
                    engine_step = step
                    break

            if not engine_step:
                log.warning(f"Could not find engine step in workflow {invocation.workflow.id}")
                for param_name in param_names:
                    param_states[param_name] = {
                        'status': 'not_defined',
                        'current_value': None,
                        'note': 'Engine step not found'
                    }
                return param_states

            # 🔑 关键修复：优先读取运行时参数（workflow_request_step_states）
            # 而不是 workflow 定义中的默认值（workflow_step.tool_inputs）
            tool_inputs = {}

            # 1. 尝试从 invocation.step_states 读取（运行时参数）
            runtime_params_found = False
            if hasattr(invocation, 'step_states') and invocation.step_states:
                for step_state in invocation.step_states:
                    if hasattr(step_state, 'workflow_step') and step_state.workflow_step.id == engine_step.id:
                        if hasattr(step_state, 'value') and step_state.value:
                            runtime_params_found = True
                            if isinstance(step_state.value, str):
                                tool_inputs = json.loads(step_state.value)
                            else:
                                tool_inputs = step_state.value
                            log.info(f"✅ Found runtime parameters for workflow {invocation.id} from step_states")
                            break

            # 2. 如果没有运行时参数，降级到 workflow 定义中的默认值
            if not runtime_params_found:
                if hasattr(engine_step, 'tool_inputs') and engine_step.tool_inputs:
                    if isinstance(engine_step.tool_inputs, str):
                        tool_inputs = json.loads(engine_step.tool_inputs)
                    else:
                        tool_inputs = engine_step.tool_inputs
                    log.warning(f"⚠️ No runtime parameters found for workflow {invocation.id}, using workflow definition defaults")

            # 检查每个参数
            for param_name in param_names:
                # 尝试多个可能的参数名格式
                possible_keys = [
                    f'param_{param_name}',  # 标准格式
                    param_name,  # 直接名称
                ]

                # 还要检查 sections 中的参数
                section_keys = [k for k in tool_inputs.keys() if k.startswith('section_')]

                param_found = False
                param_value = None

                # 1. 检查顶层参数
                for key in possible_keys:
                    if key in tool_inputs:
                        param_found = True
                        param_value = tool_inputs[key]
                        break

                # 2. 检查 section 中的参数
                if not param_found:
                    for section_key in section_keys:
                        section_value = tool_inputs.get(section_key, {})
                        if isinstance(section_value, str):
                            try:
                                section_value = json.loads(section_value)
                            except json.JSONDecodeError:
                                continue

                        if isinstance(section_value, dict):
                            for key in possible_keys:
                                if key in section_value:
                                    param_found = True
                                    param_value = section_value[key]
                                    break

                        if param_found:
                            break

                # 判断状态
                if not param_found:
                    param_states[param_name] = {
                        'status': 'not_defined',
                        'current_value': None,
                        'note': 'Parameter not found in Tool XML'
                    }
                elif param_value is None or param_value == '' or str(param_value).strip() == 'None':
                    param_states[param_name] = {
                        'status': 'unconfigured',
                        'current_value': str(param_value),
                        'note': 'Parameter defined but not configured by user'
                    }
                else:
                    param_states[param_name] = {
                        'status': 'configured',
                        'current_value': str(param_value),
                        'note': 'Parameter has a value'
                    }

            return param_states

        except Exception as e:
            log.error(f"Failed to check parameter states: {e}")
            import traceback
            log.error(traceback.format_exc())

            # 降级：返回未知状态
            for param_name in param_names:
                param_states[param_name] = {
                    'status': 'not_defined',
                    'current_value': None,
                    'note': f'Error checking: {str(e)}'
                }
            return param_states

    def _get_default_value(self, param_name: str) -> str:
        """根据参数名推测合理的默认值"""
        # 常见参数的默认值映射
        defaults = {
            'source': 'local',
            'genome': 'hg38',
            'aligner': 'star',
            'input': 'input.fastq',
            'output': 'output.bam',
            'threads': '4',
            'memory': '8GB',
            'single_end': 'false',
            'paired_end': 'true',
            'read_length': '150',
            'quality_threshold': '20',
            'adapter': 'AGATCGGAAGAGC',
            'species': 'human',
            'mirtrace_species': 'hsa',
            'ncrna_fasta': 'ncRNA.fa'
        }

        param_lower = param_name.lower()

        # 精确匹配
        if param_lower in defaults:
            return defaults[param_lower]

        # 模糊匹配
        for key, value in defaults.items():
            if key in param_lower or param_lower in key:
                return value

        # 默认值
        return '<请根据需求设置>'

    async def suggest_fix(self, context: Dict[str, Any]) -> List[Dict[str, Any]]:
        """提供修复建议"""
        analysis = await self.analyze(context)
        suggestions = []

        # 1. 为未配置的参数生成建议（优先级最高）
        if analysis['unconfigured_params']:
            param_list = ', '.join(analysis['unconfigured_params'])
            param_details = []
            for p in analysis['unconfigured_params']:
                suggestion = analysis['param_suggestions'].get(p, {})
                if isinstance(suggestion, dict):
                    value = suggestion.get('value', '<请设置>')
                    note = suggestion.get('note', '')
                else:
                    value = suggestion
                    note = ''
                param_details.append(f'     • {p}: {value}\n       {note}')

            suggestions.append({
                'action': 'configure_parameters',
                'description': f'⚠️ 参数已定义但未配置: {param_list}',
                'risk_level': 'medium',
                'unconfigured_params': analysis['unconfigured_params'],
                'suggested_values': analysis['param_suggestions'],
                'guidance': f"""
⚠️ 参数未配置

📋 以下参数已在 Tool XML 中定义，但您在运行 workflow 时未填写值：
{param_list}

🔍 当前状态：
{chr(10).join(param_details)}

🔧 修复步骤：

方法 1: 重新运行 Workflow 并配置参数
  1. 在 Galaxy 中点击 "Run Workflow"
  2. 找到这些参数的输入框
  3. 填写推荐值（见上方）
  4. 点击 "Execute"

方法 2: 在 Workflow 编辑器中设置默认值
  1. Galaxy → Workflows → 编辑该 workflow
  2. 找到 Nextflow 工具 step
  3. 设置参数默认值
  4. 保存 workflow

⚠️ 注意: 这些参数可能是必需的，不配置可能导致 workflow 失败！
"""
            })

        # 2. 为缺少的参数生成建议（参数在 Tool XML 中不存在）
        if analysis['missing_params']:
            param_list = ', '.join(analysis['missing_params'])
            param_configs = '\n'.join([
                f"{p}: {analysis['param_suggestions'].get(p, '<请设置>')}"
                for p in analysis['missing_params']
            ])

            suggestions.append({
                'action': 'add_missing_parameters',
                'description': f'❌ 参数不在 Tool XML 中: {param_list}',
                'risk_level': 'high',
                'missing_params': analysis['missing_params'],
                'suggested_values': analysis['param_suggestions'],
                'guidance': f"""
❌ 参数不存在

📋 以下参数在 Tool XML 中未定义：{param_list}

🔍 可能的原因：
  1. Pipeline 版本不匹配（Tool XML 可能是旧版本）
  2. 参数名称拼写错误
  3. 该参数可能在新版 pipeline 中被移除或重命名

🔧 解决方法：

方法 1: 更新 Tool XML
  1. 重新从 Nextflow pipeline schema 生成 Tool XML
  2. 确保 pipeline 版本与 Tool XML 一致

方法 2: 检查参数名称
  1. 查看 pipeline 的 nextflow_schema.json
  2. 确认参数的正确名称

方法 3: 使用其他参数替代
  某些参数可能在新版本中改名了，请查看文档
"""
            })

        # 2. 为无效参数生成建议
        for invalid in analysis['invalid_params']:
            suggestions.append({
                'action': 'fix_invalid_parameter',
                'description': f'修正参数 {invalid["name"]} 的值',
                'risk_level': 'medium',
                'param_name': invalid['name'],
                'current_value': invalid['current_value'],
                'suggested_value': invalid['suggested_value'],
                'guidance': f"""
⚠️ 参数值错误

参数名: {invalid["name"]}
当前值: {invalid["current_value"]}
建议值: {invalid["suggested_value"]}

请在 workflow 中更新此参数的值
"""
            })

        return suggestions

    async def apply_fix(self, fix_plan: Dict[str, Any], context: Dict[str, Any]) -> bool:
        """应用修复（生成指导）"""
        try:
            guidance = fix_plan.get('guidance', '')

            if guidance:
                # 保存指导信息到 context
                if 'fix_guidance' not in context:
                    context['fix_guidance'] = []
                context['fix_guidance'].append(guidance)

                log.info(f"Parameter fix guidance generated: {fix_plan.get('action')}")
                return True

            return False

        except Exception as e:
            log.error(f"Failed to apply parameter fix: {e}")
            return False

    def get_cost_estimate(self) -> float:
        """基于规则，无 LLM 成本"""
        return 0.0
