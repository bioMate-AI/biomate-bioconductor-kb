"""
Workflow DAG Executor

Executes Galaxy workflows as DAGs on cloud platforms, handling dependencies,
data flow, and parallel execution.
"""

import asyncio
import logging
import traceback
from typing import Dict, List, Optional, Set, Any, Callable
from datetime import datetime, timezone
from dataclasses import dataclass
from collections import defaultdict, deque

from galaxy_cloud.core.executor import CloudExecutor
from galaxy_cloud.core.job import JobResult, JobStatus
from galaxy_cloud.factory import CloudExecutorFactory

from .models import (
    WorkflowDAG, WorkflowExecution, StepExecution, WorkflowStep,
    StepStatus, StepType, WorkflowRunConfig, WorkflowInput, WorkflowOutput
)
from .data_manager import GalaxyDataManager


logger = logging.getLogger(__name__)


@dataclass
class ExecutionContext:
    """Context for workflow execution"""
    workflow_execution: WorkflowExecution
    cloud_executor: CloudExecutor
    data_manager: GalaxyDataManager
    run_config: WorkflowRunConfig
    step_outputs: Dict[str, Dict[str, Any]]  # step_id -> {output_name -> data}
    step_callbacks: Dict[str, List[Callable]]  # step_id -> callbacks


class WorkflowDAGExecutor:
    """
    Executes Galaxy workflows as DAGs on cloud platforms.

    This class handles:
    - DAG topological sorting and dependency resolution
    - Parallel step execution with resource constraints
    - Data flow between steps
    - Error handling and recovery
    - Progress monitoring and reporting
    """

    def __init__(self, cloud_executor: CloudExecutor, data_manager: GalaxyDataManager):
        self.cloud_executor = cloud_executor
        self.data_manager = data_manager
        self.logger = logging.getLogger(f"{self.__class__.__module__}.{self.__class__.__name__}")

        # Execution state
        self.active_executions: Dict[str, ExecutionContext] = {}
        self.execution_callbacks: Dict[str, List[Callable]] = defaultdict(list)

    async def execute_workflow(
        self,
        workflow_dag: WorkflowDAG,
        inputs: List[WorkflowInput],
        run_config: WorkflowRunConfig,
        execution_id: Optional[str] = None
    ) -> WorkflowExecution:
        """Execute a workflow DAG"""

        if not execution_id:
            execution_id = f"exec-{workflow_dag.workflow_id}-{int(datetime.now().timestamp())}"

        # Create workflow execution
        workflow_execution = WorkflowExecution(
            execution_id=execution_id,
            workflow_dag=workflow_dag,
            inputs=inputs,
            status=StepStatus.PENDING,
            start_time=datetime.now(timezone.utc).isoformat()
        )

        # Initialize step executions
        for step_id, step in workflow_dag.steps.items():
            step_execution = StepExecution(
                step_id=step_id,
                status=StepStatus.PENDING
            )
            workflow_execution.step_executions[step_id] = step_execution

        # Create execution context
        context = ExecutionContext(
            workflow_execution=workflow_execution,
            cloud_executor=self.cloud_executor,
            data_manager=self.data_manager,
            run_config=run_config,
            step_outputs={},
            step_callbacks=defaultdict(list)
        )

        # Store active execution
        self.active_executions[execution_id] = context

        try:
            # Stage input data
            await self._stage_workflow_inputs(context)

            # Execute workflow steps
            workflow_execution.status = StepStatus.RUNNING
            await self._execute_dag_steps(context)

            # Retrieve outputs
            await self._retrieve_workflow_outputs(context)

            # Mark as completed
            workflow_execution.status = StepStatus.COMPLETED
            workflow_execution.end_time = datetime.now(timezone.utc).isoformat()

            self.logger.info(f"Workflow execution {execution_id} completed successfully")

        except Exception as e:
            self.logger.error(f"Workflow execution {execution_id} failed: {e}")
            workflow_execution.status = StepStatus.FAILED
            workflow_execution.error_message = str(e)
            workflow_execution.end_time = datetime.now(timezone.utc).isoformat()

        finally:
            # Cleanup
            if execution_id in self.active_executions:
                del self.active_executions[execution_id]

        return workflow_execution

    async def _stage_workflow_inputs(self, context: ExecutionContext):
        """Stage workflow input data to cloud storage"""
        self.logger.info("Staging workflow inputs...")

        for workflow_input in context.workflow_execution.inputs:
            if workflow_input.dataset_info:
                # Stage dataset
                cloud_uri = await context.data_manager.stage_dataset(
                    workflow_input.dataset_info,
                    context.run_config
                )
                # Store staged location
                context.step_outputs[workflow_input.input_id] = {
                    'output': {
                        'type': 'dataset',
                        'cloud_uri': cloud_uri,
                        'dataset_info': workflow_input.dataset_info
                    }
                }

            elif workflow_input.collection_info:
                # Stage collection
                cloud_uris = await context.data_manager.stage_collection(
                    workflow_input.collection_info,
                    context.run_config
                )
                context.step_outputs[workflow_input.input_id] = {
                    'output': {
                        'type': 'collection',
                        'cloud_uris': cloud_uris,
                        'collection_info': workflow_input.collection_info
                    }
                }

            else:
                # Parameter input
                context.step_outputs[workflow_input.input_id] = {
                    'output': {
                        'type': 'parameter',
                        'value': workflow_input.value
                    }
                }

    async def _execute_dag_steps(self, context: ExecutionContext):
        """Execute workflow steps in DAG order"""
        workflow_dag = context.workflow_execution.workflow_dag

        # Build dependency graph
        dependency_graph = self._build_dependency_graph(workflow_dag)

        # Topological sort to get execution order
        execution_levels = self._topological_sort(workflow_dag, dependency_graph)

        self.logger.info(f"Executing workflow in {len(execution_levels)} levels")

        # Execute steps level by level
        for level_idx, step_ids in enumerate(execution_levels):
            self.logger.info(f"Executing level {level_idx + 1} with steps: {step_ids}")

            # Filter out input steps (already handled)
            executable_steps = [
                step_id for step_id in step_ids
                if workflow_dag.steps[step_id].step_type not in [StepType.INPUT, StepType.COLLECTION_INPUT]
            ]

            if not executable_steps:
                continue

            # Execute steps in parallel with resource constraints
            await self._execute_steps_parallel(context, executable_steps)

            # Check for failures
            failed_steps = [
                step_id for step_id in executable_steps
                if context.workflow_execution.step_executions[step_id].status == StepStatus.FAILED
            ]

            if failed_steps:
                raise Exception(f"Steps failed: {failed_steps}")

    def _build_dependency_graph(self, workflow_dag: WorkflowDAG) -> Dict[str, Set[str]]:
        """Build dependency graph for topological sorting"""
        graph = defaultdict(set)

        for dependency in workflow_dag.dependencies:
            graph[dependency.to_step].add(dependency.from_step)

        return dict(graph)

    def _topological_sort(self, workflow_dag: WorkflowDAG, dependency_graph: Dict[str, Set[str]]) -> List[List[str]]:
        """Perform topological sort to get execution levels"""
        # Initialize in-degree count
        in_degree = {step_id: 0 for step_id in workflow_dag.steps.keys()}

        # Build reverse graph and calculate in-degrees
        reverse_graph = defaultdict(set)
        for step_id, dependencies in dependency_graph.items():
            in_degree[step_id] = len(dependencies)
            for dep in dependencies:
                reverse_graph[dep].add(step_id)

        # Kahn's algorithm for level-wise topological sorting
        result = []
        queue = deque([step_id for step_id, degree in in_degree.items() if degree == 0])

        while queue:
            current_level = list(queue)
            queue.clear()
            result.append(current_level)

            for step_id in current_level:
                for neighbor in reverse_graph[step_id]:
                    in_degree[neighbor] -= 1
                    if in_degree[neighbor] == 0:
                        queue.append(neighbor)

        return result

    async def _execute_steps_parallel(self, context: ExecutionContext, step_ids: List[str]):
        """Execute multiple steps in parallel with resource constraints"""
        max_parallel = context.run_config.max_parallel_jobs

        # Create semaphore to limit parallel execution
        semaphore = asyncio.Semaphore(max_parallel)

        # Create tasks for all steps
        tasks = []
        for step_id in step_ids:
            task = asyncio.create_task(
                self._execute_single_step_with_semaphore(context, step_id, semaphore)
            )
            tasks.append(task)

        # Wait for all tasks to complete
        await asyncio.gather(*tasks, return_exceptions=True)

    async def _execute_single_step_with_semaphore(
        self,
        context: ExecutionContext,
        step_id: str,
        semaphore: asyncio.Semaphore
    ):
        """Execute a single step with semaphore protection"""
        async with semaphore:
            await self._execute_single_step(context, step_id)

    async def _execute_single_step(self, context: ExecutionContext, step_id: str):
        """Execute a single workflow step"""
        workflow_dag = context.workflow_execution.workflow_dag
        step = workflow_dag.steps[step_id]
        step_execution = context.workflow_execution.step_executions[step_id]

        self.logger.info(f"Executing step {step_id}: {step.name}")

        try:
            step_execution.status = StepStatus.RUNNING
            step_execution.start_time = datetime.now(timezone.utc).isoformat()

            if step.step_type == StepType.TOOL:
                await self._execute_tool_step(context, step, step_execution)
            elif step.step_type == StepType.SUBWORKFLOW:
                await self._execute_subworkflow_step(context, step, step_execution)
            elif step.step_type == StepType.PAUSE:
                await self._execute_pause_step(context, step, step_execution)
            else:
                raise Exception(f"Unsupported step type: {step.step_type}")

            step_execution.status = StepStatus.COMPLETED
            step_execution.end_time = datetime.now(timezone.utc).isoformat()

            self.logger.info(f"Step {step_id} completed successfully")

        except Exception as e:
            self.logger.error(f"Step {step_id} failed: {e}")
            self.logger.error(f"Traceback:\n{''.join(traceback.format_tb(e.__traceback__))}")
            step_execution.status = StepStatus.FAILED
            step_execution.error_message = str(e)
            step_execution.end_time = datetime.now(timezone.utc).isoformat()
            raise

    async def _execute_tool_step(
        self,
        context: ExecutionContext,
        step: WorkflowStep,
        step_execution: StepExecution
    ):
        """Execute a tool step"""
        if not step.job_spec:
            raise Exception(f"Tool step {step.step_id} has no job specification")

        # Prepare input data and update job spec
        job_spec = await self._prepare_job_inputs(context, step)

        # Submit job to cloud executor
        cloud_job_id = await context.cloud_executor.submit_job(job_spec)
        step_execution.cloud_job_id = cloud_job_id

        self.logger.info(f"Submitted job {cloud_job_id} for step {step.step_id}")

        # Wait for job completion
        result = await context.cloud_executor.wait_for_completion(cloud_job_id)

        # Store execution results
        step_execution.exit_code = result.exit_code
        step_execution.stdout = result.stdout
        step_execution.stderr = result.stderr
        step_execution.resource_usage = result.resource_usage or {}

        if result.status != JobStatus.COMPLETED:
            raise Exception(f"Job failed with status: {result.status}")

        # Process outputs
        await self._process_step_outputs(context, step, result)

    async def _execute_subworkflow_step(
        self,
        context: ExecutionContext,
        step: WorkflowStep,
        step_execution: StepExecution
    ):
        """Execute a subworkflow step"""
        # This would recursively execute another workflow
        # For now, we'll just mark it as completed
        self.logger.warning(f"Subworkflow execution not yet implemented for step {step.step_id}")

    async def _execute_pause_step(
        self,
        context: ExecutionContext,
        step: WorkflowStep,
        step_execution: StepExecution
    ):
        """Execute a pause step"""
        # Pause steps require user intervention
        # For automated execution, we'll skip them
        self.logger.info(f"Skipping pause step {step.step_id}")

    async def _prepare_job_inputs(self, context: ExecutionContext, step: WorkflowStep):
        """Prepare job inputs and update job specification"""
        job_spec = step.job_spec.model_copy()  # Create a copy

        # Build input files mapping
        input_files = {}
        input_env = {}

        # Process step dependencies to get input data
        workflow_dag = context.workflow_execution.workflow_dag
        for dependency in workflow_dag.dependencies:
            if dependency.to_step == step.step_id:
                from_step = dependency.from_step
                from_output = dependency.from_output
                to_input = dependency.to_input

                if from_step in context.step_outputs:
                    step_output = context.step_outputs[from_step].get(from_output)
                    if step_output:
                        # Map cloud URI to container path
                        if step_output['type'] == 'dataset':
                            cloud_uri = step_output['cloud_uri']
                            container_path = f"/input/{to_input}"
                            input_files[cloud_uri] = container_path
                            input_env[f"GALAXY_INPUT_{to_input.upper()}"] = container_path

                        elif step_output['type'] == 'collection':
                            # Handle collections
                            for idx, cloud_uri in enumerate(step_output['cloud_uris']):
                                container_path = f"/input/{to_input}_{idx}"
                                input_files[cloud_uri] = container_path

        # Update job spec with input files
        job_spec.input_files = input_files

        # Add environment variables
        if job_spec.container.env is None:
            job_spec.container.env = {}
        job_spec.container.env.update(input_env)

        # Set output directory
        job_spec.output_files = {"/output": f"/tmp/galaxy-outputs/{step.step_id}"}

        return job_spec

    async def _process_step_outputs(
        self,
        context: ExecutionContext,
        step: WorkflowStep,
        job_result: JobResult
    ):
        """Process step outputs and store them for downstream steps"""
        step_outputs = {}

        # For each output defined in the step
        for output_name, output_spec in step.outputs.items():
            if output_spec['type'] == 'dataset':
                # Create dataset from job output
                output_cloud_uri = f"{context.run_config.output_area}/{step.step_id}/{output_name}"

                # Store output location
                step_outputs[output_name] = {
                    'type': 'dataset',
                    'cloud_uri': output_cloud_uri,
                    'job_result': job_result
                }

        # Store outputs for use by downstream steps
        context.step_outputs[step.step_id] = step_outputs

    async def _retrieve_workflow_outputs(self, context: ExecutionContext):
        """Retrieve final workflow outputs"""
        workflow_dag = context.workflow_execution.workflow_dag

        for output_id, output_spec in workflow_dag.outputs.items():
            step_id = output_spec['step_id']
            output_name = output_spec['output_name']

            if step_id in context.step_outputs:
                step_output = context.step_outputs[step_id].get(output_name)
                if step_output:
                    workflow_output = WorkflowOutput(
                        output_id=output_id,
                        step_id=step_id,
                        output_name=output_name,
                        label=output_spec.get('label', '')
                    )

                    if step_output['type'] == 'dataset':
                        # Retrieve dataset from cloud storage
                        dataset_info = await context.data_manager.retrieve_dataset(
                            step_output['cloud_uri'],
                            context.run_config
                        )
                        workflow_output.dataset_info = dataset_info

                    context.workflow_execution.outputs.append(workflow_output)

    async def cancel_workflow(self, execution_id: str):
        """Cancel a running workflow execution"""
        if execution_id not in self.active_executions:
            raise ValueError(f"Execution {execution_id} not found")

        context = self.active_executions[execution_id]
        workflow_execution = context.workflow_execution

        self.logger.info(f"Cancelling workflow execution {execution_id}")

        # Cancel running jobs
        for step_execution in workflow_execution.step_executions.values():
            if step_execution.cloud_job_id and step_execution.status == StepStatus.RUNNING:
                try:
                    await context.cloud_executor.cancel_job(step_execution.cloud_job_id)
                    step_execution.status = StepStatus.CANCELLED
                except Exception as e:
                    self.logger.warning(f"Failed to cancel job {step_execution.cloud_job_id}: {e}")

        workflow_execution.status = StepStatus.CANCELLED
        workflow_execution.end_time = datetime.now(timezone.utc).isoformat()

    def get_execution_status(self, execution_id: str) -> Optional[WorkflowExecution]:
        """Get current status of a workflow execution"""
        if execution_id in self.active_executions:
            return self.active_executions[execution_id].workflow_execution
        return None

    def add_execution_callback(self, execution_id: str, callback: Callable):
        """Add callback for execution events"""
        self.execution_callbacks[execution_id].append(callback)

    async def list_active_executions(self) -> List[str]:
        """List all active workflow executions"""
        return list(self.active_executions.keys())