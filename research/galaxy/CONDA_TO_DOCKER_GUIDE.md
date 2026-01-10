# Conda 工具容器化指南

## 问题：为什么需要将 Conda 工具打包成 Docker？

### 当前挑战

**问题情景**：
- Galaxy 工具只声明了 conda 依赖
- 云端环境（AWS Batch）是隔离的容器
- Fetch-and-run 容器里没有 conda
- 无法直接在云端安装 conda 包

**结果**：
- ✗ 工具无法在云端运行
- ✗ 或者每次都要安装（慢、不稳定）

### 解决方案

**预先构建 Docker 镜像**：
1. 提前将 conda 包打包成 Docker 镜像
2. 推送到 ECR (Elastic Container Registry)
3. 云端直接拉取和运行

## 方案对比

### 方案 1：预构建 Docker 镜像（推荐）✓

```
┌─────────────┐      ┌──────────────┐      ┌─────────┐
│ Conda 包    │  →   │ Docker 镜像   │  →   │  ECR    │
│ trimmomatic │      │ 包含所有依赖  │      │ 云存储  │
└─────────────┘      └──────────────┘      └─────────┘
                                                 ↓
                                          ┌─────────────┐
                                          │ AWS Batch   │
                                          │ 直接拉取运行 │
                                          └─────────────┘
```

**优点**：
- ✓ 启动快（无需安装）
- ✓ 稳定（环境一致）
- ✓ 可缓存和版本控制
- ✓ 适合批量任务

**缺点**：
- ✗ 需要预先构建
- ✗ 占用存储空间

### 方案 2：动态安装 Conda（不推荐）✗

```
┌─────────────┐      ┌──────────────────┐
│ 任务启动    │  →   │ 下载 conda 包     │
│             │      │ 安装依赖（每次）   │
└─────────────┘      └──────────────────┘
                              ↓ (慢)
                     ┌──────────────────┐
                     │ 运行工具          │
                     └──────────────────┘
```

**缺点**：
- ✗ 每次运行都要安装（5-10分钟）
- ✗ 网络依赖（可能失败）
- ✗ 浪费计算资源和费用
- ✗ 不适合批量任务

## 实施步骤

### 步骤 1：构建单个工具镜像

使用提供的脚本：

```bash
cd /Users/renyuankai/work/biometa/galaxy

# 构建 Trimmomatic 镜像
./scripts/build_conda_tool_image.sh trimmomatic "trimmomatic=0.39" 0.39

# 构建 FastQC 镜像
./scripts/build_conda_tool_image.sh fastqc "fastqc=0.12.1" 0.12.1

# 构建 MultiQC 镜像
./scripts/build_conda_tool_image.sh multiqc "multiqc=1.14" 1.14
```

**脚本会自动**：
1. ✓ 生成 Dockerfile
2. ✓ 构建 Docker 镜像
3. ✓ 创建 ECR 仓库（如果不存在）
4. ✓ 推送镜像到 ECR
5. ✓ 提供配置文件示例

### 步骤 2：批量构建常用工具

```bash
# 一次性构建 20+ 个常用生物信息学工具
./scripts/build_common_tools.sh
```

**包含的工具**：
- Quality Control: fastqc, multiqc
- Read Processing: trimmomatic, cutadapt
- Alignment: bowtie2, bwa, hisat2
- BAM/SAM: samtools, picard
- Variant Calling: bcftools, freebayes
- RNA-seq: star, featurecounts, htseq
- Assembly: spades, megahit

### 步骤 3：更新配置文件

编辑 `config/tool_containers.yaml`，添加构建的镜像：

```yaml
tools:
  # 使用自建的 ECR 镜像
  "toolshed.g2.bx.psu.edu/repos/pjbriggs/trimmomatic/trimmomatic/0.39.0":
    image: "399683337364.dkr.ecr.us-west-2.amazonaws.com/galaxy-tools/trimmomatic"
    tag: "0.39"
    registry: "399683337364.dkr.ecr.us-west-2.amazonaws.com"
    resources:
      cpus: 4
      memory_mb: 4096

  "toolshed.g2.bx.psu.edu/repos/devteam/fastqc/fastqc/0.74+galaxy0":
    image: "399683337364.dkr.ecr.us-west-2.amazonaws.com/galaxy-tools/fastqc"
    tag: "0.12.1"
    registry: "399683337364.dkr.ecr.us-west-2.amazonaws.com"
    resources:
      cpus: 2
      memory_mb: 2048
```

### 步骤 4：重启 Galaxy

```bash
pkill -f "python.*run.py"
sh start_galaxy_with_ai.sh
```

## 长期方案：自动化构建

### 实现 Layer 3: Auto-build

代码中已经有框架（`enhanced_tool_registry.py:194-246`），需要完善：

```python
async def _auto_build_from_conda(self, tool_id: str, tool_version: str):
    """
    自动从 conda 依赖构建容器
    """
    # 1. 提取工具的 conda 依赖
    conda_packages = self._extract_conda_requirements(tool_id)

    # 2. 生成 Dockerfile
    dockerfile = self._generate_dockerfile(conda_packages)

    # 3. 触发 AWS CodeBuild
    build_id = await self._trigger_codebuild(tool_id, dockerfile)

    # 4. 等待构建完成
    ecr_image_uri = await self._wait_for_build(build_id)

    # 5. 返回 ECR 镜像 URL
    return ToolContainerInfo(
        tool_id=tool_id,
        image=ecr_image_uri,
        tag=tool_version
    )
```

### AWS CodeBuild 配置

创建 `buildspec.yml`:

```yaml
version: 0.2

phases:
  pre_build:
    commands:
      - echo Logging in to Amazon ECR...
      - aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY

  build:
    commands:
      - echo Building Docker image...
      - docker build -t $IMAGE_NAME:$IMAGE_TAG .

  post_build:
    commands:
      - echo Pushing to ECR...
      - docker tag $IMAGE_NAME:$IMAGE_TAG $ECR_REGISTRY/$IMAGE_NAME:$IMAGE_TAG
      - docker push $ECR_REGISTRY/$IMAGE_NAME:$IMAGE_TAG

artifacts:
  files:
    - '**/*'
```

## 优化建议

### 1. 镜像大小优化

使用多阶段构建：

```dockerfile
# 构建阶段
FROM continuumio/miniconda3:latest AS builder
RUN conda install -c bioconda trimmomatic=0.39 && \
    conda clean -afy

# 运行阶段（更小）
FROM debian:bullseye-slim
COPY --from=builder /opt/conda /opt/conda
ENV PATH=/opt/conda/bin:$PATH
WORKDIR /data
CMD ["/bin/bash"]
```

### 2. 镜像缓存策略

在 ECR 中设置生命周期策略：

```json
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "保留最新 5 个镜像",
      "selection": {
        "tagStatus": "any",
        "countType": "imageCountMoreThan",
        "countNumber": 5
      },
      "action": {
        "type": "expire"
      }
    }
  ]
}
```

### 3. 并行构建

使用 AWS CodeBuild 的批量构建功能：

```yaml
batch:
  fast-fail: false
  build-matrix:
    static:
      privileged-mode: true
    dynamic:
      buildspec:
        - buildspec_fastqc.yml
        - buildspec_trimmomatic.yml
        - buildspec_bowtie2.yml
```

## 成本考虑

### ECR 存储成本
- **价格**: $0.10 per GB-month
- **估算**: 每个镜像 ~500MB - 2GB
- **20个工具**: ~20GB = $2/月

### 构建成本
- **CodeBuild**: $0.005/分钟 (Linux, small)
- **估算**: 每个工具 ~5分钟
- **20个工具**: 100分钟 = $0.50

### 运行成本节省
**动态安装 conda** (方案2):
- 每次运行安装时间: 5-10分钟
- EC2 成本: $0.096/小时 (t3.medium)
- 每次浪费: ~$0.01-0.02

**预构建镜像** (方案1):
- 启动时间: < 30秒
- 节省成本: ~$0.01-0.02 per job

**如果运行 1000 个任务**:
- 节省: $10-20
- **镜像存储成本在几次运行后就回本了**

## 工具检查清单

在构建镜像前，检查工具是否已有容器：

### 1. 检查 BioContainers

```bash
# 搜索工具
curl "https://biocontainers.pro/api/ga4gh/trs/v2/tools?name=trimmomatic"

# 如果有结果 → 使用 BioContainers 镜像
# 如果无结果 → 需要自己构建
```

### 2. 检查工具 XML

```bash
# 查看工具是否声明了容器
grep -r "container.*trimmomatic" database/shed_tools/
```

### 3. 优先级

1. **优先使用 BioContainers** - 社区维护，更新及时
2. **使用工具 XML 声明** - 工具作者推荐
3. **自己构建** - 只在必要时

## 示例：完整流程

### 场景：添加新工具 "mytool"

```bash
# 1. 检查是否有现成的容器
curl "https://biocontainers.pro/api/ga4gh/trs/v2/tools?name=mytool"

# 2. 没有？构建自己的镜像
./scripts/build_conda_tool_image.sh mytool "mytool=1.2.3" 1.2.3

# 3. 更新配置
cat >> config/tool_containers.yaml << 'EOF'
  "toolshed.g2.bx.psu.edu/repos/owner/mytool/mytool/1.2.3":
    image: "399683337364.dkr.ecr.us-west-2.amazonaws.com/galaxy-tools/mytool"
    tag: "1.2.3"
    registry: "399683337364.dkr.ecr.us-west-2.amazonaws.com"
EOF

# 4. 重启 Galaxy
pkill -f "python.*run.py"
sh start_galaxy_with_ai.sh

# 5. 测试
# 通过 Galaxy Web UI 提交 mytool 任务
```

## 故障排查

### 问题 1: 镜像构建失败

```bash
# 检查 conda 包是否存在
docker run --rm continuumio/miniconda3 \
    conda search -c bioconda trimmomatic

# 手动测试安装
docker run --rm -it continuumio/miniconda3 bash
conda install -c bioconda trimmomatic=0.39
```

### 问题 2: ECR 推送失败

```bash
# 检查 ECR 认证
aws ecr get-login-password --region us-west-2

# 检查 IAM 权限
aws ecr describe-repositories --region us-west-2

# 需要的权限:
# - ecr:GetAuthorizationToken
# - ecr:BatchCheckLayerAvailability
# - ecr:PutImage
# - ecr:InitiateLayerUpload
# - ecr:UploadLayerPart
# - ecr:CompleteLayerUpload
```

### 问题 3: AWS Batch 拉取镜像失败

```bash
# 检查 BatchJobRole 是否有 ECR 权限
aws iam get-role-policy \
    --role-name BatchJobRole \
    --policy-name ECRAccessPolicy

# 添加权限（如果缺失）
aws iam put-role-policy \
    --role-name BatchJobRole \
    --policy-name ECRAccessPolicy \
    --policy-document '{
      "Version": "2012-10-17",
      "Statement": [{
        "Effect": "Allow",
        "Action": [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ],
        "Resource": "*"
      }]
    }'
```

## 最佳实践总结

### DO ✓

1. **优先使用 BioContainers** - 社区镜像更稳定
2. **预先构建常用工具** - 减少云端运行时间
3. **版本锁定** - 确保结果可重现
4. **设置 ECR 生命周期** - 自动清理旧镜像
5. **测试镜像** - 本地测试后再推送

### DON'T ✗

1. **不要在云端动态安装 conda** - 慢且不稳定
2. **不要使用 latest 标签** - 失去版本控制
3. **不要忽略镜像大小** - 影响拉取速度
4. **不要重复构建** - 检查是否已存在
5. **不要忘记文档** - 记录镜像来源和依赖

## 参考资源

- [BioContainers Registry](https://biocontainers.pro/)
- [AWS ECR 用户指南](https://docs.aws.amazon.com/ecr/)
- [Docker 多阶段构建](https://docs.docker.com/build/building/multi-stage/)
- [Conda 包搜索](https://anaconda.org/bioconda/)
- [Galaxy Tool Shed](https://toolshed.g2.bx.psu.edu/)

## 相关脚本

- [`scripts/build_conda_tool_image.sh`](scripts/build_conda_tool_image.sh) - 构建单个工具镜像
- [`scripts/build_common_tools.sh`](scripts/build_common_tools.sh) - 批量构建常用工具
- [`config/tool_containers.yaml`](config/tool_containers.yaml) - 工具容器映射配置
