#!/usr/bin/env python3
"""
通用Galaxy Workflow云执行工具

使用galaxy_cloud模块执行任何Galaxy workflow
支持从环境变量或命令行参数配置

环境变量:
    GALAXY_AWS_ENABLED=true
    GALAXY_AWS_BATCH_QUEUE=your-queue-name
    GALAXY_AWS_S3_BUCKET=your-bucket-name
    AWS_DEFAULT_REGION=us-west-2

用法:
    python run_any_galaxy_workflow.py workflow.json \\
        --input 0:/path/to/input/files \\
        --provider aws \\
        --staging workflows/test
"""

import asyncio
import logging
import sys
import os
import argparse
from pathlib import Path
from typing import Dict, Any

# 添加父目录到路径
sys.path.insert(0, str(Path(__file__).parent.parent))

from galaxy_cloud.galaxy_workflow import GalaxyCloudIntegration
from galaxy_cloud.galaxy_workflow.models import WorkflowRunConfig
from galaxy_cloud.config import ConfigManager


def parse_args():
    """解析命令行参数"""
    parser = argparse.ArgumentParser(
        description='Execute任何Galaxy workflow在云平台上',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例:
  # 使用环境变量配置
  export GALAXY_AWS_ENABLED=true
  export GALAXY_AWS_BATCH_QUEUE=galaxy-cloud-queue
  export GALAXY_AWS_S3_BUCKET=galaxy-cloud-data-1760241377
  export AWS_DEFAULT_REGION=us-west-2

  python %(prog)s workflow.json --input 0:/path/to/data

  # 使用配置文件
  python %(prog)s workflow.json --config config.yaml --input 0:/path/to/data
        """
    )

    parser.add_argument('workflow', type=str, help='Workflow JSON文件路径')
    parser.add_argument('--input', action='append', dest='inputs',
                       help='输入数据: step_id:path (可以是文件或目录)')
    parser.add_argument('--provider', default='aws',
                       help='云提供商 (默认: aws)')
    parser.add_argument('--staging', default='workflows/staging',
                       help='S3临时区域前缀 (默认: workflows/staging)')
    parser.add_argument('--output', default='workflows/outputs',
                       help='S3输出区域前缀 (默认: workflows/outputs)')
    parser.add_argument('--config', type=str,
                       help='配置文件路径 (可选，否则使用环境变量)')
    parser.add_argument('--max-parallel', type=int, default=5,
                       help='最大并行作业数 (默认: 5)')
    parser.add_argument('--timeout', type=int, default=3600,
                       help='作业超时时间(秒) (默认: 3600)')
    parser.add_argument('--monitor', action='store_true',
                       help='监控执行状态直到完成')
    parser.add_argument('--log-level', default='INFO',
                       choices=['DEBUG', 'INFO', 'WARNING', 'ERROR'],
                       help='日志级别 (默认: INFO)')

    return parser.parse_args()


def parse_inputs(input_specs: list) -> Dict[str, Any]:
    """
    解析输入参数

    输入格式: step_id:path
    - 如果path是目录，自动识别为collection
    - 如果path是文件，识别为单个dataset
    """
    inputs = {}

    for spec in input_specs:
        try:
            step_id, path_str = spec.split(':', 1)
            path = Path(path_str)

            if not path.exists():
                raise ValueError(f"路径不存在: {path}")

            if path.is_dir():
                # 目录 -> collection
                # 查找所有fastq.gz文件
                fastq_files = list(path.glob('*.fastq.gz')) + list(path.glob('*.fq.gz'))

                if not fastq_files:
                    print(f"⚠️  警告: 目录 {path} 中没有找到 .fastq.gz 文件，将使用所有文件")
                    fastq_files = list(path.glob('*'))

                inputs[step_id] = {
                    "collection_paths": [str(f) for f in fastq_files],
                    "name": path.name,
                    "ext": "fastqsanger.gz"  # 默认类型
                }
                print(f"  ✓ Step {step_id}: 目录 (collection) - {len(fastq_files)} 个文件")

            else:
                # 文件 -> dataset
                inputs[step_id] = {
                    "dataset_path": str(path),
                    "name": path.name,
                    "ext": path.suffix.replace('.', '') if path.suffix else "data"
                }
                print(f"  ✓ Step {step_id}: 文件 (dataset) - {path.name}")

        except ValueError as e:
            print(f"❌ 错误: 输入格式不正确: {spec}")
            print(f"   {e}")
            print("   正确格式: step_id:file_path 或 step_id:directory_path")
            sys.exit(1)

    return inputs


async def monitor_execution(integration, execution_id, logger, max_checks=120, interval=30):
    """监控workflow执行状态"""

    for i in range(max_checks):
        execution = await integration.get_execution_status(execution_id)

        if not execution:
            logger.warning("Execution not found")
            break

        logger.info(f"\n[Check {i+1}/{max_checks}] Overall status: {execution.status}")

        # 统计步骤状态
        step_status_counts = {}
        failed_steps = []

        for step_id, step_exec in execution.step_executions.items():
            status = str(step_exec.status)
            step_status_counts[status] = step_status_counts.get(status, 0) + 1

            if step_exec.status == 'FAILED':
                failed_steps.append((step_id, step_exec.error_message))

        # 打印状态摘要
        status_str = ", ".join([f"{status}: {count}" for status, count in sorted(step_status_counts.items())])
        logger.info(f"  Steps: {status_str}")

        # 打印失败信息
        for step_id, error_msg in failed_steps:
            logger.error(f"  ✗ Step {step_id} failed: {error_msg}")

        # 检查是否完成
        if execution.status in ['COMPLETED', 'FAILED', 'CANCELLED']:
            logger.info(f"\n{'='*60}")
            logger.info(f"Workflow {execution.status}!")
            logger.info(f"{'='*60}")

            if execution.status == 'COMPLETED':
                logger.info(f"✓ 成功完成! 输出数: {len(execution.outputs)}")
                for output in execution.outputs:
                    logger.info(f"  - {output.label}")
            elif execution.status == 'FAILED':
                logger.error(f"✗ 执行失败")
                if execution.error_message:
                    logger.error(f"  错误: {execution.error_message}")

            break

        # 等待后再检查
        await asyncio.sleep(interval)

    else:
        logger.warning(f"监控超时 (已检查 {max_checks} 次)")


async def main():
    """主函数"""

    args = parse_args()

    # 设置日志
    logging.basicConfig(
        level=getattr(logging, args.log_level),
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    logger = logging.getLogger(__name__)

    logger.info("="*70)
    logger.info("Galaxy Workflow Cloud Executor (通用版本)")
    logger.info("="*70)

    # 检查workflow文件
    workflow_file = Path(args.workflow)
    if not workflow_file.exists():
        logger.error(f"❌ Workflow文件不存在: {workflow_file}")
        sys.exit(1)

    logger.info(f"Workflow: {workflow_file}")
    logger.info(f"Provider: {args.provider}")

    # 解析输入
    if not args.inputs:
        logger.error("❌ 错误: 必须提供至少一个输入 (--input)")
        sys.exit(1)

    logger.info(f"\n解析输入:")
    inputs = parse_inputs(args.inputs)

    # 加载配置
    logger.info(f"\n加载配置...")
    if args.config:
        logger.info(f"  从文件: {args.config}")
        config_manager = ConfigManager(args.config)
        config = config_manager.load_config()
    else:
        logger.info(f"  从环境变量")
        config_manager = ConfigManager()
        config = config_manager.load_config()  # 没有config_file时自动从环境变量加载

    # 检查provider是否启用
    provider_config = getattr(config, args.provider, None)
    if not provider_config or not provider_config.enabled:
        logger.error(f"❌ Provider '{args.provider}' 未启用")
        logger.info(f"\n请设置环境变量:")
        logger.info(f"  export GALAXY_{args.provider.upper()}_ENABLED=true")
        if args.provider == 'aws':
            logger.info(f"  export GALAXY_AWS_BATCH_QUEUE=your-queue-name")
            logger.info(f"  export GALAXY_AWS_S3_BUCKET=your-bucket-name")
            logger.info(f"  export AWS_DEFAULT_REGION=us-west-2")
        sys.exit(1)

    logger.info(f"  ✓ Provider '{args.provider}' 已启用")

    # 创建运行配置
    run_config = WorkflowRunConfig(
        cloud_provider=args.provider,
        staging_area=args.staging,
        output_area=args.output,
        max_parallel_jobs=args.max_parallel,
        job_timeout=args.timeout,
        retry_attempts=2
    )

    logger.info(f"\n运行配置:")
    logger.info(f"  Staging: {run_config.staging_area}")
    logger.info(f"  Output: {run_config.output_area}")
    logger.info(f"  Max parallel: {run_config.max_parallel_jobs}")
    logger.info(f"  Timeout: {run_config.job_timeout}s")

    # 初始化Galaxy Cloud Integration
    logger.info(f"\n初始化Galaxy Cloud Integration...")

    # 将CloudConfig转换为GalaxyCloudIntegration期望的格式
    integration_config = {
        'cloud_providers': {
            'aws': config.aws.model_dump() if config.aws else {},
            'azure': config.azure.model_dump() if config.azure else {},
            'gcp': config.gcp.model_dump() if config.gcp else {},
            'kubernetes': config.kubernetes.model_dump() if config.kubernetes else {},
        },
        'storage': {
            'provider': args.provider,
            's3_bucket': config.aws.s3_bucket if config.aws else None,
        },
        'tool_registry': {
            'static_mappings_file': 'config/tool_containers.yaml',
        },
    }

    integration = GalaxyCloudIntegration(integration_config)
    await integration.initialize()

    try:
        # 提交workflow
        logger.info(f"\n{'='*70}")
        logger.info("提交workflow执行...")
        logger.info(f"{'='*70}\n")

        execution = await integration.submit_workflow_from_file(
            workflow_file=workflow_file,
            inputs=inputs,
            run_config=run_config
        )

        logger.info(f"✓ Workflow已提交!")
        logger.info(f"  Execution ID: {execution.execution_id}")
        logger.info(f"  Status: {execution.status}")
        logger.info(f"  Total steps: {len(execution.step_executions)}")

        # 如果指定了monitor，则监控执行
        if args.monitor:
            logger.info(f"\n开始监控执行 (每{30}秒检查一次)...")
            await monitor_execution(integration, execution.execution_id, logger)
        else:
            logger.info(f"\n提示: 使用 --monitor 选项可以实时监控执行状态")
            logger.info(f"或者手动检查: Execution ID = {execution.execution_id}")

    except Exception as e:
        logger.error(f"\n❌ 执行失败: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

    finally:
        await integration.close()

    logger.info(f"\n{'='*70}")
    logger.info("完成!")
    logger.info(f"{'='*70}\n")


if __name__ == "__main__":
    asyncio.run(main())
