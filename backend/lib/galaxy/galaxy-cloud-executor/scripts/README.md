# 辅助脚本目录

本目录包含Galaxy Cloud Executor的各种辅助脚本。

## 📁 目录结构

```
scripts/
├── README.md                    # 本文件
├── aws/                         # AWS相关辅助脚本
│   ├── check_logs.sh           # 查看AWS Batch作业日志
│   ├── refresh_credentials.sh  # 刷新AWS凭证
│   ├── setup_credentials.sh    # AWS凭证设置助手
│   └── test_config.sh          # 测试AWS配置
└── workflow/                    # Workflow执行脚本
    └── run_qiime2_cloud.sh     # QIIME2 workflow云执行脚本
```

## 🔧 AWS辅助脚本

### check_logs.sh
查看AWS Batch作业日志

**用法**:
```bash
./scripts/aws/check_logs.sh latest           # 查看最新作业
./scripts/aws/check_logs.sh <job-id>         # 查看特定作业
```

### refresh_credentials.sh
刷新AWS SSO凭证

**用法**:
```bash
./scripts/aws/refresh_credentials.sh
```

### setup_credentials.sh
AWS凭证设置助手（交互式）

**用法**:
```bash
./scripts/aws/setup_credentials.sh
```

### test_config.sh
测试AWS配置（Batch队列、S3、IAM角色等）

**用法**:
```bash
./scripts/aws/test_config.sh
```

## 🚀 Workflow执行脚本

### run_qiime2_cloud.sh
在AWS云上执行QIIME2 workflow

**用法**:
```bash
./scripts/workflow/run_qiime2_cloud.sh
```

**功能**:
- 自动检测Python环境
- 自动设置AWS环境变量
- 支持快速验证和完整监控两种模式
- 使用galaxy_cloud通用模块

## 📚 相关文档

- [快速开始指南](../full_docs/通用模块运行/01-快速开始.md)
- [问题排查](../full_docs/通用模块运行/03-问题排查.md)
- [脚本使用说明](../full_docs/通用模块运行/04-测试脚本说明.md)
