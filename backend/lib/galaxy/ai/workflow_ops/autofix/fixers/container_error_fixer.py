"""
Container Error Fixer - Detects and fixes container runtime errors

This fixer analyzes Nextflow trace files to detect container execution errors
and provides recommendations for fixing them.

🆕 Enhanced with AWS CloudWatch log fetching to read actual container errors
"""

import logging
import os
from typing import List, Dict, Any, Optional
from pathlib import Path
from datetime import datetime

from ..base import (
    BaseAutoFixer,
    FixContext,
    RiskLevel,
)
from galaxy.ai.workflow_ops.types import FixPlan, FixAction, ActionType
try:
    from galaxy.model import WorkflowInvocation
except ImportError:
    WorkflowInvocation = None  # type: ignore[assignment,misc]

log = logging.getLogger(__name__)


class ContainerErrorFixer(BaseAutoFixer):
    """
    Fixer for container runtime errors from Nextflow workflows

    Detects issues like:
    - Container execution failures (exit code 1, 110, etc.)
    - GTF format incompatibility
    - STAR index generation errors
    - Bowtie alignment failures
    - Resource exhaustion in containers
    """

    name = "ContainerErrorFixer"
    description = "Detects and suggests fixes for container runtime errors"

    # Common error patterns and their fixes
    # 🆕 增强版：所有错误类型都支持自动修复
    ERROR_PATTERNS = {
        'GTF_FORMAT': {
            'keywords': ['FILTER_GTF', 'ICOUNT_SEG_GTF', 'gtf', 'transcript'],
            'exit_codes': [1],
            'fix_type': 'gtf_format_fix',
            'recommendation': '添加 --skip_filter_gtf 参数跳过 GTF 过滤',
            'fixable': True,  # 🆕 可自动修复
            'auto_fix_params': {'skip_filter_gtf': True},
        },
        'STAR_INDEX': {
            'keywords': ['STAR_GENOMEGENERATE', 'STAR', 'genome'],
            'exit_codes': [110, 1],
            'fix_type': 'star_index_fix',
            'recommendation': '增加STAR内存配额到32GB',
            'fixable': True,  # 🆕 可自动修复
            'auto_fix_params': {
                'max_memory': '32.GB',  # 增加内存
                'star_index_max_memory': '32000000000',  # STAR specific
            },
        },
        'BOWTIE_ALIGN': {
            'keywords': ['BOWTIE_ALIGN', 'bowtie'],
            'exit_codes': [1],
            'fix_type': 'bowtie_params_fix',
            'recommendation': '启用Bowtie敏感模式并增加重试',
            'fixable': True,  # 🆕 可自动修复
            'auto_fix_params': {
                'bowtie_mode': 'sensitive',  # 更敏感的比对模式
                'alignments': '200',  # 增加报告的比对数
                'bowtie_n_ceil': 'L,0,0.15',  # 允许更多mismatch
            },
        },
        'RESOURCE_EXHAUSTION': {
            'keywords': [],
            'exit_codes': [137, 143],  # OOM killed, terminated
            'fix_type': 'resource_increase',
            'recommendation': '增加内存到64GB和CPU到16核',
            'fixable': True,  # 🆕 可自动修复
            'auto_fix_params': {
                'max_memory': '64.GB',
                'max_cpus': 16,
            },
        },
        'NETWORK_TIMEOUT': {  # 🆕 新增网络超时错误
            'keywords': ['timeout', 'connection', 'network'],
            'exit_codes': [124, 143],
            'fix_type': 'network_retry',
            'recommendation': '增加网络超时时间和重试次数',
            'fixable': True,
            'auto_fix_params': {
                'max_retries': 5,
                'max_time': '24.h',  # 增加最大运行时间
            },
        },
        'PERMISSION_DENIED': {  # 🆕 新增权限错误
            'keywords': ['permission denied', 'access denied', 'forbidden'],
            'exit_codes': [126, 1],
            'fix_type': 'permission_fix',
            'recommendation': '更新AWS权限配置',
            'fixable': True,
            'auto_fix_params': {
                'use_fsx': True,  # 使用FSx文件系统避免权限问题
                'enable_fusion': True,  # 启用Fusion插件
            },
        },
        'DISK_SPACE': {  # 🆕 磁盘空间不足错误
            'keywords': ['no space left', 'disk full', 'enospc'],
            'exit_codes': [1, 28],  # Error 28 = ENOSPC (No space left on device)
            'fix_type': 'disk_space_fix',
            'recommendation': '增加AWS Batch容器的磁盘空间配额',
            'fixable': False,  # 需要手动修改AWS Batch配置
            'auto_fix_params': {},
            'user_guidance': '容器磁盘空间不足。建议：1) 增加AWS Batch作业定义的磁盘空间；2) 优化workflow减少中间文件；3) 使用S3直接存储大文件',
        },
    }

    def detect_issues(self, context: FixContext) -> List[Dict[str, Any]]:
        """
        Detect container errors from Nextflow trace file and error logs

        Args:
            context: Fix context

        Returns:
            List of detected container errors
        """
        sa_session = context.metadata.get('sa_session')
        if not sa_session:
            log.error("No sa_session in context metadata")
            return []

        invocation = sa_session.query(WorkflowInvocation).get(context.invocation_id)
        if not invocation:
            log.error(f"Invocation {context.invocation_id} not found")
            return []

        issues = []

        # Get Nextflow working directory
        from galaxy.config import Configuration
        config = context.metadata.get('app_config')
        if not config:
            log.warning("No app_config in metadata, cannot locate workflow directory")
            return []

        jobs_dir = Path(config.jobs_directory)
        workflow_dir = jobs_dir / f"nextflow_workflows/workflow_{context.invocation_id}"

        # 🆕 保存 workflow_dir 到 context.metadata，供 DeepAnalysisAgent 使用
        context.metadata['workflow_dir'] = str(workflow_dir)

        # Read nextflow.out for detailed error messages (legacy method)
        nextflow_out = workflow_dir / "nextflow.out"
        error_log_content = ""
        if nextflow_out.exists():
            try:
                with open(nextflow_out, 'r') as f:
                    error_log_content = f.read()
                log.info(f"Read error log from {nextflow_out} ({len(error_log_content)} chars)")
            except Exception as e:
                log.warning(f"Failed to read {nextflow_out}: {e}")

        # Fallback: Parse trace file for failed tasks
        trace_file = workflow_dir / "workflow-trace.txt"
        if not trace_file.exists():
            log.info(f"No trace file found at {trace_file}")
            return []

        # Parse trace file for failed tasks
        failed_tasks = self._parse_trace_file(trace_file)

        if not failed_tasks:
            log.info("No failed tasks found in trace file")
            return []

        log.info(f"Found {len(failed_tasks)} failed tasks")

        # 🆕 Fetch CloudWatch logs for ALL failed tasks to get comprehensive error analysis
        # 🔑 关键修复：不再限制为前5个，也不再早期返回，而是收集所有错误
        container_logs = {}
        disk_space_errors = []  # 收集所有磁盘错误
        gtf_errors = []  # 收集所有 GTF 错误
        unknown_errors = []  # 🆕 收集所有未知错误（没有匹配任何模式的）

        # 限制 CloudWatch API 调用次数，但收集所有错误类型
        max_cloudwatch_fetches = 10  # 最多获取10个任务的日志
        fetched_count = 0

        for task in failed_tasks:
            job_id = task.get('native_id')
            if job_id and fetched_count < max_cloudwatch_fetches:
                log.info(f"Fetching CloudWatch logs for task '{task['name']}' (job {job_id})...")
                logs = self._fetch_cloudwatch_logs(job_id)
                if logs:
                    container_logs[task['name']] = logs
                    log.info(f"   ✅ Fetched {len(logs)} chars of container logs")
                    fetched_count += 1

                    # 🔑 关键修改：使用标志位跟踪是否匹配到任何已知模式
                    matched_any_pattern = False

                    # Check for specific errors in CloudWatch logs (不再 return，而是收集)
                    if "Some genes in the GTF have no associated transcript entries" in logs:
                        log.info("🎯 Detected GTF transcript error in CloudWatch logs!")
                        gtf_errors.append({
                            'task_name': task['name'],
                            'exit_code': task.get('exit_code'),
                            'evidence': logs[:500],
                        })
                        matched_any_pattern = True

                    # 🆕 Check for disk space error in CloudWatch logs
                    if "No space left on device" in logs or "no space left" in logs.lower() or "disk full" in logs.lower():
                        log.info("🎯 Detected disk space error in CloudWatch logs!")
                        disk_space_errors.append({
                            'task_name': task['name'],
                            'exit_code': task.get('exit_code'),
                            'evidence': logs[:500],
                        })
                        matched_any_pattern = True

                    # 🆕 如果没有匹配任何已知模式，作为未知错误记录
                    if not matched_any_pattern:
                        log.info(f"⚠️ Unknown error pattern for task '{task['name']}' (exit code: {task.get('exit_code')})")
                        unknown_errors.append({
                            'task_name': task['name'],
                            'exit_code': task.get('exit_code'),
                            'evidence': logs[:1000],  # 多保存一些日志用于调试
                            'full_logs': logs,  # 保存完整日志
                        })

        # 🆕 添加 GTF 错误汇总（如果检测到）
        if gtf_errors:
            log.info(f"📊 GTF errors detected in {len(gtf_errors)} tasks")
            issues.append({
                'type': 'gtf_transcript_error',
                'error_category': 'GTF_FORMAT',
                'severity': 'high',
                'message': f'GTF 文件缺少 transcript-level features（影响 {len(gtf_errors)} 个任务）',
                'recommendation': '添加 --skip_filter_gtf 参数跳过 GTF 过滤',
                'fix_type': 'parameter_addition',
                'suggested_params': {'skip_filter_gtf': True},
                'fixable': True,
                'affected_tasks': [e['task_name'] for e in gtf_errors],
                'task_count': len(gtf_errors),
                'evidence': gtf_errors[0]['evidence'] if gtf_errors else '',
            })

        # 🆕 添加磁盘空间错误汇总（如果检测到）
        if disk_space_errors:
            log.info(f"📊 Disk space errors detected in {len(disk_space_errors)} tasks")
            issues.append({
                'type': 'disk_space_error',
                'error_category': 'DISK_SPACE',
                'severity': 'critical',
                'message': f'容器磁盘空间不足（影响 {len(disk_space_errors)} 个任务）',
                'recommendation': '增加AWS Batch容器的EBS卷大小到100GB',
                'fix_type': 'infrastructure_change',
                'suggested_params': {},
                'fixable': False,
                'affected_tasks': [e['task_name'] for e in disk_space_errors],
                'task_count': len(disk_space_errors),
                'evidence': disk_space_errors[0]['evidence'] if disk_space_errors else '',
                'user_guidance': '容器磁盘空间不足（当前10GB）。建议：1) 修改 Launch Template 增加 EBS 卷到 100GB；2) 使用 --save_reference false 减少中间文件；3) 联系管理员修改 AWS Batch 作业定义',
            })

        # 🆕 添加未知错误汇总（所有没有匹配已知模式的错误）
        # 🔑 关键增强：使用 LLM 自动分析未知错误
        if unknown_errors:
            log.info(f"📊 Unknown errors detected in {len(unknown_errors)} tasks - using LLM for analysis")

            # 为每个未知错误调用 LLM 分析
            for idx, err in enumerate(unknown_errors):
                # 🤖 调用 LLM 分析这个未知错误
                llm_analysis = self._analyze_unknown_error_with_llm(
                    task_name=err['task_name'],
                    exit_code=err.get('exit_code'),
                    error_logs=err['full_logs'],
                    context=context
                )

                # 根据 LLM 分析结果生成 issue
                if llm_analysis:
                    issues.append({
                        'type': 'unknown_error_analyzed',
                        'error_category': llm_analysis.get('error_category', 'UNKNOWN'),
                        'severity': llm_analysis.get('severity', 'high'),
                        'message': llm_analysis.get('message', f'未知错误：{err["task_name"]}'),
                        'recommendation': llm_analysis.get('recommendation', '请查看原始日志'),
                        'fix_type': llm_analysis.get('fix_type', 'manual_investigation'),
                        'suggested_params': llm_analysis.get('suggested_params', {}),
                        'fixable': llm_analysis.get('fixable', False),
                        'affected_tasks': [err['task_name']],
                        'task_count': 1,
                        'exit_code': err.get('exit_code'),
                        'evidence': err['evidence'],
                        'full_error_logs': err['full_logs'],
                        'llm_analysis': llm_analysis.get('analysis', ''),  # 🆕 LLM 的分析结果
                        'root_cause': llm_analysis.get('root_cause', ''),  # 🆕 根本原因
                        'user_guidance': llm_analysis.get('user_guidance', ''),
                    })
                else:
                    # LLM 分析失败，回退到原始日志
                    log.warning(f"LLM analysis failed for {err['task_name']}, using fallback")
                    issues.append({
                        'type': 'unknown_error',
                        'error_category': 'UNKNOWN',
                        'severity': 'high',
                        'message': f'未知错误：{err["task_name"]} (exit code: {err.get("exit_code", "N/A")})',
                        'recommendation': '请查看下方的原始错误日志以诊断问题',
                        'fix_type': 'manual_investigation',
                        'suggested_params': {},
                        'fixable': False,
                        'affected_tasks': [err['task_name']],
                        'task_count': 1,
                        'exit_code': err.get('exit_code'),
                        'evidence': err['evidence'],
                        'full_error_logs': err['full_logs'],
                        'user_guidance': f'此错误尚未被识别为已知模式。请查看原始容器日志：\n\n```\n{err["evidence"]}\n```\n\n完整日志可在前端展开查看。',
                    })

        # Categorize errors by pattern matching (fallback if no specific errors found)
        error_summary = self._categorize_errors(failed_tasks)

        # Generate issues for each error category
        # 🆕 现在所有错误类型都可以自动修复
        for error_type, tasks in error_summary.items():
            if error_type in self.ERROR_PATTERNS:
                pattern = self.ERROR_PATTERNS[error_type]

                # 🆕 检查是否有auto_fix_params定义
                is_fixable = pattern.get('fixable', False)
                auto_fix_params = pattern.get('auto_fix_params', {})

                issues.append({
                    'type': 'container_error',
                    'error_category': error_type,
                    'severity': 'high',
                    'affected_tasks': [t['name'] for t in tasks],
                    'task_count': len(tasks),
                    'exit_codes': list(set(t['exit_code'] for t in tasks if t.get('exit_code'))),
                    'message': f"{len(tasks)} 个容器任务失败: {error_type}",
                    'recommendation': pattern['recommendation'],
                    'fix_type': pattern['fix_type'],
                    'fixable': is_fixable,  # 🆕 使用pattern定义的fixable
                    'suggested_params': auto_fix_params if is_fixable else {},  # 🆕 添加自动修复参数
                })
                log.info(f"Detected {error_type}: {len(tasks)} tasks affected (fixable={is_fixable})")

        # 🆕 添加总体错误总结和根因分析
        if issues:
            total_failed = len(failed_tasks)
            total_issues = len(issues)

            # 统计错误类型分布
            error_types_count = {}
            fixable_count = 0
            critical_count = 0

            for issue in issues:
                error_cat = issue.get('error_category', 'UNKNOWN')
                error_types_count[error_cat] = error_types_count.get(error_cat, 0) + issue.get('task_count', 1)
                if issue.get('fixable'):
                    fixable_count += 1
                if issue.get('severity') == 'critical':
                    critical_count += 1

            # 生成根因分析
            root_causes = []
            if 'DISK_SPACE' in error_types_count:
                root_causes.append(f"磁盘空间不足（{error_types_count['DISK_SPACE']}个任务受影响）")
            if 'GTF_FORMAT' in error_types_count:
                root_causes.append(f"GTF格式不兼容（{error_types_count['GTF_FORMAT']}个任务受影响）")
            if 'STAR_INDEX' in error_types_count:
                root_causes.append(f"STAR索引构建失败（{error_types_count['STAR_INDEX']}个任务受影响）")
            if 'UNKNOWN' in error_types_count:
                root_causes.append(f"未知错误（{error_types_count['UNKNOWN']}个任务，需要查看原始日志）")

            summary_text = (
                f"检测到 {total_failed} 个失败任务，识别出 {total_issues} 类错误。"
                f"其中 {fixable_count} 类可自动修复，{critical_count} 类需要手动处理。\n\n"
                f"**根本原因**：\n" + ("\n".join(f"- {rc}" for rc in root_causes) if root_causes else "- 待分析")
            )

            log.info(f"📊 Error Summary: {summary_text}")

            # 将 summary 添加为第一个 issue（便于前端显示）
            issues.insert(0, {
                'type': 'error_summary',
                'error_category': 'SUMMARY',
                'severity': 'info',
                'message': f'Workflow 失败总结：{total_failed} 个任务失败',
                'recommendation': summary_text,
                'fix_type': 'summary',
                'fixable': False,
                'task_count': total_failed,
                'error_breakdown': error_types_count,
                'fixable_issues': fixable_count,
                'critical_issues': critical_count,
            })

        return issues

    def _parse_trace_file(self, trace_file: Path) -> List[Dict[str, Any]]:
        """
        Parse Nextflow trace file for failed tasks

        🆕 Enhanced to also extract AWS Batch job IDs (native_id) for CloudWatch log fetching
        """
        failed_tasks = []

        try:
            with open(trace_file, 'r') as f:
                lines = f.readlines()

            if not lines:
                return failed_tasks

            # Parse header to find column positions
            header = lines[0].strip().split('\t')
            col_idx = {col: i for i, col in enumerate(header)}

            # Extract failed tasks with job IDs
            for line in lines[1:]:
                parts = line.strip().split('\t')
                if len(parts) < 5:
                    continue

                status_idx = col_idx.get('status', 4)
                status = parts[status_idx] if status_idx < len(parts) else ''

                if status in ['FAILED', 'ABORTED']:
                    task = {
                        'task_id': parts[col_idx.get('task_id', 0)] if col_idx.get('task_id', 0) < len(parts) else '',
                        'name': parts[col_idx.get('name', 3)] if col_idx.get('name', 3) < len(parts) else 'unknown',
                        'status': status,
                        'exit_code': int(parts[col_idx.get('exit', 5)]) if col_idx.get('exit', 5) < len(parts) and parts[col_idx.get('exit', 5)].isdigit() else None,
                        'native_id': parts[col_idx.get('native_id', 2)] if col_idx.get('native_id', 2) < len(parts) else None,  # 🆕 AWS Batch job ID
                    }
                    failed_tasks.append(task)

        except Exception as e:
            log.error(f"Error parsing trace file: {e}")

        return failed_tasks

    def _fetch_cloudwatch_logs(self, job_id: str) -> Optional[str]:
        """
        🆕 Fetch AWS CloudWatch logs for a failed container job

        Args:
            job_id: AWS Batch job ID (UUID from trace file native_id)

        Returns:
            Container log content as string, or None if unavailable
        """
        try:
            import boto3

            # Unset AWS_PROFILE if present to force use of static keys from environment
            if 'AWS_PROFILE' in os.environ and os.environ.get('AWS_ACCESS_KEY_ID'):
                log.info("Unsetting AWS_PROFILE to use static credentials")
                del os.environ['AWS_PROFILE']

            # Create boto3 clients
            session = boto3.Session()
            batch = session.client('batch')
            logs = session.client('logs')

            # Get job details to find log stream
            log.info(f"Fetching AWS Batch job details for {job_id}...")
            response = batch.describe_jobs(jobs=[job_id])

            if not response['jobs']:
                log.warning(f"AWS Batch job {job_id} not found")
                return None

            job = response['jobs'][0]
            log_stream_name = job.get('container', {}).get('logStreamName')

            if not log_stream_name:
                log.warning(f"No CloudWatch log stream found for job {job_id}")
                return None

            log.info(f"Found log stream: {log_stream_name}")

            # Fetch logs from CloudWatch
            log_group = '/aws/batch/job'
            log_events = []
            next_token = None

            # Fetch all log events (with pagination)
            while True:
                if next_token:
                    log_response = logs.get_log_events(
                        logGroupName=log_group,
                        logStreamName=log_stream_name,
                        nextToken=next_token,
                        startFromHead=True
                    )
                else:
                    log_response = logs.get_log_events(
                        logGroupName=log_group,
                        logStreamName=log_stream_name,
                        startFromHead=True
                    )

                events = log_response.get('events', [])
                if not events:
                    break

                log_events.extend(events)

                # Check pagination
                next_forward_token = log_response.get('nextForwardToken')
                if next_forward_token == next_token:
                    break
                next_token = next_forward_token

            log.info(f"✅ Fetched {len(log_events)} log events from CloudWatch")

            # Combine log messages
            log_content = '\n'.join(event['message'] for event in log_events)
            return log_content

        except Exception as e:
            log.warning(f"Failed to fetch CloudWatch logs for job {job_id}: {e}")
            return None

    def _categorize_errors(self, failed_tasks: List[Dict[str, Any]]) -> Dict[str, List[Dict[str, Any]]]:
        """Categorize failed tasks by error type"""
        categorized = {}

        for task in failed_tasks:
            task_name = task['name'].upper()
            exit_code = task.get('exit_code')

            # Match against error patterns
            matched = False
            for error_type, pattern in self.ERROR_PATTERNS.items():
                # Check keywords
                if pattern['keywords'] and any(kw.upper() in task_name for kw in pattern['keywords']):
                    if error_type not in categorized:
                        categorized[error_type] = []
                    categorized[error_type].append(task)
                    matched = True
                    break

                # Check exit codes
                if exit_code and exit_code in pattern['exit_codes'] and not pattern['keywords']:
                    if error_type not in categorized:
                        categorized[error_type] = []
                    categorized[error_type].append(task)
                    matched = True
                    break

            # Uncategorized errors
            if not matched:
                if 'UNKNOWN' not in categorized:
                    categorized['UNKNOWN'] = []
                categorized['UNKNOWN'].append(task)

        return categorized

    def _analyze_unknown_error_with_llm(
        self,
        task_name: str,
        exit_code: Optional[int],
        error_logs: str,
        context: FixContext
    ) -> Optional[Dict[str, Any]]:
        """
        🤖 使用 LLM 深度分析未知错误（AutoFix 2.0）

        这个方法使用多轮推理的 Agent 模式来分析错误：
        1. 初步分析错误日志
        2. 主动调查（下载 S3 文件、查看参数等）
        3. 深度分析并生成修复方案
        4. 如果需要，自动生成并上传修复后的文件

        Args:
            task_name: 失败任务的名称
            exit_code: 退出码
            error_logs: 完整的容器错误日志
            context: Fix context

        Returns:
            包含分析结果的字典，或 None（如果分析失败）
        """
        try:
            # 获取 LLM client
            from galaxy.ai.workflow_ops.llm_client import UnifiedLLMClient
            llm_client = UnifiedLLMClient()

            # 🆕 AutoFix 2.0: 使用 DeepAnalysisAgent 进行多轮推理
            try:
                from ..agent import DeepAnalysisAgent
                from ..toolkit import ToolKit
                from pathlib import Path

                # 获取 workflow 目录
                workflow_dir = Path(context.metadata.get('workflow_dir', '.'))

                # 创建工具集
                app_config = context.metadata.get('app_config')
                toolkit = ToolKit(app_config, context, workflow_dir)

                # 创建 Agent
                agent = DeepAnalysisAgent(llm_client, toolkit, max_rounds=5)

                # 执行深度分析
                log.info(f"🤖 Using DeepAnalysisAgent for unknown error: {task_name}")
                result = agent.analyze(
                    task_name=task_name,
                    error_logs=error_logs,
                    exit_code=exit_code,
                    context={
                        'invocation_id': context.invocation_id,
                        'workflow_id': context.workflow_id,
                    }
                )

                if result:
                    log.info(f"✅ DeepAnalysisAgent completed: fixable={result.get('fixable', False)}")
                    return result

            except ImportError as e:
                log.warning(f"DeepAnalysisAgent not available, falling back to simple LLM analysis: {e}")
                # 回退到简单模式（下面的代码）

            # 回退：简单的单轮 LLM 分析（保留原有逻辑作为后备）

            # 构建分析提示词
            prompt = f"""你是一个 Nextflow workflow 错误诊断专家。请分析以下容器任务的失败日志，并提供详细的诊断和修复建议。

**任务信息**：
- 任务名称：{task_name}
- 退出码：{exit_code if exit_code else 'N/A'}

**容器错误日志**：
```
{error_logs[:2000]}  # 限制长度避免超出 token 限制
```

请按以下格式提供分析：

1. **错误类型**（从以下选择或创建新类型）：
   - MEMORY_ERROR (内存不足)
   - CUDA_ERROR (GPU 相关错误)
   - NETWORK_ERROR (网络/下载错误)
   - PERMISSION_ERROR (权限问题)
   - DATA_FORMAT_ERROR (数据格式错误)
   - DEPENDENCY_ERROR (依赖缺失)
   - TIMEOUT (超时)
   - 或其他你识别出的类型

2. **根本原因**（一句话总结）

3. **详细分析**（2-3句话解释发生了什么）

4. **修复建议**：
   - 是否可以通过修改 Nextflow 参数自动修复？(true/false)
   - 如果可以，建议哪些参数修改？
   - 如果不能，用户需要做什么？

5. **严重程度**（critical/high/medium/low）

请以 JSON 格式返回，例如：
{{
    "error_category": "MEMORY_ERROR",
    "root_cause": "容器内存超出限制导致进程被 OOM killer 终止",
    "analysis": "从日志可以看到 'Killed' 信号和 exit code 137，这是典型的内存不足导致的 OOM (Out Of Memory) 错误。容器尝试分配超过可用内存的空间。",
    "fixable": true,
    "suggested_params": {{"max_memory": "64.GB"}},
    "recommendation": "增加任务的内存限制到 64GB",
    "user_guidance": "此任务因内存不足而失败。建议：1) 增加 max_memory 参数；2) 如果数据量很大，考虑分批处理；3) 检查是否有内存泄漏。",
    "severity": "high"
}}

只返回 JSON，不要其他文字。"""

            # 调用 LLM
            log.info(f"🤖 Calling LLM to analyze unknown error for task: {task_name}")
            response = llm_client.call(
                messages=[{'role': 'user', 'content': prompt}],  # 🔑 正确的格式
                provider='anthropic',  # 使用 Claude
                temperature=0,  # 低温度保证稳定性
                max_tokens=1000
            )

            if not response or 'content' not in response:
                log.error("LLM returned empty response")
                return None

            # 解析 LLM 返回的 JSON
            import json
            import re

            # 🔑 关键修复：response['content'] 是 content blocks 数组，需要提取文本
            content_blocks = response['content']

            # 提取所有文本块
            text_parts = []
            for block in content_blocks:
                if isinstance(block, dict) and block.get('type') == 'text':
                    text_parts.append(block.get('text', ''))
                elif isinstance(block, str):
                    # 兼容旧版本（如果直接返回字符串）
                    text_parts.append(block)

            content = '\n'.join(text_parts)

            # 提取 JSON（可能包含在 ```json``` 代码块中）
            json_match = re.search(r'```json\s*(.*?)\s*```', content, re.DOTALL)
            if json_match:
                json_str = json_match.group(1)
            else:
                # 尝试直接解析整个响应
                json_str = content

            analysis = json.loads(json_str)

            log.info(f"✅ LLM analysis completed for {task_name}: {analysis.get('error_category', 'UNKNOWN')}")

            # 返回标准化的分析结果
            return {
                'error_category': analysis.get('error_category', 'UNKNOWN'),
                'root_cause': analysis.get('root_cause', ''),
                'analysis': analysis.get('analysis', ''),
                'fixable': analysis.get('fixable', False),
                'suggested_params': analysis.get('suggested_params', {}),
                'recommendation': analysis.get('recommendation', ''),
                'user_guidance': analysis.get('user_guidance', ''),
                'severity': analysis.get('severity', 'high'),
                'message': f"{analysis.get('error_category', '未知错误')}: {analysis.get('root_cause', task_name)}",
                'fix_type': 'parameter_adjustment' if analysis.get('fixable') else 'manual_investigation',
            }

        except Exception as e:
            log.error(f"Failed to analyze unknown error with LLM: {e}")
            import traceback
            log.error(traceback.format_exc())
            return None

    def generate_fix_plan(
        self,
        context: FixContext,
        issues: List[Dict[str, Any]]
    ) -> Optional[FixPlan]:
        """
        Generate fix plan for container errors

        Args:
            context: Fix context
            issues: Detected issues

        Returns:
            FixPlan with fix actions or diagnostic info
        """
        if not issues:
            return None

        actions = []
        fix_reason_parts = []
        is_fixable = False
        fix_type_val = None

        for issue in issues:
            error_category = issue.get('error_category', 'UNKNOWN')
            recommendation = issue.get('recommendation', '需要手动检查日志')

            # Check if this issue is auto-fixable
            if issue.get('fixable') and issue.get('suggested_params'):
                is_fixable = True
                suggested_params = issue['suggested_params']

                fix_reason_parts.append(
                    f"检测到 {error_category} 错误，建议添加参数"
                )

                # Create parameter addition action
                from galaxy.ai.workflow_ops.types import FixType
                fix_type_val = FixType.CONFIG_ADJUSTMENT  # 参数调整属于配置调整

                actions.append(FixAction(
                    action=ActionType.UPDATE_PARAM,  # 使用 UPDATE_PARAM 来添加/更新参数
                    description=f"添加参数修复 {error_category}: {recommendation}",
                    params=suggested_params,
                    risk_level='low',  # Adding safe parameters
                ))

            else:
                # Non-fixable - diagnostic only
                task_count = issue.get('task_count', 0)
                fix_reason_parts.append(
                    f"检测到 {task_count} 个 {error_category} 容器错误"
                )

                actions.append(FixAction(
                    action=ActionType.DIAGNOSTIC,
                    description=f"诊断 {error_category} 错误: {recommendation}",
                    params={
                        'error_category': error_category,
                        'affected_tasks': issue.get('affected_tasks', []),
                        'exit_codes': issue.get('exit_codes', []),
                        'recommendation': recommendation,
                    },
                    risk_level='low',
                ))

        fix_reason = "; ".join(fix_reason_parts)

        from galaxy.ai.workflow_ops.types import FixType
        if not fix_type_val:
            fix_type_val = FixType.MANUAL_INTERVENTION

        return FixPlan(
            fixable=is_fixable,
            fix_type=fix_type_val,
            fix_actions=actions,
            explanation=f"容器错误{'修复' if is_fixable else '诊断'}: {len(issues)} 个问题. {fix_reason}",
            confidence=0.9 if is_fixable else 0.7,
            estimated_success_rate=0.8 if is_fixable else 0.0,
            requires_user_confirmation=not is_fixable,  # Auto-fixable issues don't need confirmation
        )

    def apply_fix(
        self,
        context: FixContext,
        fix_plan: FixPlan,
        sa_session: Any
    ) -> 'AutoFixResult':
        """
        Apply fix - adds parameters or logs diagnostic info

        Args:
            context: Fix context
            fix_plan: Fix plan to apply
            sa_session: Database session

        Returns:
            AutoFixResult with execution outcome
        """
        from ..base import AutoFixResult, FixStatus

        if not fix_plan.fixable:
            # Diagnostic only
            log.info(f"Container error diagnostic for invocation {context.invocation_id}:")
            log.info(f"  {fix_plan.explanation}")

            for action in fix_plan.fix_actions:
                log.info(f"  Action: {action.description}")
                if action.action == ActionType.DIAGNOSTIC:
                    log.info(f"    Recommendation: {action.params.get('recommendation', 'N/A')}")
                    log.info(f"    Affected tasks: {len(action.params.get('affected_tasks', []))}")

            return AutoFixResult(
                fix_id=None,
                fixer_name="ContainerErrorFixer",
                status=FixStatus.APPLIED,
                fix_type=fix_plan.fix_type.value,
                fix_actions=fix_plan.fix_actions,
                risk_level=RiskLevel.LOW,
                success=True,
                error_message=None,
            )

        # Apply parameter fixes
        if not sa_session:
            log.error("No sa_session provided")
            return AutoFixResult(
                fix_id=None,
                fixer_name="ContainerErrorFixer",
                status=FixStatus.FAILED,
                fix_type=fix_plan.fix_type.value,
                fix_actions=fix_plan.fix_actions,
                risk_level=RiskLevel.LOW,
                success=False,
                error_message="No database session provided",
            )

        invocation = sa_session.query(WorkflowInvocation).get(context.invocation_id)
        if not invocation:
            log.error(f"Invocation {context.invocation_id} not found")
            return AutoFixResult(
                fix_id=None,
                fixer_name="ContainerErrorFixer",
                status=FixStatus.FAILED,
                fix_type=fix_plan.fix_type.value,
                fix_actions=fix_plan.fix_actions,
                risk_level=RiskLevel.LOW,
                success=False,
                error_message=f"Invocation {context.invocation_id} not found",
            )

        # Store updated parameters in context for WorkflowRestarter to use
        updated_params = context.metadata.get('updated_parameters', {})

        log.info(f"📦 ContainerErrorFixer applying fix with {len(fix_plan.fix_actions)} actions")
        for i, action in enumerate(fix_plan.fix_actions):
            log.info(f"   Action {i+1}: type={action.action}, params={action.params}")
            if action.action == ActionType.UPDATE_PARAM:
                # Add/update parameters from this action
                for param_name, param_value in action.params.items():
                    updated_params[param_name] = param_value
                    log.info(f"     ✅ Adding parameter: {param_name} = {param_value}")

        # Save updated parameters back to context
        context.metadata['updated_parameters'] = updated_params
        log.info(f"📊 Applied {len(updated_params)} parameter fixes, returning AutoFixResult with {len(fix_plan.fix_actions)} fix_actions")

        result = AutoFixResult(
            fix_id=None,
            fixer_name="ContainerErrorFixer",
            status=FixStatus.APPLIED,
            fix_type=fix_plan.fix_type.value,
            fix_actions=fix_plan.fix_actions,
            risk_level=RiskLevel.LOW,
            success=True,
            error_message=None,
        )
        log.info(f"   AutoFixResult.fix_actions count: {len(result.fix_actions)}")
        return result
