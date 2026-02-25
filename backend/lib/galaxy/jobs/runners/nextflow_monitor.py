"""
Nextflow Workflow Monitor

监控运行中的Nextflow workflows，提供：
1. 实时日志流式回传到Galaxy
2. 状态轮询和更新
3. 输出同步到Galaxy datasets
4. AWS Batch任务日志收集（CloudWatch）
5. **NEW** LLM智能日志分析
6. **NEW** 自动错误修复

架构：
- NextflowMonitor: 主监控类，管理单个workflow的监控
- NextflowMonitorService: 监控服务，管理所有运行中的workflows
- 使用Celery周期任务实现后台监控
- 集成WorkflowLogAnalyzer和WorkflowAutoHealer
"""

import logging
import os
import subprocess
import time
from pathlib import Path
from typing import Dict, Optional, List, Tuple
from datetime import datetime

# 导入AWS Batch日志收集器
try:
    from .nextflow_batch_log_collector import BatchLogCollector, NextflowTaskLogMapper
    BATCH_LOGS_AVAILABLE = True
except ImportError as e:
    logging.warning(f"AWS Batch log collector not available: {e}")
    BATCH_LOGS_AVAILABLE = False

# 导入AI运维模块
try:
    from galaxy.ai.workflow_ops import (
        WorkflowLogAnalyzer,
        WorkflowAutoHealer,
        UnifiedLLMClient,
    )
    from galaxy.ai.workflow_ops.types import IssueSeverity
    AI_OPS_AVAILABLE = True
except ImportError as e:
    logging.warning(f"AI workflow ops not available: {e}")
    AI_OPS_AVAILABLE = False

# 导入QC门控模块
try:
    from galaxy.jobs.qc_trace_monitor import NextflowQCGateHandler
    QC_GATE_AVAILABLE = True
except ImportError as e:
    logging.warning(f"QC gate handler not available: {e}")
    QC_GATE_AVAILABLE = False

log = logging.getLogger(__name__)


class NextflowMonitor:
    """
    单个Nextflow workflow的监控器

    功能：
    1. 读取并回传Nextflow日志
    2. 检查进程状态
    3. 解析执行进度
    4. 同步输出到Galaxy
    """

    def __init__(
        self,
        invocation_id: int,
        work_dir: Path,
        process_pid: int,
        app,
        enable_batch_logs: bool = True,
        enable_ai_ops: bool = True,
        qc_overrides: Optional[Dict] = None,
        workflow_domain: str = "cryo_em",
        qc_profile: Optional[str] = None,
    ):
        """
        初始化监控器

        Args:
            invocation_id: Workflow invocation ID
            work_dir: Nextflow工作目录
            process_pid: Nextflow进程PID
            app: Galaxy app实例
            enable_batch_logs: 是否启用AWS Batch日志收集
            enable_ai_ops: 是否启用AI运维（日志分析+自动修复）
            qc_overrides: Per-invocation QC threshold overrides (Phase 1)
            workflow_domain: Domain of the workflow for domain-specific QC gating
            qc_profile: Named QC profile (Phase 2 — Layer 3)
        """
        self.invocation_id = invocation_id
        self.work_dir = work_dir
        self.process_pid = process_pid
        self.app = app
        self.qc_overrides = qc_overrides or {}
        self.workflow_domain = workflow_domain
        self.qc_profile = qc_profile
        self.logger = logging.getLogger(f"{__name__}.{invocation_id}")

        # 🔑 关键修复：从数据库获取invocation信息以支持AutoFix
        self.sa_session = app.model.context
        try:
            invocation = self.sa_session.query(app.model.WorkflowInvocation).get(invocation_id)
            if invocation:
                self.user_id = invocation.history.user_id if invocation.history else None
                self.workflow_id = invocation.workflow_id
            else:
                self.logger.warning(f"Could not find invocation {invocation_id}, AutoFix may not work")
                self.user_id = None
                self.workflow_id = None
        except Exception as e:
            self.logger.warning(f"Failed to get invocation info: {e}, AutoFix may not work")
            self.user_id = None
            self.workflow_id = None

        # 日志文件路径
        self.nextflow_log = work_dir / '.nextflow.log'
        self.stdout_file = work_dir / 'nextflow.out'
        self.stderr_file = work_dir / 'nextflow.err'
        self.trace_file = work_dir / 'workflow-trace.txt'

        # 记录已读取的日志位置（避免重复读取）
        self.log_positions = {
            'nextflow_log': 0,
            'stdout': 0,
            'stderr': 0
        }

        # 状态
        self.last_check_time = None
        self.is_completed = False
        self.exit_code = None

        # AWS Batch日志收集器（可选）
        self.batch_log_collector = None
        self.task_log_mapper = None
        self.enable_batch_logs = enable_batch_logs and BATCH_LOGS_AVAILABLE

        if self.enable_batch_logs:
            self._init_batch_log_collector()

        # AI运维模块（可选）
        self.log_analyzer = None
        self.auto_healer = None
        self.enable_ai_ops = enable_ai_ops and AI_OPS_AVAILABLE

        if self.enable_ai_ops:
            self._init_ai_ops()

        # QC门控模块（可选）
        self.qc_handler = None
        if QC_GATE_AVAILABLE:
            self._init_qc_handler()

    def _init_qc_handler(self):
        """初始化QC门控处理器，将完成的进程与QC阈值检查挂钩"""
        try:
            self.qc_handler = NextflowQCGateHandler(
                invocation_id=str(self.invocation_id),
                work_dir=self.work_dir,
                sse_callback=self._make_sse_callback(str(self.invocation_id)),
                app=self.app,
                workflow_domain=self.workflow_domain,
                qc_overrides=self.qc_overrides,
                qc_profile=self.qc_profile,
            )
            profile_note = f", profile='{self.qc_profile}'" if self.qc_profile else ""
            override_note = (
                f", {len(self.qc_overrides)} override(s)" if self.qc_overrides else ""
            )
            self.logger.info(
                f"[Workflow {self.invocation_id}] QC gate handler initialized "
                f"(domain={self.workflow_domain}{profile_note}{override_note})"
            )
        except Exception as e:
            self.logger.warning(f"[Workflow {self.invocation_id}] Failed to initialize QC gate handler: {e}")

    def _make_sse_callback(self, invocation_id: str):
        """
        Build SSE callback that POSTs QC events to the Node frontend server.
        The frontend server receives the POST and broadcasts to connected SSE clients.
        """
        import json as _json
        import urllib.request as _urllib_req

        frontend_url = os.environ.get('FRONTEND_URL', 'http://localhost:5000')
        inject_url = f"{frontend_url}/internal/sse-inject"

        def sse_callback(event_type: str, data: dict):
            payload = _json.dumps({
                "invocation_id": invocation_id,
                "event_type": event_type,
                "data": data,
            }).encode("utf-8")
            try:
                req = _urllib_req.Request(
                    inject_url,
                    data=payload,
                    headers={"Content-Type": "application/json"},
                )
                with _urllib_req.urlopen(req, timeout=5) as resp:
                    if resp.status != 200:
                        self.logger.warning(
                            f"[QC Gate SSE] Inject endpoint returned {resp.status}"
                        )
            except Exception as exc:
                self.logger.warning(
                    f"[QC Gate SSE] Failed to inject {event_type} event: {exc}"
                )

        return sse_callback

    def _init_batch_log_collector(self):
        """
        初始化AWS Batch日志收集器
        """
        try:
            aws_region = os.environ.get('AWS_DEFAULT_REGION', 'us-west-2')
            aws_profile = os.environ.get('AWS_PROFILE', None)

            self.batch_log_collector = BatchLogCollector(
                aws_region=aws_region,
                aws_profile=aws_profile
            )

            self.task_log_mapper = NextflowTaskLogMapper(
                str(self.nextflow_log)
            )

            self.logger.info(f"[Workflow {self.invocation_id}] AWS Batch log collector initialized")
        except Exception as e:
            self.logger.warning(f"[Workflow {self.invocation_id}] Failed to initialize Batch log collector: {e}")
            self.enable_batch_logs = False

    def _init_ai_ops(self):
        """
        初始化AI运维模块
        """
        try:
            # 创建共享的LLM客户端
            llm_client = UnifiedLLMClient(
                daily_budget=float(os.environ.get('NEXTFLOW_AI_DAILY_BUDGET', '10.0')),
                enable_budget_control=True
            )

            # 日志分析器
            self.log_analyzer = WorkflowLogAnalyzer(
                llm_client=llm_client,
                enable_llm=True,
                llm_threshold=IssueSeverity.WARNING  # WARNING及以上才调用LLM
            )

            # 自动修复器
            auto_fix_mode = os.environ.get('NEXTFLOW_AUTO_FIX_MODE', 'safe')  # safe/moderate/aggressive/manual
            self.auto_healer = WorkflowAutoHealer(
                llm_client=llm_client,
                auto_fix_mode=auto_fix_mode
            )

            self.logger.info(
                f"[Workflow {self.invocation_id}] AI Ops initialized "
                f"(auto_fix_mode={auto_fix_mode})"
            )
        except Exception as e:
            self.logger.warning(f"[Workflow {self.invocation_id}] Failed to initialize AI Ops: {e}")
            self.enable_ai_ops = False

    def is_process_running(self) -> bool:
        """
        检查Nextflow进程是否还在运行

        Returns:
            True if running, False if stopped
        """
        try:
            # 使用 ps 命令检查进程
            result = subprocess.run(
                ['ps', '-p', str(self.process_pid)],
                capture_output=True,
                text=True
            )
            return result.returncode == 0
        except Exception as e:
            self.logger.error(f"Failed to check process status: {e}")
            return False

    def read_log_updates(self, file_path: Path, position_key: str) -> List[str]:
        """
        读取日志文件的新增内容

        Args:
            file_path: 日志文件路径
            position_key: 位置记录的key

        Returns:
            新增的日志行列表
        """
        if not file_path.exists():
            return []

        try:
            with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                # 跳转到上次读取的位置
                f.seek(self.log_positions[position_key])

                # 读取新内容
                new_lines = f.readlines()

                # 更新位置
                self.log_positions[position_key] = f.tell()

                return new_lines
        except Exception as e:
            self.logger.error(f"Failed to read {file_path}: {e}")
            return []

    def collect_logs(self) -> Dict[str, List[str]]:
        """
        收集所有日志文件的更新

        包括:
        1. Nextflow主进程日志
        2. AWS Batch任务日志（如果启用）

        Returns:
            {'nextflow_log': [...], 'stdout': [...], 'stderr': [...], 'batch_logs': {...}}
        """
        logs = {
            'nextflow_log': self.read_log_updates(self.nextflow_log, 'nextflow_log'),
            'stdout': self.read_log_updates(self.stdout_file, 'stdout'),
            'stderr': self.read_log_updates(self.stderr_file, 'stderr')
        }

        # 收集AWS Batch日志
        if self.enable_batch_logs and self.batch_log_collector:
            logs['batch_logs'] = self._collect_batch_logs()

        return logs

    def _collect_batch_logs(self) -> Dict[str, any]:
        """
        收集AWS Batch任务日志

        Returns:
            {task_name: {'job_id': ..., 'logs': [...]}}
        """
        import time
        batch_logs = {}
        start_time = time.time()
        max_collection_time = 10  # 最多花10秒收集日志，避免阻塞API

        try:
            # 1. 更新任务映射（解析Nextflow日志）
            if self.task_log_mapper:
                self.task_log_mapper.parse_log()
                mappings = self.task_log_mapper.get_all_mappings()

                self.logger.info(
                    f"[Workflow {self.invocation_id}] Found {len(mappings)} tasks with AWS Batch job IDs"
                )

                # 2. 为每个任务获取CloudWatch日志（带超时保护）
                task_count = 0
                max_tasks = 20  # 每次API调用最多收集20个任务的日志

                for task_name, job_id in mappings.items():
                    # 超时检查：避免阻塞太久
                    elapsed = time.time() - start_time
                    if elapsed > max_collection_time:
                        self.logger.warning(
                            f"[Workflow {self.invocation_id}] Batch log collection timeout "
                            f"after {elapsed:.1f}s, collected {task_count} tasks"
                        )
                        break

                    # 限制任务数量
                    if task_count >= max_tasks:
                        self.logger.info(
                            f"[Workflow {self.invocation_id}] Reached max tasks limit ({max_tasks}), "
                            f"skipping remaining tasks"
                        )
                        break

                    # 检查是否已经获取过该任务的日志
                    if task_name in batch_logs:
                        continue

                    # 获取任务日志（带5秒超时）
                    try:
                        logs = self.batch_log_collector.get_job_logs(job_id, limit=100, timeout=5)
                        task_count += 1

                        if logs:
                            batch_logs[task_name] = {
                                'job_id': job_id,
                                'logs': logs,
                                'log_count': len(logs)
                            }
                            self.logger.debug(
                                f"[Workflow {self.invocation_id}] Collected {len(logs)} logs "
                                f"for task {task_name} (job {job_id})"
                            )

                            # 💾 持久化日志到本地文件（实时保存）
                            self._persist_batch_log(task_name, job_id, logs)
                    except Exception as e:
                        self.logger.warning(
                            f"[Workflow {self.invocation_id}] Failed to get logs for task "
                            f"{task_name} (job {job_id}): {e}"
                        )
                        # 继续处理下一个任务，不中断整个流程

                elapsed = time.time() - start_time
                self.logger.info(
                    f"[Workflow {self.invocation_id}] Batch log collection completed in {elapsed:.1f}s, "
                    f"collected {len(batch_logs)} tasks"
                )

        except Exception as e:
            self.logger.error(f"[Workflow {self.invocation_id}] Failed to collect Batch logs: {e}")

        return batch_logs

    def _persist_batch_log(self, task_name: str, job_id: str, logs: List[str]):
        """
        持久化 AWS Batch 任务日志到本地文件（实时保存）

        Args:
            task_name: 任务名称
            job_id: AWS Batch Job ID
            logs: 日志行列表

        日志保存位置：
            {work_dir}/aws_batch_logs/{task_name}_{job_id}.log
        """
        try:
            # 创建日志目录
            logs_dir = self.work_dir / "aws_batch_logs"
            logs_dir.mkdir(exist_ok=True)

            # 清理任务名称中的特殊字符，用于文件名
            safe_task_name = task_name.replace(':', '_').replace('/', '_').replace(' ', '_')
            log_file = logs_dir / f"{safe_task_name}_{job_id}.log"

            # 增量追加日志（使用追加模式，避免重复写入）
            # 首次创建时写入头部信息
            if not log_file.exists():
                with open(log_file, 'w') as f:
                    f.write(f"# AWS Batch Job ID: {job_id}\n")
                    f.write(f"# Task Name: {task_name}\n")
                    f.write(f"# Workflow Invocation: {self.invocation_id}\n")
                    f.write("# " + "="*70 + "\n")
                    f.write("# Log lines below are collected in real-time from CloudWatch\n")
                    f.write("# " + "="*70 + "\n\n")

            # 追加新日志
            with open(log_file, 'a') as f:
                for log_line in logs:
                    # 处理字典格式（{timestamp, message}）和字符串格式
                    if isinstance(log_line, dict):
                        message = log_line.get('message', str(log_line))
                        f.write(message)
                    else:
                        f.write(str(log_line))

                    if not str(log_line).endswith('\n'):
                        f.write('\n')

            self.logger.info(
                f"[Workflow {self.invocation_id}] Persisted {len(logs)} log lines "
                f"for task {task_name} to {log_file}"
            )

        except Exception as e:
            self.logger.error(
                f"[Workflow {self.invocation_id}] Failed to persist logs "
                f"for task {task_name}: {e}"
            )

    def send_logs_to_galaxy(self, logs: Dict[str, any]):
        """
        将日志发送到Galaxy workflow invocation

        Args:
            logs: 日志内容字典
        """
        # 🚀 阶段1：简单实现 - 将日志写入Galaxy日志系统
        for log_type, content in logs.items():
            if log_type == 'batch_logs':
                # AWS Batch日志（字典格式）
                self._send_batch_logs(content)
            elif content:
                # Nextflow主进程日志（列表格式）
                self._send_nextflow_logs(log_type, content)

        # 🎯 阶段2：TODO - 将日志写入workflow_invocation_step的messages
        # 需要获取workflow_invocation对象并更新其消息
        # self._update_invocation_messages(logs)

    def _send_nextflow_logs(self, log_type: str, lines: List[str]):
        """发送Nextflow主进程日志"""
        if not lines:
            return

        # 格式化日志
        prefix_map = {
            'nextflow_log': '[Nextflow] ',
            'stdout': '[stdout] ',
            'stderr': '[stderr] '
        }
        prefix = prefix_map.get(log_type, '')

        for line in lines:
            line = line.rstrip('\n')
            if line:  # 跳过空行
                self.logger.info(f"[Workflow {self.invocation_id}] {prefix}{line}")

    def _send_batch_logs(self, batch_logs: Dict[str, any]):
        """发送AWS Batch任务日志"""
        if not batch_logs:
            return

        for task_name, task_info in batch_logs.items():
            job_id = task_info.get('job_id', 'unknown')
            logs = task_info.get('logs', [])

            if logs:
                self.logger.info(
                    f"[Workflow {self.invocation_id}] [Batch:{task_name}] "
                    f"Job {job_id} - {len(logs)} log entries"
                )

                # 只显示最近的几条日志（避免刷屏）
                recent_logs = logs[-10:] if len(logs) > 10 else logs
                for log_entry in recent_logs:
                    timestamp = log_entry.get('timestamp', '')
                    message = log_entry.get('message', '')
                    self.logger.info(
                        f"[Workflow {self.invocation_id}] [Batch:{task_name}] "
                        f"[{timestamp}] {message}"
                    )

    def _parse_from_nextflow_log(self) -> Dict[str, any]:
        """
        从 .nextflow.log 解析实时任务状态（方案1：实时日志解析）

        解析 Nextflow 日志文件中的事件：
        - Submitted process > ... （任务提交）
        - process > ... [COMPLETED] （任务完成）
        - process > ... exit: 0 （任务成功）
        - process > ... [FAILED] （任务失败）
        - process > ... exit: 1 （任务失败）
        - CACHED: ... （任务缓存）

        Returns:
            状态字典 {total_tasks, completed_tasks, failed_tasks, ...}
        """
        import re
        from collections import defaultdict

        # 用于跟踪每个任务的最新状态
        task_states = {}  # {task_hash: {'name': str, 'status': str, 'time': str}}

        nextflow_log = self.work_dir / '.nextflow.log'
        if not nextflow_log.exists():
            return {
                'total_tasks': 0,
                'completed_tasks': 0,
                'failed_tasks': 0,
                'running_tasks': 0,
                'cached_tasks': 0,
                'progress_percent': 0
            }

        try:
            with open(nextflow_log, 'r', encoding='utf-8', errors='ignore') as f:
                for line in f:
                    # 1. 解析任务提交事件
                    # 示例: [f0/efe1c3] Submitted process > STAR_GENOMEGENERATE (genome.fa)
                    submit_match = re.search(r'\[([a-f0-9]{2}/[a-f0-9]{6})\].*Submitted process\s+>\s+(.+)', line)
                    if submit_match:
                        task_hash = submit_match.group(1)
                        task_name = submit_match.group(2).strip()
                        # 提取时间戳（如果有）
                        time_match = re.match(r'(\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\.\d+)', line)
                        timestamp = time_match.group(1) if time_match else ''

                        if task_hash not in task_states:
                            task_states[task_hash] = {
                                'name': task_name,
                                'status': 'SUBMITTED',
                                'time': timestamp
                            }
                        continue

                    # 2. 解析任务完成事件（多种格式）
                    # 格式1: [f0/efe1c3] process > STAR_GENOMEGENERATE [COMPLETED]
                    # 格式2: [f0/efe1c3] Completed process > STAR_GENOMEGENERATE
                    complete_match = re.search(
                        r'\[([a-f0-9]{2}/[a-f0-9]{6})\].*(?:process\s+>\s+\w+\s+\[COMPLETED\]|Completed\s+process)',
                        line
                    )
                    if complete_match:
                        task_hash = complete_match.group(1)
                        if task_hash in task_states:
                            task_states[task_hash]['status'] = 'COMPLETED'
                        continue

                    # 3. 解析任务失败事件
                    # 格式: [f0/efe1c3] process > TASK [FAILED]
                    # 或: [f0/efe1c3] NOTE: Process `TASK` terminated with an error exit status
                    fail_match = re.search(
                        r'\[([a-f0-9]{2}/[a-f0-9]{6})\].*(?:\[FAILED\]|terminated with an error)',
                        line
                    )
                    if fail_match:
                        task_hash = fail_match.group(1)
                        if task_hash in task_states:
                            task_states[task_hash]['status'] = 'FAILED'
                        continue

                    # 4. 解析缓存事件
                    # 格式: [f0/efe1c3] Cached process > TASK
                    cache_match = re.search(r'\[([a-f0-9]{2}/[a-f0-9]{6})\].*Cached\s+process', line)
                    if cache_match:
                        task_hash = cache_match.group(1)
                        if task_hash in task_states:
                            task_states[task_hash]['status'] = 'CACHED'
                        continue

            # 统计各状态任务数
            status_counts = defaultdict(int)
            for task_hash, task_info in task_states.items():
                status_counts[task_info['status']] += 1

            total = len(task_states)
            completed = status_counts.get('COMPLETED', 0) + status_counts.get('CACHED', 0)
            failed = status_counts.get('FAILED', 0)
            running = status_counts.get('SUBMITTED', 0)  # 已提交但未完成/失败的

            return {
                'total_tasks': total,
                'completed_tasks': status_counts.get('COMPLETED', 0),
                'failed_tasks': failed,
                'running_tasks': running,
                'cached_tasks': status_counts.get('CACHED', 0),
                'progress_percent': int((completed / total * 100)) if total > 0 else 0
            }

        except Exception as e:
            self.logger.error(f"Failed to parse .nextflow.log: {e}")
            import traceback
            traceback.print_exc()
            return {
                'total_tasks': 0,
                'completed_tasks': 0,
                'failed_tasks': 0,
                'running_tasks': 0,
                'cached_tasks': 0,
                'progress_percent': 0
            }

    def parse_execution_status(self) -> Dict[str, any]:
        """
        解析Nextflow执行状态（方案2：真正的混合模式 - trace + log）

        混合策略（解决running任务显示为0的问题）：
        1. 从 trace 文件读取已完成/失败的任务（最准确）
        2. ALWAYS 从 .nextflow.log 读取总提交任务数（实时性）
        3. 计算 running = submitted - finished

        为什么必须混合？
        - trace文件只记录已完成或失败的任务
        - 正在运行的任务不会出现在trace中
        - 所以必须从log中获取总任务数，然后计算差值

        Returns:
            状态字典
        """
        status = {
            'total_tasks': 0,
            'completed_tasks': 0,
            'failed_tasks': 0,
            'running_tasks': 0,
            'cached_tasks': 0,
            'progress_percent': 0
        }

        # 🔑 第一步：从 trace 文件读取已完成/失败的任务（最准确）
        finished_tasks = 0  # 已完成或失败的任务数
        if self.trace_file.exists():
            try:
                with open(self.trace_file, 'r') as f:
                    lines = f.readlines()
                    # 跳过header
                    for line in lines[1:]:
                        if line.strip():
                            finished_tasks += 1
                            # trace格式: task_id hash native_id ... status exit ...
                            parts = line.split('\t')
                            if len(parts) > 4:
                                task_status = parts[4].strip()
                                if task_status == 'COMPLETED':
                                    status['completed_tasks'] += 1
                                elif task_status == 'FAILED':
                                    status['failed_tasks'] += 1
                                elif task_status == 'RUNNING' or task_status == 'SUBMITTED':
                                    # trace中的RUNNING/SUBMITTED（极少见，但有可能）
                                    status['running_tasks'] += 1
                                elif task_status == 'CACHED':
                                    status['cached_tasks'] += 1
                                elif task_status == 'ABORTED':
                                    # 🔑 ABORTED 状态通常是因为依赖任务失败导致的中止
                                    # 计入失败任务（因为这些任务没有成功完成）
                                    status['failed_tasks'] += 1
            except Exception as e:
                self.logger.error(f"Failed to parse trace file: {e}")

        # 🔑 第二步：从 .nextflow.log 获取总提交任务数
        # （trace文件不包含running任务，必须从log中补充！）
        # 即使进程不在运行，也要解析日志以获取历史数据
        log_status = self._parse_from_nextflow_log()
        total_submitted = log_status.get('total_tasks', 0)

        if self.is_process_running():
            # 进程在运行：计算正在运行的任务数
            if total_submitted > finished_tasks:
                status['running_tasks'] = total_submitted - finished_tasks
                self.logger.debug(
                    f"[Workflow {self.invocation_id}] Running tasks: "
                    f"{status['running_tasks']} = {total_submitted} submitted - {finished_tasks} finished"
                )
            # 总任务数 = 所有已提交的任务
            status['total_tasks'] = total_submitted
        else:
            # 进程不在运行：使用log和trace中的最大值
            # 这样可以显示历史数据（即使进程已结束）
            status['total_tasks'] = max(total_submitted, finished_tasks)
            if total_submitted > 0:
                self.logger.debug(
                    f"[Workflow {self.invocation_id}] Process not running, "
                    f"using historical data: {total_submitted} submitted, {finished_tasks} finished"
                )

        # 计算进度百分比
        if status['total_tasks'] > 0:
            completed = status['completed_tasks'] + status['cached_tasks']
            status['progress_percent'] = int((completed / status['total_tasks']) * 100)

        return status

    def update_invocation_step_states(self):
        """
        从workflow-trace.txt更新WorkflowInvocationStep状态

        解析trace文件中的任务状态，更新数据库中的步骤状态，
        这样前端就能显示实时的任务进度
        """
        if not self.trace_file.exists():
            self.logger.debug(f"[Workflow {self.invocation_id}] Trace file not found, skipping step state update")
            return

        try:
            sa_session = self.app.model.context
            from galaxy.model import WorkflowInvocation, WorkflowInvocationStep

            # 获取workflow invocation
            invocation = sa_session.query(WorkflowInvocation).get(self.invocation_id)
            if not invocation:
                self.logger.error(f"Workflow invocation {self.invocation_id} not found")
                return

            # 解析trace文件获取任务状态
            # trace格式: task_id hash native_id name status exit ...
            # 示例: 1 xx/xx123 job-123 NFCORE_RNASEQ:RNASEQ:FASTQC COMPLETED 0 ...
            task_states = {}  # {task_name: status}
            # Full task rows keyed by task_id for QC gate processing
            task_rows = {}  # {task_id: (task_id, process_hash, native_id, process_name, status)}

            with open(self.trace_file, 'r') as f:
                lines = f.readlines()
                # 跳过header
                for line in lines[1:]:
                    if not line.strip():
                        continue

                    parts = line.split('\t')
                    if len(parts) > 4:
                        raw_task_id = parts[0].strip()
                        process_hash = parts[1].strip()
                        task_name = parts[3].strip()  # 进程名称
                        task_status = parts[4].strip()  # COMPLETED/FAILED/RUNNING/CACHED

                        # 记录每个任务的状态（后面的覆盖前面的，取最新状态）
                        task_states[task_name] = task_status
                        task_rows[raw_task_id] = (raw_task_id, process_hash, task_name, task_status)

            # Notify QC gate handler for newly completed tasks
            if self.qc_handler:
                for task_id, (raw_id, p_hash, p_name, p_status) in task_rows.items():
                    if p_status in ("COMPLETED", "FAILED"):
                        try:
                            self.qc_handler.handle_process_completion(
                                task_id=raw_id,
                                process_name=p_name,
                                process_hash=p_hash,
                                status=p_status,
                            )
                        except Exception as qc_exc:
                            self.logger.warning(
                                f"[QC Gate] Error processing {p_name}: {qc_exc}"
                            )

            if not task_states:
                self.logger.debug(f"[Workflow {self.invocation_id}] No tasks found in trace file")
                return

            # 🔑 将Nextflow任务状态映射到Galaxy步骤状态
            # Nextflow: COMPLETED/FAILED/RUNNING/CACHED
            # Galaxy: new/scheduled/ready/error/deleted/paused/waiting
            status_mapping = {
                'COMPLETED': 'scheduled',  # 使用scheduled表示成功完成（Galaxy习惯）
                'CACHED': 'scheduled',     # cached也算成功
                'FAILED': 'error',         # 失败
                'RUNNING': 'running',      # 运行中（如果Galaxy没有running状态，用scheduled）
            }

            # 更新每个步骤的状态
            updated_count = 0
            for invocation_step in invocation.steps:
                workflow_step = invocation_step.workflow_step
                if not workflow_step:
                    continue

                # 🔑 关键：需要将Galaxy workflow step映射到Nextflow任务名称
                # 对于原生Nextflow workflow，step.label可能包含进程名称
                # 目前简化处理：根据order_index顺序匹配
                # TODO: 未来需要更精确的映射机制

                # 暂时使用简单的启发式规则
                step_label = getattr(workflow_step, 'label', None) or f"Step_{workflow_step.order_index}"

                # 尝试在task_states中找到匹配的任务
                matched_status = None
                for task_name, task_status in task_states.items():
                    # 简单匹配：如果任务名包含步骤标签，或者是唯一任务
                    if len(task_states) == 1 or step_label.upper() in task_name.upper():
                        matched_status = task_status
                        break

                if matched_status:
                    # 映射到Galaxy状态
                    galaxy_state = status_mapping.get(matched_status, 'scheduled')

                    # 只在状态改变时更新
                    if invocation_step.state != galaxy_state:
                        old_state = invocation_step.state
                        invocation_step.state = galaxy_state
                        updated_count += 1
                        self.logger.info(
                            f"[Workflow {self.invocation_id}] Updated step {workflow_step.order_index} "
                            f"state: {old_state} → {galaxy_state} (Nextflow: {matched_status})"
                        )

            # 提交更新
            if updated_count > 0:
                sa_session.commit()
                self.logger.info(
                    f"[Workflow {self.invocation_id}] Updated {updated_count} invocation step states"
                )

        except Exception as e:
            self.logger.error(f"Failed to update invocation step states: {e}")
            import traceback
            self.logger.error(traceback.format_exc())

    def _check_failure_threshold(self, status: Dict[str, int]) -> None:
        """
        检查失败任务比例，如果超过阈值则立即标记workflow为failed

        这解决了一个关键问题：
        - Nextflow进程可能卡住或异常，导致workflow永远是'scheduled'状态
        - 即使有大量任务失败，AI运维也无法触发（因为只在'failed'状态时触发）
        - 通过主动检查失败比例，我们可以及时标记workflow为failed并触发AI分析

        Args:
            status: parse_execution_status()返回的状态字典
        """
        try:
            total_tasks = status.get('total_tasks', 0)
            failed_tasks = status.get('failed_tasks', 0)

            # 需要至少有一些任务才进行判断
            if total_tasks == 0 or failed_tasks == 0:
                return

            # 计算失败比例
            failure_rate = failed_tasks / total_tasks

            # 阈值配置（可以从配置文件读取）
            FAILURE_THRESHOLD = 0.3  # 30%失败率
            MIN_FAILED_TASKS = 3     # 至少3个任务失败

            # 检查是否满足失败条件
            if failure_rate >= FAILURE_THRESHOLD and failed_tasks >= MIN_FAILED_TASKS:
                # 检查当前workflow状态
                sa_session = self.app.model.context
                invocation = sa_session.query(self.app.model.WorkflowInvocation).get(self.invocation_id)

                if not invocation:
                    return

                # 只在状态还是'scheduled'时更新（避免重复更新）
                if invocation.state == 'scheduled':
                    self.logger.warning(
                        f"[Workflow {self.invocation_id}] "
                        f"❌ 检测到高失败率: {failed_tasks}/{total_tasks} ({failure_rate*100:.1f}%) "
                        f"- 立即标记为FAILED"
                    )

                    # 更新状态为failed
                    invocation.state = 'failed'
                    invocation.update_time = datetime.now()
                    sa_session.add(invocation)
                    sa_session.commit()

                    self.logger.info(
                        f"[Workflow {self.invocation_id}] "
                        f"✅ 已将workflow状态从'scheduled'更新为'failed'，AI运维将触发分析"
                    )

                    # 标记为已完成（避免monitor继续运行）
                    self.is_completed = True
                    self.exit_code = 1

        except Exception as e:
            self.logger.error(f"Failed to check failure threshold: {e}")
            import traceback
            self.logger.error(traceback.format_exc())

    def check_workflow_completion(self) -> Tuple[bool, Optional[int]]:
        """
        检查workflow是否完成

        Returns:
            (is_completed, exit_code)
        """
        # 检查进程是否还在运行
        is_running = self.is_process_running()

        if is_running:
            return False, None

        # 进程已停止，检查退出码
        # 从 .nextflow.log 的最后几行查找退出信息
        if self.nextflow_log.exists():
            try:
                with open(self.nextflow_log, 'r') as f:
                    lines = f.readlines()
                    # 查找最后100行中的完成信息
                    for line in lines[-100:]:
                        if 'Workflow completed' in line or 'succeeded' in line.lower():
                            return True, 0
                        elif 'error' in line.lower() or 'failed' in line.lower():
                            return True, 1
            except Exception as e:
                self.logger.error(f"Failed to check completion status: {e}")

        # 如果找不到明确的状态，但进程已停止，假定完成
        return True, 0

    def update_workflow_status(self, status: str, exit_code: Optional[int] = None):
        """
        更新Galaxy中的workflow invocation状态

        Args:
            status: 新状态 (running, completed, failed)
            exit_code: 退出码
        """
        try:
            sa_session = self.app.model.context
            invocation = sa_session.query(self.app.model.WorkflowInvocation).get(self.invocation_id)

            if not invocation:
                self.logger.error(f"Workflow invocation {self.invocation_id} not found")
                return

            if status == 'completed':
                # 标记为 READY 状态（成功完成）
                self.logger.info(f"[Workflow {self.invocation_id}] Marking as completed (READY)")
                invocation.state = invocation.states.READY
            elif status == 'failed':
                self.logger.info(f"[Workflow {self.invocation_id}] Marking as failed (exit_code={exit_code})")
                invocation.fail()
            elif status == 'running':
                # 保持 SCHEDULED 状态，但更新 update_time 让用户知道还在运行
                # update_time 会在 commit 时自动更新（onupdate=now）
                self.logger.debug(f"[Workflow {self.invocation_id}] Still running, state remains SCHEDULED")
                pass

            sa_session.add(invocation)
            sa_session.commit()

        except Exception as e:
            self.logger.error(f"Failed to update workflow status: {e}")

    def monitor_once(self) -> Dict[str, any]:
        """
        执行一次监控检查

        Returns:
            监控结果（包含AI分析结果）
        """
        result = {
            'timestamp': datetime.now().isoformat(),
            'is_running': False,
            'is_completed': False,
            'logs_collected': False,
            'status': {},
            'ai_analysis': None,  # NEW: AI分析结果
            'auto_fix_applied': False,  # NEW: 是否应用了自动修复
        }

        try:
            # 1. 检查进程状态
            result['is_running'] = self.is_process_running()

            # 2. 收集日志
            logs = self.collect_logs()
            if any(logs.values()):
                self.send_logs_to_galaxy(logs)
                result['logs_collected'] = True

                # === NEW: AI智能日志分析 ===
                if self.enable_ai_ops and self.log_analyzer:
                    ai_result = self._analyze_logs_with_ai(logs)
                    result['ai_analysis'] = ai_result

                    # 如果发现错误，尝试自动修复
                    if ai_result and ai_result.get('issues'):
                        fix_result = self._attempt_auto_fix(ai_result['issues'], logs)
                        result['auto_fix_applied'] = fix_result.get('applied', False)
                        result['fix_details'] = fix_result

            # 3. 解析执行状态
            result['status'] = self.parse_execution_status()

            # 🔑 NEW: 更新WorkflowInvocationStep状态（让前端能看到任务进度）
            self.update_invocation_step_states()

            # 🆕 检查失败任务比例，及时标记workflow为failed
            self._check_failure_threshold(result['status'])

            # 4. 检查是否完成
            is_completed, exit_code = self.check_workflow_completion()
            result['is_completed'] = is_completed
            result['exit_code'] = exit_code

            if is_completed and not self.is_completed:
                # 第一次检测到完成
                self.is_completed = True
                self.exit_code = exit_code

                if exit_code == 0:
                    self.logger.info(f"[Workflow {self.invocation_id}] ✅ Completed successfully")
                    self.update_workflow_status('completed', exit_code)
                else:
                    self.logger.error(f"[Workflow {self.invocation_id}] ❌ Failed with exit code {exit_code}")
                    self.update_workflow_status('failed', exit_code)

            self.last_check_time = datetime.now()

        except Exception as e:
            self.logger.error(f"Monitor check failed: {e}")
            import traceback
            self.logger.error(traceback.format_exc())

        return result

    def _analyze_logs_with_ai(self, logs: Dict[str, List[str]]) -> Optional[Dict[str, any]]:
        """
        使用AI分析日志

        Returns:
            {
                'status': 'running|warning|error|completed',
                'progress': {...},
                'issues': [...],
                'insights': '自然语言洞察',
                'llm_cost': 0.05
            }
        """
        try:
            # 准备context
            context = {
                'invocation_id': self.invocation_id,
                'workflow_name': 'Unknown',  # TODO: 从invocation获取
                'total_steps': 0,
            }

            # 调用日志分析器
            analysis_result = self.log_analyzer.analyze_logs_stream(logs, context)

            # 转换为dict
            result_dict = analysis_result.to_dict()

            # 输出洞察（如果有）
            if analysis_result.insights:
                self.logger.info(
                    f"[Workflow {self.invocation_id}] 🤖 AI Insights: {analysis_result.insights}"
                )

            # 输出issues（如果有）
            if analysis_result.issues:
                for issue in analysis_result.issues:
                    severity_emoji = {
                        'info': 'ℹ️',
                        'warning': '⚠️',
                        'error': '❌',
                        'critical': '🚨',
                    }
                    emoji = severity_emoji.get(issue.severity.value, '❓')
                    self.logger.log(
                        logging.ERROR if issue.severity.value == 'error' else logging.WARNING,
                        f"[Workflow {self.invocation_id}] {emoji} {issue.type.value}: {issue.message[:200]}"
                    )
                    if issue.suggestion:
                        self.logger.info(f"  💡 Suggestion: {issue.suggestion[:200]}")

            # 输出成本
            if analysis_result.llm_cost > 0:
                self.logger.debug(
                    f"[Workflow {self.invocation_id}] AI analysis cost: ${analysis_result.llm_cost:.4f}"
                )

            # ⭐ NEW: 保存分析结果到文件供前端显示
            self._save_analysis_result(result_dict, analysis_result.issues)

            return result_dict

        except Exception as e:
            self.logger.error(f"AI log analysis failed: {e}")
            import traceback
            self.logger.error(traceback.format_exc())
            return None

    def _attempt_auto_fix(self, issues: List[Dict], logs: Dict[str, List[str]]) -> Dict[str, any]:
        """
        尝试自动修复检测到的问题

        🆕 现在包含完整的自动重启流程：
        1. 使用 ContainerErrorFixer 检测可修复的容器错误
        2. 生成修复计划（包含 updated_parameters）
        3. 如果可修复，使用 WorkflowRestarter 自动重启 workflow

        Returns:
            {
                'applied': True/False,
                'fix_plans': [...],
                'applied_fixes': [...],
                'pending_fixes': [...],
                'restarted': True/False,  # 🆕 是否触发了重启
                'new_invocation_id': int or None,  # 🆕 新的 invocation ID
            }
        """
        result = {
            'applied': False,
            'fix_plans': [],
            'applied_fixes': [],
            'pending_fixes': [],
            'restarted': False,
            'new_invocation_id': None,
        }

        try:
            # 🆕 Step 1: 使用 ContainerErrorFixer 检测容器错误
            from galaxy.ai.workflow_ops.autofix.fixers.container_error_fixer import ContainerErrorFixer
            from galaxy.ai.workflow_ops.autofix.base import FixContext

            container_fixer = ContainerErrorFixer()

            # 构建 FixContext
            context = FixContext(
                user_id=self.user_id,
                invocation_id=self.invocation_id,
                workflow_id=self.workflow_id,
            )
            context.metadata['sa_session'] = self.sa_session
            context.metadata['app_config'] = self.app.config

            # 检测问题
            container_issues = container_fixer.detect_issues(context)

            if not container_issues:
                self.logger.info(f"[Workflow {self.invocation_id}] No container issues detected")
                return result

            self.logger.info(f"[Workflow {self.invocation_id}] 🔍 Detected {len(container_issues)} container issues")

            # 生成修复计划
            fix_plan = container_fixer.generate_fix_plan(context, container_issues)

            if not fix_plan:
                self.logger.warning(f"[Workflow {self.invocation_id}] No fix plan generated")
                return result

            result['fix_plans'].append(fix_plan)

            # 🆕 Step 2: 如果可修复，应用修复并重启 workflow
            if fix_plan.fixable:
                self.logger.info(f"[Workflow {self.invocation_id}] 🔧 Applying auto-fix...")

                # 应用修复（保存参数到 context）
                apply_success = container_fixer.apply_fix(context, fix_plan, self.sa_session)

                if not apply_success:
                    self.logger.error(f"[Workflow {self.invocation_id}] ❌ Failed to apply fix")
                    result['pending_fixes'].append(fix_plan)
                    return result

                # 获取更新的参数
                updated_parameters = context.metadata.get('updated_parameters', {})

                if not updated_parameters:
                    self.logger.warning(f"[Workflow {self.invocation_id}] ⚠️  No parameters to update")
                    result['pending_fixes'].append(fix_plan)
                    return result

                self.logger.info(f"[Workflow {self.invocation_id}] 📝 Updated parameters: {updated_parameters}")

                # 🆕 Step 3: 使用 WorkflowRestarter 重启 workflow
                from galaxy.ai.workflow_ops.autofix.workflow_restarter import WorkflowRestarter

                restarter = WorkflowRestarter(self.app)

                self.logger.info(f"[Workflow {self.invocation_id}] 🚀 Restarting workflow with updated parameters...")

                restart_result = restarter.restart_workflow(
                    original_invocation_id=self.invocation_id,
                    updated_parameters=updated_parameters,
                    auto_start=True,
                )

                if restart_result['success']:
                    new_invocation_id = restart_result['new_invocation_id']
                    self.logger.info(
                        f"[Workflow {self.invocation_id}] ✅ Successfully restarted as invocation {new_invocation_id}"
                    )

                    result['applied'] = True
                    result['restarted'] = True
                    result['new_invocation_id'] = new_invocation_id
                    result['applied_fixes'].append(fix_plan)

                    # 保存重启信息到文件
                    self._save_restart_info(new_invocation_id, updated_parameters, fix_plan)

                    # 🆕 发送通知给用户
                    self._send_user_notification(
                        notification_type='fix_applied',
                        title='AutoFix已自动修复',
                        message=f"修复说明: {fix_plan.explanation}",
                        new_invocation_id=new_invocation_id
                    )

                else:
                    error_msg = restart_result.get('message', 'Unknown error')
                    self.logger.error(f"[Workflow {self.invocation_id}] ❌ Restart failed: {error_msg}")
                    result['pending_fixes'].append(fix_plan)

                    # 🆕 发送通知：修复失败
                    self._send_user_notification(
                        notification_type='fix_failed',
                        title='AutoFix失败',
                        message=f"修复失败: {error_msg}"
                    )

            else:
                # 不可修复，仅诊断
                self.logger.info(f"[Workflow {self.invocation_id}] ℹ️  Issue detected but not auto-fixable")
                result['pending_fixes'].append(fix_plan)

                # 🆕 发送通知：需要手动处理
                self._send_user_notification(
                    notification_type='manual_action_required',
                    title='需要手动处理',
                    message=f"检测到问题但无法自动修复: {fix_plan.explanation}"
                )

            return result

        except Exception as e:
            self.logger.error(f"[Workflow {self.invocation_id}] ❌ Auto-fix exception: {e}")
            import traceback
            self.logger.error(traceback.format_exc())
            return result

    def _save_restart_info(self, new_invocation_id: int, updated_parameters: dict, fix_plan) -> None:
        """
        保存重启信息到分析结果文件

        Args:
            new_invocation_id: 新的 invocation ID
            updated_parameters: 更新的参数
            fix_plan: 修复计划
        """
        try:
            import json
            from pathlib import Path
            from datetime import datetime

            result_dir = Path(f"database/ai_workflow_ops/analysis_results/workflow_{self.invocation_id}")
            result_dir.mkdir(parents=True, exist_ok=True)

            restart_info = {
                'original_invocation_id': self.invocation_id,
                'new_invocation_id': new_invocation_id,
                'restart_time': datetime.now().isoformat(),
                'updated_parameters': updated_parameters,
                'fix_explanation': fix_plan.explanation,
                'fix_type': fix_plan.fix_type.value if hasattr(fix_plan.fix_type, 'value') else str(fix_plan.fix_type),
            }

            restart_file = result_dir / 'restart_info.json'
            with open(restart_file, 'w', encoding='utf-8') as f:
                json.dump(restart_info, f, ensure_ascii=False, indent=2)

            self.logger.info(f"[Workflow {self.invocation_id}] 💾 Saved restart info to {restart_file}")

        except Exception as e:
            self.logger.error(f"Failed to save restart info: {e}")

    def _send_user_notification(
        self,
        notification_type: str,
        title: str,
        message: str,
        new_invocation_id: Optional[int] = None,
    ) -> None:
        """
        发送用户通知

        Args:
            notification_type: 通知类型
            title: 通知标题
            message: 通知消息
            new_invocation_id: 新的invocation ID（如果workflow被重启）
        """
        try:
            from galaxy.ai.workflow_ops.notification_service import WorkflowNotificationService

            notification_service = WorkflowNotificationService(self.app)

            details = {
                'workflow_id': self.workflow_id,
                'invocation_id': self.invocation_id,
            }

            if new_invocation_id:
                details['new_invocation_id'] = new_invocation_id

            # 简化版：直接保存到JSON文件供前端读取
            # 完整版应该使用notification_service.send_notification()
            import json
            from pathlib import Path
            from datetime import datetime

            result_dir = Path(f"database/ai_workflow_ops/analysis_results/workflow_{self.invocation_id}")
            result_dir.mkdir(parents=True, exist_ok=True)

            notification_data = {
                'type': notification_type,
                'title': title,
                'message': message,
                'timestamp': datetime.now().isoformat(),
                'read': False,
                **details
            }

            # 保存到notifications.json（前端可以轮询这个文件）
            notifications_file = result_dir / 'notifications.json'

            # 读取已有通知
            existing_notifications = []
            if notifications_file.exists():
                try:
                    with open(notifications_file, 'r', encoding='utf-8') as f:
                        existing_notifications = json.load(f)
                except:
                    pass

            # 添加新通知
            existing_notifications.append(notification_data)

            # 保存
            with open(notifications_file, 'w', encoding='utf-8') as f:
                json.dump(existing_notifications, f, ensure_ascii=False, indent=2)

            self.logger.info(f"[Workflow {self.invocation_id}] 📬 Notification sent: {title}")

        except Exception as e:
            self.logger.error(f"Failed to send notification: {e}")

    def _save_analysis_result(self, analysis_result: Dict, issues: List) -> None:
        """
        保存AI分析结果到文件，供前端UI显示

        Args:
            analysis_result: AI分析结果字典
            issues: 检测到的问题列表
        """
        try:
            import json
            from pathlib import Path
            from datetime import datetime

            # 创建保存目录
            result_dir = Path(f"database/ai_workflow_ops/analysis_results/workflow_{self.invocation_id}")
            result_dir.mkdir(parents=True, exist_ok=True)

            # 准备保存的数据（简化版，供前端显示）
            display_data = {
                'workflow_id': str(self.invocation_id),
                'timestamp': datetime.now().isoformat(),
                'status': analysis_result.get('status', 'unknown'),
                'issues_detected': []
            }

            # 转换issues为前端友好的格式
            if issues:
                for issue in issues:
                    issue_data = {
                        'type': issue.type.value if hasattr(issue, 'type') else str(issue.get('type', 'unknown')),
                        'severity': issue.severity.value if hasattr(issue, 'severity') else str(issue.get('severity', 'medium')),
                        'message': issue.message if hasattr(issue, 'message') else str(issue.get('message', '')),
                        'suggestion': issue.suggestion if hasattr(issue, 'suggestion') else issue.get('suggestion', ''),
                        'auto_fixable': getattr(issue, 'auto_fixable', False)
                    }
                    display_data['issues_detected'].append(issue_data)

            # 保存到latest.json
            latest_file = result_dir / 'latest.json'
            with open(latest_file, 'w', encoding='utf-8') as f:
                json.dump(display_data, f, ensure_ascii=False, indent=2)

            # 同时保存一个带时间戳的备份
            timestamp_file = result_dir / f"analysis_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
            with open(timestamp_file, 'w', encoding='utf-8') as f:
                json.dump(display_data, f, ensure_ascii=False, indent=2)

            self.logger.info(f"[Workflow {self.invocation_id}] ✅ 分析结果已保存: {latest_file}")

        except Exception as e:
            self.logger.error(f"Failed to save analysis result: {e}")
            import traceback
            self.logger.error(traceback.format_exc())


class NextflowMonitorService:
    """
    Nextflow监控服务

    管理所有运行中的workflow monitors
    作为单例运行，由Celery beat定期调用
    """

    _instance = None  # 单例实例

    @classmethod
    def get_instance(cls, app):
        """
        获取单例实例

        Args:
            app: Galaxy app实例

        Returns:
            NextflowMonitorService实例
        """
        if cls._instance is None:
            cls._instance = cls(app)
        return cls._instance

    def __init__(self, app):
        """
        初始化监控服务

        Args:
            app: Galaxy app实例
        """
        self.app = app
        self.logger = logging.getLogger(__name__)

        # 活跃的monitors
        self.monitors: Dict[int, NextflowMonitor] = {}

        # 配置
        self.check_interval = 10  # 检查间隔（秒）
        self.max_monitor_age = 24 * 3600  # 最大监控时长（24小时）

        # 🔑 新增：是否在启动时恢复和分析旧workflows
        # 设置环境变量 SKIP_OLD_WORKFLOW_ANALYSIS=true 可以跳过旧workflow分析，加快启动
        skip_old_analysis = os.environ.get('SKIP_OLD_WORKFLOW_ANALYSIS', 'false').lower() == 'true'

        if skip_old_analysis:
            self.logger.info("⏭️  Skipping old workflow recovery (SKIP_OLD_WORKFLOW_ANALYSIS=true)")
        else:
            # 🔑 关键修复：启动时自动恢复SCHEDULED状态的workflows
            # 这确保Galaxy重启后能继续监控运行中的workflows并正确更新其状态
            self._recover_running_workflows()
            self.logger.info("🔄 Monitor service initialized with workflow recovery enabled")

    def register_workflow(
        self,
        invocation_id: int,
        work_dir: Path,
        process_pid: int,
        enable_batch_logs: bool = True,
        qc_overrides: Optional[Dict] = None,
        workflow_domain: str = "cryo_em",
        qc_profile: Optional[str] = None,
    ) -> NextflowMonitor:
        """
        注册一个新的workflow以监控

        Args:
            invocation_id: Workflow invocation ID
            work_dir: Nextflow工作目录
            process_pid: Nextflow进程PID
            enable_batch_logs: 是否启用AWS Batch日志收集
            qc_overrides: Per-invocation QC threshold overrides (Phase 1)
            workflow_domain: Domain of the workflow for domain-specific QC gating
            qc_profile: Named QC profile (Phase 2 — Layer 3)

        Returns:
            创建的monitor实例
        """
        monitor = NextflowMonitor(
            invocation_id=invocation_id,
            work_dir=work_dir,
            process_pid=process_pid,
            app=self.app,
            enable_batch_logs=enable_batch_logs,
            qc_overrides=qc_overrides,
            workflow_domain=workflow_domain,
            qc_profile=qc_profile,
        )

        self.monitors[invocation_id] = monitor
        self.logger.info(
            f"📊 Registered monitor for workflow {invocation_id} (PID: {process_pid}, "
            f"Batch logs: {'enabled' if enable_batch_logs else 'disabled'})"
        )

        return monitor

    def unregister_workflow(self, invocation_id: int):
        """
        取消注册一个workflow

        Args:
            invocation_id: Workflow invocation ID
        """
        if invocation_id in self.monitors:
            del self.monitors[invocation_id]
            self.logger.info(f"📊 Unregistered monitor for workflow {invocation_id}")

    def get_or_create_monitor(self, invocation_id: int) -> Optional[NextflowMonitor]:
        """
        按需获取或创建monitor（用于查看历史数据）

        这是新的设计：不在启动时恢复所有workflows，而是在API请求时按需创建。
        这样避免了启动时创建大量monitors导致资源耗尽。

        Args:
            invocation_id: Workflow invocation ID

        Returns:
            Monitor实例，如果无法创建则返回None
        """
        # 如果已存在，直接返回
        if invocation_id in self.monitors:
            return self.monitors[invocation_id]

        # 尝试创建新的monitor
        try:
            # 检查workflow工作目录
            jobs_dir = Path(self.app.config.root) / 'database' / 'jobs_directory'
            work_dir = jobs_dir / 'nextflow_workflows' / f"workflow_{invocation_id}"

            if not work_dir.exists():
                self.logger.debug(f"Workflow {invocation_id} work dir not found: {work_dir}")
                return None

            # 检查是否有日志文件（说明workflow至少启动过）
            nextflow_log = work_dir / '.nextflow.log'
            if not nextflow_log.exists():
                self.logger.debug(f"Workflow {invocation_id} has no .nextflow.log")
                return None

            # 尝试获取进程PID
            pid_file = work_dir / '.nextflow.pid'
            process_pid = None
            if pid_file.exists():
                try:
                    with open(pid_file, 'r') as f:
                        process_pid = int(f.read().strip())
                    # 验证进程是否还在运行
                    try:
                        os.kill(process_pid, 0)
                    except (OSError, ProcessLookupError):
                        process_pid = None
                except Exception:
                    process_pid = None

            # 创建monitor
            monitor = NextflowMonitor(
                invocation_id=invocation_id,
                work_dir=work_dir,
                process_pid=process_pid or 0,
                app=self.app,
                enable_batch_logs=True
            )

            # 注册到monitors（但标记为按需创建，稍后会自动清理）
            self.monitors[invocation_id] = monitor
            monitor._on_demand = True  # 标记为按需创建
            monitor._last_access_time = time.time()  # 记录访问时间

            status = "running" if process_pid else "historical"
            self.logger.info(f"📊 On-demand created monitor for workflow {invocation_id} ({status})")

            return monitor

        except Exception as e:
            self.logger.warning(f"Failed to create monitor for workflow {invocation_id}: {e}")
            return None

    def monitor_all(self):
        """
        监控所有注册的workflows

        由Celery beat定期调用
        """
        if not self.monitors:
            return

        self.logger.debug(f"📊 Monitoring {len(self.monitors)} workflows...")

        completed_workflows = []

        for invocation_id, monitor in list(self.monitors.items()):
            try:
                result = monitor.monitor_once()

                if result['is_completed']:
                    completed_workflows.append(invocation_id)

            except Exception as e:
                self.logger.error(f"Failed to monitor workflow {invocation_id}: {e}")

        # 清理已完成的workflows
        for invocation_id in completed_workflows:
            self.unregister_workflow(invocation_id)

        if completed_workflows:
            self.logger.info(f"📊 Cleaned up {len(completed_workflows)} completed workflows")

    def _recover_running_workflows(self):
        """
        服务启动时，从数据库恢复正在运行的workflows

        扫描所有SCHEDULED状态的Nextflow workflows，检查：
        1. Nextflow工作目录是否存在
        2. 是否有.nextflow.log文件（说明workflow已经开始运行）
        3. 恢复monitor以继续监控

        这样即使服务重启，也能继续显示历史运行数据和当前状态
        """
        try:
            from galaxy.model import WorkflowInvocation
            from datetime import datetime, timedelta

            sa_session = self.app.model.context
            self.logger.info("🔄 Scanning database for running Nextflow workflows...")

            # 🔑 关键修复：恢复最近24小时内的SCHEDULED或FAILED workflows
            # SCHEDULED: 正在运行的workflows
            # FAILED: 可能还有Nextflow进程在运行但被误标记为failed的workflows
            # 避免恢复很久以前失败但状态卡住的workflows
            cutoff_time = datetime.now() - timedelta(hours=24)

            # 查询SCHEDULED或FAILED状态的workflows
            candidate_invocations = sa_session.query(WorkflowInvocation).filter(
                WorkflowInvocation.state.in_([
                    WorkflowInvocation.states.SCHEDULED,
                    WorkflowInvocation.states.FAILED
                ]),
                WorkflowInvocation.update_time >= cutoff_time  # 只查找最近24小时的
            ).order_by(WorkflowInvocation.update_time.desc()).all()

            self.logger.info(f"Found {len(candidate_invocations)} candidate workflows (SCHEDULED/FAILED) in database")

            # 🔑 限制恢复数量，避免资源耗尽
            MAX_RECOVER = 20  # 最多恢复20个workflows（增加限制以处理更多workflows）
            recovered_count = 0
            skipped_count = 0

            for invocation in candidate_invocations:
                try:
                    # 检查是否是Nextflow workflow
                    # Nextflow workflows的工作目录在: database/jobs_directory/nextflow_workflows/workflow_{id}/
                    # 使用 self.app.config.new_file_path 的父目录作为 base
                    jobs_dir = Path(self.app.config.root) / 'database' / 'jobs_directory'
                    work_dir_base = jobs_dir / 'nextflow_workflows'
                    work_dir = work_dir_base / f"workflow_{invocation.id}"

                    self.logger.debug(f"Checking workflow {invocation.id}: {work_dir}")

                    if not work_dir.exists():
                        self.logger.debug(f"  ❌ Work dir not found: {work_dir}")
                        continue

                    nextflow_log = work_dir / '.nextflow.log'
                    trace_file = work_dir / 'workflow-trace.txt'

                    # 只恢复已经开始运行的workflow（有日志文件）
                    if not nextflow_log.exists():
                        self.logger.debug(f"  ❌ No .nextflow.log found for workflow {invocation.id}")
                        continue

                    self.logger.info(f"  ✅ Found workflow {invocation.id} with logs, attempting recovery...")

                    # 🔑 关键修复：不再跳过旧日志的workflow！
                    # 原因：如果workflow状态是SCHEDULED但Nextflow已退出，
                    # 我们必须恢复monitor以更新workflow状态为failed/completed
                    # 否则workflow会永远卡在SCHEDULED状态
                    log_age_minutes = 0
                    try:
                        log_mtime = nextflow_log.stat().st_mtime
                        current_time = time.time()
                        time_since_update = current_time - log_mtime
                        log_age_minutes = int(time_since_update / 60)

                        if time_since_update > 1800:
                            self.logger.info(
                                f"  ⚠️  Workflow {invocation.id} log not updated for {log_age_minutes}min "
                                f"- still recovering to check final status"
                            )
                    except Exception as e:
                        self.logger.warning(f"Failed to check log mtime for workflow {invocation.id}: {e}")

                    # 🔑 限制恢复数量
                    if recovered_count >= MAX_RECOVER:
                        self.logger.info(f"  ⏭️  Skipping workflow {invocation.id} - max recover limit reached")
                        skipped_count += 1
                        continue

                    # 尝试获取Nextflow进程PID
                    # 方法1: 从.nextflow.pid文件读取（如果存在）
                    pid_file = work_dir / '.nextflow.pid'
                    process_pid = None
                    if pid_file.exists():
                        try:
                            with open(pid_file, 'r') as f:
                                process_pid = int(f.read().strip())
                            # 验证进程是否还在运行
                            try:
                                os.kill(process_pid, 0)  # 发送信号0只检查进程是否存在
                            except (OSError, ProcessLookupError):
                                # 进程不存在，但日志文件存在，可以用于读取历史数据
                                process_pid = None
                        except Exception as e:
                            self.logger.debug(f"Failed to read PID for workflow {invocation.id}: {e}")

                    # 方法2: 如果PID文件不存在，通过进程表查找（Nextflow通常不创建PID文件）
                    if process_pid is None:
                        try:
                            import subprocess
                            # 查找匹配workflow目录的Nextflow进程
                            result = subprocess.run(
                                ['ps', 'aux'],
                                capture_output=True,
                                text=True,
                                timeout=5
                            )
                            workflow_pattern = f"workflow_{invocation.id}"
                            for line in result.stdout.split('\n'):
                                if 'nextflow' in line.lower() and workflow_pattern in line:
                                    # 提取PID（第二列）
                                    parts = line.split()
                                    if len(parts) >= 2:
                                        try:
                                            found_pid = int(parts[1])
                                            # 验证进程确实存在
                                            os.kill(found_pid, 0)
                                            process_pid = found_pid
                                            self.logger.info(f"  🔍 Found Nextflow PID {process_pid} for workflow {invocation.id} via process scan")
                                            break
                                        except (ValueError, OSError, ProcessLookupError):
                                            continue
                        except Exception as e:
                            self.logger.debug(f"Failed to scan processes for workflow {invocation.id}: {e}")

                    # 恢复monitor（即使进程已结束，也恢复以显示历史数据）
                    if invocation.id not in self.monitors:
                        # 使用PID=0表示进程已结束，但我们仍然要显示历史数据
                        monitor = NextflowMonitor(
                            invocation_id=invocation.id,
                            work_dir=work_dir,
                            process_pid=process_pid or 0,  # 0表示进程已结束
                            app=self.app,
                            enable_batch_logs=True
                        )
                        self.monitors[invocation.id] = monitor
                        recovered_count += 1

                        status = "running" if process_pid else "completed/historical"
                        self.logger.info(
                            f"✅ Recovered workflow {invocation.id} ({status}) - "
                            f"log: {nextflow_log.exists()}, trace: {trace_file.exists()}"
                        )

                        # 立即执行一次监控，更新状态（不阻塞，异常不影响恢复流程）
                        try:
                            monitor.monitor_once()
                        except Exception as monitor_err:
                            self.logger.warning(f"  ⚠️  Failed to run initial monitor for workflow {invocation.id}: {monitor_err}")

                except Exception as e:
                    self.logger.warning(f"Failed to recover workflow {invocation.id}: {e}")

            if recovered_count > 0:
                self.logger.info(
                    f"🔄 Recovered {recovered_count} workflows from database "
                    f"(skipped {skipped_count}, max={MAX_RECOVER})"
                )
            else:
                self.logger.info(f"🔄 No workflows to recover (skipped {skipped_count})")

        except Exception as e:
            self.logger.error(f"Failed to recover running workflows: {e}")
            import traceback
            self.logger.error(traceback.format_exc())


# 全局监控服务实例（单例）
_monitor_service: Optional[NextflowMonitorService] = None


def get_monitor_service(app) -> NextflowMonitorService:
    """
    获取全局监控服务实例（单例模式）

    Args:
        app: Galaxy app实例

    Returns:
        监控服务实例
    """
    return NextflowMonitorService.get_instance(app)
