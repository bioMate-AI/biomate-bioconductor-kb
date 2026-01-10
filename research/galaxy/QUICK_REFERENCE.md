# Galaxy Cloud Executor - 快速参考

## 添加新工具到云端执行

### 方法 1: 使用 BioContainers 镜像（最简单）

1. **搜索镜像**:
   ```bash
   curl "https://biocontainers.pro/api/ga4gh/trs/v2/tools?name=工具名"
   ```

2. **添加到配置**:
   ```yaml
   # config/tool_containers.yaml
   tools:
     "toolshed.g2.bx.psu.edu/repos/owner/toolname/toolname/version":
       image: "quay.io/biocontainers/toolname"
       tag: "版本标签"
   ```

3. **重启 Galaxy**:
   ```bash
   pkill -f "python.*run.py" && sh start_galaxy_with_ai.sh
   ```

### 方法 2: 从 Conda 包构建镜像

```bash
# 构建单个工具
./scripts/build_conda_tool_image.sh 工具名 "conda包=版本" 版本

# 例如
./scripts/build_conda_tool_image.sh trimmomatic "trimmomatic=0.39" 0.39

# 批量构建常用工具
./scripts/build_common_tools.sh
```

## 常用命令

### Galaxy 管理
```bash
# 启动
sh start_galaxy_with_ai.sh

# 停止
pkill -f "python.*run.py"

# 重启
pkill -f "python.*run.py" && sh start_galaxy_with_ai.sh

# 查看日志
tail -f logs/galaxy_startup_*.log
```

### AWS Batch 监控
```bash
# 查看任务状态
aws batch list-jobs \
    --job-queue galaxy-cloud-queue \
    --region us-west-2 \
    --job-status RUNNING

# 查看任务详情
aws batch describe-jobs --jobs <JOB_ID> --region us-west-2

# 查看日志
aws logs get-log-events \
    --log-group-name /aws/batch/job \
    --log-stream-name <STREAM_NAME> \
    --region us-west-2
```

### ECR 管理
```bash
# 列出镜像
aws ecr list-images \
    --repository-name galaxy-tools \
    --region us-west-2

# 删除旧镜像
aws ecr batch-delete-image \
    --repository-name galaxy-tools \
    --image-ids imageTag=old-version \
    --region us-west-2
```

## 故障排查

### 问题: 任务停留在 RUNNABLE 状态
**原因**: EC2 实例未启动或未注册到 ECS

**解决**:
```bash
# 检查计算环境
aws batch describe-compute-environments \
    --compute-environments galaxy-cloud-compute-ec2-dind-v2 \
    --region us-west-2

# 检查 ECS 容器实例
aws ecs list-container-instances \
    --cluster <CLUSTER_ARN> \
    --region us-west-2
```

### 问题: manifest not found
**原因**: 容器镜像不存在或标签错误

**解决**:
1. 检查 `config/tool_containers.yaml` 中的镜像标签
2. 验证镜像存在:
   ```bash
   docker manifest inspect quay.io/biocontainers/toolname:tag
   ```

### 问题: Cannot connect to Docker daemon
**原因**: Docker socket 未挂载

**解决**: 已修复 - 代码会自动为 fetch-and-run 容器添加 Docker socket 挂载

### 问题: 403 Forbidden (S3)
**原因**: IAM 角色配置错误

**解决**: 检查 `config/job_conf_cloud.yml` 中的 IAM 角色配置

## 配置文件位置

```
galaxy/
├── config/
│   ├── job_conf_cloud.yml        # 作业配置（主配置）
│   ├── tool_containers.yaml      # 工具容器映射
│   └── aws_cloud_config.yaml     # AWS 云配置
├── scripts/
│   ├── build_conda_tool_image.sh # 构建单个工具镜像
│   └── build_common_tools.sh     # 批量构建工具镜像
└── logs/
    └── galaxy_startup_*.log      # Galaxy 启动日志
```

## 重要文档

- [COMPLETE_FIX_SUMMARY.md](COMPLETE_FIX_SUMMARY.md) - 完整修复总结
- [CONDA_TO_DOCKER_GUIDE.md](CONDA_TO_DOCKER_GUIDE.md) - Conda 工具容器化指南
- [DOCKER_IN_DOCKER_SETUP.md](DOCKER_IN_DOCKER_SETUP.md) - Docker-in-Docker 配置
- [CONTAINER_TAG_FIX.md](CONTAINER_TAG_FIX.md) - 容器标签修复
- [DOCKER_SOCKET_FIX.md](DOCKER_SOCKET_FIX.md) - Docker socket 挂载修复

## 容器发现优先级

```
1. Static Mappings (config/tool_containers.yaml)  ← 最高优先级
   ↓ 未找到
2. Tool XML Declaration
   ↓ 未声明
3. BioContainers API
   ↓ API 失败
4. Pattern Matching (Fallback)                    ← 最低优先级
```

## AWS 资源

- **Region**: us-west-2
- **Job Queue**: galaxy-cloud-queue
- **Compute Environment**: galaxy-cloud-compute-ec2-dind-v2
- **S3 Bucket**: galaxy-cloud-data-1760241377
- **ECR Registry**: 399683337364.dkr.ecr.us-west-2.amazonaws.com
- **IAM Roles**:
  - BatchJobRole (容器运行权限)
  - ecsTaskExecutionRole (ECS 启动容器权限)
  - ecsInstanceRole (EC2 实例权限)

## 测试工作流

1. **本地测试** (可选):
   ```bash
   docker run --rm -it \
       399683337364.dkr.ecr.us-west-2.amazonaws.com/galaxy-tools/fastqc:0.12.1 \
       fastqc --version
   ```

2. **提交测试任务**:
   - 打开 Galaxy Web UI
   - 上传测试数据
   - 运行工具（如 FastQC）

3. **监控执行**:
   ```bash
   # 查看 Galaxy 日志
   tail -f logs/galaxy_startup_*.log | grep -E "Will use tool|Submitted job"

   # 查看 AWS Batch
   aws batch list-jobs --job-queue galaxy-cloud-queue --region us-west-2
   ```

4. **验证结果**:
   - 检查 Galaxy 任务状态 → "ok"
   - 下载输出文件
   - 验证结果正确性

## 常见工具的容器标签

| 工具 | BioContainers 标签 | ECR 标签 (自建) |
|------|-------------------|----------------|
| FastQC | `0.12.1--hdfd78af_0` | `0.12.1` |
| Trimmomatic | `0.38--hdfd78af_1` | `0.39` |
| Bowtie2 | `2.5.0--py39h3321a2d_0` | `2.5.0` |
| SAMtools | `1.15.1--h1170115_0` | `1.17` |
| MultiQC | `1.14--pyhdfd78af_0` | `1.14` |

## 性能优化

### 减少启动时间
1. **使用 ECR 而非 Quay.io** - 更快的镜像拉取
2. **预热镜像** - 在 EC2 实例上预先拉取常用镜像
3. **优化镜像大小** - 使用多阶段构建

### 减少成本
1. **使用 Spot 实例** - 节省 70% 计算成本
2. **设置超时** - 避免僵尸任务
3. **清理旧镜像** - 减少 ECR 存储成本

### 提高可靠性
1. **设置重试策略** - Spot 实例中断时自动重试
2. **版本锁定** - 确保结果可重现
3. **监控告警** - CloudWatch 告警异常任务
