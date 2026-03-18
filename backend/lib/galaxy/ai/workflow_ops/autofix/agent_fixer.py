"""
Agent-based Auto Fixer

多轮迭代的智能修复器，类似Claude Code的工作方式：
1. 分析问题
2. 使用工具探索
3. 形成假设
4. 验证假设
5. 生成修复方案

这是达到Claude Code级别的关键！
"""

import logging
import json
from pathlib import Path
from typing import Dict, List, Any, Optional
from dataclasses import dataclass

from .base import BaseAutoFixer, FixContext, AutoFixResult
from .tools import (
    BaseTool, ToolResult,
    ReadFileTool, BashCommandTool, GrepSearchTool, FileOperationsTool
)
from ..llm_client import UnifiedLLMClient
from ..types import FixPlan, FixAction, ActionType

log = logging.getLogger(__name__)


@dataclass
class AgentStep:
    """Agent的一个思考和行动步骤"""
    step_num: int
    thought: str  # AI的思考过程
    tool_name: Optional[str] = None  # 使用的工具
    tool_input: Optional[Dict] = None  # 工具输入
    tool_output: Optional[str] = None  # 工具输出
    conclusion: Optional[str] = None  # 这一步的结论


class AgentAutoFixer(BaseAutoFixer):
    """
    基于Agent的自动修复器

    核心特性：
    - 多轮迭代：AI可以执行多次工具调用
    - 主动探索：AI决定需要什么信息
    - 类似Claude Code的工作流程
    """

    name = "AgentAutoFixer"
    description = "Multi-turn agent that explores and fixes issues like Claude Code"

    def __init__(
        self,
        llm_client: Optional[UnifiedLLMClient] = None,
        max_iterations: int = 10,
        max_tool_calls_per_iteration: int = 3
    ):
        """
        Args:
            llm_client: LLM客户端
            max_iterations: 最大迭代轮数
            max_tool_calls_per_iteration: 每轮最多调用工具次数
        """
        super().__init__()
        self.llm_client = llm_client or UnifiedLLMClient()
        self.max_iterations = max_iterations
        self.max_tool_calls_per_iteration = max_tool_calls_per_iteration
        self.conversation_history: List[Dict] = []
        self.agent_steps: List[AgentStep] = []

    def detect_issues(self, context: FixContext) -> List[Dict[str, Any]]:
        """
        使用Agent模式检测问题

        工作流程：
        1. 初始化工具
        2. 给AI任务描述
        3. AI使用工具探索
        4. AI总结发现的问题
        """
        from galaxy.model import WorkflowInvocation

        sa_session = context.metadata.get('sa_session')
        if not sa_session:
            log.error("No sa_session in context")
            return []

        invocation = sa_session.query(WorkflowInvocation).get(context.invocation_id)
        if not invocation:
            log.error(f"Invocation {context.invocation_id} not found")
            return []

        # 获取workflow目录
        config = context.metadata.get('app_config')
        if not config:
            return []

        jobs_dir = Path(config.jobs_directory)
        workflow_dir = jobs_dir / f"nextflow_workflows/workflow_{context.invocation_id}"

        if not workflow_dir.exists():
            log.error(f"Workflow directory not found: {workflow_dir}")
            return []

        # 初始化工具
        tools = self._initialize_tools(workflow_dir)

        # 开始Agent循环
        log.info(f"🤖 Starting agent-based diagnosis for workflow {context.invocation_id}")

        task_description = self._build_initial_task(invocation, workflow_dir)
        issues = self._agent_loop(task_description, tools)

        log.info(f"✅ Agent completed: found {len(issues)} issues in {len(self.agent_steps)} steps")

        return issues

    def _initialize_tools(self, workflow_dir: Path) -> List[BaseTool]:
        """初始化可用工具"""
        return [
            ReadFileTool(workflow_dir),
            BashCommandTool(workflow_dir),
            GrepSearchTool(workflow_dir),
            FileOperationsTool(workflow_dir),
        ]

    def _build_initial_task(self, invocation, workflow_dir: Path) -> str:
        """构建初始任务描述"""
        return f"""You are a Nextflow workflow debugging expert. Your task is to diagnose why this workflow failed and create a fix plan.

## Workflow Information
- **Workflow ID**: {invocation.id}
- **Name**: {invocation.workflow.name if invocation.workflow else 'unknown'}
- **State**: {invocation.state}
- **Directory**: {workflow_dir}

## Available Files (typical structure)
- `nextflow.config`: Nextflow configuration with parameters
- `nextflow.out`: Nextflow execution log
- `workflow-trace.txt`: Task execution trace (TSV format)
- `.command.log`: Individual task logs in work directories

## Your Task
1. **Explore** the workflow directory to understand what went wrong
2. **Use tools** to read files, search logs, inspect configuration
3. **Identify root causes** of failures
4. **Generate a fix plan** with specific parameter changes

## Important
- Be systematic: start with overview (trace file), then dig into specifics
- Look for patterns in failed tasks
- Check configuration for missing or incorrect parameters
- Focus on FIXABLE issues (parameter changes, not code bugs)

Start by listing the workflow directory to see what files are available.
"""

    def _agent_loop(self, task: str, tools: List[BaseTool]) -> List[Dict[str, Any]]:
        """
        Agent主循环

        这是核心：AI会多次调用工具，每次根据上一次的结果决定下一步
        """
        # 初始化对话
        self.conversation_history = [
            {"role": "user", "content": task}
        ]

        # 工具定义（Anthropic Tool Use格式）
        tool_definitions = [tool.to_anthropic_tool() for tool in tools]
        tool_map = {tool.name: tool for tool in tools}

        iteration = 0
        while iteration < self.max_iterations:
            iteration += 1
            log.info(f"🔄 Agent iteration {iteration}/{self.max_iterations}")

            # 调用LLM
            try:
                response = self.llm_client.call(
                    messages=self.conversation_history,
                    model="claude-sonnet-4-20250514",
                    temperature=0.2,
                    max_tokens=4000,
                    tools=tool_definitions  # 🔥 关键：传递工具定义
                )

                # 解析响应
                stop_reason = response.get('stop_reason')
                content = response.get('content', [])

                # 处理响应
                if stop_reason == 'tool_use':
                    # AI想使用工具
                    tool_uses = self._extract_tool_uses(content)
                    if not tool_uses:
                        log.warning("No tool uses found despite stop_reason=tool_use")
                        break

                    # 执行工具
                    tool_results = []
                    for tool_use in tool_uses[:self.max_tool_calls_per_iteration]:
                        result = self._execute_tool(tool_use, tool_map)
                        tool_results.append(result)

                        # 记录步骤
                        self.agent_steps.append(AgentStep(
                            step_num=len(self.agent_steps) + 1,
                            thought=self._extract_thinking(content),
                            tool_name=tool_use['name'],
                            tool_input=tool_use['input'],
                            tool_output=result.output if result.success else result.error
                        ))

                    # 将工具结果添加到对话历史
                    self.conversation_history.append({
                        "role": "assistant",
                        "content": content
                    })
                    self.conversation_history.append({
                        "role": "user",
                        "content": self._format_tool_results(tool_results)
                    })

                elif stop_reason == 'end_turn' or stop_reason == 'stop_sequence':
                    # AI完成了分析，提取最终结论
                    final_text = self._extract_text(content)
                    log.info(f"✅ Agent completed analysis:\n{final_text[:500]}...")

                    # 解析issues
                    issues = self._parse_final_issues(final_text)
                    return issues

                else:
                    log.warning(f"Unexpected stop_reason: {stop_reason}")
                    break

            except Exception as e:
                log.error(f"Agent iteration failed: {e}", exc_info=True)
                break

        # 如果达到最大迭代次数，尝试强制总结
        log.warning(f"Reached max iterations ({self.max_iterations}), forcing conclusion")
        return self._force_conclusion(tool_map)

    def _extract_tool_uses(self, content: List) -> List[Dict]:
        """从Claude响应中提取tool_use blocks"""
        tool_uses = []
        for block in content:
            if isinstance(block, dict) and block.get('type') == 'tool_use':
                tool_uses.append({
                    'id': block.get('id'),
                    'name': block.get('name'),
                    'input': block.get('input', {})
                })
        return tool_uses

    def _extract_thinking(self, content: List) -> str:
        """提取AI的思考过程"""
        for block in content:
            if isinstance(block, dict) and block.get('type') == 'text':
                return block.get('text', '')
        return ""

    def _extract_text(self, content: List) -> str:
        """提取文本内容"""
        texts = []
        for block in content:
            if isinstance(block, dict) and block.get('type') == 'text':
                texts.append(block.get('text', ''))
        return '\n'.join(texts)

    def _execute_tool(self, tool_use: Dict, tool_map: Dict[str, BaseTool]) -> ToolResult:
        """执行工具调用"""
        tool_name = tool_use['name']
        tool_input = tool_use['input']

        if tool_name not in tool_map:
            return ToolResult(
                success=False,
                output="",
                error=f"Unknown tool: {tool_name}"
            )

        tool = tool_map[tool_name]
        log.info(f"🔧 Executing tool: {tool_name} with {tool_input}")

        try:
            result = tool.execute(**tool_input)
            return result
        except Exception as e:
            log.error(f"Tool execution failed: {e}")
            return ToolResult(
                success=False,
                output="",
                error=str(e)
            )

    def _format_tool_results(self, results: List[ToolResult]) -> str:
        """格式化工具结果给LLM"""
        formatted = []
        for i, result in enumerate(results, 1):
            if result.success:
                formatted.append(f"Tool Result {i}:\n{result.output}")
            else:
                formatted.append(f"Tool Result {i} (ERROR):\n{result.error}")
        return '\n\n'.join(formatted)

    def _parse_final_issues(self, text: str) -> List[Dict[str, Any]]:
        """
        从AI的最终回复中解析issues

        期望格式：JSON数组或结构化文本
        """
        # 尝试提取JSON
        import re
        json_match = re.search(r'\[.*\]', text, re.DOTALL)
        if json_match:
            try:
                issues = json.loads(json_match.group(0))
                if isinstance(issues, list):
                    return self._validate_issues(issues)
            except json.JSONDecodeError:
                pass

        # 如果没有JSON，尝试从文本中提取
        log.warning("No JSON found in final response, parsing as text")
        return self._parse_text_issues(text)

    def _validate_issues(self, issues: List[Dict]) -> List[Dict]:
        """验证并规范化issues"""
        validated = []
        for issue in issues:
            if not isinstance(issue, dict):
                continue
            if not issue.get('fixable', False):
                continue

            validated.append({
                'type': issue.get('issue_type', 'unknown'),
                'severity': issue.get('severity', 'medium'),
                'root_cause': issue.get('root_cause', ''),
                'description': issue.get('description', ''),
                'fixable': True,
                'fix_actions': issue.get('fix_actions', []),
                'risk_level': issue.get('risk_level', 'medium'),
                'estimated_cost': issue.get('estimated_cost', 0.0),
                'confidence': issue.get('confidence', 0.5),
                'agent_generated': True,
                'agent_steps': len(self.agent_steps)
            })

        return validated

    def _parse_text_issues(self, text: str) -> List[Dict]:
        """从文本中解析issues（降级方案）"""
        # 简单的启发式解析
        issues = []

        # 查找常见错误模式
        if 'gtf' in text.lower() and 'transcript' in text.lower():
            issues.append({
                'type': 'gtf_format_error',
                'severity': 'high',
                'description': 'GTF file format issue detected from agent analysis',
                'fixable': True,
                'fix_actions': [{
                    'action': 'add_parameter',
                    'parameter_name': 'skip_filter_gtf',
                    'new_value': True
                }],
                'confidence': 0.7
            })

        return issues

    def _force_conclusion(self, tool_map: Dict[str, BaseTool]) -> List[Dict]:
        """强制AI总结（当达到最大迭代次数时）"""
        conclusion_prompt = """Based on your exploration so far, please provide your final diagnosis in JSON format:

[
  {
    "issue_type": "...",
    "severity": "high/medium/low",
    "root_cause": "...",
    "description": "...",
    "fixable": true/false,
    "fix_actions": [...],
    "confidence": 0.0-1.0
  }
]

Provide ONLY the JSON array, no additional text."""

        self.conversation_history.append({
            "role": "user",
            "content": conclusion_prompt
        })

        try:
            response = self.llm_client.call(
                messages=self.conversation_history,
                model="claude-sonnet-4-20250514",
                temperature=0.2,
                max_tokens=2000
            )

            content = response.get('content', [])
            final_text = self._extract_text(content)
            return self._parse_final_issues(final_text)

        except Exception as e:
            log.error(f"Force conclusion failed: {e}")
            return []
