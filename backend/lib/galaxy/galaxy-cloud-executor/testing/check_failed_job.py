#!/usr/bin/env python3
"""
检查失败的AWS Batch作业详情和日志
"""

import boto3
import sys

if len(sys.argv) < 2:
    print("用法: python3 check_failed_job.py <job-id>")
    print("示例: python3 check_failed_job.py 5ee220c6-d466-4c8b-ba24-d4e631e597bc")
    sys.exit(1)

job_id = sys.argv[1]
region = 'us-west-2'

print(f"正在检查作业: {job_id}")
print("="*80)

batch = boto3.client('batch', region_name=region)
logs = boto3.client('logs', region_name=region)

# 获取作业详情
try:
    response = batch.describe_jobs(jobs=[job_id])
    if not response['jobs']:
        print(f"❌ 作业未找到: {job_id}")
        sys.exit(1)

    job = response['jobs'][0]

    print(f"\n作业基本信息:")
    print(f"  名称: {job['jobName']}")
    print(f"  状态: {job['status']}")
    print(f"  队列: {job['jobQueue']}")
    print(f"  定义: {job['jobDefinition']}")

    if 'statusReason' in job:
        print(f"  失败原因: {job['statusReason']}")

    print(f"\n容器配置:")
    container = job.get('container', {})
    print(f"  镜像: {container.get('image', 'N/A')}")
    print(f"  vCPUs: {container.get('vcpus', 'N/A')}")
    print(f"  内存: {container.get('memory', 'N/A')} MB")

    if 'command' in container:
        print(f"  命令: {' '.join(container['command'][:3])}...")

    if 'environment' in container:
        print(f"  环境变量:")
        for env in container['environment']:
            print(f"    {env['name']}={env['value']}")

    # 检查 Job Role
    if 'jobRoleArn' in container:
        print(f"  ✅ Job Role: {container['jobRoleArn']}")
    else:
        print(f"  ❌ Job Role: 未设置 (这可能是问题所在!)")

    # 检查执行尝试
    if 'attempts' in job and job['attempts']:
        print(f"\n执行尝试:")
        for i, attempt in enumerate(job['attempts']):
            print(f"\n  尝试 {i+1}:")
            print(f"    状态: {attempt.get('statusReason', 'N/A')}")

            if 'container' in attempt:
                att_container = attempt['container']
                print(f"    退出码: {att_container.get('exitCode', 'N/A')}")
                print(f"    原因: {att_container.get('reason', 'N/A')}")

                if 'logStreamName' in att_container:
                    log_stream = att_container['logStreamName']
                    print(f"    日志流: {log_stream}")

                    # 尝试获取日志
                    print(f"\n    CloudWatch 日志:")
                    try:
                        log_response = logs.get_log_events(
                            logGroupName='/aws/batch/job',
                            logStreamName=log_stream,
                            limit=50
                        )

                        events = log_response.get('events', [])
                        if events:
                            print(f"    " + "-"*70)
                            for event in events:
                                message = event['message'].rstrip()
                                print(f"    {message}")
                            print(f"    " + "-"*70)
                        else:
                            print(f"    (无日志输出)")
                    except Exception as e:
                        print(f"    ⚠️  无法获取日志: {e}")

    print(f"\n诊断建议:")

    if 'jobRoleArn' not in container:
        print(f"  ❌ 缺少 Job Role ARN!")
        print(f"     容器无法访问 S3")
        print(f"     解决方法: 设置环境变量 AWS_BATCH_JOB_ROLE_ARN")
        print(f"     export AWS_BATCH_JOB_ROLE_ARN='arn:aws:iam::399683337364:role/BatchJobRole'")

    if job.get('status') == 'FAILED':
        status_reason = job.get('statusReason', '')
        if 'Essential container in task exited' in status_reason:
            print(f"  ❌ 容器提前退出!")
            print(f"     可能原因:")
            print(f"     1. 缺少 Job Role 导致 S3 访问失败")
            print(f"     2. 命令语法错误")
            print(f"     3. 依赖的文件不存在")

except Exception as e:
    print(f"❌ 错误: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
