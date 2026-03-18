"""
Grep Search Tool - 搜索文件内容
"""

import logging
import re
from pathlib import Path
from typing import Dict, Any, List

from .base import BaseTool, ToolResult

log = logging.getLogger(__name__)


class GrepSearchTool(BaseTool):
    """
    Grep搜索工具

    在workflow目录中搜索内容
    """

    name = "grep_search"
    description = """Search for patterns in workflow files.

Use this to find:
- Error messages across all log files
- Parameter values in configuration
- Specific task names in trace files
- Any pattern in workflow directory

This is faster than reading multiple files one by one."""

    def __init__(self, workflow_dir: Path):
        self.workflow_dir = Path(workflow_dir)

    def get_parameters_schema(self) -> Dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "pattern": {
                    "type": "string",
                    "description": "Search pattern (supports regex)"
                },
                "file_pattern": {
                    "type": "string",
                    "description": "File pattern to search in (e.g., '*.log', '*.txt')",
                    "default": "*"
                },
                "max_results": {
                    "type": "integer",
                    "description": "Maximum number of matches to return",
                    "default": 50
                },
                "case_sensitive": {
                    "type": "boolean",
                    "description": "Case sensitive search",
                    "default": False
                }
            },
            "required": ["pattern"]
        }

    def execute(
        self,
        pattern: str,
        file_pattern: str = "*",
        max_results: int = 50,
        case_sensitive: bool = False
    ) -> ToolResult:
        """搜索文件内容"""
        try:
            # 编译正则表达式
            flags = 0 if case_sensitive else re.IGNORECASE
            regex = re.compile(pattern, flags)

            matches = []
            files_searched = 0

            # 搜索文件
            for file_path in self.workflow_dir.rglob(file_pattern):
                if not file_path.is_file():
                    continue

                # 跳过太大的文件（>10MB）
                if file_path.stat().st_size > 10 * 1024 * 1024:
                    continue

                files_searched += 1

                try:
                    with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                        for line_num, line in enumerate(f, 1):
                            if regex.search(line):
                                matches.append({
                                    'file': str(file_path.relative_to(self.workflow_dir)),
                                    'line': line_num,
                                    'content': line.strip()
                                })

                                if len(matches) >= max_results:
                                    break

                except Exception as e:
                    log.debug(f"Failed to search {file_path}: {e}")
                    continue

                if len(matches) >= max_results:
                    break

            # 格式化输出
            if matches:
                output_lines = [f"Found {len(matches)} matches in {files_searched} files:\n"]
                for match in matches:
                    output_lines.append(f"{match['file']}:{match['line']}: {match['content']}")
                output = '\n'.join(output_lines)
            else:
                output = f"No matches found for pattern '{pattern}' in {files_searched} files"

            log.info(f"🔍 Searched for '{pattern}': {len(matches)} matches in {files_searched} files")

            return ToolResult(
                success=True,
                output=output,
                metadata={
                    'matches_count': len(matches),
                    'files_searched': files_searched,
                    'pattern': pattern
                }
            )

        except Exception as e:
            log.error(f"Grep search failed: {e}")
            return ToolResult(
                success=False,
                output="",
                error=str(e)
            )
