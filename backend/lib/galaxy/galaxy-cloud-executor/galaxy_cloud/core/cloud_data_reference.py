"""
Cloud Data Reference

支持用户直接引用云上的数据，跳过数据上传步骤。
"""

from typing import Optional, Dict, Any, List
from dataclasses import dataclass, field, asdict
from enum import Enum
from datetime import datetime
import json


class CloudProvider(str, Enum):
    """云提供商"""
    AWS_S3 = "aws_s3"
    GCP_GCS = "gcp_gcs"
    AZURE_BLOB = "azure_blob"


class AccessMethod(str, Enum):
    """访问方式"""
    PUBLIC = "public"  # 公共数据，无需认证
    IAM_ROLE = "iam_role"  # 使用 IAM Role
    ACCESS_KEY = "access_key"  # 使用 Access Key（不推荐）
    SHARED_ACCESS_SIGNATURE = "sas"  # Azure SAS


@dataclass
class CloudDataAccess:
    """云数据访问配置"""
    method: AccessMethod
    role_arn: Optional[str] = None  # IAM Role ARN (for AWS)
    access_key_id: Optional[str] = None  # Access Key ID (不推荐)
    secret_access_key: Optional[str] = None  # Secret Access Key (不推荐)
    sas_token: Optional[str] = None  # SAS Token (for Azure)

    def to_dict(self) -> Dict[str, Any]:
        """转换为字典"""
        result = {"method": self.method.value}
        if self.role_arn:
            result["role_arn"] = self.role_arn
        if self.access_key_id:
            result["access_key_id"] = self.access_key_id
        # 注意：secret_access_key 和 sas_token 不应该序列化到 JSON
        return result

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'CloudDataAccess':
        """从字典创建"""
        return cls(
            method=AccessMethod(data["method"]),
            role_arn=data.get("role_arn"),
            access_key_id=data.get("access_key_id"),
            sas_token=data.get("sas_token")
        )


@dataclass
class CloudDataMetadata:
    """云数据元数据"""
    file_size: Optional[int] = None  # 文件大小（字节）
    last_modified: Optional[datetime] = None  # 最后修改时间
    checksum: Optional[str] = None  # 校验和 (e.g., "md5:abc123...")
    content_type: Optional[str] = None  # MIME 类型
    validated: bool = False  # 是否已验证
    validation_time: Optional[datetime] = None  # 验证时间
    error_message: Optional[str] = None  # 错误消息（如果验证失败）

    def to_dict(self) -> Dict[str, Any]:
        """转换为字典"""
        return {
            "file_size": self.file_size,
            "last_modified": self.last_modified.isoformat() if self.last_modified else None,
            "checksum": self.checksum,
            "content_type": self.content_type,
            "validated": self.validated,
            "validation_time": self.validation_time.isoformat() if self.validation_time else None,
            "error_message": self.error_message
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'CloudDataMetadata':
        """从字典创建"""
        return cls(
            file_size=data.get("file_size"),
            last_modified=datetime.fromisoformat(data["last_modified"]) if data.get("last_modified") else None,
            checksum=data.get("checksum"),
            content_type=data.get("content_type"),
            validated=data.get("validated", False),
            validation_time=datetime.fromisoformat(data["validation_time"]) if data.get("validation_time") else None,
            error_message=data.get("error_message")
        )


@dataclass
class CloudDataReference:
    """
    云数据引用

    表示存储在云平台（如 AWS S3）的数据，无需上传即可使用。

    Examples:
        # AWS S3 公共数据
        ref = CloudDataReference(
            provider=CloudProvider.AWS_S3,
            path="s3://public-genomes/hg38/genome.fa",
            region="us-west-2",
            access=CloudDataAccess(method=AccessMethod.PUBLIC)
        )

        # AWS S3 私有数据（使用 IAM Role）
        ref = CloudDataReference(
            provider=CloudProvider.AWS_S3,
            path="s3://my-data/sample.fastq",
            region="us-west-2",
            access=CloudDataAccess(
                method=AccessMethod.IAM_ROLE,
                role_arn="arn:aws:iam::123456789012:role/DataAccess"
            )
        )
    """
    provider: CloudProvider
    path: str  # 完整路径，例如 s3://bucket/path/to/file
    region: str  # 区域，例如 us-west-2
    access: CloudDataAccess
    metadata: CloudDataMetadata = field(default_factory=CloudDataMetadata)
    description: Optional[str] = None  # 描述
    tags: Dict[str, str] = field(default_factory=dict)  # 标签

    def __post_init__(self):
        """初始化后验证"""
        self._validate_path()

    def _validate_path(self):
        """验证路径格式"""
        if self.provider == CloudProvider.AWS_S3:
            if not self.path.startswith("s3://"):
                raise ValueError(f"AWS S3 path must start with 's3://': {self.path}")
        elif self.provider == CloudProvider.GCP_GCS:
            if not self.path.startswith("gs://"):
                raise ValueError(f"GCP GCS path must start with 'gs://': {self.path}")
        elif self.provider == CloudProvider.AZURE_BLOB:
            if not self.path.startswith("https://"):
                raise ValueError(f"Azure Blob path must start with 'https://': {self.path}")

    @property
    def bucket(self) -> str:
        """提取 bucket 名称"""
        if self.provider == CloudProvider.AWS_S3:
            # s3://bucket/path/to/file -> bucket
            return self.path.split("/")[2]
        elif self.provider == CloudProvider.GCP_GCS:
            # gs://bucket/path/to/file -> bucket
            return self.path.split("/")[2]
        else:
            raise NotImplementedError(f"Bucket extraction not implemented for {self.provider}")

    @property
    def key(self) -> str:
        """提取 key（文件路径）"""
        if self.provider == CloudProvider.AWS_S3:
            # s3://bucket/path/to/file -> path/to/file
            parts = self.path.split("/", 3)
            return parts[3] if len(parts) > 3 else ""
        elif self.provider == CloudProvider.GCP_GCS:
            # gs://bucket/path/to/file -> path/to/file
            parts = self.path.split("/", 3)
            return parts[3] if len(parts) > 3 else ""
        else:
            raise NotImplementedError(f"Key extraction not implemented for {self.provider}")

    @property
    def filename(self) -> str:
        """提取文件名"""
        return self.key.split("/")[-1] if self.key else ""

    @property
    def is_directory(self) -> bool:
        """判断是否为目录引用"""
        return self.path.endswith("/")

    def to_dict(self) -> Dict[str, Any]:
        """转换为字典（用于 JSON 序列化）"""
        return {
            "type": "cloud_reference",
            "provider": self.provider.value,
            "path": self.path,
            "region": self.region,
            "access": self.access.to_dict(),
            "metadata": self.metadata.to_dict(),
            "description": self.description,
            "tags": self.tags
        }

    def to_json(self) -> str:
        """转换为 JSON 字符串"""
        return json.dumps(self.to_dict(), indent=2)

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'CloudDataReference':
        """从字典创建"""
        return cls(
            provider=CloudProvider(data["provider"]),
            path=data["path"],
            region=data["region"],
            access=CloudDataAccess.from_dict(data["access"]),
            metadata=CloudDataMetadata.from_dict(data.get("metadata", {})),
            description=data.get("description"),
            tags=data.get("tags", {})
        )

    @classmethod
    def from_json(cls, json_str: str) -> 'CloudDataReference':
        """从 JSON 字符串创建"""
        data = json.loads(json_str)
        return cls.from_dict(data)

    def __repr__(self) -> str:
        return f"CloudDataReference(provider={self.provider.value}, path={self.path})"


@dataclass
class ValidationResult:
    """验证结果"""
    accessible: bool  # 是否可访问
    file_exists: bool  # 文件是否存在
    file_size: Optional[int] = None  # 文件大小
    last_modified: Optional[datetime] = None  # 最后修改时间
    error_message: Optional[str] = None  # 错误消息
    warnings: List[str] = field(default_factory=list)  # 警告信息

    @property
    def is_valid(self) -> bool:
        """是否验证通过"""
        return self.accessible and self.file_exists and not self.error_message

    def to_dict(self) -> Dict[str, Any]:
        """转换为字典"""
        return {
            "accessible": self.accessible,
            "file_exists": self.file_exists,
            "file_size": self.file_size,
            "last_modified": self.last_modified.isoformat() if self.last_modified else None,
            "error_message": self.error_message,
            "warnings": self.warnings,
            "is_valid": self.is_valid
        }


# 便捷函数

def create_s3_reference(
    s3_uri: str,
    region: str = "us-west-2",
    role_arn: Optional[str] = None,
    is_public: bool = False,
    description: Optional[str] = None
) -> CloudDataReference:
    """
    创建 S3 数据引用（便捷函数）

    Args:
        s3_uri: S3 URI，例如 s3://bucket/path/to/file
        region: AWS 区域
        role_arn: IAM Role ARN（私有数据时需要）
        is_public: 是否为公共数据
        description: 描述

    Returns:
        CloudDataReference 实例

    Examples:
        # 公共数据
        ref = create_s3_reference(
            "s3://public-genomes/hg38/genome.fa",
            is_public=True,
            description="Human reference genome GRCh38"
        )

        # 私有数据
        ref = create_s3_reference(
            "s3://my-data/sample.fastq",
            role_arn="arn:aws:iam::123456789012:role/DataAccess",
            description="Sample FASTQ file"
        )
    """
    if is_public:
        access = CloudDataAccess(method=AccessMethod.PUBLIC)
    elif role_arn:
        access = CloudDataAccess(method=AccessMethod.IAM_ROLE, role_arn=role_arn)
    else:
        raise ValueError("Either is_public=True or role_arn must be provided")

    return CloudDataReference(
        provider=CloudProvider.AWS_S3,
        path=s3_uri,
        region=region,
        access=access,
        description=description
    )


def create_gcs_reference(
    gcs_uri: str,
    region: str = "us-central1",
    description: Optional[str] = None
) -> CloudDataReference:
    """
    创建 GCS 数据引用（便捷函数）

    Args:
        gcs_uri: GCS URI，例如 gs://bucket/path/to/file
        region: GCP 区域
        description: 描述

    Returns:
        CloudDataReference 实例
    """
    return CloudDataReference(
        provider=CloudProvider.GCP_GCS,
        path=gcs_uri,
        region=region,
        access=CloudDataAccess(method=AccessMethod.PUBLIC),  # TODO: 支持其他访问方式
        description=description
    )
