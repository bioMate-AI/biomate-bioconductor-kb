# Fix 13: Docker-in-Docker 卷挂载问题

## 问题确认

从 AWS CloudWatch 日志看到：

### Fetch-and-Run 容器中（正常）
```
Debug: Files in INPUT_DIR before Docker run:
total 324
-rw-r--r-- 1 root root 330532 Oct 22 09:09 dataset_a7dcd028-9b6b-4c78-8f7a-11d05508c5fa.dat
Debug: INPUT_DIR path: /tmp/galaxy_job_415/inputs
Debug: Number of files: 1
```

✅ 文件成功下载到 `/tmp/galaxy_job_415/inputs/`

### FastQC 容器中（问题）
```
DEBUG: Files in INPUT_DIR:
total 0
drwxr-xr-x 2 root root 6 Oct 22 09:13 .
drwxr-xr-x 2 root root 6 Oct 22 09:13 ..
```

❌ 挂载的 `/galaxy_inputs` 是空目录！

## 根本原因

**Docker-in-Docker 的嵌套卷挂载问题**：

```
┌─────────────────────────────────────────────────────────┐
│ AWS Batch ECS 实例（宿主机）                              │
├─────────────────────────────────────────────────────────┤
│                                                           │
│  ┌────────────────────────────────────────────────────┐ │
│  │ Fetch-and-Run 容器                                  │ │
│  ├────────────────────────────────────────────────────┤ │
│  │ /tmp/galaxy_job_415/inputs/dataset_xxx.dat        │ │
│  │ ↑ 文件在这里（容器内部文件系统）                    │ │
│  │                                                      │ │
│  │ 执行: docker run -v /tmp/galaxy_job_415/inputs:... │ │
│  │        ↑ 尝试挂载容器内路径                         │ │
│  │                                                      │ │
│  │  ┌──────────────────────────────────────────────┐  │ │
│  │  │ FastQC 容器（嵌套）                           │  │ │
│  │  ├──────────────────────────────────────────────┤  │ │
│  │  │ /galaxy_inputs (空！)                        │  │ │
│  │  │ ↑ Docker 在宿主机上找这个路径，但不存在      │  │ │
│  │  └──────────────────────────────────────────────┘  │ │
│  └────────────────────────────────────────────────────┘ │
│                                                           │
└─────────────────────────────────────────────────────────┘
```

### 为什么会这样？

1. Fetch-and-run 容器下载文件到自己的文件系统：`/tmp/galaxy_job_415/inputs/`
2. 这个路径是**容器内部路径**，在宿主机上不存在
3. 当 fetch-and-run 执行 `docker run -v /tmp/galaxy_job_415/inputs:/galaxy_inputs` 时
4. Docker daemon（运行在宿主机上）尝试在**宿主机**上找 `/tmp/galaxy_job_415/inputs/`
5. 宿主机上没有这个路径，所以挂载了一个空目录

---

## 解决方案

### 方案 1: 使用宿主机 Docker Socket（推荐）

让 fetch-and-run 容器使用宿主机的 Docker daemon，并共享卷。

#### Step 1: 修改 AWS Batch Job Definition

需要在 job definition 中添加：

1. **挂载 Docker socket**
2. **使用命名卷或 bind mount**

```json
{
  "containerProperties": {
    "image": "399683337364.dkr.ecr.us-west-2.amazonaws.com/galaxy-fetch-and-run:latest",
    "vcpus": 2,
    "memory": 4096,
    "privileged": true,  // ← 需要特权模式
    "mountPoints": [
      {
        "sourceVolume": "docker-socket",
        "containerPath": "/var/run/docker.sock",
        "readOnly": false
      },
      {
        "sourceVolume": "work-dir",
        "containerPath": "/work",
        "readOnly": false
      }
    ],
    "volumes": [
      {
        "name": "docker-socket",
        "host": {
          "sourcePath": "/var/run/docker.sock"
        }
      },
      {
        "name": "work-dir",
        "host": {
          "sourcePath": "/tmp"
        }
      }
    ]
  }
}
```

#### Step 2: 修改 fetch_and_run.sh

使用宿主机路径而不是容器路径：

```bash
# 改为使用宿主机可访问的路径
WORK_DIR="/work/galaxy_job_${JOB_ID}"  # 映射到宿主机 /tmp/galaxy_job_XXX
INPUT_DIR="${WORK_DIR}/inputs"
OUTPUT_DIR="${WORK_DIR}/outputs"
SCRIPT_FILE="${WORK_DIR}/job_script.sh"

# 创建目录
mkdir -p "${INPUT_DIR}" "${OUTPUT_DIR}"

# ... 下载文件到 INPUT_DIR ...

# Docker-in-Docker 挂载时使用相同路径
docker run --rm -i \
    -v "${INPUT_DIR}:/galaxy_inputs:ro" \  # ← 现在这个路径在宿主机上存在！
    -v "${OUTPUT_DIR}:/galaxy_outputs:rw" \
    ...
```

但这还是有问题，因为 `WORK_DIR="/work/..."` 在容器内，但宿主机上是 `/tmp/...`。

**更好的方法**: 让容器知道宿主机路径

```bash
# 在环境变量中传递宿主机路径前缀
HOST_WORK_PREFIX="${HOST_WORK_PREFIX:-/tmp}"  # 从环境变量获取，默认 /tmp

# 容器内路径
CONTAINER_WORK_DIR="/work/galaxy_job_${JOB_ID}"
INPUT_DIR="${CONTAINER_WORK_DIR}/inputs"
OUTPUT_DIR="${CONTAINER_WORK_DIR}/outputs"

# 宿主机路径（用于 Docker 挂载）
HOST_WORK_DIR="${HOST_WORK_PREFIX}/galaxy_job_${JOB_ID}"
HOST_INPUT_DIR="${HOST_WORK_DIR}/inputs"
HOST_OUTPUT_DIR="${HOST_WORK_DIR}/outputs"

# 下载文件到容器路径
mkdir -p "${INPUT_DIR}" "${OUTPUT_DIR}"
aws s3 sync "s3://bucket/inputs/" "${INPUT_DIR}/"

# Docker 挂载使用宿主机路径
docker run --rm -i \
    -v "${HOST_INPUT_DIR}:/galaxy_inputs:ro" \
    -v "${HOST_OUTPUT_DIR}:/galaxy_outputs:rw" \
    ...
```

---

### 方案 2: 不使用 Docker-in-Docker（简单但不通用）

直接在 fetch-and-run 容器中安装所有工具。

优点：
- 简单，无嵌套问题
- 更快（不需要拉取镜像）

缺点：
- 镜像会很大
- 无法使用 BioContainers 的标准镜像
- 工具更新困难

**不推荐**，因为失去了容器化的灵活性。

---

### 方案 3: 使用 Bind Mount 到宿主机已知路径（实用）

修改 job definition，将宿主机的 `/tmp` 挂载到容器：

```json
{
  "mountPoints": [
    {
      "sourceVolume": "tmp",
      "containerPath": "/host-tmp",
      "readOnly": false
    }
  ],
  "volumes": [
    {
      "name": "tmp",
      "host": {
        "sourcePath": "/tmp"
      }
    }
  ]
}
```

然后在 fetch_and_run.sh 中：

```bash
# 使用挂载的宿主机 /tmp
WORK_DIR="/host-tmp/galaxy_job_${JOB_ID}"
INPUT_DIR="${WORK_DIR}/inputs"
OUTPUT_DIR="${WORK_DIR}/outputs"

mkdir -p "${INPUT_DIR}" "${OUTPUT_DIR}"

# 下载文件
aws s3 sync "s3://bucket/inputs/" "${INPUT_DIR}/"

# Docker 挂载（宿主机视角）
docker run --rm -i \
    -v "/tmp/galaxy_job_${JOB_ID}/inputs:/galaxy_inputs:ro" \
    -v "/tmp/galaxy_job_${JOB_ID}/outputs:/galaxy_outputs:rw" \
    ...
```

**这个方案最简单实用！**

---

## 实施 Fix 13

我选择**方案 3**，因为：
1. 最小改动
2. 不需要修改 job definition（AWS Batch 已经支持）
3. 不需要特权模式
4. 兼容性好

### 修改 fetch_and_run.sh

```bash
#!/bin/bash
set -e
set -o pipefail

# ... 前面的代码 ...

# Step 0: Determine work directory strategy
# If running in AWS Batch EC2, we can use /tmp which is shared with host
# Otherwise fall back to container-local /tmp
if [ -d "/host-tmp" ]; then
    # Batch EC2 with mounted host /tmp
    BASE_TMP="/host-tmp"
    USE_HOST_PATHS=true
else
    # Fallback to container-local
    BASE_TMP="/tmp"
    USE_HOST_PATHS=false
fi

WORK_DIR="${BASE_TMP}/galaxy_job_${JOB_ID}"
INPUT_DIR="${WORK_DIR}/inputs"
OUTPUT_DIR="${WORK_DIR}/outputs"
SCRIPT_FILE="${WORK_DIR}/job_script.sh"

mkdir -p "${WORK_DIR}" "${INPUT_DIR}" "${OUTPUT_DIR}"

echo "Work directory: ${WORK_DIR}"
echo "Use host paths for Docker: ${USE_HOST_PATHS}"

# ... 下载文件 ...

# Step 3: Execute with Docker-in-Docker
if [ -n "${TOOL_CONTAINER_IMAGE}" ]; then
    # Determine paths for Docker volume mounting
    if [ "${USE_HOST_PATHS}" = "true" ]; then
        # Use host paths (宿主机的 /tmp/galaxy_job_XXX)
        DOCKER_INPUT_DIR="/tmp/galaxy_job_${JOB_ID}/inputs"
        DOCKER_OUTPUT_DIR="/tmp/galaxy_job_${JOB_ID}/outputs"
    else
        # Use container paths (same as WORK_DIR)
        DOCKER_INPUT_DIR="${INPUT_DIR}"
        DOCKER_OUTPUT_DIR="${OUTPUT_DIR}"
    fi

    echo "Docker mount: ${DOCKER_INPUT_DIR} -> /galaxy_inputs"
    echo "Docker mount: ${DOCKER_OUTPUT_DIR} -> /galaxy_outputs"

    docker run --rm -i \
        -v "${DOCKER_INPUT_DIR}:/galaxy_inputs:ro" \
        -v "${DOCKER_OUTPUT_DIR}:/galaxy_outputs:rw" \
        ...
fi
```

### 修改 AWS Batch Job Definition（可选，但推荐）

在 job definition 中添加 `/tmp` 挂载：

```python
# galaxy_job_runner.py 或 aws/executor.py

def _build_mount_points(self, job_spec):
    """Build mount points for job"""
    mount_points = []
    volumes = []

    # Mount host /tmp for Docker-in-Docker file sharing
    mount_points.append({
        "sourceVolume": "host-tmp",
        "containerPath": "/host-tmp",
        "readOnly": False
    })
    volumes.append({
        "name": "host-tmp",
        "host": {
            "sourcePath": "/tmp"
        }
    })

    # Mount Docker socket for Docker-in-Docker
    mount_points.append({
        "sourceVolume": "docker-socket",
        "containerPath": "/var/run/docker.sock",
        "readOnly": False
    })
    volumes.append({
        "name": "docker-socket",
        "host": {
            "sourcePath": "/var/run/docker.sock"
        }
    })

    return mount_points, volumes
```

---

## 测试

### 预期效果

#### Before (Fix 13 之前)
```
Fetch-and-Run: /tmp/galaxy_job_415/inputs/dataset.dat  ✅ 存在
FastQC 容器:    /galaxy_inputs/                         ❌ 空的！
```

#### After (Fix 13 之后)
```
Fetch-and-Run: /host-tmp/galaxy_job_415/inputs/dataset.dat  ✅ 存在
             = 宿主机 /tmp/galaxy_job_415/inputs/dataset.dat

Docker mount:  /tmp/galaxy_job_415/inputs -> /galaxy_inputs
FastQC 容器:    /galaxy_inputs/dataset.dat                   ✅ 可见！
```

### 验证步骤

1. 重新构建 fetch-and-run 镜像
2. 推送到 ECR
3. 运行测试 workflow
4. 检查 CloudWatch 日志：
   ```
   Debug: Files in INPUT_DIR:
   total 324
   -rw-r--r-- ... dataset.dat  ← 应该能看到文件！
   ```

---

## 总结

Fix 13 解决了 Docker-in-Docker 的卷挂载问题：

- **根本原因**: 嵌套容器无法访问父容器的文件系统
- **解决方案**: 使用宿主机共享路径（`/tmp` 通过 `/host-tmp` 挂载）
- **关键修改**: fetch_and_run.sh 使用宿主机路径进行 Docker 挂载

配合 Fix 12 的路径重写，现在应该能完整运行 workflow 了！
