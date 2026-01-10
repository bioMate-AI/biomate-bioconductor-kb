#!/usr/bin/env python3
"""
使用galaxy_cloud模块执行QIIME2 Workflow

这是一个通用的示例，展示如何使用已有的galaxy_cloud框架
来执行任何Galaxy workflow，包括QIIME2 workflow
"""

import asyncio
import logging
import sys
from pathlib import Path

from galaxy_cloud.galaxy_workflow import GalaxyCloudIntegration
from galaxy_cloud.galaxy_workflow.models import WorkflowRunConfig


async def main():
    """执行QIIME2 workflow"""

    # 设置日志
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    logger = logging.getLogger(__name__)

    logger.info("=== QIIME2 Workflow Cloud Execution ===")

    # 配置
    config = {
        'cloud_providers': {
            'aws': {
                'region': 'us-west-2',
                'batch_queue': 'galaxy-cloud-queue',
                's3_bucket': 'galaxy-cloud-data-1760241377',
                'job_role_arn': None  # 可选
            }
        },
        'storage': {
            'provider': 'aws',
            's3_bucket': 'galaxy-cloud-data-1760241377'
        },
        'tool_registry': {
            # 工具注册表配置（可选）
        }
    }

    # Workflow文件路径
    workflow_file = Path("/Users/renyuankai/work/biometa/galaxy/lib/galaxy/ai/data/workflows/workflow_0dc387dc861bdb61.json")

    # 输入数据 - 传入目录路径，包含所有FASTQ文件
    inputs = {
        "0": {  # Step 0 是输入collection
            "collection_paths": [
                "/Users/renyuankai/work/biometa/galaxy/lib/galaxy/galaxy-cloud-executor/test_data/qiime2_demo/sample1_R1.fastq.gz",
                "/Users/renyuankai/work/biometa/galaxy/lib/galaxy/galaxy-cloud-executor/test_data/qiime2_demo/sample2_R1.fastq.gz",
                "/Users/renyuankai/work/biometa/galaxy/lib/galaxy/galaxy-cloud-executor/test_data/qiime2_demo/sample3_R1.fastq.gz",
            ],
            "name": "QIIME2 Sample Collection",
            "ext": "fastqsanger.gz"
        }
    }

    # 运行配置
    run_config = WorkflowRunConfig(
        cloud_provider="aws",
        staging_area="workflows/qiime2-test",
        output_area="workflows/qiime2-test/outputs",
        max_parallel_jobs=3,
        job_timeout=3600,
        retry_attempts=2
    )

    logger.info(f"Workflow: {workflow_file.name}")
    logger.info(f"Provider: {run_config.cloud_provider}")
    logger.info(f"Inputs: {len(inputs)} input(s)")

    # 初始化Galaxy Cloud Integration
    integration = GalaxyCloudIntegration(config)
    await integration.initialize()

    try:
        # 提交workflow执行
        logger.info("Submitting workflow for execution...")

        execution = await integration.submit_workflow_from_file(
            workflow_file=workflow_file,
            inputs=inputs,
            run_config=run_config
        )

        logger.info(f"✓ Workflow submitted!")
        logger.info(f"  Execution ID: {execution.execution_id}")
        logger.info(f"  Status: {execution.status}")
        logger.info(f"  Steps: {len(execution.step_executions)}")

        # 打印步骤信息
        logger.info("\nWorkflow steps:")
        for step_id, step_exec in execution.step_executions.items():
            logger.info(f"  Step {step_id}: {step_exec.status}")

        # 监控执行（可选）
        logger.info("\nMonitoring execution...")
        await monitor_execution(integration, execution.execution_id, logger)

    except Exception as e:
        logger.error(f"Failed to execute workflow: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

    finally:
        await integration.close()

    logger.info("\n=== Execution completed ===")


async def monitor_execution(integration, execution_id, logger, max_checks=60):
    """监控workflow执行状态"""

    import time

    for i in range(max_checks):
        execution = await integration.get_execution_status(execution_id)

        if not execution:
            logger.warning("Execution not found")
            break

        logger.info(f"\nCheck {i+1}/{max_checks} - Overall status: {execution.status}")

        # 打印每个步骤的状态
        step_status_counts = {}
        for step_id, step_exec in execution.step_executions.items():
            status = str(step_exec.status)
            step_status_counts[status] = step_status_counts.get(status, 0) + 1

            if step_exec.status == 'FAILED':
                logger.error(f"  Step {step_id} failed: {step_exec.error_message}")

        logger.info(f"  Step statuses: {step_status_counts}")

        # 检查是否完成
        if execution.status in ['COMPLETED', 'FAILED', 'CANCELLED']:
            logger.info(f"\nWorkflow {execution.status}!")

            if execution.status == 'COMPLETED':
                logger.info(f"Outputs: {len(execution.outputs)}")
                for output in execution.outputs:
                    logger.info(f"  - {output.label}")

            break

        # 等待一段时间再检查
        await asyncio.sleep(30)

    else:
        logger.warning("Monitoring timeout reached")


if __name__ == "__main__":
    # 确保导入路径正确
    sys.path.insert(0, str(Path(__file__).parent.parent))

    asyncio.run(main())
