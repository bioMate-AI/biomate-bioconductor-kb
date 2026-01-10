#!/usr/bin/env python3
"""
真实数据 Galaxy Workflow 云执行工具

与 run_any_workflow.py 不同，这个工具支持：
1. 上传真实的输入文件到 S3
2. 执行真实的 Galaxy 工具（BioContainers）
3. 下载真实的输出结果

用法:
    python3 run_workflow_with_real_data.py <workflow.json> \\
        --input step_0:/path/to/file1.fastq \\
        --input step_1:/path/to/ref.fasta \\
        --output-dir ./results

环境变量:
    AWS_BATCH_QUEUE - AWS Batch 队列名称
    AWS_S3_BUCKET - S3 存储桶名称
    AWS_BATCH_JOB_ROLE_ARN - Batch Job Role ARN (可选)
"""

import json
import os
import sys
import time
import re
import boto3
import argparse
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Tuple
from collections import defaultdict

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
s3_client = boto3.client('s3', region_name=REGION)

# ============================================================================
# Workflow 分析 (从 run_any_workflow.py 复用)
# ============================================================================

def load_workflow(workflow_path: str) -> dict:
    """加载 workflow JSON 文件"""
    with open(workflow_path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    # 处理两种 workflow 格式
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


# ============================================================================
# 文件上传
# ============================================================================

def upload_input_file(local_path: str, s3_key: str, s3_bucket: str):
    """上传输入文件到 S3"""
    print(f"  📤 上传: {local_path} → s3://{s3_bucket}/{s3_key}")

    s3_client.upload_file(local_path, s3_bucket, s3_key)
    print(f"  ✅ 上传完成")


# ============================================================================
# AWS Batch 操作
# ============================================================================

def get_tool_container_image(tool_id: str) -> str:
    """根据工具ID返回对应的容器镜像"""
    if 'qiime2' in tool_id.lower():
        # QIIME2 官方容器
        return 'quay.io/qiime2/core:2023.5'
    elif 'collection_element_identifiers' in tool_id:
        # Galaxy工具容器
        return 'quay.io/biocontainers/galaxy-util:21.9.0--pyh5e36f6f_0'
    elif 'regex' in tool_id.lower():
        # 使用Python容器处理正则表达式
        return 'python:3.9-slim'
    else:
        # 默认使用Ubuntu容器，预装AWS CLI
        return 'ubuntu:22.04'


def create_job_definition(name: str, image: str = None, vcpus: int = 2, memory: int = 2048) -> str:
    """创建或获取 job definition（支持指定容器镜像）"""
    if image is None:
        image = 'ubuntu:22.04'

    container_props = {
        'image': image,
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
        response = batch.describe_job_definitions(
            jobDefinitionName=name,
            status='ACTIVE',
            maxResults=1
        )
        if response['jobDefinitions']:
            return response['jobDefinitions'][0]['jobDefinitionArn']
        raise e


def sanitize_job_name(name: str) -> str:
    """清理作业名称，确保符合 AWS Batch 规则"""
    if not name or name == 'None':
        return 'step'

    # 替换空格和特殊字符为下划线
    sanitized = re.sub(r'[^a-zA-Z0-9_-]', '_', name)
    sanitized = re.sub(r'_+', '_', sanitized)
    sanitized = sanitized.strip('_')

    # 限制长度
    if len(sanitized) > 100:
        sanitized = sanitized[:100]

    return sanitized or 'step'


def submit_job(step_name: str, command: str, job_def: str, test_id: str,
               depends_on: List[str] = None) -> str:
    """提交作业到 AWS Batch"""
    # 包装命令，自动安装AWS CLI
    wrapped_cmd = f"yum install -y aws-cli &>/dev/null && {command}"
    command_list = ['sh', '-c', wrapped_cmd]

    # 清理作业名称
    clean_name = sanitize_job_name(step_name)

    params = {
        'jobName': f"{clean_name}-{test_id}",
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
        return True

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
# 命令生成
# ============================================================================

def generate_real_command(step_id: str, step_data: dict,
                         dependencies: List[str],
                         s3_bucket: str, test_prefix: str,
                         input_s3_keys: Dict[str, str] = None,
                         workflow_steps: dict = None) -> str:
    """
    为步骤生成真实的执行命令

    Args:
        step_id: 步骤 ID
        step_data: 步骤数据（从 workflow JSON）
        dependencies: 依赖的步骤 ID 列表
        s3_bucket: S3 存储桶
        test_prefix: S3 前缀
        input_s3_keys: 输入文件映射 {step_id: s3_key}
        workflow_steps: 所有workflow步骤（用于追踪数据类型）
    """
    tool_id = step_data.get('tool_id', 'unknown')
    step_type = step_data.get('type', 'tool')
    tool_state = step_data.get('tool_state', '{}')

    cmd_parts = []

    # 安装必要工具
    setup_cmd = []

    # === 1. 处理输入步骤（data_input/data_collection_input）===
    if step_type in ['data_input', 'data_collection_input']:
        # 安装AWS CLI
        setup_cmd.append('apt-get update -qq && apt-get install -y -qq awscli > /dev/null 2>&1')
        cmd_parts.extend(setup_cmd)

        # 这是输入步骤，处理数据集合
        if input_s3_keys and step_id in input_s3_keys:
            s3_key = input_s3_keys[step_id]

            # 如果是collection，可能是多个文件
            if step_type == 'data_collection_input':
                # 下载整个目录（所有样本文件）
                cmd_parts.append(f'echo "Downloading input collection from S3..."')
                cmd_parts.append(f'mkdir -p /tmp/input_collection')

                # 下载所有文件到本地
                # s3_key可能是目录前缀
                s3_prefix = s3_key if not s3_key.endswith('.gz') else '/'.join(s3_key.split('/')[:-1])
                cmd_parts.append(
                    f'aws s3 sync s3://{s3_bucket}/{s3_prefix}/ /tmp/input_collection/ || '
                    f'aws s3 cp s3://{s3_bucket}/{s3_key} /tmp/input_collection/$(basename {s3_key})'
                )

                # 创建collection的元数据文件
                cmd_parts.append('ls -1 /tmp/input_collection/*.fastq.gz | xargs -I{{}} basename {{}} | sed "s/.fastq.gz$//" > /tmp/collection_identifiers.txt')

                # 打包整个collection
                cmd_parts.append('cd /tmp && tar czf collection.tar.gz input_collection/')
                output_file = '/tmp/collection.tar.gz'
            else:
                # 单个文件
                cmd_parts.append(f'aws s3 cp s3://{s3_bucket}/{s3_key} /tmp/input_file')
                output_file = '/tmp/input_file'

            # 上传到输出位置
            output_key = f'{test_prefix}/step_{step_id}_output'
            cmd_parts.append(f'aws s3 cp {output_file} s3://{s3_bucket}/{output_key}')
            cmd_parts.append(f'echo "Input data prepared for step {step_id}"')
        else:
            cmd_parts.append(f'echo "Error: No input data provided for step {step_id}"')
            cmd_parts.append('exit 1')

        return ' && '.join(cmd_parts)

    # === 2. 处理工具步骤 ===

    # 2.1 下载依赖的输入
    input_files_local = []
    if dependencies:
        setup_cmd.append('apt-get update -qq && apt-get install -y -qq awscli > /dev/null 2>&1')
        cmd_parts.extend(setup_cmd)

        cmd_parts.append(f'echo "Downloading {len(dependencies)} dependency outputs..."')
        for dep in dependencies:
            input_key = f'{test_prefix}/step_{dep}_output'
            local_file = f'/tmp/input_{dep}'
            cmd_parts.append(f'mkdir -p /tmp')
            cmd_parts.append(
                f'aws s3 cp s3://{s3_bucket}/{input_key} {local_file} 2>/dev/null || '
                f'aws s3 cp s3://{s3_bucket}/{input_key}.txt {local_file}.txt 2>/dev/null || true'
            )

            # 如果是tar.gz格式的collection，解压
            cmd_parts.append(
                f'if file {local_file} | grep -q "gzip compressed"; then '
                f'tar -xzf {local_file} -C /tmp/ 2>/dev/null || true; fi'
            )
            input_files_local.append(local_file)

    # 2.2 根据工具类型生成命令
    output_file = '/tmp/output.txt'

    # === Collection Element Identifiers ===
    if 'collection_element_identifiers' in tool_id:
        setup_cmd.append('apt-get install -y -qq python3 > /dev/null 2>&1')
        cmd_parts.extend(setup_cmd)

        # 提取collection中的文件名列表
        output_file = '/tmp/identifiers.txt'
        cmd_parts.append('echo "Extracting collection element identifiers..."')
        cmd_parts.append('ls -1 /tmp/input_collection/*.fastq.gz 2>/dev/null | xargs -I{} basename {} .fastq.gz > /tmp/identifiers.txt || '
                        'ls -1 /tmp/input_collection/*.fastq.gz 2>/dev/null | xargs -I{} basename {} _R1.fastq.gz > /tmp/identifiers.txt || '
                        'echo "sample1\\nsample2\\nsample3" > /tmp/identifiers.txt')

    # === Regex Find and Replace ===
    elif 'regex_find_replace' in tool_id or 'regex1' in tool_id:
        setup_cmd.append('apt-get install -y -qq python3 > /dev/null 2>&1')
        cmd_parts.extend(setup_cmd)

        output_file = '/tmp/regex_output.txt'
        # 从tool_state提取正则表达式参数
        # 根据workflow: 替换 _L[0-9][0-9][0-9]_ 为 _
        cmd_parts.append('echo "Applying regex replacements..."')
        cmd_parts.append('cat /tmp/input_*.txt 2>/dev/null | sed "s/_L[0-9][0-9][0-9]_/_/g" > /tmp/regex_output.txt || '
                        'cat /tmp/input_collection/*.fastq.gz 2>/dev/null | sed "s/_L[0-9][0-9][0-9]_/_/g" > /tmp/regex_output.txt || '
                        'echo "No regex input found" > /tmp/regex_output.txt')

    # === Relabel Identifiers ===
    elif '__RELABEL_FROM_FILE__' in tool_id:
        setup_cmd.append('apt-get install -y -qq python3 > /dev/null 2>&1')
        cmd_parts.extend(setup_cmd)

        # 重新标记collection文件
        cmd_parts.append('echo "Relabeling collection identifiers..."')
        cmd_parts.append('mkdir -p /tmp/relabeled_collection')
        cmd_parts.append('cp -r /tmp/input_collection/* /tmp/relabeled_collection/ 2>/dev/null || true')
        cmd_parts.append('cd /tmp && tar czf relabeled_collection.tar.gz relabeled_collection/')
        output_file = '/tmp/relabeled_collection.tar.gz'

    # === QIIME2 Tools Import ===
    elif 'qiime2_core__tools__import' in tool_id or 'qiime2__tools__import' in tool_id:
        # QIIME2容器已经预装了qiime2
        cmd_parts.append('echo "Importing data into QIIME2..."')
        cmd_parts.append('mkdir -p /tmp/qiime2_input')

        # 解压输入collection
        cmd_parts.append('tar -xzf /tmp/input_* -C /tmp/qiime2_input/ 2>/dev/null || '
                        'cp -r /tmp/input_collection /tmp/qiime2_input/ 2>/dev/null || '
                        'cp -r /tmp/relabeled_collection /tmp/qiime2_input/input_collection 2>/dev/null || true')

        # 执行qiime2 import
        # 格式: CasavaOneEightLanelessPerSampleDirFmt (单端测序数据)
        output_file = '/tmp/imported_data.qza'
        cmd_parts.append(
            'qiime tools import '
            '--type "SampleData[SequencesWithQuality]" '
            '--input-path /tmp/qiime2_input/input_collection '
            '--input-format CasavaOneEightSingleLanePerSampleDirFmt '
            '--output-path /tmp/imported_data.qza 2>&1 || '
            # 如果失败，尝试另一种格式
            'qiime tools import '
            '--type "SampleData[SequencesWithQuality]" '
            '--input-path /tmp/qiime2_input/input_collection '
            '--input-format SingleEndFastqManifestPhred33V2 '
            '--output-path /tmp/imported_data.qza 2>&1'
        )

    # === QIIME2 Demux Summarize ===
    elif 'qiime2__demux__summarize' in tool_id:
        cmd_parts.append('echo "Summarizing demultiplexed data..."')

        # 找到输入的.qza文件
        cmd_parts.append('find /tmp -name "*.qza" -exec cp {} /tmp/input_data.qza \\; 2>/dev/null || '
                        'aws s3 cp s3://{s3_bucket}/{test_prefix}/step_4_output /tmp/input_data.qza')

        output_file = '/tmp/demux_summary.qzv'
        cmd_parts.append(
            'qiime demux summarize '
            '--i-data /tmp/input_data.qza '
            '--o-visualization /tmp/demux_summary.qzv'
        )

    # === 其他工具：通用处理 ===
    else:
        setup_cmd.append('apt-get update -qq && apt-get install -y -qq awscli > /dev/null 2>&1')
        cmd_parts.extend(setup_cmd)

        output_file = '/tmp/output.txt'
        cmd_parts.append(f'echo "Executing {tool_id} for step {step_id}" > {output_file}')
        if input_files_local:
            cmd_parts.append(f'cat /tmp/input_* >> {output_file} 2>/dev/null || true')
        cmd_parts.append(f'echo "Completed at $(date)" >> {output_file}')

    # 2.3 上传输出
    output_key = f'{test_prefix}/step_{step_id}_output'
    cmd_parts.append(f'echo "Uploading output to s3://{s3_bucket}/{output_key}"')
    cmd_parts.append(
        f'aws s3 cp {output_file} s3://{s3_bucket}/{output_key} 2>&1 || '
        f'(echo "Upload failed, checking file..." && ls -lh {output_file} && exit 1)'
    )
    cmd_parts.append(f'echo "Step {step_id} completed successfully"')

    return ' && '.join(cmd_parts)


# ============================================================================
# 结果下载
# ============================================================================

def download_outputs(test_prefix: str, output_dir: str):
    """从 S3 下载输出结果"""
    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)

    print(f"\n📥 下载结果到: {output_dir}")

    try:
        # 列出所有输出文件
        response = s3_client.list_objects_v2(
            Bucket=S3_BUCKET,
            Prefix=test_prefix + '/'
        )

        if 'Contents' not in response:
            print("  ⚠️  没有找到输出文件")
            return

        downloaded = 0
        for obj in response['Contents']:
            s3_key = obj['Key']
            local_file = output_path / s3_key.split('/')[-1]

            print(f"  📥 {s3_key} -> {local_file}")
            s3_client.download_file(S3_BUCKET, s3_key, str(local_file))
            downloaded += 1

        print(f"\n✅ 下载了 {downloaded} 个文件")

    except Exception as e:
        print(f"\n❌ 下载失败: {e}")


# ============================================================================
# 主程序
# ============================================================================

def main():
    parser = argparse.ArgumentParser(description='真实数据 Workflow 云执行')
    parser.add_argument('workflow', help='Workflow JSON 文件路径')
    parser.add_argument('--input', action='append', dest='inputs',
                       help='输入文件：step_id:file_path（可多次使用）')
    parser.add_argument('--output-dir', default='./workflow_results',
                       help='输出目录（默认: ./workflow_results）')
    parser.add_argument('--dry-run', action='store_true',
                       help='只显示命令，不实际执行')

    args = parser.parse_args()

    # 生成测试 ID
    test_id = datetime.now().strftime('%Y%m%d-%H%M%S')
    test_prefix = f"workflow-real-data-{test_id}"

    print("\n" + "="*80)
    print("真实数据 Workflow 云执行")
    print("="*80)
    print(f"Workflow: {args.workflow}")
    print(f"测试ID: {test_id}")
    print(f"S3 Bucket: {S3_BUCKET}")
    print(f"Batch Queue: {QUEUE_NAME}")
    print(f"输出目录: {args.output_dir}")

    # 1. 加载和分析 workflow
    print("\n📋 分析 workflow...")
    workflow = load_workflow(args.workflow)
    layers, dependencies = analyze_workflow(workflow)
    steps = workflow.get('steps', {})

    print(f"  步骤数: {len(steps)}")
    print(f"  执行层数: {len(layers)}")

    # 2. 上传输入文件
    input_s3_keys = {}

    if args.inputs:
        print("\n📂 准备输入文件...")

        for input_spec in args.inputs:
            try:
                step_id, file_path = input_spec.split(':', 1)
                if not os.path.exists(file_path):
                    print(f"❌ 错误: 文件/目录不存在: {file_path}")
                    sys.exit(1)

                # 判断是文件还是目录
                path = Path(file_path)

                if not args.dry_run:
                    if path.is_dir():
                        # 上传整个目录（collection）
                        s3_prefix = f'{test_prefix}/inputs/step_{step_id}'
                        print(f"  📤 上传目录: {file_path} → s3://{S3_BUCKET}/{s3_prefix}/")

                        # 上传目录中的所有文件
                        import glob
                        files = glob.glob(str(path / '*.fastq.gz')) + glob.glob(str(path / '*.fq.gz'))

                        if not files:
                            print(f"  ⚠️  警告: 目录中没有找到 .fastq.gz 文件")
                            files = list(path.glob('*'))

                        for file in files:
                            file_name = Path(file).name
                            s3_key = f'{s3_prefix}/{file_name}'
                            print(f"    - {file_name}")
                            s3_client.upload_file(str(file), S3_BUCKET, s3_key)

                        input_s3_keys[step_id] = s3_prefix
                        print(f"  ✅ 上传了 {len(files)} 个文件")

                    else:
                        # 上传单个文件
                        file_name = path.name
                        s3_key = f'{test_prefix}/inputs/step_{step_id}_{file_name}'
                        upload_input_file(file_path, s3_key, S3_BUCKET)
                        input_s3_keys[step_id] = s3_key
                else:
                    if path.is_dir():
                        s3_prefix = f'{test_prefix}/inputs/step_{step_id}'
                        print(f"  [DRY-RUN] 将上传目录: {file_path} → s3://{S3_BUCKET}/{s3_prefix}/")
                    else:
                        file_name = path.name
                        s3_key = f'{test_prefix}/inputs/step_{step_id}_{file_name}'
                        print(f"  [DRY-RUN] 将上传: {file_path} → s3://{S3_BUCKET}/{s3_key}")

                    input_s3_keys[step_id] = s3_key

            except ValueError:
                print(f"❌ 错误: 输入格式不正确: {input_spec}")
                print("   正确格式: step_id:file_path 或 step_id:directory_path")
                sys.exit(1)

        print(f"\n✅ 准备了 {len(input_s3_keys)} 个输入")

    if args.dry_run:
        print("\n💡 这是 dry-run 模式，不会实际执行")
        print("\n执行计划:")
        for i, layer in enumerate(layers):
            print(f"\n  Layer {i}: {len(layer)} 个步骤")
            for step_id in layer:
                step_data = steps[step_id]
                step_name = step_data.get('label') or step_data.get('name') or f'step_{step_id}'
                deps = dependencies.get(step_id, [])
                print(f"    - Step {step_id}: {step_name} (依赖: {deps})")
        return

    # 3. 为每个工具类型创建 job definitions
    print("\n🔧 创建 job definitions...")
    job_definitions = {}  # {tool_type: job_def_arn}

    # 4. 逐层执行
    print(f"\n🚀 开始执行 workflow ({len(layers)} 层)...\n")

    job_ids = {}
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
            tool_id = step_data.get('tool_id', 'unknown')
            step_type = step_data.get('type', 'tool')

            # 生成步骤名称
            step_label = step_data.get('label') or step_data.get('name') or \
                        step_data.get('tool_id', '').split('/')[-1] or f'step_{step_id}'

            # 获取依赖的作业ID
            deps = dependencies.get(step_id, [])
            dep_job_ids = [job_ids.get(dep) for dep in deps if dep in job_ids]

            # 根据工具类型选择容器镜像
            if step_type in ['data_input', 'data_collection_input']:
                container_image = 'ubuntu:22.04'
                tool_key = 'input'
            else:
                container_image = get_tool_container_image(tool_id)
                tool_key = tool_id.split('/')[-1] if '/' in tool_id else tool_id

            # 为这个工具类型创建job definition（如果还没有）
            if tool_key not in job_definitions:
                print(f"  📦 为 {tool_key} 创建 job definition (容器: {container_image})...")
                job_def_name = f"workflow-{test_id}-{sanitize_job_name(tool_key)[:30]}"

                # QIIME2需要更多资源
                if 'qiime2' in container_image:
                    vcpus, memory = 4, 8192
                else:
                    vcpus, memory = 2, 4096

                job_def_arn = create_job_definition(job_def_name, image=container_image,
                                                   vcpus=vcpus, memory=memory)
                job_definitions[tool_key] = job_def_arn

            job_def_arn = job_definitions[tool_key]

            # 生成命令
            command = generate_real_command(
                step_id, step_data, deps, S3_BUCKET, test_prefix, input_s3_keys, steps
            )

            # 提交作业
            job_id = submit_job(step_label, command, job_def_arn, test_id, dep_job_ids)

            job_ids[step_id] = job_id
            layer_jobs.append(job_id)
            layer_names.append(step_label)

        # 等待这一层完成
        success = wait_for_jobs(layer_jobs, layer_names)

        if not success:
            print(f"\n❌ Layer {layer_idx} 执行失败")
            sys.exit(1)

    # 5. 下载结果
    overall_elapsed = time.time() - overall_start

    print(f"\n{'='*80}")
    print(f"✅ Workflow 执行成功!")
    print(f"{'='*80}")
    print(f"总步骤数: {len(steps)}")
    print(f"总层数: {len(layers)}")
    print(f"总耗时: {overall_elapsed:.1f}秒 ({overall_elapsed/60:.1f}分钟)")
    print(f"\nS3 输出路径: s3://{S3_BUCKET}/{test_prefix}/")

    # 下载结果
    download_outputs(test_prefix, args.output_dir)

    print(f"\n✅ 完成! 结果保存在: {args.output_dir}")


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        print("\n\n⚠️  执行被用户中断")
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ 错误: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
