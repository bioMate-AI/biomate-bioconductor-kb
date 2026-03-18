"""
LLM-First Auto Fixer

使用大模型优先分析和修复所有类型的 workflow 错误
只在必要时降级到规则引擎
"""

import logging
import json
import re
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Any, Optional

from ..base import (
    BaseAutoFixer,
    FixContext,
    FixStatus,
    RiskLevel,
    AutoFixResult,
)
from ...types import FixAction, ActionType

log = logging.getLogger(__name__)


class LLMFirstFixer(BaseAutoFixer):
    """
    LLM 优先的通用修复器

    使用大模型分析错误并生成修复方案
    适用于所有类型的 workflow 错误
    """

    name = "LLMFirstFixer"
    description = "使用大模型智能分析和修复所有类型的错误"

    def __init__(self, llm_client=None, fallback_to_rules: bool = True):
        """
        初始化 LLM First Fixer

        Args:
            llm_client: LLM 客户端（如果为 None，会自动创建）
            fallback_to_rules: 如果 LLM 失败，是否降级到规则引擎
        """
        super().__init__()
        self.llm_client = llm_client
        self.fallback_to_rules = fallback_to_rules

        # 如果没有提供 LLM client，尝试创建
        if not self.llm_client:
            try:
                from ...llm_client import UnifiedLLMClient
                self.llm_client = UnifiedLLMClient()
                log.info("✅ LLMFirstFixer initialized with LLM client")
            except Exception as e:
                log.warning(f"⚠️  Failed to initialize LLM client: {e}")
                if not self.fallback_to_rules:
                    raise

    def detect_issues(self, context: FixContext) -> List[Dict[str, Any]]:
        """
        使用 LLM 检测和分析所有问题

        Args:
            context: Fix context

        Returns:
            List of detected issues with LLM analysis
        """
        from galaxy.model import WorkflowInvocation

        sa_session = context.metadata.get('sa_session')
        if not sa_session:
            log.error("No sa_session in context metadata")
            return []

        invocation = sa_session.query(WorkflowInvocation).get(context.invocation_id)
        if not invocation:
            log.error(f"Invocation {context.invocation_id} not found")
            return []

        # 收集错误信息
        error_data = self._collect_error_data(invocation, context)

        if not error_data['has_errors']:
            log.info("No errors detected in workflow")
            return []

        # 使用 LLM 分析
        if self.llm_client:
            try:
                issues = self._llm_analyze_errors(error_data, context)
                log.info(f"🤖 LLM detected {len(issues)} issues")
                return issues
            except Exception as e:
                log.error(f"❌ LLM analysis failed: {e}")
                if self.fallback_to_rules:
                    log.info("🔄 Falling back to rule-based detection")
                    return self._rule_based_detect(error_data)
                else:
                    raise
        else:
            # 没有 LLM，使用规则
            return self._rule_based_detect(error_data)

    def _collect_error_data(self, invocation, context: FixContext) -> Dict[str, Any]:
        """收集所有错误相关的数据"""
        from galaxy.config import Configuration

        config = context.metadata.get('app_config')
        if not config:
            return {'has_errors': False}

        jobs_dir = Path(config.jobs_directory)
        workflow_dir = jobs_dir / f"nextflow_workflows/workflow_{context.invocation_id}"

        error_data = {
            'has_errors': False,
            'workflow_state': invocation.state,
            'workflow_name': invocation.workflow.name if invocation.workflow else 'unknown',
            'error_logs': '',
            'trace_data': [],
            'failed_tasks': [],
            'parameters': {},
        }

        # 读取 nextflow.out
        nextflow_out = workflow_dir / "nextflow.out"
        if nextflow_out.exists():
            try:
                with open(nextflow_out, 'r') as f:
                    error_data['error_logs'] = f.read()[-10000:]  # 最后 10KB
                    if 'ERROR' in error_data['error_logs'] or 'FAILED' in error_data['error_logs']:
                        error_data['has_errors'] = True
            except Exception as e:
                log.warning(f"Failed to read nextflow.out: {e}")

        # 读取 trace 文件
        trace_file = workflow_dir / "workflow-trace.txt"
        if trace_file.exists():
            try:
                import csv
                with open(trace_file, 'r') as f:
                    reader = csv.DictReader(f, delimiter='\t')
                    # 🔥 改进: 收集所有任务统计信息
                    all_tasks = list(reader)
                    total_tasks = len(all_tasks)
                    completed_tasks = sum(1 for t in all_tasks if t.get('status') == 'COMPLETED')
                    failed_tasks = [t for t in all_tasks if t.get('status') == 'FAILED']

                    error_data['total_tasks'] = total_tasks
                    error_data['completed_tasks'] = completed_tasks

                    for task in failed_tasks:
                        error_data['failed_tasks'].append({
                            'name': task.get('name', ''),
                            'exit': task.get('exit', ''),
                            'status': task.get('status', ''),
                        })
                        error_data['has_errors'] = True
            except Exception as e:
                log.warning(f"Failed to read trace file: {e}")

        # 获取参数
        if invocation.input_parameters:
            for param in invocation.input_parameters:
                if hasattr(param, 'name') and hasattr(param, 'value'):
                    error_data['parameters'][param.name] = param.value

        return error_data

    def _llm_analyze_errors(self, error_data: Dict, context: FixContext) -> List[Dict[str, Any]]:
        """
        使用 LLM 深度分析错误并生成修复方案

        这是系统的核心智能：LLM 可以理解复杂的错误场景，
        识别未知问题，并生成个性化的修复方案
        """
        # 构建 LLM prompt
        prompt = self._build_analysis_prompt(error_data, context)

        log.info("🤖 Calling LLM for comprehensive error analysis...")

        try:
            response = self.llm_client.call(
                messages=[{"role": "user", "content": prompt}],
                model="claude-sonnet-4-20250514",  # 使用最新的Claude Sonnet 4模型
                temperature=0.2,  # 低温度确保稳定输出
                max_tokens=4000
            )

            # 解析 LLM 响应
            # 🔥 兼容新的content blocks格式
            content = response.get('content', [])
            if isinstance(content, list):
                # 提取文本内容
                text_content = ''
                for block in content:
                    if isinstance(block, dict) and block.get('type') == 'text':
                        text_content += block.get('text', '')
                content_str = text_content
            else:
                # 兼容旧版本（字符串）
                content_str = content

            result = self._parse_llm_response(content_str)

            log.info(f"✅ LLM analysis complete. Found {len(result)} fixable issues")

            return result

        except Exception as e:
            log.error(f"LLM analysis failed: {e}")
            raise

    def _build_analysis_prompt(self, error_data: Dict, context: FixContext) -> str:
        """构建 LLM 分析 prompt - 优化版本，提供更多上下文"""

        # 🔥 改进1: 增加错误日志长度到200行（从50行）
        error_summary = self._extract_error_summary(error_data['error_logs'], max_lines=200)

        # 🔥 改进2: 显示更多失败任务（10个而不是5个）
        failed_tasks_str = "\n".join([
            f"- {t['name']} (exit: {t['exit']})"
            for t in error_data['failed_tasks'][:10]
        ])

        # 🔥 改进3: 显示关键参数的实际值
        critical_params = ['genome', 'skip_filter_gtf', 'star_index_max_memory',
                          'max_memory', 'max_cpus', 'source', 'ncrna_fasta']
        params_detail = []
        for param_name in critical_params:
            if param_name in error_data['parameters']:
                value = error_data['parameters'][param_name]
                params_detail.append(f"  - {param_name}: {value}")
        params_str = "\n".join(params_detail) if params_detail else "  (无关键参数信息)"

        # 🔥 改进4: 添加任务统计信息
        task_stats = f"""
- 总任务数: {error_data.get('total_tasks', 'unknown')}
- 成功任务: {error_data.get('completed_tasks', 0)}
- 失败任务: {len(error_data['failed_tasks'])}
- 失败率: {len(error_data['failed_tasks']) / max(error_data.get('total_tasks', 1), 1) * 100:.1f}%"""

        prompt = f"""你是一个 Nextflow Workflow 专家诊断系统。请深度分析以下失败的 workflow 并生成精准的修复方案。

## Workflow 信息
- **名称**: {error_data['workflow_name']}
- **状态**: {error_data['workflow_state']}
{task_stats}

## 失败的任务详情（显示前10个）
{failed_tasks_str or '(无具体任务信息)'}

## 当前关键参数配置
{params_str}
总参数数: {len(error_data['parameters'])}

## 完整错误日志（最多200行关键部分）
```
{error_summary}
```

## 你的任务

**请按照以下步骤进行分析（Chain-of-Thought推理）**：

1. **识别错误模式**: 从错误日志中提取关键错误信息（如exit code、ERROR关键词、异常类型）
2. **定位根本原因**: 判断是参数配置问题、资源限制、数据格式错误还是其他问题
3. **查找相关参数**: 检查当前参数配置，找出可能导致问题的参数或缺失的参数
4. **设计修复方案**: 基于根本原因，设计具体的修复动作
5. **评估风险和信心**: 评估修复方案的风险级别和成功概率

## 错误分类决策树（请严格遵循）

**Step 1: 检查 Exit Code**
- **Exit code 137 或 143**: → 内存不足 (OOM Killer) → issue_type: "memory_oom_killer"
- **Exit code 1**: → 继续检查错误信息
- **Exit code 139**: → 段错误 (Segmentation fault) → 检查内存/数据损坏
- **Exit code 255**: → AWS Batch失败 → 检查权限/资源

**Step 2: 检查错误关键词优先级**

**优先级1: 文件格式问题（fixable: false）**
- 包含 "GTF" + ("KeyError" 或 "exon_number" 或 "transcript" 或 "cannot parse") → "gtf_format_error"
- 包含 "BED" + ("invalid" 或 "malformed" 或 "coordinates") → "bed_format_error"
- 包含 "GFF" + ("invalid" 或 "parse error") → "gff_format_error"
- 包含 "FASTA" + ("invalid" 或 "line endings" 或 "encoding") → "fasta_format_error"
- 包含 "FASTQ" + ("quality score" 或 "phred" 或 "encoding") → "fastq_encoding_error"
- 包含 "BAM" + ("truncated" 或 "EOF marker" 或 "invalid header") → "bam_file_corrupt"
- 包含 "VCF" + ("malformed" 或 "INFO field" 或 "header") → "vcf_format_error"

**优先级2: 资源问题（fixable: true，通过增加资源）**
- 包含 "out of memory" 或 "OOM" 或 "killed" → "memory_oom_killer"
- 包含 "no space left" 或 "disk quota" → "disk_quota_exceeded"
- 包含 "timeout" 或 "time limit" → "cpu_timeout"

**优先级3: 工具特定错误**
- 包含 "STAR" + ("index" 或 "genome" 或 "alignment") → "star_alignment_error"
- 包含 "Bowtie2" + ("index" 或 "alignment") → "bowtie2_alignment_error"
- 包含 "samtools" + ("sort" 或 "memory") → "samtools_sort_error"
- 包含 "Picard" + ("validation" 或 "VALIDATION") → "picard_validation_error"

**优先级4: AWS基础设施问题**
- 包含 "AccessDenied" 或 "permission denied" → "aws_batch_permission_denied"
- 包含 "spot" + "interruption" → "aws_batch_spot_interruption"
- 包含 "S3" + ("download" 或 "upload" 或 "transfer") → "aws_s3_transfer_error"
- 包含 "RUNNABLE" + "stuck" → "aws_batch_resource_unavailable"
- 包含 "docker pull" 或 "manifest unknown" → "container_pull_error"

**优先级5: 数据质量问题（fixable: false，需要用户检查）**
- 包含 "duplicate" + "high" → "duplicate_reads_high"
- 包含 "mapping rate" + "low" → "low_mapping_rate"

**优先级6: 参数/配置问题（fixable: true）**
- 包含 "parameter" + "required" → "missing_parameter"
- 包含 "reference genome" + "not found" → "missing_reference_genome"

## Few-shot Examples（参考案例）

**案例1: GTF格式问题**
```json
{{
  "issue_type": "gtf_format_error",
  "severity": "high",
  "root_cause": "GTF文件缺少transcript-level features，导致iCount工具失败",
  "description": "日志显示 'No transcript-level features found'，这是因为某些GTF文件只有gene和exon级别的注释",
  "fixable": true,
  "fix_actions": [
    {{
      "action": "add_parameter",
      "parameter_name": "skip_filter_gtf",
      "new_value": true,
      "reason": "跳过GTF过滤步骤可以避免对transcript-level的依赖"
    }}
  ],
  "risk_level": "low",
  "estimated_cost": 0.0,
  "confidence": 0.95
}}
```

**案例2: 内存不足问题**
```json
{{
  "issue_type": "resource_exhaustion",
  "severity": "high",
  "root_cause": "STAR genome index生成需要的内存超过了AWS Batch任务限制",
  "description": "STAR_GENOMEGENERATE任务失败，exit code 137表示内存不足",
  "fixable": true,
  "fix_actions": [
    {{
      "action": "update_parameter",
      "parameter_name": "star_index_max_memory",
      "new_value": "32000000000",
      "reason": "增加STAR index内存限制到32GB，避免OOM"
    }}
  ],
  "risk_level": "low",
  "estimated_cost": 0.5,
  "confidence": 0.9
}}
```

**案例3: 缺少必需参数**
```json
{{
  "issue_type": "missing_parameter",
  "severity": "high",
  "root_cause": "Pipeline要求source参数指定数据来源，但未提供",
  "description": "参数验证失败，提示 'source parameter is required'",
  "fixable": true,
  "fix_actions": [
    {{
      "action": "add_parameter",
      "parameter_name": "source",
      "new_value": "fastq",
      "reason": "明确指定数据源类型为fastq格式"
    }}
  ],
  "risk_level": "low",
  "estimated_cost": 0.0,
  "confidence": 0.98
}}
```

**案例4: FASTQ 质量值编码问题**
```json
{{
  "issue_type": "fastq_quality_error",
  "severity": "medium",
  "root_cause": "FASTQ文件使用Phred+64编码，但工具期望Phred+33",
  "description": "错误日志显示 'quality score out of range'，说明质量值编码不匹配",
  "fixable": false,
  "user_action_required": true,
  "recommended_action": "使用 seqtk 或 FastQC 转换质量值编码格式",
  "risk_level": "low",
  "estimated_cost": 0.0,
  "confidence": 0.95
}}
```

**案例5: BAM 文件损坏**
```json
{{
  "issue_type": "bam_file_corrupt",
  "severity": "high",
  "root_cause": "BAM文件在传输过程中损坏，文件头部不完整",
  "description": "samtools 报告 'invalid BAM binary header (truncated file?)'",
  "fixable": false,
  "user_action_required": true,
  "recommended_action": "使用 samtools quickcheck 验证文件，重新上传或生成 BAM 文件",
  "risk_level": "low",
  "estimated_cost": 0.0,
  "confidence": 1.0
}}
```

**案例6: VCF 格式错误**
```json
{{
  "issue_type": "vcf_format_error",
  "severity": "medium",
  "root_cause": "VCF文件缺少必需的头部信息或列数不匹配",
  "description": "VCF解析器报告 'malformed VCF header' 或 'INFO field not declared'",
  "fixable": false,
  "user_action_required": true,
  "recommended_action": "使用 bcftools 或 vcf-validator 修复 VCF 格式",
  "risk_level": "low",
  "estimated_cost": 0.0,
  "confidence": 0.9
}}
```

**案例7: FASTA 编码或换行符问题**
```json
{{
  "issue_type": "fasta_encoding_error",
  "severity": "medium",
  "root_cause": "FASTA文件使用Windows换行符（CRLF）或非UTF-8编码",
  "description": "samtools faidx 失败，报告 'invalid FASTA format - unexpected line endings'",
  "fixable": false,
  "user_action_required": true,
  "recommended_action": "使用 dos2unix 转换换行符，或使用 seqtk 重新格式化",
  "risk_level": "low",
  "estimated_cost": 0.0,
  "confidence": 0.95
}}
```

**案例8: GTF 文件缺少必需属性**
```json
{{
  "issue_type": "gtf_format_error",
  "severity": "high",
  "root_cause": "GTF文件缺少工具所需的必需属性字段（如exon_number）",
  "description": "iCount 工具报告 '[KeyError] exon_number'，说明GTF文件格式不完整，缺少关键的exon编号属性",
  "fixable": false,
  "user_action_required": true,
  "recommended_action": "使用 GENCODE 或 Ensembl 的标准 GTF 文件，或使用 AGAT 工具修复现有文件",
  "risk_level": "low",
  "estimated_cost": 0.0,
  "confidence": 0.98
}}
```

**案例9: BED文件坐标错误**
```json
{{
  "issue_type": "bed_format_error",
  "severity": "medium",
  "root_cause": "BED文件包含无效的染色体坐标（start >= end）",
  "description": "bedtools 报告 'Error: malformed BED entry at line 1234. Start was greater than end.'",
  "fixable": false,
  "user_action_required": true,
  "recommended_action": "使用 bedtools sort 和 awk 脚本修复坐标顺序，或重新从UCSC下载标准BED文件",
  "risk_level": "low",
  "estimated_cost": 0.0,
  "confidence": 0.92
}}
```

**案例10: 内存OOM Killer (exit code 137)**
```json
{{
  "issue_type": "memory_oom_killer",
  "severity": "high",
  "root_cause": "STAR比对任务内存使用超过容器限制，被OOM Killer强制终止",
  "description": "任务以exit code 137退出，日志中出现 'Killed'，这是典型的内存不足信号",
  "fixable": true,
  "fix_actions": [
    {{
      "action": "update_parameter",
      "parameter_name": "star_memory",
      "new_value": "64.GB",
      "reason": "将STAR内存从默认32GB增加到64GB，避免OOM"
    }}
  ],
  "risk_level": "low",
  "estimated_cost": 1.2,
  "confidence": 0.95
}}
```

**案例11: 磁盘空间不足**
```json
{{
  "issue_type": "disk_quota_exceeded",
  "severity": "high",
  "root_cause": "工作目录磁盘空间耗尽，无法写入BAM输出文件",
  "description": "错误日志显示 'No space left on device' 或 'Disk quota exceeded'",
  "fixable": false,
  "user_action_required": true,
  "recommended_action": "清理Nextflow工作目录（nextflow clean -f），或扩展AWS EBS卷容量",
  "risk_level": "medium",
  "estimated_cost": 0.0,
  "confidence": 0.98
}}
```

**案例12: AWS Batch Spot实例中断**
```json
{{
  "issue_type": "aws_batch_spot_interruption",
  "severity": "medium",
  "root_cause": "AWS回收Spot实例容量，导致正在运行的任务被强制终止",
  "description": "任务突然失败，日志显示 'Host EC2 instance terminated' 或 exit code 137（但无内存错误）",
  "fixable": true,
  "fix_actions": [
    {{
      "action": "increase_retry",
      "parameter_name": "max_retries",
      "new_value": "5",
      "reason": "增加重试次数，Nextflow会在新实例上自动重试"
    }}
  ],
  "risk_level": "low",
  "estimated_cost": 0.0,
  "confidence": 0.85
}}
```

**案例13: Docker镜像拉取失败**
```json
{{
  "issue_type": "container_pull_error",
  "severity": "high",
  "root_cause": "Docker镜像名称或标签错误，或网络连接到Docker Hub超时",
  "description": "错误日志显示 'manifest unknown' 或 'pull access denied' 或 'TLS handshake timeout'",
  "fixable": false,
  "user_action_required": true,
  "recommended_action": "验证镜像名称和标签是否正确（如 nf-core/rnaseq:3.0），或将镜像推送到私有ECR",
  "risk_level": "medium",
  "estimated_cost": 0.0,
  "confidence": 0.90
}}
```

**案例14: STAR索引版本不兼容**
```json
{{
  "issue_type": "star_alignment_error",
  "severity": "high",
  "root_cause": "STAR基因组索引版本与当前STAR版本不兼容",
  "description": "STAR报告 'Genome index is too old' 或 'EXITING because of FATAL ERROR: Genome version is INCOMPATIBLE'",
  "fixable": false,
  "user_action_required": true,
  "recommended_action": "使用STAR当前版本重新构建基因组索引，或从iGenomes下载匹配版本的索引",
  "risk_level": "low",
  "estimated_cost": 0.0,
  "confidence": 0.95
}}
```

**案例15: 低比对率（数据质量问题）**
```json
{{
  "issue_type": "low_mapping_rate",
  "severity": "medium",
  "root_cause": "FASTQ数据比对到参考基因组的成功率过低（<50%），可能是物种不匹配或数据污染",
  "description": "比对工具报告 'Overall alignment rate: 15.2%'，远低于正常值（应该>70%）",
  "fixable": false,
  "user_action_required": true,
  "recommended_action": "使用FastQC检查数据质量，确认参考基因组物种是否匹配，检查是否有adapter污染",
  "risk_level": "low",
  "estimated_cost": 0.0,
  "confidence": 0.88
}}
```

## 文件格式问题识别指南

**当错误日志包含以下关键词时，应识别为文件格式问题（需要用户操作）**：

1. **FASTQ 问题**:
   - 关键词: "quality score", "phred", "quality encoding", "invalid fastq"
   - issue_type: "fastq_quality_error"

2. **BAM 文件问题**:
   - 关键词: "invalid BAM", "truncated", "EOF marker", "bam_header_read"
   - issue_type: "bam_file_corrupt"

3. **VCF 文件问题**:
   - 关键词: "malformed VCF", "invalid variant", "INFO field not declared"
   - issue_type: "vcf_format_error"

4. **FASTA 编码问题**:
   - 关键词: "invalid FASTA", "line endings", "encoding error", "faidx failed"
   - issue_type: "fasta_encoding_error"

5. **GTF/GFF 问题**:
   - 关键词: "GTF", "no transcript", "annotation", "invalid format", "KeyError", "exon_number", "iCount", "cannot parse GTF"
   - issue_type: "gtf_format_error"
   - **特别注意**: 如果看到 `[KeyError] exon_number` 或 `iCount tool cannot parse GTF file`，一定是 GTF 文件缺少必需属性

**重要**: 对于文件格式问题，应设置 `fixable: false` 和 `user_action_required: true`，因为这些问题需要用户重新上传或处理文件。

## 输出格式

请返回 **JSON 数组格式** 的修复方案（参考上述examples）：

```json
[
  {{
    "issue_type": "错误类型",
    "severity": "high/medium/low",
    "root_cause": "一句话描述根本原因",
    "description": "详细描述问题",
    "fixable": true,
    "fix_actions": [
      {{
        "action": "update_parameter/add_parameter/increase_resource",
        "parameter_name": "参数名",
        "new_value": "新值",
        "reason": "为什么这样修复"
      }}
    ],
    "risk_level": "low/medium/high",
    "estimated_cost": 0.0,
    "confidence": 0.95
  }}
]
```

## 重要提示

1. **issue_type 必须具体、描述性强**：
   - ✅ 好的例子: "gtf_format_error", "star_memory_insufficient", "missing_reference_genome"
   - ❌ 不好的例子: "nextflow_error", "workflow_failure", "error" (太泛泛！)
   - **issue_type 应该清楚描述具体什么出错了**（什么文件？什么资源？什么参数？）

2. **fixable 字段的判断标准（非常重要！请严格遵循）**：

   **fixable: true 的场景（可以自动修复）**：
   - ✅ 增加内存/CPU/磁盘等资源配置
   - ✅ 添加或修改workflow参数（如 source, aligner）
   - ✅ 调整重试次数或超时时间
   - ✅ 修改容器配置或网络设置
   - 判断标准: **系统可以自动执行修复操作，无需人工介入**

   **fixable: false 的场景（需要用户操作）**：
   - ❌ 文件格式错误（GTF缺少属性、BAM损坏、VCF格式错误、FASTQ编码错误）
   - ❌ 数据质量问题（低比对率、高重复率、adapter污染）
   - ❌ 文件不存在或路径错误
   - ❌ 需要重新构建索引（STAR索引版本不兼容）
   - ❌ AWS权限配置问题（需要修改IAM策略）
   - ❌ 磁盘空间不足（需要清理或扩容）
   - 判断标准: **需要用户手动上传文件、修复数据、或修改外部配置**

   **关键区分**：
   - 如果问题是"数据本身有问题"（文件损坏、格式错误、质量差） → fixable: false
   - 如果问题是"配置不当"（参数缺失、资源不足） → fixable: true

   **对于 fixable: false 的问题**：
   - 必须设置 `user_action_required: true`
   - 必须提供详细的 `recommended_action`（告诉用户具体怎么做）
   - recommended_action 应该包含具体工具和命令示例

3. **recommended_action 编写标准（针对 fixable: false 的问题）**：

   **优秀的 recommended_action 示例**：
   ```
   "recommended_action": "使用 GENCODE 或 Ensembl 下载标准 GTF 文件（https://www.gencodegenes.org/），或使用 AGAT 工具修复现有文件: agat_convert_sp_gxf2gxf.pl --gff input.gtf -o fixed.gtf"
   ```

   **差的 recommended_action 示例**：
   ```
   "recommended_action": "修复GTF文件"  ❌ 太笼统，用户不知道怎么做
   ```

   **编写要点**：
   - ✅ 包含具体工具名称（如 bedtools, samtools, AGAT, FastQC）
   - ✅ 提供命令示例或网站链接
   - ✅ 说明预期结果（如"确保比对率>70%"）
   - ✅ 多个方案时，按推荐优先级排列
   - ❌ 不要只说"检查文件"、"修复问题"等空话

4. **每个修复动作必须具体、可执行**，包含明确的参数名和值

5. **优先低风险、高信心的方案**

6. **estimated_cost**: 修复的AWS成本估算（单位：美元）
   - 增加内存: 约 $0.5-2.0/小时
   - 增加CPU: 约 $0.3-1.5/小时
   - On-Demand替代Spot: 约增加2-3倍成本
   - 如果不增加AWS资源，cost = 0.0

7. **confidence**: 你对修复方案成功率的信心（0.0-1.0）
   - 0.95-1.0: 非常确定（如明确的参数错误）
   - 0.85-0.94: 比较确定（如常见的资源问题）
   - 0.70-0.84: 中等确定（如数据质量问题）
   - <0.70: 不确定，不要返回

8. **只返回JSON数组，不要任何markdown标记或其他文字**

9. **如果错误日志提到具体的文件类型、工具名称、资源类型，必须在 issue_type 中体现**
   - 例如：如果日志提到 "GTF" → issue_type 应该包含 "gtf"
   - 例如：如果日志提到 "STAR" → issue_type 应该包含 "star"
   - 例如：如果日志提到 "memory" → issue_type 应该包含 "memory"

现在请开始分析：
"""

        return prompt

    def _extract_error_summary(self, error_logs: str, max_lines: int = 50) -> str:
        """
        从错误日志中提取关键部分

        🆕 Phase 2.3补充: 增强错误日志提取
        - 提取stack trace
        - 清理DEBUG信息
        - 高亮关键错误信息
        """
        if not error_logs:
            return "(无错误日志)"

        lines = error_logs.split('\n')

        # 🆕 预处理: 去除DEBUG级别日志
        filtered_lines = []
        for line in lines:
            # 跳过DEBUG信息
            if re.match(r'.*\[DEBUG\].*', line, re.IGNORECASE):
                continue
            # 跳过过长的无意义行
            if len(line) > 500:
                continue
            filtered_lines.append(line)

        lines = filtered_lines

        # 查找关键错误模式
        error_lines = []
        stack_trace_lines = []
        important_keywords = [
            'ERROR', 'FAILED', 'Exception', 'FATAL', 'CRITICAL',
            'KeyError', 'ValueError', 'FileNotFoundError', 'MemoryError',
            'exit code', 'Killed', 'OOM', 'Traceback'
        ]

        in_stack_trace = False
        for i, line in enumerate(lines):
            # 检测stack trace开始
            if 'Traceback' in line or 'Stack trace' in line:
                in_stack_trace = True
                stack_trace_lines.append(line)
                continue

            # 在stack trace中
            if in_stack_trace:
                stack_trace_lines.append(line)
                # Stack trace通常以空行结束
                if not line.strip():
                    in_stack_trace = False
                continue

            # 查找关键错误信息
            for keyword in important_keywords:
                if keyword in line:
                    # 包含前后各 3 行上下文
                    start = max(0, i - 3)
                    end = min(len(lines), i + 4)
                    error_lines.extend(lines[start:end])
                    break

        # 🆕 优先返回stack trace (如果有)
        if stack_trace_lines:
            error_lines = stack_trace_lines[:30] + ['...'] + error_lines

        if error_lines:
            # 去重并限制长度
            unique_lines = []
            seen = set()
            for line in error_lines:
                if line not in seen:
                    unique_lines.append(line)
                    seen.add(line)
                if len(unique_lines) >= max_lines:
                    break
            return '\n'.join(unique_lines)
        else:
            # 如果没有关键错误，返回最后部分(去除DEBUG后)
            return '\n'.join(lines[-max_lines:])

    def _parse_llm_response(self, response_text: str) -> List[Dict[str, Any]]:
        """解析 LLM 返回的 JSON 响应"""
        try:
            # 提取 JSON（可能被 markdown 包围）
            json_match = re.search(r'\[.*\]', response_text, re.DOTALL)
            if not json_match:
                log.warning("No JSON array found in LLM response")
                return []

            issues = json.loads(json_match.group(0))

            # 🆕 泛泛的、无用的 issue_type（需要拒绝）
            generic_types = {
                'nextflow_error', 'nextflow_warning', 'workflow_failure',
                'workflow_error', 'error', 'failure', 'unknown_error',
                'generic_error', 'task_failure', 'process_error'
            }

            # 验证和规范化
            validated_issues = []
            for idx, issue in enumerate(issues):
                if not isinstance(issue, dict):
                    log.warning(f"⚠️  Issue {idx+1}: Not a dict, skipping")
                    continue

                # 🆕 接受 fixable=false 的问题（用于生成 User Guidance）
                is_fixable = issue.get('fixable', False)

                issue_type = issue.get('issue_type', 'unknown')

                # 🆕 拒绝泛泛的 issue_type
                if issue_type.lower() in generic_types:
                    log.warning(f"⚠️  Issue {idx+1}: Rejected generic issue_type '{issue_type}' - LLM must be more specific!")
                    log.warning(f"    Description: {issue.get('description', 'N/A')}")
                    log.warning(f"    Root cause: {issue.get('root_cause', 'N/A')}")
                    # 尝试从 description 或 root_cause 提取更具体的类型
                    issue_type = self._infer_specific_type(issue)
                    if not issue_type:
                        log.warning(f"    ❌ Cannot infer specific type - skipping this issue")
                        continue
                    else:
                        log.info(f"    ✅ Inferred specific type: {issue_type}")

                # 🆕 Day 6: 验证必需字段
                validation_errors = self._validate_issue_fields(issue, is_fixable, idx+1)
                if validation_errors:
                    log.warning(f"⚠️  Issue {idx+1} ({issue_type}): Validation failed:")
                    for error in validation_errors:
                        log.warning(f"    - {error}")
                    # 如果验证失败太严重，跳过这个issue
                    if len(validation_errors) >= 3:
                        log.warning(f"    ❌ Too many errors, skipping this issue")
                        continue
                    else:
                        log.warning(f"    ⚠️  Proceeding with warnings")

                # 🆕 为 fixable:false 的问题附加详细的 User Guidance
                user_guidance = None
                if not is_fixable or issue.get('user_action_required', False):
                    user_guidance = self._get_user_guidance(issue_type, issue)
                    log.info(f"📋 Attached User Guidance for {issue_type}: {user_guidance is not None}")

                validated_issues.append({
                    'type': issue_type,
                    'severity': issue.get('severity', 'medium'),
                    'root_cause': issue.get('root_cause', ''),
                    'description': issue.get('description', ''),
                    'fixable': is_fixable,  # 🆕 使用 LLM 返回的 fixable 值
                    'fix_actions': issue.get('fix_actions', []),
                    'risk_level': issue.get('risk_level', 'medium'),
                    'estimated_cost': issue.get('estimated_cost', 0.0),
                    'confidence': issue.get('confidence', 0.5),
                    'user_action_required': issue.get('user_action_required', False),  # 🆕 支持 user_action_required
                    'recommended_action': issue.get('recommended_action', ''),  # 🆕 支持 recommended_action
                    'user_guidance': user_guidance,  # 🆕 附加详细的 User Guidance
                    'llm_generated': True,  # 标记为 LLM 生成
                })

            return validated_issues

        except json.JSONDecodeError as e:
            log.error(f"Failed to parse LLM JSON response: {e}")
            log.debug(f"Response text: {response_text[:500]}")
            return []

    def _infer_specific_type(self, issue: Dict[str, Any]) -> Optional[str]:
        """
        从 issue 的 description 和 root_cause 中推断具体的类型

        Args:
            issue: LLM 返回的 issue 字典

        Returns:
            推断出的具体类型，如果无法推断则返回 None
        """
        description = issue.get('description', '').lower()
        root_cause = issue.get('root_cause', '').lower()
        combined = f"{description} {root_cause}"

        # GTF 相关
        if 'gtf' in combined or 'transcript' in combined or 'annotation' in combined:
            if 'format' in combined or 'invalid' in combined:
                return 'gtf_format_error'
            if 'missing' in combined or 'not found' in combined:
                return 'missing_gtf_file'
            return 'gtf_related_error'

        # 参考基因组相关
        if 'genome' in combined or 'reference' in combined or 'index' in combined:
            if 'missing' in combined or 'not found' in combined:
                return 'missing_reference_genome'
            if 'memory' in combined or 'oom' in combined:
                return 'genome_index_memory_error'
            return 'reference_genome_error'

        # STAR 相关
        if 'star' in combined:
            if 'memory' in combined or 'oom' in combined:
                return 'star_memory_insufficient'
            if 'index' in combined:
                return 'star_index_error'
            return 'star_aligner_error'

        # 内存相关
        if 'memory' in combined or 'oom' in combined:
            return 'memory_insufficient'

        # 磁盘相关
        if 'disk' in combined or 'space' in combined:
            return 'disk_space_insufficient'

        # 参数相关
        if 'parameter' in combined or 'param' in combined:
            if 'missing' in combined:
                return 'missing_parameter'
            if 'invalid' in combined or 'wrong' in combined:
                return 'invalid_parameter'
            return 'parameter_error'

        # 无法推断
        return None

    async def _refine_llm_classification(
        self,
        error_data: Dict,
        initial_issue: Dict[str, Any],
        error_summary: str
    ) -> Optional[Dict[str, Any]]:
        """
        🆕 Phase 2.4补充: 多轮对话refinement机制

        当LLM返回泛泛类型或低confidence时，进行二次分析以获取更精确的分类

        Args:
            error_data: 原始错误数据
            initial_issue: LLM第一轮返回的issue
            error_summary: 错误日志摘要

        Returns:
            Refined issue或None(如果refinement失败)
        """
        try:
            initial_type = initial_issue.get('issue_type', 'unknown')
            description = initial_issue.get('description', '')
            confidence = initial_issue.get('confidence', 0.5)

            # 只对低confidence或泛泛类型进行refinement
            generic_types = {
                'nextflow_error', 'workflow_failure', 'workflow_error',
                'error', 'failure', 'unknown_error'
            }

            if confidence >= 0.85 and initial_type not in generic_types:
                # 已经足够精确，无需refinement
                return None

            log.info(f"🔄 Refining classification for '{initial_type}' (confidence: {confidence:.2f})")

            # 准备refinement prompt
            refinement_prompt = f"""你是一个精确的错误分类专家。第一轮分析给出了一个不够精确的错误类型。

**第一轮分析结果**:
- issue_type: {initial_type}
- description: {description}
- confidence: {confidence:.2f}

**原始错误日志**:
```
{error_summary[:1000]}
```

**可选的精确错误类型列表**:
{', '.join([
    'gtf_format_error', 'bed_format_error', 'gff_format_error',
    'fastq_encoding_error', 'bam_file_corrupt', 'vcf_format_error',
    'memory_oom_killer', 'disk_quota_exceeded', 'cpu_timeout',
    'star_alignment_error', 'bowtie2_alignment_error', 'samtools_sort_error',
    'aws_batch_permission_denied', 'aws_batch_spot_interruption',
    's3_transfer_error', 'container_pull_error', 'missing_parameter'
])}

**请重新分析并返回**:
1. 最精确的issue_type (从上述列表中选择)
2. 你的confidence (0.0-1.0)
3. 简短的判断理由 (1-2句话)

**只返回JSON格式**:
```json
{{
  "refined_issue_type": "最精确的类型",
  "confidence": 0.95,
  "reasoning": "判断理由"
}}
```"""

            # 调用LLM进行refinement
            if not self.llm_client:
                log.warning("No LLM client available for refinement")
                return None

            refined_response = await self.llm_client.generate(
                prompt=refinement_prompt,
                max_tokens=500,
                temperature=0.1  # 低温度以获得更确定的结果
            )

            # 解析refinement结果
            json_match = re.search(r'\{.*\}', refined_response, re.DOTALL)
            if not json_match:
                log.warning("No JSON found in refinement response")
                return None

            refined_data = json.loads(json_match.group(0))
            refined_type = refined_data.get('refined_issue_type')
            refined_confidence = refined_data.get('confidence', 0.7)
            reasoning = refined_data.get('reasoning', '')

            if refined_type and refined_confidence >= 0.80:
                log.info(f"✅ Refinement successful: {initial_type} → {refined_type} (conf: {refined_confidence:.2f})")
                log.info(f"   Reasoning: {reasoning}")

                # 更新issue
                refined_issue = initial_issue.copy()
                refined_issue['issue_type'] = refined_type
                refined_issue['confidence'] = refined_confidence
                refined_issue['refinement_reasoning'] = reasoning
                refined_issue['refined'] = True

                return refined_issue
            else:
                log.warning(f"Refinement confidence too low ({refined_confidence:.2f})")
                return None

        except Exception as e:
            log.error(f"Refinement failed: {e}", exc_info=True)
            return None

    def _rule_based_detect(self, error_data: Dict) -> List[Dict[str, Any]]:
        """规则引擎降级方案"""
        issues = []

        # 简单规则：检测常见错误模式
        error_logs = error_data.get('error_logs', '').lower()

        if 'gtf' in error_logs and 'transcript' in error_logs:
            issues.append({
                'type': 'gtf_transcript_error',
                'severity': 'high',
                'description': 'GTF 文件缺少 transcript-level features',
                'fixable': True,
                'fix_actions': [{'action': 'add_parameter', 'parameter_name': 'skip_filter_gtf', 'new_value': True}],
                'risk_level': 'low',
                'llm_generated': False,
            })

        if 'oom' in error_logs or 'memory' in error_logs:
            issues.append({
                'type': 'resource_exhaustion',
                'severity': 'high',
                'description': '内存不足',
                'fixable': True,
                'fix_actions': [{'action': 'increase_resource', 'resource': 'memory', 'multiplier': 2}],
                'risk_level': 'low',
                'llm_generated': False,
            })

        return issues

    def generate_fix(self, issue: Dict[str, Any], context: FixContext) -> Optional[AutoFixResult]:
        """
        生成修复方案

        对于 LLM 生成的 issue，直接使用其 fix_actions
        """
        if not issue.get('fixable'):
            return None

        fix_actions = []

        # 将 LLM 建议的 action 转换为 FixAction 对象
        for action_dict in issue.get('fix_actions', []):
            action_type_str = action_dict.get('action', 'update_parameter')

            # 映射到 ActionType enum
            action_type_map = {
                'update_parameter': ActionType.UPDATE_PARAMETER,
                'add_parameter': ActionType.UPDATE_PARAMETER,
                'increase_resource': ActionType.INCREASE_RESOURCE,
                'retry': ActionType.RETRY_TASK,
            }
            action_type = action_type_map.get(action_type_str, ActionType.UPDATE_PARAMETER)

            # 构建参数字典
            params = {}
            if 'parameter_name' in action_dict:
                params[action_dict['parameter_name']] = action_dict.get('new_value')
            elif 'resource' in action_dict:
                params['resource'] = action_dict.get('resource')
                params['multiplier'] = action_dict.get('multiplier', 1.5)

            fix_actions.append(FixAction(
                action=action_type,
                params=params,
                description=action_dict.get('reason', ''),
                risk_level=issue.get('risk_level', 'medium')
            ))

        # 创建 AutoFixResult
        result = AutoFixResult(
            fix_id=None,
            fixer_name="LLMFirstFixer",
            status=FixStatus.APPLIED,
            fix_type=issue['type'],
            fix_actions=fix_actions,
            risk_level=self._parse_risk_level(issue.get('risk_level', 'medium')),
            success=True,
            estimated_cost=issue.get('estimated_cost', 0.0),
            auto_approved=issue.get('risk_level') == 'low',
            original_issue=issue,  # 🆕 保存原始 issue 信息
        )

        log.info(f"✅ Generated fix for {issue['type']} with {len(fix_actions)} actions")

        return result

    def _parse_risk_level(self, risk_str: str) -> RiskLevel:
        """解析风险等级"""
        risk_map = {
            'low': RiskLevel.LOW,
            'medium': RiskLevel.MEDIUM,
            'high': RiskLevel.HIGH,
        }
        return risk_map.get(risk_str.lower(), RiskLevel.MEDIUM)

    def generate_fix_plan(
        self,
        context: FixContext,
        issues: List[Dict[str, Any]]
    ) -> Optional['FixPlan']:
        """
        生成修复计划（BaseAutoFixer 要求的抽象方法）

        对于 LLM-First，这个方法在 detect_issues 中已经完成
        这里直接返回一个汇总的 FixPlan
        """
        from ...types import FixPlan, FixType

        if not issues:
            return None

        # 汇总所有可修复的问题
        fixable_issues = [i for i in issues if i.get('fixable')]

        if not fixable_issues:
            return None

        # 使用第一个问题的类型作为主要类型
        primary_issue = fixable_issues[0]

        # 创建FixAction列表
        from ...types import FixAction
        fix_actions = []
        for issue in fixable_issues:
            if 'fix_suggestion' in issue:
                action = FixAction(
                    action_type=self._map_to_fix_type(issue['type']),
                    parameters=issue.get('parameters', {}),
                    description=issue.get('fix_suggestion', ''),
                    reason=issue.get('description', '')
                )
                fix_actions.append(action)

        fix_plan = FixPlan(
            fixable=True,
            fix_type=self._map_to_fix_type(primary_issue['type']),
            fix_actions=fix_actions,
            explanation=primary_issue.get('description', ''),
            confidence=primary_issue.get('confidence', 0.7),
            estimated_success_rate=primary_issue.get('confidence', 0.7),
            requires_user_confirmation=primary_issue.get('risk_level', 'medium') != 'low'
        )

        return fix_plan

    def _map_to_fix_type(self, issue_type: str) -> 'FixType':
        """将 issue_type 映射到 FixType enum"""
        from ...types import FixType

        type_map = {
            'gtf_format_error': FixType.CONFIG_ADJUSTMENT,
            'gtf_transcript_error': FixType.CONFIG_ADJUSTMENT,
            'missing_parameter': FixType.CONFIG_ADJUSTMENT,
            'resource_exhaustion': FixType.RESOURCE_SCALING,
            'container_error': FixType.MANUAL_INTERVENTION,
            'file_not_found': FixType.DATA_CONVERSION,
        }

        return type_map.get(issue_type, FixType.CONFIG_ADJUSTMENT)

    async def apply_fix(
        self,
        context: FixContext,
        fix_plan: 'FixPlan',
        sa_session: Any
    ) -> AutoFixResult:
        """
        应用修复（BaseAutoFixer 要求的抽象方法）

        对于 LLM-First，修复由 generate_fix() 方法处理
        这里返回一个成功的结果

        Args:
            context: Fix context
            fix_plan: Generated fix plan
            sa_session: Database session (unused for LLM-First)
        """
        result = AutoFixResult(
            fix_id=None,
            fixer_name="LLMFirstFixer",
            status=FixStatus.APPLIED,
            fix_type=fix_plan.fix_type.value,
            fix_actions=[],
            risk_level=self._parse_risk_level(fix_plan.risk_level),
            success=True,
            estimated_cost=fix_plan.estimated_cost,
            auto_approved=not fix_plan.requires_user_confirmation,
        )

        return result

    def _validate_issue_fields(self, issue: Dict[str, Any], is_fixable: bool, issue_num: int) -> List[str]:
        """
        验证issue的必需字段和数据质量

        Args:
            issue: LLM返回的issue字典
            is_fixable: 是否可自动修复
            issue_num: Issue编号(用于日志)

        Returns:
            验证错误列表（空列表表示验证通过）
        """
        errors = []

        # 1. 验证必需字段存在
        required_fields = ['issue_type', 'severity', 'root_cause', 'description']
        for field in required_fields:
            if not issue.get(field):
                errors.append(f"Missing required field: {field}")

        # 2. 验证 severity 值
        valid_severities = ['high', 'medium', 'low']
        if issue.get('severity') and issue['severity'].lower() not in valid_severities:
            errors.append(f"Invalid severity '{issue['severity']}', must be: {valid_severities}")

        # 3. 验证 confidence 值
        confidence = issue.get('confidence', 0.5)
        if not isinstance(confidence, (int, float)) or not (0.0 <= confidence <= 1.0):
            errors.append(f"Invalid confidence '{confidence}', must be between 0.0 and 1.0")
        elif confidence < 0.70:
            errors.append(f"Confidence too low ({confidence:.2f}), must be >= 0.70")

        # 4. 验证 fixable:true 的issue必须有fix_actions
        if is_fixable:
            fix_actions = issue.get('fix_actions', [])
            if not fix_actions or not isinstance(fix_actions, list) or len(fix_actions) == 0:
                errors.append("fixable:true but no fix_actions provided")
            else:
                # 验证每个 fix_action 的结构
                for action_idx, action in enumerate(fix_actions):
                    if not isinstance(action, dict):
                        errors.append(f"fix_actions[{action_idx}] is not a dict")
                        continue
                    if not action.get('parameter_name'):
                        errors.append(f"fix_actions[{action_idx}] missing parameter_name")
                    if 'new_value' not in action:  # 允许 new_value 为空字符串或 False
                        errors.append(f"fix_actions[{action_idx}] missing new_value")

        # 5. 验证 fixable:false 的issue必须有 user_action_required 和 recommended_action
        if not is_fixable:
            if not issue.get('user_action_required'):
                errors.append("fixable:false but user_action_required is not set to true")
            if not issue.get('recommended_action'):
                errors.append("fixable:false but no recommended_action provided")
            elif len(issue['recommended_action']) < 20:
                errors.append(f"recommended_action too short ({len(issue['recommended_action'])} chars), should be detailed")

        # 6. 验证 description 和 root_cause 不能太短
        if issue.get('description') and len(issue['description']) < 10:
            errors.append(f"description too short ({len(issue['description'])} chars)")
        if issue.get('root_cause') and len(issue['root_cause']) < 10:
            errors.append(f"root_cause too short ({len(issue['root_cause'])} chars)")

        # 7. 验证 issue_type 不能太短或太泛泛
        issue_type = issue.get('issue_type', '')
        if len(issue_type) < 5:
            errors.append(f"issue_type too short: '{issue_type}'")

        return errors

    def _get_reference_template(self, issue_type: str) -> Optional[str]:
        """
        获取参考模板（仅作为 LLM 的示例，不直接返回）

        Args:
            issue_type: 问题类型

        Returns:
            参考模板的简要说明（如果有）
        """
        try:
            from ..user_guidance import (
                GTF_FORMAT_ERROR_GUIDANCE,
                MISSING_REFERENCE_GENOME_GUIDANCE,
                STAR_MEMORY_ERROR_GUIDANCE,
                BED_FORMAT_ERROR_GUIDANCE,
                MEMORY_OOM_KILLER_GUIDANCE,
                AWS_BATCH_SPOT_INTERRUPTION_GUIDANCE,
            )

            # 主要问题类型的参考模板映射（简化版，只保留核心类型）
            template_map = {
                'gtf_format_error': GTF_FORMAT_ERROR_GUIDANCE,
                'bed_format_error': BED_FORMAT_ERROR_GUIDANCE,
                'missing_reference_genome': MISSING_REFERENCE_GENOME_GUIDANCE,
                'memory_oom_killer': MEMORY_OOM_KILLER_GUIDANCE,
                'star_memory_insufficient': STAR_MEMORY_ERROR_GUIDANCE,
                'aws_batch_spot_interruption': AWS_BATCH_SPOT_INTERRUPTION_GUIDANCE,
            }

            template = template_map.get(issue_type)
            if template:
                # 返回模板的简要说明，作为 LLM 的参考
                return f"参考示例：{template.problem_summary}\n解决策略：{template.fix_strategy.value}"

            return None

        except Exception as e:
            log.warning(f"Could not load reference template for {issue_type}: {e}")
            return None

    def _generate_dynamic_guidance(
        self,
        issue_type: str,
        issue: Dict[str, Any],
        reference_template: Optional[str] = None
    ) -> Optional[Dict[str, Any]]:
        """
        🆕 使用 LLM 基于真实错误日志动态生成 User Guidance

        Args:
            issue_type: 问题类型
            issue: 包含真实错误信息的问题详情
            reference_template: 参考模板（可选）

        Returns:
            动态生成的 User Guidance
        """
        try:
            # 提取真实错误信息
            error_message = issue.get('error_message', '')
            error_logs = issue.get('error_logs', '')
            description = issue.get('description', '')
            severity = issue.get('severity', 'medium')

            # 构建 LLM Prompt
            prompt = f"""你是一个生物信息学 Workflow 故障诊断专家。请基于以下**真实的错误日志**，为用户生成详细的修复指导。

**问题类型**: {issue_type}
**严重程度**: {severity}
**错误描述**: {description}
**错误消息**: {error_message}
**错误日志**:
{error_logs[:2000]}  # 限制长度

{f'**参考示例**: {reference_template}' if reference_template else ''}

请生成一个 JSON 格式的修复指导，包含：
1. **problem_summary**: 问题的简要总结（1-2句话）
2. **problem_details**: 详细的问题说明（包括可能的原因）
3. **recommended_actions**: 推荐的修复步骤列表（按优先级排序）

每个 recommended_action 包含：
- priority: 优先级（1-5，1最高）
- title: 操作标题
- description: 操作描述
- steps: 具体步骤列表
- estimated_time: 预计耗时
- success_probability: 成功概率（0.0-1.0）
- impact: 影响说明

**重要要求**：
- 必须基于真实错误日志分析，不要泛泛而谈
- 给出具体的、可操作的步骤
- 如果错误日志中有具体的文件名、参数名，必须在建议中引用
- 按优先级排序（最有可能解决问题的放在前面）

请直接返回 JSON，不要有任何其他文字。
"""

            # 调用 LLM
            log.info(f"🤖 Calling LLM to generate dynamic User Guidance for {issue_type}...")
            response = self.llm_client.call(
                messages=[{"role": "user", "content": prompt}],
                max_tokens=2000,
                temperature=0.2,  # 较低的温度，保证输出稳定
            )

            # 解析 LLM 响应
            import json
            # content 是一个 blocks 数组，提取文本
            content_blocks = response.get('content', [])
            if isinstance(content_blocks, list) and len(content_blocks) > 0:
                # 提取第一个 text block
                response_text = content_blocks[0].get('text', '')
            elif isinstance(content_blocks, str):
                response_text = content_blocks
            else:
                response_text = ''

            guidance_data = json.loads(response_text.strip())

            # 构建标准格式的 User Guidance
            return {
                'issue_type': issue_type,
                'severity': severity,
                'category': 'dynamic_llm_generated',
                'fix_strategy': 'manual',
                'problem_summary': guidance_data.get('problem_summary', ''),
                'problem_details': guidance_data.get('problem_details', ''),
                'recommended_actions': guidance_data.get('recommended_actions', []),
                'generated_by': 'llm',  # 标记为 LLM 生成
                'timestamp': str(datetime.now()),
            }

        except Exception as e:
            log.error(f"Failed to generate dynamic guidance: {e}")
            import traceback
            traceback.print_exc()
            return None

    def _get_user_guidance(self, issue_type: str, issue: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """
        🆕 基于真实错误日志，使用 LLM 动态生成 User Guidance

        设计原则：
        1. 必须基于真实的错误日志分析
        2. LLM 动态生成针对性的修复建议
        3. 预设模板仅作为参考示例，不直接返回

        Args:
            issue_type: 问题类型（如 'gtf_format_error'）
            issue: 问题详情，包含真实的错误日志和上下文

        Returns:
            基于真实错误分析的 User Guidance 字典
        """
        try:
            # 1. 提取真实的错误信息
            error_message = issue.get('error_message', '')
            error_logs = issue.get('error_logs', '')
            description = issue.get('description', '')

            # 如果没有真实错误信息，不生成 Guidance
            if not error_message and not error_logs and not description:
                log.warning(f"⚠️  No real error data for issue type '{issue_type}', skipping User Guidance generation")
                return None

            # 2. 尝试获取参考模板（仅作为 LLM 的参考示例）
            reference_template = self._get_reference_template(issue_type)

            # 3. 使用 LLM 基于真实错误动态生成 User Guidance
            guidance = self._generate_dynamic_guidance(
                issue_type=issue_type,
                issue=issue,
                reference_template=reference_template
            )

            return guidance

        except Exception as e:
            log.error(f"Failed to generate User Guidance: {e}")
            import traceback
            traceback.print_exc()
            return None
