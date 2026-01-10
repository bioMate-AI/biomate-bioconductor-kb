#!/bin/bash
# Galaxy Cloud Executor - 生产部署脚本

set -e

echo "🚀 Galaxy Cloud Executor 生产部署"
echo "================================"

# 检查环境变量文件
if [ ! -f ".env.production" ]; then
    echo "❌ 缺少 .env.production 文件"
    echo "请复制 .env.production.template 为 .env.production 并填入实际值"
    exit 1
fi

# 加载环境变量
source .env.production

# 验证必需的环境变量
echo "🔍 验证环境变量..."
required_vars=(
    "AWS_ACCESS_KEY_ID"
    "AWS_SECRET_ACCESS_KEY" 
    "AWS_DEFAULT_REGION"
    "GALAXY_AWS_BATCH_QUEUE"
    "GALAXY_AWS_S3_BUCKET"
)

for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "❌ 缺少必需的环境变量: $var"
        exit 1
    fi
done

echo "✅ 环境变量验证通过"

# 测试AWS连接
echo "🔌 测试AWS连接..."
python3 -c "
import boto3
import os

try:
    # 测试基本连接
    session = boto3.Session()
    sts = session.client('sts', region_name=os.getenv('AWS_DEFAULT_REGION'))
    identity = sts.get_caller_identity()
    print(f'✅ AWS连接成功: {identity[\"Account\"]}')
    
    # 测试Batch访问
    batch = session.client('batch', region_name=os.getenv('AWS_DEFAULT_REGION'))
    queues = batch.describe_job_queues(jobQueues=[os.getenv('GALAXY_AWS_BATCH_QUEUE')])
    if queues['jobQueues']:
        print(f'✅ Batch队列访问正常: {os.getenv(\"GALAXY_AWS_BATCH_QUEUE\")}')
    else:
        print(f'❌ Batch队列不存在: {os.getenv(\"GALAXY_AWS_BATCH_QUEUE\")}')
        exit(1)
    
    # 测试S3访问
    s3 = session.client('s3', region_name=os.getenv('AWS_DEFAULT_REGION'))
    s3.head_bucket(Bucket=os.getenv('GALAXY_AWS_S3_BUCKET'))
    print(f'✅ S3存储桶访问正常: {os.getenv(\"GALAXY_AWS_S3_BUCKET\")}')
    
except Exception as e:
    print(f'❌ AWS连接失败: {e}')
    exit(1)
" || exit 1

# 测试配置加载
echo "⚙️  测试配置加载..."
python3 -c "
from galaxy_cloud.config import ConfigManager

try:
    config = ConfigManager('config/galaxy_cloud_config_production.yaml').load_config()
    print(f'✅ 配置加载成功')
    print(f'   默认提供商: {config.default_provider}')
    print(f'   AWS区域: {config.aws.region}')
    print(f'   监控端口: {config.monitoring.metrics_port}')
except Exception as e:
    print(f'❌ 配置加载失败: {e}')
    exit(1)
" || exit 1

echo ""
echo "🎉 生产环境部署验证完成！"
echo ""
echo "下一步："
echo "1. 启动服务: python3 -m galaxy_cloud.main --config config/galaxy_cloud_config_production.yaml"
echo "2. 监控日志: tail -f logs/galaxy-cloud.log"
echo "3. 检查指标: curl http://localhost:8080/metrics"
echo ""
echo "安全提醒："
echo "- 定期轮换AWS访问密钥"
echo "- 监控AWS用量和成本"
echo "- 检查IAM权限是否遵循最小权限原则"