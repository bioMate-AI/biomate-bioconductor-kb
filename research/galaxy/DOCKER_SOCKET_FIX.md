# Docker-in-Docker Socket 挂载修复

## 问题诊断

### 症状
AWS Batch 任务停留在 RUNNABLE 状态很久，启动后立即失败，错误信息：
```
Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?
```

### 根本原因
Fetch-and-run 容器需要访问宿主机的 Docker daemon 来启动工具容器（如 fastqc, trimmomatic 等），但是：
1. AWS Batch 作业定义**没有挂载 Docker socket**
2. EC2 Launch Template 的用户数据脚本只配置了 socket 权限，但没有告诉容器如何访问

## 解决方案

### 修改的文件
`lib/galaxy/galaxy-cloud-executor/galaxy_cloud/providers/aws/executor.py`

### 修改内容

#### 1. `_build_mount_points` 方法（第 324-347 行）
为 fetch-and-run 容器添加 Docker socket 挂载点：

```python
def _build_mount_points(self, job_spec: JobSpec) -> List[Dict[str, Any]]:
    """Build mount points for the job."""
    mount_points = []

    # Add Docker socket mount for Docker-in-Docker (fetch-and-run mode)
    if 'fetch-and-run' in job_spec.container.image:
        mount_points.append({
            'sourceVolume': 'docker_socket',
            'containerPath': '/var/run/docker.sock',
            'readOnly': False
        })
        logger.info(f"Added Docker socket mount for fetch-and-run container")

    # ... existing EFS mounts code ...
    return mount_points
```

#### 2. `_build_volumes` 方法（第 349-377 行）
添加对应的 host volume 定义：

```python
def _build_volumes(self, job_spec: JobSpec) -> List[Dict[str, Any]]:
    """Build volumes for the job."""
    volumes = []

    # Add Docker socket volume for Docker-in-Docker (fetch-and-run mode)
    # Use 'host' volume type to mount the host's Docker socket
    if 'fetch-and-run' in job_spec.container.image:
        volumes.append({
            'name': 'docker_socket',
            'host': {
                'sourcePath': '/var/run/docker.sock'
            }
        })
        logger.info(f"Added Docker socket volume (host path: /var/run/docker.sock)")

    # ... existing EFS volumes code ...
    return volumes
```

## 技术说明

### AWS Batch Volume 类型
AWS Batch 支持三种 volume 类型：
1. **host** - 挂载 EC2 宿主机路径（用于 Docker socket）
2. **efs** - 挂载 Amazon EFS 文件系统
3. **bind** - Docker bind mount（已弃用）

### Docker-in-Docker 实现方式
```
宿主机 EC2 实例
├── Docker Daemon (/var/run/docker.sock)
├── AWS Batch 容器（fetch-and-run）
│   ├── 挂载: /var/run/docker.sock (来自宿主机)
│   └── Docker CLI (通过 socket 与宿主机 daemon 通信)
│       └── 启动工具容器（fastqc, trimmomatic 等）
```

### 自动检测逻辑
代码通过检查容器镜像名称来判断是否需要 Docker socket：
```python
if 'fetch-and-run' in job_spec.container.image:
    # 添加 Docker socket 挂载
```

这意味着：
- ✓ Fetch-and-run 镜像会自动获得 Docker socket 访问
- ✓ 普通工具镜像不会挂载（更安全）
- ✓ 无需手动配置

## 测试步骤

### 1. 重启 Galaxy
```bash
pkill -f "python.*run.py"
sh start_galaxy_with_ai.sh
```

### 2. 提交测试任务
通过 Galaxy Web UI 提交一个生物信息学任务（如 FastQC）

### 3. 验证成功标志
在 CloudWatch Logs 中应该看到：
```
✓ Pulling tool container image...
✓ Successfully pulled quay.io/biocontainers/fastqc:...
✓ Running tool container...
✓ Tool execution completed
✓ Uploading outputs to S3...
```

**不应该再看到：**
```
✗ Cannot connect to the Docker daemon at unix:///var/run/docker.sock
```

### 4. 监控 AWS Batch
```bash
# 查看任务状态
aws batch list-jobs \
    --job-queue galaxy-cloud-queue \
    --region us-west-2 \
    --job-status RUNNING

# 查看作业定义（验证 volumes 和 mountPoints）
aws batch describe-job-definitions \
    --job-definition-name galaxy-cloud-executor-<hash> \
    --region us-west-2
```

## 相关配置

### EC2 Launch Template
用户数据脚本配置 Docker socket 权限：
```bash
#!/bin/bash
chmod 666 /var/run/docker.sock
groupadd -f docker
```

### 计算环境
- **名称**: `galaxy-cloud-compute-ec2-dind-v2`
- **类型**: EC2 (支持 host volume 挂载)
- **状态**: ENABLED & VALID

### 作业队列
- **队列名称**: `galaxy-cloud-queue`
- **关联计算环境**: `galaxy-cloud-compute-ec2-dind-v2`

## 故障排查

### 如果仍然出现 "Cannot connect to Docker daemon" 错误

1. **检查作业定义是否包含 volumes 和 mountPoints**：
   ```bash
   aws batch describe-job-definitions \
       --job-definition-name <your-job-def> \
       --region us-west-2 \
       --query 'jobDefinitions[0].containerProperties.{volumes:volumes,mountPoints:mountPoints}'
   ```

   应该看到：
   ```json
   {
       "volumes": [
           {
               "name": "docker_socket",
               "host": {
                   "sourcePath": "/var/run/docker.sock"
               }
           }
       ],
       "mountPoints": [
           {
               "sourceVolume": "docker_socket",
               "containerPath": "/var/run/docker.sock",
               "readOnly": false
           }
       ]
   }
   ```

2. **检查 EC2 实例的 Docker socket 权限**：
   SSH 到 EC2 实例：
   ```bash
   ls -l /var/run/docker.sock
   # 应该显示: srw-rw-rw- 1 root docker
   ```

3. **检查容器是否注册到 ECS**：
   ```bash
   aws ecs list-container-instances \
       --cluster <cluster-arn> \
       --region us-west-2
   ```

   应该看到至少一个容器实例。

### 如果作业定义没有包含 volumes

可能原因：
- Galaxy 缓存了旧的 executor 实例
- 代码没有正确重新加载

解决方案：
```bash
# 完全停止 Galaxy
pkill -f "python.*run.py"
pkill -f "celery.*worker"

# 清除 Python 缓存
find lib/galaxy/galaxy-cloud-executor -name "*.pyc" -delete
find lib/galaxy/galaxy-cloud-executor -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true

# 重新启动
sh start_galaxy_with_ai.sh
```

## 时间线

- **20:58** - 任务提交到 AWS Batch
- **21:38** - 创建新的计算环境（v2）
- **21:42** - EC2 实例启动并注册到 ECS
- **21:45** - 任务开始执行，发现 Docker socket 错误
- **22:XX** - 修复代码，添加 Docker socket 挂载
- **待测试** - 重启 Galaxy，验证修复

## 修复验证清单

- [x] 修改 `_build_mount_points` 添加 Docker socket 挂载
- [x] 修改 `_build_volumes` 添加 host volume 定义
- [x] 重启 Galaxy 加载新代码
- [ ] 提交测试任务
- [ ] 验证任务成功执行
- [ ] 检查 CloudWatch 日志确认 Docker 连接成功
- [ ] 验证工具容器成功拉取和运行
- [ ] 确认输出文件上传到 S3

## 预期结果

修复后，fetch-and-run 容器能够：
1. ✓ 通过 `/var/run/docker.sock` 连接到宿主机 Docker daemon
2. ✓ 成功拉取工具容器镜像（如 `quay.io/biocontainers/fastqc:latest`）
3. ✓ 在宿主机上运行工具容器
4. ✓ 收集输出并上传到 S3
5. ✓ Galaxy 任务状态变为 "ok"

## 相关文档

- [DOCKER_IN_DOCKER_SETUP.md](DOCKER_IN_DOCKER_SETUP.md) - 完整的 Docker-in-Docker 配置文档
- [AWS Batch User Guide - Using Docker-in-Docker](https://docs.aws.amazon.com/batch/latest/userguide/docker-in-docker.html)
- [AWS Batch Volume Mounts](https://docs.aws.amazon.com/batch/latest/userguide/job_definition_parameters.html#containerProperties)
