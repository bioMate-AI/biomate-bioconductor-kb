# 云数据引用功能使用指南

## 简介

云数据引用功能允许你直接使用存储在云端（如 AWS S3）的数据，**无需上传**即可在 Galaxy 中运行 workflow。

### 核心优势

- ⚡ **大幅节省时间**：跳过大文件上传，立即开始分析
- 💰 **降低成本**：避免重复存储和传输
- 🔄 **数据共享**：团队成员共享云数据
- 🌍 **公共数据集**：轻松使用公共基因组数据

---

## 快速开始

### 1. 创建云数据引用

```python
from galaxy_cloud.core.cloud_data_reference import create_s3_reference

# 公共数据
ref_genome = create_s3_reference(
    "s3://public-genomes/hg38/genome.fa",
    region="us-west-2",
    is_public=True,
    description="Human reference genome GRCh38"
)

# 私有数据（需要 IAM Role）
my_data = create_s3_reference(
    "s3://my-bucket/sample.fastq",
    region="us-west-2",
    role_arn="arn:aws:iam::123456789012:role/DataAccess"
)
```

### 2. 验证云数据

```python
from galaxy_cloud.core.cloud_data_validator import validate_s3_reference

# 验证数据是否可访问
result = await validate_s3_reference("s3://public-genomes/hg38/genome.fa")

if result.is_valid:
    print(f"✅ 验证通过，文件大小: {result.file_size} bytes")
else:
    print(f"❌ 验证失败: {result.error_message}")
```

### 3. 在 Workflow 中使用

```python
from galaxy_cloud.galaxy_workflow.cloud_data_manager import CloudDataManager

# 创建云数据管理器
cloud_manager = CloudDataManager(region="us-west-2")

# 准备混合输入（云引用 + 本地上传）
prepared_inputs = await cloud_manager.prepare_input_data(
    inputs=[
        ref_genome,  # 云引用
        local_dataset  # 本地文件
    ],
    run_config=run_config,
    data_manager=data_manager
)

# prepared_inputs[0]: 云引用，skip_upload=True
# prepared_inputs[1]: 本地文件，已上传到 S3
```

---

## 使用场景

### 场景 1：使用公共数据集

**问题**：参考基因组 3 GB，每次都要上传 10 分钟

**解决方案**：使用云引用

```python
# 使用 1000 Genomes Project 公共数据
ref_genome = create_s3_reference(
    "s3://1000genomes/technical/reference/human_g1k_v37.fasta.gz",
    region="us-east-1",
    is_public=True
)

# 验证
result = await validate_s3_reference(ref_genome.path, region="us-east-1")
print(f"文件大小: {result.file_size / (1024**3):.2f} GB")
```

**效果**：
- 传统方式：上传 10 分钟
- 云引用方式：验证 5 秒 ✅
- 节省时间：~10 分钟

---

### 场景 2：团队共享数据

**问题**：10 个成员分析同一批数据（1 TB），每人都要上传一遍

**解决方案**：数据上传一次，所有人使用云引用

```python
# 团队数据管理员上传数据到团队 S3
# s3://team-data/project-x/samples/

# 团队成员使用云引用
shared_data = create_s3_reference(
    "s3://team-data/project-x/samples/sample-001.fastq",
    region="us-west-2",
    role_arn="arn:aws:iam::123456789012:role/TeamDataAccess"
)
```

**效果**：
- 传统方式：10 人 × 50 小时 = 500 小时
- 云引用方式：1 次上传 = 50 小时 ✅
- 节省时间：450 小时

---

### 场景 3：大规模数据分析

**问题**：100 个样本，每个 50 GB，总共 5 TB

**解决方案**：数据已在 S3，使用云引用

```python
# 批量创建云引用
samples = [
    create_s3_reference(
        f"s3://my-data/samples/sample-{i:03d}.bam",
        region="us-west-2",
        role_arn="arn:aws:iam::123456789012:role/DataAccess"
    )
    for i in range(1, 101)
]

# 批量验证
validator = CloudDataValidator(region="us-west-2")
results = await validator.batch_validate(samples)

print(f"有效样本: {sum(1 for r in results if r.is_valid)}/100")
```

**效果**：
- 传统方式：上传 5 TB → 数天
- 云引用方式：验证 100 个文件 → 几分钟 ✅

---

## 权限配置

### 公共数据（无需配置）

```python
# 访问公共 S3 bucket
ref = create_s3_reference(
    "s3://public-bucket/data.txt",
    is_public=True
)
```

### 私有数据（需要 IAM Role）

#### 1. 创建 IAM Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::my-data-bucket/*",
        "arn:aws:s3:::my-data-bucket"
      ]
    }
  ]
}
```

#### 2. 创建 IAM Role

```bash
# 创建信任策略
cat > trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::GALAXY_ACCOUNT_ID:role/BatchJobRole"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# 创建 Role
aws iam create-role \
    --role-name MyDataAccessRole \
    --assume-role-policy-document file://trust-policy.json

# 附加 Policy
aws iam put-role-policy \
    --role-name MyDataAccessRole \
    --policy-name S3ReadAccess \
    --policy-document file://s3-read-policy.json
```

#### 3. 使用 Role

```python
my_data = create_s3_reference(
    "s3://my-data-bucket/sample.fastq",
    role_arn="arn:aws:iam::123456789012:role/MyDataAccessRole"
)
```

### 跨账户访问（Bucket Policy）

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowGalaxyCloudExecutor",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::GALAXY_ACCOUNT_ID:role/BatchJobRole"
      },
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::user-data-bucket/*",
        "arn:aws:s3:::user-data-bucket"
      ]
    }
  ]
}
```

---

## API 参考

### CloudDataReference

```python
class CloudDataReference:
    """云数据引用"""

    provider: CloudProvider  # aws_s3, gcp_gcs, azure_blob
    path: str  # 完整路径
    region: str  # 区域
    access: CloudDataAccess  # 访问配置
    metadata: CloudDataMetadata  # 元数据
    description: Optional[str]  # 描述

    # 属性
    @property
    def bucket(self) -> str:
        """提取 bucket 名称"""

    @property
    def key(self) -> str:
        """提取 key（文件路径）"""

    @property
    def filename(self) -> str:
        """提取文件名"""

    # 方法
    def to_json(self) -> str:
        """转换为 JSON"""

    @classmethod
    def from_json(cls, json_str: str) -> 'CloudDataReference':
        """从 JSON 创建"""
```

### CloudDataValidator

```python
class CloudDataValidator:
    """云数据验证器"""

    async def validate(
        self,
        cloud_ref: CloudDataReference
    ) -> ValidationResult:
        """验证单个云引用"""

    async def batch_validate(
        self,
        cloud_refs: List[CloudDataReference]
    ) -> List[ValidationResult]:
        """批量验证"""

    async def validate_directory(
        self,
        cloud_ref: CloudDataReference,
        max_files: int = 1000
    ) -> ValidationResult:
        """验证目录"""
```

### CloudDataManager

```python
class CloudDataManager:
    """云数据管理器"""

    async def prepare_input_data(
        self,
        inputs: List[Union[DatasetInfo, CloudDataReference]],
        run_config: WorkflowRunConfig,
        data_manager: Any
    ) -> List[PreparedInput]:
        """准备输入数据（支持混合输入）"""

    async def validate_cloud_references(
        self,
        cloud_refs: List[CloudDataReference]
    ) -> Dict[str, ValidationResult]:
        """批量验证云引用"""

    def get_validation_summary(
        self,
        validation_results: Dict[str, ValidationResult]
    ) -> Dict[str, Any]:
        """获取验证摘要"""
```

---

## 常见问题

### Q1: 云引用和本地上传可以混用吗？

**可以！** 这是云引用功能的核心优势。

```python
inputs = [
    # 云引用：参考基因组（大文件，公共数据）
    create_s3_reference("s3://public-genomes/hg38/genome.fa", is_public=True),

    # 本地上传：样本数据（小文件，私有数据）
    DatasetInfo(dataset_id="123", file_path="/local/sample.fastq", ...)
]

prepared = await cloud_manager.prepare_input_data(inputs, run_config, data_manager)
```

### Q2: 如何验证云数据是否可访问？

```python
# 方法 1：使用便捷函数
result = await validate_s3_reference("s3://bucket/file.txt")

# 方法 2：使用验证器
validator = CloudDataValidator()
result = await validator.validate(cloud_ref)

# 检查结果
if result.is_valid:
    print("✅ 可访问")
else:
    print(f"❌ 错误: {result.error_message}")
```

### Q3: 云引用支持目录吗？

**支持！** 路径以 `/` 结尾即为目录。

```python
# 目录引用
dir_ref = create_s3_reference("s3://my-bucket/samples/")

# 验证目录
result = await validator.validate_directory(dir_ref)
print(f"目录包含 {len(result.warnings)} 个文件")
```

### Q4: 跨区域访问会有什么影响？

**会产生额外延迟和成本。**

```python
# 验证器会自动检测并警告
result = await validator.validate(cloud_ref)

for warning in result.warnings:
    print(f"⚠️ {warning}")

# 输出示例：
# ⚠️ Cross-region access: bucket in us-east-1,
#    but specified region is us-west-2.
#    This may incur additional costs and latency.
```

**建议**：使用同区域的数据以获得最佳性能。

### Q5: 如何处理验证失败？

```python
try:
    prepared = await cloud_manager.prepare_input_data(inputs, ...)
except ValueError as e:
    print(f"云引用验证失败: {e}")

    # 检查具体错误
    validation_results = await cloud_manager.validate_cloud_references(cloud_refs)
    summary = cloud_manager.get_validation_summary(validation_results)

    if summary['errors']:
        for path, error in summary['errors'].items():
            print(f"  {path}: {error}")
```

---

## 最佳实践

### 1. 优先使用公共数据集

```python
# ✅ 推荐：使用公共数据
ref_genome = create_s3_reference(
    "s3://1000genomes/.../genome.fa",
    is_public=True
)

# ❌ 不推荐：重复上传公共数据
upload_file("/local/genome.fa")  # 浪费时间和带宽
```

### 2. 大文件使用云引用，小文件本地上传

```python
# ✅ 推荐：混合策略
inputs = [
    create_s3_reference("s3://.../big_file.bam", ...),  # 50 GB
    DatasetInfo(..., file_path="/local/small.txt", ...)  # 1 MB
]

# ❌ 不推荐：全部本地上传
inputs = [
    DatasetInfo(..., file_path="/local/big_file.bam", ...),  # 上传 50 GB
    DatasetInfo(..., file_path="/local/small.txt", ...)
]
```

### 3. 使用验证缓存

```python
# CloudDataValidator 自动缓存验证结果
validator = CloudDataValidator()

# 第一次验证：实际访问 S3
result1 = await validator.validate(cloud_ref)  # ~1 秒

# 第二次验证：使用缓存
result2 = await validator.validate(cloud_ref)  # ~0.001 秒
```

### 4. 批量验证提高效率

```python
# ✅ 推荐：批量验证
results = await validator.batch_validate(cloud_refs)  # 并行

# ❌ 不推荐：逐个验证
results = []
for ref in cloud_refs:
    result = await validator.validate(ref)  # 串行
    results.append(result)
```

### 5. 使用 IAM Role 而非 Access Key

```python
# ✅ 推荐：IAM Role
ref = create_s3_reference(
    "s3://my-bucket/data.txt",
    role_arn="arn:aws:iam::123456789012:role/DataAccess"
)

# ❌ 不推荐：Access Key（安全风险）
ref = CloudDataReference(
    ...,
    access=CloudDataAccess(
        method=AccessMethod.ACCESS_KEY,
        access_key_id="AKIAIOSFODNN7EXAMPLE",
        secret_access_key="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
    )
)
```

---

## 性能对比

### 场景：RNA-Seq 分析

| 输入 | 大小 | 传统方式 | 云引用方式 | 节省时间 |
|------|------|----------|------------|----------|
| 参考基因组 | 3 GB | 上传 10 分钟 | 验证 5 秒 | ~10 分钟 |
| 基因注释 | 500 MB | 上传 2 分钟 | 验证 5 秒 | ~2 分钟 |
| 转录本序列 | 2 GB | 上传 7 分钟 | 验证 5 秒 | ~7 分钟 |
| 样本数据 | 1 GB | 上传 3 分钟 | 上传 3 分钟 | 0 |
| **总计** | 6.5 GB | **22 分钟** | **3 分钟** | **~19 分钟** ✅ |

---

## 示例代码

完整示例代码在 `examples/` 目录：

- `test_cloud_data_reference.py` - 基本功能测试
- `test_workflow_with_cloud_data.py` - Workflow 集成示例

运行示例：

```bash
cd examples
python3 test_cloud_data_reference.py
python3 test_workflow_with_cloud_data.py
```

---

## 下一步

1. **配置权限**：参考"权限配置"章节
2. **测试验证**：运行示例代码
3. **集成 Galaxy**：将云引用集成到 Galaxy UI
4. **使用公共数据**：探索公共基因组数据集

---

## 相关文档

- [云数据引用设计文档](CLOUD_DATA_REFERENCE_DESIGN.md)
- [API 参考](../galaxy_cloud/core/cloud_data_reference.py)
- [Galaxy 集成指南](../full_docs/01-快速开始指南.md)
