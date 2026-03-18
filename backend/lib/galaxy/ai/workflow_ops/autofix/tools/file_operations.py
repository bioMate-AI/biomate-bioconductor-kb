"""
File Operations Tool - 文件系统操作
"""

import logging
from pathlib import Path
from typing import Dict, Any

from .base import BaseTool, ToolResult

log = logging.getLogger(__name__)


class FileOperationsTool(BaseTool):
    """
    文件操作工具

    列出文件、检查文件存在性等
    """

    name = "file_operations"
    description = """Perform file system operations in workflow directory.

Operations:
- list: List files and directories
- exists: Check if a file exists
- info: Get file metadata (size, modified time)

Use this to understand the workflow directory structure."""

    def __init__(self, workflow_dir: Path):
        self.workflow_dir = Path(workflow_dir)

    def get_parameters_schema(self) -> Dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "operation": {
                    "type": "string",
                    "enum": ["list", "exists", "info"],
                    "description": "Operation to perform"
                },
                "path": {
                    "type": "string",
                    "description": "Path relative to workflow directory (default: '.' for root)",
                    "default": "."
                }
            },
            "required": ["operation"]
        }

    def execute(self, operation: str, path: str = ".") -> ToolResult:
        """执行文件操作"""
        try:
            target_path = (self.workflow_dir / path).resolve()

            # 安全检查
            if not str(target_path).startswith(str(self.workflow_dir.resolve())):
                return ToolResult(
                    success=False,
                    output="",
                    error="Access denied: path outside workflow directory"
                )

            if operation == "list":
                return self._list_files(target_path)
            elif operation == "exists":
                return self._check_exists(target_path)
            elif operation == "info":
                return self._get_info(target_path)
            else:
                return ToolResult(
                    success=False,
                    output="",
                    error=f"Unknown operation: {operation}"
                )

        except Exception as e:
            log.error(f"File operation failed: {e}")
            return ToolResult(
                success=False,
                output="",
                error=str(e)
            )

    def _list_files(self, path: Path) -> ToolResult:
        """列出文件"""
        if not path.is_dir():
            return ToolResult(
                success=False,
                output="",
                error=f"Not a directory: {path.name}"
            )

        items = []
        for item in sorted(path.iterdir()):
            item_type = "DIR" if item.is_dir() else "FILE"
            size = item.stat().st_size if item.is_file() else 0
            items.append(f"{item_type:5} {size:>10} {item.name}")

        output = f"Contents of {path.relative_to(self.workflow_dir) or '.'}:\n"
        output += '\n'.join(items)

        return ToolResult(
            success=True,
            output=output,
            metadata={'item_count': len(items)}
        )

    def _check_exists(self, path: Path) -> ToolResult:
        """检查文件是否存在"""
        exists = path.exists()
        file_type = ""
        if exists:
            file_type = "directory" if path.is_dir() else "file"

        output = f"{'EXISTS' if exists else 'NOT FOUND'}: {path.relative_to(self.workflow_dir)}"
        if file_type:
            output += f" ({file_type})"

        return ToolResult(
            success=True,
            output=output,
            metadata={'exists': exists, 'type': file_type}
        )

    def _get_info(self, path: Path) -> ToolResult:
        """获取文件信息"""
        if not path.exists():
            return ToolResult(
                success=False,
                output="",
                error=f"File not found: {path.relative_to(self.workflow_dir)}"
            )

        stat = path.stat()
        file_type = "directory" if path.is_dir() else "file"

        output = f"""File: {path.relative_to(self.workflow_dir)}
Type: {file_type}
Size: {stat.st_size:,} bytes
Modified: {stat.st_mtime}"""

        return ToolResult(
            success=True,
            output=output,
            metadata={
                'size': stat.st_size,
                'modified': stat.st_mtime,
                'type': file_type
            }
        )
