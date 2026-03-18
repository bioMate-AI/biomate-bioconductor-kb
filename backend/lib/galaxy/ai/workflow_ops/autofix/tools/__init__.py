"""
AutoFix Tool System

类似Claude Code的工具系统，让AI可以主动执行操作：
- 读取文件
- 执行命令
- 搜索内容
- 分析数据

这让AI从"只能看"变成"可以做"
"""

from .base import BaseTool, ToolResult, ToolExecutionError
from .read_file import ReadFileTool
from .bash_command import BashCommandTool
from .grep_search import GrepSearchTool
from .file_operations import FileOperationsTool

__all__ = [
    'BaseTool',
    'ToolResult',
    'ToolExecutionError',
    'ReadFileTool',
    'BashCommandTool',
    'GrepSearchTool',
    'FileOperationsTool',
]
