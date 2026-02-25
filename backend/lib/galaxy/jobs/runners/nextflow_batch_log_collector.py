"""
Nextflow AWS Batch Log Collector

从AWS CloudWatch获取每个Batch任务的执行日志
支持实时流式日志和历史日志查询

架构说明:
1. Nextflow在AWS Batch上运行时，每个process会创建一个Batch job
2. 每个Batch job的日志会发送到CloudWatch Logs
3. 日志路径: /aws/batch/job
4. LogStream命名: <container-name>/default/<task-id>

用法:
    collector = BatchLogCollector(aws_region='us-west-2', aws_profile='AdministratorAccess-399683337364')

    # 获取workflow的所有任务日志
    logs = collector.get_workflow_logs(workflow_id=123)

    # 实时流式获取单个任务日志
    for log_line in collector.stream_task_logs(job_id='abc123'):
        print(log_line)
"""

import logging
import time
from typing import Dict, List, Optional, Iterator, Tuple
from datetime import datetime, timedelta
import boto3
from botocore.exceptions import ClientError

log = logging.getLogger(__name__)


class BatchLogCollector:
    """
    AWS Batch日志收集器

    从CloudWatch Logs获取Batch任务的执行日志
    """

    def __init__(
        self,
        aws_region: str = 'us-west-2',
        aws_profile: Optional[str] = None,
        log_group: str = '/aws/batch/job'
    ):
        """
        初始化日志收集器

        Args:
            aws_region: AWS区域
            aws_profile: AWS配置文件名（用于SSO）
            log_group: CloudWatch日志组名称
        """
        self.aws_region = aws_region
        self.aws_profile = aws_profile
        self.log_group = log_group
        self.logger = logging.getLogger(__name__)

        # 初始化AWS客户端
        session_kwargs = {'region_name': aws_region}
        if aws_profile:
            session_kwargs['profile_name'] = aws_profile

        session = boto3.Session(**session_kwargs)
        self.batch_client = session.client('batch')
        self.logs_client = session.client('logs')

        # 日志流位置记录（用于增量读取）
        self.stream_positions = {}  # {stream_name: next_token}

    def get_batch_jobs_for_workflow(
        self,
        workflow_id: int,
        queue_name: str = 'galaxy-cloud-queue'
    ) -> List[Dict]:
        """
        获取workflow相关的所有Batch jobs

        Args:
            workflow_id: Nextflow workflow ID
            queue_name: AWS Batch队列名称

        Returns:
            Batch job信息列表
        """
        all_jobs = []

        # AWS Batch job状态列表
        statuses = ['SUBMITTED', 'PENDING', 'RUNNABLE', 'STARTING', 'RUNNING', 'SUCCEEDED', 'FAILED']

        for status in statuses:
            try:
                # 列出指定状态的jobs
                response = self.batch_client.list_jobs(
                    jobQueue=queue_name,
                    jobStatus=status,
                    maxResults=100
                )

                jobs = response.get('jobSummaryList', [])

                # 过滤出属于该workflow的jobs
                # Nextflow在job名称中包含workflow信息
                workflow_jobs = [
                    job for job in jobs
                    if f'nf-{workflow_id}' in job.get('jobName', '') or
                       f'workflow_{workflow_id}' in job.get('jobName', '')
                ]

                all_jobs.extend(workflow_jobs)

            except ClientError as e:
                self.logger.error(f"Failed to list jobs with status {status}: {e}")

        return all_jobs

    def get_log_stream_for_job(self, job_id: str, timeout: int = 5) -> Optional[str]:
        """
        获取Batch job的CloudWatch日志流名称

        Args:
            job_id: AWS Batch job ID
            timeout: API调用超时时间（秒）

        Returns:
            日志流名称，如果未找到则返回None
        """
        try:
            # 获取job详情（添加超时配置）
            import boto3
            from botocore.config import Config
            config = Config(connect_timeout=timeout, read_timeout=timeout)

            # 为这个调用创建临时客户端（带超时配置）
            batch_client = boto3.client('batch', region_name=self.aws_region, config=config)
            if self.aws_profile:
                session = boto3.Session(profile_name=self.aws_profile, region_name=self.aws_region)
                batch_client = session.client('batch', config=config)

            response = batch_client.describe_jobs(jobs=[job_id])

            if not response.get('jobs'):
                self.logger.warning(f"Job {job_id} not found")
                return None

            job = response['jobs'][0]

            # 从job详情中提取日志流名称
            log_stream_name = job.get('container', {}).get('logStreamName')

            if not log_stream_name:
                self.logger.warning(f"No log stream found for job {job_id}")
                return None

            return log_stream_name

        except ClientError as e:
            # 如果job不存在（比如已经过期删除），不输出错误日志，只警告
            error_code = e.response.get('Error', {}).get('Code', '')
            if error_code in ['ResourceNotFoundException', 'JobNotFoundException']:
                self.logger.debug(f"Job {job_id} not found in AWS Batch (may be expired)")
            else:
                self.logger.error(f"Failed to get log stream for job {job_id}: {e}")
            return None
        except Exception as e:
            # 处理超时等其他异常
            self.logger.warning(f"Failed to get log stream for job {job_id}: {e}")
            return None

    def get_job_logs(
        self,
        job_id: str,
        start_time: Optional[datetime] = None,
        end_time: Optional[datetime] = None,
        limit: int = 1000,
        timeout: int = 5
    ) -> List[Dict]:
        """
        获取单个Batch job的日志

        Args:
            job_id: AWS Batch job ID
            start_time: 开始时间（可选）
            end_time: 结束时间（可选）
            limit: 最大日志行数
            timeout: CloudWatch API调用超时时间（秒）

        Returns:
            日志事件列表，每个事件包含 {timestamp, message}
        """
        # 获取log stream（带超时）
        log_stream = self.get_log_stream_for_job(job_id, timeout=timeout)
        if not log_stream:
            return []

        try:
            # 为CloudWatch客户端添加超时配置
            import boto3
            from botocore.config import Config
            config = Config(connect_timeout=timeout, read_timeout=timeout)

            logs_client = boto3.client('logs', region_name=self.aws_region, config=config)
            if self.aws_profile:
                session = boto3.Session(profile_name=self.aws_profile, region_name=self.aws_region)
                logs_client = session.client('logs', config=config)

            kwargs = {
                'logGroupName': self.log_group,
                'logStreamName': log_stream,
                'limit': limit
            }

            # 添加时间过滤
            if start_time:
                kwargs['startTime'] = int(start_time.timestamp() * 1000)
            if end_time:
                kwargs['endTime'] = int(end_time.timestamp() * 1000)

            response = logs_client.get_log_events(**kwargs)
            events = response.get('events', [])

            # 格式化日志
            formatted_logs = [
                {
                    'timestamp': datetime.fromtimestamp(event['timestamp'] / 1000),
                    'message': event['message']
                }
                for event in events
            ]

            return formatted_logs

        except ClientError as e:
            # 友好处理常见错误（如log stream不存在）
            error_code = e.response.get('Error', {}).get('Code', '')
            if error_code == 'ResourceNotFoundException':
                self.logger.debug(f"Log stream not found for job {job_id} (may be expired or deleted)")
            else:
                self.logger.error(f"Failed to get logs for job {job_id}: {e}")
            return []
        except Exception as e:
            # 处理超时等其他异常
            self.logger.warning(f"Failed to get logs for job {job_id} (timeout or error): {e}")
            return []

    def stream_task_logs(
        self,
        job_id: str,
        follow: bool = True,
        poll_interval: int = 2
    ) -> Iterator[Tuple[datetime, str]]:
        """
        实时流式获取任务日志（类似 tail -f）

        Args:
            job_id: AWS Batch job ID
            follow: 是否持续跟踪新日志
            poll_interval: 轮询间隔（秒）

        Yields:
            (timestamp, log_message) 元组
        """
        log_stream = self.get_log_stream_for_job(job_id)
        if not log_stream:
            self.logger.warning(f"No log stream found for job {job_id}")
            return

        next_token = None

        while True:
            try:
                kwargs = {
                    'logGroupName': self.log_group,
                    'logStreamName': log_stream,
                    'startFromHead': True  # 从头开始读取
                }

                if next_token:
                    kwargs['nextToken'] = next_token

                response = self.logs_client.get_log_events(**kwargs)
                events = response.get('events', [])

                # 输出新日志
                for event in events:
                    timestamp = datetime.fromtimestamp(event['timestamp'] / 1000)
                    yield timestamp, event['message']

                # 更新token
                new_token = response.get('nextForwardToken')

                if not follow:
                    break

                # 如果token没变，说明没有新日志
                if new_token == next_token:
                    time.sleep(poll_interval)
                else:
                    next_token = new_token

            except ClientError as e:
                self.logger.error(f"Failed to stream logs for job {job_id}: {e}")
                break

    def get_workflow_logs(
        self,
        workflow_id: int,
        queue_name: str = 'galaxy-cloud-queue',
        include_completed: bool = True
    ) -> Dict[str, List[Dict]]:
        """
        获取整个workflow的所有任务日志

        Args:
            workflow_id: Nextflow workflow ID
            queue_name: AWS Batch队列名称
            include_completed: 是否包含已完成的任务

        Returns:
            {job_id: [logs]} 字典
        """
        workflow_logs = {}

        # 获取所有相关jobs
        jobs = self.get_batch_jobs_for_workflow(workflow_id, queue_name)

        self.logger.info(f"Found {len(jobs)} jobs for workflow {workflow_id}")

        for job in jobs:
            job_id = job['jobId']
            job_name = job['jobName']
            status = job['status']

            # 跳过未完成的任务（如果不包含已完成）
            if not include_completed and status not in ['RUNNING', 'SUCCEEDED', 'FAILED']:
                continue

            self.logger.info(f"Fetching logs for job {job_name} ({job_id}) - {status}")

            # 获取日志
            logs = self.get_job_logs(job_id)

            workflow_logs[job_id] = {
                'job_name': job_name,
                'job_id': job_id,
                'status': status,
                'logs': logs
            }

        return workflow_logs

    def get_task_logs_by_name(
        self,
        task_name: str,
        workflow_id: int,
        queue_name: str = 'galaxy-cloud-queue'
    ) -> Optional[List[Dict]]:
        """
        根据任务名称获取日志

        Args:
            task_name: Nextflow任务名称（如 'STEP_1_FASTQC'）
            workflow_id: Workflow ID
            queue_name: AWS Batch队列名称

        Returns:
            日志列表，如果未找到则返回None
        """
        jobs = self.get_batch_jobs_for_workflow(workflow_id, queue_name)

        # 查找匹配的job
        for job in jobs:
            if task_name in job.get('jobName', ''):
                job_id = job['jobId']
                self.logger.info(f"Found job {job_id} for task {task_name}")
                return self.get_job_logs(job_id)

        self.logger.warning(f"No job found for task {task_name}")
        return None

    def format_logs_for_display(
        self,
        logs: List[Dict],
        show_timestamp: bool = True
    ) -> str:
        """
        格式化日志用于显示

        Args:
            logs: 日志列表
            show_timestamp: 是否显示时间戳

        Returns:
            格式化后的日志字符串
        """
        formatted_lines = []

        for log in logs:
            timestamp = log['timestamp']
            message = log['message']

            if show_timestamp:
                time_str = timestamp.strftime('%Y-%m-%d %H:%M:%S')
                formatted_lines.append(f"[{time_str}] {message}")
            else:
                formatted_lines.append(message)

        return '\n'.join(formatted_lines)


class NextflowTaskLogMapper:
    """
    Nextflow任务与AWS Batch job的映射器

    解析.nextflow.log，建立Nextflow process名称到Batch job ID的映射
    """

    def __init__(self, nextflow_log_path: str):
        """
        初始化映射器

        Args:
            nextflow_log_path: .nextflow.log文件路径
        """
        self.nextflow_log_path = nextflow_log_path
        self.logger = logging.getLogger(__name__)
        self.task_to_job_map = {}  # {task_name: batch_job_id}

    def parse_log(self):
        """
        解析Nextflow日志，提取任务到Batch job的映射

        日志格式示例（实际格式）:
        [AWS BATCH] Process `TASK_NAME` submitted > job=b94ad70d-4c5c-4711-9eed-cdc2391436a0
        """
        import re

        # 正则表达式匹配Batch job提交日志
        # 修复：匹配实际的日志格式 "Process `TASK_NAME` submitted > job=JOB_ID"
        # 示例: [AWS BATCH] Process `NFCORE_CLIPSEQ:CLIPSEQ:INPUT_CHECK:SAMPLESHEET_CHECK (clipseq_samplesheet_v3.csv)` submitted > job=b94ad70d-4c5c-4711-9eed-cdc2391436a0
        pattern = r'Process `([^`]+)` submitted > job=([a-f0-9\-]+)'

        try:
            with open(self.nextflow_log_path, 'r') as f:
                for line in f:
                    match = re.search(pattern, line)
                    if match:
                        task_name = match.group(1)
                        job_id = match.group(2)
                        self.task_to_job_map[task_name] = job_id
                        self.logger.debug(f"Mapped task {task_name} -> job {job_id}")

        except FileNotFoundError:
            self.logger.error(f"Nextflow log not found: {self.nextflow_log_path}")
        except Exception as e:
            self.logger.error(f"Failed to parse Nextflow log: {e}")

    def get_job_id_for_task(self, task_name: str) -> Optional[str]:
        """
        获取任务对应的Batch job ID

        Args:
            task_name: Nextflow任务名称

        Returns:
            Batch job ID，如果未找到则返回None
        """
        return self.task_to_job_map.get(task_name)

    def get_all_mappings(self) -> Dict[str, str]:
        """
        获取所有任务映射

        Returns:
            {task_name: job_id} 字典
        """
        return self.task_to_job_map.copy()
