"""
Nextflow Schema Loader - Automatic Parameter Definition from nextflow_schema.json

自动从 nf-core pipeline 的 nextflow_schema.json 读取参数定义
- 零配置，自动发现
- 支持本地 pipeline 文件
- 支持从 nf-core API 动态下载
- 自动解析为验证规则

Usage:
    loader = NextflowSchemaLoader()
    schema = loader.load_schema('nfcore/rnaseq')
    rules = loader.extract_validation_rules(schema)
"""

import json
import logging
import re
import requests
from pathlib import Path
from typing import Any, Dict, List, Optional

log = logging.getLogger(__name__)


class NextflowSchemaLoader:
    """从 Nextflow Pipeline 自动读取参数定义"""

    # 可能的 pipeline 存储路径
    PIPELINE_BASE_PATHS = [
        Path("/Users/renyuankai/work/biometa/galaxy/database/objects/nextflow_pipelines"),
    ]

    # nf-core GitHub raw URL 模板
    NFCORE_SCHEMA_URL_TEMPLATE = "https://raw.githubusercontent.com/nf-core/{pipeline}/master/nextflow_schema.json"

    def __init__(self):
        self._cache: Dict[str, Dict[str, Any]] = {}

    def load_schema(self, tool_name: str) -> Optional[Dict[str, Any]]:
        """
        加载 nextflow_schema.json

        查找顺序:
        1. 缓存
        2. 本地 pipeline 文件
        3. nf-core API（如果是 nfcore/* 工具）

        Args:
            tool_name: 工具名称（如 'nfcore/rnaseq'）

        Returns:
            schema 字典，如果找不到返回 None
        """
        # 1. 检查缓存
        if tool_name in self._cache:
            log.info(f"✅ 从缓存加载 schema: {tool_name}")
            return self._cache[tool_name]

        # 2. 尝试本地文件
        schema = self._load_from_local(tool_name)
        if schema:
            log.info(f"✅ 从本地文件加载 schema: {tool_name}")
            self._cache[tool_name] = schema
            return schema

        # 3. 尝试从 nf-core API 下载
        if tool_name.startswith('nfcore/'):
            schema = self._load_from_nfcore_api(tool_name)
            if schema:
                log.info(f"✅ 从 nf-core API 加载 schema: {tool_name}")
                self._cache[tool_name] = schema
                return schema

        log.warning(f"❌ 未找到 schema: {tool_name}")
        return None

    def _load_from_local(self, tool_name: str) -> Optional[Dict[str, Any]]:
        """
        从本地文件系统加载 nextflow_schema.json

        查找策略:
        1. database/objects/nextflow_pipelines/{pipeline_name}*/nextflow_schema.json
        2. 支持带时间戳的目录名（如 rnaseq_1764774740）

        Args:
            tool_name: 工具名称（如 'nfcore/rnaseq'）

        Returns:
            schema 字典或 None
        """
        pipeline_name = self._extract_pipeline_name(tool_name)

        for base_path in self.PIPELINE_BASE_PATHS:
            if not base_path.exists():
                continue

            # 查找匹配的 pipeline 目录（支持带时间戳）
            pattern = f"{pipeline_name}*"
            matching_dirs = list(base_path.glob(pattern))

            for pipeline_dir in matching_dirs:
                schema_path = pipeline_dir / "nextflow_schema.json"
                if schema_path.exists():
                    try:
                        with open(schema_path, 'r', encoding='utf-8') as f:
                            schema = json.load(f)
                        log.info(f"📁 本地 schema 文件: {schema_path}")
                        return schema
                    except Exception as e:
                        log.error(f"读取 schema 失败: {schema_path}, {e}")
                        continue

        return None

    def _load_from_nfcore_api(self, tool_name: str) -> Optional[Dict[str, Any]]:
        """
        从 nf-core GitHub API 动态下载 nextflow_schema.json

        Args:
            tool_name: 工具名称（必须是 'nfcore/xxx'）

        Returns:
            schema 字典或 None
        """
        pipeline_name = self._extract_pipeline_name(tool_name)
        url = self.NFCORE_SCHEMA_URL_TEMPLATE.format(pipeline=pipeline_name)

        try:
            log.info(f"🌐 从 nf-core API 下载 schema: {url}")
            response = requests.get(url, timeout=10)
            response.raise_for_status()

            schema = response.json()
            return schema

        except requests.RequestException as e:
            log.warning(f"从 nf-core API 下载 schema 失败: {e}")
            return None
        except json.JSONDecodeError as e:
            log.error(f"解析 nf-core schema JSON 失败: {e}")
            return None

    def extract_validation_rules(self, schema: Dict[str, Any]) -> Dict[str, Any]:
        """
        从 nextflow_schema.json 提取验证规则

        解析 JSON Schema (Draft 2020-12) 格式，提取:
        - required_params: 必需参数列表
        - param_constraints: 参数约束（类型、格式、pattern、错误消息）

        Args:
            schema: nextflow_schema.json 内容

        Returns:
            {
                'required_params': ['input', 'outdir'],
                'param_constraints': {
                    'input': {
                        'type': 'file',
                        'formats': ['.csv', '.tsv'],
                        'pattern': '^\\S+\\.csv$',
                        'error_message': '...',
                        'description': '...'
                    }
                }
            }
        """
        rules = {
            'required_params': [],
            'param_constraints': {},
            'file_params': []
        }

        # 遍历 $defs 中的所有 section
        defs = schema.get('$defs', schema.get('definitions', {}))

        for section_name, section in defs.items():
            # 提取必需参数
            required = section.get('required', [])
            rules['required_params'].extend(required)

            # 提取参数约束
            properties = section.get('properties', {})
            for param_name, param_def in properties.items():
                constraint = self._extract_param_constraint(param_name, param_def)
                rules['param_constraints'][param_name] = constraint

                # 收集文件类型参数
                if constraint['type'] in ['file', 'file-path']:
                    rules['file_params'].append(param_name)

        # 去重
        rules['required_params'] = list(set(rules['required_params']))
        rules['file_params'] = list(set(rules['file_params']))

        log.info(f"📊 提取验证规则: {len(rules['required_params'])} required, {len(rules['param_constraints'])} constraints")

        return rules

    def _extract_param_constraint(self, param_name: str, param_def: Dict[str, Any]) -> Dict[str, Any]:
        """
        从参数定义提取约束

        Args:
            param_name: 参数名
            param_def: 参数定义（来自 nextflow_schema.json）

        Returns:
            约束字典
        """
        constraint = {
            'type': self._map_json_type(param_def.get('type', 'string')),
            'formats': [],
            'pattern': param_def.get('pattern'),
            'error_message': param_def.get('errorMessage'),
            'description': param_def.get('description'),
            'help_text': param_def.get('help_text'),
            'exists': param_def.get('exists', False)
        }

        # 提取格式（从 pattern 或 format）
        json_format = param_def.get('format')
        if json_format in ['file-path', 'directory-path']:
            constraint['type'] = 'file' if json_format == 'file-path' else 'directory'

        # 从 pattern 提取文件扩展名
        pattern = param_def.get('pattern', '')
        formats = self._extract_formats_from_pattern(pattern)
        if formats:
            constraint['formats'] = formats

        # mimetype 提示
        if 'mimetype' in param_def:
            constraint['mimetype'] = param_def['mimetype']

        return constraint

    def _extract_formats_from_pattern(self, pattern: str) -> List[str]:
        """
        从正则表达式 pattern 提取文件格式

        例如:
        - '^\\S+\\.csv$' -> ['.csv']
        - '^\\S+\\.fn?a(sta)?(\\.gz)?$' -> ['.fa', '.fna', '.fasta', '.fa.gz', '.fasta.gz']
        - '^\\S+\\.gtf(\\.gz)?$' -> ['.gtf', '.gtf.gz']

        Args:
            pattern: 正则表达式

        Returns:
            文件格式列表
        """
        if not pattern:
            return []

        formats = []

        # 常见模式
        patterns_map = {
            r'\.csv': ['.csv'],
            r'\.tsv': ['.tsv'],
            r'\.fn?a(sta)?': ['.fa', '.fna', '.fasta'],
            r'\.gtf': ['.gtf'],
            r'\.gff': ['.gff'],
            r'\.bed': ['.bed'],
            r'\.bam': ['.bam'],
            r'\.fastq': ['.fastq', '.fq'],
            r'\.vcf': ['.vcf'],
        }

        # 匹配模式
        for pattern_regex, format_list in patterns_map.items():
            if re.search(pattern_regex, pattern):
                formats.extend(format_list)

        # 检查是否支持 .gz
        if r'\.gz' in pattern or r'\\.gz' in pattern:
            # 为每个格式添加 .gz 版本
            gz_formats = [f + '.gz' for f in formats if not f.endswith('.gz')]
            formats.extend(gz_formats)

        return list(set(formats))

    def _map_json_type(self, json_type) -> str:
        """
        映射 JSON Schema 类型到我们的验证类型

        Args:
            json_type: JSON Schema 类型（可能是字符串或列表，如 ["string", "null"]）

        Returns:
            验证类型
        """
        type_map = {
            'string': 'string',
            'integer': 'integer',
            'number': 'number',
            'boolean': 'boolean',
            'array': 'array',
            'object': 'object'
        }

        # 处理列表类型（如 ["string", "null"]）
        if isinstance(json_type, list):
            # 过滤掉 null，取第一个非 null 类型
            non_null_types = [t for t in json_type if t != 'null']
            if non_null_types:
                json_type = non_null_types[0]
            else:
                json_type = 'string'

        return type_map.get(json_type, 'string')

    def _extract_pipeline_name(self, tool_name: str) -> str:
        """
        从工具名提取 pipeline 名称

        例如:
        - 'nfcore/rnaseq' -> 'rnaseq'
        - 'nf-core/chipseq' -> 'chipseq'
        - 'rnaseq' -> 'rnaseq'

        Args:
            tool_name: 工具名称

        Returns:
            pipeline 名称
        """
        # 移除前缀
        name = tool_name.replace('nfcore/', '').replace('nf-core/', '')
        return name


# 便捷函数
def load_nextflow_schema(tool_name: str) -> Optional[Dict[str, Any]]:
    """
    便捷函数：加载 nextflow_schema.json

    Args:
        tool_name: 工具名称

    Returns:
        schema 字典或 None
    """
    loader = NextflowSchemaLoader()
    return loader.load_schema(tool_name)


def extract_validation_rules_from_schema(tool_name: str) -> Optional[Dict[str, Any]]:
    """
    便捷函数：从 schema 提取验证规则

    Args:
        tool_name: 工具名称

    Returns:
        验证规则字典或 None
    """
    loader = NextflowSchemaLoader()
    schema = loader.load_schema(tool_name)

    if schema:
        return loader.extract_validation_rules(schema)

    return None
