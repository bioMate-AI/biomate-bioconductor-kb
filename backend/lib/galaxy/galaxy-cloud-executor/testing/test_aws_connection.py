#!/usr/bin/env python3
"""
AWS 连接测试工具

测试 AWS 凭证、Batch 队列、S3 存储桶等基础设施的连接状态。

用法:
    python3 test_aws_connection.py

环境变量:
    AWS_DEFAULT_REGION - AWS 区域（默认: us-west-2）
    AWS_BATCH_QUEUE - Batch 队列名称（可选）
    AWS_S3_BUCKET - S3 存储桶名称（可选）
"""

import os
import sys
import boto3
from datetime import datetime

# ============================================================================
# 配置
# ============================================================================

REGION = os.environ.get('AWS_DEFAULT_REGION', 'us-west-2')
BATCH_QUEUE = os.environ.get('AWS_BATCH_QUEUE', 'galaxy-cloud-queue')
S3_BUCKET = os.environ.get('AWS_S3_BUCKET', 'galaxy-cloud-data-1760241377')
AWS_PROFILE = os.environ.get('AWS_PROFILE')

# 创建会话，如果有profile则使用
if AWS_PROFILE:
    session = boto3.Session(profile_name=AWS_PROFILE)
    print(f"使用 AWS Profile: {AWS_PROFILE}")
else:
    session = boto3.Session()
    print("使用默认 AWS 凭证")

# ============================================================================
# 测试函数
# ============================================================================

def print_header(title):
    """打印测试标题"""
    print(f"\n{'='*80}")
    print(f"  {title}")
    print(f"{'='*80}\n")


def print_result(test_name, passed, message=""):
    """打印测试结果"""
    status = "✅ PASS" if passed else "❌ FAIL"
    print(f"{status}: {test_name}")
    if message:
        print(f"       {message}")


def test_aws_credentials():
    """测试 AWS 凭证"""
    print_header("测试 1: AWS 凭证")

    try:
        sts = session.client('sts', region_name=REGION)
        identity = sts.get_caller_identity()

        account_id = identity['Account']
        arn = identity['Arn']

        print_result("AWS 凭证有效", True, f"Account: {account_id}")
        print(f"       ARN: {arn}")
        return True
    except Exception as e:
        print_result("AWS 凭证有效", False, str(e))
        return False


def test_batch_connection():
    """测试 AWS Batch 连接"""
    print_header("测试 2: AWS Batch 连接")

    try:
        batch = session.client('batch', region_name=REGION)

        # 测试 API 调用
        response = batch.describe_compute_environments(maxResults=1)

        print_result("Batch API 连接", True, "可以调用 Batch API")

        # 检查队列
        if BATCH_QUEUE:
            try:
                queues = batch.describe_job_queues(jobQueues=[BATCH_QUEUE])
                if queues['jobQueues']:
                    queue = queues['jobQueues'][0]
                    state = queue['state']
                    status = queue['status']
                    print_result(f"Batch 队列: {BATCH_QUEUE}", True,
                               f"状态: {state}, Status: {status}")
                else:
                    print_result(f"Batch 队列: {BATCH_QUEUE}", False, "队列不存在")
            except Exception as e:
                print_result(f"Batch 队列: {BATCH_QUEUE}", False, str(e))

        return True
    except Exception as e:
        print_result("Batch API 连接", False, str(e))
        return False


def test_s3_connection():
    """测试 S3 连接"""
    print_header("测试 3: S3 连接")

    try:
        s3 = session.client('s3', region_name=REGION)

        # 测试 API 调用
        s3.list_buckets()
        print_result("S3 API 连接", True, "可以调用 S3 API")

        # 检查存储桶
        if S3_BUCKET:
            try:
                s3.head_bucket(Bucket=S3_BUCKET)
                print_result(f"S3 存储桶: {S3_BUCKET}", True, "存储桶可访问")

                # 测试写入权限
                test_key = f"connection-test-{datetime.now().strftime('%Y%m%d%H%M%S')}.txt"
                s3.put_object(
                    Bucket=S3_BUCKET,
                    Key=test_key,
                    Body=b"AWS connection test"
                )
                print_result(f"S3 写入权限", True, f"成功写入: {test_key}")

                # 清理测试文件
                s3.delete_object(Bucket=S3_BUCKET, Key=test_key)
                print_result(f"S3 删除权限", True, f"成功删除: {test_key}")

            except Exception as e:
                print_result(f"S3 存储桶: {S3_BUCKET}", False, str(e))

        return True
    except Exception as e:
        print_result("S3 API 连接", False, str(e))
        return False


def test_cloudwatch_logs():
    """测试 CloudWatch Logs 连接"""
    print_header("测试 4: CloudWatch Logs 连接")

    try:
        logs = session.client('logs', region_name=REGION)

        # 测试 API 调用
        logs.describe_log_groups(limit=1)
        print_result("CloudWatch Logs API 连接", True, "可以调用 Logs API")

        # 检查 Batch 日志组
        log_group = "/aws/batch/job"
        try:
            response = logs.describe_log_groups(logGroupNamePrefix=log_group)
            if response['logGroups']:
                print_result(f"日志组: {log_group}", True, "日志组存在")
            else:
                print_result(f"日志组: {log_group}", False, "日志组不存在（首次作业时自动创建）")
        except Exception as e:
            print_result(f"日志组: {log_group}", False, str(e))

        return True
    except Exception as e:
        print_result("CloudWatch Logs API 连接", False, str(e))
        return False


def test_iam_roles():
    """测试 IAM 角色"""
    print_header("测试 5: IAM 角色")

    try:
        iam = session.client('iam', region_name=REGION)

        # 检查关键角色
        roles_to_check = [
            'ecsInstanceRole',
            'BatchJobRole',
            'AWSBatchServiceRole'
        ]

        all_passed = True
        for role_name in roles_to_check:
            try:
                role = iam.get_role(RoleName=role_name)
                arn = role['Role']['Arn']
                print_result(f"IAM 角色: {role_name}", True, f"ARN: {arn}")
            except iam.exceptions.NoSuchEntityException:
                print_result(f"IAM 角色: {role_name}", False, "角色不存在")
                all_passed = False
            except Exception as e:
                print_result(f"IAM 角色: {role_name}", False, str(e))
                all_passed = False

        return all_passed
    except Exception as e:
        print_result("IAM API 连接", False, str(e))
        return False


# ============================================================================
# 主程序
# ============================================================================

def main():
    """主测试流程"""
    print("\n" + "="*80)
    print("  AWS 连接测试")
    print("="*80)
    print(f"\n配置:")
    print(f"  区域: {REGION}")
    print(f"  Batch 队列: {BATCH_QUEUE}")
    print(f"  S3 存储桶: {S3_BUCKET}")

    # 运行所有测试
    results = {
        'AWS 凭证': test_aws_credentials(),
        'AWS Batch': test_batch_connection(),
        'S3 存储': test_s3_connection(),
        'CloudWatch Logs': test_cloudwatch_logs(),
        'IAM 角色': test_iam_roles(),
    }

    # 汇总结果
    print_header("测试汇总")

    passed = sum(1 for v in results.values() if v)
    total = len(results)

    for test_name, result in results.items():
        status = "✅" if result else "❌"
        print(f"{status} {test_name}")

    print(f"\n通过率: {passed}/{total} ({passed/total*100:.0f}%)")

    if passed == total:
        print("\n🎉 所有测试通过！AWS 连接正常。")
        return 0
    else:
        print(f"\n⚠️  {total - passed} 个测试失败，请检查配置。")
        return 1


if __name__ == '__main__':
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\n\n⚠️  用户中断")
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ 测试失败: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
