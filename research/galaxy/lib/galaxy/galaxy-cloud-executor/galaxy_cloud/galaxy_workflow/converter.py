"""
Galaxy Workflow Converter

Converts Galaxy workflows (.ga format) into cloud-executable job specifications.
"""

import json
import logging
from typing import Dict, List, Optional
from pathlib import Path
from dataclasses import dataclass

from galaxy_cloud.core.job import JobSpec, ResourceSpec, ContainerSpec
from .tool_registry import GalaxyToolRegistry
from .tool_executor import GalaxyToolExecutor
from .models import WorkflowDAG, WorkflowStep, StepDependency

logger = logging.getLogger(__name__)


@dataclass
class GalaxyWorkflowSpec:
    """Galaxy workflow specification"""
    workflow_id: str
    name: str
    version: str
    steps: Dict[str, Dict]
    connections: List[Dict]
    inputs: Dict[str, Dict]
    outputs: Dict[str, Dict]
    annotation: Optional[str] = None


class GalaxyWorkflowConverter:
    """
    Converts Galaxy workflows to cloud-executable job specifications.

    This class handles:
    - Parsing Galaxy .ga format workflows
    - Resolving tool dependencies and containers
    - Building execution DAG
    - Generating JobSpec objects for each step
    """

    def __init__(self, tool_registry: GalaxyToolRegistry, config: Optional[Dict] = None):
        self.tool_registry = tool_registry
        self.config = config or {}

        # Initialize tool executor with local tool directory if provided
        local_tool_dir = self.config.get('local_tool_dir') or self.config.get('tool_executor', {}).get('local_tool_dir')
        self.tool_executor = GalaxyToolExecutor(local_tool_dir=local_tool_dir)

        self.logger = logging.getLogger(f"{self.__class__.__module__}.{self.__class__.__name__}")

    def load_workflow_from_file(self, workflow_path: Path) -> GalaxyWorkflowSpec:
        """Load Galaxy workflow from .ga file"""
        try:
            with open(workflow_path, 'r', encoding='utf-8') as f:
                workflow_data = json.load(f)

            return self._parse_workflow_data(workflow_data)

        except Exception as e:
            self.logger.error(f"Failed to load workflow from {workflow_path}: {e}")
            raise

    def load_workflow_from_dict(self, workflow_data: Dict) -> GalaxyWorkflowSpec:
        """Load Galaxy workflow from dictionary"""
        return self._parse_workflow_data(workflow_data)

    def _parse_workflow_data(self, data: Dict) -> GalaxyWorkflowSpec:
        """Parse Galaxy workflow data structure"""
        # Handle nested workflow_json structure (from workflow files with metadata)
        if 'workflow_json' in data and isinstance(data['workflow_json'], dict):
            workflow_data = data['workflow_json']
            # Merge metadata if available
            if 'metadata' in data:
                metadata = data['metadata']
                workflow_id = metadata.get('id', workflow_data.get('uuid', 'unknown'))
                name = metadata.get('name', workflow_data.get('name', 'Unnamed Workflow'))
            else:
                workflow_id = workflow_data.get('uuid', workflow_data.get('id', 'unknown'))
                name = workflow_data.get('name', 'Unnamed Workflow')
        else:
            # Standard Galaxy workflow format
            workflow_data = data
            workflow_id = data.get('uuid', data.get('id', 'unknown'))
            name = data.get('name', 'Unnamed Workflow')

        return GalaxyWorkflowSpec(
            workflow_id=workflow_id,
            name=name,
            version=str(workflow_data.get('version', '1.0')),
            steps=workflow_data.get('steps', {}),
            connections=self._extract_connections(workflow_data),
            inputs=self._extract_inputs(workflow_data),
            outputs=self._extract_outputs(workflow_data),
            annotation=workflow_data.get('annotation')
        )

    def _extract_connections(self, data: Dict) -> List[Dict]:
        """Extract step connections from workflow data"""
        connections = []

        for step_id, step_data in data.get('steps', {}).items():
            input_connections = step_data.get('input_connections', {})

            for input_name, connection_info in input_connections.items():
                if isinstance(connection_info, list):
                    # Multiple connections to same input
                    for conn in connection_info:
                        connections.append({
                            'from_step': str(conn['id']),
                            'from_output': conn['output_name'],
                            'to_step': step_id,
                            'to_input': input_name
                        })
                elif isinstance(connection_info, dict):
                    # Single connection
                    connections.append({
                        'from_step': str(connection_info['id']),
                        'from_output': connection_info['output_name'],
                        'to_step': step_id,
                        'to_input': input_name
                    })

        return connections

    def _extract_inputs(self, data: Dict) -> Dict[str, Dict]:
        """Extract workflow inputs"""
        inputs = {}

        for step_id, step_data in data.get('steps', {}).items():
            if step_data.get('type') == 'data_input':
                inputs[step_id] = {
                    'label': step_data.get('label', f'Input {step_id}'),
                    'annotation': step_data.get('annotation', ''),
                    'format': step_data.get('tool_state', {}).get('format', 'auto'),
                    'optional': step_data.get('tool_state', {}).get('optional', False)
                }

        return inputs

    def _extract_outputs(self, data: Dict) -> Dict[str, Dict]:
        """Extract workflow outputs"""
        outputs = {}

        for step_id, step_data in data.get('steps', {}).items():
            workflow_outputs = step_data.get('workflow_outputs', [])

            for output in workflow_outputs:
                output_name = output.get('output_name', 'output')
                outputs[f"{step_id}_{output_name}"] = {
                    'step_id': step_id,
                    'output_name': output_name,
                    'label': output.get('label', f'Output from step {step_id}')
                }

        return outputs

    async def convert_to_dag(self, workflow_spec: GalaxyWorkflowSpec) -> WorkflowDAG:
        """Convert Galaxy workflow to execution DAG"""
        steps = {}
        dependencies = []

        # Create workflow steps
        for step_id, step_data in workflow_spec.steps.items():
            step = await self._create_workflow_step(step_id, step_data)
            steps[step_id] = step

        # Create dependencies
        for connection in workflow_spec.connections:
            dep = StepDependency(
                from_step=connection['from_step'],
                to_step=connection['to_step'],
                from_output=connection['from_output'],
                to_input=connection['to_input']
            )
            dependencies.append(dep)

        return WorkflowDAG(
            workflow_id=workflow_spec.workflow_id,
            name=workflow_spec.name,
            steps=steps,
            dependencies=dependencies,
            inputs=workflow_spec.inputs,
            outputs=workflow_spec.outputs
        )

    async def _create_workflow_step(self, step_id: str, step_data: Dict) -> WorkflowStep:
        """Create a workflow step from Galaxy step data"""
        step_type = step_data.get('type', 'tool')

        if step_type == 'data_input':
            return self._create_input_step(step_id, step_data)
        elif step_type == 'data_collection_input':
            return self._create_collection_input_step(step_id, step_data)
        elif step_type == 'tool':
            return await self._create_tool_step(step_id, step_data)
        elif step_type == 'subworkflow':
            return self._create_subworkflow_step(step_id, step_data)
        else:
            self.logger.warning(f"Unknown step type: {step_type} for step {step_id}")
            return self._create_generic_step(step_id, step_data)

    def _create_input_step(self, step_id: str, step_data: Dict) -> WorkflowStep:
        """Create input data step"""
        return WorkflowStep(
            step_id=step_id,
            name=step_data.get('label', f'Input {step_id}'),
            step_type='input',
            tool_id=None,
            job_spec=None,  # Input steps don't need job specs
            inputs={},
            outputs={'output': {'type': 'dataset'}},
            annotation=step_data.get('annotation', '')
        )

    def _create_collection_input_step(self, step_id: str, step_data: Dict) -> WorkflowStep:
        """Create collection input step"""
        return WorkflowStep(
            step_id=step_id,
            name=step_data.get('label', f'Collection Input {step_id}'),
            step_type='collection_input',
            tool_id=None,
            job_spec=None,
            inputs={},
            outputs={'output': {'type': 'collection'}},
            annotation=step_data.get('annotation', '')
        )

    async def _create_tool_step(self, step_id: str, step_data: Dict) -> WorkflowStep:
        """Create tool execution step"""
        tool_id = step_data.get('tool_id', '')

        # Get container info for the tool
        container_info = await self.tool_registry.get_tool_container(tool_id)

        if not container_info:
            self.logger.warning(f"No container found for tool {tool_id}, using default")
            container_info = self.tool_registry.get_default_container()

        # Parse tool state for parameters
        tool_state = step_data.get('tool_state', {})
        if isinstance(tool_state, str):
            try:
                tool_state = json.loads(tool_state)
            except json.JSONDecodeError:
                tool_state = {}

        # Create job specification
        job_spec = await self._create_job_spec_for_tool(
            step_id, tool_id, tool_state, container_info, step_data
        )

        return WorkflowStep(
            step_id=step_id,
            name=step_data.get('label', f'Tool {tool_id}'),
            step_type='tool',
            tool_id=tool_id,
            job_spec=job_spec,
            inputs=self._extract_step_inputs(step_data),
            outputs=self._extract_step_outputs(step_data),
            annotation=step_data.get('annotation', '')
        )

    def _create_subworkflow_step(self, step_id: str, step_data: Dict) -> WorkflowStep:
        """Create subworkflow step"""
        return WorkflowStep(
            step_id=step_id,
            name=step_data.get('label', f'Subworkflow {step_id}'),
            step_type='subworkflow',
            tool_id=None,
            job_spec=None,  # Subworkflows are handled separately
            inputs=self._extract_step_inputs(step_data),
            outputs=self._extract_step_outputs(step_data),
            annotation=step_data.get('annotation', ''),
            subworkflow_id=step_data.get('subworkflow', {}).get('id')
        )

    def _create_generic_step(self, step_id: str, step_data: Dict) -> WorkflowStep:
        """Create generic step for unknown types"""
        return WorkflowStep(
            step_id=step_id,
            name=step_data.get('label', f'Step {step_id}'),
            step_type=step_data.get('type', 'unknown'),
            tool_id=step_data.get('tool_id'),
            job_spec=None,
            inputs=self._extract_step_inputs(step_data),
            outputs=self._extract_step_outputs(step_data),
            annotation=step_data.get('annotation', '')
        )

    async def _create_job_spec_for_tool(self, step_id: str, tool_id: str, tool_state: Dict,
                                 container_info, step_data: Dict) -> JobSpec:
        """Create JobSpec for a Galaxy tool

        Args:
            container_info: ToolContainerInfo object or dict with container information
            step_data: Full step data from workflow for context
        """

        # Build full image name
        if hasattr(container_info, 'image'):
            full_image = container_info.image
            if hasattr(container_info, 'tag') and container_info.tag:
                if ':' not in full_image:
                    full_image = f"{full_image}:{container_info.tag}"
            base_command = container_info.command if hasattr(container_info, 'command') else None
            working_dir = container_info.working_dir if hasattr(container_info, 'working_dir') else '/data'
        else:
            full_image = container_info['image']
            base_command = container_info.get('command')
            working_dir = container_info.get('working_dir', '/data')

        # Try to build actual Galaxy tool command
        tool_command_info = await self.tool_executor.build_tool_command(
            tool_id=tool_id,
            tool_state=tool_state,
            input_files={},  # Will be filled in by DAG executor
            output_files={}  # Will be filled in by DAG executor
        )

        # Build container specification
        if tool_command_info and tool_command_info.get('command'):
            # Use the actual Galaxy tool command
            self.logger.info(f"Using Galaxy tool command for {tool_id}: {tool_command_info['command'][:100]}")
            container_spec = ContainerSpec(
                image=full_image,
                command=["/bin/bash", "-c"],
                args=[tool_command_info['command']],
                env=container_info.env if hasattr(container_info, 'env') else {},
                working_dir=tool_command_info.get('working_dir', working_dir)
            )
        else:
            # Fallback to simple args-based approach
            self.logger.warning(f"Could not build Galaxy tool command for {tool_id}, using fallback")
            container_spec = ContainerSpec(
                image=full_image,
                command=base_command,
                args=self._build_tool_args(tool_state),
                env=container_info.env if hasattr(container_info, 'env') else {},
                working_dir=working_dir
            )

        # Determine resource requirements
        resource_spec = self._determine_resource_requirements(tool_id)

        return JobSpec(
            job_id=f"galaxy-{step_id}-{tool_id.replace('/', '-')}",
            name=f"Galaxy Tool: {tool_id}",
            container=container_spec,
            resources=resource_spec,
            timeout_seconds=self._get_tool_timeout(tool_id),
            retry_attempts=2,
            labels={
                'galaxy_step_id': step_id,
                'galaxy_tool_id': tool_id,
                'workflow_step': 'true'
            }
        )

    def _build_tool_args(self, tool_state: Dict) -> List[str]:
        """Build command line arguments for Galaxy tool"""
        # This is a simplified implementation
        # In reality, this would need to parse Galaxy tool XML and build proper command line
        args = []

        # Add tool state parameters as arguments
        for param_name, param_value in tool_state.items():
            if param_name.startswith('__'):
                continue  # Skip Galaxy internal parameters

            if isinstance(param_value, bool):
                if param_value:
                    args.extend([f'--{param_name}'])
            elif param_value:
                args.extend([f'--{param_name}', str(param_value)])

        return args

    def _determine_resource_requirements(self, tool_id: str) -> ResourceSpec:
        """Determine resource requirements for a tool"""
        # Default resource requirements
        default_resources = ResourceSpec(
            cpus=1,
            memory_mb=2048,
            disk_gb=10
        )

        # Get tool-specific requirements from registry
        tool_resources = self.tool_registry.get_tool_resources(tool_id)
        if tool_resources:
            return ResourceSpec(
                cpus=tool_resources.get('cpus', default_resources.cpus),
                memory_mb=tool_resources.get('memory_mb', default_resources.memory_mb),
                disk_gb=tool_resources.get('disk_gb', default_resources.disk_gb),
                gpu=tool_resources.get('gpu'),
                gpu_type=tool_resources.get('gpu_type')
            )

        return default_resources

    def _get_tool_timeout(self, tool_id: str) -> int:
        """Get timeout for tool execution"""
        # Default timeout of 1 hour
        default_timeout = 3600

        # Get tool-specific timeout from registry
        tool_config = self.tool_registry.get_tool_config(tool_id)
        if tool_config and 'timeout' in tool_config:
            return tool_config['timeout']

        return default_timeout

    def _extract_step_inputs(self, step_data: Dict) -> Dict[str, Dict]:
        """Extract step input specifications"""
        inputs = {}

        # Parse input connections
        input_connections = step_data.get('input_connections', {})
        for input_name, connection in input_connections.items():
            inputs[input_name] = {
                'type': 'dataset',  # Default type
                'optional': False,
                'connection': connection
            }

        return inputs

    def _extract_step_outputs(self, step_data: Dict) -> Dict[str, Dict]:
        """Extract step output specifications"""
        outputs = {}

        # Default output for tools
        if step_data.get('type') == 'tool':
            outputs['output'] = {'type': 'dataset'}

        # Parse workflow outputs
        workflow_outputs = step_data.get('workflow_outputs', [])
        for output in workflow_outputs:
            output_name = output.get('output_name', 'output')
            outputs[output_name] = {
                'type': 'dataset',
                'label': output.get('label', ''),
                'workflow_output': True
            }

        return outputs

    def convert_workflow_to_jobs(self, workflow_spec: GalaxyWorkflowSpec) -> List[JobSpec]:
        """Convert Galaxy workflow to list of JobSpec objects"""
        dag = self.convert_to_dag(workflow_spec)
        job_specs = []

        for step_id, step in dag.steps.items():
            if step.job_spec:  # Only tool steps have job specs
                job_specs.append(step.job_spec)

        return job_specs

    def get_execution_order(self, workflow_spec: GalaxyWorkflowSpec) -> List[List[str]]:
        """Get step execution order based on dependencies"""
        dag = self.convert_to_dag(workflow_spec)
        return self._topological_sort(dag)

    def _topological_sort(self, dag: WorkflowDAG) -> List[List[str]]:
        """Perform topological sort to determine execution order"""
        # Build dependency graph
        graph = {step_id: set() for step_id in dag.steps.keys()}
        in_degree = {step_id: 0 for step_id in dag.steps.keys()}

        for dep in dag.dependencies:
            graph[dep.from_step].add(dep.to_step)
            in_degree[dep.to_step] += 1

        # Kahn's algorithm for topological sorting
        result = []
        queue = [step_id for step_id, degree in in_degree.items() if degree == 0]

        while queue:
            current_level = queue[:]
            queue = []
            result.append(current_level)

            for step_id in current_level:
                for neighbor in graph[step_id]:
                    in_degree[neighbor] -= 1
                    if in_degree[neighbor] == 0:
                        queue.append(neighbor)

        return result