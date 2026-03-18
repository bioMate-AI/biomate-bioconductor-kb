"""
Comprehensive Log Analyzer - 三源日志整合分析器

整合分析三种日志源:
1. Galaxy 服务日志 (Galaxy server logs)
2. Nextflow 执行日志 (Nextflow execution logs)
3. 容器任务日志 (Container logs - 支持所有 executor)
   - AWS Batch: CloudWatch Logs
   - Local: work/[hash]/.command.log
   - Slurm: work/[hash]/.command.log

确保所有ERROR和WARNING都被检测到并报告
"""

import logging
import re
import os
from typing import Dict, List, Any, Optional
from pathlib import Path
from datetime import datetime

log = logging.getLogger(__name__)


class ComprehensiveLogAnalyzer:
    """三源日志综合分析器"""

    def __init__(self, workflow_id: int, invocation_id: int, app=None):
        self.workflow_id = workflow_id
        self.invocation_id = invocation_id
        self.app = app
        self.all_errors = []
        self.all_warnings = []
        self.all_issues = []

    def analyze_all_logs(self) -> Dict[str, Any]:
        """分析所有三种日志源"""
        log.info(f"\n{'='*80}")
        log.info(f"🔍 [Workflow {self.invocation_id}] 开始三源日志综合分析...")
        log.info(f"{'='*80}")

        # 先检查文件系统，看 workflow 是否真的运行过
        nextflow_dir = Path(self.app.config.data_dir) / 'jobs_directory' / 'nextflow_workflows' / f'workflow_{self.invocation_id}'
        log.info(f"📂 Nextflow 工作目录: {nextflow_dir}")

        if nextflow_dir.exists():
            log.info(f"   ✅ 目录存在")
            # 列出关键文件
            key_files = ['.nextflow.log', 'nextflow.out', 'nextflow.err', 'workflow-trace.txt']
            for fname in key_files:
                fpath = nextflow_dir / fname
                if fpath.exists():
                    size = fpath.stat().st_size
                    log.info(f"   📄 {fname}: {size} bytes")
                else:
                    log.info(f"   ❌ {fname}: 不存在")
        else:
            log.info(f"   ⚠️  目录不存在 - workflow 可能未运行")

        result = {
            'workflow_id': self.workflow_id,
            'invocation_id': self.invocation_id,
            'timestamp': datetime.now().isoformat(),
            'sources': {
                'galaxy_server': {},
                'nextflow': {},
                'containers': {}  # 🆕 改名为 containers (支持所有 executor)
            },
            'summary': {
                'total_errors': 0,
                'total_warnings': 0,
                'total_issues': 0
            },
            'all_issues': [],
            'nextflow_dir': str(nextflow_dir),
            'nextflow_dir_exists': nextflow_dir.exists()
        }

        # 1. 分析 Galaxy 服务日志
        galaxy_result = self._analyze_galaxy_server_logs()
        result['sources']['galaxy_server'] = galaxy_result

        # 2. 分析 Nextflow 日志
        nextflow_result = self._analyze_nextflow_logs()
        result['sources']['nextflow'] = nextflow_result

        # 3. 🆕 分析容器日志 (自动检测 executor 类型)
        container_result = self._analyze_container_logs()
        result['sources']['containers'] = container_result

        # 4. 汇总所有问题
        result['all_issues'] = self.all_issues
        result['summary'] = {
            'total_errors': len(self.all_errors),
            'total_warnings': len(self.all_warnings),
            'total_issues': len(self.all_issues),
            'sources_analyzed': 3,
            'errors_by_source': {
                'galaxy_server': galaxy_result.get('error_count', 0),
                'nextflow': nextflow_result.get('error_count', 0),
                'containers': container_result.get('error_count', 0)  # 🆕 改名
            }
        }

        log.info(f"[Workflow {self.invocation_id}] 三源日志分析完成: "
                 f"{result['summary']['total_errors']} errors, "
                 f"{result['summary']['total_warnings']} warnings")

        return result

    def _analyze_galaxy_server_logs(self) -> Dict[str, Any]:
        """分析 Galaxy 服务日志"""
        log.info(f"[Workflow {self.invocation_id}] 分析 Galaxy 服务日志...")

        result = {
            'source': 'galaxy_server',
            'log_file': 'gravity/log/gunicorn.log',
            'error_count': 0,
            'warning_count': 0,
            'errors': [],
            'warnings': []
        }

        try:
            # Galaxy 日志路径
            log_paths = [
                Path(self.app.config.data_dir) / 'gravity' / 'log' / 'gunicorn.log',
                Path(self.app.config.data_dir) / 'gravity' / 'log' / 'galaxy_main.log',
                Path(self.app.config.data_dir) / 'gravity' / 'log' / 'handler_main_0.log'
            ]

            for log_path in log_paths:
                if not log_path.exists():
                    continue

                log.info(f"Reading Galaxy log: {log_path}")

                # 读取最近的日志（最后 5000 行）
                lines = self._read_recent_lines(log_path, max_lines=5000)

                # 提取与当前 workflow 相关的日志
                relevant_lines = [
                    line for line in lines
                    if f'Workflow {self.invocation_id}' in line or
                       f'workflow_{self.invocation_id}' in line or
                       f'[{self.invocation_id}]' in line
                ]

                # 分析 ERROR
                for line in relevant_lines:
                    if 'ERROR' in line:
                        error_info = self._parse_log_line(line, 'ERROR')
                        if error_info:
                            result['errors'].append(error_info)
                            self.all_errors.append(error_info)
                            self.all_issues.append({
                                'severity': 'error',
                                'source': 'galaxy_server',
                                'type': 'server_error',
                                'message': error_info['message'],
                                'timestamp': error_info.get('timestamp'),
                                'evidence': line.strip()
                            })

                # 分析 WARNING
                for line in relevant_lines:
                    if 'WARNING' in line or 'WARN' in line:
                        warning_info = self._parse_log_line(line, 'WARNING')
                        if warning_info:
                            result['warnings'].append(warning_info)
                            self.all_warnings.append(warning_info)
                            self.all_issues.append({
                                'severity': 'warning',
                                'source': 'galaxy_server',
                                'type': 'server_warning',
                                'message': warning_info['message'],
                                'timestamp': warning_info.get('timestamp'),
                                'evidence': line.strip()
                            })

            result['error_count'] = len(result['errors'])
            result['warning_count'] = len(result['warnings'])

        except Exception as e:
            log.error(f"Failed to analyze Galaxy server logs: {e}")
            result['error'] = str(e)

        return result

    def _analyze_nextflow_logs(self) -> Dict[str, Any]:
        """分析 Nextflow 日志"""
        log.info(f"[Workflow {self.invocation_id}] 分析 Nextflow 日志...")

        result = {
            'source': 'nextflow',
            'log_files': [],
            'error_count': 0,
            'warning_count': 0,
            'errors': [],
            'warnings': []
        }

        try:
            # 实际的 Nextflow 工作目录路径
            # 优先从 database/jobs_directory/nextflow_workflows/ 查找
            base_dir = Path(self.app.config.data_dir)
            nextflow_dir = base_dir / 'jobs_directory' / 'nextflow_workflows' / f'workflow_{self.invocation_id}'

            if not nextflow_dir.exists():
                log.warning(f"Nextflow directory not found: {nextflow_dir}")
                result['error'] = f"Directory not found: {nextflow_dir}"
                result['searched_path'] = str(nextflow_dir)
                return result

            log.info(f"✅ Found Nextflow directory: {nextflow_dir}")

            # 分析多个 Nextflow 日志文件
            log_files = {
                'nextflow.out': nextflow_dir / 'nextflow.out',
                'nextflow.err': nextflow_dir / 'nextflow.err',
                '.nextflow.log': nextflow_dir / '.nextflow.log'
            }

            for log_name, log_path in log_files.items():
                if not log_path.exists():
                    log.debug(f"Nextflow log not found: {log_path}")
                    continue

                # 检查文件大小
                file_size = log_path.stat().st_size
                log.info(f"📄 Reading Nextflow log: {log_name} ({file_size} bytes)")
                result['log_files'].append(str(log_path))

                if file_size == 0:
                    log.debug(f"Log file {log_name} is empty")
                    continue

                lines = self._read_recent_lines(log_path, max_lines=10000)
                log.info(f"   Read {len(lines)} lines from {log_name}")

                # 分析 ERROR
                for line in lines:
                    if re.search(r'\bERROR\b|\bError\b|\bFAILED\b', line, re.IGNORECASE):
                        error_info = self._parse_nextflow_error(line)
                        if error_info:
                            result['errors'].append(error_info)
                            self.all_errors.append(error_info)
                            self.all_issues.append({
                                'severity': 'error',
                                'source': 'nextflow',
                                'type': 'nextflow_error',
                                'message': error_info['message'],
                                'file': log_name,
                                'evidence': line.strip()[:500]  # 限制长度
                            })

                # 分析 WARNING
                for line in lines:
                    if re.search(r'\bWARN\b|\bWarning\b', line, re.IGNORECASE):
                        warning_info = self._parse_nextflow_warning(line)
                        if warning_info:
                            result['warnings'].append(warning_info)
                            self.all_warnings.append(warning_info)
                            self.all_issues.append({
                                'severity': 'warning',
                                'source': 'nextflow',
                                'type': 'nextflow_warning',
                                'message': warning_info['message'],
                                'file': log_name,
                                'evidence': line.strip()[:500]  # 限制长度
                            })

            result['error_count'] = len(result['errors'])
            result['warning_count'] = len(result['warnings'])
            result['directory'] = str(nextflow_dir)

            log.info(f"✅ Nextflow logs analysis complete: {result['error_count']} errors, {result['warning_count']} warnings")

        except Exception as e:
            log.error(f"Failed to analyze Nextflow logs: {e}")
            import traceback
            traceback.print_exc()
            result['error'] = str(e)

        return result

    def _analyze_container_logs(self) -> Dict[str, Any]:
        """
        分析容器日志 (支持所有 executor)

        根据 executor 类型选择不同的日志获取策略:
        - AWS Batch: CloudWatch Logs (原有实现)
        - Local: work/[hash]/.command.log
        - Slurm: work/[hash]/.command.log
        """
        log.info(f"[Workflow {self.invocation_id}] 🔍 开始容器日志分析...")

        # 1. 检测 executor 类型
        executor = self._detect_executor()
        log.info(f"📋 Detected executor: {executor}")

        # 2. 根据 executor 选择日志获取器
        if executor == 'awsbatch':
            return self._analyze_aws_batch_logs()
        elif executor == 'local':
            return self._analyze_local_container_logs()
        elif executor == 'slurm':
            return self._analyze_slurm_container_logs()
        else:
            # 未知 executor，尝试使用 Local 方法（fallback）
            log.warning(f"Unknown executor '{executor}', trying local log analysis as fallback")
            return self._analyze_local_container_logs()

    def _analyze_local_container_logs(self) -> Dict[str, Any]:
        """分析 Local executor 的容器日志 - 从 work/[hash]/.command.log 读取"""
        log.info(f"[Workflow {self.invocation_id}] 分析 Local 容器日志...")

        result = {
            'source': 'local_containers',
            'tasks_analyzed': 0,
            'error_count': 0,
            'warning_count': 0,
            'errors': [],
            'warnings': []
        }

        try:
            # 1. 从 trace 文件获取失败的任务
            base_dir = Path(self.app.config.data_dir)
            nextflow_dir = base_dir / 'jobs_directory' / 'nextflow_workflows' / f'workflow_{self.invocation_id}'
            trace_file = nextflow_dir / 'workflow-trace.txt'

            if not trace_file.exists():
                log.warning(f"Trace file not found: {trace_file}")
                result['error'] = f"Trace file not found: {trace_file}"
                return result

            failed_tasks = self._extract_failed_tasks_from_trace(trace_file)

            if not failed_tasks:
                log.info("No failed tasks found in trace file")
                result['message'] = "No failed tasks found"
                return result

            # 2. 对每个失败任务，读取 work 目录下的日志
            for task in failed_tasks[:10]:  # 限制最多分析 10 个任务
                task_hash = task['hash']
                task_name = task['name']

                # work 目录结构: work/[前2位]/[完整hash]/
                work_dir = nextflow_dir / 'work' / task_hash[:2] / task_hash

                if not work_dir.exists():
                    log.debug(f"Work directory not found: {work_dir}")
                    continue

                # 读取 .command.log (主日志)
                log_file = work_dir / '.command.log'
                if log_file.exists():
                    try:
                        with open(log_file, 'r', encoding='utf-8', errors='ignore') as f:
                            log_lines = f.readlines()

                        log.info(f"   Analyzing {len(log_lines)} lines from task {task_name} (hash: {task_hash[:8]}...)")

                        # 分析日志行
                        for line in log_lines:
                            # 检测 ERROR
                            if re.search(r'\bERROR\b|\bError\b|\bFailed\b|\bFAILED\b', line, re.IGNORECASE):
                                error_info = {
                                    'task_name': task_name,
                                    'task_hash': task_hash,
                                    'message': line.strip()[:500],
                                    'timestamp': datetime.now().isoformat()
                                }
                                result['errors'].append(error_info)
                                self.all_errors.append(error_info)
                                self.all_issues.append({
                                    'severity': 'error',
                                    'source': 'local_container',
                                    'type': 'container_error',
                                    'message': line.strip()[:300],
                                    'task_name': task_name,
                                    'task_hash': task_hash,
                                    'evidence': line.strip()[:500]
                                })

                            # 检测 WARNING
                            if re.search(r'\bWARN\b|\bWarning\b', line, re.IGNORECASE):
                                warning_info = {
                                    'task_name': task_name,
                                    'task_hash': task_hash,
                                    'message': line.strip()[:500],
                                    'timestamp': datetime.now().isoformat()
                                }
                                result['warnings'].append(warning_info)
                                self.all_warnings.append(warning_info)
                                self.all_issues.append({
                                    'severity': 'warning',
                                    'source': 'local_container',
                                    'type': 'container_warning',
                                    'message': line.strip()[:300],
                                    'task_name': task_name,
                                    'task_hash': task_hash,
                                    'evidence': line.strip()[:500]
                                })

                        result['tasks_analyzed'] += 1

                    except Exception as e:
                        log.error(f"Failed to read log file {log_file}: {e}")
                else:
                    log.debug(f"Log file not found: {log_file}")

            result['error_count'] = len(result['errors'])
            result['warning_count'] = len(result['warnings'])

            log.info(f"✅ Local container logs analysis complete: {result['tasks_analyzed']} tasks analyzed, "
                    f"{result['error_count']} errors, {result['warning_count']} warnings")

        except Exception as e:
            log.error(f"Failed to analyze local container logs: {e}")
            import traceback
            traceback.print_exc()
            result['error'] = str(e)

        return result

    def _analyze_slurm_container_logs(self) -> Dict[str, Any]:
        """分析 Slurm executor 的容器日志 - 从 work/[hash]/.command.log 读取"""
        log.info(f"[Workflow {self.invocation_id}] 分析 Slurm 容器日志...")

        # Slurm 的日志结构与 Local 相同，都在 work/[hash]/.command.log
        # 复用 Local 的实现
        result = self._analyze_local_container_logs()

        # 修改 source 标识
        if 'source' in result:
            result['source'] = 'slurm_containers'

        # 更新 issues 中的 source
        for issue in self.all_issues:
            if issue.get('source') == 'local_container':
                issue['source'] = 'slurm_container'

        return result

    def _analyze_aws_batch_logs(self) -> Dict[str, Any]:
        """分析 AWS Batch 日志 - 从 workflow-trace.txt 获取 job IDs，然后从 CloudWatch 拉取日志"""
        log.info(f"[Workflow {self.invocation_id}] 分析 AWS Batch 日志...")

        result = {
            'source': 'aws_batch',
            'log_streams': [],
            'error_count': 0,
            'warning_count': 0,
            'errors': [],
            'warnings': [],
            'jobs_analyzed': 0
        }

        try:
            # 1. 从 Nextflow trace 文件获取 AWS Batch Job IDs
            base_dir = Path(self.app.config.data_dir)
            nextflow_dir = base_dir / 'jobs_directory' / 'nextflow_workflows' / f'workflow_{self.invocation_id}'
            trace_file = nextflow_dir / 'workflow-trace.txt'

            if not trace_file.exists():
                log.warning(f"Trace file not found: {trace_file}")
                result['error'] = f"Trace file not found: {trace_file}"
                return result

            log.info(f"✅ Found trace file: {trace_file}")

            # 2. 解析 trace 文件获取 job IDs
            job_ids = self._extract_batch_job_ids_from_trace(trace_file)
            log.info(f"📋 Found {len(job_ids)} AWS Batch jobs from trace file")

            if not job_ids:
                log.info("No AWS Batch jobs found in trace file")
                result['message'] = "No AWS Batch jobs found"
                return result

            # 3. 使用 AWSLogsFetcher 获取日志
            try:
                from galaxy.ai.workflow_ops.aws_logs_fetcher import AWSLogsFetcher

                # 检查 AWS 配置
                import os
                region = os.getenv('AWS_REGION', 'us-east-1')
                fetcher = AWSLogsFetcher(region_name=region)

                if not fetcher.available:
                    log.warning("AWS CloudWatch client not available")
                    result['error'] = "AWS CloudWatch client not available"
                    return result

                # 4. 为每个 job 获取日志
                for job_id in job_ids[:10]:  # 限制最多分析 10 个任务
                    log.info(f"   Fetching logs for job: {job_id}")

                    # 获取日志流信息
                    stream_info = fetcher.get_batch_job_log_stream(job_id)
                    if not stream_info:
                        log.debug(f"No log stream found for job {job_id}")
                        continue

                    # 获取日志内容
                    log_lines = fetcher.fetch_logs_from_cloudwatch(
                        log_group=stream_info['log_group'],
                        log_stream=stream_info['log_stream'],
                        max_lines=1000
                    )

                    if not log_lines:
                        log.debug(f"No logs found for job {job_id}")
                        continue

                    result['log_streams'].append(stream_info['log_stream'])
                    result['jobs_analyzed'] += 1

                    log.info(f"   Analyzing {len(log_lines)} lines from job {job_id}")

                    # 5. 分析日志行
                    for line in log_lines:
                        # 检测 ERROR
                        if re.search(r'\bERROR\b|\bError\b|\bFailed\b|\bFAILED\b', line, re.IGNORECASE):
                            error_info = {
                                'job_id': job_id,
                                'message': line.strip()[:500],
                                'timestamp': datetime.now().isoformat()
                            }
                            result['errors'].append(error_info)
                            self.all_errors.append(error_info)
                            self.all_issues.append({
                                'severity': 'error',
                                'source': 'aws_batch',
                                'type': 'batch_error',
                                'message': line.strip()[:300],
                                'job_id': job_id,
                                'evidence': line.strip()[:500]
                            })

                        # 检测 WARNING
                        if re.search(r'\bWARN\b|\bWarning\b', line, re.IGNORECASE):
                            warning_info = {
                                'job_id': job_id,
                                'message': line.strip()[:500],
                                'timestamp': datetime.now().isoformat()
                            }
                            result['warnings'].append(warning_info)
                            self.all_warnings.append(warning_info)
                            self.all_issues.append({
                                'severity': 'warning',
                                'source': 'aws_batch',
                                'type': 'batch_warning',
                                'message': line.strip()[:300],
                                'job_id': job_id,
                                'evidence': line.strip()[:500]
                            })

            except ImportError as e:
                log.warning(f"AWSLogsFetcher not available: {e}")
                result['error'] = "AWS Logs Fetcher module not available"
                return result

            result['error_count'] = len(result['errors'])
            result['warning_count'] = len(result['warnings'])

            log.info(f"✅ AWS Batch logs analysis complete: {result['jobs_analyzed']} jobs analyzed, "
                    f"{result['error_count']} errors, {result['warning_count']} warnings")

        except Exception as e:
            log.error(f"Failed to analyze AWS Batch logs: {e}")
            import traceback
            traceback.print_exc()
            result['error'] = str(e)

        return result

    def _detect_executor(self) -> str:
        """
        从 nextflow.config 检测 executor 类型

        Returns:
            'awsbatch', 'local', 'slurm' 或 'unknown'
        """
        nextflow_dir = Path(self.app.config.data_dir) / 'jobs_directory' / 'nextflow_workflows' / f'workflow_{self.invocation_id}'
        config_file = nextflow_dir / 'nextflow.config'

        if not config_file.exists():
            log.warning(f"Config file not found: {config_file}")
            return 'unknown'

        try:
            with open(config_file, 'r', encoding='utf-8') as f:
                content = f.read()

            # 查找 executor = '...' 配置
            match = re.search(r"executor\s*=\s*['\"](\w+)['\"]", content)
            if match:
                executor = match.group(1).lower()
                log.info(f"✅ Detected executor: {executor}")
                return executor
            else:
                log.warning("Could not find executor configuration in nextflow.config")
                return 'unknown'

        except Exception as e:
            log.error(f"Failed to detect executor from {config_file}: {e}")
            return 'unknown'

    def _extract_failed_tasks_from_trace(self, trace_file: Path) -> List[Dict[str, str]]:
        """
        从 workflow-trace.txt 提取失败的任务信息

        Returns:
            [{'name': 'task_name', 'hash': 'abc123...', 'status': 'FAILED', 'task_id': '1'}, ...]
        """
        tasks = []

        try:
            with open(trace_file, 'r', encoding='utf-8') as f:
                lines = f.readlines()

            if len(lines) < 2:
                return tasks

            # 解析表头
            header = lines[0].strip().split('\t')
            try:
                task_id_idx = header.index('task_id')
                hash_idx = header.index('hash')
                name_idx = header.index('name')
                status_idx = header.index('status')
            except ValueError as e:
                log.warning(f"Required column not found in trace file: {e}")
                return tasks

            # 提取失败的任务
            for line in lines[1:]:
                parts = line.strip().split('\t')
                if len(parts) <= max(task_id_idx, hash_idx, name_idx, status_idx):
                    continue

                status = parts[status_idx].strip()
                if status in ['FAILED', 'ABORTED']:
                    task_hash = parts[hash_idx].strip()
                    if task_hash and task_hash != '-':
                        tasks.append({
                            'task_id': parts[task_id_idx].strip(),
                            'hash': task_hash,
                            'name': parts[name_idx].strip(),
                            'status': status
                        })

            log.info(f"📋 Extracted {len(tasks)} failed tasks from trace file")
            return tasks

        except Exception as e:
            log.error(f"Failed to extract failed tasks from trace: {e}")
            return tasks

    def _extract_batch_job_ids_from_trace(self, trace_file: Path) -> List[str]:
        """从 Nextflow trace 文件中提取 AWS Batch Job IDs"""
        job_ids = []
        try:
            with open(trace_file, 'r') as f:
                lines = f.readlines()

            if len(lines) < 2:
                return job_ids

            # 解析表头找到 native_id 和 status 列的索引
            header = lines[0].strip().split('\t')
            try:
                native_id_idx = header.index('native_id')
                status_idx = header.index('status')
            except ValueError as e:
                log.warning(f"Required column not found in trace file: {e}")
                return job_ids

            # 只提取失败任务的 native_id（即 AWS Batch Job IDs）
            for line in lines[1:]:
                parts = line.strip().split('\t')
                if len(parts) > max(native_id_idx, status_idx):
                    native_id = parts[native_id_idx].strip()
                    status = parts[status_idx].strip()
                    # 只收集失败的任务，AWS Batch Job ID 格式: UUID
                    if status == 'FAILED' and native_id and native_id != '-' and len(native_id) > 10 and '-' in native_id:
                        job_ids.append(native_id)

            log.info(f"Extracted {len(job_ids)} job IDs from trace file")
            return job_ids

        except Exception as e:
            log.error(f"Failed to extract job IDs from trace file: {e}")
            return job_ids

    def _read_recent_lines(self, file_path: Path, max_lines: int = 5000) -> List[str]:
        """读取文件最后 N 行"""
        try:
            with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                lines = f.readlines()
                return lines[-max_lines:]  # 返回最后 N 行
        except Exception as e:
            log.error(f"Failed to read file {file_path}: {e}")
            return []

    def _parse_log_line(self, line: str, level: str) -> Optional[Dict[str, Any]]:
        """解析 Galaxy 日志行"""
        # 格式: 2026-01-11 16:40:41,654 ERROR    module message
        match = re.match(r'(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2},\d{3})\s+(\w+)\s+([\w.]+)\s+(.+)', line)
        if match:
            return {
                'timestamp': match.group(1),
                'level': match.group(2),
                'module': match.group(3),
                'message': match.group(4).strip()
            }
        return {'message': line.strip()}

    def _parse_nextflow_error(self, line: str) -> Optional[Dict[str, Any]]:
        """解析 Nextflow 错误行"""
        return {
            'message': line.strip(),
            'timestamp': datetime.now().isoformat()
        }

    def _parse_nextflow_warning(self, line: str) -> Optional[Dict[str, Any]]:
        """解析 Nextflow 警告行"""
        return {
            'message': line.strip(),
            'timestamp': datetime.now().isoformat()
        }

    def persist_logs(self, analysis_result: Dict[str, Any]) -> str:
        """持久化分析结果"""
        try:
            # 保存到分析结果目录
            output_dir = Path(self.app.config.data_dir) / 'ai_workflow_ops' / 'comprehensive_logs' / f'workflow_{self.invocation_id}'
            output_dir.mkdir(parents=True, exist_ok=True)

            timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
            output_file = output_dir / f'comprehensive_analysis_{timestamp}.json'

            import json
            with open(output_file, 'w', encoding='utf-8') as f:
                json.dump(analysis_result, f, indent=2, ensure_ascii=False)

            log.info(f"Comprehensive log analysis saved to: {output_file}")
            return str(output_file)

        except Exception as e:
            log.error(f"Failed to persist logs: {e}")
            return ""
