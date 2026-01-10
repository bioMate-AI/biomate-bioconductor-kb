"""
Cloud Data Validator

验证云数据引用的可访问性和有效性。
"""

import boto3
import logging
from typing import Optional, List
from datetime import datetime
from botocore.exceptions import ClientError, BotoCoreError

from .cloud_data_reference import (
    CloudDataReference,
    CloudProvider,
    AccessMethod,
    ValidationResult
)


logger = logging.getLogger(__name__)


class CloudDataValidator:
    """云数据验证器"""

    def __init__(self, region: Optional[str] = None):
        """
        初始化验证器

        Args:
            region: 默认 AWS 区域
        """
        self.region = region or "us-west-2"
        self._s3_clients = {}  # 缓存 S3 客户端

    def _get_s3_client(self, region: str, role_arn: Optional[str] = None):
        """
        获取 S3 客户端（带缓存）

        Args:
            region: AWS 区域
            role_arn: IAM Role ARN（可选）

        Returns:
            boto3 S3 客户端
        """
        cache_key = f"{region}:{role_arn or 'default'}"

        if cache_key not in self._s3_clients:
            if role_arn:
                # 使用 IAM Role
                sts_client = boto3.client('sts', region_name=region)
                assumed_role = sts_client.assume_role(
                    RoleArn=role_arn,
                    RoleSessionName='GalaxyCloudDataValidator'
                )
                credentials = assumed_role['Credentials']

                s3_client = boto3.client(
                    's3',
                    region_name=region,
                    aws_access_key_id=credentials['AccessKeyId'],
                    aws_secret_access_key=credentials['SecretAccessKey'],
                    aws_session_token=credentials['SessionToken']
                )
            else:
                # 使用默认凭证
                s3_client = boto3.client('s3', region_name=region)

            self._s3_clients[cache_key] = s3_client

        return self._s3_clients[cache_key]

    async def validate(self, cloud_ref: CloudDataReference) -> ValidationResult:
        """
        验证云数据引用

        Args:
            cloud_ref: 云数据引用

        Returns:
            ValidationResult 验证结果
        """
        if cloud_ref.provider == CloudProvider.AWS_S3:
            return await self._validate_s3(cloud_ref)
        elif cloud_ref.provider == CloudProvider.GCP_GCS:
            return await self._validate_gcs(cloud_ref)
        elif cloud_ref.provider == CloudProvider.AZURE_BLOB:
            return await self._validate_azure(cloud_ref)
        else:
            return ValidationResult(
                accessible=False,
                file_exists=False,
                error_message=f"Unsupported provider: {cloud_ref.provider}"
            )

    async def _validate_s3(self, cloud_ref: CloudDataReference) -> ValidationResult:
        """
        验证 AWS S3 数据引用

        Args:
            cloud_ref: 云数据引用

        Returns:
            ValidationResult 验证结果
        """
        try:
            # 获取 S3 客户端
            role_arn = cloud_ref.access.role_arn if cloud_ref.access.method == AccessMethod.IAM_ROLE else None
            s3_client = self._get_s3_client(cloud_ref.region, role_arn)

            bucket = cloud_ref.bucket
            key = cloud_ref.key

            # 检查文件是否存在
            try:
                response = s3_client.head_object(Bucket=bucket, Key=key)

                # 提取元数据
                file_size = response.get('ContentLength')
                last_modified = response.get('LastModified')
                content_type = response.get('ContentType')
                etag = response.get('ETag', '').strip('"')

                # 更新云引用的元数据
                cloud_ref.metadata.file_size = file_size
                cloud_ref.metadata.last_modified = last_modified
                cloud_ref.metadata.content_type = content_type
                cloud_ref.metadata.checksum = f"etag:{etag}"
                cloud_ref.metadata.validated = True
                cloud_ref.metadata.validation_time = datetime.now()

                # 检查警告
                warnings = []

                # 检查文件大小
                if file_size and file_size > 100 * 1024 * 1024 * 1024:  # > 100 GB
                    warnings.append(f"Large file size: {file_size / (1024**3):.2f} GB")

                # 检查跨区域访问
                try:
                    bucket_location = s3_client.get_bucket_location(Bucket=bucket)
                    bucket_region = bucket_location.get('LocationConstraint') or 'us-east-1'
                    if bucket_region != cloud_ref.region:
                        warnings.append(
                            f"Cross-region access: bucket in {bucket_region}, "
                            f"but specified region is {cloud_ref.region}. "
                            f"This may incur additional costs and latency."
                        )
                except ClientError:
                    pass  # 无权限获取 bucket 位置，忽略

                return ValidationResult(
                    accessible=True,
                    file_exists=True,
                    file_size=file_size,
                    last_modified=last_modified,
                    warnings=warnings
                )

            except ClientError as e:
                error_code = e.response.get('Error', {}).get('Code', '')

                if error_code == '404' or error_code == 'NoSuchKey':
                    return ValidationResult(
                        accessible=True,  # 可以访问 bucket，但文件不存在
                        file_exists=False,
                        error_message=f"File not found: {cloud_ref.path}"
                    )
                elif error_code == '403' or error_code == 'AccessDenied':
                    return ValidationResult(
                        accessible=False,
                        file_exists=False,
                        error_message=f"Access denied: {cloud_ref.path}. Check IAM permissions."
                    )
                else:
                    return ValidationResult(
                        accessible=False,
                        file_exists=False,
                        error_message=f"S3 error ({error_code}): {str(e)}"
                    )

        except BotoCoreError as e:
            return ValidationResult(
                accessible=False,
                file_exists=False,
                error_message=f"AWS connection error: {str(e)}"
            )
        except Exception as e:
            logger.exception(f"Unexpected error validating S3 reference: {cloud_ref.path}")
            return ValidationResult(
                accessible=False,
                file_exists=False,
                error_message=f"Unexpected error: {str(e)}"
            )

    async def _validate_gcs(self, cloud_ref: CloudDataReference) -> ValidationResult:
        """验证 GCP GCS 数据引用（TODO）"""
        return ValidationResult(
            accessible=False,
            file_exists=False,
            error_message="GCS validation not yet implemented"
        )

    async def _validate_azure(self, cloud_ref: CloudDataReference) -> ValidationResult:
        """验证 Azure Blob 数据引用（TODO）"""
        return ValidationResult(
            accessible=False,
            file_exists=False,
            error_message="Azure Blob validation not yet implemented"
        )

    async def validate_directory(self, cloud_ref: CloudDataReference, max_files: int = 1000) -> ValidationResult:
        """
        验证目录引用

        Args:
            cloud_ref: 云数据引用（目录）
            max_files: 最多列出的文件数

        Returns:
            ValidationResult 验证结果
        """
        if not cloud_ref.is_directory:
            return ValidationResult(
                accessible=False,
                file_exists=False,
                error_message="Not a directory reference (path must end with '/')"
            )

        if cloud_ref.provider == CloudProvider.AWS_S3:
            return await self._validate_s3_directory(cloud_ref, max_files)
        else:
            return ValidationResult(
                accessible=False,
                file_exists=False,
                error_message=f"Directory validation not implemented for {cloud_ref.provider}"
            )

    async def _validate_s3_directory(self, cloud_ref: CloudDataReference, max_files: int) -> ValidationResult:
        """验证 S3 目录"""
        try:
            role_arn = cloud_ref.access.role_arn if cloud_ref.access.method == AccessMethod.IAM_ROLE else None
            s3_client = self._get_s3_client(cloud_ref.region, role_arn)

            bucket = cloud_ref.bucket
            prefix = cloud_ref.key

            # 列出目录中的文件
            response = s3_client.list_objects_v2(
                Bucket=bucket,
                Prefix=prefix,
                MaxKeys=max_files
            )

            if 'Contents' not in response or len(response['Contents']) == 0:
                return ValidationResult(
                    accessible=True,
                    file_exists=False,
                    error_message=f"Directory is empty or does not exist: {cloud_ref.path}"
                )

            # 计算总大小
            total_size = sum(obj.get('Size', 0) for obj in response['Contents'])
            file_count = len(response['Contents'])

            warnings = []
            if response.get('IsTruncated'):
                warnings.append(f"Directory contains more than {max_files} files. Only first {max_files} validated.")

            return ValidationResult(
                accessible=True,
                file_exists=True,
                file_size=total_size,
                warnings=warnings + [f"Directory contains {file_count} files"]
            )

        except ClientError as e:
            error_code = e.response.get('Error', {}).get('Code', '')
            if error_code == '403' or error_code == 'AccessDenied':
                return ValidationResult(
                    accessible=False,
                    file_exists=False,
                    error_message=f"Access denied: {cloud_ref.path}"
                )
            else:
                return ValidationResult(
                    accessible=False,
                    file_exists=False,
                    error_message=f"S3 error: {str(e)}"
                )
        except Exception as e:
            logger.exception(f"Error validating S3 directory: {cloud_ref.path}")
            return ValidationResult(
                accessible=False,
                file_exists=False,
                error_message=f"Unexpected error: {str(e)}"
            )

    async def batch_validate(self, cloud_refs: List[CloudDataReference]) -> List[ValidationResult]:
        """
        批量验证多个云数据引用

        Args:
            cloud_refs: 云数据引用列表

        Returns:
            ValidationResult 列表
        """
        # TODO: 实现并行验证以提高性能
        results = []
        for cloud_ref in cloud_refs:
            result = await self.validate(cloud_ref)
            results.append(result)
        return results


# 便捷函数

async def validate_s3_reference(
    s3_uri: str,
    region: str = "us-west-2",
    role_arn: Optional[str] = None
) -> ValidationResult:
    """
    验证 S3 数据引用（便捷函数）

    Args:
        s3_uri: S3 URI
        region: AWS 区域
        role_arn: IAM Role ARN

    Returns:
        ValidationResult

    Examples:
        # 验证公共数据
        result = await validate_s3_reference("s3://public-genomes/hg38/genome.fa")
        if result.is_valid:
            print(f"File size: {result.file_size} bytes")

        # 验证私有数据
        result = await validate_s3_reference(
            "s3://my-data/sample.fastq",
            role_arn="arn:aws:iam::123456789012:role/DataAccess"
        )
    """
    from .cloud_data_reference import create_s3_reference

    # 创建引用
    is_public = role_arn is None
    cloud_ref = create_s3_reference(s3_uri, region, role_arn, is_public)

    # 验证
    validator = CloudDataValidator(region)
    return await validator.validate(cloud_ref)
