#!/usr/bin/env python3
"""
Galaxy Workflow Cloud Execution Example

This example demonstrates how to execute Galaxy workflows on cloud platforms
using the galaxy-cloud-executor framework.
"""

import asyncio
import logging
from pathlib import Path

from galaxy_cloud.galaxy_workflow import GalaxyCloudIntegration
from galaxy_cloud.galaxy_workflow.config import load_config_from_file
from galaxy_cloud.galaxy_workflow.models import WorkflowRunConfig, WorkflowInput, DatasetInfo


async def main():
    """Main example function"""

    # Setup logging
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    logger = logging.getLogger(__name__)

    logger.info("=== Galaxy Workflow Cloud Execution Example ===")

    # Load configuration
    config_path = Path("examples/galaxy_workflow_config.yaml")
    config = load_config_from_file(config_path)

    # Initialize Galaxy Cloud Integration
    integration = GalaxyCloudIntegration(config.dict())
    await integration.initialize()

    try:
        # Example 1: Execute workflow from file
        await example_workflow_from_file(integration, logger)

        # Example 2: Execute workflow from Galaxy instance
        # await example_workflow_from_galaxy(integration, logger)

        # Example 3: Monitor workflow execution
        # await example_monitor_workflow(integration, logger)

    finally:
        await integration.close()

    logger.info("=== Example completed ===")


async def example_workflow_from_file(integration: GalaxyCloudIntegration, logger):
    """Example: Execute workflow from .ga file"""

    logger.info("--- Example 1: Workflow from file ---")

    # Define workflow file (you would provide your own .ga file)
    workflow_file = Path("examples/sample_workflow.ga")

    # For this example, we'll create a simple workflow structure
    if not workflow_file.exists():
        sample_workflow = create_sample_workflow()
        workflow_file.parent.mkdir(exist_ok=True)
        with open(workflow_file, 'w') as f:
            import json
            json.dump(sample_workflow, f, indent=2)

    # Define workflow inputs
    inputs = {
        "input_dataset": {
            "dataset_path": "/path/to/input/sequences.fasta",
            "name": "Input Sequences",
            "ext": "fasta"
        },
        "reference_genome": {
            "dataset_path": "/path/to/reference/genome.fa",
            "name": "Reference Genome",
            "ext": "fasta"
        },
        "quality_threshold": 20
    }

    # Define run configuration
    run_config = WorkflowRunConfig(
        cloud_provider="kubernetes",
        namespace="galaxy-workflows",
        staging_area="staging/example1",
        output_area="outputs/example1",
        max_parallel_jobs=3,
        job_timeout=3600,
        retry_attempts=2
    )

    logger.info(f"Submitting workflow: {workflow_file}")
    logger.info(f"Target platform: {run_config.cloud_provider}")

    try:
        # Submit workflow for execution
        execution = await integration.submit_workflow_from_file(
            workflow_file=workflow_file,
            inputs=inputs,
            run_config=run_config
        )

        logger.info(f"Workflow submitted with execution ID: {execution.execution_id}")
        logger.info(f"Workflow status: {execution.status}")

        # Print execution summary
        print_execution_summary(execution, logger)

    except Exception as e:
        logger.error(f"Failed to execute workflow: {e}")


async def example_workflow_from_galaxy(integration: GalaxyCloudIntegration, logger):
    """Example: Execute workflow from Galaxy instance"""

    logger.info("--- Example 2: Workflow from Galaxy ---")

    # Galaxy workflow and history IDs (you would use real IDs)
    workflow_id = "f2db41e1fa331b3e"
    history_id = "1cd8e2f6b131e891"

    # Define inputs (referring to Galaxy datasets)
    inputs = {
        "input_data": "dataset_123456789abcdef",  # Galaxy dataset ID
        "reference": "dataset_987654321fedcba",   # Galaxy dataset ID
        "parameters": {
            "quality_threshold": 20,
            "coverage_threshold": 10
        }
    }

    # Run configuration
    run_config = WorkflowRunConfig(
        cloud_provider="aws",
        staging_area="s3://galaxy-cloud-bucket/staging",
        output_area="s3://galaxy-cloud-bucket/outputs",
        max_parallel_jobs=5,
        job_timeout=7200
    )

    logger.info(f"Submitting Galaxy workflow: {workflow_id}")

    try:
        # Submit workflow from Galaxy
        execution = await integration.submit_workflow_from_galaxy(
            workflow_id=workflow_id,
            inputs=inputs,
            run_config=run_config,
            history_id=history_id
        )

        logger.info(f"Galaxy workflow submitted: {execution.execution_id}")
        print_execution_summary(execution, logger)

    except Exception as e:
        logger.error(f"Failed to execute Galaxy workflow: {e}")


async def example_monitor_workflow(integration: GalaxyCloudIntegration, logger):
    """Example: Monitor workflow execution"""

    logger.info("--- Example 3: Monitor workflow ---")

    # List active executions
    executions = await integration.list_executions()
    logger.info(f"Active executions: {executions}")

    if executions:
        execution_id = executions[0]

        # Monitor execution status
        for i in range(10):  # Check status 10 times
            status = await integration.get_execution_status(execution_id)
            if status:
                logger.info(f"Execution {execution_id} status: {status.status}")

                # Print step statuses
                for step_id, step_exec in status.step_executions.items():
                    logger.info(f"  Step {step_id}: {step_exec.status}")

                if status.status in ['completed', 'failed', 'cancelled']:
                    break

            await asyncio.sleep(30)  # Wait 30 seconds between checks


def create_sample_workflow():
    """Create a sample workflow for demonstration"""
    return {
        "uuid": "sample-workflow-uuid",
        "name": "Sample Bioinformatics Workflow",
        "version": "1.0",
        "annotation": "A sample workflow for demonstration",
        "steps": {
            "0": {
                "id": 0,
                "type": "data_input",
                "label": "Input Dataset",
                "annotation": "Input sequences in FASTA format"
            },
            "1": {
                "id": 1,
                "type": "data_input",
                "label": "Reference Genome",
                "annotation": "Reference genome in FASTA format"
            },
            "2": {
                "id": 2,
                "type": "tool",
                "tool_id": "toolshed.g2.bx.psu.edu/repos/devteam/fastqc/fastqc",
                "label": "FastQC Quality Control",
                "annotation": "Quality control of input sequences",
                "input_connections": {
                    "input_file": {"id": 0, "output_name": "output"}
                }
            },
            "3": {
                "id": 3,
                "type": "tool",
                "tool_id": "toolshed.g2.bx.psu.edu/repos/devteam/bwa/bwa_mem",
                "label": "BWA Alignment",
                "annotation": "Align sequences to reference genome",
                "input_connections": {
                    "reference_source": {"id": 1, "output_name": "output"},
                    "fastq_input": {"id": 0, "output_name": "output"}
                }
            },
            "4": {
                "id": 4,
                "type": "tool",
                "tool_id": "toolshed.g2.bx.psu.edu/repos/devteam/samtools_mpileup/samtools_mpileup",
                "label": "Variant Calling",
                "annotation": "Call variants from alignment",
                "input_connections": {
                    "reference_source": {"id": 1, "output_name": "output"},
                    "input_bam": {"id": 3, "output_name": "output"}
                },
                "workflow_outputs": [
                    {"output_name": "output_vcf", "label": "Variants"}
                ]
            }
        }
    }


def print_execution_summary(execution, logger):
    """Print execution summary"""
    logger.info("--- Execution Summary ---")
    logger.info(f"Execution ID: {execution.execution_id}")
    logger.info(f"Workflow: {execution.workflow_dag.name}")
    logger.info(f"Status: {execution.status}")
    logger.info(f"Start Time: {execution.start_time}")
    logger.info(f"End Time: {execution.end_time}")

    if execution.error_message:
        logger.error(f"Error: {execution.error_message}")

    logger.info(f"Total Steps: {len(execution.step_executions)}")

    # Step status summary
    status_counts = {}
    for step_exec in execution.step_executions.values():
        status = step_exec.status
        status_counts[status] = status_counts.get(status, 0) + 1

    for status, count in status_counts.items():
        logger.info(f"  {status}: {count} steps")

    # Output summary
    if execution.outputs:
        logger.info(f"Outputs: {len(execution.outputs)}")
        for output in execution.outputs:
            logger.info(f"  {output.label}: {output.output_name}")


async def example_batch_execution():
    """Example: Execute multiple workflows in batch"""

    # This would demonstrate batch execution of multiple workflows
    # with different configurations and priorities
    pass


async def example_workflow_with_collections():
    """Example: Execute workflow with dataset collections"""

    # This would demonstrate handling of Galaxy dataset collections
    # in cloud execution environment
    pass


if __name__ == "__main__":
    asyncio.run(main())