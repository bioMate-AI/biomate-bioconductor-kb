# Galaxy Cloud Execution - 当前状态总结

## ✅ 已完成的修复

### 1. Docker镜像标签问题
- **问题**: 镜像标签不存在导致502 Bad Gateway
- **修复**: 更新 `config/tool_containers.json` 使用验证过的标签
  - fastqc: `0.11.9--0`
  - trimmomatic: `0.38--0`
- **状态**: ✅ 已解决

### 2. JobWrapper.job属性错误
- **问题**: `'JobWrapper' object has no attribute 'job'`
- **修复**: 使用 `Job.states.OK` 替代 `job_wrapper.job.states.OK`
- **文件**: `lib/galaxy_cloud/galaxy_workflow/galaxy_job_runner.py:470`
- **状态**: ✅ 已解决

### 3. 命令行为空问题
- **问题**: `runner_command_line` 和 `command_line` 都是 None
- **修复**: 主动调用 `job_wrapper.prepare()` 生成命令
- **文件**: `lib/galaxy_cloud/galaxy_workflow/galaxy_job_runner.py:318-327`
- **状态**: ✅ 已解决

### 4. Shell命令解析问题
- **问题**: Galaxy命令包含 `&&`、`if`、管道等shell结构
- **修复**: 使用 `["/bin/sh", "-c", command_line]` 包装完整命令
- **文件**: `lib/galaxy_cloud/galaxy_workflow/galaxy_job_runner.py:330-334`
- **状态**: ✅ 已解决

### 5. AWS认证问题
- **问题**: 初始时 AWS credentials 无效
- **修复**: 用户重新认证 AWS
- **状态**: ✅ 已解决

## ❌ 当前核心问题：文件路径问题

### 问题描述

Galaxy生成的命令使用**本地文件系统路径**：

```bash
ln -s '/Users/renyuankai/work/biometa/galaxy/database/objects/5/e/0/dataset_5e0bc902-6575-4117-bbc6-47d200745b35.dat' 'sample_reads_fastq_gz.gz' && \
mkdir -p '/Users/renyuankai/work/biometa/galaxy/database/objects/e/0/8/dataset_e0873ccc-aaf7-4ae2-b499-673a35e5eeab_files' && \
fastqc --outdir '/Users/renyuankai/work/biometa/galaxy/database/objects/e/0/8/dataset_e0873ccc-aaf7-4ae2-b499-673a35e5eeab_files' ...
```

但这些路径在AWS Batch容器中**不存在**，导致：
- 容器启动成功 ✅
- 命令开始执行 ✅
- 文件不存在，命令失败 ❌
- 容器立即退出（0秒运行时间）❌

### 根本原因

缺少**云数据管理层**，需要：

1. **输入阶段**:
   - 上传输入文件到S3
   - 获取S3 URI
   - 修改命令中的本地路径为容器内路径

2. **执行阶段**:
   - 容器启动时从S3下载输入文件
   - 执行工具
   - 将输出文件上传到S3

3. **输出阶段**:
   - 从S3下载输出文件到本地
   - 更新Galaxy数据库

## 🔧 需要实现的功能

### 选项A：完整的云数据管理（推荐，但工作量大）

实现一个数据管理层处理文件传输：

```python
class CloudDataManager:
    def upload_inputs(self, job_wrapper) -> Dict[str, str]:
        """上传输入文件到S3，返回文件映射"""
        pass

    def rewrite_command(self, command: str, file_mapping: Dict) -> str:
        """重写命令中的文件路径"""
        pass

    def download_outputs(self, job_wrapper, s3_paths: List[str]):
        """从S3下载输出文件到本地"""
        pass
```

### 选项B：使用Galaxy的对象存储（可能更简单）

如果Galaxy已经配置了S3作为对象存储，那么：
- 数据已经在S3上
- 只需要挂载或下载到容器

检查Galaxy配置：
```yaml
# config/galaxy.yml
object_store_config_file: config/object_store_conf.yml
```

### 选项C：本地执行模拟（临时测试）

在AWS Batch任务定义中添加卷挂载：
- 挂载EFS（Elastic File System）
- 将Galaxy数据目录同步到EFS
- 容器可以访问相同的文件路径

## 📊 当前日志分析

最新执行日志显示：

```
Job 91 command_line after prepare: ln -s '/Users/renyuankai/work/biometa/galaxy/database/objects/5/e/0/dataset_5e0bc902-6575-4117-bbc6-47d200745b35.dat' ...
Job 91 wrapping command in shell: ln -s '/Users/renyuankai/work/biometa/galaxy/database/objects/5/e/0/dataset_5e0bc902-6575-4117-bbc6-47d200745b35.dat' ...
Submitted job galaxy-91 to AWS Batch with ID 10cb045b-84a5-421f-91bb-1b57bd465b68
```

✅ 命令生成成功
✅ 命令包装成功
✅ 任务提交成功
❌ 文件路径不存在

## 🔍 诊断工具

使用提供的脚本查看AWS任务详情：

```bash
# 查看最近的任务
./check_aws_job.sh

# 查看特定任务
./check_aws_job.sh 10cb045b-84a5-421f-91bb-1b57bd465b68
```

关键查看：
1. **container.command**: 实际执行的命令
2. **container.exitCode**: 退出码（非0表示失败）
3. **CloudWatch logs**: 容器内的错误消息

## 📝 下一步建议

### 短期（测试）
1. 查看AWS CloudWatch日志确认文件路径错误
2. 创建一个简单的测试工具（不需要输入文件）
3. 验证容器执行和结果收集流程

### 中期（实现）
1. 实现输入文件S3上传
2. 实现命令路径重写
3. 实现输出文件S3下载
4. 测试完整流程

### 长期（优化）
1. 支持大文件流式传输
2. 实现增量同步
3. 添加缓存机制
4. 支持多区域部署

## 📂 相关文件

- 配置: `config/tool_containers.json`
- 主代码: `lib/galaxy_cloud/galaxy_workflow/galaxy_job_runner.py`
- AWS执行器: `lib/galaxy_cloud/providers/aws/executor.py`
- 诊断脚本: `check_aws_job.sh`

## 🎯 成功标准

真正的成功需要：
- ✅ 任务提交到AWS Batch
- ✅ 容器成功启动
- ✅ 输入文件可访问
- ✅ 工具成功执行
- ✅ 输出文件生成
- ✅ 输出文件下载回本地
- ✅ Galaxy显示正确结果

当前进度：前2项已完成，第3项需要实现。
