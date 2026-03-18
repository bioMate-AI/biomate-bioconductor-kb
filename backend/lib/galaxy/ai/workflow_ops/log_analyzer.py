"""
Workflow日志智能分析器

实时分析Nextflow workflow日志，提取关键信息：
1. 执行进度
2. 错误和警告
3. 性能指标
4. LLM增强的洞察
"""

import logging
import re
import time
import json
from typing import Dict, List, Optional, Any, Tuple
from datetime import datetime

from .types import (
    LogAnalysisResult,
    Issue,
    ProgressInfo,
    WorkflowStatus,
    IssueSeverity,
    IssueType,
)
from .llm_client import UnifiedLLMClient

log = logging.getLogger(__name__)


class LogPatternMatcher:
    """
    日志模式匹配器

    使用正则表达式快速提取常见信息（不调用LLM）
    """

    # 进度模式
    PROGRESS_PATTERNS = [
        r'\[([0-9a-f]+)\]\s+process\s+>\s+(\w+)\s+\[(\d+)%\]',  # [abc123] process > taskName [50%]
        r'(\d+)\s+of\s+(\d+)',  # 5 of 10
    ]

    # 错误模式
    ERROR_PATTERNS = [
        # 参数错误
        (r'(?:invalid|unknown|missing)\s+parameter\s+[\'"]?(\w+)[\'"]?', IssueType.INVALID_PARAM),
        (r'(?:required|mandatory)\s+parameter\s+[\'"]?(\w+)[\'"]?\s+(?:not\s+)?(?:provided|found|set)', IssueType.MISSING_PARAM),

        # 数据格式错误
        (r'(?:unexpected|invalid|malformed)\s+(?:file\s+)?format', IssueType.DATA_FORMAT),
        (r'(?:cannot|failed to)\s+parse\s+(?:file|input)', IssueType.DATA_FORMAT),

        # 资源限制
        (r'out of memory|OOM|memory\s+exhausted', IssueType.RESOURCE_LIMIT),
        (r'(?:disk|storage)\s+(?:full|quota\s+exceeded)', IssueType.RESOURCE_LIMIT),

        # 网络错误
        (r'connection\s+(?:timeout|refused|reset)', IssueType.NETWORK_ERROR),
        (r'(?:download|fetch)\s+failed', IssueType.NETWORK_ERROR),

        # 依赖缺失
        (r'(?:command|executable)\s+not\s+found', IssueType.DEPENDENCY_MISSING),
        (r'(?:module|package)\s+[\'"]?(\w+)[\'"]?\s+not\s+found', IssueType.DEPENDENCY_MISSING),

        # 权限错误
        (r'permission\s+denied', IssueType.PERMISSION_ERROR),
        (r'access\s+denied', IssueType.PERMISSION_ERROR),
    ]

    # 警告模式
    WARNING_PATTERNS = [
        r'warning:',
        r'deprecated',
        r'will be removed',
    ]

    @classmethod
    def extract_progress(cls, logs: List[str]) -> Optional[ProgressInfo]:
        """从日志中提取进度信息（快速，不调用LLM）"""
        for line in reversed(logs[-50:]):  # 只看最近50行
            for pattern in cls.PROGRESS_PATTERNS:
                match = re.search(pattern, line, re.IGNORECASE)
                if match:
                    if len(match.groups()) >= 2:
                        try:
                            current = int(match.group(1))
                            total = int(match.group(2))
                            percentage = (current / total * 100) if total > 0 else 0
                            return ProgressInfo(
                                current=current,
                                total=total,
                                percentage=percentage
                            )
                        except (ValueError, IndexError):
                            continue
        return None

    @classmethod
    def quick_scan_errors(cls, logs: List[str]) -> List[Tuple[str, IssueType, str]]:
        """
        快速扫描错误（正则匹配，不调用LLM）

        Returns:
            List of (error_line, issue_type, matched_pattern)
        """
        errors = []
        for line in logs:
            line_lower = line.lower()

            # 跳过INFO级别
            if re.search(r'\b(info|debug)\b', line_lower):
                continue

            # 检查每个错误模式
            for pattern, issue_type in cls.ERROR_PATTERNS:
                if re.search(pattern, line, re.IGNORECASE):
                    errors.append((line, issue_type, pattern))
                    break  # 一行只匹配一个错误类型

        return errors

    @classmethod
    def quick_scan_warnings(cls, logs: List[str]) -> List[str]:
        """快速扫描警告"""
        warnings = []
        for line in logs:
            for pattern in cls.WARNING_PATTERNS:
                if re.search(pattern, line, re.IGNORECASE):
                    warnings.append(line)
                    break
        return warnings


class WorkflowLogAnalyzer:
    """
    智能日志分析器

    分级处理策略：
    1. 轻量级：正则匹配（INFO、进度）
    2. 中量级：小模型分析（WARNING）
    3. 重量级：大模型深度分析（ERROR、CRITICAL）
    """

    def __init__(
        self,
        llm_client: Optional[UnifiedLLMClient] = None,
        enable_llm: bool = True,
        llm_threshold: IssueSeverity = IssueSeverity.WARNING
    ):
        """
        Args:
            llm_client: LLM客户端（如果为None，自动创建）
            enable_llm: 是否启用LLM分析
            llm_threshold: 触发LLM分析的严重级别阈值
        """
        self.llm_client = llm_client or UnifiedLLMClient()
        self.enable_llm = enable_llm
        self.llm_threshold = llm_threshold

        # 历史状态（避免重复分析）
        self.analyzed_log_lines = 0
        self.last_analysis_time = None
        self.cumulative_issues: List[Issue] = []

    def analyze_logs_stream(
        self,
        logs: Dict[str, List[str]],
        context: Optional[Dict[str, Any]] = None
    ) -> LogAnalysisResult:
        """
        流式分析日志（增量分析，不重复处理）

        Args:
            logs: {
                'nextflow_log': [...],
                'stdout': [...],
                'stderr': [...],
                'batch_logs': {...}
            }
            context: {
                'invocation_id': int,
                'workflow_name': str,
                'total_steps': int,
                ...
            }

        Returns:
            LogAnalysisResult
        """
        start_time = time.time()
        context = context or {}

        # 合并所有日志
        all_logs = []
        all_logs.extend(logs.get('nextflow_log', []))
        all_logs.extend(logs.get('stdout', []))
        all_logs.extend(logs.get('stderr', []))

        # 只分析新增的日志
        new_logs = all_logs[self.analyzed_log_lines:]
        if not new_logs:
            # 没有新日志，返回上次的结果
            return self._get_cached_result()

        # 更新已分析行数
        self.analyzed_log_lines = len(all_logs)

        # === 第1阶段：快速模式匹配 ===
        progress = self._extract_progress_fast(all_logs, context)
        new_issues = self._scan_issues_fast(new_logs)

        # 更新累积的issues
        self.cumulative_issues.extend(new_issues)

        # === 第2阶段：LLM深度分析（按需） ===
        insights = ""
        llm_cost = 0.0

        if self.enable_llm and self._should_call_llm(new_issues):
            llm_result = self._analyze_with_llm(new_logs, new_issues, context)
            insights = llm_result.get('insights', '')
            llm_cost = llm_result.get('cost', 0.0)

            # LLM可能发现额外的issues
            if llm_result.get('additional_issues'):
                self.cumulative_issues.extend(llm_result['additional_issues'])

        # === 第3阶段：确定整体状态 ===
        status = self._determine_status(self.cumulative_issues, progress)

        # 构建结果
        analysis_duration = time.time() - start_time
        result = LogAnalysisResult(
            status=status,
            progress=progress,
            issues=self.cumulative_issues[-50:],  # 只返回最近50个issues
            insights=insights,
            analysis_duration=analysis_duration,
            llm_cost=llm_cost,
        )

        self.last_analysis_time = datetime.now()
        return result

    def _extract_progress_fast(
        self,
        logs: List[str],
        context: Dict[str, Any]
    ) -> ProgressInfo:
        """快速提取进度（正则匹配）"""
        # 先尝试正则匹配
        progress = LogPatternMatcher.extract_progress(logs)
        if progress:
            return progress

        # 如果没有匹配，使用context中的信息
        total_steps = context.get('total_steps', 0)
        if total_steps:
            # 简单估算：完成的步骤数 = cumulative completed issues
            completed = sum(1 for issue in self.cumulative_issues if 'completed' in issue.message.lower())
            return ProgressInfo(
                current=completed,
                total=total_steps,
                percentage=(completed / total_steps * 100) if total_steps > 0 else 0
            )

        # 默认值
        return ProgressInfo(current=0, total=0, percentage=0)

    def _scan_issues_fast(self, logs: List[str]) -> List[Issue]:
        """快速扫描issues（正则匹配）"""
        issues = []

        # 扫描错误
        errors = LogPatternMatcher.quick_scan_errors(logs)
        for error_line, issue_type, pattern in errors:
            issue = Issue(
                severity=IssueSeverity.ERROR,
                type=issue_type,
                message=error_line.strip(),
                suggestion="需要LLM深度分析以获取修复建议",
                auto_fixable=False,  # 需要LLM判断
                raw_logs=[error_line],
            )
            issues.append(issue)

        # 扫描警告
        warnings = LogPatternMatcher.quick_scan_warnings(logs)
        for warning_line in warnings:
            issue = Issue(
                severity=IssueSeverity.WARNING,
                type=IssueType.UNKNOWN,
                message=warning_line.strip(),
                suggestion="",
                auto_fixable=False,
                raw_logs=[warning_line],
            )
            issues.append(issue)

        return issues

    def _should_call_llm(self, new_issues: List[Issue]) -> bool:
        """判断是否需要调用LLM"""
        if not new_issues:
            return False

        # 检查是否有严重级别足够的issue
        severity_order = {
            IssueSeverity.INFO: 0,
            IssueSeverity.WARNING: 1,
            IssueSeverity.ERROR: 2,
            IssueSeverity.CRITICAL: 3,
        }

        max_severity = max(
            (severity_order[issue.severity] for issue in new_issues),
            default=0
        )

        return max_severity >= severity_order[self.llm_threshold]

    def _analyze_with_llm(
        self,
        logs: List[str],
        issues: List[Issue],
        context: Dict[str, Any]
    ) -> Dict[str, Any]:
        """
        使用LLM深度分析

        Returns:
            {
                'insights': '对日志的理解',
                'additional_issues': [...],
                'cost': 0.05
            }
        """
        # 准备prompt
        logs_sample = "\n".join(logs[-100:])  # 最近100行
        issues_json = json.dumps([
            {
                'severity': issue.severity.value,
                'type': issue.type.value,
                'message': issue.message[:200],  # 截断
            }
            for issue in issues
        ], indent=2)

        prompt = f"""你是一个Nextflow workflow日志分析专家。请分析以下日志：

**Context:**
- Workflow ID: {context.get('invocation_id', 'N/A')}
- Workflow Name: {context.get('workflow_name', 'N/A')}
- Total Steps: {context.get('total_steps', 'N/A')}

**Recent Logs (last 100 lines):**
```
{logs_sample}
```

**已检测到的Issues（正则匹配）：**
```json
{issues_json}
```

**请提供：**

1. **执行状态洞察**：用1-2句话总结当前workflow的执行状态和关键发现
2. **额外的Issues**（如果正则匹配漏掉了）：
   - 严重级别（info/warning/error/critical）
   - 问题类型（data_format/missing_param/resource_limit等）
   - 具体描述
   - 是否可自动修复
   - 修复建议

请以JSON格式返回：
```json
{{
  "insights": "执行状态洞察（自然语言）",
  "additional_issues": [
    {{
      "severity": "error",
      "type": "data_format",
      "message": "具体问题描述",
      "suggestion": "修复建议",
      "auto_fixable": true
    }}
  ]
}}
```
"""

        messages = [
            {"role": "user", "content": prompt}
        ]

        try:
            # 选择模型：目前只使用 Haiku（Sonnet 不可用）
            has_errors = any(issue.severity == IssueSeverity.ERROR for issue in issues)
            model = 'claude-3-haiku-20240307'  # 统一使用 Haiku

            result = self.llm_client.call(
                messages=messages,
                model=model,
                temperature=0.3,
                max_tokens=2000,
            )

            # 解析LLM返回
            content = result['content']
            usage_stats = result['usage_stats']

            # 调试：记录Claude返回的原始内容
            log.debug(f"Claude raw response (first 500 chars): {content[:500]}")

            # 提取JSON（处理LLM可能返回的markdown格式）
            json_match = re.search(r'```json\s*\n(.*?)\n```', content, re.DOTALL)
            if json_match:
                json_str = json_match.group(1)
            else:
                # 如果没有markdown格式，尝试提取{}或[]包裹的JSON
                json_match2 = re.search(r'(\{.*\}|\[.*\])', content, re.DOTALL)
                if json_match2:
                    json_str = json_match2.group(1)
                else:
                    json_str = content

            # 去除可能的空白字符
            json_str = json_str.strip()

            if not json_str:
                log.warning(f"Empty content from Claude, using default response")
                return {
                    'insights': 'LLM返回空内容',
                    'additional_issues': [],
                    'cost': usage_stats.cost,
                }

            parsed = json.loads(json_str)

            # 转换additional_issues为Issue对象
            additional_issues = []
            for raw_issue in parsed.get('additional_issues', []):
                try:
                    issue = Issue(
                        severity=IssueSeverity(raw_issue.get('severity', 'warning')),
                        type=IssueType(raw_issue.get('type', 'unknown')),
                        message=raw_issue.get('message', ''),
                        suggestion=raw_issue.get('suggestion', ''),
                        auto_fixable=raw_issue.get('auto_fixable', False),
                    )
                    additional_issues.append(issue)
                except (ValueError, KeyError) as e:
                    log.warning(f"Failed to parse LLM issue: {e}")

            return {
                'insights': parsed.get('insights', ''),
                'additional_issues': additional_issues,
                'cost': usage_stats.cost,
            }

        except Exception as e:
            log.error(f"LLM analysis failed: {e}")
            return {
                'insights': f"LLM分析失败: {e}",
                'additional_issues': [],
                'cost': 0.0,
            }

    def _determine_status(
        self,
        issues: List[Issue],
        progress: ProgressInfo
    ) -> WorkflowStatus:
        """根据issues和进度确定整体状态"""
        if not issues:
            if progress.percentage >= 100:
                return WorkflowStatus.COMPLETED
            else:
                return WorkflowStatus.RUNNING

        # 检查最高严重级别
        has_critical = any(issue.severity == IssueSeverity.CRITICAL for issue in issues)
        has_error = any(issue.severity == IssueSeverity.ERROR for issue in issues)
        has_warning = any(issue.severity == IssueSeverity.WARNING for issue in issues)

        if has_critical or has_error:
            return WorkflowStatus.ERROR
        elif has_warning:
            return WorkflowStatus.WARNING
        else:
            return WorkflowStatus.RUNNING

    def _get_cached_result(self) -> LogAnalysisResult:
        """获取缓存的结果（没有新日志时）"""
        return LogAnalysisResult(
            status=WorkflowStatus.RUNNING,
            progress=ProgressInfo(current=0, total=0, percentage=0),
            issues=[],
            insights="No new logs",
            analysis_duration=0.0,
            llm_cost=0.0,
        )

    def reset(self):
        """重置分析器状态（用于新的workflow）"""
        self.analyzed_log_lines = 0
        self.last_analysis_time = None
        self.cumulative_issues.clear()
