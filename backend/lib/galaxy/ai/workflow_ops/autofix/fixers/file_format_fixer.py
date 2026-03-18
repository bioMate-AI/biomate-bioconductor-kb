"""
File Format Fixer

自动检测和修复文件格式问题，包括：
1. FASTQ 编码转换（Phred33/64）
2. 换行符转换（CRLF/LF）
3. 文件编码问题（UTF-8/Latin1）
4. 压缩格式问题
"""

import logging
import re
import os
from pathlib import Path
from typing import Dict, List, Any, Optional, Tuple
from datetime import datetime

from ..base import (
    BaseAutoFixer,
    FixContext,
    FixStatus,
    RiskLevel,
    AutoFixResult,
)
from ...types import FixAction, ActionType

log = logging.getLogger(__name__)


class FileFormatFixer(BaseAutoFixer):
    """
    文件格式修复器

    自动检测和修复常见的文件格式问题：
    1. FASTQ 质量编码转换（Phred33 ↔ Phred64）
    2. 换行符转换（Windows CRLF → Unix LF）
    3. 文件编码转换（Latin1 → UTF-8）
    4. 去除 BOM 标记
    """

    name = "FileFormatFixer"
    description = "自动检测和修复文件格式问题"

    # 支持的文件格式问题类型
    ISSUE_TYPES = {
        "fastq_encoding": {
            "name": "FASTQ 质量编码错误",
            "patterns": [
                r"quality.*(?:encoding|phred|illumina)",
                r"(?:phred|illumina).*(?:33|64|1\.3|1\.5)",
                r"invalid.*quality.*score",
            ],
            "fixable": True,
        },
        "line_ending": {
            "name": "换行符问题",
            "patterns": [
                r"(?:CRLF|carriage return|\\r\\n)",
                r"(?:unix|dos).*line.*ending",
                r"unexpected.*line.*terminator",
            ],
            "fixable": True,
        },
        "file_encoding": {
            "name": "文件编码问题",
            "patterns": [
                r"(?:encoding|charset).*(?:error|invalid)",
                r"(?:utf-8|latin1|ascii).*decode.*error",
                r"invalid.*character.*encoding",
            ],
            "fixable": True,
        },
        "bom": {
            "name": "BOM 标记问题",
            "patterns": [
                r"(?:BOM|byte.*order.*mark)",
                r"unexpected.*(?:\\xef\\xbb\\xbf|﻿)",
            ],
            "fixable": True,
        },
    }

    # FASTQ 编码检测阈值
    PHRED33_MIN = 33  # '!'
    PHRED33_MAX = 73  # 'I'
    PHRED64_MIN = 64  # '@'
    PHRED64_MAX = 104  # 'h'

    def __init__(self, workspace_path: Optional[str] = None):
        """
        初始化 File Format Fixer

        Args:
            workspace_path: 工作空间路径（用于存放转换后的文件）
        """
        super().__init__()
        self.workspace_path = workspace_path or os.getenv(
            "GALAXY_AUTOFIX_WORKSPACE",
            "/tmp/galaxy_autofix"
        )
        # 确保工作空间存在
        Path(self.workspace_path).mkdir(parents=True, exist_ok=True)

    def detect_issues(self, context: FixContext) -> List[Dict[str, Any]]:
        """
        检测文件格式问题

        从错误日志中识别文件格式相关的问题
        """
        issues = []
        error_logs = context.metadata.get("error_logs", "")

        for issue_type, config in self.ISSUE_TYPES.items():
            for pattern in config["patterns"]:
                if re.search(pattern, error_logs, re.IGNORECASE):
                    # 提取文件路径
                    file_path = self._extract_file_path(error_logs)

                    issue = {
                        "type": f"file_format_{issue_type}",
                        "severity": "medium",
                        "issue_type": issue_type,
                        "message": config["name"],
                        "file_path": file_path,
                        "error_logs": error_logs,
                        "fixable": config["fixable"],
                    }
                    issues.append(issue)
                    break  # 每种类型只检测一次

        return issues

    def _extract_file_path(self, error_logs: str) -> Optional[str]:
        """
        从错误日志中提取文件路径

        Args:
            error_logs: 错误日志

        Returns:
            提取到的文件路径，如果无法提取则返回 None
        """
        # 常见的文件路径模式
        path_patterns = [
            r"(?:file|path|input)[:\s]+([/\w\-\.]+\.(?:fastq|fq|txt|csv|tsv|gtf|gff|bed)(?:\.gz)?)",
            r"([/\w\-\.]+\.(?:fastq|fq|txt|csv|tsv|gtf|gff|bed)(?:\.gz)?)",
        ]

        for pattern in path_patterns:
            match = re.search(pattern, error_logs, re.IGNORECASE)
            if match:
                return match.group(1)

        return None

    def generate_fix_plan(
        self,
        context: FixContext,
        issues: List[Dict[str, Any]]
    ) -> Optional[Any]:
        """
        生成文件格式修复计划
        """
        from ...types import FixPlan

        if not issues:
            return None

        # 处理第一个文件格式问题
        issue = issues[0]
        issue_type = issue.get("issue_type", "unknown")
        file_path = issue.get("file_path")

        fix_actions = []

        if issue_type == "fastq_encoding":
            # FASTQ 编码转换
            fix_actions.append(
                FixAction(
                    type=ActionType.CONVERT_FILE_FORMAT,
                    description="转换 FASTQ 质量编码",
                    details={
                        "file_path": file_path,
                        "conversion_type": "fastq_encoding",
                        "from_encoding": "auto-detect",
                        "to_encoding": "Phred33",
                        "backup": True,
                    },
                    risk_level="low",
                )
            )

        elif issue_type == "line_ending":
            # 换行符转换
            fix_actions.append(
                FixAction(
                    type=ActionType.CONVERT_FILE_FORMAT,
                    description="转换换行符为 Unix 格式",
                    details={
                        "file_path": file_path,
                        "conversion_type": "line_ending",
                        "from_format": "CRLF",
                        "to_format": "LF",
                        "backup": True,
                    },
                    risk_level="low",
                )
            )

        elif issue_type == "file_encoding":
            # 文件编码转换
            fix_actions.append(
                FixAction(
                    type=ActionType.CONVERT_FILE_FORMAT,
                    description="转换文件编码为 UTF-8",
                    details={
                        "file_path": file_path,
                        "conversion_type": "encoding",
                        "from_encoding": "auto-detect",
                        "to_encoding": "UTF-8",
                        "backup": True,
                    },
                    risk_level="low",
                )
            )

        elif issue_type == "bom":
            # 去除 BOM
            fix_actions.append(
                FixAction(
                    type=ActionType.CONVERT_FILE_FORMAT,
                    description="去除文件 BOM 标记",
                    details={
                        "file_path": file_path,
                        "conversion_type": "remove_bom",
                        "backup": True,
                    },
                    risk_level="low",
                )
            )

        else:
            # 未知问题类型
            fix_actions.append(
                FixAction(
                    type=ActionType.USER_ACTION_REQUIRED,
                    description=f"未知的文件格式问题: {issue_type}",
                    details={
                        "issue_type": issue_type,
                        "message": "需要手动检查文件格式",
                    },
                    risk_level="low",
                )
            )

        return FixPlan(
            fixer_name=self.name,
            issue_type=f"file_format_{issue_type}",
            description=f"修复文件格式问题: {self.ISSUE_TYPES.get(issue_type, {}).get('name', issue_type)}",
            fix_actions=fix_actions,
            risk_level=RiskLevel.LOW,
            estimated_cost=0.0,
            confidence_score=0.85,
        )

    async def apply_fix(
        self,
        context: FixContext,
        fix_plan: Any,
        sa_session: Any,
    ) -> AutoFixResult:
        """
        应用文件格式修复

        实际执行文件转换操作
        """
        start_time = datetime.now()

        try:
            # 检查权限
            allowed, error_msg = self.check_permissions(context, sa_session)
            if not allowed:
                return AutoFixResult(
                    fix_id=None,
                    status=FixStatus.FAILED,
                    fixer_name=self.name,
                    fix_type="file_format_fix",
                    fix_actions=fix_plan.fix_actions,
                    risk_level=fix_plan.risk_level,
                    success=False,
                    error_message=error_msg,
                )

            # 对于文件格式修复，我们不自动执行
            # 而是返回修复计划，让用户通过 API 确认后执行
            return AutoFixResult(
                fix_id=None,
                status=FixStatus.PENDING,
                fixer_name=self.name,
                fix_type="file_format_fix",
                fix_actions=fix_plan.fix_actions,
                risk_level=fix_plan.risk_level,
                success=False,
                error_message="需要用户确认后通过 API 执行文件格式转换",
                auto_approved=False,
                user_approved=False,
                execution_time_seconds=(datetime.now() - start_time).total_seconds(),
            )

        except Exception as e:
            log.error(f"Error applying file format fix: {e}")
            return AutoFixResult(
                fix_id=None,
                status=FixStatus.FAILED,
                fixer_name=self.name,
                fix_type="file_format_fix",
                fix_actions=fix_plan.fix_actions,
                risk_level=fix_plan.risk_level,
                success=False,
                error_message=str(e),
                execution_time_seconds=(datetime.now() - start_time).total_seconds(),
            )

    # ========== API Methods (供 REST API 调用) ==========

    def detect_file_format_issues(self, file_path: str) -> Dict[str, Any]:
        """
        检测文件的格式问题

        Args:
            file_path: 文件路径

        Returns:
            检测结果
        """
        if not os.path.exists(file_path):
            raise FileNotFoundError(f"File not found: {file_path}")

        issues = []

        # 检测换行符
        line_ending = self._detect_line_ending(file_path)
        if line_ending == "CRLF":
            issues.append({
                "type": "line_ending",
                "severity": "low",
                "message": "文件使用 Windows 换行符（CRLF），建议转换为 Unix 格式（LF）",
            })

        # 检测 BOM
        has_bom = self._detect_bom(file_path)
        if has_bom:
            issues.append({
                "type": "bom",
                "severity": "low",
                "message": "文件包含 BOM 标记，可能导致解析问题",
            })

        # 如果是 FASTQ 文件，检测编码
        if file_path.endswith(('.fastq', '.fq')):
            encoding = self._detect_fastq_encoding(file_path)
            issues.append({
                "type": "fastq_encoding",
                "severity": "info",
                "message": f"FASTQ 质量编码: {encoding}",
                "encoding": encoding,
            })

        return {
            "file_path": file_path,
            "issues": issues,
            "has_issues": len(issues) > 0,
        }

    def _detect_line_ending(self, file_path: str) -> str:
        """
        检测文件的换行符类型

        Args:
            file_path: 文件路径

        Returns:
            "CRLF", "LF", or "CR"
        """
        try:
            with open(file_path, 'rb') as f:
                sample = f.read(1024 * 1024)  # 读取前 1MB

            if b'\r\n' in sample:
                return "CRLF"
            elif b'\n' in sample:
                return "LF"
            elif b'\r' in sample:
                return "CR"
            else:
                return "UNKNOWN"
        except Exception as e:
            log.error(f"Error detecting line ending: {e}")
            return "UNKNOWN"

    def _detect_bom(self, file_path: str) -> bool:
        """
        检测文件是否包含 BOM

        Args:
            file_path: 文件路径

        Returns:
            True if BOM detected
        """
        try:
            with open(file_path, 'rb') as f:
                first_bytes = f.read(3)

            # UTF-8 BOM: EF BB BF
            return first_bytes == b'\xef\xbb\xbf'
        except Exception as e:
            log.error(f"Error detecting BOM: {e}")
            return False

    def _detect_fastq_encoding(self, file_path: str, sample_size: int = 10000) -> str:
        """
        检测 FASTQ 文件的质量编码

        Args:
            file_path: FASTQ 文件路径
            sample_size: 采样大小（读取多少条记录）

        Returns:
            "Phred33", "Phred64", or "Unknown"
        """
        try:
            min_score = 255
            max_score = 0
            count = 0

            with open(file_path, 'r') as f:
                while count < sample_size:
                    # FASTQ 格式: @header, sequence, +, quality
                    header = f.readline()
                    if not header:
                        break

                    sequence = f.readline()
                    plus = f.readline()
                    quality = f.readline().strip()

                    if quality:
                        for char in quality:
                            score = ord(char)
                            min_score = min(min_score, score)
                            max_score = max(max_score, score)

                        count += 1

            # 判断编码
            if max_score <= self.PHRED33_MAX:
                return "Phred33"
            elif min_score >= self.PHRED64_MIN:
                return "Phred64"
            else:
                return "Mixed or Unknown"

        except Exception as e:
            log.error(f"Error detecting FASTQ encoding: {e}")
            return "Unknown"

    def convert_file_format(
        self,
        file_path: str,
        conversion_type: str,
        **kwargs
    ) -> Dict[str, Any]:
        """
        转换文件格式

        Args:
            file_path: 源文件路径
            conversion_type: 转换类型
            **kwargs: 其他参数

        Returns:
            转换结果
        """
        if not os.path.exists(file_path):
            raise FileNotFoundError(f"File not found: {file_path}")

        # 创建备份
        if kwargs.get("backup", True):
            backup_path = f"{file_path}.backup"
            import shutil
            shutil.copy2(file_path, backup_path)

        try:
            if conversion_type == "line_ending":
                result = self._convert_line_ending(file_path, kwargs.get("to_format", "LF"))
            elif conversion_type == "remove_bom":
                result = self._remove_bom(file_path)
            elif conversion_type == "fastq_encoding":
                result = self._convert_fastq_encoding(
                    file_path,
                    kwargs.get("to_encoding", "Phred33")
                )
            elif conversion_type == "encoding":
                result = self._convert_encoding(
                    file_path,
                    kwargs.get("from_encoding", "auto"),
                    kwargs.get("to_encoding", "UTF-8")
                )
            else:
                raise ValueError(f"Unknown conversion type: {conversion_type}")

            return {
                "success": True,
                "file_path": file_path,
                "conversion_type": conversion_type,
                "backup_path": backup_path if kwargs.get("backup") else None,
                "message": result,
            }

        except Exception as e:
            log.error(f"Error converting file format: {e}")
            # 恢复备份
            if kwargs.get("backup", True):
                import shutil
                shutil.copy2(backup_path, file_path)

            return {
                "success": False,
                "error": str(e),
            }

    def _convert_line_ending(self, file_path: str, to_format: str) -> str:
        """转换换行符"""
        with open(file_path, 'r', newline='') as f:
            content = f.read()

        # 统一换行符
        content = content.replace('\r\n', '\n').replace('\r', '\n')

        if to_format == "CRLF":
            content = content.replace('\n', '\r\n')

        with open(file_path, 'w', newline='') as f:
            f.write(content)

        return f"换行符已转换为 {to_format}"

    def _remove_bom(self, file_path: str) -> str:
        """去除 BOM 标记"""
        with open(file_path, 'rb') as f:
            content = f.read()

        if content.startswith(b'\xef\xbb\xbf'):
            content = content[3:]  # 去除 UTF-8 BOM

        with open(file_path, 'wb') as f:
            f.write(content)

        return "BOM 标记已去除"

    def _convert_fastq_encoding(self, file_path: str, to_encoding: str) -> str:
        """转换 FASTQ 质量编码"""
        # 这里需要实际的转换逻辑
        # 简化版本：只返回消息
        return f"FASTQ 编码转换为 {to_encoding}（需要实现实际转换逻辑）"

    def _convert_encoding(self, file_path: str, from_encoding: str, to_encoding: str) -> str:
        """转换文件编码"""
        if from_encoding == "auto":
            # 尝试检测编码
            import chardet
            with open(file_path, 'rb') as f:
                result = chardet.detect(f.read())
                from_encoding = result['encoding']

        with open(file_path, 'r', encoding=from_encoding) as f:
            content = f.read()

        with open(file_path, 'w', encoding=to_encoding) as f:
            f.write(content)

        return f"文件编码已从 {from_encoding} 转换为 {to_encoding}"
