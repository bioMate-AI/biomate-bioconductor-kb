"""
Workflow Parameter Analyzer

分析 Workflow 参数并生成修复建议
"""

import logging
import re
import json
import os
from typing import Dict, List, Any, Optional, Tuple
from datetime import datetime

log = logging.getLogger(__name__)


def detect_pipeline_type(workflow) -> str:
    """
    从 Workflow 中检测 Pipeline 类型

    Returns:
        Pipeline 名称，例如 "nf-core/rnaseq"
    """
    workflow_name = workflow.name.lower() if workflow.name else ""

    # 检查常见的 nf-core pipeline 名称
    nf_core_patterns = [
        r'nf-core[/\-_]?rnaseq',
        r'nf-core[/\-_]?chipseq',
        r'nf-core[/\-_]?clipseq',
        r'nf-core[/\-_]?atacseq',
        r'nf-core[/\-_]?smrnaseq',
        r'nf-core[/\-_]?methylseq',
    ]

    for pattern in nf_core_patterns:
        match = re.search(pattern, workflow_name)
        if match:
            # 标准化格式为 nf-core/pipeline
            pipeline_name = match.group(0).replace('_', '-')
            if '/' not in pipeline_name:
                pipeline_name = pipeline_name.replace('nf-core-', 'nf-core/')
            return pipeline_name

    # 如果没有匹配，返回原始名称
    return workflow_name or "unknown"


def validate_parameter(value: Any, rules: Dict[str, Any]) -> Optional[str]:
    """
    验证参数值是否符合规则

    Args:
        value: 参数值
        rules: 验证规则字典

    Returns:
        错误信息，如果验证通过返回 None
    """
    if not rules:
        return None

    # 检查 pattern (正则表达式)
    if 'pattern' in rules:
        pattern = rules['pattern']
        if isinstance(value, str) and not re.match(pattern, value):
            return f"Value '{value}' does not match pattern '{pattern}'"

    # 检查 allowed_values (允许的值列表)
    if 'allowed_values' in rules:
        allowed = rules['allowed_values']
        if value not in allowed:
            return f"Value '{value}' not in allowed values: {allowed}"

    # 检查 min_value / max_value (数值范围)
    if 'min_value' in rules or 'max_value' in rules:
        try:
            num_value = float(value) if isinstance(value, str) else value
            if 'min_value' in rules and num_value < rules['min_value']:
                return f"Value {value} is less than minimum {rules['min_value']}"
            if 'max_value' in rules and num_value > rules['max_value']:
                return f"Value {value} exceeds maximum {rules['max_value']}"
        except (ValueError, TypeError):
            return f"Value '{value}' is not a valid number"

    return None


async def analyze_with_llm(
    pipeline_name: str,
    issues: List[Dict[str, Any]],
    invocation: Any,
    anthropic_api_key: Optional[str] = None
) -> Dict[str, Any]:
    """
    使用 LLM 分析参数问题并生成修复建议

    Args:
        pipeline_name: Pipeline 名称
        issues: 检测到的问题列表
        invocation: WorkflowInvocation 对象
        anthropic_api_key: Anthropic API 密钥

    Returns:
        包含修复建议的字典
    """
    # 获取 AWS 配置
    aws_config = {
        'instance_type': os.environ.get('AWS_INSTANCE_TYPE', 'm5.xlarge'),
        'max_memory': os.environ.get('AWS_MAX_MEMORY', '16GB'),
        'max_cpus': os.environ.get('AWS_MAX_CPUS', '4'),
        'batch_queue': os.environ.get('AWS_BATCH_QUEUE', 'default'),
        's3_bucket': os.environ.get('AWS_S3_BUCKET', ''),
    }

    # 构建 prompt
    prompt = f"""You are an expert in bioinformatics workflow parameter configuration.

Analyze the following parameter issues for a {pipeline_name} workflow and generate fix recommendations.

AWS Environment:
- Instance Type: {aws_config['instance_type']}
- Available Memory: {aws_config['max_memory']}
- Available CPUs: {aws_config['max_cpus']}
- AWS Batch Queue: {aws_config['batch_queue']}
- S3 Bucket: {aws_config['s3_bucket']}

Detected Issues:
{json.dumps(issues, indent=2)}

For each issue, provide:
1. parameter: Parameter name
2. fix_type: One of 'set_value', 'add_missing', 'fix_type', 'aws_resource'
3. current_value: Current value (if any)
4. recommended_value: Recommended value
5. reason: Clear explanation why this fix is needed
6. risk_level: 'low', 'medium', or 'high'
7. auto_apply: true if risk is low and fix is safe to apply automatically

Important guidelines:
- For required parameters, always provide a sensible default
- Ensure resource parameters (memory, CPU) are compatible with AWS instance type
- For genome/reference parameters, use GRCh38 as default for human data
- Consider the pipeline-specific requirements

Return a JSON object with a "recommendations" array.
"""

    try:
        # 尝试导入 anthropic
        import anthropic

        # 使用 API key
        api_key = anthropic_api_key or os.environ.get('ANTHROPIC_API_KEY')
        if not api_key:
            log.warning("No Anthropic API key found, using rule-based fixes")
            return generate_rule_based_fixes(issues, aws_config)

        client = anthropic.Anthropic(api_key=api_key)

        message = client.messages.create(
            model="claude-3-5-sonnet-20241022",
            max_tokens=2048,
            messages=[
                {"role": "user", "content": prompt}
            ]
        )

        # 解析响应
        response_text = message.content[0].text

        # 提取 JSON (可能在 markdown 代码块中)
        json_match = re.search(r'```json\s*(.*?)\s*```', response_text, re.DOTALL)
        if json_match:
            response_text = json_match.group(1)

        result = json.loads(response_text)

        log.info(f"LLM generated {len(result.get('recommendations', []))} parameter fixes")

        return result

    except ImportError:
        log.warning("anthropic package not available, using rule-based fixes")
        return generate_rule_based_fixes(issues, aws_config)
    except Exception as e:
        log.error(f"LLM analysis failed: {e}, falling back to rule-based fixes")
        return generate_rule_based_fixes(issues, aws_config)


def generate_rule_based_fixes(
    issues: List[Dict[str, Any]],
    aws_config: Dict[str, str]
) -> Dict[str, Any]:
    """
    基于规则生成参数修复建议（不依赖 LLM）

    Args:
        issues: 问题列表
        aws_config: AWS 配置

    Returns:
        修复建议
    """
    recommendations = []

    # 常见参数的默认值
    default_values = {
        'genome': 'GRCh38',
        'fasta': 's3://ngi-igenomes/igenomes/Homo_sapiens/NCBI/GRCh38/Sequence/WholeGenomeFasta/genome.fa',
        'gtf': 's3://ngi-igenomes/igenomes/Homo_sapiens/NCBI/GRCh38/Annotation/Genes/genes.gtf',
        'aligner': 'star',
        'max_memory': aws_config.get('max_memory', '16.GB'),
        'max_cpus': aws_config.get('max_cpus', '4'),
        'mirtrace_species': 'hsa',  # 人类
        'ncrna_fasta': 's3://ngi-igenomes/igenomes/Homo_sapiens/NCBI/GRCh38/Annotation/SmallRNA/hairpin.fa',
    }

    for issue in issues:
        param_name = issue['parameter']
        issue_type = issue['type']
        template = issue.get('template')

        recommendation = {
            'parameter': param_name,
            'fix_type': 'add_missing' if issue_type == 'missing_required' else 'set_value',
            'current_value': issue.get('current_value'),
            'recommended_value': None,
            'reason': '',
            'risk_level': 'medium',
            'auto_apply': False
        }

        # 根据参数名称选择默认值
        if param_name in default_values:
            recommendation['recommended_value'] = default_values[param_name]
            recommendation['reason'] = f"Parameter '{param_name}' is required for {template.pipeline_name if template else 'this pipeline'}. Setting to commonly used default value."
            recommendation['risk_level'] = 'low'
            recommendation['auto_apply'] = True
        elif template and template.default_value:
            recommendation['recommended_value'] = template.default_value
            recommendation['reason'] = f"Using default value from parameter template"
            recommendation['risk_level'] = 'low'
            recommendation['auto_apply'] = True
        elif issue_type == 'validation_failed':
            # 尝试从 allowed_values 中选择第一个
            if template and template.validation_rules:
                allowed = template.validation_rules.get('allowed_values', [])
                if allowed:
                    recommendation['recommended_value'] = allowed[0]
                    recommendation['reason'] = f"Current value '{issue['current_value']}' is invalid. Using first allowed value: {allowed[0]}"
                    recommendation['risk_level'] = 'medium'
        else:
            # 无法自动生成推荐值
            recommendation['recommended_value'] = f"<MANUAL_REVIEW_REQUIRED>"
            recommendation['reason'] = f"Unable to automatically determine value for '{param_name}'. Manual review required."
            recommendation['risk_level'] = 'high'

        if recommendation['recommended_value']:
            recommendations.append(recommendation)

    return {'recommendations': recommendations}


def get_critical_params_for_pipeline(pipeline_name: str) -> Dict[str, List[str]]:
    """
    获取特定 Pipeline 的关键参数列表

    Returns:
        关键参数字典
    """
    critical_params = {
        'nf-core/rnaseq': ['genome', 'aligner'],
        'nf-core/chipseq': ['genome', 'aligner'],
        'nf-core/clipseq': ['genome'],
        'nf-core/atacseq': ['genome', 'aligner'],
        'nf-core/smrnaseq': ['genome', 'mirtrace_species'],
        'nf-core/methylseq': ['genome', 'aligner'],
    }

    return {
        'required': critical_params.get(pipeline_name, []),
        'recommended': ['max_memory', 'max_cpus']
    }
