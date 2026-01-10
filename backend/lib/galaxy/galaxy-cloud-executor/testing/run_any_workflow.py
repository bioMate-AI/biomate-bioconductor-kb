#!/usr/bin/env python3
"""
通用 Galaxy Workflow 云执行工具

用法:
    python3 run_any_workflow.py <workflow_json_path>

示例:
    python3 run_any_workflow.py /path/to/workflow.json
    python3 run_any_workflow.py ../ai/data/workflows/workflow_*.json

环境变量:
    AWS_BATCH_QUEUE - AWS Batch 队列名称
    AWS_S3_BUCKET - S3 存储桶名称
    AWS_BATCH_JOB_ROLE_ARN - Batch Job Role ARN (可选)
"""

import json
import os
import sys
import time
import boto3
from datetime import datetime
from typing import Dict, List, Set, Tuple
from collections import defaultdict, deque

# ============================================================================
# 配置
# ============================================================================

REGION = os.environ.get('AWS_DEFAULT_REGION', 'us-west-2')
QUEUE_NAME = os.environ.get('AWS_BATCH_QUEUE')
S3_BUCKET = os.environ.get('AWS_S3_BUCKET')
JOB_ROLE_ARN = os.environ.get('AWS_BATCH_JOB_ROLE_ARN')

if not QUEUE_NAME or not S3_BUCKET:
    print("❌ 错误: 请设置环境变量")
    print("  export AWS_BATCH_QUEUE=your-queue-name")
    print("  export AWS_S3_BUCKET=your-bucket-name")
    sys.exit(1)

# AWS 客户端
batch = boto3.client('batch', region_name=REGION)
s3 = boto3.client('s3', region_name=REGION)

# 测试 ID (使用时间戳)
TEST_ID = datetime.now().strftime('%Y%m%d-%H%M%S')
TEST_PREFIX = f"workflow-test-{TEST_ID}"

# 任务跟踪
job_ids = {}
step_outputs = {}

# ============================================================================
# Workflow 分析
# ============================================================================

def load_workflow(workflow_path: str) -> dict:
    """加载 workflow JSON 文件"""
    with open(workflow_path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    # 处理两种 workflow 格式
    # 格式1: 直接包含 steps（如 workflow_00a4dbc9329c638b.json）
    # 格式2: 有 workflow_json 字段，steps 在里面
    if 'workflow_json' in data and isinstance(data['workflow_json'], dict):
        return data['workflow_json']

    return data


def analyze_workflow(workflow: dict) -> Tuple[List[List[str]], Dict[str, List[str]]]:
    """
    分析 workflow 结构，返回执行层次和依赖关系

    Returns:
        (layers, dependencies)
        - layers: 按执行顺序排列的步骤层次
        - dependencies: 每个步骤的依赖步骤列表
    """
    steps = workflow.get('steps', {})

    # 构建依赖图
    dependencies = defaultdict(list)
    in_degree = defaultdict(int)

    for step_id, step_data in steps.items():
        # 初始化
        if step_id not in in_degree:
            in_degree[step_id] = 0

        # 分析输入连接
        input_connections = step_data.get('input_connections', {})

        for input_name, connections in input_connections.items():
            if not connections:
                continue

            # 处理单个连接或连接列表
            if isinstance(connections, dict):
                connections = [connections]

            for conn in connections:
                source_step = str(conn.get('id', ''))
                if source_step and source_step in steps:
                    dependencies[step_id].append(source_step)
                    in_degree[step_id] += 1

    # 拓扑排序 - 分层
    layers = []
    remaining_steps = set(steps.keys())

    while remaining_steps:
        # 找到当前层：没有未处理依赖的步骤
        current_layer = []
        for step_id in remaining_steps:
            deps = dependencies[step_id]
            if all(dep not in remaining_steps for dep in deps):
                current_layer.append(step_id)

        if not current_layer:
            # 有循环依赖
            print(f"⚠️  警告: 检测到循环依赖，剩余步骤: {remaining_steps}")
            current_layer = list(remaining_steps)

        layers.append(sorted(current_layer))
        remaining_steps -= set(current_layer)

    return layers, dict(dependencies)


def print_workflow_info(workflow: dict, layers: List[List[str]], dependencies: Dict[str, List[str]]):
    """打印 workflow 信息"""
    steps = workflow.get('steps', {})
    name = workflow.get('name', 'Unnamed Workflow')

    print("\n" + "="*80)
    print(f"Workflow 云执行测试")
    print("="*80)
    print(f"\nWorkflow 名称: {name}")
    print(f"步骤数: {len(steps)}")
    print(f"执行层数: {len(layers)}")

    # 处理空 layers
    if layers:
        print(f"最大并行度: {max(len(layer) for layer in layers)}")
    else:
        print(f"最大并行度: 0")

    print(f"\n配置:")
    print(f"  区域: {REGION}")
    print(f"  队列: {QUEUE_NAME}")
    print(f"  S3桶: {S3_BUCKET}")
    print(f"  测试ID: {TEST_ID}")
    if JOB_ROLE_ARN:
        print(f"  Job Role: {JOB_ROLE_ARN}")

    print(f"\n执行计划:")
    for i, layer in enumerate(layers):
        print(f"  Layer {i}: {len(layer)} 步骤 - {layer}")

    print()


# ============================================================================
# AWS Batch 操作
# ============================================================================

def create_job_definition(name: str, vcpus: int = 1, memory: int = 512) -> str:
    """创建或获取 job definition"""
    container_props = {
        'image': 'public.ecr.aws/amazonlinux/amazonlinux:2',
        'vcpus': vcpus,
        'memory': memory,
        'command': ['echo', 'hello'],
    }

    if JOB_ROLE_ARN:
        container_props['jobRoleArn'] = JOB_ROLE_ARN

    try:
        response = batch.register_job_definition(
            jobDefinitionName=name,
            type='container',
            containerProperties=container_props
        )
        return response['jobDefinitionArn']
    except Exception as e:
        # 如果已存在，获取最新版本
        response = batch.describe_job_definitions(status='ACTIVE', maxResults=1)
        if response['jobDefinitions']:
            return response['jobDefinitions'][0]['jobDefinitionArn']
        raise e


def sanitize_job_name(name: str) -> str:
    """
    清理作业名称，确保符合 AWS Batch 规则

    AWS Batch job name 规则:
    - 最多 128 个字符
    - 只能包含: 字母、数字、连字符(-)、下划线(_)
    """
    if not name or name == 'None':
        return 'step'

    # 替换空格和特殊字符为下划线
    import re
    sanitized = re.sub(r'[^a-zA-Z0-9_-]', '_', name)

    # 移除连续的下划线
    sanitized = re.sub(r'_+', '_', sanitized)

    # 移除首尾的下划线
    sanitized = sanitized.strip('_')

    # 限制长度（留空间给时间戳）
    if len(sanitized) > 100:
        sanitized = sanitized[:100]

    return sanitized or 'step'


def submit_job(step_name: str, command: str, job_def: str,
               depends_on: List[str] = None) -> str:
    """提交作业（自动包装AWS CLI安装）"""
    # 包装命令，自动安装AWS CLI
    wrapped_cmd = f"yum install -y aws-cli &>/dev/null && {command}"
    command_list = ['sh', '-c', wrapped_cmd]

    # 清理作业名称
    clean_name = sanitize_job_name(step_name)

    params = {
        'jobName': f"{clean_name}-{TEST_ID}",
        'jobQueue': QUEUE_NAME,
        'jobDefinition': job_def,
        'containerOverrides': {
            'command': command_list,
            'environment': [{'name': 'AWS_DEFAULT_REGION', 'value': REGION}]
        }
    }

    if depends_on:
        params['dependsOn'] = [{'jobId': jid} for jid in depends_on]

    response = batch.submit_job(**params)
    job_id = response['jobId']

    deps_str = f" (依赖: {len(depends_on)} 个作业)" if depends_on else ""
    print(f"  ✓ 提交作业: {step_name}{deps_str} -> {job_id[:8]}...")

    return job_id


def wait_for_jobs(job_ids_list: List[str], step_names: List[str] = None):
    """等待作业完成"""
    if not job_ids_list:
        return

    pending = set(job_ids_list)
    start_time = time.time()

    names_map = {}
    if step_names:
        names_map = dict(zip(job_ids_list, step_names))

    print(f"\n等待 {len(pending)} 个作业完成...")

    failed_jobs = []

    while pending:
        response = batch.describe_jobs(jobs=list(pending))

        for job in response['jobs']:
            job_id = job['jobId']
            status = job['status']
            name = names_map.get(job_id, job['jobName'])

            if status in ['SUCCEEDED', 'FAILED']:
                elapsed = time.time() - start_time

                if status == 'SUCCEEDED':
                    print(f"  ✓ {name} 完成 ({elapsed:.1f}s)")
                else:
                    reason = job.get('statusReason', 'Unknown')
                    print(f"  ✗ {name} 失败: {reason}")
                    failed_jobs.append((name, job_id, reason))

                pending.remove(job_id)

        if pending:
            time.sleep(5)

    elapsed = time.time() - start_time
    print(f"\n所有作业完成，总耗时: {elapsed:.1f}秒 ({elapsed/60:.1f}分钟)")

    if failed_jobs:
        print(f"\n❌ {len(failed_jobs)} 个作业失败:")
        for name, job_id, reason in failed_jobs:
            print(f"  - {name} ({job_id}): {reason}")
        return False

    return True


# ============================================================================
# Workflow 执行
# ============================================================================

def generate_mock_command(step_id: str, step_data: dict, dependencies: List[str]) -> str:
    """
    为步骤生成模拟命令

    在真实场景中，这里会：
    1. 从 S3 下载依赖步骤的输出
    2. 执行工具命令
    3. 上传输出到 S3
    """
    tool_id = step_data.get('tool_id', 'unknown')
    label = step_data.get('label', f'step_{step_id}')

    # 构建命令
    cmd_parts = []

    # 1. 下载依赖输入
    if dependencies:
        for dep in dependencies:
            cmd_parts.append(
                f'aws s3 cp s3://{S3_BUCKET}/{TEST_PREFIX}/step_{dep}_output.txt /tmp/input_{dep}.txt'
            )

    # 2. 模拟工具执行
    cmd_parts.append(f'echo "Executing {tool_id} for step {step_id}" > /tmp/output.txt')

    if dependencies:
        # 简单处理：合并所有输入
        cmd_parts.append(f'cat /tmp/input_*.txt >> /tmp/output.txt 2>/dev/null || true')

    cmd_parts.append(f'echo "Step {step_id} completed at $(date)" >> /tmp/output.txt')

    # 3. 上传输出
    cmd_parts.append(
        f'aws s3 cp /tmp/output.txt s3://{S3_BUCKET}/{TEST_PREFIX}/step_{step_id}_output.txt'
    )

    return ' && '.join(cmd_parts)


def execute_workflow(workflow_path: str) -> bool:
    """执行完整 workflow"""
    # 1. 加载和分析
    print(f"\n加载 workflow: {workflow_path}")
    workflow = load_workflow(workflow_path)
    layers, dependencies = analyze_workflow(workflow)
    steps = workflow.get('steps', {})

    print_workflow_info(workflow, layers, dependencies)

    # 检查是否为空 workflow
    if not steps:
        print("\n⚠️  跳过: Workflow 没有步骤")
        return True  # 返回成功，但跳过执行

    if not layers:
        print("\n⚠️  跳过: Workflow 没有可执行层")
        return True  # 返回成功，但跳过执行

    # 2. 创建 job definition
    print("正在创建 job definition...")
    job_def_arn = create_job_definition(f"workflow-{TEST_ID}", vcpus=1, memory=512)
    print(f"  Job Definition: {job_def_arn}")

    # 3. 逐层执行
    print(f"\n开始执行 workflow ({len(layers)} 层)...\n")

    overall_start = time.time()

    for layer_idx, layer in enumerate(layers):
        print(f"{'='*80}")
        print(f"Layer {layer_idx}: {len(layer)} 个步骤")
        print(f"{'='*80}")

        layer_jobs = []
        layer_names = []

        # 提交这一层的所有作业
        for step_id in layer:
            step_data = steps[step_id]

            # 生成步骤名称（优先级：label > name > tool_id > step_id）
            step_label = step_data.get('label') or step_data.get('name') or \
                        step_data.get('tool_id', '').split('/')[-1] or f'step_{step_id}'

            # 获取依赖的作业ID
            deps = dependencies.get(step_id, [])
            dep_job_ids = [job_ids.get(dep) for dep in deps if dep in job_ids]

            # 生成命令
            command = generate_mock_command(step_id, step_data, deps)

            # 提交作业
            job_id = submit_job(step_label, command, job_def_arn, dep_job_ids)

            job_ids[step_id] = job_id
            layer_jobs.append(job_id)
            layer_names.append(step_label)

        # 等待这一层完成
        success = wait_for_jobs(layer_jobs, layer_names)

        if not success:
            print(f"\n❌ Layer {layer_idx} 执行失败")
            return False

    # 4. 完成
    overall_elapsed = time.time() - overall_start

    print(f"\n{'='*80}")
    print(f"✅ Workflow 执行成功!")
    print(f"{'='*80}")
    print(f"总步骤数: {len(steps)}")
    print(f"总层数: {len(layers)}")
    print(f"总耗时: {overall_elapsed:.1f}秒 ({overall_elapsed/60:.1f}分钟)")
    print(f"\nS3 输出路径: s3://{S3_BUCKET}/{TEST_PREFIX}/")
    print(f"测试ID: {TEST_ID}")

    return True


# ============================================================================
# 主程序
# ============================================================================

def main():
    if len(sys.argv) < 2:
        print("用法: python3 run_any_workflow.py <workflow_json_path>")
        print("\n示例:")
        print("  python3 run_any_workflow.py workflow.json")
        print("  python3 run_any_workflow.py ../ai/data/workflows/workflow_*.json")
        sys.exit(1)

    workflow_path = sys.argv[1]

    if not os.path.exists(workflow_path):
        print(f"❌ 错误: 文件不存在: {workflow_path}")
        sys.exit(1)

    try:
        success = execute_workflow(workflow_path)
        sys.exit(0 if success else 1)
    except KeyboardInterrupt:
        print("\n\n⚠️  用户中断")
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ 执行失败: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == '__main__':
    main()
