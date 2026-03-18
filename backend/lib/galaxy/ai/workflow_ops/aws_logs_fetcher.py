"""
AWS CloudWatch Logs Fetcher

智能获取 AWS Batch 容器日志
"""

import logging
import boto3
from typing import Dict, List, Optional, Any
from pathlib import Path
from datetime import datetime, timedelta

log = logging.getLogger(__name__)


class AWSLogsFetcher:
    """
    AWS CloudWatch 日志获取器

    支持:
    1. 从 CloudWatch 实时获取运行中的任务日志
    2. 持久化日志到本地
    3. 优先使用本地缓存
    """

    def __init__(self, region_name: str = 'us-east-1'):
        """
        初始化 AWS 客户端

        Args:
            region_name: AWS 区域
        """
        try:
            self.logs_client = boto3.client('logs', region_name=region_name)
            self.batch_client = boto3.client('batch', region_name=region_name)
            self.available = True
            log.info(f"AWS CloudWatch client initialized for region: {region_name}")
        except Exception as e:
            log.warning(f"Failed to initialize AWS clients: {e}")
            self.logs_client = None
            self.batch_client = None
            self.available = False

    def get_batch_job_log_stream(self, job_id: str) -> Optional[Dict[str, str]]:
        """
        获取 Batch Job 的 CloudWatch 日志流信息

        Args:
            job_id: AWS Batch Job ID

        Returns:
            {'log_group': '...', 'log_stream': '...'} 或 None
        """
        if not self.available:
            return None

        try:
            # 获取 Job 详情
            response = self.batch_client.describe_jobs(jobs=[job_id])

            if not response.get('jobs'):
                log.warning(f"Job {job_id} not found in AWS Batch")
                return None

            job = response['jobs'][0]

            # 从 Job 中提取日志流信息
            if 'container' in job and 'logStreamName' in job['container']:
                log_stream = job['container']['logStreamName']
                log_group = '/aws/batch/job'  # AWS Batch 默认日志组

                return {
                    'log_group': log_group,
                    'log_stream': log_stream
                }

            log.warning(f"No log stream found for job {job_id}")
            return None

        except Exception as e:
            log.error(f"Failed to get log stream for job {job_id}: {e}")
            return None

    def fetch_logs_from_cloudwatch(
        self,
        log_group: str,
        log_stream: str,
        max_lines: int = 1000
    ) -> List[str]:
        """
        从 CloudWatch 获取日志

        Args:
            log_group: CloudWatch 日志组名称
            log_stream: CloudWatch 日志流名称
            max_lines: 最大行数限制

        Returns:
            日志行列表
        """
        if not self.available:
            return []

        try:
            log.info(f"Fetching logs from CloudWatch: {log_group}/{log_stream}")

            logs = []
            next_token = None

            while len(logs) < max_lines:
                # 获取日志事件
                kwargs = {
                    'logGroupName': log_group,
                    'logStreamName': log_stream,
                    'startFromHead': True,
                    'limit': min(1000, max_lines - len(logs))
                }

                if next_token:
                    kwargs['nextToken'] = next_token

                response = self.logs_client.get_log_events(**kwargs)

                events = response.get('events', [])
                if not events:
                    break

                # 提取消息
                for event in events:
                    logs.append(event['message'])

                # 检查是否有更多日志
                next_forward_token = response.get('nextForwardToken')
                if next_forward_token == next_token:
                    # 没有更多日志了
                    break

                next_token = next_forward_token

            log.info(f"Fetched {len(logs)} log lines from CloudWatch")
            return logs

        except Exception as e:
            log.error(f"Failed to fetch logs from CloudWatch: {e}")
            import traceback
            log.error(traceback.format_exc())
            return []

    def save_logs_to_file(self, logs: List[str], file_path: Path):
        """
        保存日志到本地文件

        Args:
            logs: 日志行列表
            file_path: 保存路径
        """
        try:
            file_path.parent.mkdir(parents=True, exist_ok=True)

            with open(file_path, 'w', encoding='utf-8') as f:
                for line in logs:
                    f.write(line + '\n')

            log.info(f"Saved {len(logs)} log lines to {file_path}")

        except Exception as e:
            log.error(f"Failed to save logs to {file_path}: {e}")

    def get_job_logs(
        self,
        job_id: str,
        cache_dir: Optional[Path] = None,
        force_refresh: bool = False
    ) -> List[str]:
        """
        智能获取 Job 日志（优先使用缓存）

        Args:
            job_id: AWS Batch Job ID
            cache_dir: 本地缓存目录
            force_refresh: 强制从 CloudWatch 刷新

        Returns:
            日志行列表
        """
        # 1. 如果有缓存且不强制刷新，优先使用缓存
        if cache_dir and not force_refresh:
            cache_file = cache_dir / f"{job_id}.log"
            if cache_file.exists():
                try:
                    with open(cache_file, 'r', encoding='utf-8', errors='ignore') as f:
                        logs = f.readlines()
                    log.info(f"Loaded {len(logs)} lines from cache: {cache_file}")
                    return [line.rstrip('\n') for line in logs]
                except Exception as e:
                    log.warning(f"Failed to read cache file {cache_file}: {e}")

        # 2. 从 CloudWatch 获取
        if not self.available:
            log.warning("AWS clients not available, cannot fetch from CloudWatch")
            return []

        log_stream_info = self.get_batch_job_log_stream(job_id)
        if not log_stream_info:
            return []

        logs = self.fetch_logs_from_cloudwatch(
            log_stream_info['log_group'],
            log_stream_info['log_stream']
        )

        # 3. 保存到缓存
        if cache_dir and logs:
            cache_file = cache_dir / f"{job_id}.log"
            self.save_logs_to_file(logs, cache_file)

        return logs


def get_aws_logs_fetcher(app) -> Optional[AWSLogsFetcher]:
    """
    获取或创建 AWS 日志获取器（单例）

    Args:
        app: Galaxy app instance

    Returns:
        AWSLogsFetcher 实例或 None
    """
    # 检查是否已经创建
    if hasattr(app, '_aws_logs_fetcher'):
        return app._aws_logs_fetcher

    # 创建新实例
    import os
    region = os.environ.get('AWS_REGION', 'us-east-1')

    try:
        fetcher = AWSLogsFetcher(region_name=region)
        app._aws_logs_fetcher = fetcher
        return fetcher
    except Exception as e:
        log.warning(f"Failed to create AWS logs fetcher: {e}")
        return None


def extract_job_ids_from_trace(trace_file: Path) -> List[Dict[str, str]]:
    """
    从 workflow-trace.txt 提取 AWS Batch Job IDs

    Args:
        trace_file: trace 文件路径

    Returns:
        [{'task_name': '...', 'job_id': '...', 'status': 'FAILED'}, ...]
    """
    jobs = []

    try:
        with open(trace_file, 'r') as f:
            lines = f.readlines()

        # 跳过表头
        for line in lines[1:]:
            parts = line.strip().split('\t')
            if len(parts) < 13:
                continue

            # 修正列索引（参考trace文件header）:
            # task_id=0, hash=1, native_id=2, name=3, status=4, exit=5...
            native_id = parts[2]  # 列3: native_id (AWS Batch Job ID)
            task_name = parts[3]  # 列4: name (任务名称)
            status = parts[4]     # 列5: status

            # 只收集失败或仍在运行的任务
            # AWS Batch Job ID 是 UUID 格式（如 c010563b-e61d-4e32-9fb6-7ce7c6621452），不是 "job-xxx"
            if status in ['FAILED', 'RUNNING'] and native_id and native_id != '-' and len(native_id) > 10 and '-' in native_id:
                jobs.append({
                    'task_name': task_name,
                    'job_id': native_id,
                    'status': status
                })

        log.info(f"Extracted {len(jobs)} job IDs from trace file")

    except Exception as e:
        log.error(f"Failed to extract job IDs from trace file: {e}")

    return jobs
