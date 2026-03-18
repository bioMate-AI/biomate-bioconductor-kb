"""
ReadFile Tool - 读取文件内容
"""

import logging
from pathlib import Path
from typing import Dict, Any

from .base import BaseTool, ToolResult, ToolExecutionError

log = logging.getLogger(__name__)


class ReadFileTool(BaseTool):
    """
    读取文件工具

    让AI可以主动读取文件内容，类似Claude Code的Read tool
    """

    name = "read_file"
    description = """Read the contents of a file from the workflow directory.

Use this tool to inspect:
- Nextflow configuration files (nextflow.config)
- Error logs (nextflow.out, .command.log)
- Trace files (workflow-trace.txt)
- Any other file in the workflow directory

This is essential for understanding the exact configuration and errors."""

    def __init__(self, workflow_dir: Path):
        """
        Args:
            workflow_dir: Workflow根目录
        """
        self.workflow_dir = Path(workflow_dir)

    def get_parameters_schema(self) -> Dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "file_path": {
                    "type": "string",
                    "description": "Relative path to the file from workflow directory (e.g., 'nextflow.config', '.command.log')"
                },
                "max_lines": {
                    "type": "integer",
                    "description": "Maximum number of lines to read (default: 500)",
                    "default": 500
                }
            },
            "required": ["file_path"]
        }

    def execute(self, file_path: str, max_lines: int = 500) -> ToolResult:
        """读取文件内容"""
        try:
            # 安全性检查：防止路径遍历攻击
            target_path = (self.workflow_dir / file_path).resolve()
            if not str(target_path).startswith(str(self.workflow_dir.resolve())):
                raise ToolExecutionError(f"Access denied: path outside workflow directory")

            if not target_path.exists():
                return ToolResult(
                    success=False,
                    output="",
                    error=f"File not found: {file_path}"
                )

            # 读取文件
            with open(target_path, 'r', encoding='utf-8', errors='ignore') as f:
                lines = f.readlines()

            # 限制行数
            if len(lines) > max_lines:
                content = ''.join(lines[-max_lines:])
                output = f"[Showing last {max_lines} lines of {len(lines)} total lines]\n\n{content}"
            else:
                output = ''.join(lines)

            log.info(f"📄 Read file: {file_path} ({len(lines)} lines)")

            return ToolResult(
                success=True,
                output=output,
                metadata={
                    'total_lines': len(lines),
                    'lines_shown': min(len(lines), max_lines),
                    'file_path': file_path
                }
            )

        except Exception as e:
            log.error(f"Failed to read file {file_path}: {e}")
            return ToolResult(
                success=False,
                output="",
                error=str(e)
            )
