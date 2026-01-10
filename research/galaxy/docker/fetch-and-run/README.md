# Galaxy Cloud Executor - A+B Solution

## 概述

这是一个**通用的Galaxy workflow云执行解决方案**，使用"A+B策略"平衡性能和通用性：

- **A方案 (90%)**: 预装通用运行环境 - Python、R、Perl及常用包
- **B方案 (10%)**: 运行时动态安装缺失的包 - 自动检测并安装

### 核心优势

1. ✅ **通用性** - 无需为每个工具编写if-else逻辑，自动适配所有Galaxy workflows
2. ✅ **快速启动** - 90%的工具开箱即用，无需等待依赖安装
3. ✅ **容错性** - 自动检测并修复依赖问题（如BiocManager自动安装）
4. ✅ **可扩展** - 未来可逐步为高频工具构建专用容器

## 快速开始

### 构建镜像

一键构建并推送到ECR：

```bash
cd docker/fetch-and-run
./build_and_push.sh
```

脚本会自动：
1. 验证Dockerfile和fetch_and_run.sh存在
2. 构建Docker镜像（5-10分钟）
3. 登录ECR
4. 推送镜像到ECR
5. 保存digest到latest-digest.txt

### 更新Galaxy配置

构建完成后，脚本会输出新的digest。更新Galaxy配置：

```python
# lib/galaxy/galaxy-cloud-executor/galaxy_cloud/galaxy_workflow/galaxy_job_runner.py
# 行号: ~1304

fetch_and_run_image = job_destination.params.get(
    'fetch_and_run_image',
    f"{account}.dkr.ecr.{region}.amazonaws.com/galaxy-fetch-and-run@sha256:NEW_DIGEST_HERE"
)
```

### 重启Galaxy

```bash
pkill -f 'python.*run.py'
PYTHONPATH=lib sh run.sh --daemon
```

## A+B方案详解

### A方案：预装环境 (90%)

**Dockerfile配置：**
- Python 3.9 + numpy, pandas, biopython
- Perl 5 + perl-core
- R + BiocManager + getopt
- AWS CLI
- Docker CLI（用于Docker-in-Docker）

**预装的R包：**
- `BiocManager` - 通用包管理器（支持CRAN和Bioconductor）
- `getopt` - 命令行参数解析（最常用）

### B方案：动态安装 (10%)

**fetch_and_run.sh中的关键逻辑：**

```bash
# 1. 检测缺失的R包
MISSING_PACKAGES=$(Rscript -e "
packages <- c('DESeq2', 'edgeR', ...)
installed <- installed.packages()[,1]
missing <- setdiff(packages, installed)
cat(missing, sep=' ')
")

# 2. 自动安装BiocManager（如果缺失）⭐️ 关键修复
if ! Rscript -e "library('BiocManager')" 2>/dev/null; then
    echo "[DYNAMIC-INSTALL] BiocManager not found, installing..."
    Rscript -e "install.packages('BiocManager', repos='https://cloud.r-project.org/')"
fi

# 3. 使用BiocManager安装缺失的包
for pkg in $MISSING_PACKAGES; do
    echo "[DYNAMIC-INSTALL] Installing R package: $pkg"
    Rscript -e "BiocManager::install('$pkg', update=FALSE, ask=FALSE)"
done
```

## 关键Bug修复：BiocManager自动安装

### 问题描述

之前DESeq2安装失败的原因：

```bash
# ❌ 错误：直接使用BiocManager，但它可能不存在
Rscript -e "BiocManager::install('DESeq2')"

# 错误信息：
# Error: package 'BiocManager' is not installed
```

### 解决方案

在使用BiocManager前先检查并安装：

```bash
# ✅ 正确：先检查并安装BiocManager
if ! Rscript -e "library('BiocManager')" 2>/dev/null; then
    install.packages('BiocManager')
fi
BiocManager::install('DESeq2')
```

## 文件说明

```
docker/fetch-and-run/
├── Dockerfile                 # A+B容器定义
├── fetch_and_run.sh          # 通用执行脚本（含动态安装逻辑）
├── build_and_push.sh         # 本地构建脚本 ⭐️ 推荐使用
├── build_galaxy_cloud_image.sh # AWS Batch构建脚本（已废弃）
├── latest-digest.txt         # 最新镜像digest（自动生成）
└── README.md                 # 本文档
```

## 架构对比

### 之前的问题 ❌
- 每次都要编译R包（5-10分钟）
- DESeq2安装失败率高（BiocManager未安装）
- 网络波动导致构建失败

### A+B方案后 ✅
- 90%工具零等待
- BiocManager自动修复依赖
- 只需初次构建镜像（5-10分钟）
- 后续使用直接拉取预构建镜像

## 与Nextflow对比

| 特性 | Nextflow | Galaxy (A+B方案) |
|-----|----------|------------------|
| 云原生支持 | ✅ 原生 | ⚠️ 需要adapter |
| 容器化 | ✅ 容器优先 | ⚠️ 混合模式 |
| Web UI | ❌ 命令行 | ✅ 友好UI |
| Python生态 | ❌ Groovy DSL | ✅ 原生集成 |
| 学习曲线 | 中等 | 低（非技术用户） |

**结论：**
- 技术团队、标准分析 → 推荐Nextflow
- 非技术用户、Python生态 → 推荐Galaxy A+B方案

## 故障排查

### 构建失败

查看构建日志：
```bash
tail -100 /tmp/docker-build-local.log
```

### 推送失败

检查ECR登录：
```bash
aws ecr get-login-password --region us-west-2 | \
  docker login --username AWS --password-stdin 399683337364.dkr.ecr.us-west-2.amazonaws.com
```

### R包安装失败

常见问题：
1. **网络超时** - 在AWS内网速度正常，本地构建可能慢
2. **依赖缺失** - 确保Dockerfile安装了libxml2-devel等开发库
3. **版本冲突** - BiocManager会自动处理版本依赖

查看运行时日志：
```bash
# 在Galaxy job详情中查看容器输出
# 搜索 "[DYNAMIC-INSTALL]" 关键字
```

## 未来优化

### 短期（当前A+B方案）✅
- 预装通用环境
- 动态安装缺失包
- 自动修复BiocManager依赖

### 中期（工具统计）
- 收集高频使用的工具
- 识别动态安装频率最高的包
- 为TOP 20工具构建专用容器

### 长期（专用容器）
- 为每个主要工具构建专用容器
- 使用Planemo + Bioconda自动生成
- 最终消除动态安装

## 版本历史

- **v1.0** (2025-10-31) - 初始A+B方案，修复BiocManager bug
  - 预装Python + R + Perl
  - 预装BiocManager + getopt
  - 自动检测并安装BiocManager
  - Digest: sha256:4e90bbc130e2179251648ec270b01b7ac9215842a79683526d6d8e797e48d369

## 相关文档

- [AWS Batch文档](https://docs.aws.amazon.com/batch/)
- [Galaxy文档](https://docs.galaxyproject.org/)
- [BiocManager文档](https://bioconductor.org/install/)
- [Docker文档](https://docs.docker.com/)

## 联系与支持

遇到问题？
1. 查看构建日志：/tmp/docker-build-local.log
2. 查看Galaxy job日志：在Web UI中查看job详情
3. 检查AWS Batch任务状态：AWS控制台
