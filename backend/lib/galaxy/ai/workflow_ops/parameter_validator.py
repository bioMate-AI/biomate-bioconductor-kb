"""
Workflow Parameter Validator - Hybrid Configuration Architecture

混合配置驱动的参数验证器：
- 优先从 nextflow_schema.json 自动读取（零配置）
- 支持手动配置扩展（Galaxy 特定业务规则）
- 无硬编码 if-else
- 新增 nf-core workflow 零配置！

Usage:
    from galaxy.ai.workflow_ops.parameter_validator import validate_workflow_parameters

    result = validate_workflow_parameters(trans, 'nfcore/rnaseq', params)
    # ✅ 自动从 nextflow_schema.json 读取验证规则！
    if not result.valid:
        raise HTTPException(status_code=400, detail=result.to_dict())
"""

import logging
import os
import re
import yaml
from typing import Any, Dict, List, Optional
from pathlib import Path

log = logging.getLogger(__name__)


class ValidationError:
    """验证错误"""

    def __init__(self, field: str, message: str, severity: str = 'error'):
        self.field = field
        self.message = message
        self.severity = severity  # 'error' 或 'warning'

    def to_dict(self) -> Dict[str, str]:
        return {
            'field': self.field,
            'message': self.message,
            'severity': self.severity
        }


class ValidationResult:
    """验证结果"""

    def __init__(self):
        self.errors: List[ValidationError] = []
        self.warnings: List[ValidationError] = []

    @property
    def valid(self) -> bool:
        """是否验证通过（没有错误）"""
        return len(self.errors) == 0

    def add_error(self, field: str, message: str):
        """添加错误"""
        self.errors.append(ValidationError(field, message, 'error'))

    def add_warning(self, field: str, message: str):
        """添加警告"""
        self.warnings.append(ValidationError(field, message, 'warning'))

    def to_dict(self) -> Dict[str, Any]:
        """转换为字典"""
        return {
            'valid': self.valid,
            'errors': [e.to_dict() for e in self.errors],
            'warnings': [w.to_dict() for w in self.warnings]
        }


class ValidationConfigLoader:
    """验证配置加载器"""

    _config_cache: Optional[Dict[str, Any]] = None

    @classmethod
    def load_config(cls) -> Dict[str, Any]:
        """加载验证配置"""
        if cls._config_cache is not None:
            return cls._config_cache

        config_path = Path(__file__).parent / 'validation_config.yaml'

        try:
            with open(config_path, 'r', encoding='utf-8') as f:
                config = yaml.safe_load(f)
            cls._config_cache = config
            log.info(f"加载验证配置成功: {config_path}")
            return config
        except Exception as e:
            log.error(f"加载验证配置失败: {e}", exc_info=True)
            # 返回最小默认配置
            return {
                'default': {
                    'required_params': ['input'],
                    'file_params': ['input', 'fasta', 'gtf']
                }
            }

    @classmethod
    def get_config_for_tool(cls, tool_name: str) -> Dict[str, Any]:
        """
        获取指定工具的验证配置（支持继承和通配符）

        Args:
            tool_name: 工具名称（如 'nfcore/clipseq'）

        Returns:
            合并后的配置字典
        """
        all_configs = cls.load_config()

        # 1. 从 default 开始
        config = all_configs.get('default', {}).copy()

        # 2. 精确匹配
        if tool_name in all_configs:
            tool_config = all_configs[tool_name]
            config = cls._merge_config(config, tool_config, all_configs)
            return config

        # 3. 通配符匹配
        for pattern, pattern_config in all_configs.items():
            if cls._matches_pattern(tool_name, pattern):
                config = cls._merge_config(config, pattern_config, all_configs)

        # 4. 如果没有匹配，使用 unknown fallback
        if not config or config == all_configs.get('default', {}):
            if 'unknown' in all_configs:
                config = cls._merge_config(config, all_configs['unknown'], all_configs)

        log.info(f"工具 {tool_name} 使用验证配置: {list(config.keys())}")
        return config

    @classmethod
    def _merge_config(cls, base: Dict[str, Any], override: Dict[str, Any], all_configs: Dict[str, Any]) -> Dict[str, Any]:
        """
        合并配置（处理 extends）

        Args:
            base: 基础配置
            override: 覆盖配置
            all_configs: 所有配置（用于解析 extends）

        Returns:
            合并后的配置
        """
        result = base.copy()

        # 处理 extends
        if 'extends' in override:
            parent_name = override['extends']
            if parent_name in all_configs:
                parent_config = all_configs[parent_name]
                result = cls._merge_config(result, parent_config, all_configs)

        # 合并其他字段
        for key, value in override.items():
            if key == 'extends':
                continue

            if isinstance(value, dict) and key in result and isinstance(result[key], dict):
                # 递归合并字典
                result[key] = {**result[key], **value}
            elif isinstance(value, list) and key in result and isinstance(result[key], list):
                # 合并列表（去重）
                result[key] = list(set(result[key] + value))
            else:
                # 直接覆盖
                result[key] = value

        return result

    @classmethod
    def _matches_pattern(cls, tool_name: str, pattern: str) -> bool:
        """
        检查工具名是否匹配通配符模式

        支持:
        - * 匹配任意字符
        - nfcore/* 匹配所有 nfcore workflow
        - *seq 匹配所有以 seq 结尾的 workflow

        Args:
            tool_name: 工具名称
            pattern: 通配符模式

        Returns:
            是否匹配
        """
        if '*' not in pattern:
            return False

        # 转换为正则表达式
        regex_pattern = pattern.replace('*', '.*')
        regex_pattern = f'^{regex_pattern}$'

        try:
            return bool(re.match(regex_pattern, tool_name, re.IGNORECASE))
        except Exception:
            return False


class WorkflowParameterValidator:
    """工作流参数验证器 - 配置驱动"""

    # S3 路径正则
    S3_PATH_PATTERN = re.compile(r'^s3://[a-zA-Z0-9\-\.]+/.+')

    # dataset_id 格式正则
    DATASET_ID_PATTERN = re.compile(r'^dataset_id:[a-zA-Z0-9]+$')

    def __init__(self, trans, tool_name: str):
        """
        初始化验证器

        Args:
            trans: Galaxy transaction context
            tool_name: 工具名称（如 'nfcore/clipseq'）
        """
        self.trans = trans
        self.tool_name = tool_name
        self.app = trans.app
        self.sa_session = trans.sa_session
        self.security = trans.security

        # 🆕 使用混合配置加载器（自动从 schema + 手动配置）
        from .hybrid_config_loader import HybridConfigLoader
        hybrid_loader = HybridConfigLoader()
        self.config = hybrid_loader.load_config(tool_name)

        log.info(f"🔧 验证器初始化: {tool_name}")
        log.info(f"   必需参数: {len(self.config.get('required_params', []))}")
        log.info(f"   参数约束: {len(self.config.get('param_constraints', {}))}")

    def validate(self, params: Dict[str, Any]) -> ValidationResult:
        """
        验证工作流参数（完全基于配置驱动）

        Args:
            params: 工作流参数字典

        Returns:
            ValidationResult: 验证结果
        """
        result = ValidationResult()

        log.info(f"开始验证参数，工具: {self.tool_name}")

        # 1. 验证必需参数（从配置读取）
        self._validate_required_params(params, result)

        # 2. 验证文件路径（从配置读取）
        self._validate_file_paths(params, result)

        # 3. 验证参考基因组（从配置读取）
        self._validate_reference_genome(params, result)

        # 4. 验证推荐参数（从配置读取）
        self._validate_recommended_params(params, result)

        # 5. 验证参数约束（从配置读取）
        self._validate_param_constraints(params, result)

        log.info(f"参数验证完成: valid={result.valid}, errors={len(result.errors)}, warnings={len(result.warnings)}")

        return result

    def _validate_required_params(self, params: Dict[str, Any], result: ValidationResult):
        """验证必需参数（从配置读取）"""

        required_params = self.config.get('required_params', [])

        for param_name in required_params:
            if param_name not in params or not params[param_name]:
                result.add_error(
                    param_name,
                    f"缺少必需参数: {param_name}"
                )
                log.warning(f"缺少必需参数: {param_name}")

    def _validate_file_paths(self, params: Dict[str, Any], result: ValidationResult):
        """验证文件路径（从配置读取）"""

        file_params = self.config.get('file_params', [])

        for param_name in file_params:
            if param_name not in params:
                continue

            path = params[param_name]
            if not path:
                continue

            # 验证路径格式
            if not self._is_valid_path_format(path):
                result.add_error(
                    param_name,
                    f"路径格式不正确: {path}"
                )
                log.warning(f"参数 {param_name} 路径格式不正确: {path}")
                continue

            # 如果是 dataset_id，验证数据集存在
            if path.startswith('dataset_id:'):
                dataset_id = path.replace('dataset_id:', '')
                if not self._dataset_exists(dataset_id):
                    result.add_error(
                        param_name,
                        f"数据集不存在或已删除: {dataset_id}"
                    )
                    log.warning(f"数据集不存在: {dataset_id}")

            # 如果是 S3 路径，验证格式
            elif path.startswith('s3://'):
                if not self.S3_PATH_PATTERN.match(path):
                    result.add_warning(
                        param_name,
                        f"S3 路径格式可能不正确: {path}"
                    )
                    log.info(f"S3 路径格式警告: {path}")

            # 如果是本地路径，验证文件存在（可选）
            elif path.startswith('/'):
                # 本地路径验证（可能权限不足，只作为警告）
                if not os.path.exists(path):
                    result.add_warning(
                        param_name,
                        f"本地文件可能不存在: {path}"
                    )

    def _validate_reference_genome(self, params: Dict[str, Any], result: ValidationResult):
        """验证参考基因组（从配置读取）"""

        ref_config = self.config.get('reference_genome_check', {})

        if not ref_config.get('enabled', True):
            return

        has_genome = 'genome' in params and params['genome']
        has_fasta = 'fasta' in params and params['fasta']
        has_gtf = 'gtf' in params and params['gtf']

        # 从配置读取验证规则
        rules = ref_config.get('rules', [])

        for rule in rules:
            condition = rule.get('condition')
            message = rule.get('error') or rule.get('warning')
            field = rule.get('field', 'genome')

            if condition == 'no_genome_and_no_fasta':
                if not has_genome and not has_fasta:
                    if 'error' in rule:
                        result.add_error(field, message)
                    else:
                        result.add_warning(field, message)

            elif condition == 'has_gtf_but_no_fasta':
                if has_gtf and not has_fasta:
                    if 'error' in rule:
                        result.add_error(field, message)
                    else:
                        result.add_warning(field, message)

    def _validate_recommended_params(self, params: Dict[str, Any], result: ValidationResult):
        """验证推荐参数（从配置读取）"""

        recommended = self.config.get('recommended_params', {})

        for param_name, config in recommended.items():
            if param_name not in params or not params[param_name]:
                warning_msg = config.get('warning')
                if warning_msg:
                    result.add_warning(param_name, warning_msg)

    def _validate_param_constraints(self, params: Dict[str, Any], result: ValidationResult):
        """验证参数约束（从配置读取）"""

        constraints = self.config.get('param_constraints', {})

        for param_name, constraint in constraints.items():
            if param_name not in params:
                continue

            value = params[param_name]
            if not value:
                continue

            # 验证文件格式
            if constraint.get('type') == 'file':
                formats = constraint.get('formats', [])
                if formats:
                    if not any(str(value).endswith(fmt) for fmt in formats):
                        result.add_warning(
                            param_name,
                            f"文件格式可能不正确，期望: {', '.join(formats)}"
                        )

            # 验证选择值
            elif constraint.get('type') == 'select':
                allowed = constraint.get('allowed_values', [])
                if allowed and value not in allowed:
                    result.add_error(
                        param_name,
                        f"参数值无效，允许的值: {', '.join(allowed)}"
                    )

    def _is_valid_path_format(self, path: str) -> bool:
        """检查路径格式是否有效"""

        if not path:
            return False

        # dataset_id: 格式
        if self.DATASET_ID_PATTERN.match(path):
            return True

        # S3 路径
        if path.startswith('s3://'):
            return True

        # 绝对路径
        if path.startswith('/'):
            return True

        # 其他格式视为无效
        return False

    def _dataset_exists(self, encoded_id: str) -> bool:
        """检查数据集是否存在"""
        from galaxy.model import HistoryDatasetAssociation

        try:
            decoded_id = self.security.decode_id(encoded_id)
            hda = self.sa_session.query(HistoryDatasetAssociation).get(decoded_id)

            if not hda:
                log.warning(f"Dataset not found: {encoded_id}")
                return False

            # 检查是否删除
            if hda.deleted:
                log.warning(f"Dataset is deleted: {encoded_id}")
                return False

            # 检查用户权限
            if hda.history.user_id != self.trans.user.id:
                log.warning(f"Access denied: Dataset {encoded_id} does not belong to current user")
                return False

            log.info(f"Dataset {encoded_id} exists and is accessible")
            return True

        except Exception as e:
            log.error(f"Failed to check dataset existence: {e}", exc_info=True)
            return False


def validate_workflow_parameters(trans, tool_name: str, params: Dict[str, Any]) -> ValidationResult:
    """
    便捷函数：验证工作流参数

    Usage:
        from galaxy.ai.workflow_ops.parameter_validator import validate_workflow_parameters

        result = validate_workflow_parameters(trans, 'nfcore/clipseq', params)
        if not result.valid:
            raise HTTPException(status_code=400, detail=result.to_dict())

    Args:
        trans: Galaxy transaction context
        tool_name: 工具名称
        params: 参数字典

    Returns:
        ValidationResult: 验证结果
    """
    validator = WorkflowParameterValidator(trans, tool_name)
    return validator.validate(params)
