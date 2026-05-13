"""
深度错误日志解析器
Deep Error Log Parser

用于解析 Nextflow 任务的详细错误信息，包括：
- .command.err (标准错误输出)
- .command.out (标准输出)
- .command.log (Nextflow 日志)
- .exitcode (退出码)
"""

import logging
import os
import re
from pathlib import Path
from typing import Dict, List, Optional, Tuple

log = logging.getLogger(__name__)


class TaskErrorDetails:
    """任务错误详情"""

    def __init__(self):
        self.task_name: str = ""
        self.exit_code: int = 0
        self.error_type: str = ""
        self.error_message: str = ""
        self.root_cause: str = ""
        self.stderr_lines: List[str] = []
        self.stdout_lines: List[str] = []
        self.recommendations: List[str] = []


class ErrorLogParser:
    """错误日志深度解析器"""

    # 错误模式匹配
    ERROR_PATTERNS = {
        'cpu_insufficient': {
            'pattern': r'exceeds available CPUs.*req: (\d+).*avail: (\d+)',
            'severity': 'high',
            'fixable': True
        },
        'memory_oom': {
            'pattern': r'(Out of memory|OOM killed|Cannot allocate memory)',
            'severity': 'high',
            'fixable': True
        },
        'file_not_found': {
            'pattern': r'(No such file or directory|FileNotFoundError): (.+)',
            'severity': 'medium',
            'fixable': True
        },
        'gtf_format_error': {
            'pattern': r'(GTF|transcript).*(error|invalid|missing|failed)',
            'severity': 'medium',
            'fixable': True
        },
        'star_index_error': {
            'pattern': r'STAR.*(index|genome).*(error|failed)',
            'severity': 'high',
            'fixable': True
        },
        'container_pull_error': {
            'pattern': r'(Failed to pull|unable to pull|manifest unknown)',
            'severity': 'high',
            'fixable': False
        },
        'permission_denied': {
            'pattern': r'Permission denied',
            'severity': 'high',
            'fixable': False
        }
    }

    @staticmethod
    def parse_task_error(work_dir: str, task_name: str = "") -> Optional[TaskErrorDetails]:
        """
        深度解析任务错误

        Args:
            work_dir: Nextflow 任务工作目录 (如 work/a1/b2c3d4...)
            task_name: 任务名称

        Returns:
            TaskErrorDetails 或 None
        """
        if not os.path.exists(work_dir):
            log.warning(f"Work directory not found: {work_dir}")
            return None

        details = TaskErrorDetails()
        details.task_name = task_name

        # 1. 读取退出码
        exit_code = ErrorLogParser._read_exit_code(work_dir)
        details.exit_code = exit_code

        if exit_code == 0:
            return None  # 成功的任务

        # 2. 读取 stderr
        stderr_path = os.path.join(work_dir, '.command.err')
        if os.path.exists(stderr_path):
            details.stderr_lines = ErrorLogParser._read_file_lines(stderr_path)

        # 3. 读取 stdout
        stdout_path = os.path.join(work_dir, '.command.out')
        if os.path.exists(stdout_path):
            details.stdout_lines = ErrorLogParser._read_file_lines(stdout_path)

        # 4. 分析错误类型和根本原因
        error_type, root_cause = ErrorLogParser._analyze_error_type(
            details.stderr_lines,
            details.stdout_lines,
            exit_code
        )
        details.error_type = error_type
        details.root_cause = root_cause

        # 5. 提取错误消息（最关键的几行）
        details.error_message = ErrorLogParser._extract_error_message(
            details.stderr_lines,
            details.stdout_lines,
            error_type
        )

        # 6. 生成修复建议
        details.recommendations = ErrorLogParser._generate_recommendations(
            error_type,
            root_cause
        )

        log.debug(f"Parsed error for {task_name}: type={error_type}, cause={root_cause[:50]}...")
        return details

    @staticmethod
    def _read_exit_code(work_dir: str) -> int:
        """读取任务退出码"""
        exit_code_path = os.path.join(work_dir, '.exitcode')
        if not os.path.exists(exit_code_path):
            return -1

        try:
            with open(exit_code_path, 'r') as f:
                return int(f.read().strip())
        except Exception as e:
            log.warning(f"Failed to read exit code: {e}")
            return -1

    @staticmethod
    def _read_file_lines(file_path: str, max_lines: int = 1000) -> List[str]:
        """读取文件行（最多 max_lines 行）"""
        try:
            with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                lines = f.readlines()
                # 如果文件太大，只读最后 max_lines 行
                if len(lines) > max_lines:
                    lines = lines[-max_lines:]
                return [line.rstrip() for line in lines]
        except Exception as e:
            log.warning(f"Failed to read file {file_path}: {e}")
            return []

    @staticmethod
    def _analyze_error_type(
        stderr_lines: List[str],
        stdout_lines: List[str],
        exit_code: int
    ) -> Tuple[str, str]:
        """
        分析错误类型和根本原因

        Returns:
            (error_type, root_cause)
        """
        all_lines = stderr_lines + stdout_lines
        combined_text = '\n'.join(all_lines)

        # 按优先级匹配错误模式
        for error_type, pattern_info in ErrorLogParser.ERROR_PATTERNS.items():
            pattern = pattern_info['pattern']
            match = re.search(pattern, combined_text, re.IGNORECASE | re.MULTILINE)

            if match:
                # 提取匹配的上下文作为根本原因
                match_start = max(0, match.start() - 200)
                match_end = min(len(combined_text), match.end() + 200)
                root_cause = combined_text[match_start:match_end].strip()

                log.info(f"  ✓ Detected error type: {error_type}")
                return error_type, root_cause

        # 未匹配到已知模式，返回通用错误
        # 尝试找到包含 "error" 关键字的行
        for line in reversed(stderr_lines):
            if re.search(r'error|failed|exception', line, re.IGNORECASE):
                return 'unknown_error', line

        return 'unknown_error', f'Exit code: {exit_code}'

    @staticmethod
    def _extract_error_message(
        stderr_lines: List[str],
        stdout_lines: List[str],
        error_type: str
    ) -> str:
        """
        提取最关键的错误消息（5-10 行）

        优先级：
        1. stderr 中包含关键字的行
        2. stdout 中的错误行
        3. 最后几行
        """
        error_lines = []

        # 优先从 stderr 提取
        for line in stderr_lines:
            if any(keyword in line.lower() for keyword in ['error', 'failed', 'exception', 'fatal']):
                error_lines.append(line)

        # 如果 stderr 没有，从 stdout 提取
        if not error_lines:
            for line in stdout_lines:
                if any(keyword in line.lower() for keyword in ['error', 'failed', 'exception']):
                    error_lines.append(line)

        # 如果还是没有，取 stderr 的最后 10 行
        if not error_lines:
            error_lines = stderr_lines[-10:] if stderr_lines else stdout_lines[-10:]

        # 限制长度
        error_lines = error_lines[:10]

        return '\n'.join(error_lines)

    @staticmethod
    def _generate_recommendations(error_type: str, root_cause: str) -> List[str]:
        """根据错误类型生成修复建议"""
        recommendations = []

        if error_type == 'cpu_insufficient':
            match = re.search(r'req: (\d+).*avail: (\d+)', root_cause)
            if match:
                req = match.group(1)
                avail = match.group(2)
                recommendations.append(f"设置 max_cpus: {avail} 限制 CPU 使用")

        elif error_type == 'memory_oom':
            recommendations.append("增加 max_memory 参数")
            recommendations.append("考虑使用 --star_index_max_memory 参数")

        elif error_type == 'file_not_found':
            recommendations.append("检查输入文件路径是否正确")
            recommendations.append("确保文件可访问（权限、路径）")

        elif error_type == 'gtf_format_error':
            recommendations.append("使用 --skip_filter_gtf 跳过 GTF 格式检查")
            recommendations.append("检查 GTF 文件格式是否符合标准")

        elif error_type == 'star_index_error':
            recommendations.append("增加 --star_index_max_memory 参数")
            recommendations.append("检查基因组文件是否完整")

        else:
            recommendations.append("检查任务日志获取详细错误信息")

        return recommendations


def parse_all_failed_tasks(trace_file: str, nextflow_work_dir: str) -> List[TaskErrorDetails]:
    """
    解析所有失败任务的详细错误

    Args:
        trace_file: workflow-trace.txt 路径
        nextflow_work_dir: Nextflow 工作目录根路径

    Returns:
        失败任务的错误详情列表
    """
    if not os.path.exists(trace_file):
        log.warning(f"Trace file not found: {trace_file}")
        return []

    failed_tasks = []

    try:
        with open(trace_file, 'r') as f:
            lines = f.readlines()

        if len(lines) < 2:
            return []

        # 解析 header
        header = lines[0].strip().split('\t')
        indices = {
            'task_id': header.index('task_id') if 'task_id' in header else None,
            'hash': header.index('hash') if 'hash' in header else None,
            'name': header.index('name') if 'name' in header else None,
            'status': header.index('status') if 'status' in header else None,
            'workdir': header.index('workdir') if 'workdir' in header else None,
        }

        # 解析失败任务
        for line in lines[1:]:
            fields = line.strip().split('\t')

            status_idx = indices['status']
            if status_idx is None or len(fields) <= status_idx:
                continue

            if fields[status_idx] == 'FAILED':
                task_name = fields[indices['name']] if indices['name'] and len(fields) > indices['name'] else "Unknown"
                work_dir = fields[indices['workdir']] if indices['workdir'] and len(fields) > indices['workdir'] else None

                if work_dir and os.path.exists(work_dir):
                    task_error = ErrorLogParser.parse_task_error(work_dir, task_name)
                    if task_error:
                        failed_tasks.append(task_error)

        log.info(f"Parsed {len(failed_tasks)} failed tasks from trace file")
        return failed_tasks

    except Exception as e:
        log.error(f"Failed to parse trace file: {e}")
        return []
