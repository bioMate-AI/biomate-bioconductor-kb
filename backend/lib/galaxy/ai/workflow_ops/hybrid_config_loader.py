"""
Hybrid Config Loader - Schema + Manual Configuration

混合配置加载器：
1. 优先从 nextflow_schema.json 自动读取（零配置）
2. 合并手动配置（Galaxy 特定业务规则）
3. 添加 Galaxy 通用规则（dataset_id、S3 支持）

Usage:
    loader = HybridConfigLoader()
    config = loader.load_config('nfcore/rnaseq')
    # 自动从 schema 读取 + Galaxy 业务规则
"""

import logging
from typing import Any, Dict, List, Optional

from .nextflow_schema_loader import NextflowSchemaLoader
from .parameter_validator import ValidationConfigLoader

log = logging.getLogger(__name__)


class HybridConfigLoader:
    """混合配置加载器：自动 schema + 手动配置"""

    def __init__(self):
        self.schema_loader = NextflowSchemaLoader()
        self.manual_loader = ValidationConfigLoader()

    def load_config(self, tool_name: str) -> Dict[str, Any]:
        """
        混合加载配置

        优先级:
        1. 自动从 nextflow_schema.json 读取（如果存在）
        2. 与手动配置合并（manual 可以覆盖和扩展）
        3. 添加 Galaxy 特定规则（通用）

        Args:
            tool_name: 工具名称（如 'nfcore/rnaseq'）

        Returns:
            合并后的配置字典
        """
        config = {}
        source_info = []

        # 1. 尝试从 nextflow_schema.json 自动加载
        schema = self.schema_loader.load_schema(tool_name)
        if schema:
            auto_rules = self.schema_loader.extract_validation_rules(schema)
            config.update(auto_rules)
            source_info.append('nextflow_schema.json')
            log.info(f"✅ 从 nextflow_schema.json 加载: {tool_name}")
            log.info(f"   - {len(config.get('required_params', []))} 必需参数")
            log.info(f"   - {len(config.get('param_constraints', {}))} 参数约束")
        else:
            log.info(f"⚠️  未找到 nextflow_schema.json: {tool_name}")

        # 2. 加载手动配置（可以覆盖和扩展）
        manual_config = self.manual_loader.get_config_for_tool(tool_name)
        if manual_config and manual_config != self.manual_loader.load_config().get('default', {}):
            config = self._merge_configs(config, manual_config)
            source_info.append('validation_config.yaml')
            log.info(f"✅ 应用手动配置: {tool_name}")

        # 3. 添加 Galaxy 特定规则（所有 workflow 通用）
        config = self._add_galaxy_rules(config)
        source_info.append('Galaxy 通用规则')

        # 4. 如果完全没有配置，使用 fallback
        if not config.get('required_params') and not config.get('param_constraints'):
            log.warning(f"⚠️  使用默认 fallback 配置: {tool_name}")
            config = self._get_fallback_config()
            source_info.append('fallback')

        log.info(f"📊 最终配置来源: {' + '.join(source_info)}")

        return config

    def _merge_configs(self, auto: Dict[str, Any], manual: Dict[str, Any]) -> Dict[str, Any]:
        """
        合并配置，manual 可以覆盖和扩展 auto

        支持:
        - overrides: 完全覆盖 auto 的配置
        - extends: 扩展（追加到列表）
        - custom_validations: 添加自定义验证

        Args:
            auto: 自动配置（从 schema）
            manual: 手动配置（从 YAML）

        Returns:
            合并后的配置
        """
        result = auto.copy()

        # 处理覆盖（overrides）
        if 'overrides' in manual:
            log.info(f"   应用覆盖规则: {len(manual['overrides'])} 个")
            for key, value in manual['overrides'].items():
                if key in result.get('param_constraints', {}):
                    # 覆盖参数约束
                    result['param_constraints'][key].update(value)
                elif key == 'required_params':
                    # 覆盖必需参数列表
                    result['required_params'] = value
                else:
                    # 其他覆盖
                    result[key] = value

        # 处理扩展（extends）- 追加到列表
        if 'extends' in manual:
            # 处理 extends: default（已由 ValidationConfigLoader 处理）
            pass

        # 处理额外的必需参数
        if 'required_params' in manual and 'overrides' not in manual:
            # 如果不是覆盖模式，则合并
            existing_required = set(result.get('required_params', []))
            manual_required = set(manual['required_params'])
            result['required_params'] = list(existing_required | manual_required)

        # 处理额外的参数约束
        if 'param_constraints' in manual:
            if 'param_constraints' not in result:
                result['param_constraints'] = {}
            # 合并或覆盖
            for param, constraint in manual['param_constraints'].items():
                if param in result['param_constraints']:
                    # 合并约束
                    result['param_constraints'][param].update(constraint)
                else:
                    # 新增约束
                    result['param_constraints'][param] = constraint

        # 添加自定义验证规则
        if 'custom_validations' in manual:
            result['custom_validations'] = manual['custom_validations']
            log.info(f"   添加自定义验证: {len(manual['custom_validations'])} 个")

        # 添加业务规则
        if 'business_rules' in manual:
            result['business_rules'] = manual['business_rules']

        return result

    def _add_galaxy_rules(self, config: Dict[str, Any]) -> Dict[str, Any]:
        """
        添加 Galaxy 特定规则（所有 workflow 通用）

        - 支持 dataset_id: 格式
        - 支持 s3:// 路径
        - 支持本地绝对路径

        Args:
            config: 配置字典

        Returns:
            添加 Galaxy 规则后的配置
        """
        # 为所有文件类型参数添加 Galaxy 支持
        file_params = config.get('file_params', [])

        for param_name in file_params:
            if param_name in config.get('param_constraints', {}):
                constraint = config['param_constraints'][param_name]

                # 添加额外支持的格式
                if 'additional_formats' not in constraint:
                    constraint['additional_formats'] = []

                # Galaxy dataset_id 格式
                if 'dataset_id:*' not in constraint['additional_formats']:
                    constraint['additional_formats'].append('dataset_id:*')

                # S3 路径
                if 's3://*' not in constraint['additional_formats']:
                    constraint['additional_formats'].append('s3://*')

                # 本地绝对路径
                if '/*' not in constraint['additional_formats']:
                    constraint['additional_formats'].append('/*')

                constraint['galaxy_enhanced'] = True

        # 添加 Galaxy 特定的验证类型
        if 'custom_validations' not in config:
            config['custom_validations'] = []

        # 确保有 Galaxy dataset 检查
        galaxy_validations = [
            {
                'type': 'galaxy_dataset_check',
                'description': '验证 Galaxy dataset 是否存在',
                'params': file_params
            },
            {
                'type': 's3_path_format',
                'description': '验证 S3 路径格式',
                'params': file_params
            }
        ]

        for validation in galaxy_validations:
            # 避免重复添加
            if validation not in config['custom_validations']:
                config['custom_validations'].append(validation)

        return config

    def _get_fallback_config(self) -> Dict[str, Any]:
        """
        获取 fallback 配置（当完全没有配置时使用）

        Returns:
            最小默认配置
        """
        return {
            'required_params': ['input'],
            'file_params': ['input', 'fasta', 'gtf', 'genome_fasta'],
            'param_constraints': {
                'input': {
                    'type': 'file',
                    'formats': ['.csv', '.tsv'],
                    'description': 'Input samplesheet'
                }
            },
            'reference_genome_check': {
                'enabled': True,
                'rules': [
                    {
                        'condition': 'no_genome_and_no_fasta',
                        'error': '必须指定参考基因组（genome）或 FASTA 文件',
                        'field': 'genome'
                    }
                ]
            }
        }

    def get_config_summary(self, tool_name: str) -> Dict[str, Any]:
        """
        获取配置摘要（用于调试和日志）

        Args:
            tool_name: 工具名称

        Returns:
            配置摘要
        """
        config = self.load_config(tool_name)

        summary = {
            'tool_name': tool_name,
            'required_params_count': len(config.get('required_params', [])),
            'param_constraints_count': len(config.get('param_constraints', {})),
            'file_params_count': len(config.get('file_params', [])),
            'custom_validations_count': len(config.get('custom_validations', [])),
            'has_schema': bool(self.schema_loader.load_schema(tool_name)),
            'has_manual_config': bool(
                self.manual_loader.get_config_for_tool(tool_name) !=
                self.manual_loader.load_config().get('default', {})
            )
        }

        return summary


# 便捷函数
def load_hybrid_config(tool_name: str) -> Dict[str, Any]:
    """
    便捷函数：加载混合配置

    Args:
        tool_name: 工具名称

    Returns:
        混合配置字典
    """
    loader = HybridConfigLoader()
    return loader.load_config(tool_name)


def get_config_summary(tool_name: str) -> Dict[str, Any]:
    """
    便捷函数：获取配置摘要

    Args:
        tool_name: 工具名称

    Returns:
        配置摘要
    """
    loader = HybridConfigLoader()
    return loader.get_config_summary(tool_name)
