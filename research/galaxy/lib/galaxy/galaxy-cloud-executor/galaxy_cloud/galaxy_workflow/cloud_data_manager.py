"""
Cloud Data Manager Extension

扩展 GalaxyDataManager 以支持云数据引用功能。
用户可以直接引用云上的数据，跳过上传步骤。
"""

import logging
from typing import Dict, List, Optional, Any, Union
from dataclasses import dataclass

from galaxy_cloud.core.cloud_data_reference import (
    CloudDataReference,
    CloudProvider,
    ValidationResult
)
from galaxy_cloud.core.cloud_data_validator import CloudDataValidator

from .models import DatasetInfo, WorkflowRunConfig


logger = logging.getLogger(__name__)


@dataclass
class PreparedInput:
    """
    准备好的输入数据

    支持两种类型：
    1. 本地文件 → 需要上传到 S3
    2. 云引用 → 直接使用云路径
    """
    name: str  # 输入名称
    cloud_uri: str  # S3/GCS/Azure URI
    skip_upload: bool  # 是否跳过上传
    is_cloud_reference: bool  # 是否为云引用
    access_role: Optional[str] = None  # IAM Role ARN（如果需要）
    local_path: Optional[str] = None  # 本地路径（如果是本地文件）
    dataset_info: Optional[DatasetInfo] = None  # Dataset 信息
    cloud_reference: Optional[CloudDataReference] = None  # 云引用对象


class CloudDataManager:
    """
    云数据管理器

    扩展 DataManager 功能，支持：
    1. 传统方式：本地文件 → 上传到 S3 → 云执行
    2. 云引用方式：直接使用云上数据 → 跳过上传 → 云执行
    """

    def __init__(self, region: str = "us-west-2"):
        """
        初始化云数据管理器

        Args:
            region: 默认 AWS 区域
        """
        self.region = region
        self.validator = CloudDataValidator(region)
        self.logger = logging.getLogger(f"{self.__class__.__module__}.{self.__class__.__name__}")

        # 缓存验证结果
        self._validation_cache: Dict[str, ValidationResult] = {}

    async def prepare_input_data(
        self,
        inputs: List[Union[DatasetInfo, CloudDataReference]],
        run_config: WorkflowRunConfig,
        data_manager: Any  # GalaxyDataManager 实例
    ) -> List[PreparedInput]:
        """
        准备输入数据

        支持混合输入：
        - 本地文件：通过 data_manager 上传到 S3
        - 云引用：直接使用云路径，跳过上传

        Args:
            inputs: 输入列表（可以是 DatasetInfo 或 CloudDataReference）
            run_config: Workflow 运行配置
            data_manager: GalaxyDataManager 实例（用于上传本地文件）

        Returns:
            PreparedInput 列表

        Examples:
            # 混合输入示例
            inputs = [
                # 云引用：参考基因组（3 GB，已在云上）
                CloudDataReference(
                    provider=CloudProvider.AWS_S3,
                    path="s3://public-genomes/hg38/genome.fa",
                    region="us-west-2",
                    access=CloudDataAccess(method=AccessMethod.PUBLIC)
                ),
                # 本地文件：样本数据（100 MB，用户上传）
                DatasetInfo(
                    dataset_id="123",
                    file_path="/galaxy/data/sample.fastq",
                    file_name="sample.fastq",
                    ext="fastq"
                )
            ]

            prepared = await cloud_data_manager.prepare_input_data(
                inputs, run_config, data_manager
            )

            # 结果：
            # prepared[0]: 云引用，skip_upload=True
            # prepared[1]: 本地文件，skip_upload=False，已上传到 S3
        """
        prepared_inputs = []

        for idx, input_item in enumerate(inputs):
            if isinstance(input_item, CloudDataReference):
                # 云引用：验证并直接使用
                prepared = await self._prepare_cloud_reference(input_item, idx)
                prepared_inputs.append(prepared)

            elif isinstance(input_item, DatasetInfo):
                # 本地文件：上传到 S3
                prepared = await self._prepare_local_file(input_item, run_config, data_manager, idx)
                prepared_inputs.append(prepared)

            else:
                raise TypeError(f"Unsupported input type: {type(input_item)}")

        return prepared_inputs

    async def _prepare_cloud_reference(
        self,
        cloud_ref: CloudDataReference,
        index: int
    ) -> PreparedInput:
        """
        准备云引用输入

        验证云路径，但不上传数据。

        Args:
            cloud_ref: 云数据引用
            index: 输入索引

        Returns:
            PreparedInput
        """
        self.logger.info(f"Preparing cloud reference: {cloud_ref.path}")

        # 验证云引用（带缓存）
        cache_key = f"{cloud_ref.provider}:{cloud_ref.path}"
        if cache_key in self._validation_cache:
            validation_result = self._validation_cache[cache_key]
            self.logger.info(f"Using cached validation result for {cloud_ref.path}")
        else:
            validation_result = await self.validator.validate(cloud_ref)
            self._validation_cache[cache_key] = validation_result

        # 检查验证结果
        if not validation_result.is_valid:
            error_msg = f"Cloud reference validation failed: {validation_result.error_message}"
            self.logger.error(error_msg)
            raise ValueError(error_msg)

        # 输出警告（如果有）
        for warning in validation_result.warnings:
            self.logger.warning(f"Cloud reference warning: {warning}")

        # 返回准备好的输入
        return PreparedInput(
            name=f"input_{index}",
            cloud_uri=cloud_ref.path,
            skip_upload=True,  # 关键：跳过上传
            is_cloud_reference=True,
            access_role=cloud_ref.access.role_arn,
            cloud_reference=cloud_ref
        )

    async def _prepare_local_file(
        self,
        dataset_info: DatasetInfo,
        run_config: WorkflowRunConfig,
        data_manager: Any,
        index: int
    ) -> PreparedInput:
        """
        准备本地文件输入

        上传本地文件到 S3。

        Args:
            dataset_info: Dataset 信息
            run_config: Workflow 运行配置
            data_manager: GalaxyDataManager 实例
            index: 输入索引

        Returns:
            PreparedInput
        """
        self.logger.info(f"Preparing local file: {dataset_info.file_path}")

        # 使用 GalaxyDataManager 上传文件到 S3
        cloud_uri = await data_manager.stage_dataset(dataset_info, run_config)

        return PreparedInput(
            name=f"input_{index}",
            cloud_uri=cloud_uri,
            skip_upload=False,  # 已经上传
            is_cloud_reference=False,
            local_path=dataset_info.file_path,
            dataset_info=dataset_info
        )

    async def validate_cloud_references(
        self,
        cloud_refs: List[CloudDataReference]
    ) -> Dict[str, ValidationResult]:
        """
        批量验证云引用

        Args:
            cloud_refs: 云数据引用列表

        Returns:
            字典：path -> ValidationResult
        """
        results = {}

        for cloud_ref in cloud_refs:
            result = await self.validator.validate(cloud_ref)
            results[cloud_ref.path] = result

        return results

    def get_validation_summary(
        self,
        validation_results: Dict[str, ValidationResult]
    ) -> Dict[str, Any]:
        """
        获取验证摘要

        Args:
            validation_results: 验证结果字典

        Returns:
            摘要信息
        """
        total = len(validation_results)
        valid = sum(1 for r in validation_results.values() if r.is_valid)
        invalid = total - valid

        total_size = sum(
            r.file_size for r in validation_results.values()
            if r.file_size is not None
        )

        errors = {
            path: result.error_message
            for path, result in validation_results.items()
            if result.error_message
        }

        warnings = {
            path: result.warnings
            for path, result in validation_results.items()
            if result.warnings
        }

        return {
            "total": total,
            "valid": valid,
            "invalid": invalid,
            "total_size_bytes": total_size,
            "total_size_gb": total_size / (1024 ** 3) if total_size else 0,
            "errors": errors,
            "warnings": warnings
        }

    async def create_job_input_config(
        self,
        prepared_inputs: List[PreparedInput]
    ) -> Dict[str, Any]:
        """
        创建作业输入配置

        生成 AWS Batch 作业所需的输入配置。

        Args:
            prepared_inputs: 准备好的输入列表

        Returns:
            作业输入配置
        """
        input_config = {
            "inputs": [],
            "environment": {}
        }

        for prepared in prepared_inputs:
            input_entry = {
                "name": prepared.name,
                "s3_uri": prepared.cloud_uri,
                "is_cloud_reference": prepared.is_cloud_reference
            }

            if prepared.access_role:
                input_entry["access_role"] = prepared.access_role

            if prepared.dataset_info:
                input_entry["galaxy_dataset_id"] = prepared.dataset_info.dataset_id
                input_entry["file_type"] = prepared.dataset_info.ext

            input_config["inputs"].append(input_entry)

            # 设置环境变量（工具可能需要）
            env_var_name = f"INPUT_{prepared.name.upper()}_S3"
            input_config["environment"][env_var_name] = prepared.cloud_uri

        return input_config


# 便捷函数

async def prepare_mixed_inputs(
    local_files: List[DatasetInfo],
    cloud_references: List[CloudDataReference],
    run_config: WorkflowRunConfig,
    data_manager: Any,
    region: str = "us-west-2"
) -> List[PreparedInput]:
    """
    准备混合输入（便捷函数）

    Args:
        local_files: 本地文件列表
        cloud_references: 云引用列表
        run_config: Workflow 运行配置
        data_manager: GalaxyDataManager 实例
        region: AWS 区域

    Returns:
        PreparedInput 列表

    Examples:
        # 准备混合输入
        prepared = await prepare_mixed_inputs(
            local_files=[
                DatasetInfo(dataset_id="123", file_path="/data/sample.fastq", ...)
            ],
            cloud_references=[
                create_s3_reference("s3://public-genomes/hg38/genome.fa", is_public=True)
            ],
            run_config=run_config,
            data_manager=data_manager
        )
    """
    cloud_manager = CloudDataManager(region)

    # 合并输入
    all_inputs = list(cloud_references) + list(local_files)

    return await cloud_manager.prepare_input_data(all_inputs, run_config, data_manager)
