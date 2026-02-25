"""
Nextflow Workflow Job Runner

工作流级别的Nextflow集成
将整个Galaxy Workflow作为单个Nextflow任务提交
"""

import json
import logging
import os
import subprocess
import time
from pathlib import Path
from typing import Dict, List, Any, Optional

from galaxy.jobs.runners import AsynchronousJobRunner, AsynchronousJobState
from galaxy.jobs.runners.nextflow_workflow_converter import GalaxyToNextflowConverter
from galaxy.jobs.runners.nextflow_s3_manager import NextflowS3Manager
from galaxy.jobs.runners.nextflow_cloud_data_manager import CloudDataManager
from galaxy.jobs.runners.nextflow_monitor import get_monitor_service
from galaxy.jobs.runners.nextflow_remote_executor import NextflowRemoteExecutor

log = logging.getLogger(__name__)


class NextflowWorkflowState(AsynchronousJobState):
    """
    Nextflow工作流执行状态

    跟踪整个workflow的执行，而不是单个job
    """

    def __init__(self, invocation, process, work_dir, topology, step_mappings, remote_exec_info=None):
        super().__init__()
        self.invocation = invocation
        self.process = process
        self.work_dir = work_dir
        self.topology = topology
        self.step_mappings = step_mappings

        # 步骤状态跟踪
        self.step_states = {}  # {step_id: 'pending'|'running'|'completed'|'failed'}
        for step_id in step_mappings.keys():
            self.step_states[step_id] = 'pending'

        # 输出收集
        self.collected_outputs = {}

        # 远程执行信息（如果使用远程执行模式）
        self.remote_exec_info = remote_exec_info  # {remote_workspace, screen_name/pid, status, ...}


class NextflowWorkflowJobRunner(AsynchronousJobRunner):
    """
    工作流级别的Nextflow Job Runner

    核心功能:
    1. 接收整个WorkflowInvocation
    2. 转换为Nextflow脚本
    3. 提交到AWS Batch执行
    4. 监控所有步骤状态
    5. 收集所有输出
    """

    runner_name = "NextflowWorkflowRunner"

    def __init__(self, app, nworkers, **kwargs):
        """初始化Workflow Runner"""
        super().__init__(app, nworkers, **kwargs)

        self.logger = logging.getLogger(__name__)

        # 工作目录
        self.work_dir = Path(app.config.jobs_directory) / "nextflow_workflows"
        self.work_dir.mkdir(parents=True, exist_ok=True)

        # 转换器 - 读取环境变量决定使用方案A还是方案B-3
        env_value = os.environ.get('USE_GALAXY_IN_CONTAINER', '')
        use_galaxy_in_container = env_value.lower() in ('true', '1', 'yes')
        self.logger.error(f"🔧🔧🔧 ENV DEBUG: USE_GALAXY_IN_CONTAINER='{env_value}' -> use_galaxy_in_container={use_galaxy_in_container}")
        self.logger.error(f"🔧🔧🔧 ALL AWS ENV: AWS_PROFILE={os.environ.get('AWS_PROFILE')}, AWS_S3_BUCKET={os.environ.get('AWS_S3_BUCKET')}")

        # ⭐⭐⭐ 使用 Host-CLI 模式（真正的终极方案）⭐⭐⭐
        # 原理: 在LaunchTemplate UserData中预装AWS CLI到宿主机隔离目录
        # 然后挂载到容器的完全不同名的路径,避开Nextflow volumes解析bug
        # 核心优势:
        #   1. UserData在宿主机启动时安装AWS CLI到 /opt/aws-cli-mount
        #   2. 挂载到容器的 /opt/aws-cli-container (完全不同名,避开Nextflow bug)
        #   3. 100% 兼容 BioContainers（不覆盖/usr目录）
        #   4. 不依赖beforeScript,避免鸡生蛋死锁
        #   5. 完全自主可控，不依赖第三方公司(WAVE)
        self.s3_transfer_mode = 'host-cli'
        self.logger.info(f"🚀 S3 Transfer Mode: {self.s3_transfer_mode} (Host-CLI with UserData + Non-overlapping Paths)")

        self.converter = GalaxyToNextflowConverter(
            app,
            use_galaxy_in_container=use_galaxy_in_container
        )

        # 🆕 Nextflow Executor 配置
        # 支持三种执行器: awsbatch, local, slurm
        self.nextflow_executor = os.environ.get('NEXTFLOW_EXECUTOR', 'awsbatch').lower()
        if self.nextflow_executor not in ['awsbatch', 'local', 'slurm']:
            self.logger.warning(f"Invalid NEXTFLOW_EXECUTOR '{self.nextflow_executor}', defaulting to 'awsbatch'")
            self.nextflow_executor = 'awsbatch'
        self.logger.info(f"🚀 Nextflow Executor: {self.nextflow_executor}")

        # AWS配置（awsbatch 模式需要）
        self.aws_region = os.environ.get('AWS_DEFAULT_REGION', 'us-west-2')
        self.aws_batch_queue = os.environ.get('AWS_BATCH_QUEUE', 'galaxy-cloud-queue')
        self.aws_s3_bucket = os.environ.get('AWS_S3_BUCKET', '')

        # 🆕 Slurm 配置（slurm 模式需要）
        self.slurm_partition = os.environ.get('SLURM_PARTITION', 'compute')
        self.slurm_qos = os.environ.get('SLURM_QOS', 'normal')
        self.slurm_account = os.environ.get('SLURM_ACCOUNT', '')

        # S3文件传输模式配置已经在上面设置（传给converter了）
        # 静态AWS CLI配置（仅在static-cli模式下使用）
        self.static_aws_cli_path = os.environ.get('NEXTFLOW_STATIC_AWS_CLI_PATH', '/mnt/efs/aws-cli-static')

        # S3数据管理器
        if self.aws_s3_bucket:
            self.s3_manager = NextflowS3Manager(
                s3_bucket=self.aws_s3_bucket,
                aws_region=self.aws_region
            )
            self.logger.info(f"S3 Manager initialized for bucket: {self.aws_s3_bucket}")
        else:
            self.s3_manager = None
            self.logger.warning("S3 bucket not configured, S3 operations will be skipped")

        # Cloud数据管理器(云原生数据流 - 数据不回传本地)
        try:
            self.cloud_data_manager = CloudDataManager(
                app=app,
                bucket=self.aws_s3_bucket
            )
            # 云原生模式开关(默认启用)
            self.cloud_native_mode = os.environ.get('NEXTFLOW_CLOUD_NATIVE', 'true').lower() == 'true'
            self.logger.info(f"Cloud-native mode: {'ENABLED' if self.cloud_native_mode else 'DISABLED'}")
        except Exception as e:
            self.logger.warning(f"Failed to initialize CloudDataManager: {e}")
            self.cloud_data_manager = None
            self.cloud_native_mode = False

        # Nextflow可执行文件
        self.nextflow_bin = self._find_nextflow()

        # 活跃的工作流
        self.active_workflows = {}  # {invocation_id: NextflowWorkflowState}

        # 监控服务（用于日志收集）
        self.monitor_service = get_monitor_service(app)

        # 是否启用AWS Batch日志收集（默认启用）
        self.enable_batch_logs = os.environ.get('NEXTFLOW_ENABLE_BATCH_LOGS', 'true').lower() == 'true'

        # 远程执行器配置（在 AWS/服务器上运行 Nextflow 主进程）
        remote_config = {
            'enabled': os.environ.get('NEXTFLOW_REMOTE_EXECUTION', 'false').lower() == 'true',
            'host': os.environ.get('NEXTFLOW_REMOTE_HOST', ''),
            'user': os.environ.get('NEXTFLOW_REMOTE_USER', 'ec2-user'),
            'ssh_key': os.environ.get('NEXTFLOW_REMOTE_SSH_KEY', ''),
            'workspace_dir': os.environ.get('NEXTFLOW_REMOTE_WORKSPACE', '/home/ec2-user/nextflow_workspaces'),
            'use_screen': os.environ.get('NEXTFLOW_REMOTE_USE_SCREEN', 'true').lower() == 'true',
            'nextflow_bin': os.environ.get('NEXTFLOW_REMOTE_BIN', '/usr/local/bin/nextflow'),
            'sync_method': os.environ.get('NEXTFLOW_REMOTE_SYNC_METHOD', 'rsync'),
        }

        # 初始化远程执行器
        try:
            self.remote_executor = NextflowRemoteExecutor(remote_config)
        except Exception as e:
            if remote_config['enabled']:
                # 如果配置了远程执行但初始化失败，这是严重错误
                self.logger.error(f"Failed to initialize remote executor: {e}")
                raise
            else:
                # 未配置远程执行，失败是正常的
                self.remote_executor = None

        self.logger.info(f"NextflowWorkflowJobRunner initialized")
        self.logger.info(f"  Work directory: {self.work_dir}")
        self.logger.info(f"  AWS Batch queue: {self.aws_batch_queue}")
        self.logger.info(f"  AWS S3 bucket: {self.aws_s3_bucket}")
        self.logger.info(f"  Batch logs enabled: {self.enable_batch_logs}")
        self.logger.info(f"  Remote execution: {'ENABLED' if (self.remote_executor and self.remote_executor.enabled) else 'DISABLED'}")

    def _find_nextflow(self) -> str:
        """查找Nextflow可执行文件"""
        nextflow_path = subprocess.run(
            ['which', 'nextflow'],
            capture_output=True,
            text=True
        ).stdout.strip()

        if not nextflow_path:
            raise RuntimeError("Nextflow not found in PATH")

        self.logger.info(f"Nextflow found at: {nextflow_path}")
        return nextflow_path

    def queue_workflow(self, workflow_invocation):
        """
        提交整个工作流到Nextflow

        这是主入口，替代了原来的逐个job提交
        """
        invocation_id = workflow_invocation.id
        self.logger.info(f"[Workflow {invocation_id}] Submitting workflow to Nextflow")

        try:
            # 1. 转换workflow为Nextflow脚本
            conversion_result = self.converter.convert_workflow(workflow_invocation)

            # 2. 创建工作目录
            workflow_work_dir = self.work_dir / f"workflow_{invocation_id}"
            workflow_work_dir.mkdir(parents=True, exist_ok=True)

            # 3. 保存Nextflow脚本
            nf_script_path = workflow_work_dir / "workflow.nf"
            with open(nf_script_path, 'w') as f:
                f.write(conversion_result['nextflow_script'])

            self.logger.info(f"[Workflow {invocation_id}] Nextflow script saved to {nf_script_path}")

            # 4. 准备输入数据
            input_params = self._prepare_workflow_inputs(
                workflow_invocation, workflow_work_dir
            )

            # 5. 生成Nextflow配置
            nf_config_path = self._generate_nextflow_config(
                workflow_invocation, workflow_work_dir, input_params
            )

            # 6. 启动Nextflow执行
            process = self._start_nextflow_workflow(
                nf_script_path,
                nf_config_path,
                input_params,
                workflow_work_dir
            )

            # 7. 创建workflow状态
            workflow_state = NextflowWorkflowState(
                invocation=workflow_invocation,
                process=process,
                work_dir=workflow_work_dir,
                topology=conversion_result['topology'],
                step_mappings=conversion_result['step_mappings']
            )

            self.active_workflows[invocation_id] = workflow_state

            self.logger.info(
                f"[Workflow {invocation_id}] Nextflow started (PID: {process.pid})"
            )

            # 8. 注册到监控服务（用于日志收集）
            try:
                monitor = self.monitor_service.register_workflow(
                    invocation_id=invocation_id,
                    work_dir=workflow_work_dir,
                    process_pid=process.pid,
                    enable_batch_logs=self.enable_batch_logs
                )
                self.logger.info(
                    f"[Workflow {invocation_id}] Registered to monitor service "
                    f"(Batch logs: {'enabled' if self.enable_batch_logs else 'disabled'})"
                )
            except Exception as e:
                self.logger.warning(
                    f"[Workflow {invocation_id}] Failed to register monitor: {e}. "
                    f"Log collection will not be available."
                )

            return workflow_state

        except Exception as e:
            self.logger.error(f"[Workflow {invocation_id}] Failed to submit: {e}")
            import traceback
            self.logger.error(f"[Workflow {invocation_id}] Traceback:\n{traceback.format_exc()}")
            raise

    def run_native_nextflow(self, workflow_invocation):
        """
        直接运行上传的原生Nextflow工作流（不经过转换）

        用于从Nextflow zip包上传生成的workflow
        这些workflow已经有 "native-execution" 标签

        工作流程:
        1. 从Engine节点的tool_id提取Nextflow包信息
        2. 定位到上传的Nextflow包目录
        3. 准备输入参数（从workflow input获取）
        4. 直接运行Nextflow包的main.nf

        返回:
            NextflowWorkflowState: 工作流状态
        """
        invocation_id = workflow_invocation.id
        workflow = workflow_invocation.workflow

        self.logger.info(f"🚀 [Workflow {invocation_id}] Starting NATIVE Nextflow execution")

        try:
            # 1. 找到Engine节点（第一个使用nextflow tool的节点）
            engine_step = None

            # 调试：打印所有步骤
            self.logger.info(f"[Workflow {invocation_id}] Workflow has {len(workflow.steps)} steps:")
            for i, step in enumerate(workflow.steps):
                self.logger.info(f"  Step {i}: type={step.type}, tool_id={step.tool_id}, label={getattr(step, 'label', None)}")

            for step in workflow.steps:
                if step.tool_id:
                    # 检查tool_id中是否包含nextflow相关的名称
                    # 可能的tool_id: "rnaseq", "nfcore_rnaseq", "nextflow_rnaseq" 等
                    if ('nextflow' in step.tool_id.lower() and 'extractor' not in step.tool_id.lower()) or \
                       (step.type == 'tool' and 'extractor' not in step.tool_id.lower()):
                        # 对于Engine & Satellites模式，Engine节点的tool_id就是pipeline名称
                        # 比如 "rnaseq", "atacseq" 等
                        engine_step = step
                        self.logger.info(f"[Workflow {invocation_id}] Found potential Engine step: {step.tool_id}")
                        break

            if not engine_step:
                raise ValueError(
                    f"Cannot find Engine step in workflow {workflow.id}. "
                    f"Native execution requires an Engine node with Nextflow tool. "
                    f"Workflow has {len(workflow.steps)} steps, check logs for details."
                )

            tool_id = engine_step.tool_id
            self.logger.info(f"[Workflow {invocation_id}] Found Engine step: {tool_id}")

            # 调试：打印engine_step的可用属性
            self.logger.debug(f"[Workflow {invocation_id}] Engine step type: {type(engine_step)}")
            self.logger.debug(f"[Workflow {invocation_id}] Engine step attributes: {[attr for attr in dir(engine_step) if not attr.startswith('_')][:20]}")

            # 2. 从tool_id推断Nextflow包位置
            # tool_id 格式: "rnaseq", "atacseq" 等
            # Nextflow包存储在: database/objects/nextflow_pipelines/{tool_id}_{timestamp}/
            # 我们需要找到最新的包（通过查找tool对应的XML获取确切路径）

            # 方案A: 从tool XML读取包路径（最准确）
            nextflow_package_path = self._get_nextflow_package_path(tool_id)

            if not nextflow_package_path or not Path(nextflow_package_path).exists():
                raise FileNotFoundError(
                    f"Nextflow package not found for tool {tool_id}. "
                    f"Expected path: {nextflow_package_path}"
                )

            self.logger.info(f"[Workflow {invocation_id}] Nextflow package: {nextflow_package_path}")

            # 3. 创建工作目录
            workflow_work_dir = self.work_dir / f"workflow_{invocation_id}"
            workflow_work_dir.mkdir(parents=True, exist_ok=True)

            # 4. 准备输入参数（从workflow invocation获取）
            input_params = self._prepare_native_workflow_inputs(
                workflow_invocation, engine_step
            )

            # 5. 生成Nextflow配置（使用标准AWS Batch配置）
            # 传递 input_params 以便配置生成器能根据参数调整配置
            # 传递 engine_step 以便能提取 tool XML 中的默认值
            nf_config_path = self._generate_nextflow_config(
                workflow_invocation, workflow_work_dir, input_params, engine_step
            )

            # 6. 启动Nextflow执行（直接运行main.nf）
            nf_script_path = Path(nextflow_package_path) / "main.nf"

            # 🔑 决定是否使用 test profile
            # 优先从用户参数中读取 use_test_profile（Galaxy UI 中的复选框）
            use_test_profile = input_params.pop('use_test_profile', 'false').lower() in ['true', '1', 'yes']

            if use_test_profile:
                self.logger.info(
                    f"[Workflow {workflow_invocation.id}] User enabled test profile - "
                    f"will use pipeline's built-in test data"
                )
            else:
                self.logger.info(
                    f"[Workflow {workflow_invocation.id}] Test profile disabled - "
                    f"using user-provided inputs"
                )
            result = self._start_nextflow_workflow(
                invocation_id,
                nf_script_path,
                nf_config_path,
                input_params,
                workflow_work_dir,
                use_test_profile=use_test_profile,
                engine_step=engine_step
            )

            # 处理返回结果（本地或远程执行）
            if isinstance(result, dict) and 'remote_exec_info' in result:
                # 远程执行
                process = None
                remote_exec_info = result['remote_exec_info']
                self.logger.info(
                    f"🎉 [Workflow {invocation_id}] NATIVE Nextflow started successfully "
                    f"(REMOTE mode, workspace: {remote_exec_info['remote_workspace']})"
                )
            else:
                # 本地执行
                process = result
                remote_exec_info = None
                self.logger.info(
                    f"🎉 [Workflow {invocation_id}] NATIVE Nextflow started successfully "
                    f"(LOCAL mode, PID: {process.pid})"
                )

            # 7. 创建workflow状态（原生执行没有topology和step_mappings）
            workflow_state = NextflowWorkflowState(
                invocation=workflow_invocation,
                process=process,
                work_dir=workflow_work_dir,
                topology={},  # 原生执行不需要topology
                step_mappings={},  # 原生执行不需要step mappings
                remote_exec_info=remote_exec_info  # 远程执行信息（如果有）
            )

            self.active_workflows[invocation_id] = workflow_state

            # 8. 注册到监控服务（仅本地执行需要）
            if process:
                try:
                    self.monitor_service.register_workflow(
                        invocation_id=invocation_id,
                        work_dir=workflow_work_dir,
                        process_pid=process.pid,
                        enable_batch_logs=self.enable_batch_logs
                    )
                except Exception as e:
                    self.logger.warning(
                        f"[Workflow {invocation_id}] Failed to register monitor: {e}"
                    )

            return workflow_state

        except Exception as e:
            self.logger.error(f"[Workflow {invocation_id}] Failed to run native Nextflow: {e}")
            import traceback
            self.logger.error(traceback.format_exc())
            raise

    def _get_nextflow_package_path(self, tool_id: str) -> Optional[str]:
        """
        获取Nextflow包的路径

        从tool XML中提取nextflow run命令中的路径
        例如: nextflow run '/path/to/main.nf' -> /path/to/

        参数:
            tool_id: Galaxy tool ID

        返回:
            Nextflow包目录路径，如果找不到则返回None
        """
        try:
            # 加载tool
            tool = self.app.toolbox.get_tool(tool_id)
            if not tool:
                self.logger.warning(f"Tool {tool_id} not found in toolbox")
                return None

            # 从tool command中提取Nextflow路径
            # 命令格式: nextflow run '/path/to/main.nf' ...
            command = tool.command
            if 'nextflow run' in command:
                import re
                # 匹配: nextflow run 'path' 或 nextflow run "path"
                match = re.search(r"nextflow run ['\"]([^'\"]+)['\"]", command)
                if match:
                    nf_script_path = match.group(1)
                    # 返回目录（去掉main.nf）
                    package_dir = str(Path(nf_script_path).parent)
                    self.logger.info(f"Extracted Nextflow package path from tool: {package_dir}")
                    return package_dir

            self.logger.warning(f"Could not extract Nextflow path from tool {tool_id}")
            return None

        except Exception as e:
            self.logger.error(f"Error getting Nextflow package path for {tool_id}: {e}")
            return None

    def _prepare_native_workflow_inputs(self, workflow_invocation, engine_step) -> Dict:
        """
        准备原生Nextflow工作流的输入参数（通用方法）

        通用化设计:
        1. 只自动设置通用参数 (input, outdir)
        2. 所有其他参数从用户在Galaxy UI填写的表单中获取
        3. 不硬编码任何pipeline特定的参数

        参数:
            workflow_invocation: Galaxy WorkflowInvocation对象
            engine_step: Engine节点（Nextflow tool步骤）

        返回:
            参数字典 {param_name: value}
        """
        invocation_id = workflow_invocation.id
        params = {}

        # 1. 上传输入数据到S3并获取URI
        if self.s3_manager:
            try:
                self.logger.info(f"[Workflow {invocation_id}] Uploading native workflow inputs to S3...")

                # 使用workflow_invocation.input_datasets获取输入
                # (不能使用workflow_invocation.steps，因为此时steps还未创建)
                s3_input_mapping = self.s3_manager.upload_workflow_inputs(
                    workflow_invocation,
                    self.work_dir / f"workflow_{invocation_id}"
                )

                # 找到第一个S3 URI作为 --input 参数
                # 大部分nf-core pipeline都使用 --input 作为主输入参数
                #
                # ⚠️ 注意：只有当用户实际上传了输入文件时才设置 --input
                # 如果用户使用 -profile test 但没有上传输入，应该让 test profile 的默认值生效
                if s3_input_mapping:
                    for step_id, s3_uri in s3_input_mapping.items():
                        if str(s3_uri).startswith('s3://'):
                            # 只有当 input 参数尚未设置时才自动设置
                            # 这样可以避免覆盖 profile 中的默认值
                            if 'input' not in params:
                                params['input'] = s3_uri
                                self.logger.info(
                                    f"[Workflow {invocation_id}] Auto-set input parameter: "
                                    f"--input {s3_uri}"
                                )
                            else:
                                self.logger.info(
                                    f"[Workflow {invocation_id}] Skipping auto-set of --input "
                                    f"(already set to: {params['input']})"
                                )
                            break

            except Exception as e:
                self.logger.error(f"[Workflow {invocation_id}] Failed to upload inputs: {e}")
                import traceback
                self.logger.error(traceback.format_exc())

        # 2. 从用户在Galaxy UI填写的表单中获取其他参数
        # 这是通用化的关键：不硬编码任何pipeline特定参数
        # 注意：必须先获取用户参数，再设置 auto-generated 参数
        # 这样 auto-generated 参数（input, outdir）的优先级更高
        user_params = self._extract_user_parameters(workflow_invocation, engine_step)

        # 3. 合并参数，但 auto-generated 参数优先级更高
        # 用户参数先添加，然后 auto-generated 参数覆盖
        for key, value in user_params.items():
            if key not in params:  # 只添加不存在的参数
                params[key] = value

        # 4. 自动设置outdir参数（所有nf-core pipeline都需要）
        # 必须在用户参数之后设置，确保不被覆盖
        outdir = f"s3://{self.aws_s3_bucket}/workflows/{invocation_id}/outputs"
        params['outdir'] = outdir
        self.logger.info(f"[Workflow {invocation_id}] Auto-set outdir parameter: --outdir {outdir}")

        # 注意：不自动补充 fasta 参数
        # 如果 pipeline 需要 fasta，应该：
        # 1. 用户手动提供 fasta URL
        # 2. 让 iGenomes 自动处理（设置 genome 参数即可）
        # 3. 从 test.config 中通过智能补全获取（如果有配置的话）

        # 🔑 智能参数补全：根据 pipeline 类型自动补充必填参数
        # 获取 Nextflow package 路径
        try:
            nextflow_package_path = self._get_nextflow_package_path(engine_step.tool_id)
            if nextflow_package_path and Path(nextflow_package_path).exists():
                params = self._smart_fill_required_params(invocation_id, nextflow_package_path, params)
            else:
                self.logger.warning(f"[Workflow {invocation_id}] Could not get nextflow_package_path, skipping smart fill")
        except Exception as e:
            self.logger.warning(f"[Workflow {invocation_id}] Failed to get nextflow_package_path: {e}")

        # 🚀 AutoFix参数合并：优先级最高
        # 从workflow invocation的META_PARAMETERS中提取autofix_params
        autofix_params = self._extract_autofix_params(workflow_invocation)
        if autofix_params:
            self.logger.info(
                f"[Workflow {invocation_id}] 🔧 Merging {len(autofix_params)} AutoFix parameters (highest priority)"
            )

            for key, value in autofix_params.items():
                # 🔑 智能处理特殊参数（input/outdir）
                # 规则：如果值是Galaxy dataset ID格式（如"2368: filename.csv"），则跳过
                #      如果值是真实路径（s3://、http://、/绝对路径），则应用
                if key in ('input', 'outdir'):
                    if isinstance(value, str) and ':' in value:
                        # 进一步判断：是dataset ID还是S3/HTTP URL
                        if not value.startswith(('s3://', 'http://', 'https://', 'ftp://', '/')):
                            # 看起来是 "数字: 文件名" 格式，这是Galaxy dataset ID
                            self.logger.info(
                                f"[Workflow {invocation_id}]   ⏭️ Skip --{key} = '{value}' (Galaxy dataset ID format, using auto-generated: {params.get(key)})"
                            )
                            continue
                        else:
                            # 是真实的URL（如s3://bucket/key），应该应用
                            self.logger.info(
                                f"[Workflow {invocation_id}]   ℹ️  --{key} is a real URL/path, will apply"
                            )

                old_value = params.get(key)
                params[key] = value
                if old_value is not None and old_value != value:
                    self.logger.info(
                        f"[Workflow {invocation_id}]   ✓ Override --{key}: {old_value} → {value}"
                    )
                else:
                    self.logger.info(
                        f"[Workflow {invocation_id}]   ✓ Add --{key} = {value}"
                    )

        self.logger.info(
            f"[Workflow {invocation_id}] Prepared {len(params)} parameters for native execution "
            f"({len(user_params)} from user/tool defaults, {len(autofix_params) if autofix_params else 0} from AutoFix)"
        )

        return params

    def _extract_user_parameters(self, workflow_invocation, engine_step) -> Dict:
        """
        从用户在Galaxy UI填写的表单中提取Nextflow参数

        通用方法：适用于所有nf-core pipeline
        - 遍历workflow_invocation的所有steps
        - 找到Engine step对应的invocation step
        - 提取用户填写的所有参数值

        参数:
            workflow_invocation: Galaxy WorkflowInvocation对象
            engine_step: Engine workflow step

        返回:
            用户填写的参数字典 {param_name: param_value}
        """
        invocation_id = workflow_invocation.id
        user_params = {}

        try:
            # 🔑 关键修复：从 workflow_invocation.steps 读取运行时参数，而不是从 workflow.steps 读取静态定义
            # workflow_invocation.steps 包含用户在运行工作流时填写的实际值
            import json

            # 🔑 关键修复：从 workflow_invocation.step_states 读取运行时参数
            # step_states 在调度时就已经创建，包含用户填写的值
            invocation_step_state = None

            try:
                self.logger.info(f"[Workflow {invocation_id}] Checking workflow_invocation.step_states for runtime parameters...")

                # 安全地获取 step_states
                step_states = getattr(workflow_invocation, 'step_states', [])

                if step_states:
                    self.logger.info(f"[Workflow {invocation_id}] Found {len(step_states)} step_states")

                    # 找到对应于 engine_step 的 step_state
                    for step_state in step_states:
                        if hasattr(step_state, 'workflow_step') and step_state.workflow_step.id == engine_step.id:
                            invocation_step_state = step_state
                            self.logger.info(
                                f"[Workflow {invocation_id}] ✅ Found step_state for engine (workflow_step.id={engine_step.id})"
                            )
                            break
                else:
                    self.logger.info(f"[Workflow {invocation_id}] No step_states available")
            except Exception as e:
                self.logger.warning(f"[Workflow {invocation_id}] Could not access step_states: {e}")
                import traceback
                self.logger.warning(traceback.format_exc())

            # 优先从 step_state 的 value 读取（用户运行时填写的值）
            if invocation_step_state and hasattr(invocation_step_state, 'value') and invocation_step_state.value:
                try:
                    # step_state.value 是序列化的 JSON 字符串
                    runtime_state = invocation_step_state.value
                    if isinstance(runtime_state, str):
                        runtime_state = json.loads(runtime_state)

                    self.logger.info(
                        f"[Workflow {invocation_id}] ✅ Found step_state value with {len(runtime_state)} keys"
                    )

                    # 🔍 调试：打印完整的 runtime_state
                    self.logger.info(f"[Workflow {invocation_id}] 🔍 DEBUG: Full runtime_state = {json.dumps(runtime_state, indent=2, default=str)}")

                    # 解析 step_state.value 中的参数
                    for param_key, param_value in runtime_state.items():
                        self.logger.debug(f"[Workflow {invocation_id}] Processing param_key='{param_key}', param_value type={type(param_value)}, value='{param_value}'")

                        # 🔑 修复：正确的空值检查（不能把 False/0 当作空值）
                        # 跳过 None、空字符串、以及字符串 "None"（Galaxy XML 默认值）
                        if param_value is None or param_value == '' or str(param_value).strip() == 'None':
                            self.logger.debug(f"[Workflow {invocation_id}] Skipping empty parameter: {param_key}")
                            continue

                        # 跳过ConnectedValue
                        if isinstance(param_value, dict) and param_value.get('__class__') == 'ConnectedValue':
                            self.logger.debug(f"[Workflow {invocation_id}] Skipping ConnectedValue: {param_key}")
                            continue

                        # 提取参数
                        if param_key == 'use_test_profile':
                            # use_test_profile 是 boolean，直接使用
                            user_params['use_test_profile'] = str(param_value).lower()
                            self.logger.info(f"[Workflow {invocation_id}] ✅ User parameter: use_test_profile = {param_value}")
                        elif param_key.startswith('param_'):
                            nf_param_name = param_key.replace('param_', '')
                            user_params[nf_param_name] = param_value
                            self.logger.info(f"[Workflow {invocation_id}] User parameter: --{nf_param_name} = {param_value}")
                        elif param_key.startswith('section_'):
                            # Section parameters (grouped)
                            self.logger.info(f"[Workflow {invocation_id}] Found section: {param_key}")

                            # 🔑 关键修复：Galaxy 存储的 section 值是 JSON 字符串，需要再解析一次
                            if isinstance(param_value, str):
                                try:
                                    param_value = json.loads(param_value)
                                    self.logger.debug(f"[Workflow {invocation_id}] Parsed section JSON string to dict")
                                except json.JSONDecodeError as e:
                                    self.logger.warning(f"[Workflow {invocation_id}] Failed to parse section '{param_key}' JSON: {e}")
                                    continue

                            if isinstance(param_value, dict):
                                self.logger.info(f"[Workflow {invocation_id}] Section '{param_key}' has {len(param_value)} sub-parameters")
                                for sub_key, sub_value in param_value.items():
                                    self.logger.debug(f"[Workflow {invocation_id}]   sub_key='{sub_key}', sub_value='{sub_value}'")
                                    # 🔑 修复：正确的空值检查（不能把 False/0 当作空值）
                                    # 跳过 None、空字符串、以及字符串 "None"（Galaxy XML 默认值）
                                    if sub_value is None or sub_value == '' or str(sub_value).strip() == 'None':
                                        self.logger.debug(f"[Workflow {invocation_id}]   Skipping empty sub-parameter: {sub_key}")
                                        continue
                                    # 提取 param_ 开头的参数
                                    if sub_key.startswith('param_'):
                                        nf_param_name = sub_key.replace('param_', '')
                                        user_params[nf_param_name] = sub_value
                                        self.logger.info(f"[Workflow {invocation_id}] User parameter (section): --{nf_param_name} = {sub_value}")
                            else:
                                self.logger.warning(f"[Workflow {invocation_id}] Section '{param_key}' is not a dict after parsing: {type(param_value)}")

                except json.JSONDecodeError as e:
                    self.logger.warning(f"[Workflow {invocation_id}] Failed to parse invocation step state: {e}")

            # Fallback: 从工作流定义的 tool_state 读取（不太可能有用户值，但作为后备）
            elif hasattr(engine_step, 'tool_state') and engine_step.tool_state:
                try:
                    tool_state = json.loads(engine_step.tool_state)
                    self.logger.info(
                        f"[Workflow {invocation_id}] No invocation step state, using workflow definition tool_state "
                        f"({len(tool_state)} keys found)"
                    )

                    for param_key, param_value in tool_state.items():
                        # 🔑 修复：正确的空值检查（不能把 False/0 当作空值）
                        # 跳过 None、空字符串、以及字符串 "None"（Galaxy XML 默认值）
                        if param_value is None or param_value == '' or str(param_value).strip() == 'None':
                            continue

                        if isinstance(param_value, dict) and param_value.get('__class__') == 'ConnectedValue':
                            continue

                        if param_key == 'use_test_profile':
                            user_params['use_test_profile'] = str(param_value).lower()
                        elif param_key.startswith('param_'):
                            nf_param_name = param_key.replace('param_', '')
                            user_params[nf_param_name] = param_value
                        elif param_key.startswith('input_'):
                            # 🔑 支持 input_ 开头的字段（如 input_fasta）
                            nf_param_name = param_key.replace('input_', '')
                            user_params[nf_param_name] = param_value
                        elif param_key.startswith('section_'):
                            # 🔑 关键修复：section 值也是 JSON 字符串
                            if isinstance(param_value, str):
                                try:
                                    param_value = json.loads(param_value)
                                except json.JSONDecodeError:
                                    continue
                            if isinstance(param_value, dict):
                                for sub_key, sub_value in param_value.items():
                                    # 🔑 修复：正确的空值检查（不能把 False/0 当作空值）
                                    # 跳过 None、空字符串、以及字符串 "None"（Galaxy XML 默认值）
                                    if sub_value is None or sub_value == '' or str(sub_value).strip() == 'None':
                                        continue
                                    if sub_key.startswith('param_'):
                                        nf_param_name = sub_key.replace('param_', '')
                                        user_params[nf_param_name] = sub_value

                except json.JSONDecodeError as e:
                    self.logger.warning(f"[Workflow {invocation_id}] Failed to parse tool_state: {e}")
            else:
                self.logger.info(
                    f"[Workflow {invocation_id}] No invocation step state or tool_state found, "
                    f"will rely on Nextflow pipeline defaults"
                )

        except Exception as e:
            self.logger.warning(
                f"[Workflow {invocation_id}] Failed to extract user parameters: {e}"
            )
            import traceback
            self.logger.warning(traceback.format_exc())

        # 日志汇总
        if user_params:
            self.logger.info(
                f"[Workflow {invocation_id}] ✅ Extracted {len(user_params)} user parameter(s): {list(user_params.keys())}"
            )

            # 🔑 新增：检查是否有外部URL需要下载，给出警告
            self._check_external_file_downloads(user_params, invocation_id)
        else:
            self.logger.info(
                f"[Workflow {invocation_id}] No user parameters found, will rely on Nextflow pipeline defaults"
            )

        return user_params

    def _extract_autofix_params(self, workflow_invocation) -> Dict:
        """
        从workflow invocation的META_PARAMETERS中提取AutoFix参数

        AutoFix参数通过前端传递，存储在workflow invocation的input_parameters中
        类型为META_PARAMETERS，名称为"autofix_params"

        参数:
            workflow_invocation: Galaxy WorkflowInvocation对象

        返回:
            AutoFix参数字典 {param_name: value}
        """
        import json
        from galaxy.model import WorkflowRequestInputParameter

        invocation_id = workflow_invocation.id
        autofix_params = {}

        try:
            param_types = WorkflowRequestInputParameter.types

            # 遍历workflow invocation的所有input_parameters
            for parameter in workflow_invocation.input_parameters:
                if parameter.type == param_types.META_PARAMETERS and parameter.name == "autofix_params":
                    # 找到了autofix_params参数
                    try:
                        autofix_params = json.loads(parameter.value)
                        self.logger.info(
                            f"[Workflow {invocation_id}] 🔧 Found AutoFix parameters: {list(autofix_params.keys())}"
                        )
                        break
                    except json.JSONDecodeError as e:
                        self.logger.warning(
                            f"[Workflow {invocation_id}] Failed to parse autofix_params JSON: {e}"
                        )

        except Exception as e:
            self.logger.warning(
                f"[Workflow {invocation_id}] Failed to extract AutoFix parameters: {e}"
            )
            import traceback
            self.logger.warning(traceback.format_exc())

        return autofix_params

    def _check_external_file_downloads(self, params: Dict, invocation_id: int):
        """
        检查参数中是否包含需要从外部URL下载的文件
        如果有，记录警告并建议优化方案
        """
        external_urls = []
        url_params = ['ncrna_fasta', 'fasta', 'gtf', 'gff', 'bed', 'additional_fasta']

        for param_name in url_params:
            param_value = params.get(param_name)
            if param_value and isinstance(param_value, str):
                if param_value.startswith(('http://', 'https://', 'ftp://')):
                    external_urls.append((param_name, param_value))

        if external_urls:
            self.logger.warning(
                f"[Workflow {invocation_id}] ⚠️  检测到 {len(external_urls)} 个外部文件下载："
            )
            for param_name, url in external_urls:
                # 提取文件名
                filename = url.split('/')[-1]
                file_size_mb = "未知"

                # 对于已知的大文件给出估计大小
                if 'ncrna' in filename.lower():
                    file_size_mb = "~20MB"
                elif 'genome' in filename.lower() or 'fasta' in filename.lower():
                    file_size_mb = "~800MB"
                elif 'gtf' in filename.lower() or 'gff' in filename.lower():
                    file_size_mb = "~50MB"

                self.logger.warning(
                    f"[Workflow {invocation_id}]   - {param_name}: {filename} (大小: {file_size_mb})"
                )

            self.logger.warning(
                f"[Workflow {invocation_id}] 💡 建议："
            )
            self.logger.warning(
                f"[Workflow {invocation_id}]   1. 预先下载大文件到Galaxy，避免网络问题"
            )
            self.logger.warning(
                f"[Workflow {invocation_id}]   2. 或使用iGenomes (设置genome参数如GRCh38)"
            )
            self.logger.warning(
                f"[Workflow {invocation_id}]   3. 已自动配置：10次重试、120秒超时"
            )

    def _extract_tool_defaults(self, engine_step) -> Dict:
        """
        从 tool XML 定义中提取默认参数值

        这是一个兜底方法，用于当 tool_state 为空时获取默认参数
        特别是 param_genome 这样有默认值的参数
        """
        tool_defaults = {}

        try:
            # 获取 tool 对象
            tool_id = engine_step.tool_id
            if not tool_id:
                self.logger.info("No tool_id in engine_step")
                return tool_defaults

            self.logger.info(f"Attempting to extract defaults for tool: {tool_id}")

            # 从 Galaxy 的 toolbox 中获取 tool
            tool = self.app.toolbox.get_tool(tool_id)
            if not tool:
                self.logger.warning(f"Could not find tool '{tool_id}' in toolbox")
                return tool_defaults

            # 🔑 关键修复：直接从 tool XML 文件解析默认值
            # Galaxy 的 tool.inputs 可能是嵌套结构（只有 8 个顶层 inputs），不包含所有参数
            # 最可靠的方法是直接解析 XML
            import xml.etree.ElementTree as ET

            tool_xml_path = tool.config_file
            self.logger.info(f"Parsing tool XML: {tool_xml_path}")

            tree = ET.parse(tool_xml_path)
            root = tree.getroot()

            # 查找所有 param 元素
            param_count = 0
            for param in root.findall('.//param'):
                name = param.get('name', '')

                # 只处理 param_ 开头的参数
                if not name.startswith('param_'):
                    continue

                param_count += 1
                param_type = param.get('type', 'text')
                default_value = None

                # 根据不同的参数类型提取默认值
                if param_type == 'select':
                    # 对于 select 类型，查找 selected="true" 的 option
                    for option in param.findall('option'):
                        if option.get('selected', 'false') == 'true':
                            default_value = option.get('value')
                            break
                elif param_type == 'boolean':
                    # 对于 boolean 类型，如果 checked="true"，则默认值为 true
                    if param.get('checked', 'false') == 'true':
                        default_value = 'true'
                else:
                    # 对于其他类型，直接读取 value 属性
                    default_value = param.get('value')

                # 如果找到了非空的默认值，添加到结果中
                if default_value and default_value.strip():
                    nf_param_name = name.replace('param_', '')
                    tool_defaults[nf_param_name] = default_value
                    self.logger.info(
                        f"Extracted tool default: --{nf_param_name} = {default_value}"
                    )

            self.logger.info(f"Scanned {param_count} param_* elements, found {len(tool_defaults)} defaults")

        except Exception as e:
            self.logger.warning(f"Failed to extract tool defaults: {e}")
            import traceback
            self.logger.warning(traceback.format_exc())

        return tool_defaults

    def _smart_fill_required_params(self, invocation_id: int, nextflow_package_path: str, params: Dict) -> Dict:
        """
        智能补全必填参数：根据 pipeline 类型自动填充隐藏的必填参数

        这个方法解决了一个核心问题：
        - nf-core pipelines 的某些参数在 schema 中不标记为 required
        - 但在代码逻辑中是必需的（如 clipseq 的 source、ncrna_fasta）
        - 用户无法从 UI 得知这些参数是必填的

        解决方案：
        1. 读取 pipeline 的 test.config
        2. 提取测试配置中的关键参数作为默认值
        3. 只补充用户未提供的参数（不覆盖用户选择）

        参数:
            invocation_id: workflow invocation ID
            nextflow_package_path: Nextflow pipeline 路径
            params: 当前已提取的参数字典

        返回:
            补全后的参数字典
        """
        try:
            # 1. 检测 pipeline 类型
            pipeline_name = self._detect_pipeline_name(nextflow_package_path)
            self.logger.info(f"[Workflow {invocation_id}] 🔍 Detected pipeline: {pipeline_name}")

            # 2. 读取 test.config
            test_config_path = os.path.join(nextflow_package_path, 'conf', 'test.config')
            if not os.path.exists(test_config_path):
                self.logger.warning(f"[Workflow {invocation_id}] ⚠️ test.config not found, skipping smart fill")
                return params

            # 3. 解析 test.config 提取关键参数
            import re
            required_params = {}

            with open(test_config_path, 'r') as f:
                content = f.read()

                # 定义每个 pipeline 的关键必填参数
                # 这些参数在代码逻辑中是必需的，但 schema 中没有标记为 required
                critical_params = {
                    'clipseq': ['source', 'ncrna_fasta'],
                    'smrnaseq': ['mirtrace_species'],
                    # 可以继续添加其他 pipelines
                }

                # 获取当前 pipeline 的关键参数列表
                params_to_check = critical_params.get(pipeline_name, [])

                for param_name in params_to_check:
                    # 如果用户已经提供了这个参数，跳过
                    if param_name in params and params[param_name]:
                        self.logger.info(f"[Workflow {invocation_id}] ✓ Parameter '{param_name}' already provided by user: {params[param_name]}")
                        continue

                    # 从 test.config 中提取参数值
                    # 匹配模式: param_name = "value" 或 param_name = 'value'
                    pattern = rf'{param_name}\s*=\s*["\']([^"\']+)["\']'
                    match = re.search(pattern, content)

                    if match:
                        value = match.group(1)
                        required_params[param_name] = value
                        self.logger.info(f"[Workflow {invocation_id}] ✅ Auto-filled required parameter: --{param_name} = {value}")
                    else:
                        self.logger.warning(f"[Workflow {invocation_id}] ⚠️ Could not find '{param_name}' in test.config")

            # 4. 特殊处理：测试数据替换为生产数据
            # 定义需要替换测试数据的参数及其生产环境 URL
            production_replacements = {
                'clipseq': {
                    'ncrna_fasta': {
                        'test_patterns': ['test-datasets', 'smallRNA'],
                        'production_url': 'https://ftp.ensembl.org/pub/release-110/fasta/homo_sapiens/ncrna/Homo_sapiens.GRCh38.ncrna.fa.gz'
                    }
                },
                # 可以为其他 pipelines 添加类似的配置
                # 'rnaseq': {
                #     'gtf': {
                #         'test_patterns': ['test-datasets'],
                #         'production_url': 'https://production/gtf'
                #     }
                # }
            }

            # 应用生产数据替换规则
            if pipeline_name in production_replacements:
                for param_name, replacement_config in production_replacements[pipeline_name].items():
                    if param_name not in params and param_name in required_params:
                        test_value = required_params[param_name]
                        # 检查是否是测试数据
                        is_test_data = any(pattern in test_value for pattern in replacement_config['test_patterns'])
                        if is_test_data:
                            production_url = replacement_config['production_url']
                            required_params[param_name] = production_url
                            self.logger.info(
                                f"[Workflow {invocation_id}] 🔄 Replaced test {param_name} "
                                f"with production data: {production_url}"
                            )

            # 5. 合并到 params 中（只添加用户未提供的参数）
            for param_name, param_value in required_params.items():
                if param_name not in params:
                    params[param_name] = param_value

            if required_params:
                self.logger.info(f"[Workflow {invocation_id}] 🎉 Smart fill completed: {len(required_params)} parameters auto-filled")

        except Exception as e:
            self.logger.warning(f"[Workflow {invocation_id}] ⚠️ Smart fill failed: {e}")
            import traceback
            self.logger.debug(traceback.format_exc())

        return params

    def _detect_pipeline_name(self, nextflow_package_path: str) -> str:
        """
        从 Nextflow package 路径中检测 pipeline 名称

        例如: /path/to/clipseq_v2_1766548150 -> clipseq
        """
        import re
        dirname = os.path.basename(nextflow_package_path)
        # 提取 pipeline 名称（去除版本号和时间戳）
        match = re.match(r'^([a-z]+)', dirname)
        if match:
            return match.group(1)
        return dirname

    def _get_aws_batch_config_for_mode(self) -> str:
        """根据S3传输模式返回AWS Batch配置片段"""

        if self.s3_transfer_mode == 'native':
            # 方案1: Nextflow原生模式 - 使用内置S3客户端（推荐）
            return """        // Mode: Native (Nextflow内置S3客户端)
        // 不依赖aws命令，使用Nextflow内置的Java AWS SDK
        // 完全不需要配置cliPath，Nextflow自动处理S3传输
        // 关键优势: 不挂载任何目录，100%兼容BioContainers

        maxTransferAttempts = 3
        maxSpotAttempts = 3
        jobRole = 'arn:aws:iam::399683337364:role/ecsInstanceRole'"""

        elif self.s3_transfer_mode == 'wave':
            # 方案2: Wave + Fusion模式 - 不需要AWS CLI，但需要基本AWS Batch配置
            return """        // Mode: Wave + Fusion (Seqera官方方案)
        // Fusion在容器内提供虚拟S3文件系统，无需AWS CLI挂载
        // 这样不会覆盖容器的 /usr 目录，100%兼容BioContainers

        maxTransferAttempts = 3
        maxSpotAttempts = 3
        jobRole = 'arn:aws:iam::399683337364:role/ecsInstanceRole'"""

        elif self.s3_transfer_mode == 'goofys':
            # 方案3: Goofys自建模式 - 需要FUSE设备权限
            return """        // Mode: Goofys FUSE (开源免费，自建)
        // Goofys挂载S3，需要FUSE设备和SYS_ADMIN权限
        containerOptions = '--cap-add SYS_ADMIN --device /dev/fuse'"""

        elif self.s3_transfer_mode == 'static-cli':
            # 方案4: Static CLI模式 - 动态安装AWS CLI
            return """        // Mode: Static CLI (免费，100%通用)
        // 在容器内动态安装AWS CLI，不需要挂载或预安装"""

        elif self.s3_transfer_mode == 's5cmd':
            # 方案6: Static CLI动态安装（终极解决方案）
            # 放弃volumes挂载（Nextflow解析有bug），改用beforeScript动态安装
            # 这是唯一100%可靠的方案,不依赖宿主机配置
            return """        // Mode: Static CLI (Dynamic Installation - Ultimate Solution)
        // AWS CLI is installed dynamically in each container via beforeScript
        // No volumes mounting - avoids all Nextflow volume parsing bugs
        // 100% reliable, works with all containers including BioContainers

        maxTransferAttempts = 3
        maxSpotAttempts = 3
        jobRole = 'arn:aws:iam::399683337364:role/ecsInstanceRole'"""

        else:  # host-cli
            # Host-CLI 模式 + Bind Mount欺骗策略 (终极解决方案)
            # UserData在宿主机上: mount --bind /opt/aws-cli-mount /opt/aws-cli-container
            # Nextflow看到cliPath,会自动推断并挂载宿主机的 /opt/aws-cli-container
            # 由于bind mount,实际挂载的是 /opt/aws-cli-mount 的内容
            # 关键: 只配置cliPath,不配置AWS CLI的volumes,让Nextflow自动处理
            return """        // Mode: Host-CLI with Bind Mount Trick (Ultimate Solution)
        // UserData creates: mount --bind /opt/aws-cli-mount /opt/aws-cli-container
        // Nextflow auto-infers volume from cliPath and mounts host's /opt/aws-cli-container
        // Due to bind mount, it actually gets /opt/aws-cli-mount content

        // 1. Only set cliPath - let Nextflow auto-generate the volume
        cliPath = '/opt/aws-cli-container/bin/aws'

        // 2. No SSL certificate mount - let containers use their own CA bundles
        // 🔑 关键修复：不挂载宿主机SSL证书，因为：
        //    - 宿主机可能没有 /etc/pki/tls/certs/ca-bundle.crt（这是RedHat路径）
        //    - 容器内的AWS CLI会使用自带的证书
        //    - AWS SDK会自动通过ECS Task Role获取凭证，不需要特殊SSL配置

        maxTransferAttempts = 3
        maxSpotAttempts = 3
        jobRole = 'arn:aws:iam::399683337364:role/ecsInstanceRole'"""
    
    def _get_ulimit_fix(self) -> str:
        """
        返回通用的 ulimit 修复代码

        问题：Nextflow 默认在脚本开头添加 "ulimit -s unlimited"
        AWS Batch 容器没有 CAP_SYS_RESOURCE 权限，导致任务失败

        解决方案：定义一个空的 ulimit 函数覆盖系统命令
        """
        return """# 🔧 ulimit 权限修复（通用）
# 定义空函数避免 AWS Batch 容器权限错误
ulimit() { :; }
export -f ulimit
"""

    def _get_alpine_fix(self) -> str:
        """
        返回 Alpine 容器兼容性修复代码

        问题：Alpine Linux 使用 musl libc，无法运行基于 glibc 编译的 AWS CLI
        host-cli 模式下，宿主机的 AWS CLI（glibc）挂载到 Alpine 容器会报错

        解决方案：
        1. 检测是否为 Alpine 容器
        2. 如果是，安装 glibc 兼容层（libc6-compat）
        3. 验证 AWS CLI 是否可用
        """
        return """# 🔧 Alpine 容器兼容性修复（host-cli 模式）
if [ -f /etc/alpine-release ]; then
    echo "⚠️ Alpine Linux detected - installing glibc compatibility layer for host AWS CLI..."

    # 尝试安装 libc6-compat（需要 root 或 sudo 权限）
    if command -v apk >/dev/null 2>&1; then
        apk add --no-cache libc6-compat bash 2>/dev/null || {
            echo "❌ Failed to install libc6-compat - container may not have apk or root access"
            echo "   This is expected if the container runs as non-root user"
        }
    fi

    # 验证 AWS CLI 是否可用
    if command -v aws >/dev/null 2>&1; then
        echo "✅ AWS CLI is available"
        aws --version 2>&1 | head -1 || echo "⚠️ AWS CLI exists but may not work properly"
    else
        echo "❌ AWS CLI not found in PATH"
    fi
fi"""

    def _get_executor_config(self) -> str:
        """
        根据配置的 executor 类型生成对应的配置

        支持三种执行器:
        - awsbatch: AWS Batch (默认)
        - local: 本地执行
        - slurm: Slurm HPC 集群
        """
        if self.nextflow_executor == 'awsbatch':
            return f"""    executor = 'awsbatch'
    queue = '{self.aws_batch_queue}'

    // AWS Batch 特定配置
    // Native模式：Nextflow使用Java AWS SDK直接访问S3
    // 容器内不需要AWS CLI或证书配置"""

        elif self.nextflow_executor == 'local':
            return """    executor = 'local'

    // 本地执行配置
    // 使用本地计算资源，不需要云服务"""

        elif self.nextflow_executor == 'slurm':
            slurm_options = []
            if self.slurm_partition:
                slurm_options.append(f"--partition={self.slurm_partition}")
            if self.slurm_qos:
                slurm_options.append(f"--qos={self.slurm_qos}")
            if self.slurm_account:
                slurm_options.append(f"--account={self.slurm_account}")

            clusterOptions = ' '.join(slurm_options) if slurm_options else ''

            return f"""    executor = 'slurm'
    {f"clusterOptions = '{clusterOptions}'" if clusterOptions else ""}

    // Slurm 集群配置
    // 提交任务到 Slurm 队列管理系统"""

        else:
            # 默认返回 local
            return """    executor = 'local'"""

    def _get_process_config_for_mode(self) -> str:
        """根据S3传输模式返回Process配置片段"""

        if self.s3_transfer_mode == 'native':
            # 原生模式：不需要beforeScript，Nextflow自动处理所有S3操作
            # 但需要 ulimit 修复
            return f"""
    // Native模式 - Nextflow内置S3客户端自动处理数据传输
    // 容器内不需要aws命令，不需要任何额外安装
    beforeScript = '''{self._get_ulimit_fix()}
    '''
"""

        elif self.s3_transfer_mode == 'static-cli':
            # 方案2: Static CLI - 在任务执行前动态安装AWS CLI
            return f"""
    // Static CLI模式 - 每次任务启动时动态安装AWS CLI
    // 优点：100%可靠，不依赖宿主机或AMI
    // 缺点：每次任务启动增加10-20秒
    beforeScript = '''{self._get_ulimit_fix()}
        set -e  # 遇到错误立即退出

        # 检查AWS CLI是否已安装
        if ! command -v aws >/dev/null 2>&1; then
            echo "[$(date)] Installing AWS CLI v2..."

            # 创建临时目录
            mkdir -p /tmp/aws-install
            cd /tmp/aws-install

            # 下载AWS CLI（重试3次）
            for i in 1 2 3; do
                if curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip; then
                    break
                fi
                echo "Download attempt $i failed, retrying..."
                sleep 2
            done

            # 解压
            unzip -q awscliv2.zip

            # 安装到临时路径（不需要root权限）
            ./aws/install -i ./aws-cli -b ./bin

            # 添加到PATH
            export PATH=$PWD/bin:$PATH

            echo "[$(date)] AWS CLI installed: $(aws --version)"
        else
            echo "[$(date)] AWS CLI already available: $(aws --version)"
        fi

        # 确保aws命令可用
        which aws
    '''
"""
        elif self.s3_transfer_mode == 'goofys':
            # 方案3: Goofys自建方案 - 安装Goofys并挂载S3
            return f"""
    // Goofys模式 - 安装Goofys并挂载S3作为本地文件系统
    beforeScript = '''{self._get_ulimit_fix()}
        echo "========================================="
        echo "🚀 Goofys S3 Transparent Mount"
        echo "========================================="

        # 安装Goofys（如果不存在）
        if ! command -v goofys >/dev/null 2>&1; then
            echo "📦 [Goofys] Installing..."
            apt-get update -qq && apt-get install -y -qq fuse curl ca-certificates
            curl -L https://github.com/kahing/goofys/releases/latest/download/goofys -o /usr/local/bin/goofys
            chmod +x /usr/local/bin/goofys
            echo "✅ [Goofys] Installed"
        fi

        # 挂载S3 bucket
        MOUNT_POINT="/mnt/s3"
        S3_BUCKET="{self.aws_s3_bucket}"
        AWS_REGION="{self.aws_region}"

        mkdir -p ${{MOUNT_POINT}}

        if ! mountpoint -q ${{MOUNT_POINT}} 2>/dev/null; then
            echo "📂 [S3 Mount] Mounting ${{S3_BUCKET}}..."
            goofys \\
                --region ${{AWS_REGION}} \\
                --stat-cache-ttl 1m \\
                --type-cache-ttl 1m \\
                ${{S3_BUCKET}} ${{MOUNT_POINT}} &
            sleep 3

            if mountpoint -q ${{MOUNT_POINT}} 2>/dev/null; then
                echo "✅ [S3 Mount] Successfully mounted at ${{MOUNT_POINT}}"
                df -h ${{MOUNT_POINT}} 2>/dev/null || echo "   (FUSE mount active)"
            else
                echo "⚠️  [S3 Mount] Failed to mount, workflow may fail"
            fi
        else
            echo "✅ [S3 Mount] Already mounted at ${{MOUNT_POINT}}"
        fi

        echo "========================================="
    '''
"""
        elif self.s3_transfer_mode == 's5cmd':
            # Static CLI模式 - 在每个容器内动态安装AWS CLI
            # 100%可靠,不依赖宿主机或volumes挂载
            return f"""
    // Static CLI模式 - 每次任务启动时动态安装AWS CLI
    // 优点：100%可靠，不依赖宿主机或AMI，避免volumes挂载bug
    // 缺点：每次任务启动增加10-20秒
    beforeScript = '''{self._get_ulimit_fix()}
        set -e  # 遇到错误立即退出

        # 检查AWS CLI是否已安装
        if ! command -v aws >/dev/null 2>&1; then
            echo "[$(date)] Installing AWS CLI v2..."

            # 创建临时目录
            mkdir -p /tmp/aws-install
            cd /tmp/aws-install

            # 下载AWS CLI（重试3次）
            for i in 1 2 3; do
                if curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip; then
                    break
                fi
                echo "Download attempt $i failed, retrying..."
                sleep 2
            done

            # 解压
            unzip -q awscliv2.zip

            # 安装到临时路径（不需要root权限）
            ./aws/install -i ./aws-cli -b ./bin

            # 添加到PATH
            export PATH=$PWD/bin:$PATH

            echo "[$(date)] AWS CLI installed: $(aws --version)"
        else
            echo "[$(date)] AWS CLI already available: $(aws --version)"
        fi

        # 确保aws命令可用
        which aws
    '''
"""
        elif self.s3_transfer_mode == 'host-cli':
            # Host CLI模式 - 需要 ulimit 修复 + Alpine 兼容性修复
            # 🔑 关键修复：不设置 AWS_CA_BUNDLE 环境变量
            # 原因：宿主机的SSL证书路径可能不存在，导致AWS CLI失败
            # 解决：让容器使用自带的SSL证书，通过 ECS Task Role 自动获取AWS凭证
            return f"""
    // Host CLI模式
    // AWS CLI 通过 cliPath 从宿主机挂载
    // AWS 凭证通过 ECS Task Role (jobRole) 自动获取

    // 🔑 关键修复：覆盖 pipeline 的 process.shell 设置
    // 某些 pipeline (如 smrnaseq) 会设置自定义的 process.shell，导致生成错误的 nxf_launch 函数
    // 我们强制使用标准的 bash shell，确保 .command.run 能正确执行
    shell = ['/bin/bash', '-euo', 'pipefail']

    // ulimit 修复 + Alpine 兼容性修复
    beforeScript = '''{self._get_ulimit_fix()}{self._get_alpine_fix()}
    '''
"""
        else:
            # 其他模式（wave等）也需要 ulimit 修复
            return f"""
    // ulimit 修复（通用）
    beforeScript = '''{self._get_ulimit_fix()}
    '''
"""

    def _check_pipeline_config_conflicts(self, pipeline_dir: Path):
        """
        检查 pipeline 的配置文件是否包含可能导致问题的设置

        常见问题：
        1. aws.client.anonymous = true - 导致无法访问私有 S3 bucket
        2. 动态设置 anonymous 基于 igenomes - 可能误触发

        这个方法会发出警告，帮助诊断问题
        """
        pipeline_config = pipeline_dir / "nextflow.config"
        if not pipeline_config.exists():
            return

        try:
            with open(pipeline_config, 'r') as f:
                content = f.read()

            # 检查是否设置了 anonymous
            if 'anonymous' in content.lower():
                self.logger.warning(
                    f"⚠️  Pipeline config contains 'anonymous' setting - "
                    f"Galaxy will override with 'anonymous = false' to ensure authenticated S3 access"
                )

                # 提取具体的设置（用于调试）
                import re
                anonymous_lines = re.findall(r'.*anonymous.*', content, re.IGNORECASE)
                for line in anonymous_lines[:3]:  # 只显示前3个匹配
                    self.logger.debug(f"   Pipeline config: {line.strip()}")

        except Exception as e:
            self.logger.debug(f"Could not check pipeline config: {e}")

    def _ensure_aws_credentials(self):
        """
        确保进程环境变量中有 AWS 凭证

        如果环境变量中已有显式凭证则直接返回
        否则尝试从 AWS SSO profile 获取并设置到环境变量

        这个方法会修改进程的 os.environ，确保后续代码能检测到凭证
        """
        # 如果已经有显式凭证，直接返回
        if 'AWS_ACCESS_KEY_ID' in os.environ and 'AWS_SECRET_ACCESS_KEY' in os.environ:
            self.logger.info("✅ AWS credentials already in environment variables")
            return

        # 尝试从 SSO profile 获取凭证
        aws_profile = os.environ.get('AWS_PROFILE', '')
        if not aws_profile:
            self.logger.warning("⚠️ No AWS_PROFILE and no explicit credentials")
            return

        try:
            # 使用 boto3 从 SSO 获取临时凭证
            import boto3
            session = boto3.Session(profile_name=aws_profile)
            credentials = session.get_credentials()

            if credentials:
                # 关键：设置到进程的环境变量中（不只是局部变量）
                os.environ['AWS_ACCESS_KEY_ID'] = credentials.access_key
                os.environ['AWS_SECRET_ACCESS_KEY'] = credentials.secret_key
                if credentials.token:
                    os.environ['AWS_SESSION_TOKEN'] = credentials.token

                self.logger.info(f"✅ Retrieved and set AWS SSO credentials for profile: {aws_profile}")
                self.logger.info(f"   Access Key: {credentials.access_key[:20]}...")
            else:
                self.logger.warning(f"⚠️ No credentials found for profile: {aws_profile}")

        except Exception as e:
            self.logger.error(f"❌ Failed to get AWS SSO credentials: {e}")
            self.logger.error(f"   Will rely on profile-based authentication (may fail)")
            self.logger.error(f"   💡 Workaround: Run './start_galaxy_with_aws.sh' to pre-fetch credentials")

    def _get_wave_fusion_config_for_mode(self) -> str:
        """根据S3传输模式返回Wave/Fusion配置片段"""

        if self.s3_transfer_mode == 'wave':
            # 方案1: Wave + Fusion（第三方付费）
            return """
// Wave配置（动态容器增强）
wave {
    enabled = true
    endpoint = 'https://wave.seqera.io'
}

// Fusion配置（高性能S3文件系统）
fusion {
    enabled = true
    exportStorageCredentials = true
}"""
        elif self.s3_transfer_mode == 'goofys':
            # 方案2: Goofys自建（完全免费）
            return """
// Wave配置（Goofys模式不使用）
wave {
    enabled = false
}

// Fusion配置（Goofys模式不使用，使用Goofys替代）
fusion {
    enabled = false
}"""
        else:
            # 其他模式：禁用Wave + Fusion
            return """
// Wave配置（当前模式不使用）
wave {
    enabled = false
}

// Fusion配置（当前模式不使用）
fusion {
    enabled = false
}"""

    def _generate_nextflow_config(self, workflow_invocation, work_dir: Path, nf_parameters: Dict = None, engine_step = None) -> Path:
        """
        生成Nextflow配置文件

        包含AWS Batch、Wave、Fusion等配置

        参数:
            workflow_invocation: Workflow invocation对象
            work_dir: 工作目录
            nf_parameters: Nextflow参数字典（可选），用于智能配置
            engine_step: Engine workflow step（可选），用于提取tool XML默认值
        """
        config_path = work_dir / "nextflow.config"
        nf_parameters = nf_parameters or {}

        # 🔑 关键修复：使用本地 workDir + S3 bucket-dir 的混合模式
        # 问题：某些 pipeline（如 DROP）的 collectFile 操作在主进程执行，无法直接写入 S3
        # 解决方案：
        #   1. workDir = 本地路径（用于主进程的 collectFile 等操作）
        #   2. -bucket-dir = S3 路径（用于 AWS Batch 任务的数据staging）
        # Nextflow 会自动在本地 workDir 和 S3 bucket-dir 之间同步数据
        local_work_dir = str(work_dir / "work")
        s3_bucket_dir = f"s3://{self.aws_s3_bucket}/nextflow_workflows/{workflow_invocation.id}/work"

        # 🔑 关键修复：在生成配置前先确保有 AWS 凭证
        # 这样配置生成时就能正确检测到凭证，决定是否使用 profile
        self._ensure_aws_credentials()

        # 🔍 检查 pipeline 是否可能有配置冲突
        self._check_pipeline_config_conflicts(work_dir.parent)

        # AWS Profile配置（支持SSO）
        # 只有在没有显式凭证时才使用 profile
        # Java AWS SDK 对 SSO profile 的支持有限，当同时存在环境变量凭证和 profile 时会冲突
        aws_profile = os.environ.get('AWS_PROFILE', '')
        has_explicit_credentials = (
            'AWS_ACCESS_KEY_ID' in os.environ and
            'AWS_SECRET_ACCESS_KEY' in os.environ
        )

        if has_explicit_credentials:
            # 有显式凭证时不设置 profile，让 Java SDK 使用环境变量
            profile_config = "// profile not set - using environment variables (AWS_ACCESS_KEY_ID, etc.)"
            self.logger.info(f"[Workflow {workflow_invocation.id}] Using explicit AWS credentials from environment")
        elif aws_profile:
            # 只有 profile 没有显式凭证时，才在配置文件中设置 profile
            profile_config = f"profile = '{aws_profile}'"
            self.logger.warning(
                f"[Workflow {workflow_invocation.id}] Using AWS profile '{aws_profile}' - "
                f"Note: Java AWS SDK has limited SSO support, may fail"
            )
        else:
            profile_config = ""
            self.logger.warning(f"[Workflow {workflow_invocation.id}] No AWS credentials configured!")

        # 🔑 智能处理 igenomes_ignore 参数
        # 如果用户指定了预定义的 genome（如 GRCh38），则不要忽略 iGenomes
        # 这样可以让 pipeline 自动加载参考文件
        use_igenomes = False
        genome_value = nf_parameters.get('genome')

        # 如果用户参数中没有 genome，尝试从 tool XML 默认值中获取
        if not genome_value and engine_step is not None:
            self.logger.info(f"[Workflow {workflow_invocation.id}] No genome in user parameters, attempting to extract from tool XML...")
            try:
                tool_defaults = self._extract_tool_defaults(engine_step)
                self.logger.info(f"[Workflow {workflow_invocation.id}] Extracted tool defaults: {tool_defaults}")
                genome_value = tool_defaults.get('genome')
                if genome_value:
                    self.logger.info(
                        f"[Workflow {workflow_invocation.id}] Found genome default in tool XML: '{genome_value}'"
                    )
                    # 🔑 关键修复：将 genome 添加到参数字典，以便传递给 Nextflow
                    nf_parameters['genome'] = genome_value
                    self.logger.info(
                        f"[Workflow {workflow_invocation.id}] Added genome parameter to nf_parameters: --genome {genome_value}"
                    )
                else:
                    self.logger.warning(f"[Workflow {workflow_invocation.id}] No genome found in tool defaults")
            except Exception as e:
                self.logger.warning(f"[Workflow {workflow_invocation.id}] Could not extract genome default: {e}")
                import traceback
                self.logger.warning(f"[Workflow {workflow_invocation.id}] Traceback: {traceback.format_exc()}")
        elif not genome_value:
            self.logger.info(f"[Workflow {workflow_invocation.id}] No genome in user parameters and no engine_step provided")

        # 检查是否是预定义的 genome（而不是文件路径）
        if genome_value and not genome_value.startswith('/') and not genome_value.startswith('s3://'):
            use_igenomes = True
            self.logger.info(
                f"[Workflow {workflow_invocation.id}] User specified genome '{genome_value}', "
                f"enabling iGenomes support"
            )

        # 🔑 关键修复：构建 params 块，包含所有用户参数和 AutoFix 参数
        # 这样确保参数不仅通过命令行传递，也写入 nextflow.config
        params_lines = []

        if use_igenomes:
            # 使用 iGenomes，但仍然禁用匿名访问
            params_lines.append("    // 使用 iGenomes 自动加载参考文件，但禁用匿名访问")
            params_lines.append("    igenomes_ignore = false")
            params_lines.append(f"    genome = '{genome_value}'")
            self.logger.info(f"[Workflow {workflow_invocation.id}] iGenomes enabled (igenomes_ignore = false, genome = {genome_value})")
            # 🔑 临时修复：对于 smRNA-seq pipeline，如果没有 mirtrace_species，默认设置为 hsa
            if not nf_parameters.get('mirtrace_species'):
                # 根据 genome 推断 mirtrace_species
                genome_to_species = {
                    'GRCh38': 'hsa', 'GRCh37': 'hsa', 'hg38': 'hsa', 'hg19': 'hsa',
                    'GRCm39': 'mmu', 'GRCm38': 'mmu', 'mm10': 'mmu', 'mm39': 'mmu',
                    'Rnor_6.0': 'rno',
                    'BDGP6': 'dme',
                    'WBcel235': 'cel',
                }
                inferred_species = genome_to_species.get(genome_value, 'hsa')  # 默认 hsa
                nf_parameters['mirtrace_species'] = inferred_species
                self.logger.info(
                    f"[Workflow {workflow_invocation.id}] Auto-inferred mirtrace_species='{inferred_species}' from genome='{genome_value}'"
                )
        else:
            # 不使用 iGenomes（用户提供了自定义参考文件或使用 test profile）
            params_lines.append("    // 确保 pipeline 不会启用 igenomes 的匿名访问模式")
            params_lines.append("    igenomes_ignore = true")
            self.logger.info(f"[Workflow {workflow_invocation.id}] iGenomes disabled (igenomes_ignore = true)")

        # 🔑 关键修复：添加所有用户参数到 params 块
        # 这包括 AutoFix 应用的参数（如 skip_filter_gtf = true）
        # 排除一些系统参数（input, outdir, use_test_profile）
        system_params = {'input', 'outdir', 'use_test_profile', 'genome', 'igenomes_ignore', 'mirtrace_species'}
        params_written = 0

        for param_name, param_value in nf_parameters.items():
            # 跳过已经处理的参数和系统参数
            if param_name in system_params:
                continue

            # 跳过空值
            if param_value is None or param_value == '' or str(param_value).strip() == 'None':
                continue

            # 根据类型格式化参数值
            if isinstance(param_value, bool):
                # 布尔值：true/false（小写，不带引号）
                params_lines.append(f"    {param_name} = {str(param_value).lower()}")
                params_written += 1
                self.logger.info(f"[Workflow {workflow_invocation.id}] Added parameter to config: {param_name} = {str(param_value).lower()}")
            elif isinstance(param_value, (int, float)):
                # 数字：不带引号
                params_lines.append(f"    {param_name} = {param_value}")
                params_written += 1
                self.logger.info(f"[Workflow {workflow_invocation.id}] Added parameter to config: {param_name} = {param_value}")
            elif isinstance(param_value, str):
                # 字符串：带单引号
                # 转义单引号
                escaped_value = param_value.replace("'", "\\'")
                params_lines.append(f"    {param_name} = '{escaped_value}'")
                params_written += 1
                self.logger.info(f"[Workflow {workflow_invocation.id}] Added parameter to config: {param_name} = '{escaped_value}'")
            else:
                # 其他类型（列表、字典等）：转为字符串并带引号
                self.logger.warning(
                    f"[Workflow {workflow_invocation.id}] Unsupported parameter type for {param_name}: {type(param_value)}, "
                    f"converting to string"
                )
                params_lines.append(f"    {param_name} = '{param_value}'")
                params_written += 1

        if params_written > 0:
            self.logger.info(
                f"[Workflow {workflow_invocation.id}] ✅ Wrote {params_written} user/AutoFix parameters to nextflow.config params block"
            )

        # 组装 params 块
        params_block = "params {\n" + "\n".join(params_lines) + "\n}"

        config_content = f"""
// Nextflow Configuration for Galaxy Workflow
// Workflow ID: {workflow_invocation.id}
// S3 Transfer Mode: {self.s3_transfer_mode}

// 🔒 强制覆盖 AWS 配置的参数
// 某些 nf-core pipelines 会在 profile 中设置这些参数，可能导致权限问题
// 我们在最外层定义这些参数，确保它们不会被覆盖
{params_block}

// AWS Batch配置
aws {{
    region = '{self.aws_region}'
    {profile_config}
    batch {{
{self._get_aws_batch_config_for_mode()}
    }}
    client {{
        maxConnections = 20
        connectionTimeout = 60000  // 🔑 增加到 60 秒（下载大文件需要更长时间）
        socketTimeout = 120000     // 🔑 Socket 超时 120 秒（网络慢时避免中断）
        uploadMaxThreads = 4
        uploadChunkSize = '100MB'
        uploadMaxAttempts = 10     // 增加到 10 次重试
        uploadRetrySleep = '1000ms' // 🔑 增加重试间隔到 1 秒
        uploadStorageClass = 'INTELLIGENT_TIERING'
        maxErrorRetry = 10         // HTTP 请求最大重试次数
        downloadMaxAttempts = 10   // 🔑 下载最大重试次数
        downloadRetrySleep = '2000ms' // 🔑 下载重试间隔 2 秒
        // 🔑 关键修复：强制使用文件缓冲以支持 mark/reset
        // 问题：从 HTTPS 下载并上传到 S3 时，输入流不支持 mark/reset 导致重试失败
        // 解决方案：禁用流式上传，强制先下载到本地再上传
        s3Acl = 'private'
        // 禁用SSL验证（Mac本地Java SSL问题临时解决方案）
        // 仅影响Nextflow主进程访问S3，不影响容器内任务
        s3PathStyleAccess = true

        // 🔑 通用修复：强制禁用匿名访问
        // 问题：某些 nf-core pipelines（如 scrnaseq）会动态设置：
        //   aws.client.anonymous = !params.igenomes_ignore && params.igenomes_base?.startsWith('s3://ngi-igenomes/') ?: false
        // 这会导致访问私有 S3 bucket 时出现 Access Denied (403)
        // 解决方案：
        //   1. 根据用户参数智能设置 params.igenomes_ignore（上面的 params 块）
        //      - 如果用户指定了预定义的 genome（如 GRCh38），则 igenomes_ignore = false
        //      - 否则 igenomes_ignore = true
        //   2. 显式设置 anonymous = false（这里）
        //   3. 双重保护，确保无论 igenomes_ignore 如何设置，都使用认证访问
        anonymous = false
    }}
}}

// Process配置
process {{
{self._get_executor_config()}

    // 容器配置
    container = 'ubuntu:20.04'  // 默认容器（当process没有指定container时使用）

    // 资源限制
    cpus = 2
    memory = '4 GB'
    time = '1h'

    // 错误处理 - 网络下载失败时自动重试
    errorStrategy = 'retry'
    maxRetries = 5              // 🔑 增加到 5 次（网络问题需要更多重试）
    maxErrors = 10              // 🔑 允许累计 10 个错误再失败
{self._get_process_config_for_mode()}
}}

// Docker配置
// 🔑 关键修复：配置Docker registry用于biocontainers镜像
// 问题：nf-core pipelines使用的biocontainers镜像默认从quay.io拉取
// AWS Batch默认只从Docker Hub拉取，导致"manifest unknown"错误
//
// TODO: ECR优先级支持
// 当前Nextflow的docker.registry不支持数组形式的fallback
// 未来可以通过process级别的容器覆盖来实现ECR优先
docker {{
    enabled = true
    registry = 'quay.io'  // biocontainers镜像的默认registry
}}

{self._get_wave_fusion_config_for_mode()}

// 工作目录
// 使用本地目录，避免 Nextflow 主进程的 collectFile 等操作尝试直接写入 S3
// AWS Batch 任务会通过 S3 传输输入/输出文件
workDir = '{local_work_dir}'

// HTTP/HTTPS 文件下载配置
// 🔑 关键修复：增强 HTTP 下载的重试和超时配置
// 问题：从 Ensembl FTP、GitHub 等 HTTPS 下载文件时网络不稳定导致失败
// 解决方案：增加重试次数、超时时间、重试间隔，使用更保守的策略
filePorter {{
    maxRetries = 10          // 🔑 文件传输最大重试次数（增加到10次）
    maxTransferAttempts = 15 // 🔑 最大传输尝试次数（增加到15次）
    retryDelay = '5s'        // 🔑 重试延迟 5 秒（给网络恢复时间）
}}

// HTTP 客户端配置
// 针对从 GitHub 等外部 URL 下载文件的场景
env {{
    // Nextflow 内部 HTTP 客户端配置
    NXF_FILE_REMOTE_DEBUG = 'false'
}}

// 报告
report {{
    enabled = true
    file = 'workflow-report.html'
    overwrite = true
}}

timeline {{
    enabled = true
    file = 'workflow-timeline.html'
    overwrite = true
}}

trace {{
    enabled = true
    file = 'workflow-trace.txt'
    overwrite = true
}}
"""

        with open(config_path, 'w') as f:
            f.write(config_content)

        self.logger.info(f"Nextflow config saved to {config_path}")
        return config_path

    def _prepare_workflow_inputs(self, workflow_invocation, work_dir: Path) -> Dict[str, str]:
        """
        准备工作流输入数据

        策略:
        1. 将输入数据上传到S3
        2. 生成参数映射
        3. Nextflow通过Fusion访问
        """
        input_params = {}

        # 使用S3 Manager上传输入数据
        if self.s3_manager:
            try:
                self.logger.info(f"[Workflow {workflow_invocation.id}] Uploading inputs to S3...")
                s3_input_mapping = self.s3_manager.upload_workflow_inputs(
                    workflow_invocation, work_dir
                )

                # 转换为Nextflow参数格式
                # 区分数据输入(S3 URI)和参数输入(值)
                for step_id, value in s3_input_mapping.items():
                    if str(value).startswith('s3://'):
                        # 数据输入: 使用input_前缀
                        input_params[f"input_{step_id}"] = value
                        self.logger.info(f"[Workflow {workflow_invocation.id}] Data input step {step_id}: {value}")
                    else:
                        # 参数输入: 使用param_前缀
                        input_params[f"param_{step_id}"] = value
                        self.logger.info(f"[Workflow {workflow_invocation.id}] Parameter input step {step_id}: {value}")

            except Exception as e:
                self.logger.error(f"[Workflow {workflow_invocation.id}] Failed to upload inputs: {e}")
                # 回退到占位符
                for step in workflow_invocation.workflow.steps:
                    if step.type in ['data_input', 'data_collection_input']:
                        step_id = step.order_index
                        input_s3_path = f"s3://{self.aws_s3_bucket}/workflows/{workflow_invocation.id}/inputs/step_{step_id}/input_data"
                        input_params[f"input_{step_id}"] = input_s3_path

        else:
            # 没有S3配置，使用占位符
            self.logger.warning(f"[Workflow {workflow_invocation.id}] S3 not configured, using placeholders")
            for step in workflow_invocation.workflow.steps:
                if step.type in ['data_input', 'data_collection_input']:
                    step_id = step.order_index
                    input_params[f"input_{step_id}"] = f"placeholder_input_{step_id}"

        return input_params

    def _parse_test_config(self, test_config_path: Path) -> Dict[str, str]:
        """
        通用解析器：从 Nextflow 的 conf/test.config 文件中提取参数

        支持解析 Groovy 语法的 params { ... } 块，例如：
        params {
            input = 'https://...'
            fasta = 'https://...'
            skip_tools = 'fastp,gens'
        }

        Returns:
            参数字典，key 是参数名（不带 -- 前缀），value 是参数值（字符串）
        """
        import re

        try:
            with open(test_config_path, 'r') as f:
                content = f.read()

            # 提取 params { ... } 块
            # 使用大括号计数器来正确提取完整的 params 块（支持嵌套）
            params_start = content.find('params')
            if params_start == -1:
                self.logger.warning("Could not find 'params' keyword in test config")
                return {}

            # 找到第一个开括号
            brace_start = content.find('{', params_start)
            if brace_start == -1:
                self.logger.warning("Could not find opening brace for params block")
                return {}

            # 使用括号计数器找到匹配的闭括号
            brace_count = 0
            brace_end = -1
            for i in range(brace_start, len(content)):
                if content[i] == '{':
                    brace_count += 1
                elif content[i] == '}':
                    brace_count -= 1
                    if brace_count == 0:
                        brace_end = i
                        break

            if brace_end == -1:
                self.logger.warning("Could not find closing brace for params block")
                return {}

            params_block = content[brace_start+1:brace_end]
            self.logger.debug(f"Extracted params block: {len(params_block)} characters")

            # 解析参数：支持多种格式
            # 1. simple_param = 'value'
            # 2. simple_param = "value"
            # 3. simple_param = true/false
            # 4. simple_param = 123
            # 5. simple_param = params.base_path + '/file.txt'

            test_params = {}

            # 先处理带引号的字符串参数（包括字符串插值 ${variable}）
            for match in re.finditer(r'(\w+)\s*=\s*["\']([^"\']+)["\']', params_block):
                param_name = match.group(1)
                param_value = match.group(2)

                # 特殊处理：对于包含 ${projectDir}/assets/ 的参数，尝试映射到 S3 测试数据
                # 例如: gene_annotation = "${projectDir}/assets/gene_annotation.yaml"
                #   -> gene_annotation = "s3://bucket/test_data/drop/gene_annotation.yaml"
                if '${projectDir}/assets/' in param_value:
                    # 提取文件名
                    import os
                    filename = os.path.basename(param_value.replace('${projectDir}/assets/', ''))
                    # 尝试从 S3 加载（假设已上传到 test_data/<pipeline>/）
                    # 获取 pipeline 名称（从 test_config_path）
                    pipeline_name = test_config_path.parent.parent.name.split('_')[0]  # e.g., "drop_1766045589" -> "drop"
                    s3_path = f"s3://{self.aws_s3_bucket}/test_data/{pipeline_name}/{filename}"
                    test_params[param_name] = s3_path
                    self.logger.info(f"   Mapped local path to S3: {param_name} = {s3_path}")
                    continue

                # 跳过包含本地路径变量的参数（${projectDir}, ${launchDir}, ${baseDir}）
                if '${projectDir}' in param_value or '${launchDir}' in param_value or '${baseDir}' in param_value:
                    self.logger.debug(f"   Skipping local path parameter: {param_name} = {param_value}")
                    continue

                # 移除配置相关的元数据参数
                if param_name not in ['config_profile_name', 'config_profile_description']:
                    test_params[param_name] = param_value

            # 处理布尔值和数字（包括整数和小数）
            for match in re.finditer(r'(\w+)\s*=\s*(true|false|\d+\.?\d*)', params_block):
                param_name = match.group(1)
                param_value = match.group(2)
                if param_name not in test_params and param_name not in ['config_profile_name', 'config_profile_description']:
                    test_params[param_name] = param_value

            # 处理字符串插值和拼接（例如：params.base_path + '/file.txt'）
            # 提取 base path 变量
            base_paths = {}
            for match in re.finditer(r'(\w+_base(?:_path)?)\s*=\s*["\']([^"\']+)["\']', params_block):
                base_paths[match.group(1)] = match.group(2)

            # 处理使用 base path 的参数
            for match in re.finditer(r'(\w+)\s*=\s*params\.(\w+)\s*\+\s*["\']([^"\']+)["\']', params_block):
                param_name = match.group(1)
                base_var = match.group(2)
                suffix = match.group(3)
                if base_var in base_paths:
                    test_params[param_name] = base_paths[base_var] + suffix

            self.logger.info(f"📊 Parsed {len(test_params)} parameters from test config")

            return test_params

        except Exception as e:
            self.logger.error(f"Failed to parse test config {test_config_path}: {e}")
            import traceback
            self.logger.error(traceback.format_exc())
            return {}

    def _start_nextflow_workflow(
        self,
        invocation_id: int,
        script_path: Path,
        config_path: Path,
        params: Dict[str, str],
        work_dir: Path,
        use_test_profile: bool = False,
        engine_step = None
    ):
        """
        启动Nextflow工作流执行（本地或远程）

        Args:
            invocation_id: Workflow invocation ID
            script_path: Nextflow main.nf路径
            config_path: Nextflow配置文件路径
            params: 参数字典
            work_dir: 工作目录
            use_test_profile: 是否使用test profile（默认True，与nf-core原生行为一致）
            engine_step: Engine step 对象（用于提取 XML 默认值）

        返回:
            - 本地执行: subprocess.Popen 对象
            - 远程执行: 字典 {remote_exec_info: {...}, process: None}
        """
        # 构建命令
        cmd = [
            self.nextflow_bin,
            'run',
            str(script_path),
            '-c', str(config_path),
            '-resume',  # 🔄 自动启用 resume：失败重跑时自动跳过已完成任务
        ]

        # 🔑 关键修复：添加 -bucket-dir 用于 AWS Batch 任务的数据 staging
        # 这允许本地 workDir（用于主进程的 collectFile 等操作）+ S3 bucket-dir（用于 AWS Batch 任务）
        if self.aws_s3_bucket and self.aws_batch_queue:
            # 从 work_dir 提取 workflow ID
            workflow_id = work_dir.name.replace('workflow_', '')
            s3_bucket_dir = f"s3://{self.aws_s3_bucket}/nextflow_workflows/{workflow_id}/work"
            cmd.extend(['-bucket-dir', s3_bucket_dir])
            self.logger.info(f"📦 S3 bucket-dir for AWS Batch tasks: {s3_bucket_dir}")

        # 🎯 新策略：use_test_profile 只提供参考文件，不替换用户数据
        # 当用户勾选"Use Test Profile"时：
        #   1. 保留用户的输入数据（samplesheet）
        #   2. 自动补充所有缺失的参考基因组文件
        #   3. 不使用 -profile test（避免替换用户数据）
        if use_test_profile:
            self.logger.info("✅ Use Test Profile enabled - will provide reference files while keeping user data")

            # 🎯 通用策略：自动解析 pipeline 的 conf/test.config 文件
            # 从 script_path 中提取 pipeline 目录
            pipeline_dir = script_path.parent
            test_config_path = pipeline_dir / 'conf' / 'test.config'

            if test_config_path.exists():
                self.logger.info(f"📄 Parsing test config: {test_config_path}")
                test_ref_params = self._parse_test_config(test_config_path)

                if test_ref_params:
                    # 🔑 关键修复：当使用 test profile 时，需要移除 XML 默认值，只保留用户显式提供的参数
                    # Galaxy 无法区分"用户填写的值"和"XML默认值"，所以我们需要提取 XML 默认值并移除它们
                    if engine_step:
                        try:
                            tool_defaults = self._extract_tool_defaults(engine_step)
                            self.logger.info(f"🔍 Extracted {len(tool_defaults)} tool XML defaults to filter out")

                            # 移除与 XML 默认值相同的参数（这些很可能是 XML 默认值，而非用户输入）
                            params_to_remove = []
                            for param_name, param_value in params.items():
                                if param_name in tool_defaults and str(param_value) == str(tool_defaults[param_name]):
                                    params_to_remove.append(param_name)
                                    self.logger.debug(f"   Removing XML default: {param_name} = {param_value}")

                            for param_name in params_to_remove:
                                del params[param_name]

                            if params_to_remove:
                                self.logger.info(f"🧹 Removed {len(params_to_remove)} XML default parameters to use test profile values instead")
                        except Exception as e:
                            self.logger.warning(f"Could not extract tool defaults for filtering: {e}")

                    # 只添加用户没有提供的参数（保留用户的 input）
                    added_count = 0
                    for param_name, param_value in test_ref_params.items():
                        # 跳过 input 参数，保留用户提供的数据
                        if param_name == 'input':
                            continue
                        # test_ref_params 的优先级最高，直接覆盖
                        if param_name not in params:
                            params[param_name] = param_value
                            added_count += 1
                        else:
                            # 如果参数已存在，test profile 的值仍然优先
                            self.logger.debug(f"   Overriding {param_name}: {params[param_name]} -> {param_value}")
                            params[param_name] = param_value
                            added_count += 1

                    self.logger.info(f"✅ Added {added_count} reference file parameters from test profile")
                    self.logger.info(f"✅ User's input data (samplesheet) preserved: {params.get('input', 'N/A')}")
                else:
                    self.logger.warning(f"⚠️ Could not parse test config: {test_config_path}")
            else:
                self.logger.warning(f"⚠️ Test config not found: {test_config_path}")

        # 添加Galaxy配置
        cmd.extend([
            # Wave和Fusion已禁用（私有ECR镜像无法通过Wave访问）
            # '-with-wave',
            # '-with-fusion',
            '-with-report',
            '-with-timeline',
            '-with-trace',
        ])

        for param_name, param_value in params.items():
            # 🔑 修复：将所有参数值转换为字符串（处理 bool、int 等类型）
            # 布尔值转换为小写（Nextflow 约定: true/false 而不是 True/False）
            if isinstance(param_value, bool):
                param_value_str = str(param_value).lower()
            else:
                param_value_str = str(param_value)
            cmd.extend(['--' + param_name, param_value_str])

        self.logger.info(f"Starting Nextflow with -resume enabled: {' '.join(cmd)}")
        self.logger.info("🔄 Resume mode: If this workflow was run before, completed tasks will be skipped")

        # 准备环境变量 - 确保AWS凭证传递给Nextflow
        env = os.environ.copy()

        # 🔑 关键修复：从AWS SSO获取临时凭证
        # Nextflow的AWS SDK(Java)不直接支持SSO profiles，需要显式凭证

        # 优先使用环境变量中已有的凭证（避免重复获取和SSL问题）
        if 'AWS_ACCESS_KEY_ID' in os.environ and 'AWS_SECRET_ACCESS_KEY' in os.environ:
            self.logger.info("✅ Using AWS credentials from environment variables")
            # 这些凭证会自动被 env = os.environ.copy() 复制
        else:
            # 只有在环境变量没有凭证时才尝试从 SSO 获取
            aws_profile = os.environ.get('AWS_PROFILE', '')
            if aws_profile:
                try:
                    # 使用boto3从SSO获取临时凭证
                    import boto3
                    session = boto3.Session(profile_name=aws_profile)
                    credentials = session.get_credentials()
                    if credentials:
                        env['AWS_ACCESS_KEY_ID'] = credentials.access_key
                        env['AWS_SECRET_ACCESS_KEY'] = credentials.secret_key
                        if credentials.token:
                            env['AWS_SESSION_TOKEN'] = credentials.token
                        self.logger.info(f"✅ Retrieved AWS SSO credentials for profile: {aws_profile}")
                    else:
                        self.logger.warning(f"⚠️ No credentials found for profile: {aws_profile}")
                except Exception as e:
                    self.logger.error(f"❌ Failed to get AWS SSO credentials: {e}")
                    self.logger.error(f"   Will rely on profile-based authentication (Nextflow may fail if Java AWS SDK doesn't support SSO)")
                    self.logger.error(f"   💡 Workaround: Run 'source export_aws_credentials.sh' before starting Galaxy")

        # 显式传递AWS相关环境变量
        # ⚠️ 重要: 优先使用静态密钥,避免传递 AWS_PROFILE (SSO)
        aws_env_vars = [
            'AWS_ACCESS_KEY_ID',     # 静态密钥 (优先)
            'AWS_SECRET_ACCESS_KEY',
            'AWS_SESSION_TOKEN',
            'AWS_DEFAULT_REGION',
            'AWS_REGION',
            'TOWER_ACCESS_TOKEN',  # Seqera Wave token
            'NXF_HOME',  # Nextflow home directory
            'JAVA_HOME',  # Java home directory
        ]

        # 只有在没有静态密钥时,才传递 AWS_PROFILE
        has_static_keys = ('AWS_ACCESS_KEY_ID' in env and 'AWS_SECRET_ACCESS_KEY' in env)
        if not has_static_keys and 'AWS_PROFILE' in env:
            aws_env_vars.insert(0, 'AWS_PROFILE')  # SSO profile (回退方案)

        for var in aws_env_vars:
            if var in env:
                if var == 'AWS_ACCESS_KEY_ID':
                    self.logger.info(f"Passing {var} to Nextflow subprocess (static key)")
                elif var == 'AWS_PROFILE':
                    self.logger.info(f"Passing {var} to Nextflow subprocess (SSO - may require periodic login)")
                else:
                    self.logger.info(f"Passing {var} to Nextflow subprocess")

        # 确保 AWS 配置文件路径总是被设置（SSO 需要这些）
        import pathlib
        home_dir = pathlib.Path.home()
        if 'AWS_CONFIG_FILE' not in env:
            env['AWS_CONFIG_FILE'] = str(home_dir / '.aws' / 'config')
            self.logger.info(f"Setting AWS_CONFIG_FILE={env['AWS_CONFIG_FILE']}")

        if 'AWS_SHARED_CREDENTIALS_FILE' not in env:
            env['AWS_SHARED_CREDENTIALS_FILE'] = str(home_dir / '.aws' / 'credentials')
            self.logger.info(f"Setting AWS_SHARED_CREDENTIALS_FILE={env['AWS_SHARED_CREDENTIALS_FILE']}")

        # 🔧 修复Mac本地Java SSL握手问题 + HTTP下载重试问题
        # 1. 禁用Nextflow主进程的SSL证书验证（仅影响本地S3访问，不影响容器内任务）
        # 2. 增加 JVM 内存以支持大文件缓冲
        # 3. 配置 AWS SDK 使用文件缓冲而非流式传输（解决 mark/reset 问题）
        nxf_opts = env.get('NXF_OPTS', '')

        # 必需的 JVM 选项
        required_opts = [
            '-Dcom.amazonaws.sdk.disableCertChecking=true',  # SSL 问题
            '-Xms512m',                                       # 最小堆内存
            '-Xmx2g',                                         # 最大堆内存（增加以支持文件缓冲）
            '-Daws.client.socketTimeout=60000',              # Socket 超时 60 秒
            '-Daws.client.connectionTimeout=60000',          # 连接超时 60 秒
        ]

        # 合并选项（避免重复）
        opts_list = nxf_opts.split() if nxf_opts else []
        for opt in required_opts:
            # 检查是否已存在相同的配置项（不同的值）
            opt_key = opt.split('=')[0] if '=' in opt else opt
            # 移除旧的同名配置
            opts_list = [o for o in opts_list if not o.startswith(opt_key)]
            # 添加新配置
            opts_list.append(opt)

        env['NXF_OPTS'] = ' '.join(opts_list)
        self.logger.info(f"Setting NXF_OPTS with enhanced retry and buffering: {env['NXF_OPTS']}")

        # 🚀 检查是否使用远程执行模式
        if self.remote_executor and self.remote_executor.enabled:
            self.logger.info(f"[Workflow {invocation_id}] 🌐 Using REMOTE execution mode")
            self.logger.info(f"   Nextflow will run on: {self.remote_executor.host}")

            try:
                # 启动远程执行
                remote_exec_info = self.remote_executor.start_workflow(
                    invocation_id=invocation_id,
                    local_work_dir=work_dir,
                    nextflow_cmd=cmd
                )

                self.logger.info(f"[Workflow {invocation_id}] ✅ Remote execution started successfully")
                self.logger.info(f"   Remote workspace: {remote_exec_info['remote_workspace']}")
                if 'screen_name' in remote_exec_info:
                    self.logger.info(f"   Screen session: {remote_exec_info['screen_name']}")
                if 'pid' in remote_exec_info:
                    self.logger.info(f"   Process PID: {remote_exec_info['pid']}")

                # 返回远程执行信息（process 为 None）
                return {
                    'remote_exec_info': remote_exec_info,
                    'process': None
                }

            except Exception as e:
                self.logger.error(f"[Workflow {invocation_id}] ❌ Failed to start remote execution: {e}")
                raise

        # 本地执行模式
        self.logger.info(f"[Workflow {invocation_id}] 💻 Using LOCAL execution mode")

        # 启动Nextflow
        stdout_file = work_dir / 'nextflow.out'
        stderr_file = work_dir / 'nextflow.err'

        process = subprocess.Popen(
            cmd,
            stdout=open(stdout_file, 'w'),
            stderr=open(stderr_file, 'w'),
            cwd=work_dir,
            env=env  # 显式传递环境变量
        )

        self.logger.info(f"[Workflow {invocation_id}] ✅ Local execution started (PID: {process.pid})")

        return process

    def check_watched_items(self):
        """
        监控所有活跃的工作流

        这是AsynchronousJobRunner的核心方法
        定期调用以检查状态
        """
        # 1. 监控 workflow 状态（原有逻辑）
        for invocation_id, workflow_state in list(self.active_workflows.items()):
            try:
                self._monitor_workflow_state(invocation_id, workflow_state)
            except Exception as e:
                self.logger.error(f"[Workflow {invocation_id}] Monitoring error: {e}")

        # 2. 触发日志收集（新增）
        # NextflowMonitorService 会收集所有注册的 workflow 的日志
        try:
            self.monitor_service.monitor_all()
        except Exception as e:
            self.logger.error(f"Monitor service error: {e}")

    def _monitor_workflow_state(self, invocation_id, workflow_state: NextflowWorkflowState):
        """
        监控单个工作流状态（本地或远程）

        解析Nextflow日志，更新步骤状态
        """
        # 判断是本地执行还是远程执行
        if workflow_state.remote_exec_info:
            # 远程执行模式
            self._monitor_remote_workflow(invocation_id, workflow_state)
        else:
            # 本地执行模式
            self._monitor_local_workflow(invocation_id, workflow_state)

    def _monitor_local_workflow(self, invocation_id, workflow_state: NextflowWorkflowState):
        """监控本地执行的 workflow"""
        # 检查Nextflow进程
        process = workflow_state.process
        returncode = process.poll()

        # 解析Nextflow日志
        log_file = workflow_state.work_dir / '.nextflow.log'
        if log_file.exists():
            self._parse_nextflow_log(invocation_id, workflow_state, log_file)

        # 进程完成
        if returncode is not None:
            self.logger.info(f"[Workflow {invocation_id}] Nextflow completed with code {returncode}")

            if returncode == 0:
                # 成功：收集输出
                self._collect_workflow_outputs(invocation_id, workflow_state)
                self._mark_workflow_completed(invocation_id, workflow_state)
            else:
                # 失败
                self._mark_workflow_failed(invocation_id, workflow_state, returncode)

            # 移除
            del self.active_workflows[invocation_id]

    def _monitor_remote_workflow(self, invocation_id, workflow_state: NextflowWorkflowState):
        """监控远程执行的 workflow"""
        try:
            # 通过远程执行器检查状态
            status_info = self.remote_executor.check_status(
                invocation_id=invocation_id,
                exec_info=workflow_state.remote_exec_info
            )

            # 更新状态
            current_status = status_info['status']

            # 记录进度信息
            if 'succeeded_count' in status_info:
                self.logger.debug(
                    f"[Workflow {invocation_id}] Remote progress: "
                    f"{status_info['succeeded_count']} tasks succeeded"
                )

            # 检查是否完成
            if current_status == 'completed':
                self.logger.info(f"[Workflow {invocation_id}] Remote workflow completed successfully")

                # 收集输出
                self._collect_workflow_outputs(invocation_id, workflow_state)
                self._mark_workflow_completed(invocation_id, workflow_state)

                # 移除
                del self.active_workflows[invocation_id]

            elif current_status == 'failed':
                error_message = status_info.get('error_message', 'Unknown error')
                self.logger.error(f"[Workflow {invocation_id}] Remote workflow failed: {error_message}")

                # 标记失败
                exit_code = status_info.get('exit_code', 1)
                self._mark_workflow_failed(invocation_id, workflow_state, exit_code)

                # 移除
                del self.active_workflows[invocation_id]

            # else: status == 'running'，继续监控

        except Exception as e:
            self.logger.error(f"[Workflow {invocation_id}] Error monitoring remote workflow: {e}")
            # 不要删除，继续尝试监控

    def _parse_nextflow_log(self, invocation_id, workflow_state, log_file: Path):
        """
        解析Nextflow日志，提取进度信息

        Nextflow日志格式:
        [task-1] Submitted process > STEP_1_SED
        [task-1] Completed process > STEP_1_SED
        """
        try:
            with open(log_file, 'r') as f:
                for line in f:
                    # 提交
                    if 'Submitted process' in line:
                        step_name = self._extract_process_name(line)
                        step_id = self._find_step_id_by_name(workflow_state, step_name)
                        if step_id is not None:
                            workflow_state.step_states[step_id] = 'running'
                            self.logger.info(f"[Workflow {invocation_id}] Step {step_id} running")

                    # 完成
                    elif 'Completed process' in line:
                        step_name = self._extract_process_name(line)
                        step_id = self._find_step_id_by_name(workflow_state, step_name)
                        if step_id is not None:
                            workflow_state.step_states[step_id] = 'completed'
                            self.logger.info(f"[Workflow {invocation_id}] Step {step_id} completed")

                    # 失败
                    elif 'Failed process' in line or 'ERROR' in line:
                        step_name = self._extract_process_name(line)
                        step_id = self._find_step_id_by_name(workflow_state, step_name)
                        if step_id is not None:
                            workflow_state.step_states[step_id] = 'failed'
                            self.logger.error(f"[Workflow {invocation_id}] Step {step_id} failed")

        except Exception as e:
            self.logger.warning(f"[Workflow {invocation_id}] Error parsing log: {e}")

    def _extract_process_name(self, log_line: str) -> Optional[str]:
        """从日志行中提取process名称"""
        # 例: [task-1] Submitted process > STEP_1_SED
        if '>' in log_line:
            parts = log_line.split('>')
            if len(parts) > 1:
                return parts[-1].strip()
        return None

    def _find_step_id_by_name(self, workflow_state, step_name: str) -> Optional[int]:
        """根据process名称查找step_id"""
        for step_id, name in workflow_state.step_mappings.items():
            if name == step_name:
                return step_id
        return None

    def _collect_workflow_outputs(self, invocation_id, workflow_state):
        """
        收集工作流输出

        从S3下载publishDir的结果
        """
        self.logger.info(f"[Workflow {invocation_id}] Collecting outputs...")

        # 使用S3 Manager下载输出数据
        if self.s3_manager:
            try:
                # S3结果路径前缀（使用 outputs 而非 results，与 --outdir 参数一致）
                s3_results_prefix = f"workflows/{invocation_id}/outputs"

                self.logger.info(f"[Workflow {invocation_id}] Downloading outputs from S3 ({s3_results_prefix})...")
                output_mapping = self.s3_manager.download_workflow_outputs(
                    workflow_state.invocation,
                    s3_results_prefix,
                    workflow_state.work_dir
                )

                # 保存输出路径
                for step_id, local_path in output_mapping.items():
                    workflow_state.collected_outputs[step_id] = local_path
                    self.logger.info(f"[Workflow {invocation_id}] Collected outputs for step {step_id}: {local_path}")

                if not output_mapping:
                    self.logger.warning(f"[Workflow {invocation_id}] No outputs downloaded from S3")

            except Exception as e:
                self.logger.error(f"[Workflow {invocation_id}] Failed to download outputs: {e}")
                import traceback
                self.logger.error(f"[Workflow {invocation_id}] Traceback:\n{traceback.format_exc()}")

        else:
            # 回退到本地检查（无S3配置）
            self.logger.info(f"[Workflow {invocation_id}] S3 not configured, checking local results...")
            results_dir = workflow_state.work_dir / 'results'

            for step_id in workflow_state.step_mappings.keys():
                step_output_dir = results_dir / f"step_{step_id}"
                if step_output_dir.exists():
                    self.logger.info(f"[Workflow {invocation_id}] Found local outputs for step {step_id}")
                    workflow_state.collected_outputs[step_id] = step_output_dir
                else:
                    self.logger.warning(f"[Workflow {invocation_id}] No local outputs for step {step_id}")

    def _mark_workflow_completed(self, invocation_id, workflow_state):
        """标记工作流完成"""
        self.logger.info(f"[Workflow {invocation_id}] Workflow completed successfully!")

        try:
            # 创建输出数据集
            self._create_output_datasets(invocation_id, workflow_state)

            # 更新Galaxy WorkflowInvocation状态
            invocation = workflow_state.invocation
            invocation.state = invocation.states.SCHEDULED  # 标记为已完成

            # 提交到数据库
            self.app.sa_session.add(invocation)
            self.app.sa_session.flush()

            self.logger.info(f"[Workflow {invocation_id}] Updated workflow state to completed")

        except Exception as e:
            self.logger.error(f"[Workflow {invocation_id}] Failed to mark as completed: {e}")
            import traceback
            self.logger.error(traceback.format_exc())

    def _mark_workflow_failed(self, invocation_id, workflow_state, returncode):
        """标记工作流失败"""
        self.logger.error(f"[Workflow {invocation_id}] Workflow failed with code {returncode}")

        # 读取错误日志
        stderr_file = workflow_state.work_dir / 'nextflow.err'
        error_msg = f"Nextflow execution failed with return code {returncode}"

        if stderr_file.exists():
            with open(stderr_file, 'r') as f:
                error_log = f.read()
                self.logger.error(f"[Workflow {invocation_id}] Error log:\n{error_log[:1000]}")
                error_msg = f"{error_msg}\n\n{error_log[:500]}"

        try:
            # 更新Galaxy WorkflowInvocation状态
            invocation = workflow_state.invocation
            invocation.state = invocation.states.FAILED

            # 添加错误消息
            from galaxy.schema.invocation import (
                InvocationUnexpectedFailure,
                FailureReason
            )
            failure = InvocationUnexpectedFailure(
                reason=FailureReason.unexpected_failure,
                details=error_msg
            )
            invocation.add_message(failure)

            # 提交到数据库
            self.app.sa_session.add(invocation)
            self.app.sa_session.flush()

            self.logger.info(f"[Workflow {invocation_id}] Updated workflow state to failed")

        except Exception as e:
            self.logger.error(f"[Workflow {invocation_id}] Failed to mark as failed: {e}")
            import traceback
            self.logger.error(traceback.format_exc())

    def _create_output_datasets(self, invocation_id, workflow_state):
        """
        创建输出数据集

        云原生模式: 创建S3元数据引用，不下载数据
        传统模式: 下载S3文件并注册为本地数据集
        """
        self.logger.info(f"[Workflow {invocation_id}] Creating output datasets...")

        # 检查是否使用云原生模式
        if self.cloud_native_mode and self.cloud_data_manager:
            self.logger.info(f"[Workflow {invocation_id}] Using cloud-native mode (data stays in S3)")
            self._create_cloud_output_datasets(invocation_id, workflow_state)
        else:
            self.logger.info(f"[Workflow {invocation_id}] Using traditional mode (downloading from S3)")
            self._create_local_output_datasets(invocation_id, workflow_state)

    def _create_cloud_output_datasets(self, invocation_id, workflow_state):
        """
        创建云原生输出数据集 (数据留在S3，只创建元数据)
        """
        invocation = workflow_state.invocation
        history = invocation.history
        work_dir = str(workflow_state.work_dir)

        try:
            # 使用CloudDataManager创建元数据
            result = self.cloud_data_manager.create_workflow_output_metadata(
                workflow_invocation_id=invocation_id,
                workflow_dir=work_dir,
                history=history
            )

            # 记录结果
            total_files = result.get('total_files', 0)
            total_size = result.get('total_size', 0)

            self.logger.info(
                f"[Workflow {invocation_id}] ✅ Created {total_files} cloud datasets "
                f"(total size: {CloudDataManager._format_size(total_size)}, data in S3)"
            )

            # 显示每个输出
            for output in result.get('outputs', []):
                self.logger.info(
                    f"  - {output['name']}: {output['s3_uri']} "
                    f"({CloudDataManager._format_size(output['size'])})"
                )

        except Exception as e:
            self.logger.error(f"[Workflow {invocation_id}] Failed to create cloud datasets: {e}")
            import traceback
            self.logger.error(traceback.format_exc())

    def _create_local_output_datasets(self, invocation_id, workflow_state):
        """
        创建传统本地输出数据集 (从S3下载数据到本地)
        """
        invocation = workflow_state.invocation
        workflow = invocation.workflow
        history = invocation.history

        created_datasets = 0

        for step in workflow.steps:
            if step.type != 'tool':
                continue

            step_id = step.order_index

            # 检查是否有输出
            if step_id not in workflow_state.collected_outputs:
                self.logger.warning(
                    f"[Workflow {invocation_id}] No outputs collected for step {step_id}"
                )
                continue

            output_dir = workflow_state.collected_outputs[step_id]

            # 🔧 修复：递归遍历所有输出文件（Nextflow输出按模块组织在子目录中）
            import glob
            output_files = glob.glob(str(output_dir / '**' / '*'), recursive=True)
            # 只保留文件，排除目录
            output_files = [f for f in output_files if Path(f).is_file()]

            self.logger.info(
                f"[Workflow {invocation_id}] Found {len(output_files)} output files "
                f"for step {step_id} in {output_dir}"
            )

            for output_file_path in output_files:
                try:
                    dataset = self._create_dataset_from_file(
                        output_file_path,
                        history,
                        step,
                        invocation
                    )

                    if dataset:
                        created_datasets += 1
                        self.logger.info(
                            f"[Workflow {invocation_id}] Created dataset {dataset.id} "
                            f"for step {step_id}: {Path(output_file_path).name}"
                        )

                except Exception as e:
                    self.logger.error(
                        f"[Workflow {invocation_id}] Failed to create dataset "
                        f"from {output_file_path}: {e}"
                    )

        self.logger.info(
            f"[Workflow {invocation_id}] Created {created_datasets} output datasets"
        )

    def _create_dataset_from_file(self, file_path, history, step, invocation):
        """
        从文件创建Galaxy数据集

        参数:
            file_path: 输出文件路径
            history: Galaxy History对象
            step: WorkflowStep对象
            invocation: WorkflowInvocation对象

        返回:
            创建的Dataset对象
        """
        from galaxy import model

        file_path = Path(file_path)

        if not file_path.exists():
            self.logger.warning(f"Output file does not exist: {file_path}")
            return None

        # 创建新数据集
        dataset = model.HistoryDatasetAssociation(
            extension='auto',  # 自动检测格式
            create_dataset=True,
            sa_session=self.app.sa_session,
        )

        # 设置history
        dataset.history = history

        # 设置名称
        dataset.name = f"{step.label or f'Step {step.order_index}'} output: {file_path.name}"

        # 设置可见性
        dataset.visible = True

        # 复制文件到Galaxy数据目录
        try:
            self.app.object_store.update_from_file(
                dataset.dataset,
                file_name=str(file_path),
                create=True
            )

            # 设置数据集状态
            dataset.state = dataset.states.OK
            dataset.blurb = 'Nextflow workflow output'
            dataset.info = f'Generated by Nextflow workflow {invocation.id}'

        except Exception as e:
            self.logger.error(f"Failed to copy file to object store: {e}")
            dataset.state = dataset.states.ERROR
            dataset.info = f'Error importing file: {str(e)}'

        # 添加到session
        self.app.sa_session.add(dataset)
        self.app.sa_session.flush()

        # 设置元数据
        try:
            self.app.datatypes_registry.set_external_metadata_tool.regenerate_imported_metadata_if_needed(
                dataset,
                history,
                self.app.sa_session
            )
        except Exception as e:
            self.logger.warning(f"Failed to set metadata: {e}")

        return dataset

    def stop_job(self, job_wrapper):
        """停止job（工作流级别不适用）"""
        pass

    def recover(self, job, job_wrapper):
        """恢复job（工作流级别不适用）"""
        pass
