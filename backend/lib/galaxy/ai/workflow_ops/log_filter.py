"""
Cost-Optimized Log Filter

成本优化的日志过滤算法
平衡分析效果和 LLM Token 成本
"""

import re
import logging
from typing import List, Dict, Tuple, Optional
from dataclasses import dataclass
from enum import Enum

log = logging.getLogger(__name__)


class LogLevel(str, Enum):
    """日志级别"""
    ERROR = "ERROR"
    FATAL = "FATAL"
    WARN = "WARN"
    INFO = "INFO"
    DEBUG = "DEBUG"


@dataclass
class LogSegment:
    """日志片段"""
    level: LogLevel
    start_line: int
    end_line: int
    content: List[str]
    importance: float  # 0-1, 重要性评分

    def __len__(self):
        return len(self.content)


class CostOptimizedLogFilter:
    """
    成本优化的日志过滤器

    策略:
    1. 优先保留 ERROR/FATAL 及其上下文
    2. 保留重要的 WARN 信息
    3. 跳过重复的日志行
    4. 限制总 token 数量
    """

    # 关键词权重
    ERROR_KEYWORDS = {
        'ERROR': 1.0,
        'FATAL': 1.0,
        'Exception': 0.9,
        'Failed': 0.8,
        'Caused by': 0.8,
        'exit status': 0.9,
        'exit code': 0.9,
    }

    WARN_KEYWORDS = {
        'WARN': 0.6,
        'WARNING': 0.6,
        'deprecated': 0.3,
    }

    SKIP_PATTERNS = [
        r'^\s*$',  # 空行
        r'^\s*\[main\] DEBUG',  # DEBUG 日志
        r'^\s*\[.*\] INFO.*progress',  # 进度信息
    ]

    def __init__(
        self,
        max_tokens: int = 4000,
        context_lines: int = 10,
        avg_chars_per_token: int = 4
    ):
        """
        初始化过滤器

        Args:
            max_tokens: 最大 token 数 (控制 LLM 成本)
            context_lines: 错误上下文行数
            avg_chars_per_token: 平均每个 token 的字符数
        """
        self.max_tokens = max_tokens
        self.max_chars = max_tokens * avg_chars_per_token
        self.context_lines = context_lines

    def calculate_importance(self, line: str) -> float:
        """
        计算日志行的重要性评分

        Args:
            line: 日志行

        Returns:
            重要性评分 (0-1)
        """
        score = 0.0

        # 检查 ERROR 关键词
        for keyword, weight in self.ERROR_KEYWORDS.items():
            if keyword in line:
                score = max(score, weight)

        # 检查 WARN 关键词
        for keyword, weight in self.WARN_KEYWORDS.items():
            if keyword in line:
                score = max(score, weight)

        return score

    def should_skip(self, line: str) -> bool:
        """
        判断是否应该跳过该行

        Args:
            line: 日志行

        Returns:
            True 如果应该跳过
        """
        for pattern in self.SKIP_PATTERNS:
            if re.match(pattern, line):
                return True
        return False

    def extract_error_segments(
        self,
        log_lines: List[str]
    ) -> List[LogSegment]:
        """
        提取错误相关的日志片段

        Args:
            log_lines: 完整日志行列表

        Returns:
            错误片段列表，按重要性排序
        """
        segments = []

        for i, line in enumerate(log_lines):
            # 跳过不重要的行
            if self.should_skip(line):
                continue

            importance = self.calculate_importance(line)

            # 只处理重要的行 (ERROR, WARN 等)
            if importance > 0.5:
                # 提取上下文
                start = max(0, i - self.context_lines)
                end = min(len(log_lines), i + self.context_lines + 1)

                # 检查是否与已有片段重叠
                overlaps = False
                for existing in segments:
                    if not (end <= existing.start_line or start >= existing.end_line):
                        # 有重叠，合并
                        overlaps = True
                        existing.start_line = min(existing.start_line, start)
                        existing.end_line = max(existing.end_line, end)
                        existing.importance = max(existing.importance, importance)
                        break

                if not overlaps:
                    # 创建新片段
                    level = self._detect_level(line)
                    segment = LogSegment(
                        level=level,
                        start_line=start,
                        end_line=end,
                        content=log_lines[start:end],
                        importance=importance
                    )
                    segments.append(segment)

        # 按重要性排序
        segments.sort(key=lambda s: s.importance, reverse=True)

        log.info(f"Extracted {len(segments)} error segments from {len(log_lines)} lines")
        return segments

    def _detect_level(self, line: str) -> LogLevel:
        """检测日志级别"""
        if 'ERROR' in line or 'FATAL' in line or 'Exception' in line:
            return LogLevel.ERROR
        if 'WARN' in line or 'WARNING' in line:
            return LogLevel.WARN
        return LogLevel.INFO

    def filter_logs(
        self,
        log_lines: List[str],
        preserve_structure: bool = True
    ) -> Tuple[List[str], Dict[str, any]]:
        """
        过滤日志，保留最重要的部分

        Args:
            log_lines: 完整日志
            preserve_structure: 是否保留原始行号结构

        Returns:
            (过滤后的日志, 统计信息)
        """
        # 1. 提取错误片段
        segments = self.extract_error_segments(log_lines)

        # 2. 按重要性选择片段，直到达到 token 限制
        selected_lines = []
        total_chars = 0
        segments_used = 0

        for segment in segments:
            segment_chars = sum(len(line) for line in segment.content)

            if total_chars + segment_chars > self.max_chars:
                # 超出限制，但如果是第一个片段，至少保留部分
                if segments_used == 0:
                    # 截取部分内容
                    remaining_chars = self.max_chars - total_chars
                    partial_lines = []
                    partial_chars = 0

                    for line in segment.content:
                        if partial_chars + len(line) <= remaining_chars:
                            partial_lines.append(line)
                            partial_chars += len(line)
                        else:
                            break

                    if partial_lines:
                        selected_lines.extend(partial_lines)
                        total_chars += partial_chars
                        segments_used += 1

                break

            # 添加整个片段
            selected_lines.extend(segment.content)
            total_chars += segment_chars
            segments_used += 1

        # 3. 去重
        unique_lines = []
        seen = set()
        for line in selected_lines:
            line_hash = hash(line.strip())
            if line_hash not in seen:
                unique_lines.append(line)
                seen.add(line_hash)

        # 4. 统计信息
        stats = {
            'original_lines': len(log_lines),
            'filtered_lines': len(unique_lines),
            'segments_extracted': len(segments),
            'segments_used': segments_used,
            'original_chars': sum(len(line) for line in log_lines),
            'filtered_chars': sum(len(line) for line in unique_lines),
            'estimated_tokens': len(unique_lines) * 20,  # 粗略估计
            'compression_ratio': len(unique_lines) / len(log_lines) if log_lines else 0,
            'cost_saved_percent': (1 - len(unique_lines) / len(log_lines)) * 100 if log_lines else 0
        }

        log.info(
            f"Log filtering: {stats['original_lines']} → {stats['filtered_lines']} lines "
            f"({stats['compression_ratio']:.1%}), saved {stats['cost_saved_percent']:.1f}% cost"
        )

        return unique_lines, stats

    def filter_multiple_sources(
        self,
        logs_dict: Dict[str, List[str]],
        prioritize: Optional[List[str]] = None
    ) -> Tuple[Dict[str, List[str]], Dict[str, any]]:
        """
        过滤多个日志源

        Args:
            logs_dict: {'nextflow_log': [...], 'aws_batch_logs': {...}, ...}
            prioritize: 优先处理的日志源列表

        Returns:
            (过滤后的日志字典, 统计信息)
        """
        if not prioritize:
            prioritize = ['aws_batch_logs', 'stderr', 'nextflow_log', 'stdout']

        filtered = {}
        total_stats = {
            'sources_processed': 0,
            'total_original_lines': 0,
            'total_filtered_lines': 0,
            'total_cost_saved_percent': 0
        }

        remaining_tokens = self.max_tokens

        for source in prioritize:
            if source not in logs_dict or remaining_tokens <= 0:
                continue

            source_logs = logs_dict[source]

            # 处理嵌套字典 (如 aws_batch_logs)
            if isinstance(source_logs, dict):
                filtered_source = {}
                for job_id, job_logs in source_logs.items():
                    if remaining_tokens <= 0:
                        break

                    # 为每个 job 分配一部分 token
                    job_max_tokens = remaining_tokens // max(1, len(source_logs))

                    temp_filter = CostOptimizedLogFilter(
                        max_tokens=job_max_tokens,
                        context_lines=self.context_lines
                    )

                    filtered_job_logs, job_stats = temp_filter.filter_logs(job_logs)
                    filtered_source[job_id] = filtered_job_logs

                    remaining_tokens -= job_stats['estimated_tokens']
                    total_stats['total_original_lines'] += job_stats['original_lines']
                    total_stats['total_filtered_lines'] += job_stats['filtered_lines']

                if filtered_source:
                    filtered[source] = filtered_source
                    total_stats['sources_processed'] += 1

            # 处理列表
            elif isinstance(source_logs, list):
                source_max_tokens = remaining_tokens

                temp_filter = CostOptimizedLogFilter(
                    max_tokens=source_max_tokens,
                    context_lines=self.context_lines
                )

                filtered_logs, source_stats = temp_filter.filter_logs(source_logs)
                filtered[source] = filtered_logs

                remaining_tokens -= source_stats['estimated_tokens']
                total_stats['total_original_lines'] += source_stats['original_lines']
                total_stats['total_filtered_lines'] += source_stats['filtered_lines']
                total_stats['sources_processed'] += 1

        # 计算总体节省
        if total_stats['total_original_lines'] > 0:
            total_stats['total_cost_saved_percent'] = (
                1 - total_stats['total_filtered_lines'] / total_stats['total_original_lines']
            ) * 100

        log.info(
            f"Filtered {total_stats['sources_processed']} log sources: "
            f"{total_stats['total_original_lines']} → {total_stats['total_filtered_lines']} lines, "
            f"saved {total_stats['total_cost_saved_percent']:.1f}% cost"
        )

        return filtered, total_stats
