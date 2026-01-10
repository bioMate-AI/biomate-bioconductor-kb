# 云数据引用功能设计

## 背景

**问题**：用户每次运行 workflow 都需要上传数据到 S3，即使数据已经在云上
**影响**：
- 大文件上传耗时长（几十 GB 的基因组数据）
- 浪费带宽和存储成本
- 重复数据传输

**解决方案**：支持用户直接引用云上的数据，跳过上传步骤

---

## 用例场景

### 场景 1：公共数据集
```
用户想分析人类参考基因组 GRCh38
- 数据已在 S3: s3://galaxy-public-data/genomes/hg38/
- 传统方式：下载 → 上传到自己的 Galaxy → 再上传到云
- 云引用方式：直接配置 s3://galaxy-public-data/genomes/hg38/genome.fa
```

### 场景 2：团队共享数据
```
团队共享的测序数据存储在 S3
- 数据位置: s3://team-shared-data/project-x/samples/
- 多个成员需要分析同一批数据
- 传统方式：每人都要上传一遍
- 云引用方式：直接引用共享 S3 路径
```

### 场景 3：大规模数据分析
```
用户有 100 个样本，每个 50 GB
- 总数据量：5 TB
- 传统方式：上传需要数小时甚至数天
- 云引用方式：数据已在 S3，立即开始分析
```

---

## 功能设计

### 1. 数据类型扩展

在 Galaxy 中新增云数据类型，支持用户配置云路径。

#### 新增数据类型：`cloud_data`

```yaml
# Galaxy 数据类型定义
datatypes:
  - name: cloud_s3
    display: "Cloud S3 Data"
    extension: cloud_s3
    description: "Reference to data stored in AWS S3"

  - name: cloud_s3_directory
    display: "Cloud S3 Directory"
    extension: cloud_s3_dir
    description: "Reference to a directory in AWS S3"
```

---

### 2. 用户界面设计

#### Galaxy UI 新增输入方式

**选项 1：上传本地文件**（现有方式）
```
[Choose File] sample.fastq
```

**选项 2：引用云数据**（新功能）
```
☑️ Use Cloud Data Reference
   Cloud Provider: [AWS S3 ▼]
   Data Path: s3://my-bucket/data/sample.fastq
   Region: [us-west-2 ▼]

   [Validate] 验证路径是否可访问
```

---

### 3. 数据格式定义

#### Cloud Data Reference JSON 格式

```json
{
  "type": "cloud_reference",
  "provider": "aws_s3",
  "path": "s3://bucket-name/path/to/file.fastq",
  "region": "us-west-2",
  "metadata": {
    "file_size": 1073741824,
    "last_modified": "2025-10-15T10:00:00Z",
    "checksum": "md5:abc123...",
    "validated": true
  },
  "access": {
    "type": "iam_role",  // or "access_key"
    "role_arn": "arn:aws:iam::123456789012:role/GalaxyCloudDataAccess"
  }
}
```

---

### 4. 权限管理

#### 两种访问方式

**方式 1：IAM Role（推荐）**
```
用户配置 IAM Role ARN
→ Galaxy 云执行器使用 Role 访问数据
→ 安全，不需要暴露 Access Key
```

**方式 2：跨账户访问**
```
用户授权 Galaxy 的 IAM Role 访问其 S3 bucket
→ 设置 Bucket Policy
→ Galaxy 直接读取用户数据
```

#### Bucket Policy 示例

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowGalaxyCloudExecutorRead",
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

### 5. 数据验证

#### 验证流程

```
用户输入云数据路径
    ↓
Galaxy 验证访问权限
    ↓
检查文件是否存在
    ↓
获取文件元数据（大小、修改时间）
    ↓
可选：校验文件格式（FASTQ/BAM/VCF）
    ↓
保存为 Cloud Reference 数据集
```

#### 验证 API

```python
async def validate_cloud_reference(cloud_ref: CloudDataReference) -> ValidationResult:
    """
    验证云数据引用

    Returns:
        ValidationResult with:
        - accessible: bool
        - file_exists: bool
        - file_size: int
        - error_message: str (if any)
    """
```

---

### 6. DataManager 集成

#### 修改 DataManager 逻辑

```python
class GalaxyDataManager:
    async def prepare_input_data(self, job_spec: JobSpec):
        """
        准备输入数据

        支持两种方式：
        1. 本地文件 → 上传到 S3
        2. 云引用 → 直接返回云路径
        """
        prepared_inputs = []

        for input_dataset in job_spec.inputs:
            if input_dataset.type == "cloud_reference":
                # 云引用：直接使用云路径
                cloud_ref = CloudDataReference.from_json(input_dataset.metadata)
                prepared_inputs.append({
                    's3_uri': cloud_ref.path,
                    'skip_upload': True,
                    'access_role': cloud_ref.access.role_arn
                })
            else:
                # 本地文件：上传到 S3
                s3_uri = await self.upload_to_s3(input_dataset)
                prepared_inputs.append({
                    's3_uri': s3_uri,
                    'skip_upload': False
                })

        return prepared_inputs
```

---

### 7. 工作流集成

#### Workflow 中的云数据引用

```json
{
  "steps": {
    "0": {
      "type": "data_input",
      "tool_id": null,
      "inputs": [
        {
          "name": "reference_genome",
          "type": "cloud_reference",
          "cloud_path": "s3://public-genomes/hg38/genome.fa",
          "description": "Human reference genome GRCh38"
        }
      ]
    },
    "1": {
      "type": "tool",
      "tool_id": "bwa_mem",
      "inputs": {
        "reference": {
          "connection": "0:reference_genome"
        },
        "reads": {
          "type": "user_upload"  // 用户上传
        }
      }
    }
  }
}
```

#### 混合模式

```
输入 1: 参考基因组 → 云引用（公共数据，3 GB）
输入 2: 样本数据 → 用户上传（私有数据，100 MB）
```

这样既利用了云数据，又支持用户私有数据。

---

## 实现步骤

### Phase 1: 核心功能（MVP）

1. ✅ 定义 CloudDataReference 数据模型
2. ✅ 实现 DataManager 的云引用支持
3. ✅ 实现路径验证功能
4. ✅ 更新 AWS Batch 作业提交逻辑

### Phase 2: Galaxy UI 集成

1. 🔄 新增云数据输入组件
2. 🔄 实现路径验证 UI
3. 🔄 更新数据类型定义

### Phase 3: 高级功能

1. 📋 支持目录引用（批量文件）
2. 📋 支持其他云平台（GCP, Azure）
3. 📋 数据缓存和版本管理

---

## 配置示例

### Galaxy 配置（galaxy.yml）

```yaml
cloud_executor:
  # 云数据引用功能
  cloud_data_reference:
    enabled: true

    # 允许的 S3 bucket 前缀（安全控制）
    allowed_s3_prefixes:
      - "s3://public-genomes/*"
      - "s3://team-shared-data/*"
      - "s3://user-data-*/*"

    # 默认访问方式
    default_access_method: "iam_role"

    # 验证配置
    validation:
      check_file_exists: true
      check_file_format: true  # 验证文件格式
      timeout_seconds: 30

    # 缓存配置（可选）
    cache:
      enabled: true
      ttl_seconds: 3600  # 元数据缓存时间
```

### 用户配置示例

```yaml
# ~/.galaxy/cloud_data_config.yml
cloud_data_sources:
  - name: "Public Genomes"
    provider: "aws_s3"
    bucket: "public-genomes"
    region: "us-west-2"
    access:
      type: "public"  # 公共数据，无需认证

  - name: "Team Shared Data"
    provider: "aws_s3"
    bucket: "team-shared-data"
    region: "us-west-2"
    access:
      type: "iam_role"
      role_arn: "arn:aws:iam::123456789012:role/TeamDataAccess"

  - name: "My Private Data"
    provider: "aws_s3"
    bucket: "my-data-bucket"
    region: "us-west-2"
    access:
      type: "iam_role"
      role_arn: "arn:aws:iam::123456789012:role/MyDataAccess"
```

---

## 安全考虑

### 1. 访问控制

- ✅ 使用 IAM Role，不暴露 Access Key
- ✅ 限制允许的 S3 bucket 前缀
- ✅ 验证用户有权限访问指定路径

### 2. 数据隔离

- ✅ 每个用户的云引用独立验证
- ✅ 作业执行时使用最小权限原则
- ✅ 输出数据写入用户独立的 S3 路径

### 3. 审计日志

```
记录所有云数据访问：
- 用户 ID
- 访问的 S3 路径
- 访问时间
- 作业 ID
```

---

## 性能优化

### 1. 元数据缓存

```
首次验证云路径时：
→ 获取文件大小、修改时间等元数据
→ 缓存 1 小时

后续使用：
→ 直接读取缓存，跳过验证
→ 加快作业提交速度
```

### 2. 并行验证

```
Workflow 有多个云引用输入时：
→ 并行验证所有路径
→ 减少总验证时间
```

### 3. 懒加载

```
只在作业实际执行时访问 S3
→ 提交作业时只验证路径
→ AWS Batch 容器启动时才下载数据
```

---

## 用户体验

### 传统方式 vs 云引用方式

#### 传统方式
```
1. 用户上传 5 GB 参考基因组（10 分钟）
2. Galaxy 上传到 S3（5 分钟）
3. 开始执行作业
总时间：15 分钟 + 作业时间
```

#### 云引用方式
```
1. 用户配置云路径（10 秒）
2. Galaxy 验证路径（5 秒）
3. 直接开始执行作业
总时间：15 秒 + 作业时间
```

**节省时间：~15 分钟** ✅

---

## 错误处理

### 常见错误和解决方案

1. **路径不存在**
   ```
   错误：The specified key does not exist
   解决：检查路径拼写，确认文件在指定位置
   ```

2. **权限不足**
   ```
   错误：Access Denied
   解决：配置 Bucket Policy 或使用正确的 IAM Role
   ```

3. **跨区域访问**
   ```
   警告：Data in us-east-1, but job running in us-west-2
   建议：使用同区域数据以减少延迟和成本
   ```

---

## 测试用例

### 单元测试

```python
# test_cloud_data_reference.py

async def test_validate_s3_path():
    """测试 S3 路径验证"""
    ref = CloudDataReference(
        provider="aws_s3",
        path="s3://test-bucket/test.fastq",
        region="us-west-2"
    )
    result = await validate_cloud_reference(ref)
    assert result.accessible is True

async def test_mixed_inputs():
    """测试混合输入（云引用 + 本地上传）"""
    job_spec = JobSpec(
        inputs=[
            {"type": "cloud_reference", "path": "s3://..."},
            {"type": "local_file", "path": "/tmp/sample.fastq"}
        ]
    )
    prepared = await data_manager.prepare_input_data(job_spec)
    assert len(prepared) == 2
    assert prepared[0]['skip_upload'] is True
    assert prepared[1]['skip_upload'] is False
```

### 集成测试

```bash
# 测试完整流程
python3 test_cloud_reference_workflow.py
```

---

## 文档

### 用户文档

- 如何配置云数据引用
- 权限配置指南
- 常见问题排查

### 管理员文档

- Galaxy 配置指南
- IAM Role 设置
- 安全最佳实践

---

## 总结

### 核心价值

- ⚡ **性能提升**：跳过数据上传，立即开始分析
- 💰 **成本节约**：避免重复存储和传输
- 🔄 **数据共享**：团队成员共享云数据
- 🌍 **公共数据集**：轻松使用公共基因组数据

### 实现复杂度

- 🟢 **核心功能**：中等（1-2 天）
- 🟡 **Galaxy UI 集成**：较高（3-5 天）
- 🟢 **测试和文档**：中等（1-2 天）

总计：**1-2 周完整实现**

---

## 下一步

1. ✅ 实现 CloudDataReference 数据模型
2. ✅ 更新 DataManager 支持云引用
3. ✅ 实现路径验证功能
4. 🔄 创建测试示例
5. 📋 编写用户文档

开始实现核心功能 →
