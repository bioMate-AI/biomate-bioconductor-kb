"""
Galaxy Cloud Integration

Provides the bridge between Galaxy core and the cloud execution system.
Handles Galaxy API interactions, job status synchronization, and data integration.
"""

import json
import logging
from typing import Dict, List, Optional, Any, Union
from datetime import datetime, timezone
from pathlib import Path

import httpx

# Import galaxy_cloud module to ensure providers are registered
import galaxy_cloud
from galaxy_cloud.factory import CloudExecutorFactory
from galaxy_cloud.core.executor import CloudExecutor

from .converter import GalaxyWorkflowConverter
from .tool_registry import GalaxyToolRegistry
from .dag_executor import WorkflowDAGExecutor
from .data_manager import GalaxyDataManager
from .models import (
    WorkflowExecution, WorkflowInput, WorkflowOutput,
    DatasetInfo, CollectionInfo, WorkflowRunConfig,
    StepStatus
)


logger = logging.getLogger(__name__)


class GalaxyCloudIntegration:
    """
    Main integration class that orchestrates Galaxy workflow execution on cloud platforms.

    This class provides:
    - High-level API for submitting Galaxy workflows to cloud
    - Integration with Galaxy API for data retrieval and status updates
    - Workflow execution orchestration
    - Result collection and Galaxy integration
    """

    def __init__(self, config: Dict[str, Any]):
        self.config = config
        self.logger = logging.getLogger(f"{self.__class__.__module__}.{self.__class__.__name__}")

        # Initialize components
        self.tool_registry = GalaxyToolRegistry(config.get('tool_registry', {}))
        self.workflow_converter = GalaxyWorkflowConverter(self.tool_registry, config)
        self.data_manager = GalaxyDataManager(config.get('storage', {}))

        # Cloud executors for different providers
        self.cloud_executors: Dict[str, CloudExecutor] = {}

        # Galaxy API client
        self.galaxy_api_client = None
        if config.get('galaxy_api'):
            self.galaxy_api_client = GalaxyAPIClient(config['galaxy_api'])

        # Active workflow executions
        self.active_executions: Dict[str, WorkflowExecution] = {}

    async def initialize(self):
        """Initialize the integration system"""
        self.logger.info("Initializing Galaxy Cloud Integration")

        # Initialize Galaxy API client
        if self.galaxy_api_client:
            await self.galaxy_api_client.initialize()

        self.logger.info("Galaxy Cloud Integration initialized successfully")

    async def submit_workflow_from_file(
        self,
        workflow_file: Path,
        inputs: Dict[str, Any],
        run_config: WorkflowRunConfig,
        galaxy_invocation_id: Optional[str] = None
    ) -> WorkflowExecution:
        """Submit a Galaxy workflow file for cloud execution"""

        # Load and convert workflow
        workflow_spec = self.workflow_converter.load_workflow_from_file(workflow_file)
        workflow_dag = await self.workflow_converter.convert_to_dag(workflow_spec)

        return await self._execute_workflow_dag(
            workflow_dag, inputs, run_config, galaxy_invocation_id
        )

    async def submit_workflow_from_galaxy(
        self,
        workflow_id: str,
        inputs: Dict[str, Any],
        run_config: WorkflowRunConfig,
        history_id: Optional[str] = None
    ) -> WorkflowExecution:
        """Submit a workflow from Galaxy instance for cloud execution"""

        if not self.galaxy_api_client:
            raise ValueError("Galaxy API client not configured")

        # Fetch workflow from Galaxy
        workflow_data = await self.galaxy_api_client.get_workflow(workflow_id)
        workflow_spec = self.workflow_converter.load_workflow_from_dict(workflow_data)
        workflow_dag = await self.workflow_converter.convert_to_dag(workflow_spec)

        # Convert Galaxy inputs to workflow inputs
        workflow_inputs = await self._convert_galaxy_inputs(inputs, history_id)

        return await self._execute_workflow_dag(
            workflow_dag, workflow_inputs, run_config, None
        )

    async def _execute_workflow_dag(
        self,
        workflow_dag,
        inputs: Union[Dict[str, Any], List[WorkflowInput]],
        run_config: WorkflowRunConfig,
        galaxy_invocation_id: Optional[str] = None
    ) -> WorkflowExecution:
        """Execute a workflow DAG on cloud platform"""

        # Get or create cloud executor
        cloud_executor = await self._get_cloud_executor(run_config.cloud_provider)

        # Create DAG executor
        dag_executor = WorkflowDAGExecutor(cloud_executor, self.data_manager)

        # Convert inputs if needed
        if isinstance(inputs, dict):
            workflow_inputs = await self._convert_input_dict_to_workflow_inputs(inputs)
        else:
            workflow_inputs = inputs

        # Execute workflow
        execution_id = galaxy_invocation_id or f"cloud-exec-{int(datetime.now().timestamp())}"
        workflow_execution = await dag_executor.execute_workflow(
            workflow_dag, workflow_inputs, run_config, execution_id
        )

        # Store execution
        self.active_executions[execution_id] = workflow_execution

        # Update Galaxy if invocation ID is provided
        if galaxy_invocation_id and self.galaxy_api_client:
            await self._sync_execution_with_galaxy(workflow_execution, galaxy_invocation_id)

        return workflow_execution

    async def _get_cloud_executor(self, provider: str) -> CloudExecutor:
        """Get or create cloud executor for provider"""
        if provider not in self.cloud_executors:
            provider_config = self.config.get('cloud_providers', {}).get(provider, {})

            # Map provider names to executor types
            executor_type_map = {
                'aws': 'aws-batch',
                'azure': 'azure-batch',
                'gcp': 'gcp-batch',
                'kubernetes': 'kubernetes'
            }

            executor_type = executor_type_map.get(provider, provider)
            executor = CloudExecutorFactory.create(executor_type, provider_config)

            await executor.__aenter__()
            self.cloud_executors[provider] = executor

        return self.cloud_executors[provider]

    async def _convert_galaxy_inputs(
        self,
        inputs: Dict[str, Any],
        history_id: Optional[str] = None
    ) -> List[WorkflowInput]:
        """Convert Galaxy API inputs to WorkflowInput objects"""

        workflow_inputs = []

        for input_id, input_value in inputs.items():
            if isinstance(input_value, str) and input_value.startswith('dataset_'):
                # Dataset input
                dataset_id = input_value.replace('dataset_', '')
                dataset_info = await self.galaxy_api_client.get_dataset(dataset_id, history_id)

                workflow_input = WorkflowInput(
                    input_id=input_id,
                    label=f"Dataset {dataset_id}",
                    type='dataset',
                    dataset_info=dataset_info
                )
                workflow_inputs.append(workflow_input)

            elif isinstance(input_value, str) and input_value.startswith('collection_'):
                # Collection input
                collection_id = input_value.replace('collection_', '')
                collection_info = await self.galaxy_api_client.get_collection(collection_id, history_id)

                workflow_input = WorkflowInput(
                    input_id=input_id,
                    label=f"Collection {collection_id}",
                    type='collection',
                    collection_info=collection_info
                )
                workflow_inputs.append(workflow_input)

            else:
                # Parameter input
                workflow_input = WorkflowInput(
                    input_id=input_id,
                    label=f"Parameter {input_id}",
                    type='parameter',
                    value=input_value
                )
                workflow_inputs.append(workflow_input)

        return workflow_inputs

    async def _convert_input_dict_to_workflow_inputs(
        self,
        inputs: Dict[str, Any]
    ) -> List[WorkflowInput]:
        """Convert input dictionary to WorkflowInput objects"""

        workflow_inputs = []

        for input_id, input_value in inputs.items():
            if isinstance(input_value, dict):
                if 'dataset_path' in input_value:
                    # Local dataset file
                    dataset_info = DatasetInfo(
                        dataset_id=input_id,
                        history_id='local',
                        name=input_value.get('name', input_id),
                        file_ext=input_value.get('ext', 'data'),
                        file_path=input_value['dataset_path']
                    )

                    workflow_input = WorkflowInput(
                        input_id=input_id,
                        label=dataset_info.name,
                        type='dataset',
                        dataset_info=dataset_info
                    )
                    workflow_inputs.append(workflow_input)

                elif 'collection_paths' in input_value:
                    # Local collection
                    elements = []
                    for idx, path in enumerate(input_value['collection_paths']):
                        element = DatasetInfo(
                            dataset_id=f"{input_id}_element_{idx}",
                            history_id='local',
                            name=f"Element {idx}",
                            file_ext=input_value.get('ext', 'data'),
                            file_path=path
                        )
                        elements.append(element)

                    collection_info = CollectionInfo(
                        collection_id=input_id,
                        history_id='local',
                        name=input_value.get('name', input_id),
                        collection_type='list',
                        elements=elements
                    )

                    workflow_input = WorkflowInput(
                        input_id=input_id,
                        label=collection_info.name,
                        type='collection',
                        collection_info=collection_info
                    )
                    workflow_inputs.append(workflow_input)

            else:
                # Simple parameter
                workflow_input = WorkflowInput(
                    input_id=input_id,
                    label=f"Parameter {input_id}",
                    type='parameter',
                    value=input_value
                )
                workflow_inputs.append(workflow_input)

        return workflow_inputs

    async def _sync_execution_with_galaxy(
        self,
        workflow_execution: WorkflowExecution,
        galaxy_invocation_id: str
    ):
        """Sync workflow execution status with Galaxy"""

        try:
            # Update invocation status
            await self.galaxy_api_client.update_invocation_status(
                galaxy_invocation_id,
                self._convert_status_to_galaxy(workflow_execution.status)
            )

            # Update step statuses
            for step_id, step_execution in workflow_execution.step_executions.items():
                await self.galaxy_api_client.update_step_status(
                    galaxy_invocation_id,
                    step_id,
                    self._convert_status_to_galaxy(step_execution.status),
                    step_execution.error_message
                )

            # If completed, create output datasets in Galaxy
            if workflow_execution.status == StepStatus.COMPLETED:
                await self._create_galaxy_outputs(workflow_execution, galaxy_invocation_id)

        except Exception as e:
            self.logger.error(f"Failed to sync execution {workflow_execution.execution_id} with Galaxy: {e}")

    def _convert_status_to_galaxy(self, status: StepStatus) -> str:
        """Convert internal status to Galaxy status"""
        mapping = {
            StepStatus.PENDING: 'new',
            StepStatus.QUEUED: 'queued',
            StepStatus.RUNNING: 'running',
            StepStatus.COMPLETED: 'ok',
            StepStatus.FAILED: 'error',
            StepStatus.CANCELLED: 'deleted',
            StepStatus.SKIPPED: 'skipped'
        }
        return mapping.get(status, 'new')

    async def _create_galaxy_outputs(
        self,
        workflow_execution: WorkflowExecution,
        galaxy_invocation_id: str
    ):
        """Create output datasets in Galaxy from workflow results"""

        for output in workflow_execution.outputs:
            if output.dataset_info:
                # Create dataset in Galaxy
                await self.galaxy_api_client.create_dataset_from_file(
                    output.dataset_info.file_path,
                    output.label,
                    output.dataset_info.file_ext,
                    galaxy_invocation_id
                )

    async def get_execution_status(self, execution_id: str) -> Optional[WorkflowExecution]:
        """Get current status of a workflow execution"""
        return self.active_executions.get(execution_id)

    async def cancel_execution(self, execution_id: str):
        """Cancel a running workflow execution"""
        if execution_id in self.active_executions:
            workflow_execution = self.active_executions[execution_id]

            # Find the DAG executor (this is simplified - in practice you'd track this)
            for provider, executor in self.cloud_executors.items():
                dag_executor = WorkflowDAGExecutor(executor, self.data_manager)
                await dag_executor.cancel_workflow(execution_id)

    async def list_executions(self) -> List[str]:
        """List all active workflow executions"""
        return list(self.active_executions.keys())

    async def cleanup_execution(self, execution_id: str, cleanup_data: bool = False):
        """Clean up resources for a completed execution"""
        if execution_id in self.active_executions:
            workflow_execution = self.active_executions[execution_id]

            if cleanup_data:
                # Clean up cloud storage
                for cloud_executor in self.cloud_executors.values():
                    dag_executor = WorkflowDAGExecutor(cloud_executor, self.data_manager)
                    # Clean up staging area for this execution
                    # This would need to be implemented in the data manager

            # Remove from active executions
            del self.active_executions[execution_id]

    async def close(self):
        """Close all resources"""
        # Close cloud executors
        for executor in self.cloud_executors.values():
            await executor.__aexit__(None, None, None)

        # Close data manager
        await self.data_manager.close()

        # Close tool registry
        await self.tool_registry.close()

        # Close Galaxy API client
        if self.galaxy_api_client:
            await self.galaxy_api_client.close()


class GalaxyAPIClient:
    """Client for interacting with Galaxy API"""

    def __init__(self, config: Dict[str, Any]):
        self.base_url = config['url'].rstrip('/')
        self.api_key = config['api_key']
        self.verify_ssl = config.get('verify_ssl', True)

        self.client = httpx.AsyncClient(
            base_url=f"{self.base_url}/api",
            headers={'X-API-KEY': self.api_key},
            verify=self.verify_ssl,
            timeout=30.0
        )

    async def initialize(self):
        """Initialize API client and verify connection"""
        try:
            response = await self.client.get('/version')
            response.raise_for_status()
            version = response.json()
            logger.info(f"Connected to Galaxy {version.get('version_major', 'unknown')}")
        except Exception as e:
            logger.error(f"Failed to connect to Galaxy API: {e}")
            raise

    async def get_workflow(self, workflow_id: str) -> Dict[str, Any]:
        """Get workflow definition from Galaxy"""
        response = await self.client.get(f'/workflows/{workflow_id}')
        response.raise_for_status()
        return response.json()

    async def get_dataset(self, dataset_id: str, history_id: Optional[str] = None) -> DatasetInfo:
        """Get dataset information from Galaxy"""
        endpoint = f'/datasets/{dataset_id}'
        if history_id:
            endpoint = f'/histories/{history_id}/contents/{dataset_id}'

        response = await self.client.get(endpoint)
        response.raise_for_status()
        data = response.json()

        return DatasetInfo(
            dataset_id=dataset_id,
            history_id=data.get('history_id', ''),
            name=data.get('name', ''),
            file_ext=data.get('extension', ''),
            file_size=data.get('file_size'),
            file_path=data.get('file_name')  # This might need adjustment based on Galaxy setup
        )

    async def get_collection(self, collection_id: str, history_id: Optional[str] = None) -> CollectionInfo:
        """Get collection information from Galaxy"""
        endpoint = f'/dataset_collections/{collection_id}'
        if history_id:
            endpoint = f'/histories/{history_id}/contents/dataset_collections/{collection_id}'

        response = await self.client.get(endpoint)
        response.raise_for_status()
        data = response.json()

        # Get collection elements
        elements = []
        for element in data.get('elements', []):
            if element.get('object', {}).get('history_content_type') == 'dataset':
                dataset_data = element['object']
                element_info = DatasetInfo(
                    dataset_id=dataset_data['id'],
                    history_id=dataset_data.get('history_id', ''),
                    name=dataset_data.get('name', ''),
                    file_ext=dataset_data.get('extension', ''),
                    file_size=dataset_data.get('file_size'),
                    file_path=dataset_data.get('file_name')
                )
                elements.append(element_info)

        return CollectionInfo(
            collection_id=collection_id,
            history_id=data.get('history_id', ''),
            name=data.get('name', ''),
            collection_type=data.get('collection_type', ''),
            elements=elements
        )

    async def update_invocation_status(self, invocation_id: str, status: str):
        """Update workflow invocation status"""
        data = {'state': status}
        response = await self.client.put(f'/invocations/{invocation_id}', json=data)
        response.raise_for_status()

    async def update_step_status(self, invocation_id: str, step_id: str, status: str, error_message: Optional[str] = None):
        """Update workflow step status"""
        data = {'state': status}
        if error_message:
            data['error_message'] = error_message

        response = await self.client.put(f'/invocations/{invocation_id}/steps/{step_id}', json=data)
        response.raise_for_status()

    async def create_dataset_from_file(self, file_path: str, name: str, ext: str, history_id: str):
        """Create a new dataset in Galaxy from a file"""
        # This is a simplified implementation
        # In practice, you'd need to handle file uploads properly
        data = {
            'name': name,
            'extension': ext,
            'file_path': file_path
        }
        response = await self.client.post(f'/histories/{history_id}/contents', json=data)
        response.raise_for_status()
        return response.json()

    async def close(self):
        """Close API client"""
        await self.client.aclose()