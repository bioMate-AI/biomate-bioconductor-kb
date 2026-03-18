"""
错误搜索 Agent

功能:
1. 从错误日志中提取特征
2. 搜索互联网查找解决方案
3. 分析搜索结果并提取知识
4. 生成修复建议

使用方法:
    agent = ErrorSearchAgent(llm_client=llm_client, enable_web_search=True)
    solution = await agent.search_and_solve(error_log, context)
"""

import logging
import re
import json
from typing import Dict, List, Optional, Any
from dataclasses import dataclass, asdict
from enum import Enum

log = logging.getLogger(__name__)


class ErrorType(Enum):
    """错误类型枚举"""
    OUT_OF_MEMORY = "out_of_memory"          # Exit code 137, OOM
    TIMEOUT = "timeout"                       # Exit code 143, SIGTERM
    FILE_NOT_FOUND = "file_not_found"        # FileNotFoundError
    PERMISSION_DENIED = "permission_denied"   # PermissionError
    NETWORK_ERROR = "network_error"           # Connection refused, timeout
    RESOURCE_LIMIT = "resource_limit"         # Disk full, ulimit
    SYNTAX_ERROR = "syntax_error"             # Parse error, invalid config
    PROCESS_FAILURE = "process_failure"       # Generic process failure
    UNKNOWN = "unknown"


@dataclass
class ErrorFeature:
    """错误特征"""
    error_type: ErrorType
    error_message: str
    process_name: Optional[str] = None
    pipeline: Optional[str] = None
    exit_code: Optional[int] = None
    resources: Optional[Dict[str, Any]] = None
    environment: Optional[str] = None
    nextflow_version: Optional[str] = None

    def to_dict(self) -> Dict:
        """转换为字典（处理 Enum）"""
        data = asdict(self)
        data['error_type'] = self.error_type.value
        return data


@dataclass
class SearchResult:
    """搜索结果"""
    title: str
    url: str
    snippet: str
    source: str  # "stackoverflow", "github", "documentation", etc.
    relevance_score: float = 0.0
    date: Optional[str] = None


@dataclass
class ErrorSolution:
    """错误解决方案"""
    root_cause: str
    fix_description: str
    config_changes: List[str]
    verification_steps: List[str]
    references: List[str]
    confidence: float  # 0.0-1.0

    def to_dict(self) -> Dict:
        """转换为字典"""
        return asdict(self)


class ErrorSearchAgent:
    """
    错误搜索 Agent

    使用 LLM + Web Search 分析和解决 workflow 错误
    """

    def __init__(
        self,
        llm_client,
        enable_web_search: bool = True,
        max_search_results: int = 5
    ):
        """
        初始化错误搜索 Agent

        Args:
            llm_client: UnifiedLLMClient 实例
            enable_web_search: 是否启用网络搜索
            max_search_results: 最大搜索结果数量
        """
        self.llm_client = llm_client
        self.enable_web_search = enable_web_search
        self.max_search_results = max_search_results
        self.logger = logging.getLogger(__name__)

    def extract_error_features(self, error_log: str, context: Dict[str, Any]) -> ErrorFeature:
        """
        从错误日志中提取特征

        Args:
            error_log: 错误日志内容
            context: 上下文信息 (pipeline, process, resources等)

        Returns:
            ErrorFeature 对象
        """
        # 1. 检测错误类型
        error_type = self._detect_error_type(error_log)

        # 2. 提取退出码
        exit_code = self._extract_exit_code(error_log)

        # 3. 提取进程名称
        process_name = context.get('process_name') or self._extract_process_name(error_log)

        # 4. 提取 pipeline 信息
        pipeline = context.get('pipeline') or self._extract_pipeline(error_log)

        return ErrorFeature(
            error_type=error_type,
            error_message=error_log,
            process_name=process_name,
            pipeline=pipeline,
            exit_code=exit_code,
            resources=context.get('resources'),
            environment=context.get('environment', 'AWS Batch'),
            nextflow_version=context.get('nextflow_version')
        )

    def _detect_error_type(self, error_log: str) -> ErrorType:
        """检测错误类型"""
        error_log_lower = error_log.lower()

        # Exit code 137 = OOM kill
        if 'exit status (137)' in error_log_lower or 'oom' in error_log_lower or 'out of memory' in error_log_lower:
            return ErrorType.OUT_OF_MEMORY

        # Exit code 143 = SIGTERM (timeout)
        if 'exit status (143)' in error_log_lower or 'timeout' in error_log_lower:
            return ErrorType.TIMEOUT

        # File not found
        if 'no such file' in error_log_lower or 'filenotfound' in error_log_lower:
            return ErrorType.FILE_NOT_FOUND

        # Permission denied
        if 'permission denied' in error_log_lower or 'access denied' in error_log_lower:
            return ErrorType.PERMISSION_DENIED

        # Network error
        if 'connection refused' in error_log_lower or 'network error' in error_log_lower:
            return ErrorType.NETWORK_ERROR

        # Resource limit
        if 'disk full' in error_log_lower or 'no space left' in error_log_lower:
            return ErrorType.RESOURCE_LIMIT

        # Syntax error
        if 'syntax error' in error_log_lower or 'parse error' in error_log_lower:
            return ErrorType.SYNTAX_ERROR

        # Generic process failure
        if 'error executing process' in error_log_lower or 'process terminated' in error_log_lower:
            return ErrorType.PROCESS_FAILURE

        return ErrorType.UNKNOWN

    def _extract_exit_code(self, error_log: str) -> Optional[int]:
        """提取退出码"""
        match = re.search(r'exit status \((\d+)\)', error_log)
        if match:
            return int(match.group(1))
        return None

    def _extract_process_name(self, error_log: str) -> Optional[str]:
        """提取进程名称"""
        # 匹配: Error executing process > 'PROCESS_NAME'
        match = re.search(r"process > '([^']+)'", error_log)
        if match:
            return match.group(1)
        return None

    def _extract_pipeline(self, error_log: str) -> Optional[str]:
        """提取 pipeline 名称"""
        # 匹配: NFCORE_RNASEQ, nf-core/rnaseq, etc.
        match = re.search(r'(nf-core/\w+|NFCORE_\w+)', error_log, re.IGNORECASE)
        if match:
            return match.group(1).lower()
        return None

    def search_error_solutions(
        self,
        error_feature: ErrorFeature
    ) -> List[SearchResult]:
        """
        搜索错误解决方案（使用 LLM 的搜索能力）

        Args:
            error_feature: 错误特征

        Returns:
            搜索结果列表
        """
        if not self.enable_web_search:
            self.logger.info("Web search is disabled")
            return []

        # 构建搜索查询
        queries = self._build_search_queries(error_feature)

        self.logger.info(f"Search queries: {queries[:2]}")

        # 使用 LLM 进行网络搜索（同步调用）
        # 注意: 这里使用 LLM 的内置搜索功能，而不是直接调用搜索 API
        search_results = self._search_with_llm(queries[:2], error_feature)

        return search_results

    def _build_search_queries(self, error_feature: ErrorFeature) -> List[str]:
        """构建搜索查询"""
        queries = []

        # 查询1: pipeline + process + error type
        if error_feature.pipeline and error_feature.process_name:
            queries.append(
                f"{error_feature.pipeline} {error_feature.process_name} "
                f"{error_feature.error_type.value.replace('_', ' ')}"
            )

        # 查询2: pipeline + exit code
        if error_feature.pipeline and error_feature.exit_code:
            queries.append(
                f"{error_feature.pipeline} exit code {error_feature.exit_code}"
            )

        # 查询3: Nextflow + error type + environment
        queries.append(
            f"Nextflow {error_feature.error_type.value.replace('_', ' ')} "
            f"{error_feature.environment or 'AWS Batch'}"
        )

        # 查询4: exit code only (fallback)
        if error_feature.exit_code:
            queries.append(f"Nextflow exit code {error_feature.exit_code}")

        return queries

    def _search_with_llm(
        self,
        queries: List[str],
        error_feature: ErrorFeature
    ) -> List[SearchResult]:
        """
        使用 LLM 进行网络搜索

        这里我们让 LLM 模拟搜索结果（基于其知识库）
        实际生产环境应该集成真实的搜索 API
        """
        search_prompt = f"""You are an expert in Nextflow/nf-core workflow debugging. Based on the error below, provide the top 3 most relevant resources you know about.

**Error Information:**
- Type: {error_feature.error_type.value}
- Exit Code: {error_feature.exit_code or 'N/A'}
- Process: {error_feature.process_name or 'Unknown'}
- Pipeline: {error_feature.pipeline or 'Unknown'}
- Error Message: {error_feature.error_message[:300]}...

**Search Queries:** {', '.join(queries)}

**Task:** Based on your knowledge of Nextflow, nf-core pipelines, AWS Batch, and common bioinformatics workflow errors, provide 3 REAL, SPECIFIC resources that would help solve this error.

**Important:**
- Use REAL URLs from your knowledge (GitHub issues, nf-core docs, Nextflow docs, Stack Overflow)
- Be specific about the solution in the snippet
- Higher relevance_score (0.0-1.0) for more relevant solutions

Return ONLY valid JSON (no markdown):
[
    {{
        "title": "Specific title from real resource",
        "url": "https://github.com/... or https://nf-co.re/... or real URL",
        "snippet": "Specific excerpt showing the solution",
        "source": "github|nf-core|nextflow-docs|stackoverflow",
        "relevance_score": 0.9
    }}
]
"""

        try:
            # 使用同步调用（LLM Client 是同步的）
            response_dict = self.llm_client.call(
                messages=[{"role": "user", "content": search_prompt}],
                max_tokens=1500,
                temperature=0.3  # 降低温度以获得更精确的结果
            )

            # 提取内容
            response_content = response_dict.get('content', '')

            # 解析 JSON 响应（尝试多种格式）
            json_match = re.search(r'```json\n(.*?)\n```', response_content, re.DOTALL)
            if json_match:
                results_data = json.loads(json_match.group(1))
            else:
                # 尝试提取数组
                json_match = re.search(r'\[\s*\{.*?\}\s*\]', response_content, re.DOTALL)
                if json_match:
                    results_data = json.loads(json_match.group(0))
                else:
                    # 尝试直接解析整个响应
                    results_data = json.loads(response_content)

            # 转换为 SearchResult 对象
            search_results = [
                SearchResult(
                    title=r.get('title', ''),
                    url=r.get('url', ''),
                    snippet=r.get('snippet', ''),
                    source=r.get('source', 'unknown'),
                    relevance_score=r.get('relevance_score', 0.5)
                )
                for r in results_data
            ]

            return search_results[:self.max_search_results]

        except Exception as e:
            self.logger.error(f"LLM search failed: {e}")
            # 返回空列表，回退到无搜索结果的分析
            return []

    def analyze_and_generate_solution(
        self,
        error_feature: ErrorFeature,
        search_results: List[SearchResult]
    ) -> ErrorSolution:
        """
        分析搜索结果并生成解决方案

        Args:
            error_feature: 错误特征
            search_results: 搜索结果

        Returns:
            ErrorSolution 对象
        """
        # 构建 LLM prompt
        prompt = self._build_analysis_prompt(error_feature, search_results)

        system_prompt = (
            "You are an expert in Nextflow/nf-core workflow debugging with deep knowledge of "
            "AWS Batch, container orchestration, and bioinformatics pipelines. "
            "Analyze the error and provide SPECIFIC, ACTIONABLE solutions with exact "
            "configuration changes that can be applied immediately."
        )

        # 调用 LLM 分析（同步调用）
        response_dict = self.llm_client.call(
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": prompt}
            ],
            max_tokens=2000,
            temperature=0.2  # 低温度确保精确性
        )

        # 解析 LLM 响应
        response_content = response_dict.get('content', '')
        solution = self._parse_solution_response(response_content)

        return solution

    def _build_analysis_prompt(
        self,
        error_feature: ErrorFeature,
        search_results: List[SearchResult]
    ) -> str:
        """构建分析 prompt"""
        prompt = f"""## Workflow Error Analysis

**Error Information:**
- Type: {error_feature.error_type.value}
- Exit Code: {error_feature.exit_code or 'N/A'}
- Process: {error_feature.process_name or 'Unknown'}
- Pipeline: {error_feature.pipeline or 'Unknown'}
- Environment: {error_feature.environment or 'Unknown'}

**Error Message:**
```
{error_feature.error_message[:1000]}
```

**Resources:**
{error_feature.resources or 'Not specified'}

"""

        if search_results:
            prompt += "**Search Results from Internet:**\n\n"
            for i, result in enumerate(search_results[:3], 1):
                prompt += f"""### Result {i}: {result.title}
Source: {result.source}
URL: {result.url}
Snippet: {result.snippet}

"""
        else:
            prompt += "**No search results available. Use your knowledge to analyze.**\n\n"

        prompt += """**Task:**
Based on the error information and search results above, provide a SPECIFIC, ACTIONABLE solution:

1. **Root Cause**: Why did this error occur? Be specific (e.g., "Container ran out of memory because the process requested 8GB but the data size was 45GB")

2. **Fix Description**: Exact steps to fix this (e.g., "Increase process memory from 8GB to 64GB in nextflow.config")

3. **Config Changes**: Provide EXACT configuration lines that can be copy-pasted:
   - For nextflow.config modifications
   - For AWS Batch job definitions
   - For container resource limits
   Example: `process { withName: 'FASTQC' { memory = '64.GB' } }`

4. **Verification Steps**: How to verify the fix worked
   - What logs to check
   - What output to expect
   - How to confirm the issue is resolved

5. **References**: URLs to relevant documentation or issues

Return ONLY valid JSON (no markdown):
{
    "root_cause": "Specific technical explanation with numbers/values",
    "fix_description": "Detailed step-by-step instructions",
    "config_changes": [
        "process.memory = '64.GB'",
        "process.cpus = 8",
        "Full config blocks that can be copy-pasted"
    ],
    "verification_steps": [
        "Check CloudWatch logs for memory usage",
        "Verify process completed without exit code 137",
        "Confirm output files were created"
    ],
    "references": ["https://nf-co.re/...", "https://github.com/..."],
    "confidence": 0.85
}
"""

        return prompt

    def _parse_solution_response(self, response: str) -> ErrorSolution:
        """解析 LLM 响应为 ErrorSolution"""
        try:
            # 提取 JSON 块
            json_match = re.search(r'```json\n(.*?)\n```', response, re.DOTALL)
            if json_match:
                solution_data = json.loads(json_match.group(1))
            else:
                # 尝试直接解析整个响应
                solution_data = json.loads(response)

            return ErrorSolution(
                root_cause=solution_data.get('root_cause', 'Unknown cause'),
                fix_description=solution_data.get('fix_description', 'No fix available'),
                config_changes=solution_data.get('config_changes', []),
                verification_steps=solution_data.get('verification_steps', []),
                references=solution_data.get('references', []),
                confidence=solution_data.get('confidence', 0.5)
            )

        except Exception as e:
            self.logger.error(f"Failed to parse solution response: {e}")
            # 返回默认解决方案
            return ErrorSolution(
                root_cause=f"Failed to analyze error: {str(e)}",
                fix_description="Unable to generate automatic fix. Please check the error logs manually.",
                config_changes=[],
                verification_steps=["Review error logs", "Check documentation"],
                references=[],
                confidence=0.1
            )

    def search_and_solve(
        self,
        error_log: str,
        context: Dict[str, Any]
    ) -> ErrorSolution:
        """
        完整的错误搜索和解决流程

        Args:
            error_log: 错误日志
            context: 上下文信息

        Returns:
            ErrorSolution
        """
        # 1. 提取错误特征
        error_feature = self.extract_error_features(error_log, context)
        self.logger.info(f"Detected error type: {error_feature.error_type.value}")

        # 2. 搜索解决方案（同步调用）
        search_results = self.search_error_solutions(error_feature)
        self.logger.info(f"Found {len(search_results)} search results")

        # 3. 分析并生成解决方案（同步调用）
        solution = self.analyze_and_generate_solution(error_feature, search_results)
        self.logger.info(f"Generated solution with confidence: {solution.confidence}")

        return solution
