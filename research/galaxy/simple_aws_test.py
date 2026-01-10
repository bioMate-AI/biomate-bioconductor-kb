#!/usr/bin/env python3
"""
简单的AWS连接测试
"""

import boto3
import os
from botocore.exceptions import NoCredentialsError, ClientError

def check_aws():
    """检查AWS连接"""
    print("🔍 检查AWS连接状态...")

    try:
        # 检查凭证
        sts = boto3.client('sts')
        identity = sts.get_caller_identity()
        print(f"✅ AWS凭证有效")
        print(f"   账户: {identity['Account']}")
        print(f"   用户: {identity['Arn'].split('/')[-1]}")

        # 检查区域
        region = boto3.Session().region_name or 'us-east-1'
        print(f"   区域: {region}")

        return True

    except NoCredentialsError:
        print("❌ 未找到AWS凭证")
        print("💡 解决方法:")
        print("   1. 运行: aws configure")
        print("   2. 或设置环境变量:")
        print("      export AWS_ACCESS_KEY_ID=your_key")
        print("      export AWS_SECRET_ACCESS_KEY=your_secret")
        return False

    except ClientError as e:
        print(f"❌ AWS凭证无效: {e}")
        return False

def quick_s3_test():
    """快速S3测试"""
    print("\n📦 快速S3测试...")

    try:
        s3 = boto3.client('s3')
        buckets = s3.list_buckets()

        print(f"✅ S3访问正常，发现{len(buckets['Buckets'])}个存储桶")

        # 显示前3个存储桶
        for bucket in buckets['Buckets'][:3]:
            print(f"   - {bucket['Name']}")

        return buckets['Buckets'][0]['Name'] if buckets['Buckets'] else None

    except Exception as e:
        print(f"❌ S3访问失败: {e}")
        return None

def main():
    print("☁️ AWS快速连接测试\n")

    if check_aws():
        bucket = quick_s3_test()

        print(f"\n🎯 下一步:")
        if bucket:
            print(f"   export AWS_S3_BUCKET={bucket}")
            print("   export AWS_BATCH_QUEUE=your-queue-name  # 如果有的话")
            print("   然后运行: python test_galaxy_cloud_executor.py")
        else:
            print("   创建一个S3存储桶用于测试")
            print("   aws s3 mb s3://galaxy-cloud-test-bucket")

if __name__ == '__main__':
    main()