"""
Parameter Fix Strategy

自动修复 workflow 参数配置问题
"""

import logging
from typing import Dict, List, Any, Optional

log = logging.getLogger(__name__)


class ParameterFixStrategy:
    """参数修复策略"""

    def __init__(self):
        self.name = "parameter_fix"
        log.info(f"Initialized {self.name} strategy")

    def can_fix(self, issue: Dict[str, Any]) -> bool:
        """判断是否可以修复此问题"""
        issue_type = issue.get('type', '')
        return issue_type in ['parameter_error', 'parameter_missing', 'parameter_invalid']

    def generate_fix(self, issue: Dict[str, Any], context: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """生成修复方案"""
        try:
            param_name = self._extract_param_name(issue)
            if not param_name:
                return None

            fix = {
                'strategy': self.name,
                'issue_type': issue.get('type'),
                'param_name': param_name,
                'action': 'update_parameter',
                'description': f"自动修复参数: {param_name}",
                'risk_level': 'low',
                'auto_applicable': True
            }

            # 根据参数类型提供建议值
            if 'recommended_value' in issue:
                fix['new_value'] = issue['recommended_value']
            elif 'suggestion' in issue:
                fix['suggestion'] = issue['suggestion']

            return fix

        except Exception as e:
            log.error(f"Failed to generate fix for parameter issue: {e}")
            return None

    def _extract_param_name(self, issue: Dict[str, Any]) -> Optional[str]:
        """从问题描述中提取参数名"""
        message = issue.get('message', '')

        # 尝试从消息中提取参数名
        # 格式: "参数 'xxx': ..."
        if '参数' in message and '"' in message:
            start = message.find('"') + 1
            end = message.find('"', start)
            if start > 0 and end > start:
                return message[start:end]

        # 直接使用 evidence 中的参数名
        if 'param_name' in issue:
            return issue['param_name']

        return None

    def apply_fix(self, fix: Dict[str, Any], workflow_invocation) -> bool:
        """应用修复（实际修改参数）"""
        try:
            param_name = fix.get('param_name')
            new_value = fix.get('new_value')

            if not param_name:
                log.warning("Cannot apply fix: missing param_name")
                return False

            log.info(f"Applying parameter fix: {param_name} = {new_value}")

            # TODO: 实际更新 workflow_invocation 的参数
            # 这里需要访问 workflow_invocation.step_states 并更新相应的参数值

            return True

        except Exception as e:
            log.error(f"Failed to apply parameter fix: {e}")
            return False
