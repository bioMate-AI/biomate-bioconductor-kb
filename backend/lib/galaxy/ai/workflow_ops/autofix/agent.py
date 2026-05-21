"""
AutoFix 2.0 - Deep Analysis Agent

多轮推理引擎，让 LLM 能够像人类专家一样：
1. 分析错误日志
2. 主动调查（下载文件、查看参数）
3. 深度分析
4. 生成修复方案

作者：AI Workflow AutoFix Team
日期：2026-01-30
"""

import logging
import json
import re
import time
from typing import Any, Callable, Dict, List, Optional
from pathlib import Path

from .toolkit import ToolKit
from .toolkit_v2 import EnhancedToolKit
from .tool_parameter_recommender import ToolParameterRecommender as _BaseToolParameterRecommender
# Wired version adds family_dedup priority (top-1 24%→100% on canonical eval)
# behind BIOMATE_FAMILY_PRIORITIZE=1 env flag. With flag unset, behavior is
# bit-identical to base class. Lazy/graceful import so any failure falls back.
try:
    from backend.lib.galaxy.ai.retrievers.wired_recommender import (
        WiredToolParameterRecommender as ToolParameterRecommender,
    )
except Exception:  # noqa: BLE001
    ToolParameterRecommender = _BaseToolParameterRecommender

log = logging.getLogger(__name__)


# ProgressCallback contract — see _emit() below.
# Each event is a dict with:
#   - phase: str — one of {'start', 'round_1_done', 'tool_call_start',
#       'tool_call_done', 'final_start', 'done', 'error'}
#   - round: int — 0 for start, 1+ thereafter
#   - friendly_message: str — 1-sentence user-facing English
#   - technical: dict — engineer-channel payload (tool name, tokens,
#       timings, partial results); never displayed to end users
#   - elapsed_s: float — seconds since agent.analyze() began
ProgressCallback = Callable[[Dict[str, Any]], None]


class DeepAnalysisAgent:
    """
    深度分析智能体

    核心能力：
    - 多轮推理（最多 5 轮）
    - 工具调用（下载文件、查看参数等）
    - 自主决策（决定需要什么信息）
    - 生成式修复（创建修复后的文件）
    - 智能参数推荐（基于 7000+ Galaxy 工具数据库）
    """

    def __init__(
        self,
        llm_client,
        toolkit,
        max_rounds: int = 5,
        db_path: Optional[str] = None,
        progress_callback: Optional[ProgressCallback] = None,
    ):
        self.llm_client = llm_client
        self.toolkit = toolkit  # Can be ToolKit or EnhancedToolKit
        self.max_rounds = max_rounds

        # 对话历史（用于多轮推理）
        self.conversation_history = []

        # 检测是否使用增强工具集
        self.is_enhanced = isinstance(toolkit, EnhancedToolKit)

        # 🆕 初始化参数推荐器
        self.parameter_recommender = None
        if db_path:
            try:
                self.parameter_recommender = ToolParameterRecommender(db_path=db_path)
                log.info(f"✅ ToolParameterRecommender initialized with database: {db_path}")
            except Exception as e:
                log.warning(f"⚠️ Failed to initialize ToolParameterRecommender: {e}")
                self.parameter_recommender = None

        # Optional progress callback. When set, agent emits structured events
        # at key points (start, round-1 done, each tool call, final). Caller
        # routes them to user-channel chat lines + engineer-channel logs.
        self._progress_callback = progress_callback
        self._analysis_start_t: float = 0.0

    def _emit(self, phase: str, round_n: int, friendly: str, technical: Optional[Dict[str, Any]] = None) -> None:
        """Emit a progress event to the optional callback. Never raises."""
        if self._progress_callback is None:
            return
        try:
            event = {
                "phase": phase,
                "round": round_n,
                "friendly_message": friendly,
                "technical": technical or {},
                "elapsed_s": round(time.time() - self._analysis_start_t, 2) if self._analysis_start_t else 0.0,
            }
            self._progress_callback(event)
        except Exception as exc:
            # Progress reporting must never break the analysis itself.
            log.debug("DeepAnalysisAgent: progress callback raised: %s", exc)

    def analyze(
        self,
        task_name: str,
        error_logs: str,
        exit_code: Optional[int],
        context: Dict[str, Any]
    ) -> Dict[str, Any]:
        """
        深度分析错误并生成修复方案

        Args:
            task_name: 任务名称
            error_logs: 错误日志
            exit_code: 退出码
            context: 上下文信息

        Returns:
            {
                'error_category': str,
                'root_cause': str,
                'analysis': str,
                'fixable': bool,
                'suggested_params': dict,
                'generated_files': list,  # 🆕 生成的文件列表
                'investigation_steps': list,  # 🆕 调查步骤
                'recommendation': str,
                'confidence': float,  # 🆕 置信度
            }
        """
        log.info(f"🤖 Starting deep analysis for task: {task_name}")
        self._analysis_start_t = time.time()

        # 清空对话历史
        self.conversation_history = []

        self._emit(
            phase="start",
            round_n=0,
            friendly="Looking into why your workflow failed…",
            technical={"task_name": task_name, "exit_code": exit_code, "log_size": len(error_logs or "")},
        )

        # Round 1: 初步分析 + 决定需要什么工具
        round_1_result = self._round_1_initial_analysis(
            task_name, error_logs, exit_code
        )

        if not round_1_result['needs_investigation']:
            # 简单错误，不需要工具调用，直接返回。
            # Prompt asks LLM for 'initial_assessment'; the fallback path wraps
            # it under 'analysis'. Accept both so either path produces a result.
            log.info(f"✅ Simple error detected, no investigation needed")
            simple = (
                round_1_result.get('analysis')
                or round_1_result.get('initial_assessment')
                or round_1_result
            )
            self._emit(
                phase="done",
                round_n=1,
                friendly=self._friendly_done_summary(simple),
                technical={"shortcircuit": True, "result_keys": list(simple.keys()) if isinstance(simple, dict) else None},
            )
            return simple

        self._emit(
            phase="round_1_done",
            round_n=1,
            friendly="Reading the logs and the failing task's output…",
            technical={
                "needs_investigation": True,
                "planned_tool_calls": len(round_1_result.get('tool_calls', [])),
                "initial_category": (round_1_result.get('initial_assessment') or {}).get('error_category'),
            },
        )

        # Round 2-N: 工具调用 + 深度分析
        investigation_results = self._investigate_with_tools(
            round_1_result['tool_calls']
        )

        # Final Round: 综合分析 + 生成修复方案
        self._emit(
            phase="final_start",
            round_n=self.max_rounds,
            friendly="Putting the pieces together to suggest a fix…",
            technical={"tools_run": len(investigation_results.get('tool_executions', []))},
        )

        final_result = self._final_analysis_and_fix(
            task_name,
            error_logs,
            investigation_results,
            context
        )

        log.info(f"✅ Deep analysis completed: fixable={final_result.get('fixable', False)}, confidence={final_result.get('confidence', 0):.2f}")

        self._emit(
            phase="done",
            round_n=self.max_rounds,
            friendly=self._friendly_done_summary(final_result),
            technical={
                "fixable": final_result.get('fixable'),
                "confidence": final_result.get('confidence'),
                "error_category": final_result.get('error_category'),
            },
        )

        return final_result

    @staticmethod
    def _friendly_done_summary(result: Dict[str, Any]) -> str:
        """Render a 1-sentence chat-friendly summary of a diagnosis result."""
        if not isinstance(result, dict):
            return "Done — diagnosis complete."
        fix = result.get('suggested_fix') or result.get('recommendation')
        cause = result.get('root_cause') or result.get('likely_cause')
        if fix:
            head = str(fix).split('. ')[0].strip().rstrip('.')
            return f"Suggested fix: {head}."
        if cause:
            head = str(cause).split('. ')[0].strip().rstrip('.')
            return f"Most likely cause: {head}."
        return "Done — diagnosis complete."

    @staticmethod
    def _friendly_tool_call(tool_name: str, args: Dict[str, Any], reason: str) -> str:
        """Render a chat-friendly description of what the agent is about to do."""
        # Map technical tool names to user-friendly verbs
        verbs = {
            "read_file": ("Reading", lambda a: a.get('file_path', 'a file')),
            "edit_file": ("Editing", lambda a: a.get('file_path', 'a file')),
            "write_file": ("Creating", lambda a: a.get('file_path', 'a file')),
            "grep": ("Searching for", lambda a: f"`{a.get('pattern', 'a pattern')}` in the workflow"),
            "glob": ("Looking for", lambda a: f"files matching `{a.get('pattern', 'a pattern')}`"),
            "bash": ("Running", lambda a: f"`{a.get('command', 'a command')[:50]}`"),
            "download_s3_file": ("Downloading", lambda a: f"{a.get('s3_path', 'a file from S3').rsplit('/', 1)[-1]}"),
            "inspect_trace": ("Reading", lambda _a: "the workflow trace"),
            "get_workflow_params": ("Checking", lambda _a: "the workflow parameters"),
        }
        if tool_name in verbs:
            verb, fmt = verbs[tool_name]
            try:
                target = fmt(args)
            except Exception:
                target = "details"
            return f"{verb} {target}…"
        # Fallback: pass the reason as-is if the LLM provided one in human-readable form
        if reason and len(reason) < 90 and reason.lower() not in ("no reason provided", ""):
            return reason.rstrip('.') + "…"
        return f"Running an investigation step ({tool_name})…"

    @staticmethod
    def _friendly_tool_done(tool_name: str, result: Dict[str, Any]) -> str:
        """1-sentence chat-friendly summary of what a tool returned."""
        if not result.get('success', False):
            err = result.get('error') or result.get('message') or 'no output'
            return f"That step couldn't complete ({str(err)[:80]})."
        if tool_name == "read_file":
            lines = result.get('lines') or result.get('line_count') or 0
            return f"Got the file ({lines} lines)." if lines else "Got the file contents."
        if tool_name == "grep":
            hits = result.get('matches') or result.get('count')
            if isinstance(hits, list):
                return f"Found {len(hits)} match(es)."
            if isinstance(hits, int):
                return f"Found {hits} match(es)."
            return "Search complete."
        if tool_name == "glob":
            files = result.get('files') or []
            return f"Found {len(files)} file(s) matching." if files else "No files matched."
        if tool_name == "bash":
            return "Command finished."
        if tool_name == "download_s3_file":
            return "Downloaded — checking contents."
        if tool_name == "inspect_trace":
            return "Read the trace."
        if tool_name == "get_workflow_params":
            return "Got the parameters."
        return "Step complete."

    def _round_1_initial_analysis(
        self,
        task_name: str,
        error_logs: str,
        exit_code: Optional[int]
    ) -> Dict[str, Any]:
        """
        第一轮：初步分析，决定是否需要工具调查
        """
        available_tools = self.toolkit.list_tools()
        tools_desc = '\n'.join([
            f"- {t['name']}: {t['description']}"
            for t in available_tools
        ])

        # 如果使用增强工具集，添加工具使用示例
        enhanced_tools_guide = ""
        if self.is_enhanced:
            enhanced_tools_guide = """

**💡 增强工具集使用指南**（新增）：

你现在拥有更强大的工具，可以像人类专家一样调试代码：

1. **read_file** - 读取本地文件（配置、脚本、日志）
   示例：查看 nextflow.config 的具体配置
   ```json
   {"tool": "read_file", "args": {"file_path": "nextflow.config"}}
   ```

2. **edit_file** - 修改文件（精确替换字符串）
   示例：修复 Python 脚本中的导入错误
   ```json
   {"tool": "edit_file", "args": {"file_path": "bin/process.py", "old_string": "import wrong_module", "new_string": "import correct_module"}}
   ```

3. **bash** - 运行命令（检查环境、验证文件）
   示例：检查 GTF 文件格式
   ```json
   {"tool": "bash", "args": {"command": "head -20 reference.gtf"}}
   ```

4. **glob** - 查找文件（使用模式匹配）
   示例：找到所有 Python 脚本
   ```json
   {"tool": "glob", "args": {"pattern": "**/*.py"}}
   ```

5. **grep** - 搜索文件内容（使用正则表达式）
   示例：查找包含 "exon_number" 的代码
   ```json
   {"tool": "grep", "args": {"pattern": "exon_number", "file_pattern": "*.py"}}
   ```

6. **write_file** - 创建新文件
   示例：生成配置文件
   ```json
   {"tool": "write_file", "args": {"file_path": "config_fixed.txt", "content": "key=value"}}
   ```

**何时使用新工具**：
- 错误提到具体的配置文件 → 用 read_file 查看
- 错误在脚本中（Python、R、Shell）→ 用 edit_file 修复
- 需要验证文件是否存在 → 用 bash 或 glob
- 需要查找代码位置 → 用 grep
"""

        prompt = f"""你是一个 Nextflow workflow 错误诊断专家。你的任务是分析错误并决定是否需要更多信息。

**任务信息**：
- 任务名称：{task_name}
- 退出码：{exit_code if exit_code else 'N/A'}

**错误日志**（前2000字符）：
```
{error_logs[:2000]}
```

**可用工具**：
{tools_desc}
{enhanced_tools_guide}

请分析这个错误，并回答：

1. **这是一个简单错误还是需要深入调查？**
   - 如果错误信息已经很明确（如明确的内存不足、明确的参数错误），选择 "simple"
   - 如果需要查看文件内容、参数配置才能确定根因，选择 "needs_investigation"

2. **如果需要调查，你需要哪些工具？**

以 JSON 格式返回：

```json
{{
    "needs_investigation": true/false,
    "tool_calls": [
        {{
            "tool": "download_s3_file",
            "args": {{"s3_path": "s3://..."}},
            "reason": "需要查看 samplesheet 的实际内容以确定格式问题"
        }}
    ],
    "initial_assessment": {{
        "error_category": "DATA_FORMAT_ERROR",
        "likely_cause": "Samplesheet 格式可能不正确",
        "confidence": 0.7
    }}
}}
```

如果是简单错误，tool_calls 为空数组，并在 initial_assessment 中直接给出完整分析。

只返回 JSON，不要其他文字。"""

        # 调用 LLM
        response = self.llm_client.call(
            messages=[{'role': 'user', 'content': prompt}],
            provider='anthropic',
            temperature=0.1,
            max_tokens=1500
        )

        # 解析响应
        analysis = self._parse_llm_response(response)

        if not analysis:
            # 解析失败，回退到简单模式
            return {
                'needs_investigation': False,
                'analysis': {
                    'error_category': 'UNKNOWN',
                    'root_cause': 'Failed to parse initial analysis',
                    'fixable': False,
                }
            }

        # 保存到对话历史
        self.conversation_history.append({
            'round': 1,
            'type': 'initial_analysis',
            'result': analysis
        })

        return analysis

    def _investigate_with_tools(self, tool_calls: List[Dict]) -> Dict[str, Any]:
        """
        执行工具调用，收集调查结果
        """
        investigation_results = {
            'tool_executions': [],
            'findings': []
        }

        log.info(f"🔍 Executing {len(tool_calls)} tool calls")

        for i, tool_call in enumerate(tool_calls):
            tool_name = tool_call['tool']
            tool_args = tool_call.get('args', {})
            reason = tool_call.get('reason', 'No reason provided')

            log.info(f"  Tool {i+1}/{len(tool_calls)}: {tool_name}({tool_args}) - {reason}")

            self._emit(
                phase="tool_call_start",
                round_n=2 + i,
                friendly=self._friendly_tool_call(tool_name, tool_args, reason),
                technical={"tool": tool_name, "args": tool_args, "reason": reason, "index": i, "of": len(tool_calls)},
            )
            tool_start_t = time.time()

            # 执行工具
            result = self.toolkit.execute_tool(tool_name, **tool_args)

            self._emit(
                phase="tool_call_done",
                round_n=2 + i,
                friendly=self._friendly_tool_done(tool_name, result),
                technical={
                    "tool": tool_name,
                    "success": result.get('success', False),
                    "tool_elapsed_s": round(time.time() - tool_start_t, 2),
                    "result_size_b": len(str(result.get('preview') or result.get('output') or '')),
                },
            )

            investigation_results['tool_executions'].append({
                'tool': tool_name,
                'args': tool_args,
                'reason': reason,
                'result': result,
                'success': result.get('success', False)
            })

            # 如果成功，提取关键发现
            if result.get('success'):
                if tool_name == 'download_s3_file':
                    investigation_results['findings'].append({
                        'type': 'file_content',
                        'file': tool_args['s3_path'],
                        'preview': result.get('preview', ''),
                        'lines': result.get('lines', 0),
                        'size': result.get('size_bytes', 0),
                    })
                elif tool_name == 'get_workflow_params':
                    investigation_results['findings'].append({
                        'type': 'workflow_params',
                        'params': result.get('params', {}),
                    })

        # 保存到对话历史
        self.conversation_history.append({
            'round': 2,
            'type': 'investigation',
            'results': investigation_results
        })

        return investigation_results

    def _final_analysis_and_fix(
        self,
        task_name: str,
        error_logs: str,
        investigation_results: Dict[str, Any],
        context: Dict[str, Any]
    ) -> Dict[str, Any]:
        """
        最终分析：综合所有信息，生成修复方案

        🆕 新增：调用 ToolParameterRecommender 获取智能参数建议
        """
        # 构建完整的上下文
        investigation_summary = self._summarize_investigation(investigation_results)

        # 🆕 获取参数推荐（如果可用）
        parameter_recommendations = []
        parameter_recommendations_text = ""

        if self.parameter_recommender:
            try:
                # 提取工具名称和 workflow 参数
                tool_name = context.get('workflow_name', '')
                workflow_params = {}

                # 从调查结果中提取参数
                for finding in investigation_results.get('findings', []):
                    if finding.get('type') == 'workflow_params':
                        workflow_params = finding.get('params', {})
                        break

                log.info(f"🔍 Requesting parameter recommendations for tool: {tool_name}")
                parameter_recommendations = self.parameter_recommender.recommend_parameters(
                    tool_name=tool_name,
                    error_context=error_logs[:1000],  # First 1000 chars of error
                    workflow_params=workflow_params
                )

                if parameter_recommendations:
                    log.info(f"✅ Got {len(parameter_recommendations)} parameter recommendations from database")

                    # 格式化推荐为文本
                    recs_list = []
                    for rec in parameter_recommendations:
                        recs_list.append(
                            f"  - **{rec.parameter_name}**: `{rec.recommended_value}` "
                            f"(confidence: {rec.confidence:.0%})\n"
                            f"    Reason: {rec.reasoning}"
                        )

                    parameter_recommendations_text = f"""

**🔧 智能参数推荐**（基于 Galaxy Tools 数据库）：
{chr(10).join(recs_list)}

💡 这些推荐是基于 7000+ Galaxy 工具的历史使用数据和最佳实践。
"""
                else:
                    log.info(f"ℹ️ No parameter recommendations found for {tool_name}")

            except Exception as e:
                log.warning(f"⚠️ Failed to get parameter recommendations: {e}")
                parameter_recommendations = []

        prompt = f"""你是一个 Nextflow workflow 错误修复专家。基于错误日志和调查结果，给出精确的修复方案。

**任务名称**：{task_name}

**原始错误日志**：
```
{error_logs[:1500]}
```

**调查结果**：
{investigation_summary}
{parameter_recommendations_text}

现在，基于以上所有信息，提供一个**完整的、可执行的**修复方案。

💡 如果有智能参数推荐，请优先考虑使用这些推荐值，它们来自 7000+ Galaxy 工具的最佳实践。

⚠️ **重要规则**：
1. 如果调查结果中下载了 S3 文件，**必须使用调查结果中显示的实际 S3 路径**（形如 s3://bucket-name/path/to/file.csv）
2. **绝对不要猜测或使用示例路径**（如 s3://my-bucket/... 或 s3://nf-core-xxx/...）
3. 从 "✅ Downloaded s3://..." 这一行中精确提取完整的 S3 路径

如果错误涉及文件格式问题（如 samplesheet 格式错误）：
1. **生成修复后的文件内容**（完整内容，不是示例）
2. 提供上传后的参数配置

如果是参数配置问题：
1. 提供精确的参数值（不是占位符）

以 JSON 格式返回：

```json
{{
    "error_category": "DATA_FORMAT_ERROR",
    "root_cause": "Samplesheet 只有 2 列（sample, fastq），但需要 4 列（sample_name, group_name, input_name, fastq）",
    "analysis": "通过下载 samplesheet.csv 发现...",
    "fixable": true,
    "fix_strategy": "file_generation",  // 或 "parameter_adjustment"

    // 如果需要生成文件
    "generated_file": {{
        "original_s3_path": "从调查结果中提取的实际 S3 路径（必须是完整路径，不能是示例）",
        "new_content": "完整的修复后文件内容...",
        "explanation": "基于原文件的 2 个样本，添加了 group_name 和 input_name 列"
    }},

    // 修复参数
    "suggested_params": {{
        "input": "s3://.../samplesheet_autofix.csv"  // 或其他参数
    }},

    "recommendation": "已自动修复 samplesheet 格式。原有 2 个样本数据保留，添加了必需的列。",
    "confidence": 0.95,

    "investigation_steps": [
        "Downloaded samplesheet.csv from S3",
        "Detected 2 columns: sample, fastq",
        "Generated fixed version with 4 columns"
    ]
}}
```

只返回 JSON，不要其他文字。确保 generated_file.new_content 包含**完整的**文件内容，不是示例或省略。
确保 generated_file.original_s3_path 是从调查结果中提取的实际路径，不是猜测的路径。"""

        # 调用 LLM
        response = self.llm_client.call(
            messages=[{'role': 'user', 'content': prompt}],
            provider='anthropic',
            temperature=0.1,
            max_tokens=3000  # 更大的 token 限制，因为需要生成完整文件
        )

        # 解析响应
        fix_plan = self._parse_llm_response(response)

        if not fix_plan:
            return {
                'error_category': 'UNKNOWN',
                'root_cause': 'Failed to generate fix plan',
                'fixable': False,
                'confidence': 0.0,
            }

        # 🔑 关键步骤：如果生成了文件，上传到 S3
        if fix_plan.get('fix_strategy') == 'file_generation' and 'generated_file' in fix_plan:
            generated_file = fix_plan['generated_file']
            original_s3_path = generated_file.get('original_s3_path', '')

            # 🔒 验证：确保 S3 路径来自调查结果，而不是 LLM 猜测的
            valid_s3_path = self._validate_s3_path_from_investigation(
                original_s3_path,
                investigation_results
            )

            if not valid_s3_path:
                log.warning(f"⚠️ LLM 提供的 S3 路径可能不正确: {original_s3_path}")
                log.warning(f"   将尝试从调查结果中提取实际路径...")

                # 尝试从调查结果中提取
                actual_path = self._extract_s3_path_from_investigation(investigation_results)
                if actual_path:
                    log.info(f"✅ 找到实际 S3 路径: {actual_path}")
                    original_s3_path = actual_path
                else:
                    log.error(f"❌ 无法从调查结果中提取 S3 路径")
                    fix_plan['fixable'] = False
                    fix_plan['recommendation'] += f"\n\n⚠️ 错误：无法确定正确的 S3 路径"
                    return fix_plan

            log.info(f"📝 Uploading generated file to S3...")
            log.info(f"   Original path: {original_s3_path}")

            upload_result = self.toolkit.execute_tool(
                'upload_s3_file',
                content=generated_file['new_content'],
                original_s3_path=original_s3_path,
                suffix='_autofix'
            )

            if upload_result.get('success'):
                new_s3_path = upload_result['new_s3_path']
                log.info(f"✅ Generated file uploaded to: {new_s3_path}")

                # 更新参数中的路径
                fix_plan['suggested_params']['input'] = new_s3_path
                fix_plan['generated_files'] = [{
                    'original': generated_file['original_s3_path'],
                    'fixed': new_s3_path,
                    'size': upload_result['size_bytes'],
                }]
            else:
                log.error(f"❌ Failed to upload generated file: {upload_result.get('error')}")
                fix_plan['fixable'] = False
                fix_plan['recommendation'] += f"\n\n⚠️ 警告：文件上传失败 - {upload_result.get('error')}"

        # 🆕 添加参数推荐到 fix_plan
        if parameter_recommendations:
            fix_plan['parameter_recommendations'] = [
                {
                    'parameter_name': rec.parameter_name,
                    'recommended_value': rec.recommended_value,
                    'confidence': rec.confidence,
                    'reasoning': rec.reasoning,
                    'alternative_values': rec.alternative_values,
                }
                for rec in parameter_recommendations
            ]
            log.info(f"✅ Added {len(parameter_recommendations)} parameter recommendations to fix plan")

        # 保存到对话历史
        self.conversation_history.append({
            'round': 3,
            'type': 'final_analysis',
            'fix_plan': fix_plan,
            'parameter_recommendations': parameter_recommendations if parameter_recommendations else None
        })

        return fix_plan

    def _summarize_investigation(self, investigation_results: Dict[str, Any]) -> str:
        """将调查结果汇总为文本"""
        summary_parts = []

        for execution in investigation_results['tool_executions']:
            tool = execution['tool']
            success = execution['success']
            result = execution['result']

            if success:
                if tool == 'download_s3_file':
                    summary_parts.append(
                        f"✅ Downloaded {execution['args']['s3_path']}:\n"
                        f"   - Size: {result['size_bytes']} bytes\n"
                        f"   - Lines: {result['lines']}\n"
                        f"   - Preview:\n{result['preview']}"
                    )
                elif tool == 'get_workflow_params':
                    params = result.get('params', {})
                    # 🔑 修复：转换为可序列化的格式
                    try:
                        # 尝试直接序列化
                        params_str = json.dumps(params, indent=2)
                    except (TypeError, ValueError):
                        # 如果失败，转换为字符串字典
                        params_str = json.dumps({k: str(v) for k, v in params.items()}, indent=2)
                    summary_parts.append(
                        f"✅ Workflow parameters:\n"
                        f"   {params_str}"
                    )
                elif tool == 'inspect_trace':
                    failed = result.get('failed_count', 0)
                    summary_parts.append(
                        f"✅ Trace file inspection:\n"
                        f"   - Total tasks: {result.get('total_tasks', 0)}\n"
                        f"   - Failed tasks: {failed}"
                    )
                # 新工具集的结果摘要
                elif tool == 'read_file':
                    summary_parts.append(
                        f"✅ Read file {execution['args']['file_path']}:\n"
                        f"   - Lines: {result.get('lines', 0)}\n"
                        f"   - Content preview:\n{result.get('content', '')[:500]}"
                    )
                elif tool == 'edit_file':
                    summary_parts.append(
                        f"✅ Edited file {execution['args']['file_path']}:\n"
                        f"   - Replacements: {result.get('replacements', 0)}\n"
                        f"   - Backup: {result.get('backup_path', 'N/A')}"
                    )
                elif tool == 'bash':
                    summary_parts.append(
                        f"✅ Executed command: {execution['args']['command']}\n"
                        f"   - Exit code: {result.get('exit_code', 0)}\n"
                        f"   - Output:\n{result.get('stdout', '')[:500]}"
                    )
                elif tool == 'glob':
                    summary_parts.append(
                        f"✅ Found files matching '{execution['args']['pattern']}':\n"
                        f"   - Count: {result.get('count', 0)}\n"
                        f"   - Files: {', '.join(result.get('files', [])[:10])}"
                    )
                elif tool == 'grep':
                    summary_parts.append(
                        f"✅ Searched for pattern '{execution['args']['pattern']}':\n"
                        f"   - Matches: {result.get('count', 0)}\n"
                        f"   - Files: {', '.join([m['file'] for m in result.get('matches', [])][:5])}"
                    )
                elif tool == 'write_file':
                    summary_parts.append(
                        f"✅ Created file {execution['args']['file_path']}:\n"
                        f"   - Size: {result.get('size_bytes', 0)} bytes"
                    )
            else:
                summary_parts.append(
                    f"❌ {tool} failed: {result.get('error', 'Unknown error')}"
                )

        return '\n\n'.join(summary_parts) if summary_parts else "No investigation performed"

    def _validate_s3_path_from_investigation(
        self,
        s3_path: str,
        investigation_results: Dict[str, Any]
    ) -> bool:
        """
        验证 S3 路径是否来自调查结果

        Returns:
            True if the path is from investigation results, False otherwise
        """
        if not s3_path or not s3_path.startswith('s3://'):
            return False

        # 检查是否是常见的错误路径（LLM 猜测的）
        bad_patterns = [
            's3://my-bucket/',
            's3://nf-core-',
            's3://example-',
            's3://bucket/',
        ]

        for pattern in bad_patterns:
            if s3_path.startswith(pattern):
                log.warning(f"   检测到可疑的 S3 路径模式: {pattern}")
                return False

        # 检查路径是否在调查结果中
        for execution in investigation_results.get('tool_executions', []):
            if execution['tool'] == 'download_s3_file':
                downloaded_path = execution['args'].get('s3_path', '')
                if downloaded_path == s3_path:
                    log.info(f"   ✅ S3 路径已验证（来自调查结果）")
                    return True

        log.warning(f"   ⚠️ S3 路径未在调查结果中找到")
        return False

    def _extract_s3_path_from_investigation(
        self,
        investigation_results: Dict[str, Any]
    ) -> Optional[str]:
        """
        从调查结果中提取实际下载的 S3 路径

        Returns:
            The actual S3 path from investigation, or None if not found
        """
        for execution in investigation_results.get('tool_executions', []):
            if execution['tool'] == 'download_s3_file' and execution.get('success'):
                s3_path = execution['args'].get('s3_path', '')
                if s3_path.startswith('s3://'):
                    log.info(f"   从调查结果中提取到 S3 路径: {s3_path}")
                    return s3_path

        return None

    def _parse_llm_response(self, response: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """解析 LLM 的 JSON 响应"""
        try:
            # 提取 content
            content_blocks = response.get('content', [])
            text_parts = []

            for block in content_blocks:
                if isinstance(block, dict) and block.get('type') == 'text':
                    text_parts.append(block.get('text', ''))
                elif isinstance(block, str):
                    text_parts.append(block)

            content = '\n'.join(text_parts)

            # 提取 JSON
            json_match = re.search(r'```json\s*(.*?)\s*```', content, re.DOTALL)
            if json_match:
                json_str = json_match.group(1)
            else:
                # 尝试直接解析整个响应
                json_str = content

            return json.loads(json_str)

        except Exception as e:
            log.error(f"Failed to parse LLM response: {e}")
            log.debug(f"Response content: {response}")
            return None
