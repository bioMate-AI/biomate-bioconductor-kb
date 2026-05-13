"""
LLM Universal Fixer - 通用智能修复器

基于大语言模型的通用错误修复器，替代所有专门的规则式 Fixers。
实现高度泛化、自适应的错误诊断和修复能力。

设计理念：
1. 一个 Fixer 修复所有错误类型
2. LLM 原生理解，无需规则匹配
3. 基于历史案例的少样本学习
4. 自适应未知错误场景
"""

import logging
import json
import re
import inspect
import os
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
from ...types import FixAction, ActionType, FixPlan, FixType
from ..deep_log_analyzer import DeepLogAnalyzer

log = logging.getLogger(__name__)


class LLMUniversalFixer(BaseAutoFixer):
    """
    通用 LLM 驱动的自动修复器

    核心能力:
    - 理解任何类型的 Nextflow 错误（CPU、内存、文件格式、配置、权限等）
    - 基于深度日志分析生成精准修复方案
    - 少样本学习：利用历史修复记录提升准确率
    - 自适应：处理从未见过的新错误类型
    - 可解释：提供详细的诊断和修复理由
    """

    name = "LLMUniversalFixer"
    description = "基于 Claude Sonnet 4 的通用智能错误修复器，支持所有 Nextflow 错误类型"

    def __init__(self, llm_client=None, max_context_tokens: int = 8000):
        """
        初始化通用修复器

        Args:
            llm_client: LLM 客户端（如果为 None，会自动创建）
            max_context_tokens: LLM 上下文最大 token 数
        """
        super().__init__()
        self.llm_client = llm_client
        self.max_context_tokens = max_context_tokens

        # 如果没有提供 LLM client，尝试创建
        if not self.llm_client:
            try:
                from ...llm_client import UnifiedLLMClient
                self.llm_client = UnifiedLLMClient()
                log.info("✅ LLMUniversalFixer initialized with LLM client")
            except Exception as e:
                log.error(f"❌ Failed to initialize LLM client: {e}")
                raise RuntimeError(f"LLMUniversalFixer requires LLM client: {e}")

    def detect_issues(self, context: FixContext) -> List[Dict[str, Any]]:
        """
        使用深度日志分析 + LLM 智能检测所有问题

        工作流程:
        1. 使用 DeepLogAnalyzer 收集完整上下文
        2. LLM 分析日志，识别所有错误
        3. 对每个错误给出根因、修复方案、风险评估

        Args:
            context: Fix context

        Returns:
            检测到的问题列表，每个问题包含详细诊断和修复建议
        """
        from galaxy.model import WorkflowInvocation

        sa_session = context.metadata.get('sa_session')
        app_config = context.metadata.get('app_config')

        if not sa_session:
            log.error("❌ No sa_session in context metadata")
            return []

        invocation = sa_session.query(WorkflowInvocation).get(context.invocation_id)
        if not invocation:
            log.error(f"❌ Invocation {context.invocation_id} not found")
            return []

        # Step 1: 深度日志分析
        log.info("📊 Step 1: Collecting comprehensive error context...")
        analyzer = DeepLogAnalyzer(
            workflow_invocation_id=context.invocation_id,
            app_config=app_config
        )

        try:
            analysis_context = analyzer.analyze()

            # 🔍 DEBUG: 打印分析上下文的摘要信息
            summary = analysis_context.get('summary', {})
            log.info(f"🔍 DEBUG: Analysis summary: {summary}")
            log.info(f"🔍 DEBUG: has_errors = {analysis_context.get('has_errors')}")
            log.info(f"🔍 DEBUG: total_failed_tasks = {summary.get('total_failed_tasks')}")
            log.info(f"🔍 DEBUG: total_errors = {summary.get('total_errors')}")

            # 检查是否有错误
            if not analysis_context.get('has_errors'):
                log.info("✅ No errors detected in workflow")
                return []

            # 格式化为 LLM 友好的文本
            llm_context = analyzer.format_for_llm(
                analysis_context,
                max_tokens=self.max_context_tokens
            )

            log.info(f"📋 Formatted context: {len(llm_context)} characters")

        except Exception as e:
            log.error(f"❌ Deep log analysis failed: {e}")
            import traceback
            traceback.print_exc()
            return []

        # Step 2: LLM 智能分析
        log.info("🤖 Step 2: Calling LLM for intelligent error analysis...")

        try:
            issues = self._llm_analyze_errors(llm_context, analysis_context, context)
            log.info(f"✅ LLM detected {len(issues)} issues")

            # 验证和增强 issues
            validated_issues = self._validate_and_enrich_issues(issues, analysis_context)
            log.info(f"✅ Validated {len(validated_issues)} issues")

            return validated_issues

        except Exception as e:
            log.error(f"❌ LLM analysis failed: {e}")
            import traceback
            traceback.print_exc()
            return []

    def _llm_analyze_errors(
        self,
        llm_context: str,
        raw_context: Dict[str, Any],
        fix_context: FixContext
    ) -> List[Dict[str, Any]]:
        """
        使用 LLM 深度分析错误并生成修复方案

        核心提示词设计：
        - 基于完整的错误上下文（不只是日志片段）
        - 提供历史修复案例作为 few-shot examples
        - 要求结构化 JSON 输出
        - 强调根因分析 > 症状描述

        Args:
            llm_context: 格式化的 LLM 上下文文本
            raw_context: 原始分析数据（包含历史修复）
            fix_context: 修复上下文

        Returns:
            LLM 识别的问题列表
        """
        # 构建通用分析 Prompt
        prompt = self._build_universal_analysis_prompt(llm_context, raw_context)

        log.info("🤖 Calling Claude Sonnet 4 for comprehensive analysis...")

        try:
            # 调用 LLM
            response = self.llm_client.call(
                messages=[{"role": "user", "content": prompt}],
                model="claude-sonnet-4-20250514",
                temperature=0.2,  # 低温度确保稳定输出
                max_tokens=6000  # 足够长以支持复杂场景
            )

            # 解析响应
            content = response.get('content', [])
            if isinstance(content, list):
                # 提取文本内容（content blocks 格式）
                text_content = ''
                for block in content:
                    if isinstance(block, dict) and block.get('type') == 'text':
                        text_content += block.get('text', '')
                content_str = text_content
            else:
                # 兼容字符串格式
                content_str = content

            # 🔍 DEBUG: 保存LLM原始响应用于调试
            debug_dir = f"/Users/renyuankai/work/biometa/galaxy/database/ai_workflow_ops/debug"
            os.makedirs(debug_dir, exist_ok=True)
            debug_file = os.path.join(debug_dir, f"llm_response_{fix_context.invocation_id}.txt")
            try:
                with open(debug_file, 'w') as f:
                    f.write(f"=== LLM Raw Response ===\n\n{content_str}\n")
                log.info(f"🔍 DEBUG: Saved LLM response to {debug_file}")
            except Exception as e:
                log.warning(f"⚠️  Failed to save debug LLM response: {e}")

            # 解析 JSON
            issues = self._parse_llm_response(content_str)

            log.info(f"✅ LLM analysis complete. Found {len(issues)} issues")

            return issues

        except Exception as e:
            log.error(f"❌ LLM analysis failed: {e}")
            import traceback
            traceback.print_exc()
            raise

    def _build_universal_analysis_prompt(
        self,
        llm_context: str,
        raw_context: Dict[str, Any]
    ) -> str:
        """
        构建通用的 LLM 分析提示词

        提示词策略：
        1. Chain-of-Thought 推理引导
        2. 明确的错误分类决策树
        3. Fixable vs Non-fixable 判断标准
        4. 丰富的 Few-shot Examples
        5. 结构化 JSON 输出要求

        Args:
            llm_context: 格式化的上下文文本
            raw_context: 原始上下文数据

        Returns:
            完整的 LLM Prompt
        """
        # 获取历史修复案例作为 Few-shot examples
        historical_fixes = raw_context.get('historical_fixes', [])
        few_shot_examples = self._format_few_shot_examples(historical_fixes)

        prompt = f"""你是一个 Nextflow Workflow 专家诊断系统。请深度分析以下失败的 workflow 并生成精准的修复方案。

## 完整的错误上下文

{llm_context}

## 你的任务

**请按照以下步骤进行 Chain-of-Thought 推理**：

1. **识别错误模式**: 从日志中提取关键错误信息（exit code、ERROR 关键词、异常类型、失败任务）
2. **定位根本原因**: 判断是配置问题、资源限制、文件格式错误、权限问题还是其他
3. **评估可修复性**: 判断能否通过修改参数/配置自动修复，还是需要用户手动干预
4. **设计修复方案**: 如果可修复，给出具体的参数调整；如果不可修复，给出详细的用户操作指南
5. **评估风险和成本**: 评估修复方案的风险级别和 AWS 成本影响

## 错误分类决策树（严格遵循）

### Step 1: 检查 Exit Code 优先级

**Exit Code 137 或 143**:
- → 内存不足 (OOM Killer)
- → issue_type: "memory_oom_killer"
- → fixable: true（通过增加内存）

**Exit Code 1**:
- → 继续检查错误日志内容

**Exit Code 139**:
- → 段错误 (Segmentation fault)
- → 检查内存/数据损坏

**Exit Code 255**:
- → AWS Batch 失败
- → 检查权限/资源

### Step 2: 错误关键词优先级匹配

**优先级 1: CPU/资源不足（可修复）**
- 包含 "Process requirement exceeds available CPUs" → "cpu_shortage"
  - fixable: true
  - fix_action: 减少 max_cpus 参数或增加可用 CPU
  - 示例: "req: 12; avail: 8" → 设置 max_cpus=8

- 包含 "Process requirement exceeds available memory" → "memory_shortage"
  - fixable: true
  - fix_action: 减少 max_memory 参数或增加内存限制

**优先级 2: 文件格式问题（通常不可修复）**
- 包含 "GTF" + ("KeyError" 或 "exon_number" 或 "transcript" 或 "cannot parse") → "gtf_format_error"
  - fixable: false
  - user_action_required: true
  - recommended_action: 使用标准 GTF（GENCODE/Ensembl）或使用 AGAT 工具修复

- 包含 "FASTA" + ("invalid" 或 "line endings") → "fasta_format_error"
- 包含 "FASTQ" + ("quality score" 或 "encoding") → "fastq_encoding_error"
- 包含 "BAM" + ("truncated" 或 "EOF marker") → "bam_file_corrupt"
- 包含 "VCF" + ("malformed" 或 "INFO field") → "vcf_format_error"

**优先级 3: 配置/参数问题（可修复）**
- 包含 "parameter" + ("required" 或 "missing") → "missing_parameter"
  - fixable: true
  - fix_action: 添加缺失参数

- 包含 "reference genome" + "not found" → "missing_reference_genome"
  - fixable: true（如果系统有该参考基因组）
  - fixable: false（如果需要用户上传）

**优先级 4: AWS 基础设施问题**
- 包含 "AccessDenied" 或 "permission denied" → "aws_permission_denied"
  - fixable: false
  - user_action_required: true

- 包含 "spot" + "interruption" → "aws_spot_interruption"
  - fixable: true（增加重试次数或切换到 On-Demand）

- 包含 "docker pull" 或 "manifest unknown" → "container_pull_error"
  - fixable: false
  - user_action_required: true

## Fixable 判断标准（关键！）

**fixable: true 的场景（可以自动修复）**：
✅ 调整资源配置（CPU、内存、磁盘）
✅ 添加或修改 workflow 参数（如 source, aligner, skip_*）
✅ 调整重试次数或超时时间
✅ 修改容器配置或执行器设置

**fixable: false 的场景（需要用户操作）**：
❌ 文件格式错误（GTF 缺少属性、BAM 损坏、VCF 格式错误）
❌ 数据质量问题（低比对率、高重复率）
❌ 文件不存在或路径错误
❌ AWS 权限配置问题
❌ 磁盘空间不足（需要手动清理或扩容）
❌ Docker 镜像不存在（需要修改镜像名或推送到 ECR）

**对于 fixable: false 的问题**：
- 必须设置 `user_action_required: true`
- 必须提供详细的 `recommended_action`（具体工具、命令、网站链接）

{few_shot_examples}

## 输出格式要求

**请返回 JSON 数组格式的修复方案**：

```json
[
  {{
    "issue_type": "具体的错误类型（如 cpu_shortage, gtf_format_error, missing_parameter）",
    "severity": "high/medium/low",
    "root_cause": "一句话描述根本原因（必须基于实际日志内容）",
    "description": "详细描述问题（包括具体的文件名、参数名、错误值）",
    "fixable": true,
    "fix_actions": [
      {{
        "action": "update_parameter/add_parameter/increase_resource/reduce_resource",
        "parameter_name": "参数名",
        "old_value": "当前值（如果有）",
        "new_value": "建议的新值",
        "reason": "为什么这样修复（必须有明确理由）"
      }}
    ],
    "risk_level": "low/medium/high",
    "estimated_cost": 0.0,
    "confidence": 0.95
  }}
]
```

**如果问题不可自动修复（fixable: false）**：

```json
[
  {{
    "issue_type": "gtf_format_error",
    "severity": "high",
    "root_cause": "GTF 文件缺少必需的 exon_number 属性",
    "description": "iCount 工具报告 '[KeyError] exon_number'，说明 GTF 文件格式不完整",
    "fixable": false,
    "user_action_required": true,
    "recommended_action": "使用 GENCODE 或 Ensembl 的标准 GTF 文件（https://www.gencodegenes.org/），或使用 AGAT 工具修复: agat_convert_sp_gxf2gxf.pl --gff input.gtf -o fixed.gtf",
    "risk_level": "low",
    "estimated_cost": 0.0,
    "confidence": 0.98
  }}
]
```

## 重要规则

1. **issue_type 必须具体、描述性强**：
   - ✅ 好: "cpu_shortage", "gtf_format_error", "star_memory_insufficient"
   - ❌ 差: "nextflow_error", "workflow_failure", "error"（太泛泛！）

2. **root_cause 必须基于实际日志**：
   - 必须引用日志中的具体错误信息、文件名、数值
   - 不要凭空猜测

3. **fix_actions 必须可执行**：
   - 必须包含明确的 parameter_name 和 new_value
   - reason 必须解释为什么这个值能解决问题

4. **recommended_action 必须详细（针对 fixable:false）**：
   - 包含具体工具名称（bedtools, samtools, AGAT, FastQC）
   - 提供命令示例或网站链接
   - 说明预期结果

5. **confidence 必须 >= 0.70**：
   - 0.95-1.0: 非常确定（明确的参数错误、exit code 匹配）
   - 0.85-0.94: 比较确定（常见资源问题）
   - 0.70-0.84: 中等确定（需要进一步验证）
   - <0.70: 不要返回

6. **estimated_cost**：
   - 增加内存: 约 $0.5-2.0/小时
   - 增加 CPU: 约 $0.3-1.5/小时
   - 如果不增加 AWS 资源，cost = 0.0

7. **只返回 JSON 数组，不要任何 markdown 标记或其他文字**

现在请开始分析：
"""

        return prompt

    def _format_few_shot_examples(self, historical_fixes: List[Dict]) -> str:
        """
        格式化历史修复案例为 Few-shot Examples

        从历史修复记录中提取成功案例，作为 LLM 的学习示例。

        Args:
            historical_fixes: 历史修复记录列表

        Returns:
            格式化的 Few-shot examples 文本
        """
        if not historical_fixes:
            return self._get_default_few_shot_examples()

        examples = []
        for idx, fix in enumerate(historical_fixes[:3], 1):  # 最多 3 个案例
            if fix.get('success'):
                example = f"""
**案例 {idx}: {fix.get('issue_type', 'Unknown')}**
```json
{{
  "issue_type": "{fix.get('issue_type', '')}",
  "severity": "high",
  "root_cause": "{fix.get('root_cause', '')}",
  "description": "{fix.get('description', '')}",
  "fixable": true,
  "fix_actions": {json.dumps(fix.get('fix_actions', []), indent=2, ensure_ascii=False)},
  "risk_level": "{fix.get('risk_level', 'low')}",
  "estimated_cost": {fix.get('estimated_cost', 0.0)},
  "confidence": {fix.get('confidence', 0.9)}
}}
```
"""
                examples.append(example)

        if examples:
            return "\n## Few-shot Examples（参考历史成功修复案例）\n" + "\n".join(examples)
        else:
            return self._get_default_few_shot_examples()

    def _get_default_few_shot_examples(self) -> str:
        """
        获取默认的 Few-shot Examples（当没有历史案例时）

        Returns:
            默认示例文本
        """
        return """
## Few-shot Examples（参考案例）

**案例 1: CPU 资源不足**
```json
{
  "issue_type": "cpu_shortage",
  "severity": "high",
  "root_cause": "任务需要 12 个 CPU，但系统只有 8 个可用",
  "description": "错误日志显示 'Process requirement exceeds available CPUs -- req: 12; avail: 8'，需要调整 max_cpus 参数",
  "fixable": true,
  "fix_actions": [
    {
      "action": "update_parameter",
      "parameter_name": "max_cpus",
      "old_value": "16",
      "new_value": "8",
      "reason": "将 max_cpus 限制设为实际可用 CPU 数，避免任务请求超出系统容量"
    }
  ],
  "risk_level": "low",
  "estimated_cost": 0.0,
  "confidence": 0.98
}
```

**案例 2: GTF 格式错误**
```json
{
  "issue_type": "gtf_format_error",
  "severity": "high",
  "root_cause": "GTF 文件缺少工具所需的必需属性字段（如 exon_number）",
  "description": "iCount 工具报告 '[KeyError] exon_number'，说明 GTF 文件格式不完整，缺少关键的 exon 编号属性",
  "fixable": false,
  "user_action_required": true,
  "recommended_action": "使用 GENCODE 或 Ensembl 的标准 GTF 文件（https://www.gencodegenes.org/），或使用 AGAT 工具修复现有文件: agat_convert_sp_gxf2gxf.pl --gff input.gtf -o fixed.gtf",
  "risk_level": "low",
  "estimated_cost": 0.0,
  "confidence": 0.98
}
```

**案例 3: 缺少必需参数**
```json
{
  "issue_type": "missing_parameter",
  "severity": "high",
  "root_cause": "Pipeline 要求 source 参数指定数据来源，但未提供",
  "description": "参数验证失败，提示 'source parameter is required'",
  "fixable": true,
  "fix_actions": [
    {
      "action": "add_parameter",
      "parameter_name": "source",
      "new_value": "fastq",
      "reason": "明确指定数据源类型为 fastq 格式"
    }
  ],
  "risk_level": "low",
  "estimated_cost": 0.0,
  "confidence": 0.98
}
```
"""

    def _parse_llm_response(self, response_text: str) -> List[Dict[str, Any]]:
        """
        解析 LLM 返回的 JSON 响应

        Args:
            response_text: LLM 响应文本

        Returns:
            解析后的 issues 列表
        """
        try:
            # 提取 JSON 数组（可能被 markdown 包围）
            json_match = re.search(r'\[.*\]', response_text, re.DOTALL)
            if not json_match:
                log.warning("⚠️  No JSON array found in LLM response")
                log.debug(f"Response text: {response_text[:500]}")
                return []

            issues = json.loads(json_match.group(0))

            if not isinstance(issues, list):
                log.warning("⚠️  LLM response is not a list")
                return []

            log.info(f"✅ Parsed {len(issues)} issues from LLM response")

            return issues

        except json.JSONDecodeError as e:
            log.error(f"❌ Failed to parse LLM JSON response: {e}")
            log.debug(f"Response text: {response_text[:500]}")
            return []

    def _validate_and_enrich_issues(
        self,
        issues: List[Dict[str, Any]],
        analysis_context: Dict[str, Any]
    ) -> List[Dict[str, Any]]:
        """
        验证和增强 LLM 返回的 issues

        验证内容：
        1. 必需字段检查
        2. issue_type 不能太泛泛
        3. fixable=true 必须有 fix_actions
        4. fixable=false 必须有 recommended_action
        5. confidence >= 0.70

        增强内容：
        1. 添加原始错误日志片段
        2. 添加失败任务信息
        3. 标准化字段格式

        Args:
            issues: LLM 返回的原始 issues
            analysis_context: 深度分析上下文

        Returns:
            验证和增强后的 issues
        """
        # 定义泛泛的 issue_type（需要拒绝）
        generic_types = {
            'nextflow_error', 'nextflow_warning', 'workflow_failure',
            'workflow_error', 'error', 'failure', 'unknown_error',
            'generic_error', 'task_failure', 'process_error'
        }

        validated_issues = []

        for idx, issue in enumerate(issues, 1):
            if not isinstance(issue, dict):
                log.warning(f"⚠️  Issue {idx}: Not a dict, skipping")
                continue

            # 验证必需字段
            required_fields = ['issue_type', 'severity', 'root_cause', 'description']
            missing_fields = [f for f in required_fields if not issue.get(f)]
            if missing_fields:
                log.warning(f"⚠️  Issue {idx}: Missing fields {missing_fields}, skipping")
                continue

            # 检查泛泛的 issue_type
            issue_type = issue.get('issue_type', '').lower()
            if issue_type in generic_types:
                log.warning(f"⚠️  Issue {idx}: Rejected generic issue_type '{issue_type}'")
                continue

            # 验证 confidence
            confidence = issue.get('confidence', 0.5)
            if not isinstance(confidence, (int, float)) or confidence < 0.70:
                log.warning(f"⚠️  Issue {idx}: Confidence too low ({confidence:.2f}), skipping")
                continue

            # 验证 fixable=true 的 issue
            is_fixable = issue.get('fixable', False)
            if is_fixable:
                fix_actions = issue.get('fix_actions', [])
                if not fix_actions or not isinstance(fix_actions, list):
                    log.warning(f"⚠️  Issue {idx}: fixable=true but no fix_actions, skipping")
                    continue

                # 验证每个 fix_action
                valid_actions = True
                for action_idx, action in enumerate(fix_actions):
                    if not isinstance(action, dict):
                        log.warning(f"⚠️  Issue {idx}, action {action_idx}: Not a dict")
                        valid_actions = False
                        break
                    if not action.get('parameter_name') or 'new_value' not in action:
                        log.warning(f"⚠️  Issue {idx}, action {action_idx}: Missing parameter_name or new_value")
                        valid_actions = False
                        break

                if not valid_actions:
                    continue

            # 验证 fixable=false 的 issue
            if not is_fixable:
                if not issue.get('user_action_required'):
                    log.warning(f"⚠️  Issue {idx}: fixable=false but user_action_required not set")
                    issue['user_action_required'] = True  # 自动修正

                if not issue.get('recommended_action'):
                    log.warning(f"⚠️  Issue {idx}: fixable=false but no recommended_action")
                    continue

            # 增强 issue：添加原始错误日志片段
            issue['error_logs_snippet'] = self._extract_relevant_logs(
                analysis_context.get('nextflow_logs', {}),
                issue_type
            )

            # 增强 issue：添加失败任务信息
            issue['affected_tasks'] = self._extract_affected_tasks(
                analysis_context.get('failed_tasks', []),
                issue_type
            )

            # 标准化字段
            issue['llm_generated'] = True
            issue['analyzer_version'] = 'universal_v1.0'
            issue['timestamp'] = datetime.now().isoformat()

            validated_issues.append(issue)
            log.info(f"✅ Issue {idx}: {issue_type} validated (confidence: {confidence:.2f})")

        return validated_issues

    def _extract_relevant_logs(self, nextflow_logs: Dict, issue_type: str) -> str:
        """
        提取与 issue 相关的日志片段

        Args:
            nextflow_logs: Nextflow 日志数据
            issue_type: 问题类型

        Returns:
            相关日志片段（最多 500 字符）
        """
        error_log = nextflow_logs.get('error_summary', '')
        if not error_log:
            return ""

        # 根据 issue_type 提取相关关键词
        keywords = self._get_keywords_for_issue_type(issue_type)

        # 查找包含关键词的行
        lines = error_log.split('\n')
        relevant_lines = []
        for line in lines:
            if any(keyword.lower() in line.lower() for keyword in keywords):
                relevant_lines.append(line)
                if len('\n'.join(relevant_lines)) > 500:
                    break

        if relevant_lines:
            snippet = '\n'.join(relevant_lines[:10])  # 最多 10 行
            return snippet[:500]  # 最多 500 字符
        else:
            return error_log[:500]  # 降级：返回前 500 字符

    def _get_keywords_for_issue_type(self, issue_type: str) -> List[str]:
        """
        获取 issue 类型的相关关键词

        Args:
            issue_type: 问题类型

        Returns:
            关键词列表
        """
        keyword_map = {
            'cpu_shortage': ['CPU', 'cpus', 'requirement exceeds'],
            'memory_oom_killer': ['memory', 'OOM', 'Killed', 'exit code 137'],
            'gtf_format_error': ['GTF', 'exon_number', 'KeyError', 'transcript'],
            'missing_parameter': ['parameter', 'required', 'missing'],
            'aws_permission_denied': ['AccessDenied', 'permission', 'denied'],
            'container_pull_error': ['docker', 'pull', 'manifest'],
        }

        return keyword_map.get(issue_type, ['ERROR', 'FAILED'])

    def _extract_affected_tasks(self, failed_tasks: List[Dict], issue_type: str) -> List[str]:
        """
        提取受影响的任务名称

        Args:
            failed_tasks: 失败任务列表
            issue_type: 问题类型

        Returns:
            任务名称列表（最多 5 个）
        """
        task_names = []
        for task in failed_tasks[:5]:  # 最多 5 个
            name = task.get('name', 'unknown')
            exit_code = task.get('exit_code', 'N/A')
            task_names.append(f"{name} (exit: {exit_code})")

        return task_names

    def generate_fix_plan(
        self,
        context: FixContext,
        issues: List[Dict[str, Any]]
    ) -> Optional[FixPlan]:
        """
        生成修复计划

        对于通用修复器，修复计划在 detect_issues 中已经由 LLM 生成。
        这里只需要将 issues 转换为 FixPlan 格式。

        Args:
            context: Fix context
            issues: 检测到的问题列表

        Returns:
            修复计划（如果有可修复的问题）
        """
        # 过滤出可修复的问题
        fixable_issues = [i for i in issues if i.get('fixable')]

        if not fixable_issues:
            log.info("ℹ️  No fixable issues found")
            return None

        # 使用第一个可修复问题作为主要问题
        primary_issue = fixable_issues[0]

        # 转换 fix_actions
        fix_actions = []
        for issue in fixable_issues:
            for llm_action in issue.get('fix_actions', []):
                action = FixAction(
                    action=self._map_action_type(llm_action.get('action', 'update_parameter')),
                    params={
                        llm_action.get('parameter_name', ''): llm_action.get('new_value', '')
                    },
                    description=llm_action.get('reason', ''),
                    risk_level=issue.get('risk_level', 'low')
                )
                fix_actions.append(action)

        # 创建 FixPlan
        fix_plan = FixPlan(
            fixable=True,
            fix_type=self._map_fix_type(primary_issue['issue_type']),
            fix_actions=fix_actions,
            explanation=primary_issue.get('description', ''),
            confidence=primary_issue.get('confidence', 0.7),
            estimated_success_rate=primary_issue.get('confidence', 0.7),
            requires_user_confirmation=(primary_issue.get('risk_level', 'medium') != 'low')
        )

        log.info(f"✅ Generated fix plan with {len(fix_actions)} actions")

        return fix_plan

    def _map_action_type(self, action_str: str) -> ActionType:
        """
        映射 LLM 返回的 action 字符串到 ActionType enum

        Args:
            action_str: LLM 返回的 action 类型

        Returns:
            ActionType enum 值
        """
        action_map = {
            'update_parameter': ActionType.UPDATE_PARAM,
            'add_parameter': ActionType.UPDATE_PARAM,
            'increase_resource': ActionType.INCREASE_MEMORY,
            'reduce_resource': ActionType.UPDATE_PARAM,
            'retry': ActionType.RETRY_TASK,
        }

        return action_map.get(action_str, ActionType.UPDATE_PARAM)

    def _map_fix_type(self, issue_type: str) -> FixType:
        """
        映射 issue_type 到 FixType enum

        Args:
            issue_type: 问题类型

        Returns:
            FixType enum 值
        """
        # CPU/内存问题 → 资源扩展
        if 'cpu' in issue_type.lower() or 'memory' in issue_type.lower():
            return FixType.RESOURCE_SCALING

        # 参数/配置问题 → 配置调整
        if 'parameter' in issue_type.lower() or 'config' in issue_type.lower():
            return FixType.CONFIG_ADJUSTMENT

        # 文件格式问题 → 数据转换（虽然通常不可修复）
        if 'format' in issue_type.lower() or 'gtf' in issue_type.lower():
            return FixType.DATA_CONVERSION

        # 默认：配置调整
        return FixType.CONFIG_ADJUSTMENT

    async def apply_fix(
        self,
        context: FixContext,
        fix_plan: FixPlan,
        sa_session: Any
    ) -> AutoFixResult:
        """
        应用修复计划

        对于通用修复器，修复应用由 orchestrator 或 executor 处理。
        这里返回一个成功的结果。

        Args:
            context: Fix context
            fix_plan: 生成的修复计划
            sa_session: 数据库 session

        Returns:
            修复结果
        """
        # 检查 apply_fix 是否需要异步调用
        # 如果 base class 的 apply_fix 是同步的，这里需要适配

        result = AutoFixResult(
            fix_id=None,
            fixer_name="LLMUniversalFixer",
            status=FixStatus.APPLIED,
            fix_type=fix_plan.fix_type.value if hasattr(fix_plan.fix_type, 'value') else str(fix_plan.fix_type),
            fix_actions=fix_plan.fix_actions,
            risk_level=self._parse_risk_level(fix_plan.risk_level if hasattr(fix_plan, 'risk_level') else 'medium'),
            success=True,
            estimated_cost=getattr(fix_plan, 'estimated_cost', 0.0),
            auto_approved=(not fix_plan.requires_user_confirmation),
        )

        log.info(f"✅ Fix applied: {fix_plan.fix_type}")

        return result

    def _parse_risk_level(self, risk_str: str) -> RiskLevel:
        """
        解析风险等级字符串

        Args:
            risk_str: 风险等级字符串

        Returns:
            RiskLevel enum 值
        """
        risk_map = {
            'low': RiskLevel.LOW,
            'medium': RiskLevel.MEDIUM,
            'high': RiskLevel.HIGH,
        }

        return risk_map.get(risk_str.lower(), RiskLevel.MEDIUM)
