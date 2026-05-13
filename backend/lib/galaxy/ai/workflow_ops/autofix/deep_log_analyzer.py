"""
Deep Log Analyzer - 深度日志分析器
统一收集和整合所有 workflow 错误信息

核心功能：
1. 收集 Nextflow 主日志（nextflow.out/err）
2. 收集所有失败任务的详细日志（.command.err/.command.out）
3. 提取系统资源信息
4. 整理 workflow 配置和参数
5. 收集历史修复记录
6. 格式化为 LLM 友好的上下文
"""

import logging
import os
import re
from pathlib import Path
from typing import Dict, List, Optional, Any
from datetime import datetime

log = logging.getLogger(__name__)


class DeepLogAnalyzer:
    """深度日志分析器 - 为 LLM Universal Fixer 提供完整上下文"""

    def __init__(self, workflow_invocation_id: str, app_config=None, work_dir: Optional[str] = None):
        """
        初始化分析器

        Args:
            workflow_invocation_id: Workflow invocation ID
            app_config: Galaxy app configuration (用于获取 jobs_directory)
            work_dir: Nextflow 工作目录（可选，如果提供 app_config 则自动计算）
        """
        self.workflow_invocation_id = workflow_invocation_id

        # 从 app_config 计算 work_dir
        if work_dir:
            self.work_dir = work_dir
        elif app_config:
            from pathlib import Path
            jobs_dir = Path(app_config.jobs_directory)
            self.work_dir = str(jobs_dir / f"nextflow_workflows/workflow_{workflow_invocation_id}")
        else:
            raise ValueError("Must provide either work_dir or app_config")

        self.trace_file = os.path.join(self.work_dir, 'workflow-trace.txt')

        log.info(f"📂 DeepLogAnalyzer initialized: work_dir={self.work_dir}")

    def analyze(self) -> Dict[str, Any]:
        """
        执行深度分析，收集所有相关信息

        Returns:
            完整的上下文字典，包含所有分析结果
        """
        log.info(f"🔍 DeepLogAnalyzer: Analyzing workflow {self.workflow_invocation_id}")

        context = {
            'workflow_id': self.workflow_invocation_id,
            'timestamp': datetime.now().isoformat(),
            'analysis_version': '2.0',  # LLM-Native version
        }

        # 1. 收集 Nextflow 主日志
        log.info("  📝 Collecting Nextflow main logs...")
        context['nextflow_logs'] = self._collect_nextflow_logs()

        # 2. 收集失败任务详情
        log.info("  🔧 Collecting failed task details...")
        context['failed_tasks'] = self._collect_failed_tasks()

        # 3. 收集系统资源信息
        log.info("  💻 Collecting system resource info...")
        context['system_resources'] = self._collect_system_resources()

        # 4. 收集 workflow 配置
        log.info("  ⚙️  Collecting workflow configuration...")
        context['workflow_config'] = self._collect_workflow_config()

        # 5. 收集历史修复记录
        log.info("  📚 Collecting historical fix records...")
        context['historical_fixes'] = self._collect_historical_fixes()

        # 6. 生成摘要统计
        context['summary'] = self._generate_summary(context)

        # 🔥 关键修复：将has_errors提升到顶层，供LLMUniversalFixer直接访问
        context['has_errors'] = context['summary'].get('has_errors', False)

        log.info(f"✅ Analysis complete: {context['summary']['total_failed_tasks']} failed tasks, "
                 f"{context['summary']['total_errors']} unique errors, has_errors={context['has_errors']}")

        return context

    def _collect_nextflow_logs(self) -> Dict[str, str]:
        """收集 Nextflow 主日志"""
        logs = {}

        # nextflow.out
        out_path = os.path.join(self.work_dir, 'nextflow.out')
        if os.path.exists(out_path):
            try:
                with open(out_path, 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read()
                    # 保留最后 10000 字符（足够包含所有错误信息）
                    logs['nextflow_out'] = content[-10000:] if len(content) > 10000 else content
                    logs['nextflow_out_full_size'] = len(content)
            except Exception as e:
                log.warning(f"Failed to read nextflow.out: {e}")
                logs['nextflow_out'] = ""

        # nextflow.err
        err_path = os.path.join(self.work_dir, 'nextflow.err')
        if os.path.exists(err_path):
            try:
                with open(err_path, 'r', encoding='utf-8', errors='ignore') as f:
                    logs['nextflow_err'] = f.read()
            except Exception as e:
                log.warning(f"Failed to read nextflow.err: {e}")
                logs['nextflow_err'] = ""

        return logs

    def _collect_failed_tasks(self) -> List[Dict[str, Any]]:
        """
        收集所有失败任务的详细信息

        从 trace file 找到失败任务，然后读取其详细日志
        """
        if not os.path.exists(self.trace_file):
            log.warning(f"Trace file not found: {self.trace_file}")
            return []

        failed_tasks = []

        try:
            with open(self.trace_file, 'r') as f:
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
                'exit': header.index('exit') if 'exit' in header else None,
                'workdir': header.index('workdir') if 'workdir' in header else None,
                'cpus': header.index('cpus') if 'cpus' in header else None,
                'memory': header.index('memory') if 'memory' in header else None,
            }

            # 收集失败任务（最多前 20 个，避免信息过载）
            for line in lines[1:]:
                if len(failed_tasks) >= 20:
                    break

                fields = line.strip().split('\t')
                status_idx = indices['status']

                if status_idx and len(fields) > status_idx and fields[status_idx] == 'FAILED':
                    task_info = self._extract_task_info(fields, indices)
                    if task_info:
                        failed_tasks.append(task_info)

            log.info(f"  ✓ Collected {len(failed_tasks)} failed tasks")

        except Exception as e:
            log.error(f"Failed to parse trace file: {e}")

        return failed_tasks

    def _extract_task_info(self, fields: List[str], indices: Dict) -> Optional[Dict[str, Any]]:
        """提取单个任务的详细信息"""
        try:
            task_info = {
                'task_name': fields[indices['name']] if indices['name'] and len(fields) > indices['name'] else 'Unknown',
                'exit_code': int(fields[indices['exit']]) if indices['exit'] and len(fields) > indices['exit'] else -1,
                'cpus': fields[indices['cpus']] if indices['cpus'] and len(fields) > indices['cpus'] else 'unknown',
                'memory': fields[indices['memory']] if indices['memory'] and len(fields) > indices['memory'] else 'unknown',
            }

            # 读取工作目录中的日志
            workdir_idx = indices['workdir']
            if workdir_idx and len(fields) > workdir_idx:
                workdir = fields[workdir_idx]
                if os.path.exists(workdir):
                    # .command.err (标准错误)
                    err_path = os.path.join(workdir, '.command.err')
                    if os.path.exists(err_path):
                        with open(err_path, 'r', encoding='utf-8', errors='ignore') as f:
                            stderr = f.read()
                            # 保留最后 2000 字符
                            task_info['stderr'] = stderr[-2000:] if len(stderr) > 2000 else stderr
                            task_info['stderr_full_size'] = len(stderr)

                    # .command.out (标准输出)
                    out_path = os.path.join(workdir, '.command.out')
                    if os.path.exists(out_path):
                        with open(out_path, 'r', encoding='utf-8', errors='ignore') as f:
                            stdout = f.read()
                            # 保留最后 1000 字符
                            task_info['stdout'] = stdout[-1000:] if len(stdout) > 1000 else stdout
                            task_info['stdout_full_size'] = len(stdout)

                    # .command.sh (执行脚本)
                    sh_path = os.path.join(workdir, '.command.sh')
                    if os.path.exists(sh_path):
                        with open(sh_path, 'r', encoding='utf-8', errors='ignore') as f:
                            script = f.read()
                            # 保留最后 500 字符
                            task_info['script'] = script[-500:] if len(script) > 500 else script

            return task_info

        except Exception as e:
            log.warning(f"Failed to extract task info: {e}")
            return None

    def _collect_system_resources(self) -> Dict[str, Any]:
        """收集系统资源信息"""
        import psutil

        try:
            resources = {
                'cpu_count': psutil.cpu_count(logical=True),
                'cpu_percent': psutil.cpu_percent(interval=0.1),
                'memory_total_gb': round(psutil.virtual_memory().total / (1024**3), 2),
                'memory_available_gb': round(psutil.virtual_memory().available / (1024**3), 2),
                'memory_percent': psutil.virtual_memory().percent,
                'disk_total_gb': round(psutil.disk_usage('/').total / (1024**3), 2),
                'disk_free_gb': round(psutil.disk_usage('/').free / (1024**3), 2),
                'disk_percent': psutil.disk_usage('/').percent,
            }
        except Exception as e:
            log.warning(f"Failed to collect system resources: {e}")
            resources = {
                'cpu_count': 'unknown',
                'memory_total_gb': 'unknown',
                'disk_total_gb': 'unknown',
            }

        return resources

    def _collect_workflow_config(self) -> Dict[str, Any]:
        """收集 workflow 配置信息"""
        config = {}

        # 读取 nextflow.config
        config_path = os.path.join(self.work_dir, 'nextflow.config')
        if os.path.exists(config_path):
            try:
                with open(config_path, 'r') as f:
                    content = f.read()

                # 提取关键配置
                config['executor'] = self._extract_config_value(content, 'executor')
                config['max_cpus'] = self._extract_config_value(content, 'max_cpus')
                config['max_memory'] = self._extract_config_value(content, 'max_memory')
                config['max_time'] = self._extract_config_value(content, 'max_time')

                # 提取 params 块
                params = self._extract_params_block(content)
                config['parameters'] = params

            except Exception as e:
                log.warning(f"Failed to read nextflow.config: {e}")

        return config

    def _extract_config_value(self, content: str, key: str) -> Optional[str]:
        """从配置内容中提取值"""
        pattern = rf'{key}\s*=\s*["\']?([^"\'\n]+)["\']?'
        match = re.search(pattern, content)
        return match.group(1).strip() if match else None

    def _extract_params_block(self, content: str) -> Dict[str, str]:
        """提取 params 块中的所有参数"""
        params = {}

        # 查找 params { ... } 块
        params_match = re.search(r'params\s*\{([^}]+)\}', content, re.DOTALL)
        if params_match:
            params_block = params_match.group(1)

            # 提取每个参数
            for line in params_block.split('\n'):
                line = line.strip()
                if '=' in line and not line.startswith('//'):
                    parts = line.split('=', 1)
                    if len(parts) == 2:
                        key = parts[0].strip()
                        value = parts[1].strip().rstrip(',').strip('"\'')
                        params[key] = value

        return params

    def _collect_historical_fixes(self) -> List[Dict[str, Any]]:
        """收集历史修复记录（用于 LLM 学习）"""
        history = []

        history_dir = os.path.join(
            os.path.dirname(self.work_dir),
            '..',
            '..',
            'ai_workflow_ops',
            'autofix_history'
        )

        # 只读取最近的 5 个修复记录
        try:
            if os.path.exists(history_dir):
                files = sorted(
                    [f for f in os.listdir(history_dir) if f.endswith('_autofix.json')],
                    key=lambda x: os.path.getmtime(os.path.join(history_dir, x)),
                    reverse=True
                )[:5]

                for filename in files:
                    try:
                        import json
                        filepath = os.path.join(history_dir, filename)
                        with open(filepath, 'r') as f:
                            data = json.load(f)

                        # 提取最后一次执行的摘要
                        if data.get('executions'):
                            last_exec = data['executions'][-1]
                            history.append({
                                'workflow_id': data.get('workflow_invocation_id'),
                                'timestamp': last_exec.get('timestamp'),
                                'applied_count': last_exec.get('summary', {}).get('applied_count', 0),
                                'success': last_exec.get('summary', {}).get('applied_count', 0) > 0
                            })
                    except Exception as e:
                        log.warning(f"Failed to read history file {filename}: {e}")

        except Exception as e:
            log.warning(f"Failed to collect historical fixes: {e}")

        return history

    def _generate_summary(self, context: Dict[str, Any]) -> Dict[str, Any]:
        """生成分析摘要"""
        failed_tasks_count = len(context.get('failed_tasks', []))
        nextflow_logs = context.get('nextflow_logs', {}).get('nextflow_out', '')

        # 判断是否有错误：有失败任务或者日志中包含ERROR关键词
        has_errors = (
            failed_tasks_count > 0 or
            'ERROR' in nextflow_logs or
            'FAILED' in nextflow_logs or
            'Exception' in nextflow_logs
        )

        return {
            'total_failed_tasks': failed_tasks_count,
            'total_errors': self._count_unique_errors(context.get('failed_tasks', [])),
            'has_errors': has_errors,  # 🔥 关键修复：添加has_errors字段
            'has_nextflow_logs': bool(nextflow_logs),
            'has_system_info': bool(context.get('system_resources', {}).get('cpu_count')),
            'has_config': bool(context.get('workflow_config', {}).get('parameters')),
            'historical_fixes_count': len(context.get('historical_fixes', [])),
        }

    def _count_unique_errors(self, failed_tasks: List[Dict]) -> int:
        """统计唯一错误数量（基于 exit code 去重）"""
        exit_codes = set()
        for task in failed_tasks:
            exit_codes.add(task.get('exit_code', -1))
        return len(exit_codes)

    def format_for_llm(self, context: Dict[str, Any], max_tokens: int = 8000) -> str:
        """
        将上下文格式化为 LLM 友好的字符串（控制 token 数量）

        Args:
            context: 分析上下文
            max_tokens: 最大 token 数量（粗略估算：1 token ≈ 4 chars）

        Returns:
            格式化的上下文字符串
        """
        max_chars = max_tokens * 4

        sections = []

        # 1. 基本信息
        sections.append("## Workflow Information")
        sections.append(f"- Workflow ID: {context['workflow_id']}")
        sections.append(f"- Failed Tasks: {context['summary']['total_failed_tasks']}")
        sections.append(f"- Unique Errors: {context['summary']['total_errors']}")
        sections.append("")

        # 2. 系统资源
        resources = context.get('system_resources', {})
        sections.append("## System Resources")
        sections.append(f"- Available CPUs: {resources.get('cpu_count', 'unknown')}")
        sections.append(f"- Total Memory: {resources.get('memory_total_gb', 'unknown')} GB")
        sections.append(f"- Available Memory: {resources.get('memory_available_gb', 'unknown')} GB")
        sections.append(f"- Disk Free: {resources.get('disk_free_gb', 'unknown')} GB")
        sections.append("")

        # 3. Nextflow 主日志（精简）
        nf_logs = context.get('nextflow_logs', {})
        if nf_logs.get('nextflow_out'):
            sections.append("## Nextflow Output (last 2000 chars)")
            sections.append("```")
            sections.append(nf_logs['nextflow_out'][-2000:])
            sections.append("```")
            sections.append("")

        # 4. 失败任务详情（最多 5 个）
        failed_tasks = context.get('failed_tasks', [])[:5]
        if failed_tasks:
            sections.append("## Failed Tasks Details")
            for i, task in enumerate(failed_tasks, 1):
                sections.append(f"\n### Task {i}: {task.get('task_name', 'Unknown')}")
                sections.append(f"- Exit Code: {task.get('exit_code', -1)}")
                sections.append(f"- CPUs: {task.get('cpus', 'unknown')}")
                sections.append(f"- Memory: {task.get('memory', 'unknown')}")

                if task.get('stderr'):
                    sections.append("\n**Error Output:**")
                    sections.append("```")
                    sections.append(task['stderr'][-500:])  # 最后 500 字符
                    sections.append("```")

            sections.append("")

        # 5. Workflow 配置
        wf_config = context.get('workflow_config', {})
        if wf_config.get('parameters'):
            sections.append("## Workflow Parameters")
            for key, value in list(wf_config['parameters'].items())[:15]:  # 最多 15 个参数
                sections.append(f"- {key}: {value}")
            sections.append("")

        # 组合所有部分
        formatted = '\n'.join(sections)

        # 如果超出限制，截断
        if len(formatted) > max_chars:
            formatted = formatted[:max_chars] + "\n\n... (truncated)"

        return formatted
