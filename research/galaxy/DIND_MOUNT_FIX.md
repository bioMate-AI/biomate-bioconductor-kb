# Docker-in-Docker 嵌套挂载问题修复

## 问题诊断

### AWS 错误日志
```
Inside container:
total 0
drwxr-xr-x 2 root root 6 Oct 21 14:36 inputs    # ✓ 可见
drwxr-xr-x 2 root root 6 Oct 21 14:36 outputs   # ✓ 可见
                                                 # ✗ job_script.sh 不见了！

bash: /tmp/galaxy_job_370/job_script.sh: No such file or directory
```

### 问题分析

**环境架构**：
```
宿主机 (EC2)
  └─ Fetch-and-Run 容器
      ├─ /tmp/galaxy_job_370/job_script.sh  ✓ 存在
      ├─ /tmp/galaxy_job_370/inputs/         ✓ 存在
      ├─ /tmp/galaxy_job_370/outputs/        ✓ 存在
      └─ 启动 → 工具容器 (FastQC)
                 └─ 尝试访问 /tmp/galaxy_job_370/job_script.sh  ✗ 不存在
```

**根本原因**：

这是一个 **Docker-in-Docker 嵌套挂载问题**：

1. **Fetch-and-run 容器**内的文件在 `/tmp/galaxy_job_370/`
2. **工具容器**由 fetch-and-run 启动（Docker-in-Docker）
3. 挂载命令：`-v /tmp/galaxy_job_370:/tmp/galaxy_job_370:rw`
4. **问题**：这个路径在 **fetch-and-run 容器内**，不在 **宿主机**上！

**技术细节**：
- Docker-in-Docker 时，`docker run -v` 中的路径是相对于**宿主机**的
- Fetch-and-run 容器内的路径对工具容器不可见
- 只有宿主机上实际存在的路径才能被挂载

**为什么 inputs/ 和 outputs/ 可见？**
- 这些目录在 fetch-and-run 容器内创建：`mkdir -p "${INPUT_DIR}" "${OUTPUT_DIR}"`
- Docker 会自动在工具容器内创建这些目录（即使挂载源不存在）
- 但是 **文件内容** 是空的（因为挂载源不存在）

## 解决方案对比

### 方案 A: 挂载宿主机路径（复杂）✗

需要知道宿主机的真实路径，复杂且不可靠：

```bash
# 需要找到宿主机路径
HOST_PATH=$(docker inspect fetch-and-run-container | jq ...)
docker run -v "${HOST_PATH}:..." tool-container
```

**问题**：
- 需要复杂的路径转换
- 容器内无法获取宿主机路径
- 不同环境路径不同

### 方案 B: 通过 stdin 传递脚本（简单）✓

**选择的方案**：直接通过标准输入传递脚本内容

```bash
# 不需要挂载脚本文件
docker run --rm -i \
    -v "${INPUT_DIR}:/galaxy_inputs:ro" \
    -v "${OUTPUT_DIR}:/galaxy_outputs:rw" \
    "${TOOL_CONTAINER_IMAGE}" \
    bash < "${SCRIPT_FILE}"  # 通过管道传递
```

**优点**：
- ✓ 简单直接
- ✓ 避免挂载问题
- ✓ 跨环境通用
- ✓ 无需修改路径

## 实现细节

### 修改前（有问题）

```bash
# 尝试挂载整个工作目录
docker run --rm \
    -v "${WORK_DIR}:${WORK_DIR}:rw" \  # ✗ 路径在容器内，不在宿主机
    -v "${INPUT_DIR}:/galaxy_inputs:ro" \
    -v "${OUTPUT_DIR}:/galaxy_outputs:rw" \
    -w "${WORK_DIR}" \
    "${TOOL_CONTAINER_IMAGE}" \
    bash "${SCRIPT_FILE}"  # ✗ 文件不存在
```

### 修改后（正确）

```bash
# 通过 stdin 传递脚本，避免挂载问题
docker run --rm -i \  # -i 启用交互模式（stdin）
    -v "${INPUT_DIR}:/galaxy_inputs:ro" \  # ✓ 只挂载 inputs 和 outputs
    -v "${OUTPUT_DIR}:/galaxy_outputs:rw" \
    -e GALAXY_INPUT_DIR="/galaxy_inputs" \
    -e GALAXY_OUTPUT_DIR="/galaxy_outputs" \
    -w /tmp/work \
    "${TOOL_CONTAINER_IMAGE}" \
    bash < "${SCRIPT_FILE}"  # ✓ 通过管道传递脚本内容
```

**关键变化**：
1. 添加 `-i` 标志启用标准输入
2. 移除 `WORK_DIR` 挂载（不需要了）
3. 使用 `< "${SCRIPT_FILE}"` 通过管道传递脚本
4. 更新环境变量使用容器内路径

## 输入输出文件处理

### 问题：inputs 和 outputs 挂载也有问题吗？

**当前状态**：
```bash
-v "${INPUT_DIR}:/galaxy_inputs:ro"   # INPUT_DIR=/tmp/galaxy_job_370/inputs
-v "${OUTPUT_DIR}:/galaxy_outputs:rw" # OUTPUT_DIR=/tmp/galaxy_job_370/outputs
```

**理论上**：这些路径也在 fetch-and-run 容器内，应该也有问题。

**实际上**：
- Docker 会自动创建挂载点目录（即使源不存在）
- 但是 **文件内容** 可能无法正确传递

**进一步优化方案**（如果需要）：

#### 选项 1: 复制文件到容器内
```bash
# 在 docker run 前将文件复制到容器内
# 但这需要容器持久化，不适合 --rm 模式
```

#### 选项 2: 使用 docker cp
```bash
# 启动容器
CONTAINER_ID=$(docker run -d tool-container sleep 3600)

# 复制文件
docker cp "${INPUT_DIR}/." "${CONTAINER_ID}:/galaxy_inputs/"

# 执行脚本
docker exec "${CONTAINER_ID}" bash < "${SCRIPT_FILE}"

# 复制输出
docker cp "${CONTAINER_ID}:/galaxy_outputs/." "${OUTPUT_DIR}/"

# 清理
docker rm -f "${CONTAINER_ID}"
```

#### 选项 3: 通过 tar 流式传输（推荐）
```bash
# 将输入文件打包后通过 stdin 传递
tar -C "${INPUT_DIR}" -cf - . | \
docker run --rm -i \
    -e GALAXY_OUTPUT_DIR="/galaxy_outputs" \
    "${TOOL_CONTAINER_IMAGE}" \
    bash -c "
        mkdir -p /galaxy_inputs /galaxy_outputs
        tar -C /galaxy_inputs -xf -
        # 运行脚本
        bash
        # 打包输出
        tar -C /galaxy_outputs -cf - .
    " | tar -C "${OUTPUT_DIR}" -xf -
```

## 当前实现的权衡

### 优点
- ✓ 脚本执行问题已解决（通过 stdin）
- ✓ 简单实现
- ✓ 快速修复

### 潜在问题
- ⚠ inputs/outputs 挂载可能仍有问题
- ⚠ 需要测试文件传输是否正常

### 测试计划
1. 提交任务查看脚本是否执行（当前修复）
2. 检查输入文件是否能被工具读取
3. 检查输出文件是否能正确回传

## 测试结果（待验证）

### 预期成功的标志
```
✓ 脚本成功执行（不再报错 "No such file or directory"）
✓ 工具能读取输入文件
✓ 输出文件成功上传到 S3
✓ Galaxy 任务状态变为 "ok"
```

### 如果输入文件读取失败

**症状**：
```
✓ 脚本执行
✗ fastqc: cannot open input file
```

**解决方案**：
需要改进输入文件传输机制（使用选项 3 的 tar 流式传输）

## 长期改进建议

### 方案 1: 使用 Volume 插件

AWS 提供 EFS (Elastic File System) 可以在容器间共享：

```yaml
# docker-compose.yml 或 ECS task definition
volumes:
  galaxy_shared:
    driver: efs
    driver_opts:
      fs_id: fs-xxxxx
```

### 方案 2: 重新设计架构

避免 Docker-in-Docker，使用其他隔离机制：

```
选项 A: 使用 ECS 任务间通信
  Fetch-and-run (ECS任务1) → 调度 → Tool (ECS任务2)
  通过 S3 共享文件

选项 B: 使用 AWS Batch 多容器任务
  同一任务内多个容器共享本地文件系统

选项 C: 使用 Kubernetes
  Pod 内多容器共享 Volume
```

### 方案 3: 简化为单容器

最简单的方案：在 fetch-and-run 容器内直接安装工具

```dockerfile
# 在 fetch-and-run 镜像中预装常用工具
FROM amazonlinux:2
RUN yum install -y fastqc trimmomatic ...
```

**问题**：
- 镜像变大
- 工具更新需要重建镜像
- 不够灵活

## 相关问题

### Q: 为什么不直接使用工具容器，跳过 fetch-and-run？

**A**: Fetch-and-run 提供了额外的功能：
- S3 文件传输（下载输入，上传输出）
- 错误处理和日志
- 环境变量设置
- 清理工作

### Q: 这个问题在 Kubernetes 中会出现吗？

**A**: 不会。Kubernetes Pod 中的多容器共享同一个文件系统 Volume。

### Q: 能否使用 Docker --volumes-from？

**A**: 不能。这需要容器持久化运行，不适合 batch job。

## 修复验证清单

- [x] 修改 fetch_and_run.sh 使用 stdin 传递脚本
- [x] 重新构建并推送镜像
- [ ] 提交测试任务
- [ ] 验证脚本执行成功
- [ ] 验证输入文件读取成功
- [ ] 验证输出文件上传成功
- [ ] Galaxy 任务状态变为 "ok"

## 文件修改

**修改文件**: `docker/fetch-and-run/fetch_and_run.sh`

**关键修改**:
```diff
- docker run --rm \
-     -v "${WORK_DIR}:${WORK_DIR}:rw" \
+ docker run --rm -i \
      -v "${INPUT_DIR}:/galaxy_inputs:ro" \
      -v "${OUTPUT_DIR}:/galaxy_outputs:rw" \
-     -w "${WORK_DIR}" \
+     -w /tmp/work \
      "${TOOL_CONTAINER_IMAGE}" \
-     bash "${SCRIPT_FILE}"
+     bash < "${SCRIPT_FILE}"
```

## 下一步

1. **等待测试任务结果**
2. **如果输入文件读取失败**，实施 tar 流式传输方案
3. **如果成功**，考虑长期架构改进

## 参考

- [Docker-in-Docker 最佳实践](https://jpetazzo.github.io/2015/09/03/do-not-use-docker-in-docker-for-ci/)
- [Docker 卷挂载](https://docs.docker.com/storage/volumes/)
- [标准输入重定向](https://www.gnu.org/software/bash/manual/html_node/Redirections.html)
