"""
Parameter Validation Fixer

检测和修复 Nextflow 参数验证错误

错误特征：
- 从 nextflow.err 解析
- error_type: 'parameter_validation'
- 错误格式: "--parameter (invalid_value): Expected any of [[valid1, valid2, ...]]"

修复策略：
1. 计算用户输入值与有效值的相似度（使用编辑距离）
2. 如果相似度 > 0.6，自动推荐最相似的值
3. 提供所有有效值的选择列表
4. 生成可执行的配置修改
"""

import difflib
import logging
from typing import List, Dict, Any, Optional

from galaxy.ai.workflow_ops.models import RootCause, Action, ConfigChange

log = logging.getLogger(__name__)


class ParameterValidationFixer:
    """参数验证错误修复器"""

    def __init__(self):
        self.name = "ParameterValidationFixer"

    def can_fix(self, root_cause: RootCause) -> bool:
        """
        检测是否是参数验证错误

        检测条件：
        1. root_cause.type == 'parameter_validation'
        2. description 包含 'invalid input values'
        3. description 包含 'Expected any of'
        """
        if root_cause.type == 'parameter_validation':
            return True

        desc_lower = root_cause.description.lower()
        return ('invalid input values' in desc_lower or
                'expected any of' in desc_lower)

    async def suggest_fixes(
        self,
        root_cause: RootCause,
        context: Dict[str, Any],
        trans
    ) -> List[Action]:
        """
        生成修复建议

        Returns:
            List[Action]: 修复动作列表
        """
        log.info(f"[ParameterValidationFixer] Analyzing root cause: {root_cause.type}")

        # 从 root_cause 提取参数信息
        param_info = self._extract_parameter_info(root_cause)

        if not param_info:
            log.warning(f"[ParameterValidationFixer] Failed to extract parameter info from: {root_cause.description}")
            return []

        param_name = param_info['parameter_name']
        invalid_value = param_info['invalid_value']
        valid_values = param_info['valid_values']
        error_subtype = param_info.get('error_subtype', 'unknown')

        log.info(f"[ParameterValidationFixer] Parameter: {param_name}, Invalid: {invalid_value}, Subtype: {error_subtype}")

        actions = []

        # 🆕 特殊处理: S3 路径验证错误
        if error_subtype == 's3_validation':
            s3_path = param_info.get('s3_path', invalid_value)
            s3_error_type = param_info.get('s3_error_type', 'unknown')

            actions = self._create_s3_validation_fixes(
                root_cause,
                context,
                param_name,
                s3_path,
                s3_error_type
            )
            log.info(f"[ParameterValidationFixer] Generated {len(actions)} S3 validation fix actions")
            return actions

        # 原有逻辑: 枚举值验证错误
        log.info(f"[ParameterValidationFixer] Valid values: {valid_values}")

        # 策略 1: 查找最相似的值（使用编辑距离）
        best_match = self._find_best_match(invalid_value, valid_values)

        if best_match:
            suggested_value, similarity = best_match

            # 如果相似度 > 0.6，认为是拼写错误
            if similarity > 0.6:
                actions.append(self._create_auto_fix_action(
                    root_cause,
                    context,
                    param_name,
                    invalid_value,
                    suggested_value,
                    similarity
                ))

        # 策略 2: 提供所有有效值的选择列表（总是提供）
        actions.append(self._create_choice_action(
            root_cause,
            context,
            param_name,
            invalid_value,
            valid_values
        ))

        log.info(f"[ParameterValidationFixer] Generated {len(actions)} fix actions")
        return actions

    def _extract_parameter_info(self, root_cause: RootCause) -> Optional[Dict[str, Any]]:
        """
        从 root_cause 提取参数信息

        从 description 解析：
        1. 枚举值错误: "--aligner (parabricks_fq2bam): Expected any of [bwa-mem, bwa-mem2, ...]"
        2. S3 路径错误: "--snpeff_cache (s3://annotation-cache/snpeff_cache/): could not validate file format of 's3://...': Could not parse XML response"

        Returns:
            {
                'parameter_name': 'aligner',
                'invalid_value': 'parabricks_fq2bam',
                'valid_values': ['bwa-mem', 'bwa-mem2', ...],
                'error_subtype': 'enum_validation' | 's3_validation'
            }
        """
        import re

        # Pattern 1: 枚举值验证错误
        match = re.search(
            r'--(\w+)\s*\(([^)]+)\):\s*Expected any of \[([^\]]+)\]',
            root_cause.description
        )

        if match:
            param_name = match.group(1)
            invalid_value = match.group(2).strip()
            valid_values_str = match.group(3)
            valid_values = [v.strip() for v in valid_values_str.split(',')]

            return {
                'parameter_name': param_name,
                'invalid_value': invalid_value,
                'valid_values': valid_values,
                'error_subtype': 'enum_validation'
            }

        # Pattern 2: S3 路径验证错误
        s3_match = re.search(
            r'--(\w+)\s*\(([^)]+)\):\s*could not validate file format of \'([^\']+)\'.*?(?:Could not parse XML response|NoSuchBucket|AccessDenied)',
            root_cause.description,
            re.DOTALL
        )

        if s3_match:
            param_name = s3_match.group(1)
            invalid_path = s3_match.group(2).strip()
            s3_path_detail = s3_match.group(3).strip()

            return {
                'parameter_name': param_name,
                'invalid_value': invalid_path,
                'valid_values': [],  # S3 路径错误没有枚举值
                'error_subtype': 's3_validation',
                's3_path': s3_path_detail,
                's3_error_type': self._detect_s3_error_type(root_cause.description)
            }

        # 如果是从 evidence 中提取的结构化数据
        if hasattr(root_cause, 'metadata') and root_cause.metadata:
            if 'parameter_name' in root_cause.metadata:
                return {
                    'parameter_name': root_cause.metadata['parameter_name'],
                    'invalid_value': root_cause.metadata['invalid_value'],
                    'valid_values': root_cause.metadata.get('valid_values', []),
                    'error_subtype': root_cause.metadata.get('error_subtype', 'unknown')
                }

        return None

    def _detect_s3_error_type(self, error_description: str) -> str:
        """
        检测 S3 错误的具体类型

        Returns:
            'no_such_bucket' | 'access_denied' | 'parse_xml_failed' | 'unknown'
        """
        desc_lower = error_description.lower()

        if 'nosuchbucket' in desc_lower or 'no such bucket' in desc_lower:
            return 'no_such_bucket'
        elif 'accessdenied' in desc_lower or 'access denied' in desc_lower:
            return 'access_denied'
        elif 'could not parse xml' in desc_lower:
            return 'parse_xml_failed'  # 可能是 bucket 不存在或权限问题
        else:
            return 'unknown'

    def _find_best_match(
        self,
        invalid_value: str,
        valid_values: List[str]
    ) -> Optional[tuple]:
        """
        查找最相似的有效值

        使用 SequenceMatcher 计算编辑距离

        Returns:
            (best_value, similarity_ratio) or None
        """
        if not valid_values:
            return None

        similarities = []
        for valid_value in valid_values:
            ratio = difflib.SequenceMatcher(
                None,
                invalid_value.lower(),
                valid_value.lower()
            ).ratio()
            similarities.append((valid_value, ratio))

        # 按相似度排序
        similarities.sort(key=lambda x: x[1], reverse=True)
        best_match = similarities[0]

        return best_match

    def _create_auto_fix_action(
        self,
        root_cause: RootCause,
        context: Dict[str, Any],
        param_name: str,
        invalid_value: str,
        suggested_value: str,
        similarity: float
    ) -> Action:
        """
        创建自动修复动作

        可以一键修复的建议
        """
        invocation_id = context.get('invocation_id', 'unknown')
        config_file = f"workflow_{invocation_id}/parameters.json"

        return Action(
            action_id=f"auto_fix_{param_name}_{root_cause.id}",
            title=f"修正参数 '{param_name}' 为推荐值",
            description=(
                f"检测到参数值可能是拼写错误：\n\n"
                f"**当前值**: `{invalid_value}`\n"
                f"**推荐值**: `{suggested_value}` (相似度 {similarity*100:.0f}%)\n\n"
                f"这是最接近的有效值，很可能是您想要的。\n\n"
                f"**自动修复**: 点击下方按钮将自动修改配置文件并重新运行 workflow。"
            ),
            auto_apply=True,  # ⭐ 可以自动修复
            risk_level="low",
            estimated_time_minutes=1,
            config_changes=[
                ConfigChange(
                    file_path=config_file,
                    change_type="modify",
                    old_value=f'"{param_name}": "{invalid_value}"',
                    new_value=f'"{param_name}": "{suggested_value}"',
                    line_number=None,  # 自动查找
                    description=f"修正参数 {param_name} 的值"
                )
            ],
            validation_command=None,
            rollback_possible=True
        )

    def _create_choice_action(
        self,
        root_cause: RootCause,
        context: Dict[str, Any],
        param_name: str,
        invalid_value: str,
        valid_values: List[str]
    ) -> Action:
        """
        创建选择动作

        提供所有有效值的选择列表
        """
        invocation_id = context.get('invocation_id', 'unknown')
        config_file = f"workflow_{invocation_id}/parameters.json"

        # 格式化有效值列表
        valid_values_display = '\n'.join([f"  • `{v}`" for v in valid_values])

        return Action(
            action_id=f"choose_{param_name}_{root_cause.id}",
            title=f"选择参数 '{param_name}' 的有效值",
            description=(
                f"参数 `--{param_name}` 的值 `{invalid_value}` 无效。\n\n"
                f"**允许的值**：\n{valid_values_display}\n\n"
                f"请从上述列表中选择一个值，或使用上方的自动修复建议。"
            ),
            auto_apply=False,  # 需要用户选择
            risk_level="low",
            estimated_time_minutes=1,
            config_changes=[
                ConfigChange(
                    file_path=config_file,
                    change_type="modify",
                    old_value=f'"{param_name}": "{invalid_value}"',
                    new_value=f'"{param_name}": "<user_choice>"',  # 占位符
                    description=f"修改参数 {param_name} 为用户选择的值"
                )
            ],
            validation_command=None,
            rollback_possible=True,
            # 🆕 额外元数据用于前端渲染选择器
            metadata={
                'parameter_name': param_name,
                'invalid_value': invalid_value,
                'valid_values': valid_values,
                'ui_type': 'dropdown'  # 前端应该渲染为下拉选择器
            }
        )

    def _create_s3_validation_fixes(
        self,
        root_cause: RootCause,
        context: Dict[str, Any],
        param_name: str,
        s3_path: str,
        s3_error_type: str
    ) -> List[Action]:
        """
        创建 S3 路径验证错误的修复建议

        Args:
            param_name: 参数名（如 'snpeff_cache'）
            s3_path: 无效的 S3 路径（如 's3://annotation-cache/snpeff_cache/'）
            s3_error_type: 错误类型（'no_such_bucket', 'access_denied', 'parse_xml_failed'）

        Returns:
            List[Action]: 3个修复建议
        """
        invocation_id = context.get('invocation_id', 'unknown')
        config_file = f"workflow_{invocation_id}/parameters.json"

        actions = []

        # 🔍 建议 1: 验证 S3 bucket 存在性和权限（最高优先级）
        if s3_error_type in ['no_such_bucket', 'parse_xml_failed']:
            error_desc = "S3 bucket 不存在或无法访问" if s3_error_type == 'no_such_bucket' else "无法解析 S3 响应（可能是 bucket 不存在或权限问题）"

            actions.append(Action(
                action_id=f"verify_s3_{param_name}_{root_cause.id}",
                title=f"验证 S3 路径存在性和权限",
                description=(
                    f"**错误原因**: {error_desc}\n\n"
                    f"**无效路径**: `{s3_path}`\n\n"
                    f"**诊断步骤**:\n\n"
                    f"1. 运行以下命令检查 S3 bucket 是否存在：\n"
                    f"   ```bash\n"
                    f"   aws s3 ls {s3_path}\n"
                    f"   ```\n\n"
                    f"2. 如果返回 `NoSuchBucket` 错误，说明 bucket 不存在\n"
                    f"3. 如果返回 `AccessDenied` 错误，说明当前 AWS 凭证没有访问权限\n\n"
                    f"**可能的解决方案**:\n"
                    f"- 如果 bucket 不存在：联系管理员创建或使用正确的 S3 路径\n"
                    f"- 如果权限不足：检查 AWS IAM 策略，确保有 `s3:ListBucket` 和 `s3:GetObject` 权限\n"
                ),
                auto_apply=False,  # 需要手动验证
                risk_level="low",
                estimated_time_minutes=5,
                config_changes=[],
                validation_command=f"aws s3 ls {s3_path}",
                rollback_possible=True,
                metadata={
                    'parameter_name': param_name,
                    's3_path': s3_path,
                    's3_error_type': s3_error_type,
                    'requires_manual_action': True
                }
            ))
        elif s3_error_type == 'access_denied':
            actions.append(Action(
                action_id=f"fix_s3_permissions_{param_name}_{root_cause.id}",
                title=f"修复 S3 权限问题",
                description=(
                    f"**错误原因**: 当前 AWS 凭证没有访问 `{s3_path}` 的权限\n\n"
                    f"**诊断步骤**:\n\n"
                    f"1. 检查当前 AWS 凭证：\n"
                    f"   ```bash\n"
                    f"   aws sts get-caller-identity\n"
                    f"   ```\n\n"
                    f"2. 检查 S3 bucket 策略：\n"
                    f"   ```bash\n"
                    f"   aws s3api get-bucket-policy --bucket annotation-cache\n"
                    f"   ```\n\n"
                    f"**解决方案**:\n"
                    f"- 联系 AWS 管理员添加 S3 访问权限\n"
                    f"- 或使用有权限的 AWS 凭证运行 workflow\n"
                ),
                auto_apply=False,
                risk_level="low",
                estimated_time_minutes=10,
                config_changes=[],
                validation_command=f"aws s3 ls {s3_path}",
                rollback_possible=True,
                metadata={
                    'parameter_name': param_name,
                    's3_path': s3_path,
                    's3_error_type': s3_error_type,
                    'requires_aws_admin': True
                }
            ))

        # ✂️ 建议 2: 移除参数（如果不需要此功能）
        actions.append(Action(
            action_id=f"remove_param_{param_name}_{root_cause.id}",
            title=f"移除参数 '{param_name}'",
            description=(
                f"如果不需要 `{param_name}` 功能，可以直接移除此参数。\n\n"
                f"**影响**:\n"
                f"- 相关功能将被禁用（如 SnpEff 注释、VEP 缓存等）\n"
                f"- Workflow 可以正常运行，但缺少某些注释信息\n\n"
                f"**自动修复**: 点击下方按钮将自动从配置中移除 `{param_name}` 并重新运行 workflow。"
            ),
            auto_apply=True,  # 可以自动修复
            risk_level="low",
            estimated_time_minutes=1,
            config_changes=[
                ConfigChange(
                    file_path=config_file,
                    change_type="remove",
                    old_value=f'"{param_name}": "{s3_path}"',
                    new_value="",  # 移除整行
                    description=f"移除参数 {param_name}"
                )
            ],
            validation_command=None,
            rollback_possible=True,
            metadata={
                'parameter_name': param_name,
                's3_path': s3_path,
                'removes_functionality': True
            }
        ))

        # 🔄 建议 3: 使用默认值或替代路径
        actions.append(Action(
            action_id=f"use_default_{param_name}_{root_cause.id}",
            title=f"使用默认配置",
            description=(
                f"让 pipeline 使用默认的 `{param_name}` 配置。\n\n"
                f"**说明**:\n"
                f"- 移除当前的无效路径\n"
                f"- Pipeline 将使用内置默认值或自动下载资源\n"
                f"- 可能会增加运行时间（首次下载缓存）\n\n"
                f"**自动修复**: 点击下方按钮将自动移除自定义路径，使用默认配置。"
            ),
            auto_apply=True,  # 可以自动修复
            risk_level="low",
            estimated_time_minutes=2,
            config_changes=[
                ConfigChange(
                    file_path=config_file,
                    change_type="remove",
                    old_value=f'"{param_name}": "{s3_path}"',
                    new_value="",
                    description=f"移除自定义 {param_name}，使用默认配置"
                )
            ],
            validation_command=None,
            rollback_possible=True,
            metadata={
                'parameter_name': param_name,
                's3_path': s3_path,
                'uses_default': True
            }
        ))

        return actions
