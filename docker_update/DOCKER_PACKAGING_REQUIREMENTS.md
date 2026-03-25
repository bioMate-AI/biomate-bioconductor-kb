# Docker 镜像打包要求（Galaxy GPU Workflow）

## 文档说明

**目标读者**: 负责 Docker 镜像构建的同事
**用途**: 为 Galaxy GPU Workflow 准备符合规范的 Docker 镜像
**重要性**: ⭐️⭐️⭐️⭐️⭐️ 镜像不符合规范会导致 Workflow 100% 失败

---

## 核心要求（必须遵守）

### ⭐️ 要求 1: 构建两个镜像标签

每个 AI 工具需要构建 **2 个镜像标签**：

| 标签 | 用途 | ENTRYPOINT | 说明 |
|------|------|------------|------|
| `latest` | 独立使用 | ✅ 可以有 | 原始镜像，供用户直接使用 |
| `nextflow` | Nextflow/Galaxy | ❌ **必须移除** | Wrapper 镜像，用于 Nextflow 调度 |

**示例**:
```bash
# 镜像 1 (原始)
399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/chai1:latest

# 镜像 2 (Nextflow wrapper)
399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/chai1:nextflow
```

---

### ⭐️ 要求 2: Nextflow Wrapper 镜像必须移除 ENTRYPOINT

**为什么必须移除?**

Nextflow 需要完全控制容器执行的命令。如果 ENTRYPOINT 存在，会导致命令传递失败。

**错误示例** (会导致 Workflow 失败):
```dockerfile
FROM python:3.10

# ❌ 不要在 wrapper 镜像中设置 ENTRYPOINT
ENTRYPOINT ["python", "-m", "tool"]  # 这会导致 Nextflow 无法正确执行命令

CMD ["--help"]
```

**正确示例**:
```dockerfile
FROM 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/tool:latest

# ✅ 移除任何 ENTRYPOINT
ENTRYPOINT []

# ✅ CMD 可以保留（可选，作为默认命令）
CMD ["python", "-m", "tool"]
```

---

## 标准 Dockerfile 模板

### 模板 1: 原始镜像 (`:latest`)

```dockerfile
# 基础镜像（根据工具选择）
FROM nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu22.04

# 安装系统依赖
RUN apt-get update && apt-get install -y \
    python3.10 \
    python3-pip \
    git \
    wget \
    && rm -rf /var/lib/apt/lists/*

# 设置工作目录
WORKDIR /opt/tool

# 安装 Python 依赖
COPY requirements.txt .
RUN pip3 install --no-cache-dir -r requirements.txt

# 复制工具代码
COPY . .

# 安装工具
RUN pip3 install -e .

# ✅ 原始镜像可以设置 ENTRYPOINT（方便用户使用）
ENTRYPOINT ["python", "-m", "tool"]
CMD ["--help"]

# 元数据
LABEL maintainer="Your Team"
LABEL description="Tool for AI prediction"
LABEL version="1.0.0"
```

### 模板 2: Nextflow Wrapper 镜像 (`:nextflow`)

```dockerfile
# 基于原始镜像构建
FROM 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/<tool>:latest

# ⭐️ 核心要求：移除 ENTRYPOINT
ENTRYPOINT []

# ✅ CMD 可以保留（作为默认命令，可选）
CMD ["python", "-m", "<tool>"]

# 元数据（推荐添加）
LABEL maintainer="Galaxy Team"
LABEL description="<Tool> wrapper for Nextflow/AWS Batch orchestration"
LABEL base-image="biomate/ai-tools/<tool>:latest"
LABEL wrapper-version="1.0"
LABEL purpose="nextflow"
```

**关键点**:
1. **基于 `latest` 镜像构建** - 确保两个镜像内容完全一致
2. **只改动 ENTRYPOINT** - 使用 `ENTRYPOINT []` 清空
3. **添加元数据** - 标明这是 Nextflow wrapper 镜像

---

## 构建和推送脚本

### 标准构建脚本 (build-and-push.sh)

```bash
#!/bin/bash
set -e  # 遇到错误立即退出

# ==================== 配置部分 ====================
ECR_REGISTRY="399683337364.dkr.ecr.us-west-2.amazonaws.com"
TOOL_NAME="<your-tool-name>"  # 修改为你的工具名
IMAGE_NAME="biomate/ai-tools/${TOOL_NAME}"
AWS_REGION="us-west-2"

# ==================== 函数定义 ====================
log_info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1"
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
}

# ==================== 步骤 1: 登录 ECR ====================
log_info "Logging in to ECR..."
aws ecr get-login-password --region ${AWS_REGION} | \
    docker login --username AWS --password-stdin ${ECR_REGISTRY}

if [ $? -ne 0 ]; then
    log_error "Failed to login to ECR"
    exit 1
fi
log_info "✅ ECR login successful"

# ==================== 步骤 2: 构建原始镜像 ====================
log_info "Building original image (latest)..."
docker build -t ${IMAGE_NAME}:latest -f Dockerfile .

if [ $? -ne 0 ]; then
    log_error "Failed to build original image"
    exit 1
fi
log_info "✅ Original image built successfully"

# ==================== 步骤 3: 推送原始镜像 ====================
log_info "Pushing original image to ECR..."
docker tag ${IMAGE_NAME}:latest ${ECR_REGISTRY}/${IMAGE_NAME}:latest
docker push ${ECR_REGISTRY}/${IMAGE_NAME}:latest

if [ $? -ne 0 ]; then
    log_error "Failed to push original image"
    exit 1
fi
log_info "✅ Original image pushed: ${ECR_REGISTRY}/${IMAGE_NAME}:latest"

# ==================== 步骤 4: 构建 Nextflow Wrapper 镜像 ====================
log_info "Building Nextflow wrapper image..."
docker build -t ${IMAGE_NAME}:nextflow -f Dockerfile.nextflow .

if [ $? -ne 0 ]; then
    log_error "Failed to build Nextflow wrapper image"
    exit 1
fi
log_info "✅ Nextflow wrapper image built successfully"

# ==================== 步骤 5: 推送 Nextflow Wrapper 镜像 ====================
log_info "Pushing Nextflow wrapper image to ECR..."
docker tag ${IMAGE_NAME}:nextflow ${ECR_REGISTRY}/${IMAGE_NAME}:nextflow
docker push ${ECR_REGISTRY}/${IMAGE_NAME}:nextflow

if [ $? -ne 0 ]; then
    log_error "Failed to push Nextflow wrapper image"
    exit 1
fi
log_info "✅ Nextflow wrapper image pushed: ${ECR_REGISTRY}/${IMAGE_NAME}:nextflow"

# ==================== 步骤 6: 验证镜像 ====================
log_info "Verifying images in ECR..."
aws ecr describe-images \
    --repository-name ${IMAGE_NAME} \
    --region ${AWS_REGION} \
    --query 'imageDetails[*].[imageTags[0],imagePushedAt,imageSizeInBytes]' \
    --output table

log_info "=========================================="
log_info "✅ All images built and pushed successfully!"
log_info "Original: ${ECR_REGISTRY}/${IMAGE_NAME}:latest"
log_info "Wrapper:  ${ECR_REGISTRY}/${IMAGE_NAME}:nextflow"
log_info "=========================================="
```

**使用方法**:
```bash
# 1. 修改脚本中的 TOOL_NAME
vim build-and-push.sh

# 2. 添加执行权限
chmod +x build-and-push.sh

# 3. 执行构建
./build-and-push.sh
```

---

## 目录结构规范

**推荐的项目结构**:
```
docker/<tool-name>-nextflow-wrapper/
├── Dockerfile                 # 原始镜像（:latest）
├── Dockerfile.nextflow        # Nextflow wrapper 镜像（:nextflow）
├── build-and-push.sh          # 构建和推送脚本
├── requirements.txt           # Python 依赖（如适用）
├── README.md                  # 镜像说明文档
└── test/                      # 测试脚本（可选）
    └── test_image.sh
```

**示例: Chai-1**
```
docker/chai1-nextflow-wrapper/
├── Dockerfile                 # FROM nvidia/cuda:... (原始镜像)
├── Dockerfile.nextflow        # FROM biomate/ai-tools/chai1:latest (wrapper)
├── build-and-push.sh
└── README.md
```

---

## 验证和测试

### 1. 本地验证（构建后）

```bash
# 1.1 检查 ENTRYPOINT 是否已移除
docker inspect <image>:nextflow | grep -A 5 Entrypoint
# 应该输出: "Entrypoint": null 或 []

# 1.2 测试基本命令
docker run --rm <image>:nextflow <tool-command> --help
# 应该正常输出帮助信息

# 1.3 测试实际执行（如果有测试数据）
docker run --rm \
    -v $(pwd)/test_data:/data \
    <image>:nextflow \
    <tool-command> /data/input.txt /data/output
```

### 2. ECR 验证（推送后）

```bash
# 2.1 检查镜像是否存在
aws ecr describe-images \
    --repository-name biomate/ai-tools/<tool> \
    --region us-west-2 \
    --query 'imageDetails[*].[imageTags[0],imagePushedAt]' \
    --output table

# 应该看到两个标签: latest 和 nextflow

# 2.2 拉取并测试
docker pull 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/<tool>:nextflow
docker run --rm <ecr-image>:nextflow <tool-command> --help
```

### 3. GPU 测试（在 EC2 上）

```bash
# SSH 到 GPU 实例
ssh -i ~/.ssh/galaxy-ec2-key ec2-user@<ec2-ip>

# 拉取镜像
docker pull 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/<tool>:nextflow

# 测试 GPU 访问
docker run --rm --gpus all <image>:nextflow nvidia-smi

# 测试工具执行
docker run --rm --gpus all \
    -v /tmp:/work \
    <image>:nextflow \
    <tool-command> /work/test_input /work/test_output
```

---

## 常见问题 (FAQ)

### Q1: 为什么需要两个镜像标签？

**A**:
- **`latest`**: 供用户直接使用，可以有 ENTRYPOINT，方便命令行操作
- **`nextflow`**: 供 Nextflow 调度，必须移除 ENTRYPOINT，否则命令传递失败

### Q2: 如果原始镜像没有 ENTRYPOINT，还需要构建 wrapper 镜像吗？

**A**:
是的，仍然推荐构建。原因：
1. 明确标识这是 Nextflow 兼容版本
2. 未来原始镜像可能添加 ENTRYPOINT
3. 统一管理，所有 GPU 工具都有 `:nextflow` 标签

### Q3: Dockerfile.nextflow 可以做其他修改吗？

**A**:
不推荐。Wrapper 镜像应该：
- ✅ 只移除 ENTRYPOINT
- ✅ 只添加元数据 LABEL
- ❌ 不要修改软件版本
- ❌ 不要安装额外依赖
- ❌ 不要改变工作目录

### Q4: CMD 需要移除吗？

**A**:
不需要。CMD 可以保留，作为默认命令。Nextflow 会覆盖 CMD，但不会受到影响。

### Q5: 如何检查 ENTRYPOINT 是否已正确移除？

**A**:
```bash
# 方法 1: docker inspect
docker inspect <image>:nextflow | grep -A 5 Entrypoint
# 应该输出: "Entrypoint": null

# 方法 2: 运行测试
docker run --rm <image>:nextflow echo "test"
# 应该输出: test（如果有 ENTRYPOINT 会报错或输出异常）
```

### Q6: 基础镜像如何选择？

**A**:
根据工具的 GPU 和 Python 要求：

| 工具类型 | 推荐基础镜像 |
|---------|-------------|
| PyTorch + CUDA 11.8 | `nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu22.04` |
| PyTorch + CUDA 12.1 | `nvidia/cuda:12.1.0-cudnn8-runtime-ubuntu22.04` |
| TensorFlow + GPU | `tensorflow/tensorflow:2.13.0-gpu` |
| 纯 Python (no GPU) | `python:3.10-slim` |

### Q7: 镜像太大怎么优化？

**A**:
```dockerfile
# 1. 使用 multi-stage build
FROM python:3.10 AS builder
RUN pip install --no-cache-dir <packages>

FROM python:3.10-slim
COPY --from=builder /usr/local/lib/python3.10/site-packages /usr/local/lib/python3.10/site-packages

# 2. 清理缓存
RUN apt-get update && apt-get install -y <packages> \
    && rm -rf /var/lib/apt/lists/*  # 清理 apt 缓存

RUN pip install --no-cache-dir <packages>  # 不保留 pip 缓存

# 3. 合并 RUN 指令
RUN apt-get update && apt-get install -y pkg1 pkg2 \
    && pip install pkg3 pkg4 \
    && rm -rf /var/lib/apt/lists/*
```

---

## 检查清单

在提交镜像前，确保：

**镜像构建** ✅
- [ ] 构建了 `:latest` 镜像
- [ ] 构建了 `:nextflow` 镜像
- [ ] `:nextflow` 镜像已移除 ENTRYPOINT
- [ ] 两个镜像功能完全一致（除 ENTRYPOINT）

**ECR 推送** ✅
- [ ] `:latest` 镜像已推送到 ECR
- [ ] `:nextflow` 镜像已推送到 ECR
- [ ] 镜像命名符合规范: `biomate/ai-tools/<tool>`
- [ ] 镜像在正确的 region (us-west-2)

**验证测试** ✅
- [ ] `docker inspect` 确认 ENTRYPOINT 为空
- [ ] 本地运行 `--help` 正常
- [ ] 测试数据执行成功（如有）
- [ ] EC2 GPU 测试通过（如需 GPU）

**文档** 📋
- [ ] 创建了 README.md
- [ ] 记录了镜像版本和依赖
- [ ] 提供了使用示例
- [ ] 说明了测试方法

---

## 参考案例

### 成功案例: Chai-1

**文件结构**:
```
docker/chai1-nextflow-wrapper/
├── Dockerfile          # 原始镜像
├── Dockerfile.nextflow # 只有 3 行！
├── build-and-push.sh
└── README.md
```

**Dockerfile.nextflow 内容**:
```dockerfile
FROM 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/chai1:latest
ENTRYPOINT []
CMD ["python", "-m", "chai_lab.chai1"]
```

**就这么简单！** 只需要 3 行代码。

---

### 成功案例: Boltz

**Dockerfile.nextflow 内容**:
```dockerfile
FROM 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/boltz:latest
ENTRYPOINT []
LABEL purpose="nextflow"
```

**特点**: 甚至不需要 CMD，更加简洁。

---

## 联系和支持

**遇到问题时**:
1. 查阅本文档的 FAQ 部分
2. 检查参考案例（Chai-1, Boltz）
3. 查看详细技术文档: `docker/DOCKER_ENTRYPOINT_ISSUE.md`
4. 联系 Galaxy 团队

**提供的信息**:
- 工具名称和版本
- Dockerfile 内容
- 错误日志
- `docker inspect` 输出

---

## 附录: 完整示例

### 示例工具: MyTool

**Dockerfile** (原始镜像):
```dockerfile
FROM nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu22.04

RUN apt-get update && apt-get install -y \
    python3.10 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/mytool

COPY requirements.txt .
RUN pip3 install --no-cache-dir -r requirements.txt

COPY . .
RUN pip3 install -e .

ENTRYPOINT ["mytool"]
CMD ["--help"]

LABEL version="1.0.0"
```

**Dockerfile.nextflow** (Wrapper 镜像):
```dockerfile
FROM 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/mytool:latest

ENTRYPOINT []
CMD ["mytool"]

LABEL maintainer="Galaxy Team"
LABEL purpose="nextflow"
```

**build-and-push.sh**:
```bash
#!/bin/bash
set -e

ECR_REGISTRY="399683337364.dkr.ecr.us-west-2.amazonaws.com"
TOOL_NAME="mytool"
IMAGE_NAME="biomate/ai-tools/${TOOL_NAME}"

# 登录 ECR
aws ecr get-login-password --region us-west-2 | \
    docker login --username AWS --password-stdin ${ECR_REGISTRY}

# 构建并推送原始镜像
docker build -t ${IMAGE_NAME}:latest -f Dockerfile .
docker tag ${IMAGE_NAME}:latest ${ECR_REGISTRY}/${IMAGE_NAME}:latest
docker push ${ECR_REGISTRY}/${IMAGE_NAME}:latest

# 构建并推送 Nextflow wrapper
docker build -t ${IMAGE_NAME}:nextflow -f Dockerfile.nextflow .
docker tag ${IMAGE_NAME}:nextflow ${ECR_REGISTRY}/${IMAGE_NAME}:nextflow
docker push ${ECR_REGISTRY}/${IMAGE_NAME}:nextflow

echo "✅ Done!"
echo "Latest:   ${ECR_REGISTRY}/${IMAGE_NAME}:latest"
echo "Nextflow: ${ECR_REGISTRY}/${IMAGE_NAME}:nextflow"
```

---

**文档版本**: 1.0
**创建日期**: 2026-03-17
**适用对象**: Docker 镜像构建工程师
**验证状态**: ✅ 已验证（Chai-1, Boltz 成功案例）
