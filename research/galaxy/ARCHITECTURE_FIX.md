# 架构问题修复记录

## 问题

AWS 容器日志显示错误：
```
exec /usr/local/bin/fetch_and_run.sh: exec format error
```

## 原因

Docker 镜像是在 Apple Silicon (ARM64) 机器上构建的，但 AWS Batch compute environment 使用的是 x86_64 架构的实例。

- **本地构建架构**: ARM64 (aarch64)
- **AWS Batch 实例**: x86_64 (amd64)

当 x86_64 实例尝试运行 ARM64 二进制文件时，会出现 "exec format error"。

## 解决方案

使用 Docker Buildx 进行跨平台构建，明确指定目标平台为 `linux/amd64`。

### 修改的文件

**`docker/fetch-and-run/build_and_push.sh`**:

```bash
# 之前 (自动使用本地架构)
docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" .

# 之后 (明确指定 x86_64)
docker buildx build --platform linux/amd64 -t "${IMAGE_NAME}:${IMAGE_TAG}" --load .
```

### 重新构建

```bash
cd /Users/renyuankai/work/biometa/galaxy/docker/fetch-and-run
./build_and_push.sh
```

### 验证

```bash
# 检查镜像架构
docker inspect galaxy-fetch-and-run:latest --format '{{.Architecture}}'
# 输出: amd64 ✅
```

## 新镜像信息

- **ECR URI**: `399683337364.dkr.ecr.us-west-2.amazonaws.com/galaxy-fetch-and-run:latest`
- **架构**: `linux/amd64` (x86_64)
- **Digest**: `sha256:c0d3a3e34046963db3b366ce6fa19996df1bc122db5e4b90473edf6ea2015baf`
- **推送时间**: 2025-10-21 14:38 (CST)

## Docker CLI 安装

镜像中包含 Docker CLI v20.10.9，根据架构自动下载：

```dockerfile
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "aarch64" ]; then DOCKER_ARCH="aarch64"; \
    elif [ "$ARCH" = "x86_64" ]; then DOCKER_ARCH="x86_64"; \
    else echo "Unsupported architecture: $ARCH" && exit 1; fi && \
    curl -fsSL https://download.docker.com/linux/static/stable/${DOCKER_ARCH}/docker-20.10.9.tgz -o docker.tgz && \
    tar --extract --file docker.tgz --strip-components 1 --directory /usr/local/bin/ docker/docker && \
    rm docker.tgz && \
    docker --version
```

在 x86_64 容器中执行时，自动下载 x86_64 版本的 Docker CLI。

## 测试

现在可以重新运行 Galaxy workflow，应该不会再出现 "exec format error" 了。

### 检查 AWS Batch 日志

预期看到：
```
=========================================
Galaxy Fetch-and-Run Starting
=========================================
Job ID: 196
S3 Bucket: galaxy-cloud-data-1760241377
AWS Region: us-west-2
...
```

而不是之前的错误：
```
exec /usr/local/bin/fetch_and_run.sh: exec format error ❌
```

## 经验教训

1. **跨平台构建**: 在 Apple Silicon Mac 上构建用于 AWS 的镜像时，务必使用 `--platform linux/amd64`
2. **验证架构**: 推送前检查镜像架构 (`docker inspect`)
3. **AWS Batch**: 默认使用 x86_64 实例（除非明确配置 ARM Graviton 实例）
4. **Buildx**: Docker Buildx 支持多平台构建，是最佳实践

## 相关命令

```bash
# 查看本地镜像架构
docker inspect <image>:<tag> --format '{{.Architecture}}'

# 构建多平台镜像（如果需要同时支持 ARM 和 x86）
docker buildx build --platform linux/amd64,linux/arm64 -t <image>:<tag> --push .

# 查看 AWS Batch compute environment 实例类型
aws batch describe-compute-environments --region us-west-2

# 查看 ECR 镜像详情
aws ecr describe-images --repository-name galaxy-fetch-and-run --region us-west-2
```

## 状态

✅ **已修复** - 镜像已重新构建为 x86_64 架构并推送到 ECR
