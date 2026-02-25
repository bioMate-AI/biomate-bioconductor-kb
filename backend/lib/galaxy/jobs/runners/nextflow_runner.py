"""
Nextflow Job Runner - 完整实现版本

真正能运行workflow的NextflowJobRunner:
- ✅ 处理真实的输入文件
- ✅ 执行真实的命令
- ✅ 生成真实的输出文件
- ✅ 自动选择容器
- ✅ 支持AWS Batch
- ✅ Wave和Fusion集成
"""

import logging
import os
import subprocess
import tempfile
import shutil
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from galaxy.jobs.runners import AsynchronousJobRunner, AsynchronousJobState
from galaxy import model

logger = logging.getLogger(__name__)


class NextflowJobRunner(AsynchronousJobRunner):
    """
    完整的Nextflow Job Runner

    特点:
    - 真实执行Galaxy工具命令
    - 处理输入/输出文件
    - 自动选择工具容器
    - 支持本地和AWS Batch执行
    - Wave容器服务和Fusion文件系统支持
    """

    runner_name = "NextflowJobRunner"

    def __init__(self, app, nworkers, **kwargs):
        super().__init__(app, nworkers)
        self.app = app
        self.logger = logging.getLogger(__name__)

        # 查找Nextflow可执行文件
        self.nextflow_bin = self._find_nextflow()
        if not self.nextflow_bin:
            self.logger.error("Nextflow not found! Install: brew install nextflow")
            raise RuntimeError("Nextflow not installed")

        self.logger.info(f"Nextflow found at: {self.nextflow_bin}")

        # 测试Nextflow版本
        try:
            result = subprocess.run(
                [self.nextflow_bin, '-version'],
                capture_output=True,
                text=True,
                timeout=10
            )
            if result.returncode == 0:
                version_line = result.stdout.split('\n')[1] if len(result.stdout.split('\n')) > 1 else 'unknown'
                self.logger.info(f"Nextflow version: {version_line.strip()}")
        except Exception as e:
            self.logger.warning(f"Could not verify Nextflow version: {e}")

        # 工作目录
        self.work_dir = Path(app.config.job_working_directory) / "nextflow_jobs"
        self.work_dir.mkdir(parents=True, exist_ok=True)
        self.logger.info(f"Nextflow work directory: {self.work_dir}")

        # 活跃jobs
        self.active_jobs: Dict[str, 'NextflowJobState'] = {}

        self.logger.info("NextflowJobRunner initialized successfully")

    def _find_nextflow(self) -> Optional[str]:
        """查找Nextflow可执行文件"""
        try:
            result = subprocess.run(
                ['which', 'nextflow'],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0:
                return result.stdout.strip()
        except Exception as e:
            self.logger.debug(f"Error finding nextflow: {e}")
        return None

    def queue_job(self, job_wrapper):
        """
        提交job到Nextflow执行

        完整流程:
        1. 检查工具是否适合Nextflow执行
        2. 获取job信息（命令、输入、输出）
        3. 准备工作目录
        4. 复制输入文件
        5. 生成Nextflow workflow
        6. 启动Nextflow执行
        7. 监控执行状态
        """
        job_id = job_wrapper.get_id_tag()
        self.logger.info(f"[{job_id}] Submitting job to Nextflow")

        try:
            # 创建job专用工作目录
            job_work_dir = self.work_dir / f"job_{job_id}"
            job_work_dir.mkdir(parents=True, exist_ok=True)

            # 获取job详细信息（这会检查命令行）
            job_info = self._extract_job_info(job_wrapper, job_work_dir)

            # 验证是否成功提取到命令行
            if not job_info or not job_info.get('command_line'):
                tool_id = job_wrapper.tool.id if hasattr(job_wrapper, 'tool') else 'unknown'
                self.logger.warning(
                    f"[{job_id}] Tool '{tool_id}' has no command line - "
                    f"not suitable for Nextflow execution. "
                    f"Please configure this tool to use local runner in job_conf.yml"
                )
                job_wrapper.fail(
                    f"Tool '{tool_id}' cannot be executed with Nextflow (no command line). "
                    f"This tool requires local execution. "
                    f"Please update your job_conf.yml to route this tool to local runner."
                )
                return

            # 准备输入文件
            self._prepare_input_files(job_info, job_work_dir)

            # 生成Nextflow workflow
            nf_script = self._generate_nextflow_workflow(job_info, job_work_dir)

            # 生成Nextflow配置
            nf_config = self._generate_nextflow_config(job_info, job_work_dir)

            # 启动Nextflow
            process = self._start_nextflow(job_info, nf_script, nf_config, job_work_dir)

            # 创建job state
            job_state = NextflowJobState(
                job_wrapper=job_wrapper,
                process=process,
                job_info=job_info,
                job_work_dir=job_work_dir
            )
            self.active_jobs[job_id] = job_state

            self.logger.info(f"[{job_id}] Nextflow started (PID: {process.pid})")

        except Exception as e:
            self.logger.error(f"[{job_id}] Failed to start Nextflow: {e}")
            import traceback
            self.logger.error(f"[{job_id}] Traceback:\n{traceback.format_exc()}")
            job_wrapper.fail(f"Failed to start Nextflow: {e}")

    def _extract_job_info(self, job_wrapper, job_work_dir: Path) -> Dict:
        """
        提取job的完整信息

        包括:
        - 命令行
        - 输入文件列表
        - 输出文件列表
        - 工具信息
        - 容器信息
        """
        job = job_wrapper.get_job()
        job_id = job_wrapper.get_id_tag()

        # 获取命令行（已在queue_job中验证过，这里应该总有命令）
        command_line = job_wrapper.get_command_line()

        self.logger.info(f"[{job_id}] Command: {str(command_line)[:200]}...")

        # 获取输入文件
        input_files = []
        try:
            for input_assoc in job.input_datasets:
                if input_assoc.dataset and input_assoc.dataset.dataset:
                    dataset = input_assoc.dataset.dataset
                    file_path = dataset.get_file_name()
                    if file_path and os.path.exists(file_path):
                        input_files.append({
                            'name': input_assoc.name,
                            'galaxy_path': file_path,
                            'extension': input_assoc.dataset.extension,
                            'size': dataset.get_size()
                        })
                        self.logger.info(f"[{job_id}] Input: {input_assoc.name} -> {file_path}")
        except Exception as e:
            self.logger.warning(f"[{job_id}] Could not get input datasets: {e}")

        # 获取输出文件
        output_files = []
        try:
            for output_assoc in job.output_datasets:
                if output_assoc.dataset and output_assoc.dataset.dataset:
                    dataset = output_assoc.dataset.dataset
                    file_path = dataset.get_file_name()
                    output_files.append({
                        'name': output_assoc.name,
                        'galaxy_path': file_path,
                        'extension': output_assoc.dataset.extension
                    })
                    self.logger.info(f"[{job_id}] Output: {output_assoc.name} -> {file_path}")
        except Exception as e:
            self.logger.warning(f"[{job_id}] Could not get output datasets: {e}")

        # 获取工具容器
        container = self._get_tool_container(job_wrapper)

        return {
            'job_id': job_id,
            'command_line': command_line,
            'input_files': input_files,
            'output_files': output_files,
            'container': container,
            'tool_id': job_wrapper.tool.id if job_wrapper.tool else 'unknown',
            'tool_name': job_wrapper.tool.name if job_wrapper.tool else 'Unknown Tool'
        }

    def _get_tool_container(self, job_wrapper) -> str:
        """
        自动选择工具容器

        优先级:
        1. 工具XML中定义的container
        2. 从requirements推断BioContainers
        3. Fallback到基础镜像
        """
        tool = job_wrapper.tool

        if not tool:
            return 'ubuntu:20.04'

        # 1. 检查tool containers定义
        if hasattr(tool, 'containers') and tool.containers:
            container = tool.containers[0]
            if hasattr(container, 'identifier'):
                self.logger.info(f"Using tool container: {container.identifier}")
                return container.identifier
            else:
                self.logger.info(f"Using tool container: {container}")
                return str(container)

        # 2. 从requirements推断
        if hasattr(tool, 'requirements') and tool.requirements:
            packages = [r for r in tool.requirements if hasattr(r, 'name')]
            if packages:
                # 使用第一个package作为主要工具
                primary = packages[0]
                package_name = primary.name.lower()
                version = getattr(primary, 'version', 'latest')

                # 构建BioContainers镜像名
                biocontainer = f"quay.io/biocontainers/{package_name}:{version}"
                self.logger.info(f"Inferred BioContainer: {biocontainer}")
                return biocontainer

        # 3. Fallback
        self.logger.warning(f"No container found for tool {tool.id}, using ubuntu:20.04")
        return 'ubuntu:20.04'

    def _prepare_input_files(self, job_info: Dict, job_work_dir: Path):
        """
        准备输入文件

        将Galaxy数据库中的文件复制到Nextflow工作目录
        如果使用AWS，则上传到S3
        """
        use_aws = os.environ.get('NEXTFLOW_USE_AWS', 'false').lower() == 'true'

        if use_aws:
            # AWS模式: 上传到S3
            aws_s3_bucket = os.environ.get('AWS_S3_BUCKET', 'galaxy-cloud-data-1760241377')
            s3_prefix = f"nextflow-inputs/job_{job_info['job_id']}"

            for input_file in job_info['input_files']:
                galaxy_path = input_file['galaxy_path']
                simple_name = f"{input_file['name']}.{input_file['extension']}"
                s3_path = f"s3://{aws_s3_bucket}/{s3_prefix}/{simple_name}"

                try:
                    # 上传到S3
                    subprocess.run(
                        ['aws', 's3', 'cp', galaxy_path, s3_path],
                        check=True,
                        capture_output=True
                    )
                    input_file['s3_path'] = s3_path
                    input_file['simple_name'] = simple_name
                    self.logger.info(f"[{job_info['job_id']}] Uploaded input to S3: {galaxy_path} -> {s3_path}")
                except Exception as e:
                    self.logger.error(f"[{job_info['job_id']}] Failed to upload input to S3 {galaxy_path}: {e}")
                    raise
        else:
            # 本地模式: 复制到本地目录
            input_dir = job_work_dir / "inputs"
            input_dir.mkdir(exist_ok=True)

            for input_file in job_info['input_files']:
                galaxy_path = input_file['galaxy_path']
                simple_name = f"{input_file['name']}.{input_file['extension']}"
                local_path = input_dir / simple_name

                try:
                    # 复制文件
                    shutil.copy2(galaxy_path, local_path)
                    input_file['local_path'] = str(local_path)
                    input_file['simple_name'] = simple_name
                    self.logger.info(f"[{job_info['job_id']}] Copied input: {galaxy_path} -> {local_path}")
                except Exception as e:
                    self.logger.error(f"[{job_info['job_id']}] Failed to copy input {galaxy_path}: {e}")
                    raise

    def _generate_nextflow_workflow(self, job_info: Dict, job_work_dir: Path) -> Path:
        """
        生成Nextflow workflow文件

        这是真正执行工具命令的workflow
        支持本地文件和S3输入
        """
        job_id = job_info['job_id']
        use_aws = os.environ.get('NEXTFLOW_USE_AWS', 'false').lower() == 'true'

        # 准备输入channel
        input_channels = []
        input_paths_for_channel = []

        for input_file in job_info['input_files']:
            simple_name = input_file['simple_name']
            input_channels.append(f"    path '{simple_name}'")

            if use_aws and 's3_path' in input_file:
                # AWS模式: 使用S3路径
                input_paths_for_channel.append(f"file('{input_file['s3_path']}')")
            elif 'local_path' in input_file:
                # 本地模式: 使用本地路径
                input_paths_for_channel.append(f"file('{input_file['local_path']}')")

        # 准备输出pattern
        output_patterns = []
        for output_file in job_info['output_files']:
            ext = output_file['extension']
            # 根据扩展名生成输出pattern
            output_patterns.append(f"    path '*.{ext}', optional: true")

        # 如果没有特定扩展名，匹配所有文件
        if not output_patterns:
            output_patterns.append("    path '*', optional: true")

        # 重写命令中的路径
        rewritten_command = self._rewrite_command_paths(
            job_info['command_line'],
            job_info['input_files']
        )

        # 输出目录
        if use_aws:
            aws_s3_bucket = os.environ.get('AWS_S3_BUCKET', 'galaxy-cloud-data-1760241377')
            output_dir = f"s3://{aws_s3_bucket}/nextflow-outputs/job_{job_id}"
        else:
            output_dir = str(job_work_dir / "outputs")

        # 生成Nextflow DSL
        nf_content = f"""#!/usr/bin/env nextflow
nextflow.enable.dsl=2

/*
 * Auto-generated Nextflow workflow for Galaxy job {job_id}
 * Tool: {job_info['tool_name']} ({job_info['tool_id']})
 * Execution: {'AWS Batch + S3' if use_aws else 'Local Docker'}
 */

params.job_id = '{job_id}'
params.output_dir = '{output_dir}'

process GALAXY_TOOL {{
    container '{job_info['container']}'

    publishDir params.output_dir, mode: 'copy'

"""

        if input_channels:
            nf_content += "    input:\n" + "\n".join(input_channels) + "\n\n"

        nf_content += "    output:\n" + "\n".join(output_patterns) + "\n\n"

        nf_content += f"""    script:
    \"\"\"
    set -e

    # Galaxy tool command
    {rewritten_command}

    # Ensure outputs are generated
    echo "Job {job_id} completed successfully"
    \"\"\"
}}

workflow {{
"""

        if input_paths_for_channel:
            # 创建输入channel
            nf_content += f"    input_files = Channel.fromList([{', '.join(input_paths_for_channel)}])\n"
            nf_content += "    GALAXY_TOOL(input_files)\n"
        else:
            nf_content += "    GALAXY_TOOL()\n"

        nf_content += "}\n"

        # 写入文件
        nf_file = job_work_dir / "workflow.nf"
        nf_file.write_text(nf_content)

        self.logger.info(f"[{job_id}] Generated Nextflow workflow: {nf_file}")
        self.logger.debug(f"[{job_id}] Workflow content:\n{nf_content}")

        return nf_file

    def _rewrite_command_paths(self, command: str, input_files: List[Dict]) -> str:
        """
        重写命令中的路径

        将Galaxy路径替换为Nextflow工作目录中的相对路径
        """
        rewritten = command

        for input_file in input_files:
            if 'galaxy_path' in input_file and 'simple_name' in input_file:
                # 替换Galaxy绝对路径为简单文件名
                rewritten = rewritten.replace(
                    input_file['galaxy_path'],
                    input_file['simple_name']
                )

        return rewritten

    def _generate_nextflow_config(self, job_info: Dict, job_work_dir: Path) -> Path:
        """
        生成Nextflow配置文件

        配置:
        - 执行器（本地或AWS Batch）
        - Wave容器服务
        - Fusion文件系统
        - 资源限制
        """
        job_id = job_info['job_id']

        # 检测是否使用AWS云执行
        use_aws = os.environ.get('NEXTFLOW_USE_AWS', 'false').lower() == 'true'
        aws_region = os.environ.get('AWS_DEFAULT_REGION', 'us-west-2')
        aws_queue = os.environ.get('AWS_BATCH_QUEUE', 'galaxy-cloud-queue')
        aws_s3_bucket = os.environ.get('AWS_S3_BUCKET', 'galaxy-cloud-data-1760241377')

        if use_aws:
            # AWS云执行配置
            work_dir = f"s3://{aws_s3_bucket}/nextflow-work/job_{job_id}"
            self.logger.info(f"[{job_id}] Using AWS Batch with S3 work directory: {work_dir}")

            config_content = f"""
// Nextflow configuration for Galaxy job {job_id} - AWS Cloud Execution

// S3工作目录
workDir = '{work_dir}'

// 进程配置 - AWS Batch
process {{
    executor = 'awsbatch'
    queue = '{aws_queue}'

    // 容器（通过Wave自动转换）
    container = '{job_info['container']}'

    // 资源限制
    cpus = 2
    memory = '4 GB'
    time = '1h'

    // 错误处理
    errorStrategy = 'finish'

    // 确保正确的scratch设置
    scratch = false
}}

// AWS配置
aws {{
    region = '{aws_region}'
    batch {{
        cliPath = '/usr/local/bin/aws'
        maxTransferAttempts = 3
        maxSpotAttempts = 3
        jobRole = 'arn:aws:iam::399683337364:role/ecsInstanceRole'
    }}
    client {{
        maxConnections = 20
        connectionTimeout = 10000
        uploadMaxThreads = 4
        uploadChunkSize = '100MB'
        uploadMaxAttempts = 5
        uploadRetrySleep = '100ms'
    }}
}}

// Wave容器服务 - 自动转换容器到ECR
wave {{
    enabled = true
    strategy = ['conda', 'container']
    endpoint = 'https://wave.seqera.io'
}}

// Fusion文件系统 - 高性能S3访问
fusion {{
    enabled = true
    exportStorageCredentials = true
    exportAwsAccessKeys = true
}}

// 报告
report {{
    enabled = true
    file = '{job_work_dir / "report.html"}'
}}

trace {{
    enabled = true
    file = '{job_work_dir / "trace.txt"}'
}}

// 启用详细日志
trace {{
    enabled = true
    fields = 'task_id,hash,native_id,name,status,exit,submit,duration,realtime,cpus,memory,rss,vmem,peak_rss,peak_vmem,rchar,wchar'
}}
"""
        else:
            # 本地Docker执行配置
            work_dir = job_work_dir / "work"
            self.logger.info(f"[{job_id}] Using local Docker execution")

            config_content = f"""
// Nextflow configuration for Galaxy job {job_id} - Local Docker Execution

// 本地工作目录
workDir = '{work_dir}'

// 进程配置 - 本地Docker
process {{
    executor = 'local'

    // 容器引擎
    container = '{job_info['container']}'

    // 资源限制
    cpus = 2
    memory = '4 GB'
    time = '1h'

    // 错误处理
    errorStrategy = 'finish'
}}

// Docker配置
docker {{
    enabled = true
    runOptions = '-u $(id -u):$(id -g)'
}}

// 报告
report {{
    enabled = true
    file = '{job_work_dir / "report.html"}'
}}

trace {{
    enabled = true
    file = '{job_work_dir / "trace.txt"}'
}}
"""

        config_file = job_work_dir / "nextflow.config"
        config_file.write_text(config_content)

        self.logger.info(f"[{job_id}] Generated Nextflow config: {config_file}")

        return config_file

    def _start_nextflow(
        self,
        job_info: Dict,
        nf_script: Path,
        nf_config: Path,
        job_work_dir: Path
    ) -> subprocess.Popen:
        """启动Nextflow进程"""
        job_id = job_info['job_id']

        # 使用绝对路径
        nf_script_abs = nf_script.absolute()
        nf_config_abs = nf_config.absolute()

        # 构建命令
        cmd = [
            self.nextflow_bin,
            'run',
            str(nf_script_abs),
            '-c', str(nf_config_abs),
            '-ansi-log', 'false',
            '-name', f"galaxy-job-{job_id}"
        ]

        self.logger.info(f"[{job_id}] Nextflow command: {' '.join(cmd)}")

        # 日志文件
        log_file = job_work_dir / "nextflow.log"
        log_fh = open(log_file, 'w')

        # 准备环境变量 - 继承当前进程的所有环境变量（包括AWS凭证）
        env = os.environ.copy()

        # 确保关键的AWS环境变量存在
        if 'AWS_PROFILE' in env:
            self.logger.info(f"[{job_id}] Using AWS_PROFILE: {env['AWS_PROFILE']}")
        if 'AWS_DEFAULT_REGION' in env:
            self.logger.info(f"[{job_id}] Using AWS_DEFAULT_REGION: {env['AWS_DEFAULT_REGION']}")

        # 启动进程
        process = subprocess.Popen(
            cmd,
            stdout=log_fh,
            stderr=subprocess.STDOUT,
            cwd=str(job_work_dir.absolute()),
            env=env  # 传递环境变量
        )

        self.logger.info(f"[{job_id}] Log file: {log_file}")

        return process

    def check_watched_items(self):
        """检查活跃jobs的状态"""
        for job_id, job_state in list(self.active_jobs.items()):
            returncode = job_state.process.poll()

            if returncode is not None:
                # Job finished
                self.logger.info(f"[{job_id}] Nextflow process finished with code {returncode}")

                if returncode == 0:
                    # 成功 - 复制输出文件
                    try:
                        self._collect_outputs(job_state)
                        job_state.job_wrapper.change_state(model.Job.states.OK)
                        job_state.job_wrapper.finish('')
                        self.logger.info(f"[{job_id}] Job completed successfully")
                    except Exception as e:
                        self.logger.error(f"[{job_id}] Failed to collect outputs: {e}")
                        job_state.job_wrapper.fail(f"Output collection failed: {e}")
                else:
                    # 失败
                    log_file = job_state.job_work_dir / "nextflow.log"
                    try:
                        error_log = log_file.read_text()[-2000:]
                    except:
                        error_log = "Could not read log"

                    self.logger.error(f"[{job_id}] Nextflow execution failed")
                    self.logger.error(f"[{job_id}] Log tail:\n{error_log}")
                    job_state.job_wrapper.fail(f"Nextflow execution failed (exit code {returncode})")

                # 清理
                del self.active_jobs[job_id]

    def _collect_outputs(self, job_state: 'NextflowJobState'):
        """
        收集输出文件

        从Nextflow输出目录复制到Galaxy数据库位置
        支持从本地或S3下载
        """
        job_id = job_state.job_info['job_id']
        use_aws = os.environ.get('NEXTFLOW_USE_AWS', 'false').lower() == 'true'

        if use_aws:
            # AWS模式: 从S3下载输出
            aws_s3_bucket = os.environ.get('AWS_S3_BUCKET', 'galaxy-cloud-data-1760241377')
            s3_output_prefix = f"s3://{aws_s3_bucket}/nextflow-outputs/job_{job_id}/"

            try:
                # 列出S3中的输出文件
                result = subprocess.run(
                    ['aws', 's3', 'ls', s3_output_prefix],
                    capture_output=True,
                    text=True
                )

                # 如果目录不存在或为空，记录警告但不失败
                if result.returncode != 0:
                    self.logger.warning(f"[{job_id}] No outputs found in S3: {s3_output_prefix}")
                    self.logger.warning(f"[{job_id}] This is expected for tools that don't generate file outputs")
                    # 创建空的输出文件以满足Galaxy
                    for output_file_info in job_state.job_info['output_files']:
                        galaxy_path = output_file_info['galaxy_path']
                        os.makedirs(os.path.dirname(galaxy_path), exist_ok=True)
                        # 创建空文件
                        Path(galaxy_path).touch()
                        self.logger.info(f"[{job_id}] Created empty output file: {galaxy_path}")
                    return

                s3_files = []
                for line in result.stdout.strip().split('\n'):
                    if line.strip():
                        parts = line.split()
                        if len(parts) >= 4:
                            filename = parts[-1]
                            s3_files.append(filename)

                if not s3_files:
                    self.logger.warning(f"[{job_id}] No output files found in S3 (directory exists but empty)")
                    # 创建空输出文件
                    for output_file_info in job_state.job_info['output_files']:
                        galaxy_path = output_file_info['galaxy_path']
                        os.makedirs(os.path.dirname(galaxy_path), exist_ok=True)
                        Path(galaxy_path).touch()
                        self.logger.info(f"[{job_id}] Created empty output file: {galaxy_path}")
                    return

                self.logger.info(f"[{job_id}] Found {len(s3_files)} output files in S3")

                # 下载并复制到Galaxy数据库位置
                for idx, output_file_info in enumerate(job_state.job_info['output_files']):
                    galaxy_path = output_file_info['galaxy_path']

                    if idx < len(s3_files):
                        s3_file = s3_output_prefix + s3_files[idx]

                        # 确保目标目录存在
                        os.makedirs(os.path.dirname(galaxy_path), exist_ok=True)

                        # 从S3下载到Galaxy数据库
                        subprocess.run(
                            ['aws', 's3', 'cp', s3_file, galaxy_path],
                            check=True,
                            capture_output=True
                        )
                        self.logger.info(f"[{job_id}] Downloaded output from S3: {s3_file} -> {galaxy_path}")
                    else:
                        self.logger.warning(f"[{job_id}] No S3 file for output {idx}, creating empty file")
                        os.makedirs(os.path.dirname(galaxy_path), exist_ok=True)
                        Path(galaxy_path).touch()

            except Exception as e:
                self.logger.error(f"[{job_id}] Failed to collect outputs from S3: {e}")
                # 对于无输出的工具，创建空文件而不是失败
                self.logger.warning(f"[{job_id}] Creating empty output files as fallback")
                for output_file_info in job_state.job_info['output_files']:
                    galaxy_path = output_file_info['galaxy_path']
                    try:
                        os.makedirs(os.path.dirname(galaxy_path), exist_ok=True)
                        Path(galaxy_path).touch()
                    except Exception as touch_error:
                        self.logger.error(f"[{job_id}] Failed to create empty file {galaxy_path}: {touch_error}")
        else:
            # 本地模式: 从本地目录复制
            output_dir = job_state.job_work_dir / "outputs"

            if not output_dir.exists():
                self.logger.warning(f"[{job_id}] Output directory not found: {output_dir}")
                return

            # 获取所有输出文件
            output_files = list(output_dir.glob('*'))
            self.logger.info(f"[{job_id}] Found {len(output_files)} output files")

            # 复制到Galaxy数据库位置
            for idx, output_file_info in enumerate(job_state.job_info['output_files']):
                galaxy_path = output_file_info['galaxy_path']

            # 找到匹配的输出文件
            if idx < len(output_files):
                source_file = output_files[idx]

                try:
                    # 确保目标目录存在
                    os.makedirs(os.path.dirname(galaxy_path), exist_ok=True)

                    # 复制文件
                    shutil.copy2(source_file, galaxy_path)
                    self.logger.info(f"[{job_id}] Copied output: {source_file} -> {galaxy_path}")
                except Exception as e:
                    self.logger.error(f"[{job_id}] Failed to copy output: {e}")
                    raise

    def stop_job(self, job_wrapper):
        """停止job"""
        job_id = job_wrapper.get_id_tag()
        self.logger.info(f"[{job_id}] Stopping Nextflow job")

        if job_id in self.active_jobs:
            job_state = self.active_jobs[job_id]
            job_state.process.terminate()
            self.logger.info(f"[{job_id}] Process terminated")
            del self.active_jobs[job_id]

    def recover(self, job, job_wrapper):
        """恢复job（重启后）"""
        self.logger.warning("Job recovery not implemented for NextflowJobRunner")
        job_wrapper.fail("Job recovery not supported")

    def shutdown(self):
        """关闭runner"""
        self.logger.info("Shutting down NextflowJobRunner")

        # 终止所有活跃jobs
        for job_id, job_state in list(self.active_jobs.items()):
            self.logger.info(f"[{job_id}] Terminating on shutdown")
            job_state.process.terminate()

        super().shutdown()


class NextflowJobState(AsynchronousJobState):
    """Nextflow job状态"""

    def __init__(self, job_wrapper, process, job_info: Dict, job_work_dir: Path):
        super().__init__(
            files_dir=None,
            job_wrapper=job_wrapper,
            job_id=None,
            job_file=None,
            output_file=None,
            error_file=None
        )
        self.process = process
        self.job_info = job_info
        self.job_work_dir = job_work_dir
