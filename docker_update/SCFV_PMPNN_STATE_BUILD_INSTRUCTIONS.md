# scFv-pMPNN 和 STATE Docker 镜像构建指南

**目标读者**: 打包同事
**紧急程度**: 🔴 高优先级
**原因**: 当前 scFv-pMPNN 基础镜像不完整，导致 Galaxy workflow 失败
**创建日期**: 2026-03-24

---

## 问题说明

**scFv-pMPNN workflow 失败**，退出码 2，所有重试均失败。

**根本原因**（基于 ProFam 的调试经验）:
- Docker 基础镜像可能缺少必要的文件或依赖
- `/opt/scfv-pmpnn/run_design.py` 可能不存在
- Python 依赖包可能未安装（类似 ProFam 的 `requirements.txt` 未安装问题）

**参考文档**: [PROFAM_BASE_IMAGE_FIX.md](PROFAM_BASE_IMAGE_FIX.md)

---

## 核心要求（⭐️ 必须遵守）

### 1. 每个工具需要两个镜像标签

| 标签 | ENTRYPOINT | 用途 |
|------|------------|------|
| `latest` | ✅ 可以有 | 基础镜像，供独立使用 |
| `nextflow` | ❌ **必须移除** | Nextflow wrapper，用于 Galaxy/AWS Batch |

**scFv-pMPNN 示例**:
```
399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/scfv-pmpnn:latest
399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/scfv-pmpnn:nextflow
```

**STATE 示例**:
```
399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/state:latest
399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/state:nextflow
```

### 2. 必须包含所有文件和依赖

**关键检查清单**:
- ✅ 所有 Python 脚本存在（如 `run_design.py`）
- ✅ `requirements.txt` 中的所有依赖已安装
- ✅ 工具本身已正确安装（`pip install -e .` 或类似）
- ✅ 模型文件已下载（如果需要）
- ✅ 所有可执行文件有正确权限

---

## scFv-pMPNN 完整构建步骤

### 📋 需要的文件

假设你的 scFv-pMPNN 代码仓库结构如下：
```
scfv-pmpnn/
├── setup.py
├── requirements.txt
├── run_design.py          # ⚠️ 必须存在
├── run_predict.py         # ⚠️ 必须存在
├── scfv_pmpnn/
│   ├── __init__.py
│   ├── design.py
│   └── predict.py
└── models/               # 如果有预训练模型
```

### 步骤 1: 创建基础镜像 Dockerfile

**文件**: `Dockerfile` （用于 `:latest` 标签）

```dockerfile
# 选择合适的基础镜像（根据工具的 CUDA 需求）
FROM nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu22.04

# 安装系统依赖
RUN apt-get update && apt-get install -y \
    python3.10 \
    python3-pip \
    git \
    wget \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# 设置工作目录
WORKDIR /opt/scfv-pmpnn

# 复制所有代码到镜像
COPY . /opt/scfv-pmpnn/

# ⚠️ 关键步骤：安装所有 Python 依赖
# 确保 requirements.txt 中的所有包都被安装
RUN pip3 install --no-cache-dir -r requirements.txt

# ⚠️ 关键步骤：安装工具本身
RUN pip3 install --no-cache-dir -e .

# ⚠️ 关键步骤：确保所有脚本可执行
RUN chmod +x /opt/scfv-pmpnn/run_design.py && \
    chmod +x /opt/scfv-pmpnn/run_predict.py

# ⚠️ 如果有模型文件需要预下载，在这里下载
# RUN python3 -c "from scfv_pmpnn import download_models; download_models()"

# 验证安装（推荐）
RUN python3 -c "import scfv_pmpnn; print(f'scFv-pMPNN version: {scfv_pmpnn.__version__}')" && \
    python3 run_design.py --help && \
    python3 run_predict.py --help

# 元数据
LABEL maintainer="BioMate AI Team"
LABEL description="scFv-pMPNN: AI-powered antibody sequence design"
LABEL version="1.0.0"

# 原始镜像可以有 ENTRYPOINT（方便用户使用）
ENTRYPOINT ["python3", "/opt/scfv-pmpnn/run_design.py"]
CMD ["--help"]
```

### 步骤 2: 创建 Nextflow Wrapper Dockerfile

**文件**: `Dockerfile.nextflow` （用于 `:nextflow` 标签）

```dockerfile
# 基于 latest 镜像构建
FROM 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/scfv-pmpnn:latest

# ⭐️ 核心要求：移除 ENTRYPOINT
ENTRYPOINT []

# CMD 可以保留（作为默认命令）
CMD ["/bin/bash"]

# 元数据
LABEL maintainer="Galaxy Team"
LABEL description="scFv-pMPNN wrapper for Nextflow/AWS Batch"
LABEL base-image="biomate/ai-tools/scfv-pmpnn:latest"
LABEL wrapper-version="1.0"
LABEL purpose="nextflow"
```

### 步骤 3: 构建和推送脚本

**文件**: `build-and-push-scfv-pmpnn.sh`

```bash
#!/bin/bash
set -e

echo "=== scFv-pMPNN Docker 镜像构建和推送 ==="

# 配置
ECR_REGISTRY="399683337364.dkr.ecr.us-west-2.amazonaws.com"
IMAGE_NAME="biomate/ai-tools/scfv-pmpnn"
AWS_REGION="us-west-2"

# 步骤 1: 登录 ECR
echo "Step 1: 登录 ECR..."
aws ecr get-login-password --region ${AWS_REGION} | \
    docker login --username AWS --password-stdin ${ECR_REGISTRY}

# 步骤 2: 构建基础镜像
echo "Step 2: 构建基础镜像 (latest)..."
docker build -t ${IMAGE_NAME}:latest -f Dockerfile .

# 步骤 3: 推送基础镜像
echo "Step 3: 推送基础镜像到 ECR..."
docker tag ${IMAGE_NAME}:latest ${ECR_REGISTRY}/${IMAGE_NAME}:latest
docker push ${ECR_REGISTRY}/${IMAGE_NAME}:latest

# 步骤 4: 构建 Nextflow wrapper 镜像
echo "Step 4: 构建 Nextflow wrapper 镜像..."
docker build -t ${IMAGE_NAME}:nextflow -f Dockerfile.nextflow .

# 步骤 5: 推送 Nextflow wrapper 镜像
echo "Step 5: 推送 Nextflow wrapper 镜像到 ECR..."
docker tag ${IMAGE_NAME}:nextflow ${ECR_REGISTRY}/${IMAGE_NAME}:nextflow
docker push ${ECR_REGISTRY}/${IMAGE_NAME}:nextflow

echo ""
echo "✅ 完成！两个镜像已成功推送："
echo "  - ${ECR_REGISTRY}/${IMAGE_NAME}:latest"
echo "  - ${ECR_REGISTRY}/${IMAGE_NAME}:nextflow"
```

### 步骤 4: 验证镜像

```bash
#!/bin/bash

ECR_REGISTRY="399683337364.dkr.ecr.us-west-2.amazonaws.com"
IMAGE="${ECR_REGISTRY}/biomate/ai-tools/scfv-pmpnn:nextflow"

echo "=== 验证 scFv-pMPNN 镜像 ==="

# 测试 1: 检查文件存在
echo "Test 1: 检查关键文件..."
docker run --rm --entrypoint /bin/bash ${IMAGE} -c "ls -la /opt/scfv-pmpnn/run_design.py"
docker run --rm --entrypoint /bin/bash ${IMAGE} -c "ls -la /opt/scfv-pmpnn/run_predict.py"

# 测试 2: 检查 Python 模块
echo "Test 2: 检查 Python 模块..."
docker run --rm --entrypoint /bin/bash ${IMAGE} -c "python3 -c 'import scfv_pmpnn; print(scfv_pmpnn.__version__)'"

# 测试 3: 检查依赖包
echo "Test 3: 检查关键依赖..."
docker run --rm --entrypoint /bin/bash ${IMAGE} -c "python3 -c 'import torch; import transformers; import biopython'"

# 测试 4: 运行 help 命令
echo "Test 4: 运行 help 命令..."
docker run --rm --entrypoint /bin/bash ${IMAGE} -c "python3 /opt/scfv-pmpnn/run_design.py --help"

echo "✅ 所有验证通过！"
```

---

## STATE 完整构建步骤

### 📋 需要的文件

STATE 代码仓库结构：
```
state/
├── setup.py
├── requirements.txt
├── run_state.py          # ⚠️ 主执行脚本
├── state/
│   ├── __init__.py
│   ├── model.py
│   └── predict.py
└── models/               # 如果有预训练模型
```

### 步骤 1: 创建基础镜像 Dockerfile

**文件**: `Dockerfile` （用于 `:latest` 标签）

```dockerfile
# 选择合适的基础镜像
FROM nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu22.04

# 安装系统依赖
RUN apt-get update && apt-get install -y \
    python3.10 \
    python3-pip \
    git \
    wget \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# 设置工作目录
WORKDIR /opt/state

# 复制所有代码到镜像
COPY . /opt/state/

# ⚠️ 关键步骤：安装所有 Python 依赖
RUN pip3 install --no-cache-dir -r requirements.txt

# ⚠️ 关键步骤：安装工具本身
RUN pip3 install --no-cache-dir -e .

# ⚠️ 关键步骤：确保所有脚本可执行
RUN chmod +x /opt/state/run_state.py

# ⚠️ 如果有模型文件需要预下载，在这里下载
# RUN python3 -c "from state import download_models; download_models()"

# 验证安装
RUN python3 -c "import state; print(f'STATE version: {state.__version__}')" && \
    python3 run_state.py --help

# 元数据
LABEL maintainer="BioMate AI Team"
LABEL description="STATE: Structure-based protein design"
LABEL version="1.0.0"

# 原始镜像可以有 ENTRYPOINT
ENTRYPOINT ["python3", "/opt/state/run_state.py"]
CMD ["--help"]
```

### 步骤 2: 创建 Nextflow Wrapper Dockerfile

**文件**: `Dockerfile.nextflow`

```dockerfile
# 基于 latest 镜像构建
FROM 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/state:latest

# ⭐️ 核心要求：移除 ENTRYPOINT
ENTRYPOINT []

# CMD 可以保留
CMD ["/bin/bash"]

# 元数据
LABEL maintainer="Galaxy Team"
LABEL description="STATE wrapper for Nextflow/AWS Batch"
LABEL base-image="biomate/ai-tools/state:latest"
LABEL wrapper-version="1.0"
LABEL purpose="nextflow"
```

### 步骤 3: 构建和推送脚本

**文件**: `build-and-push-state.sh`

```bash
#!/bin/bash
set -e

echo "=== STATE Docker 镜像构建和推送 ==="

# 配置
ECR_REGISTRY="399683337364.dkr.ecr.us-west-2.amazonaws.com"
IMAGE_NAME="biomate/ai-tools/state"
AWS_REGION="us-west-2"

# 步骤 1: 登录 ECR
echo "Step 1: 登录 ECR..."
aws ecr get-login-password --region ${AWS_REGION} | \
    docker login --username AWS --password-stdin ${ECR_REGISTRY}

# 步骤 2: 构建基础镜像
echo "Step 2: 构建基础镜像 (latest)..."
docker build -t ${IMAGE_NAME}:latest -f Dockerfile .

# 步骤 3: 推送基础镜像
echo "Step 3: 推送基础镜像到 ECR..."
docker tag ${IMAGE_NAME}:latest ${ECR_REGISTRY}/${IMAGE_NAME}:latest
docker push ${ECR_REGISTRY}/${IMAGE_NAME}:latest

# 步骤 4: 构建 Nextflow wrapper 镜像
echo "Step 4: 构建 Nextflow wrapper 镜像..."
docker build -t ${IMAGE_NAME}:nextflow -f Dockerfile.nextflow .

# 步骤 5: 推送 Nextflow wrapper 镜像
echo "Step 5: 推送 Nextflow wrapper 镜像到 ECR..."
docker tag ${IMAGE_NAME}:nextflow ${ECR_REGISTRY}/${IMAGE_NAME}:nextflow
docker push ${ECR_REGISTRY}/${IMAGE_NAME}:nextflow

echo ""
echo "✅ 完成！两个镜像已成功推送："
echo "  - ${ECR_REGISTRY}/${IMAGE_NAME}:latest"
echo "  - ${ECR_REGISTRY}/${IMAGE_NAME}:nextflow"
```

---

## ⚠️ 常见错误和修复

### 错误 1: ModuleNotFoundError

**症状**:
```
ModuleNotFoundError: No module named 'scfv_pmpnn'
```

**原因**: `requirements.txt` 未安装或工具未安装

**修复**:
```dockerfile
# 确保这两行都存在
RUN pip3 install --no-cache-dir -r requirements.txt
RUN pip3 install --no-cache-dir -e .
```

### 错误 2: FileNotFoundError

**症状**:
```
python: can't open file '/opt/scfv-pmpnn/run_design.py': No such file or directory
```

**原因**: 文件未复制到镜像中

**修复**:
```dockerfile
# 确保所有文件都被复制
COPY . /opt/scfv-pmpnn/

# 验证文件存在
RUN ls -la /opt/scfv-pmpnn/run_design.py
```

### 错误 3: Permission denied

**症状**:
```
bash: /opt/scfv-pmpnn/run_design.py: Permission denied
```

**原因**: 脚本没有执行权限

**修复**:
```dockerfile
RUN chmod +x /opt/scfv-pmpnn/run_design.py
```

---

## 📞 联系方式

**完成后请通知**:
- Galaxy workflow 开发团队

**遇到问题时**:
1. 查看 [DOCKER_PACKAGING_REQUIREMENTS.md](DOCKER_PACKAGING_REQUIREMENTS.md)
2. 参考 [PROFAM_BASE_IMAGE_FIX.md](PROFAM_BASE_IMAGE_FIX.md) - ProFam 的完整修复案例
3. 运行验证脚本确认所有文件和依赖都存在

---

## ✅ 检查清单

构建完成后，请确认：

### scFv-pMPNN
- [ ] `latest` 镜像已推送到 ECR
- [ ] `nextflow` 镜像已推送到 ECR
- [ ] `run_design.py` 存在且可执行
- [ ] `run_predict.py` 存在且可执行
- [ ] `scfv_pmpnn` 模块可导入
- [ ] 所有依赖包已安装
- [ ] `nextflow` 镜像的 ENTRYPOINT 为空

### STATE
- [ ] `latest` 镜像已推送到 ECR
- [ ] `nextflow` 镜像已推送到 ECR
- [ ] `run_state.py` 存在且可执行
- [ ] `state` 模块可导入
- [ ] 所有依赖包已安装
- [ ] `nextflow` 镜像的 ENTRYPOINT 为空

---

**参考文档**:
- [DOCKER_PACKAGING_REQUIREMENTS.md](DOCKER_PACKAGING_REQUIREMENTS.md) - 完整打包规范
- [PROFAM_BASE_IMAGE_FIX.md](PROFAM_BASE_IMAGE_FIX.md) - ProFam 修复案例
- [GPU_WORKFLOW_STANDARD.md](../docs/GPU_WORKFLOW_STANDARD.md) - GPU workflow 开发规范
