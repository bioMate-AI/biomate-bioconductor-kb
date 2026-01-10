# Docker-in-Docker 配置完成总结

## 配置完成时间
2025-10-21

## 已完成的配置步骤

### 1. 创建 EC2 Launch Template
- **名称**: `galaxy-batch-dind-template`
- **功能**: 配置 Docker socket 权限，允许容器访问宿主机 Docker
- **用户数据脚本**:
  ```bash
  #!/bin/bash
  chmod 666 /var/run/docker.sock
  groupadd -f docker
  ```

### 2. 创建 EC2 计算环境
- **名称**: `galaxy-cloud-compute-ec2-dind`
- **类型**: EC2 (MANAGED)
- **状态**: ENABLED
- **验证状态**: VALID ✓
- **ARN**: `arn:aws:batch:us-west-2:399683337364:compute-environment/galaxy-cloud-compute-ec2-dind`
- **Launch Template**: `galaxy-batch-dind-template`
- **资源配置**:
  - minvCpus: 0
  - maxvCpus: 16
  - desiredvCpus: 0
  - instanceTypes: optimal
  - allocationStrategy: BEST_FIT_PROGRESSIVE

### 3. 更新作业队列
- **队列名称**: `galaxy-cloud-queue`
- **关联计算环境**: `galaxy-cloud-compute-ec2-dind`
- **状态**: 已成功更新 ✓

### 4. 更新 Galaxy 配置
- **配置文件**: `config/job_conf_cloud.yml`
- **修改内容**: 所有云执行环境 (cloud_small, cloud_medium, cloud_large) 均设置:
  ```yaml
  use_fetch_and_run: "true"
  ```

## Docker-in-Docker 工作原理

### Fetch-and-Run 模式
1. AWS Batch 启动 fetch-and-run 容器 (`399683337364.dkr.ecr.us-west-2.amazonaws.com/galaxy-fetch-and-run:latest`)
2. Fetch-and-run 容器内有 Docker CLI 客户端
3. 通过挂载宿主机 Docker socket (`/var/run/docker.sock`)，容器可以访问宿主机 Docker daemon
4. Fetch-and-run 容器拉取并运行实际的工具容器 (如 `quay.io/biocontainers/fastqc:...`)
5. 工具容器执行完成后，fetch-and-run 将结果上传到 S3

### 架构优势
- 支持任意 Docker 镜像 (biocontainers, custom images)
- 无需为每个工具创建 AWS Batch 作业定义
- 自动处理数据传输 (S3 ↔ 容器)
- 支持复杂的生物信息学工具链

## IAM 角色配置

### BatchJobRole
- **ARN**: `arn:aws:iam::399683337364:role/BatchJobRole`
- **用途**: 容器运行时的权限（访问 S3, ECR 等）
- **配置位置**: `job_conf_cloud.yml` 中的 `job_role_arn`

### ecsTaskExecutionRole
- **ARN**: `arn:aws:iam::399683337364:role/ecsTaskExecutionRole`
- **用途**: ECS 启动容器的权限（拉取镜像、写日志等）
- **配置位置**: `job_conf_cloud.yml` 中的 `execute_role_arn`

## 下一步测试步骤

### 1. 重启 Galaxy
```bash
# 停止当前运行的 Galaxy
pkill -f "python.*run.py"

# 重新启动
sh start_galaxy_with_ai.sh
```

### 2. 提交测试任务
- 使用 Galaxy Web UI 提交一个 FastQC 任务
- 任务将被路由到 `cloud_small` 环境
- AWS Batch 将在 EC2 实例上启动 fetch-and-run 容器
- Fetch-and-run 将拉取并运行 FastQC 容器

### 3. 监控任务执行
```bash
# 查看 AWS Batch 作业状态
aws batch list-jobs \
    --job-queue galaxy-cloud-queue \
    --region us-west-2 \
    --job-status RUNNING

# 获取作业 ID 后查看日志
aws batch describe-jobs \
    --jobs <JOB_ID> \
    --region us-west-2
```

### 4. 预期的成功标志
✓ Fetch-and-run 容器成功启动
✓ Docker 客户端连接到宿主机 Docker daemon
✓ 成功拉取工具容器 (如 `quay.io/biocontainers/fastqc:...`)
✓ 工具容器成功执行
✓ 输出文件成功上传到 S3
✓ Galaxy 任务状态变为 "ok"

## 关键文件位置

### AWS 配置脚本
- `configure_docker_in_docker.sh` - Launch Template 创建脚本
- `create_ec2_compute_env.sh` - EC2 计算环境创建脚本

### Galaxy 配置文件
- `config/job_conf_cloud.yml` - 作业配置（实际使用的配置文件）
- `config/aws_cloud_config.yaml` - AWS 云配置

### Docker 镜像
- `docker/fetch-and-run/Dockerfile` - Fetch-and-run 容器定义
- `docker/fetch-and-run/build_and_push.sh` - 镜像构建和推送脚本
- ECR 镜像: `399683337364.dkr.ecr.us-west-2.amazonaws.com/galaxy-fetch-and-run:latest`

## 故障排查

### 如果遇到 "Cannot connect to Docker daemon" 错误
1. 检查 EC2 Launch Template 用户数据是否正确执行
2. SSH 到 EC2 实例，验证 Docker socket 权限: `ls -l /var/run/docker.sock`
3. 应该显示: `srw-rw-rw- 1 root docker 0 ... /var/run/docker.sock`

### 如果遇到 403 Forbidden 错误
1. 检查 IAM 角色是否正确配置在 `job_conf_cloud.yml` 中
2. 验证 BatchJobRole 有 S3 访问权限
3. 验证 ecsTaskExecutionRole 有 ECR 和 CloudWatch Logs 权限

### 如果容器无法启动
1. 检查 EC2 计算环境状态: `aws batch describe-compute-environments`
2. 检查作业队列状态: `aws batch describe-job-queues`
3. 查看 CloudWatch Logs: `/aws/batch/job`

## 配置历史

### 解决的问题
1. ✓ Docker 镜像架构不匹配 (ARM64 vs x86_64)
2. ✓ 403 S3 访问错误 (IAM 角色配置)
3. ✓ 配置文件识别错误 (job_conf.yml vs job_conf_cloud.yml)
4. ✓ Boolean 参数解析错误
5. ✓ Docker-in-Docker 不支持 (Fargate → EC2)

### 当前状态
- AWS Batch 基础设施: ✓ 完成
- IAM 权限配置: ✓ 完成
- Docker-in-Docker 支持: ✓ 完成
- Galaxy 配置: ✓ 完成
- **待测试**: 端到端工作流执行

## 参考资源

- [AWS Batch 用户指南](https://docs.aws.amazon.com/batch/)
- [Docker-in-Docker 最佳实践](https://jpetazzo.github.io/2015/09/03/do-not-use-docker-in-docker-for-ci/)
- [Galaxy Cloud Executor 文档](lib/galaxy/galaxy-cloud-executor/README.md)
