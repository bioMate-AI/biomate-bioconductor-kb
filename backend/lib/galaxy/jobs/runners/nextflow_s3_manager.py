"""
S3数据管理器

处理Nextflow工作流的S3数据上传和下载
"""

import logging
import os
import subprocess
from pathlib import Path
from typing import Dict, List, Optional

try:
    import boto3
    from botocore.exceptions import ClientError, NoCredentialsError
    BOTO3_AVAILABLE = True
except ImportError:
    BOTO3_AVAILABLE = False

log = logging.getLogger(__name__)


class NextflowS3Manager:
    """
    S3数据管理器

    负责:
    1. 上传workflow输入数据到S3
    2. 从S3下载workflow输出数据
    3. 管理S3路径和本地路径映射
    """

    def __init__(self, s3_bucket: str, aws_region: str = 'us-west-2',
                 user_id: str = "", workflow_id: str = ""):
        self.s3_bucket = s3_bucket
        self.aws_region = aws_region
        self.user_id = user_id        # for billing cost-attribution tags
        self.workflow_id = workflow_id
        self.logger = logging.getLogger(__name__)

        # 初始化 boto3 S3 客户端 (优先使用,支持静态密钥)
        self.s3_client = None
        if BOTO3_AVAILABLE:
            try:
                # boto3 会自动使用环境变量中的 AWS_ACCESS_KEY_ID 或 AWS_PROFILE
                self.s3_client = boto3.client('s3', region_name=aws_region)
                self.logger.info("✅ Initialized boto3 S3 client (supports static keys)")
            except Exception as e:
                self.logger.warning(f"Failed to initialize boto3 S3 client: {e}")

        # 回退: 验证AWS CLI可用 (如果 boto3 不可用)
        if not self.s3_client:
            self._verify_aws_cli()

    def _verify_aws_cli(self):
        """验证AWS CLI是否可用"""
        try:
            result = subprocess.run(
                ['aws', '--version'],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0:
                self.logger.info(f"AWS CLI available: {result.stdout.strip()}")
            else:
                self.logger.warning("AWS CLI not available, S3 operations may fail")
        except Exception as e:
            self.logger.warning(f"AWS CLI check failed: {e}")

    def upload_workflow_inputs(
        self,
        workflow_invocation,
        local_work_dir: Path
    ) -> Dict[int, str]:
        """
        上传workflow输入数据到S3

        参数:
            workflow_invocation: Galaxy WorkflowInvocation对象
            local_work_dir: 本地工作目录

        返回:
            {step_id: s3_uri} 映射
        """
        invocation_id = workflow_invocation.id
        s3_input_mapping = {}

        self.logger.info(f"[Workflow {invocation_id}] Uploading inputs to S3 and collecting parameters...")

        # 遍历所有输入步骤
        for step in workflow_invocation.workflow.steps:
            step_id = step.order_index

            # 处理参数输入
            if step.type == 'parameter_input':
                param_value = self._get_parameter_value(workflow_invocation, step_id)
                if param_value is not None:
                    s3_input_mapping[step_id] = str(param_value)
                    self.logger.info(
                        f"[Workflow {invocation_id}] Parameter step {step_id}: value='{param_value}'"
                    )
                continue

            # 处理数据输入
            if step.type not in ['data_input', 'data_collection_input']:
                continue

            step_id = step.order_index

            # 获取输入数据集
            input_dataset = self._get_input_dataset(workflow_invocation, step_id)

            if not input_dataset:
                self.logger.warning(f"[Workflow {invocation_id}] No dataset for input step {step_id}")
                continue

            # 本地文件路径
            # 使用get_file_name()方法获取文件路径
            try:
                file_name = input_dataset.get_file_name() if hasattr(input_dataset, 'get_file_name') else None
                local_path = Path(file_name) if file_name else None
            except Exception as e:
                self.logger.warning(f"[Workflow {invocation_id}] Error getting file name for step {step_id}: {e}")
                local_path = None

            if not local_path or not local_path.exists():
                self.logger.warning(
                    f"[Workflow {invocation_id}] Input file not found for step {step_id}: {local_path}"
                )
                # 使用占位符（用于测试）
                s3_uri = f"s3://{self.s3_bucket}/workflows/{invocation_id}/inputs/step_{step_id}/input_data"
                s3_input_mapping[step_id] = s3_uri
                continue

            # S3目标路径 - 使用dataset的实际名称，而不是本地文件名
            # dataset.name通常是用户上传时的原始文件名（如 "my_samples.csv"）
            # local_path.name是Galaxy内部存储的文件名（如 "dataset_XXX.dat"）
            dataset_name = input_dataset.name if hasattr(input_dataset, 'name') and input_dataset.name else local_path.name
            s3_key = f"workflows/{invocation_id}/inputs/step_{step_id}/{dataset_name}"
            s3_uri = f"s3://{self.s3_bucket}/{s3_key}"

            # 上传到S3
            success = self._upload_file_to_s3(local_path, s3_uri)

            if success:
                s3_input_mapping[step_id] = s3_uri
                self.logger.info(
                    f"[Workflow {invocation_id}] Uploaded step {step_id}: "
                    f"{local_path} -> {s3_uri}"
                )
            else:
                self.logger.error(
                    f"[Workflow {invocation_id}] Failed to upload step {step_id}"
                )

        self.logger.info(
            f"[Workflow {invocation_id}] Uploaded {len(s3_input_mapping)} inputs"
        )

        return s3_input_mapping

    def _get_input_dataset(self, workflow_invocation, step_id: int):
        """
        获取输入步骤的数据集

        从workflow invocation的input_datasets中查找对应步骤的输入数据
        """
        try:
            # ✅ 使用workflow_invocation.input_datasets而不是workflow_invocation.steps
            # 这是因为Nextflow调度器在WorkflowInvocationSteps创建之前就被调用了

            # input_datasets: List[WorkflowRequestToInputDatasetAssociation]
            # 每个association包含: workflow_step_id, dataset_id, name
            for input_assoc in workflow_invocation.input_datasets:
                # 获取workflow_step对象
                workflow_step = input_assoc.workflow_step
                if workflow_step and workflow_step.order_index == step_id:
                    # 获取关联的dataset
                    dataset = input_assoc.dataset
                    if dataset:
                        self.logger.info(
                            f"[Workflow {workflow_invocation.id}] Found input dataset for step {step_id}: "
                            f"dataset_id={dataset.id}, name={dataset.name}"
                        )
                        return dataset

            # 如果input_datasets中没有找到，尝试从input_dataset_collections获取
            for collection_assoc in workflow_invocation.input_dataset_collections:
                workflow_step = collection_assoc.workflow_step
                if workflow_step and workflow_step.order_index == step_id:
                    # HistoryDatasetCollectionAssociation.collection -> DatasetCollection
                    # DatasetCollection.elements -> list[DatasetCollectionElement]
                    hdca = collection_assoc.dataset_collection
                    if hdca:
                        self.logger.info(
                            f"[Workflow {workflow_invocation.id}] Found input collection for step {step_id}: "
                            f"collection_id={hdca.id}, name={hdca.name}"
                        )
                        # 访问底层的DatasetCollection对象
                        if hasattr(hdca, 'collection'):
                            dataset_collection = hdca.collection
                            if dataset_collection and hasattr(dataset_collection, 'elements'):
                                elements = dataset_collection.elements
                                if elements and len(elements) > 0:
                                    element = elements[0]
                                    if hasattr(element, 'dataset_instance') and element.dataset_instance:
                                        self.logger.info(
                                            f"[Workflow {workflow_invocation.id}] Using first element from collection"
                                        )
                                        return element.dataset_instance
                        else:
                            # 如果hdca本身就是DatasetCollection，直接访问elements
                            if hasattr(hdca, 'elements'):
                                elements = hdca.elements
                                if elements and len(elements) > 0:
                                    element = elements[0]
                                    if hasattr(element, 'dataset_instance') and element.dataset_instance:
                                        self.logger.info(
                                            f"[Workflow {workflow_invocation.id}] Using first element from collection"
                                        )
                                        return element.dataset_instance

            self.logger.warning(
                f"[Workflow {workflow_invocation.id}] No input dataset found for step {step_id}"
            )

        except Exception as e:
            self.logger.error(f"Error getting input dataset for step {step_id}: {e}")
            import traceback
            self.logger.error(traceback.format_exc())

        return None

    def _get_parameter_value(self, workflow_invocation, step_id: int):
        """
        获取参数输入步骤的参数值

        从workflow invocation的input_step_parameters中查找对应步骤的参数值
        """
        try:
            # input_step_parameters: Dict mapping step_id to parameter value
            # 检查workflow_invocation是否有input_step_parameters属性
            if hasattr(workflow_invocation, 'input_step_parameters'):
                params = workflow_invocation.input_step_parameters
                if params and step_id in params:
                    value = params[step_id]
                    self.logger.info(
                        f"[Workflow {workflow_invocation.id}] Found parameter for step {step_id}: value='{value}'"
                    )
                    return value

            # 尝试从steps中获取tool_inputs
            for step in workflow_invocation.workflow.steps:
                if step.order_index == step_id and step.type == 'parameter_input':
                    # 从step的tool_inputs中获取默认值
                    if hasattr(step, 'tool_inputs') and step.tool_inputs:
                        # tool_inputs可能包含默认值
                        if isinstance(step.tool_inputs, dict):
                            default_value = step.tool_inputs.get('default', step.tool_inputs.get('value', None))
                            if default_value is not None:
                                self.logger.info(
                                    f"[Workflow {workflow_invocation.id}] Using default parameter for step {step_id}: value='{default_value}'"
                                )
                                return default_value

            self.logger.warning(
                f"[Workflow {workflow_invocation.id}] No parameter value found for step {step_id}, using placeholder"
            )
            return "PLACEHOLDER_PARAM_VALUE"

        except Exception as e:
            self.logger.error(f"Error getting parameter value for step {step_id}: {e}")
            import traceback
            self.logger.error(traceback.format_exc())
            return "ERROR_PARAM_VALUE"

    def _upload_file_to_s3(self, local_path: Path, s3_uri: str) -> bool:
        """
        上传单个文件到S3

        优先使用 boto3 (支持静态密钥),回退到 aws CLI
        """
        # 方法 1: 使用 boto3 (推荐,支持静态密钥)
        if self.s3_client:
            try:
                self.logger.info(f"Uploading {local_path} to {s3_uri} (via boto3)")

                # 解析 S3 URI: s3://bucket/key
                if not s3_uri.startswith('s3://'):
                    raise ValueError(f"Invalid S3 URI: {s3_uri}")

                s3_uri_parts = s3_uri[5:].split('/', 1)
                bucket = s3_uri_parts[0]
                key = s3_uri_parts[1] if len(s3_uri_parts) > 1 else ''

                # 上传文件，附加 billing 标签
                extra_args: dict = {}
                if self.user_id:
                    extra_args["Tagging"] = (
                        f"user_id={self.user_id}&workflow_id={self.workflow_id}"
                    )
                self.s3_client.upload_file(
                    str(local_path), bucket, key,
                    ExtraArgs=extra_args if extra_args else None
                )

                self.logger.info(f"✅ Upload successful (boto3): {s3_uri}")
                return True

            except ClientError as e:
                self.logger.error(f"❌ boto3 upload failed: {e}")
                # 回退到 AWS CLI
            except Exception as e:
                self.logger.error(f"❌ boto3 upload error: {e}")
                # 回退到 AWS CLI

        # 方法 2: 回退到 AWS CLI (仅在 boto3 失败时使用)
        try:
            self.logger.info(f"Uploading {local_path} to {s3_uri} (via AWS CLI)")

            cmd = [
                'aws', 's3', 'cp',
                str(local_path),
                s3_uri,
                '--region', self.aws_region
            ]

            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=300  # 5分钟超时
            )

            if result.returncode == 0:
                self.logger.info(f"✅ Upload successful (AWS CLI): {s3_uri}")
                return True
            else:
                self.logger.error(f"❌ Upload failed: {result.stderr}")
                return False

        except subprocess.TimeoutExpired:
            self.logger.error(f"❌ Upload timeout: {local_path}")
            return False
        except Exception as e:
            self.logger.error(f"❌ Upload error: {e}")
            return False

    def download_workflow_outputs(
        self,
        workflow_invocation,
        s3_results_prefix: str,
        local_work_dir: Path
    ) -> Dict[int, Path]:
        """
        从S3下载workflow输出数据

        🔧 重新设计：Nextflow的--outdir输出是按模块组织的（如 01_prealign/pretrim_fastqc/），
        而非按Galaxy步骤组织（step_X/）。因此我们需要：
        1. 下载整个outputs目录
        2. 将输出映射到Galaxy的workflow步骤

        参数:
            workflow_invocation: Galaxy WorkflowInvocation对象
            s3_results_prefix: S3结果目录前缀（如 workflows/686/outputs）
            local_work_dir: 本地工作目录

        返回:
            {step_id: local_path} 映射
        """
        invocation_id = workflow_invocation.id
        output_mapping = {}

        self.logger.info(f"[Workflow {invocation_id}] Downloading outputs from S3...")
        self.logger.info(f"[Workflow {invocation_id}] S3 prefix: s3://{self.s3_bucket}/{s3_results_prefix}")

        # 本地输出目录（下载整个outputs目录结构）
        local_outputs_dir = local_work_dir / 'outputs'
        local_outputs_dir.mkdir(parents=True, exist_ok=True)

        # 下载整个outputs目录（包含所有Nextflow模块的输出）
        s3_outputs_uri = f"s3://{self.s3_bucket}/{s3_results_prefix}/"
        success = self._download_s3_directory(s3_outputs_uri, local_outputs_dir)

        if not success:
            self.logger.warning(
                f"[Workflow {invocation_id}] Failed to download outputs from {s3_outputs_uri}"
            )
            return output_mapping

        # 检查下载的文件
        downloaded_files = list(local_outputs_dir.rglob('*'))
        downloaded_files = [f for f in downloaded_files if f.is_file()]

        self.logger.info(
            f"[Workflow {invocation_id}] Downloaded {len(downloaded_files)} files from S3"
        )

        # 打印前10个文件路径用于调试
        if downloaded_files:
            self.logger.info("[Workflow {invocation_id}] Sample output files:")
            for f in downloaded_files[:10]:
                rel_path = f.relative_to(local_outputs_dir)
                self.logger.info(f"  - {rel_path}")
            if len(downloaded_files) > 10:
                self.logger.info(f"  ... and {len(downloaded_files) - 10} more files")

        # 🔧 为每个workflow步骤创建映射
        # 策略：将整个outputs目录映射到第一个tool步骤
        # Galaxy会自动根据output名称匹配到正确的输出数据集
        for step in workflow_invocation.workflow.steps:
            if step.type == 'tool':
                step_id = step.order_index
                # 所有输出都在同一个目录下
                output_mapping[step_id] = local_outputs_dir
                self.logger.info(
                    f"[Workflow {invocation_id}] Mapped outputs to step {step_id}"
                )
                # 只映射到第一个tool步骤即可
                break

        if not output_mapping:
            self.logger.warning(
                f"[Workflow {invocation_id}] No tool steps found in workflow"
            )

        return output_mapping

    def _download_s3_directory(self, s3_uri: str, local_dir: Path) -> bool:
        """
        下载S3目录到本地

        使用aws s3 sync命令
        """
        try:
            self.logger.info(f"Downloading {s3_uri} to {local_dir}")

            cmd = [
                'aws', 's3', 'sync',
                s3_uri,
                str(local_dir),
                '--region', self.aws_region
            ]

            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=600  # 10分钟超时
            )

            if result.returncode == 0:
                # 检查是否有文件下载
                downloaded_files = list(local_dir.glob('*'))
                if downloaded_files:
                    self.logger.info(
                        f"Download successful: {len(downloaded_files)} files"
                    )
                    return True
                else:
                    self.logger.warning("No files downloaded (directory may be empty)")
                    return False
            else:
                self.logger.error(f"Download failed: {result.stderr}")
                return False

        except subprocess.TimeoutExpired:
            self.logger.error(f"Download timeout: {s3_uri}")
            return False
        except Exception as e:
            self.logger.error(f"Download error: {e}")
            return False

    def cleanup_workflow_s3_data(self, workflow_invocation):
        """
        清理workflow的S3数据（可选）

        用于释放S3存储空间
        """
        invocation_id = workflow_invocation.id
        s3_prefix = f"workflows/{invocation_id}/"

        self.logger.info(f"[Workflow {invocation_id}] Cleaning up S3 data: {s3_prefix}")

        try:
            cmd = [
                'aws', 's3', 'rm',
                f"s3://{self.s3_bucket}/{s3_prefix}",
                '--recursive',
                '--region', self.aws_region
            ]

            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=300
            )

            if result.returncode == 0:
                self.logger.info(f"[Workflow {invocation_id}] S3 cleanup successful")
                return True
            else:
                self.logger.warning(f"[Workflow {invocation_id}] S3 cleanup failed: {result.stderr}")
                return False

        except Exception as e:
            self.logger.error(f"[Workflow {invocation_id}] S3 cleanup error: {e}")
            return False

    def get_s3_file_size(self, s3_uri: str) -> Optional[int]:
        """获取S3文件大小（字节）"""
        try:
            cmd = [
                'aws', 's3', 'ls',
                s3_uri,
                '--region', self.aws_region
            ]

            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=30
            )

            if result.returncode == 0 and result.stdout:
                # 解析输出: 2024-01-01 12:00:00  1234 filename
                parts = result.stdout.strip().split()
                if len(parts) >= 3:
                    return int(parts[2])

        except Exception as e:
            self.logger.warning(f"Failed to get S3 file size: {e}")

        return None

    def verify_s3_upload(self, local_path: Path, s3_uri: str) -> bool:
        """
        验证S3上传是否成功

        比较本地文件大小和S3文件大小
        """
        try:
            local_size = local_path.stat().st_size
            s3_size = self.get_s3_file_size(s3_uri)

            if s3_size is not None and local_size == s3_size:
                self.logger.info(f"Upload verified: {s3_uri} ({local_size} bytes)")
                return True
            else:
                self.logger.warning(
                    f"Upload verification failed: local={local_size}, s3={s3_size}"
                )
                return False

        except Exception as e:
            self.logger.warning(f"Upload verification error: {e}")
            return False
