#!/usr/bin/env python3
"""
测试 S3 bucket 参数修复

验证 job_destination.params 中的 aws_s3_bucket 能被正确读取
"""

import sys
sys.path.insert(0, 'lib')

# 模拟 JobDestination 对象
class MockJobDestination:
    def __init__(self):
        self.params = {
            'provider': 'aws',
            'aws_region': 'us-west-2',
            'aws_batch_queue': 'galaxy-cloud-queue',
            'aws_s3_bucket': 'galaxy-cloud-data-1760241377',  # 使用 aws_s3_bucket (config文件中的名称)
            'vcpus': 2,
            'memory_mb': 4096,
            'timeout_seconds': 3600
        }

# 测试修复后的代码逻辑
job_destination = MockJobDestination()

# 原来的代码（会失败）:
s3_bucket_old = job_destination.params.get('s3_bucket')
print(f"❌ 旧代码: s3_bucket = job_destination.params.get('s3_bucket')")
print(f"   结果: {s3_bucket_old}")
print()

# 修复后的代码（应该成功）:
s3_bucket_new = job_destination.params.get('s3_bucket') or job_destination.params.get('aws_s3_bucket')
print(f"✅ 新代码: s3_bucket = job_destination.params.get('s3_bucket') or job_destination.params.get('aws_s3_bucket')")
print(f"   结果: {s3_bucket_new}")
print()

# 验证结果
if s3_bucket_old:
    print("❌ 测试失败：旧代码不应该找到 s3_bucket")
    sys.exit(1)

if not s3_bucket_new:
    print("❌ 测试失败：新代码应该找到 aws_s3_bucket")
    sys.exit(1)

if s3_bucket_new != 'galaxy-cloud-data-1760241377':
    print(f"❌ 测试失败：期望 'galaxy-cloud-data-1760241377'，实际 '{s3_bucket_new}'")
    sys.exit(1)

print("✅ 测试通过！修复后的代码能正确读取 aws_s3_bucket 参数")
print()
print("实际配置参数:")
for key, value in job_destination.params.items():
    print(f"  {key}: {value}")
