#!/usr/bin/env python3
"""
AWS连接测试脚本
测试AWS凭证和基础服务连接
"""

import boto3
from botocore.exceptions import ClientError, NoCredentialsError
import os


def test_aws_credentials():
    """测试AWS凭证"""
    print("🔐 测试AWS凭证...")

    try:
        # 创建STS客户端来验证凭证
        sts = boto3.client('sts')
        identity = sts.get_caller_identity()

        print(f"✅ AWS凭证有效")
        print(f"   账户ID: {identity['Account']}")
        print(f"   用户ARN: {identity['Arn']}")
        print(f"   用户ID: {identity['UserId']}")
        return True

    except NoCredentialsError:
        print("❌ 未找到AWS凭证")
        print("💡 请配置AWS凭证:")
        print("   方法1: aws configure")
        print("   方法2: 设置环境变量 AWS_ACCESS_KEY_ID 和 AWS_SECRET_ACCESS_KEY")
        return False

    except ClientError as e:
        print(f"❌ AWS凭证无效: {e}")
        return False


def test_batch_access():
    """测试AWS Batch访问权限"""
    print("\n📋 测试AWS Batch访问权限...")

    try:
        batch = boto3.client('batch')

        # 列出作业队列
        response = batch.describe_job_queues()
        queues = response.get('jobQueues', [])

        print(f"✅ AWS Batch访问正常")
        print(f"   发现 {len(queues)} 个作业队列:")

        for queue in queues[:5]:  # 只显示前5个
            print(f"     - {queue['jobQueueName']} ({queue['state']})")

        if queues:
            return queues[0]['jobQueueName']  # 返回第一个队列名
        else:
            print("⚠️ 未找到作业队列，需要创建一个")
            return None

    except ClientError as e:
        error_code = e.response['Error']['Code']
        if error_code == 'AccessDenied':
            print("❌ 没有AWS Batch访问权限")
            print("💡 需要以下IAM权限:")
            print("   - batch:DescribeJobQueues")
            print("   - batch:DescribeComputeEnvironments")
        else:
            print(f"❌ AWS Batch访问错误: {e}")
        return None


def test_s3_access():
    """测试S3访问权限"""
    print("\n🗄️ 测试S3访问权限...")

    try:
        s3 = boto3.client('s3')

        # 列出存储桶
        response = s3.list_buckets()
        buckets = response.get('Buckets', [])

        print(f"✅ S3访问正常")
        print(f"   发现 {len(buckets)} 个存储桶:")

        for bucket in buckets[:5]:  # 只显示前5个
            print(f"     - {bucket['Name']}")

        if buckets:
            return buckets[0]['Name']  # 返回第一个存储桶名
        else:
            print("⚠️ 未找到存储桶，建议创建一个用于测试")
            return None

    except ClientError as e:
        error_code = e.response['Error']['Code']
        if error_code == 'AccessDenied':
            print("❌ 没有S3访问权限")
            print("💡 需要以下IAM权限:")
            print("   - s3:ListAllMyBuckets")
        else:
            print(f"❌ S3访问错误: {e}")
        return None


def test_create_minimal_resources():
    """创建最小的测试资源"""
    print("\n🛠️ 创建最小测试资源...")

    region = os.getenv('AWS_DEFAULT_REGION', 'us-east-1')

    try:
        # 创建S3存储桶用于测试
        s3 = boto3.client('s3', region_name=region)
        bucket_name = f"galaxy-cloud-test-{boto3.Session().get_credentials().access_key[-6:].lower()}"

        try:
            if region == 'us-east-1':
                s3.create_bucket(Bucket=bucket_name)
            else:
                s3.create_bucket(
                    Bucket=bucket_name,
                    CreateBucketConfiguration={'LocationConstraint': region}
                )
            print(f"✅ 创建测试存储桶: {bucket_name}")

            # 设置环境变量
            os.environ['AWS_S3_BUCKET'] = bucket_name

        except ClientError as e:
            if e.response['Error']['Code'] == 'BucketAlreadyExists':
                print(f"⚠️ 存储桶 {bucket_name} 已存在")
                os.environ['AWS_S3_BUCKET'] = bucket_name
            else:
                print(f"❌ 创建存储桶失败: {e}")
                return False

        print("\n💡 请注意:")
        print(f"   设置环境变量: export AWS_S3_BUCKET={bucket_name}")
        print("   如果要测试AWS Batch，还需要创建Batch队列")

        return True

    except Exception as e:
        print(f"❌ 创建资源失败: {e}")
        return False


def main():
    """主测试函数"""
    print("☁️ AWS连接测试开始\n")
    print("=" * 50)

    # 1. 测试凭证
    if not test_aws_credentials():
        return

    # 2. 测试Batch
    queue_name = test_batch_access()
    if queue_name:
        os.environ['AWS_BATCH_QUEUE'] = queue_name
        print(f"💡 设置环境变量: export AWS_BATCH_QUEUE={queue_name}")

    # 3. 测试S3
    bucket_name = test_s3_access()
    if bucket_name:
        os.environ['AWS_S3_BUCKET'] = bucket_name
        print(f"💡 设置环境变量: export AWS_S3_BUCKET={bucket_name}")

    # 4. 如果没有资源，提供创建建议
    if not queue_name and not bucket_name:
        print("\n🚀 资源创建建议:")
        print("1. 创建S3存储桶用于测试")
        create_resources = input("是否创建最小测试资源? (y/N): ").lower().strip()

        if create_resources == 'y':
            test_create_minimal_resources()

    print("\n" + "=" * 50)
    print("✅ AWS连接测试完成！")

    # 给出下一步建议
    print("\n🎯 下一步:")
    if queue_name and bucket_name:
        print("✅ 可以运行完整的AWS测试:")
        print("   python test_galaxy_cloud_executor_fixed.py")
    elif bucket_name:
        print("⚠️ 只有S3可用，建议创建AWS Batch队列")
        print("   参考: cloud_setup_guide.md")
    else:
        print("⚠️ 需要创建AWS资源才能进行云端测试")
        print("   参考: cloud_setup_guide.md")


if __name__ == '__main__':
    main()