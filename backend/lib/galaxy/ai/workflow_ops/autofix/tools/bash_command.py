"""
Bash Command Tool - 执行安全的命令
"""

import logging
import subprocess
from pathlib import Path
from typing import Dict, Any, List

from .base import BaseTool, ToolResult, ToolExecutionError

log = logging.getLogger(__name__)


class BashCommandTool(BaseTool):
    """
    执行Bash命令工具（受限）

    安全性考虑：
    - 只允许白名单命令
    - 只能在workflow目录内执行
    - 超时保护
    """

    name = "bash_command"
    description = """Execute a safe bash command to inspect workflow state.

Allowed commands:
- ls: List files in workflow directory
- grep: Search in files
- wc: Count lines/words
- head/tail: View file snippets
- cat: View small files
- find: Find files by name

Use this to explore the workflow directory structure and inspect files."""

    # 白名单命令（安全）
    ALLOWED_COMMANDS = {
        'ls', 'grep', 'wc', 'head', 'tail', 'cat', 'find', 'file', 'stat'
    }

    def __init__(self, workflow_dir: Path):
        self.workflow_dir = Path(workflow_dir)

    def get_parameters_schema(self) -> Dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "command": {
                    "type": "string",
                    "description": f"Bash command to execute (allowed: {', '.join(self.ALLOWED_COMMANDS)})"
                }
            },
            "required": ["command"]
        }

    def _is_safe_command(self, command: str) -> bool:
        """检查命令是否安全"""
        # 提取命令的第一个单词
        cmd_parts = command.strip().split()
        if not cmd_parts:
            return False

        base_cmd = cmd_parts[0]

        # 检查是否在白名单中
        if base_cmd not in self.ALLOWED_COMMANDS:
            return False

        # 禁止危险字符
        dangerous_chars = [';', '|', '&', '>', '<', '`', '$', '(', ')']
        if any(char in command for char in dangerous_chars):
            return False

        return True

    def execute(self, command: str) -> ToolResult:
        """执行命令"""
        try:
            # 安全检查
            if not self._is_safe_command(command):
                return ToolResult(
                    success=False,
                    output="",
                    error=f"Command not allowed. Only these commands are permitted: {', '.join(self.ALLOWED_COMMANDS)}"
                )

            log.info(f"🔧 Executing command: {command}")

            # 在workflow目录中执行
            result = subprocess.run(
                command,
                shell=True,
                cwd=self.workflow_dir,
                capture_output=True,
                text=True,
                timeout=10  # 10秒超时
            )

            output = result.stdout
            if result.stderr:
                output += f"\n[STDERR]\n{result.stderr}"

            return ToolResult(
                success=result.returncode == 0,
                output=output,
                metadata={
                    'return_code': result.returncode,
                    'command': command
                }
            )

        except subprocess.TimeoutExpired:
            return ToolResult(
                success=False,
                output="",
                error="Command timed out (10s limit)"
            )
        except Exception as e:
            log.error(f"Command execution failed: {e}")
            return ToolResult(
                success=False,
                output="",
                error=str(e)
            )
