"""
Workflow Generator for Galaxy AI Assistant

Generates Galaxy workflow templates from decomposed tasks and tool recommendations.
"""

import json
import re
import uuid
from typing import Dict, List, Any, Optional, Tuple
from datetime import datetime
from .types import (
    Task, Tool, ToolRecommendation, WorkflowStep, WorkflowTemplate,
    UserRequest, TaskGraph
)
from .config import AIConfig
from .llm_client import LLMClient


class WorkflowGenerator:
    """Generates Galaxy workflow templates from tasks and tool recommendations."""
    
    def __init__(self, config: AIConfig):
        self.config = config
        self.llm_client = LLMClient(config)
    
    def generate_workflow(
        self,
        tasks: List[Task],
        tool_recommendations: Dict[str, List[ToolRecommendation]],
        user_request: UserRequest
    ) -> WorkflowTemplate:
        """Generate a complete workflow template."""
        
        # Create task dependency graph
        task_graph = self._create_task_graph(tasks)
        
        # Select best tools for each task
        selected_tools = self._select_tools_for_tasks(tasks, tool_recommendations)
        
        # Generate workflow steps
        workflow_steps = self._generate_workflow_steps(tasks, selected_tools, task_graph)
        
        # Determine workflow inputs and outputs
        workflow_inputs = self._determine_workflow_inputs(tasks, workflow_steps)
        workflow_outputs = self._determine_workflow_outputs(tasks, workflow_steps)
        
        # Generate workflow metadata
        workflow_name = self._generate_workflow_name(user_request, tasks)
        workflow_description = self._generate_workflow_description(user_request, tasks)
        workflow_tags = self._generate_workflow_tags(user_request, tasks)
        
        return WorkflowTemplate(
            name=workflow_name,
            description=workflow_description,
            steps=workflow_steps,
            inputs=workflow_inputs,
            outputs=workflow_outputs,
            tags=workflow_tags,
            created_at=datetime.now()
        )
    
    def _create_task_graph(self, tasks: List[Task]) -> TaskGraph:
        """Create a dependency graph from tasks."""
        graph = TaskGraph()
        
        for task in tasks:
            graph.add_task(task)
        
        for task in tasks:
            for dep_id in task.dependencies:
                graph.add_dependency(dep_id, task.id)
        
        return graph
    
    def _select_tools_for_tasks(
        self,
        tasks: List[Task],
        tool_recommendations: Dict[str, List[ToolRecommendation]]
    ) -> Dict[str, Tool]:
        """Select the best tool for each task."""
        selected_tools = {}
        
        for task in tasks:
            recommendations = tool_recommendations.get(task.id, [])
            if recommendations:
                # Select the highest confidence tool
                best_recommendation = max(recommendations, key=lambda r: r.confidence)
                selected_tools[task.id] = best_recommendation.tool
            else:
                # Create a placeholder tool if no recommendations
                selected_tools[task.id] = self._create_placeholder_tool(task)
        
        return selected_tools
    
    def _create_placeholder_tool(self, task: Task) -> Tool:
        """Create a placeholder tool when no recommendations are available."""
        return Tool(
            id=f"placeholder_{task.task_type.value}",
            name=f"Placeholder Tool for {task.name}",
            version="1.0.0",
            description=f"Placeholder tool for {task.description}",
            inputs=[{'name': 'input', 'type': dt.name} for dt in task.input_data_types],
            outputs=[{'name': 'output', 'type': dt.name} for dt in task.output_data_types],
            requirements=[]
        )
    
    def _generate_workflow_steps(
        self,
        tasks: List[Task],
        selected_tools: Dict[str, Tool],
        task_graph: TaskGraph
    ) -> List[WorkflowStep]:
        """Generate workflow steps from tasks and selected tools."""
        
        # Get execution order
        execution_order = task_graph.get_execution_order()
        
        steps = []
        step_id_map = {}  # Map task ID to step ID
        output_map = {}    # Map task ID to output dataset names
        
        for i, task_id in enumerate(execution_order):
            task = task_graph.nodes[task_id]
            tool = selected_tools[task_id]
            
            step_id = i + 1  # Galaxy steps are 1-indexed
            step_id_map[task_id] = step_id
            
            # Determine input connections
            input_connections = self._determine_input_connections(
                task, tool, step_id_map, output_map
            )
            
            # Generate tool parameters
            parameters = self._generate_tool_parameters(task, tool)
            
            # Calculate step position for workflow editor
            position = self._calculate_step_position(i, len(execution_order))
            
            step = WorkflowStep(
                step_id=step_id,
                tool_id=tool.id,
                tool_version=tool.version,
                input_connections=input_connections,
                parameters=parameters,
                annotation=f"{task.name}: {task.description}",
                position=position
            )
            
            steps.append(step)
            
            # Track outputs for subsequent steps
            output_map[task_id] = self._get_step_outputs(tool, step_id)
        
        return steps
    
    def _determine_input_connections(
        self,
        task: Task,
        tool: Tool,
        step_id_map: Dict[str, int],
        output_map: Dict[str, Dict[str, str]]
    ) -> Dict[str, Any]:
        """Determine input connections for a workflow step."""
        connections = {}
        
        # For each tool input, find the appropriate source
        for tool_input in tool.inputs:
            input_name = tool_input['name']
            input_type = tool_input['type']
            
            # Check if this input should come from a previous step
            source_found = False
            for dep_task_id in task.dependencies:
                if dep_task_id in output_map:
                    dep_outputs = output_map[dep_task_id]
                    
                    # Find matching output type
                    for output_name, output_type in dep_outputs.items():
                        if self._types_compatible(input_type, output_type):
                            connections[input_name] = {
                                'id': step_id_map[dep_task_id],
                                'output_name': output_name
                            }
                            source_found = True
                            break
                    
                    if source_found:
                        break
            
            # If no dependency provides this input, it's a workflow input
            if not source_found:
                # Check if this matches task input data types
                for input_data_type in task.input_data_types:
                    if self._types_compatible(input_type, input_data_type.name):
                        connections[input_name] = {
                            'id': None,  # Workflow input
                            'output_name': f"input_{input_data_type.name}"
                        }
                        break
        
        return connections
    
    def _generate_tool_parameters(self, task: Task, tool: Tool) -> Dict[str, Any]:
        """Generate default parameters for a tool based on the task."""
        parameters = {}
        
        # Use LLM to suggest appropriate parameters
        if self.config.auto_parameter_inference:
            parameters = self._llm_generate_parameters(task, tool)
        
        # Add any constraint-based parameters
        if hasattr(task, 'constraints'):
            constraints = getattr(task, 'constraints', {})
            
            # Memory constraints
            if constraints.get('memory_intensive'):
                if 'memory' in str(tool.description).lower():
                    parameters['memory_gb'] = 16
            
            # Quality vs speed trade-offs
            quality_priority = constraints.get('quality_priority')
            if quality_priority == 'high':
                parameters['quality_mode'] = 'high'
            elif quality_priority == 'speed':
                parameters['quality_mode'] = 'fast'
        
        return parameters
    
    def _llm_generate_parameters(self, task: Task, tool: Tool) -> Dict[str, Any]:
        """Use LLM to generate appropriate tool parameters."""
        schema = {
            "type": "object",
            "properties": {
                "parameters": {
                    "type": "object",
                    "additionalProperties": True
                }
            },
            "required": ["parameters"]
        }
        
        prompt = f"""
        Suggest appropriate parameters for this bioinformatics tool:
        
        Tool: {tool.name} ({tool.id})
        Description: {tool.description}
        
        Task Context:
        - Name: {task.name}
        - Description: {task.description}
        - Task Type: {task.task_type.value}
        - Intent: {task.intent_type.value}
        
        Provide sensible default parameters that would be appropriate for this task.
        Consider standard bioinformatics best practices.
        Only include parameters that are commonly adjusted and important for the analysis.
        
        Example parameter types: thread count, quality thresholds, algorithm settings, output formats.
        """
        
        try:
            response_text = self.llm_client.generate_structured(prompt, schema)
            # Parse the JSON response
            response = self._parse_json_response(response_text)
            return response.get('parameters', {})
        except Exception as e:
            print(f"Parameter generation failed: {e}")
            return {}

    def _parse_json_response(self, response_text: str) -> Dict[str, Any]:
        """Parse JSON response with error recovery."""

        # Check if response is empty or None
        if not response_text or not response_text.strip():
            raise ValueError("Empty or None response from LLM")

        # First try direct JSON parsing
        try:
            return json.loads(response_text.strip())
        except json.JSONDecodeError as original_error:
            print(f"Direct JSON parse failed: {original_error}")
            print(f"Response text (first 200 chars): {response_text[:200]}")

            # Try to extract JSON from markdown code blocks
            json_match = re.search(r'```(?:json)?\s*(\{.*?\})\s*```', response_text, re.DOTALL)
            if json_match:
                try:
                    return json.loads(json_match.group(1))
                except json.JSONDecodeError:
                    pass

            # Try to find JSON object in the text
            json_match = re.search(r'\{.*\}', response_text, re.DOTALL)
            if json_match:
                json_str = json_match.group()
                try:
                    return json.loads(json_str)
                except json.JSONDecodeError:
                    # Try to fix common JSON errors
                    fixed_json = self._fix_common_json_errors(json_str)
                    if fixed_json:
                        try:
                            return json.loads(fixed_json)
                        except json.JSONDecodeError:
                            pass

            raise ValueError(f"No valid JSON found in response. Original error: {original_error}")

    def _fix_common_json_errors(self, json_str: str) -> str:
        """Fix common JSON formatting errors."""
        # Remove trailing commas before closing brackets/braces
        json_str = re.sub(r',\s*([}\]])', r'\1', json_str)

        # Fix missing commas between array items (basic heuristic)
        json_str = re.sub(r'}\s*{', r'}, {', json_str)
        json_str = re.sub(r']\s*\[', r'], [', json_str)

        # Remove any trailing content after the main JSON object
        brace_count = 0
        for i, char in enumerate(json_str):
            if char == '{':
                brace_count += 1
            elif char == '}':
                brace_count -= 1
                if brace_count == 0:
                    json_str = json_str[:i+1]
                    break

        return json_str

    def _calculate_step_position(self, step_index: int, total_steps: int) -> Dict[str, int]:
        """Calculate position for workflow step in the editor."""
        # Arrange steps in a left-to-right flow
        x = 200 + (step_index * 300)
        y = 200 + (step_index % 3) * 150  # Stagger vertically for readability
        
        return {'left': x, 'top': y}
    
    def _get_step_outputs(self, tool: Tool, step_id: int) -> Dict[str, str]:
        """Get the output dataset names and types for a tool step."""
        outputs = {}
        
        for i, output in enumerate(tool.outputs):
            output_name = output.get('name', f'output_{i}')
            output_type = output.get('type', 'data')
            outputs[output_name] = output_type
        
        return outputs
    
    def _types_compatible(self, type1: str, type2: str) -> bool:
        """Check if two data types are compatible."""
        # Normalize types
        t1 = type1.lower().strip()
        t2 = type2.lower().strip()
        
        # Direct match
        if t1 == t2:
            return True
        
        # Common compatibility mappings
        compatibility_map = {
            'fastq': ['fastqsanger', 'fastqillumina'],
            'fasta': ['fa', 'fna', 'faa'],
            'bam': ['sam'],
            'tabular': ['csv', 'tsv', 'txt'],
            'gff': ['gff3', 'gtf']
        }
        
        for base_type, compatible_types in compatibility_map.items():
            if (t1 == base_type and t2 in compatible_types) or \
               (t2 == base_type and t1 in compatible_types):
                return True
        
        return False
    
    def _determine_workflow_inputs(
        self,
        tasks: List[Task],
        workflow_steps: List[WorkflowStep]
    ) -> List[Dict[str, Any]]:
        """Determine the required workflow inputs."""
        workflow_inputs = []
        input_data_types = set()
        
        # Collect all input data types from tasks
        for task in tasks:
            for input_type in task.input_data_types:
                input_data_types.add(input_type.name)
        
        # Create workflow input definitions
        for i, data_type in enumerate(sorted(input_data_types)):
            workflow_inputs.append({
                'label': f'Input {data_type.title()} Dataset',
                'name': f'input_{data_type}',
                'type': 'data',
                'format': data_type,
                'optional': False,
                'description': f'Input dataset in {data_type} format'
            })
        
        return workflow_inputs
    
    def _determine_workflow_outputs(
        self,
        tasks: List[Task],
        workflow_steps: List[WorkflowStep]
    ) -> List[Dict[str, Any]]:
        """Determine the workflow outputs."""
        workflow_outputs = []
        
        # The outputs are typically from the final steps
        # For now, mark all final step outputs as workflow outputs
        if workflow_steps:
            final_step = workflow_steps[-1]
            
            # Create output definitions
            for i, task in enumerate(tasks):
                if not any(task.id in other_task.dependencies for other_task in tasks):
                    # This task doesn't feed into other tasks - it's a final output
                    for output_type in task.output_data_types:
                        workflow_outputs.append({
                            'label': f'{task.name} Result',
                            'name': f'output_{output_type.name}',
                            'type': 'data',
                            'format': output_type.name,
                            'description': f'Output from {task.name}: {task.description}'
                        })
        
        return workflow_outputs
    
    def _generate_workflow_name(self, user_request: UserRequest, tasks: List[Task]) -> str:
        """Generate a descriptive name for the workflow."""
        
        # Extract key terms from request
        request_text = user_request.request_text
        
        # Use LLM to generate a concise name
        prompt = f"""
        Generate a concise, descriptive name for a bioinformatics workflow based on this request:
        
        User Request: "{request_text}"
        
        Tasks in workflow:
        {chr(10).join([f"- {task.name}" for task in tasks])}
        
        Generate a workflow name that is:
        1. 3-8 words long
        2. Descriptive of the main analysis
        3. Uses standard bioinformatics terminology
        4. Professional and clear
        
        Examples: "RNA-seq Differential Expression Analysis", "Genome Assembly and Annotation", "Variant Calling Pipeline"
        
        Respond with just the workflow name, no quotes or additional text.
        """
        
        try:
            name = self.llm_client.generate(prompt).strip().strip('"\'')
            return name
        except Exception:
            # Fallback to simple name generation
            main_task_types = list(set(task.task_type.value for task in tasks))
            return f"{' and '.join(main_task_types).title()} Workflow"
    
    def _generate_workflow_description(self, user_request: UserRequest, tasks: List[Task]) -> str:
        """Generate a detailed description for the workflow."""
        
        task_descriptions = []
        for i, task in enumerate(tasks, 1):
            task_descriptions.append(f"{i}. {task.name}: {task.description}")
        
        description = f"""
        Workflow generated from user request: "{user_request.request_text}"
        
        This workflow performs the following steps:
        {chr(10).join(task_descriptions)}
        
        Generated automatically by Galaxy AI Assistant.
        """
        
        return description.strip()
    
    def _generate_workflow_tags(self, user_request: UserRequest, tasks: List[Task]) -> List[str]:
        """Generate relevant tags for the workflow."""
        tags = ['ai-generated']
        
        # Add tags based on task types
        task_types = set(task.task_type.value for task in tasks)
        tags.extend(task_types)
        
        # Add tags based on intent types
        intent_types = set(task.intent_type.value for task in tasks)
        tags.extend(intent_types)
        
        # Add domain-specific tags
        request_text = user_request.request_text.lower()
        if 'rna' in request_text or 'transcriptome' in request_text:
            tags.append('rna-seq')
        if 'genome' in request_text:
            tags.append('genomics')
        if 'variant' in request_text or 'snp' in request_text:
            tags.append('variant-analysis')
        if 'assembly' in request_text:
            tags.append('assembly')
        
        return list(set(tags))  # Remove duplicates
    
    def export_to_galaxy_format(self, workflow_template: WorkflowTemplate) -> Dict[str, Any]:
        """Export workflow template to Galaxy's native workflow format."""
        
        galaxy_workflow = {
            'a_galaxy_workflow': 'true',
            'annotation': workflow_template.description,
            'format-version': '0.1',
            'name': workflow_template.name,
            'steps': {},
            'tags': workflow_template.tags,
            'uuid': str(uuid.uuid4()),
            'version': 1
        }
        
        # Add workflow input steps first
        input_step_id = 0
        input_step_mapping = {}  # Map input names/IDs to step IDs
        original_input_step_mapping = {}  # Map original step IDs to new step IDs
        
        for workflow_input in workflow_template.inputs:
            input_name = workflow_input.get('name', f'input_{input_step_id}')
            input_type = workflow_input.get('type', 'data')
            
            if input_type == 'data_collection':
                # Data collection input step
                collection_type = workflow_input.get('collection_type', 'list')
                formats = workflow_input.get('format', ['data'])
                
                galaxy_workflow['steps'][str(input_step_id)] = {
                    'id': input_step_id,
                    'type': 'data_collection_input',
                    'tool_id': None,
                    'tool_version': None,
                    'annotation': workflow_input.get('description', ''),
                    'input_connections': {},
                    'inputs': [{
                        'name': input_name,
                        'description': workflow_input.get('description', '')
                    }],
                    'label': workflow_input.get('label', input_name),
                    'name': 'Input dataset collection',
                    'outputs': [],
                    'position': {'left': input_step_id * 200, 'top': 100},
                    'post_job_actions': {},
                    'tool_state': json.dumps({
                        'collection_type': collection_type,
                        'format': formats,
                        'optional': workflow_input.get('optional', False)
                    }),
                    'uuid': str(uuid.uuid4()),
                    'workflow_outputs': []
                }
                
            elif input_type == 'parameter':
                # Parameter input step
                param_type = workflow_input.get('parameter_type', 'text')
                
                galaxy_workflow['steps'][str(input_step_id)] = {
                    'id': input_step_id,
                    'type': 'parameter_input',
                    'tool_id': None,
                    'tool_version': None,
                    'annotation': workflow_input.get('description', ''),
                    'input_connections': {},
                    'inputs': [{
                        'name': input_name,
                        'description': workflow_input.get('description', '')
                    }],
                    'label': workflow_input.get('label', input_name),
                    'name': 'Input parameter',
                    'outputs': [],
                    'position': {'left': input_step_id * 200, 'top': 200},
                    'post_job_actions': {},
                    'tool_state': json.dumps({
                        'parameter_type': param_type,
                        'optional': workflow_input.get('optional', False)
                    }),
                    'uuid': str(uuid.uuid4()),
                    'workflow_outputs': []
                }
                
            else:
                # Generic data input step
                galaxy_workflow['steps'][str(input_step_id)] = {
                    'id': input_step_id,
                    'type': 'data_input',
                    'tool_id': None,
                    'tool_version': None,
                    'annotation': workflow_input.get('description', ''),
                    'input_connections': {},
                    'inputs': [{
                        'name': input_name,
                        'description': workflow_input.get('description', '')
                    }],
                    'label': workflow_input.get('label', input_name),
                    'name': 'Input dataset',
                    'outputs': [],
                    'position': {'left': input_step_id * 200, 'top': 150},
                    'post_job_actions': {},
                    'tool_state': json.dumps({
                        'format': workflow_input.get('format', 'auto'),
                        'optional': workflow_input.get('optional', False)
                    }),
                    'uuid': str(uuid.uuid4()),
                    'workflow_outputs': []
                }
            
            # Map both input name and original input step ID to the new step ID
            input_step_mapping[input_name] = input_step_id
            
            # Extract original input step ID from input name if it follows the pattern input_X
            if input_name.startswith('input_') and input_name[6:].isdigit():
                original_step_id = int(input_name[6:])
                original_input_step_mapping[original_step_id] = input_step_id
            
            input_step_id += 1
        
        # Convert tool steps to Galaxy format
        # Ensure tool step IDs don't conflict with input step IDs
        for step in workflow_template.steps:
            # Adjust step ID to avoid conflicts with input steps
            adjusted_step_id = step.step_id + input_step_id
            # Update step connections to reference the newly created input steps
            updated_connections = {}
            workflow_inputs = {}
            
            for input_name, connection in step.input_connections.items():
                if isinstance(connection, dict) and str(connection.get('id', '')).startswith('workflow_input_'):
                    # This is a marked input step connection - reconnect to the actual input step
                    original_input_step = connection.get('_original_input_step')
                    
                    # Try to find the correct mapping using the original input step ID
                    if original_input_step is not None and original_input_step in original_input_step_mapping:
                        updated_connections[input_name] = {
                            'id': original_input_step_mapping[original_input_step],
                            'output_name': 'output'
                        }
                    else:
                        # Fallback: try to find by input step name
                        input_step_name = f'input_{original_input_step}' if original_input_step is not None else None
                        if input_step_name and input_step_name in input_step_mapping:
                            updated_connections[input_name] = {
                                'id': input_step_mapping[input_step_name],
                                'output_name': 'output'
                            }
                        else:
                            # Add as runtime parameter if input step not found
                            workflow_inputs[input_name] = {
                                'description': f"Runtime parameter for {connection.get('_input_label', input_name)}",
                                'optional': False
                            }
                elif connection.get('id') is None:
                    # This was originally a workflow input - add as runtime parameter
                    workflow_inputs[input_name] = {
                        'description': f"Runtime parameter for {input_name}",
                        'optional': False
                    }
                else:
                    # This is a valid step-to-step connection, adjust the referenced step ID
                    connection_copy = dict(connection)
                    if 'id' in connection_copy and isinstance(connection_copy['id'], int):
                        connection_copy['id'] = connection_copy['id'] + input_step_id
                    updated_connections[input_name] = connection_copy
            
            # Check if step has workflow_inputs attribute from cleaning
            if hasattr(step, 'workflow_inputs'):
                workflow_inputs.update(step.workflow_inputs)
            
            galaxy_workflow['steps'][str(adjusted_step_id)] = {
                'id': adjusted_step_id,
                'type': 'tool',
                'tool_id': step.tool_id,
                'tool_version': step.tool_version,
                'annotation': step.annotation,
                'input_connections': updated_connections,
                'inputs': workflow_inputs,
                'position': step.position,
                'post_job_actions': {},
                'tool_state': json.dumps(step.parameters),
                'uuid': str(uuid.uuid4()),
                'workflow_outputs': []
            }
        
        # CRITICAL: Final validation to ensure NO workflow_input_ markers remain
        # This prevents the "Invalid connection. Failed to find input step id workflow_input_X" error
        self._validate_and_clean_final_workflow(galaxy_workflow)
        
        return galaxy_workflow
    
    def _validate_and_clean_final_workflow(self, galaxy_workflow):
        """
        Final validation and cleanup to ensure no workflow_input_ markers remain.
        This is a safety net to prevent the workflow save error.
        """
        import logging
        log = logging.getLogger(__name__)
        
        # Check all steps for workflow_input_ markers
        problematic_connections = []
        all_step_ids = {int(step_id) for step_id in galaxy_workflow['steps'].keys()}
        
        for step_id, step_data in galaxy_workflow['steps'].items():
            input_connections = step_data.get('input_connections', {})
            
            for input_name, connection in input_connections.items():
                if isinstance(connection, dict) and 'id' in connection:
                    conn_id = connection['id']
                    
                    # Check for workflow_input_ markers
                    if isinstance(conn_id, str) and conn_id.startswith('workflow_input_'):
                        problematic_connections.append({
                            'step_id': step_id,
                            'input_name': input_name,
                            'connection': connection,
                            'marker_id': conn_id
                        })
                        
                        # Try to extract the original step ID and fix it
                        try:
                            # Extract the number from workflow_input_X
                            original_step_id = int(conn_id.split('_')[-1])
                            
                            # If we have an input step with this ID, connect to it
                            if original_step_id in all_step_ids:
                                log.warning(f"EMERGENCY FIX: Converting {conn_id} to step {original_step_id}")
                                connection['id'] = original_step_id
                            else:
                                # Find the first input step (tool_id is None)
                                for check_step_id, check_step_data in galaxy_workflow['steps'].items():
                                    if check_step_data.get('tool_id') is None:
                                        log.warning(f"EMERGENCY FIX: Converting {conn_id} to first input step {check_step_id}")
                                        connection['id'] = int(check_step_id)
                                        break
                                else:
                                    # If no input step found, remove the connection
                                    log.error(f"EMERGENCY FIX: Removing problematic connection {conn_id}")
                                    del input_connections[input_name]
                                    break
                                    
                        except (ValueError, IndexError):
                            # If we can't parse the marker, remove the connection
                            log.error(f"EMERGENCY FIX: Removing unparseable connection {conn_id}")
                            del input_connections[input_name]
                            break
                    
                    # Also check for connections to non-existent steps
                    elif isinstance(conn_id, (int, str)) and int(conn_id) not in all_step_ids:
                        log.error(f"EMERGENCY FIX: Connection to non-existent step {conn_id} in step {step_id}")
                        # Remove the problematic connection
                        del input_connections[input_name]
                        break
        
        if problematic_connections:
            log.error(f"FOUND AND FIXED {len(problematic_connections)} workflow_input_ markers in final workflow")
            for prob in problematic_connections:
                log.error(f"  - Step {prob['step_id']}.{prob['input_name']}: {prob['marker_id']}")
        else:
            log.debug("Final workflow validation passed - no workflow_input_ markers found")

    def generate_workflow_with_context(self, user_request_text: str, similar_workflows: List[Dict]) -> Dict[str, Any]:
        """
        Generate a custom workflow using LLM based on user request and similar workflows context.
        This is the Stage 2 LLM generation method.
        """
        import logging
        log = logging.getLogger(__name__)

        try:
            # Check if LLM client is available
            if not self.llm_client:
                log.warning("LLM client not available, using fallback generation")
                return self._generate_fallback_workflow(user_request_text, similar_workflows)

            # Prepare context from similar workflows
            context_summary = self._prepare_similar_workflows_context(similar_workflows)
            log.debug(f"Prepared context summary with {len(similar_workflows)} workflows")

            # Create LLM prompt for workflow generation
            llm_prompt = self._create_workflow_generation_prompt(user_request_text, context_summary)
            log.debug(f"Created LLM prompt with length: {len(llm_prompt)} characters")

            # Call LLM to generate workflow
            log.info(f"Calling LLM to generate workflow for: {user_request_text}")
            try:
                llm_response = self.llm_client.generate(llm_prompt, max_tokens=2000, temperature=0.7)
                log.info(f"LLM response received, length: {len(llm_response)} characters")
            except Exception as llm_error:
                log.error(f"LLM generation failed: {llm_error}")
                return self._generate_fallback_workflow(user_request_text, similar_workflows)

            # Parse LLM response and create workflow structure
            workflow_data = self._parse_llm_workflow_response(llm_response, user_request_text)
            log.info(f"Successfully generated workflow: {workflow_data.get('name', 'Unknown')}")

            return {
                "success": True,
                "workflow": workflow_data,
                "confidence": 0.85,
                "generation_method": "LLM_with_context"
            }

        except Exception as e:
            log.error(f"LLM workflow generation failed: {e}")
            return {
                "success": False,
                "error": str(e),
                "generation_method": "LLM_with_context"
            }

    def _prepare_similar_workflows_context(self, similar_workflows: List[Dict]) -> str:
        """Prepare context summary from similar workflows for LLM."""
        if not similar_workflows:
            return "No reference patterns available."

        context_parts = ["Reference workflow patterns (for conceptual guidance only):"]

        for i, workflow in enumerate(similar_workflows[:3], 1):
            name = workflow.get("name", f"Pattern {i}")
            description = workflow.get("description", "No description")
            tools = workflow.get("tools", [])

            # Focus on the APPROACH rather than specific implementation
            context_parts.append(f"\nPattern {i}: {name}")
            context_parts.append(f"   → Approach: {description[:150]}...")
            if tools:
                # Show tool categories rather than specific tools
                tool_categories = self._extract_tool_categories(tools[:5])
                context_parts.append(f"   → Common tool types: {', '.join(tool_categories)}")

        context_parts.append("\n💡 Use these as inspiration for workflow structure and approach, NOT as templates to copy!")
        return "\n".join(context_parts)

    def _extract_tool_categories(self, tools: List[str]) -> List[str]:
        """Extract tool categories from tool names to avoid copying specific tools."""
        categories = []
        for tool in tools:
            tool_lower = tool.lower()
            if any(word in tool_lower for word in ['fastq', 'quality', 'qc']):
                categories.append("Quality Control")
            elif any(word in tool_lower for word in ['trim', 'adapter']):
                categories.append("Preprocessing")
            elif any(word in tool_lower for word in ['map', 'align', 'bowtie', 'bwa', 'hisat']):
                categories.append("Alignment")
            elif any(word in tool_lower for word in ['count', 'expression', 'featurecounts']):
                categories.append("Quantification")
            elif any(word in tool_lower for word in ['deseq', 'differential', 'stats']):
                categories.append("Statistical Analysis")
            elif any(word in tool_lower for word in ['plot', 'visual', 'graph']):
                categories.append("Visualization")
            elif any(word in tool_lower for word in ['filter', 'select']):
                categories.append("Filtering")
            else:
                categories.append("Analysis")

        return list(set(categories))  # Remove duplicates

    def _create_workflow_generation_prompt(self, user_request: str, context: str) -> str:
        """Create LLM prompt for generating custom workflow."""
        return f"""You are an expert Galaxy bioinformatics workflow designer. Your task is to create a completely NEW and CUSTOM workflow specifically tailored to the user's unique requirements.

🎯 USER'S SPECIFIC REQUEST:
{user_request}

📚 REFERENCE PATTERNS (for inspiration only):
{context}

⚠️ IMPORTANT GUIDELINES:
1. FOCUS PRIMARILY on the user's specific request and requirements
2. DO NOT copy or replicate the reference workflows - use them ONLY for understanding common patterns
3. Design a workflow that directly addresses the user's stated goals
4. Be creative and innovative in your approach
5. Consider the most efficient and modern tools for the user's specific use case
6. Adapt the complexity based on what the user actually needs

🧠 THINKING PROCESS:
- What is the user trying to accomplish? (analyze their request deeply)
- What are the key steps needed to achieve their goal?
- What would be the most logical data flow for their specific case?
- Which modern Galaxy tools would be most appropriate?
- How can I make this workflow efficient and user-friendly?

📋 RESPONSE FORMAT (JSON):
{{
    "name": "Descriptive workflow name that reflects the user's specific goal",
    "description": "Clear explanation of what this custom workflow accomplishes for the user",
    "steps": [
        {{
            "id": 1,
            "tool_id": "appropriate_galaxy_tool_for_this_step",
            "annotation": "Clear explanation of what this step does in context of user's goal",
            "inputs": [{{"name": "input_name", "type": "data_type"}}],
            "outputs": [{{"name": "output_name", "type": "data_type"}}]
        }}
    ],
    "inputs": [{{"label": "User's input data description", "type": "appropriate_type"}}],
    "outputs": [{{"label": "Final result description", "type": "result_type"}}],
    "tags": ["custom", "user-specific", "relevant-domain-tags"]
}}

🚀 Now create a 3-7 step workflow that is SPECIFICALLY designed for: "{user_request}"

Remember: This should be a CUSTOM solution, not a copy of the reference patterns!"""

    def _parse_llm_workflow_response(self, llm_response: str, user_request: str) -> Dict[str, Any]:
        """Parse LLM response and create workflow structure."""
        try:
            # Try to extract JSON from LLM response
            import re
            json_match = re.search(r'\{.*\}', llm_response, re.DOTALL)

            if json_match:
                workflow_json = json.loads(json_match.group())
                return workflow_json
            else:
                raise ValueError("No JSON found in LLM response")

        except (json.JSONDecodeError, ValueError):
            # Fallback: create a basic workflow structure when JSON parsing fails
            return {
                "name": f"Custom Workflow: {user_request[:50]}...",
                "description": f"AI-generated custom workflow for: {user_request}",
                "steps": [
                    {
                        "id": 1,
                        "tool_id": "data_preparation",
                        "annotation": "Prepare input data",
                        "inputs": [],
                        "outputs": [{"name": "prepared_data", "type": "data"}]
                    },
                    {
                        "id": 2,
                        "tool_id": "main_analysis",
                        "annotation": f"Main analysis for: {user_request}",
                        "inputs": [{"name": "input_data", "type": "data"}],
                        "outputs": [{"name": "analysis_results", "type": "data"}]
                    },
                    {
                        "id": 3,
                        "tool_id": "results_formatting",
                        "annotation": "Format and visualize results",
                        "inputs": [{"name": "raw_results", "type": "data"}],
                        "outputs": [{"name": "final_output", "type": "data"}]
                    }
                ],
                "inputs": [{"label": "Input Dataset", "type": "data"}],
                "outputs": [{"label": "Analysis Results", "type": "data"}],
                "tags": ["ai-generated", "custom", "llm-created"]
            }

    def _generate_fallback_workflow(self, user_request_text: str, similar_workflows: List[Dict]) -> Dict[str, Any]:
        """Generate a fallback workflow when LLM is not available."""
        import logging
        log = logging.getLogger(__name__)

        log.info("Generating fallback workflow template")

        # Use the best similar workflow as a base if available
        base_workflow = None
        if similar_workflows:
            base_workflow = similar_workflows[0]  # Use the most similar one

        workflow_name = f"Custom Workflow: {user_request_text[:50]}..."
        if base_workflow:
            workflow_name = f"Enhanced {base_workflow.get('name', 'Workflow')}"

        # Create more specific fallback steps based on user request
        fallback_steps = self._create_adaptive_fallback_steps(user_request_text, base_workflow)

        fallback_workflow = {
            "name": workflow_name,
            "description": f"Custom workflow designed for: {user_request_text}" + (
                f" (Inspired by patterns from: {base_workflow.get('name', 'similar workflow')})" if base_workflow else ""
            ),
            "steps": fallback_steps,
            "inputs": [{"label": f"Input data for {user_request_text}", "type": "data"}],
            "outputs": [{"label": f"Results from {user_request_text}", "type": "data"}],
            "tags": ["ai-generated", "custom-workflow"] + self._extract_request_tags(user_request_text)
        }

        # Add tools from base workflow if available
        if base_workflow and base_workflow.get("tools"):
            fallback_workflow["recommended_tools"] = base_workflow["tools"][:5]

        return {
            "success": True,
            "workflow": fallback_workflow,
            "confidence": 0.7,
            "generation_method": "fallback_with_context"
        }

    def _create_adaptive_fallback_steps(self, user_request_text: str, base_workflow: Dict = None) -> List[Dict]:
        """Create adaptive fallback steps based on user request context."""
        request_lower = user_request_text.lower()

        # Determine workflow type from user request
        if any(word in request_lower for word in ['rna-seq', 'rna seq', 'transcriptome', 'expression']):
            return self._create_rna_seq_steps(user_request_text, base_workflow)
        elif any(word in request_lower for word in ['variant', 'mutation', 'snp', 'genome']):
            return self._create_variant_analysis_steps(user_request_text, base_workflow)
        elif any(word in request_lower for word in ['quality', 'qc', 'fastq']):
            return self._create_quality_control_steps(user_request_text, base_workflow)
        elif any(word in request_lower for word in ['assembly', 'assemble', 'contig']):
            return self._create_assembly_steps(user_request_text, base_workflow)
        else:
            return self._create_generic_analysis_steps(user_request_text, base_workflow)

    def _create_rna_seq_steps(self, user_request: str, base_workflow: Dict = None) -> List[Dict]:
        """Create RNA-seq specific workflow steps."""
        return [
            {
                "id": 1,
                "tool_id": "fastq_quality_assessment",
                "annotation": f"Quality assessment for RNA-seq data: {user_request}",
                "inputs": [],
                "outputs": [{"name": "quality_report", "type": "html"}]
            },
            {
                "id": 2,
                "tool_id": "read_trimming",
                "annotation": "Trim and filter RNA-seq reads",
                "inputs": [{"name": "raw_reads", "type": "fastq"}],
                "outputs": [{"name": "clean_reads", "type": "fastq"}]
            },
            {
                "id": 3,
                "tool_id": "rna_alignment",
                "annotation": "Align reads to reference transcriptome",
                "inputs": [{"name": "clean_reads", "type": "fastq"}],
                "outputs": [{"name": "alignments", "type": "bam"}]
            },
            {
                "id": 4,
                "tool_id": "expression_quantification",
                "annotation": f"Quantify expression levels for: {user_request}",
                "inputs": [{"name": "alignments", "type": "bam"}],
                "outputs": [{"name": "expression_matrix", "type": "tabular"}]
            }
        ]

    def _create_variant_analysis_steps(self, user_request: str, base_workflow: Dict = None) -> List[Dict]:
        """Create variant analysis specific workflow steps."""
        return [
            {
                "id": 1,
                "tool_id": "sequence_alignment",
                "annotation": f"Align sequences for variant analysis: {user_request}",
                "inputs": [],
                "outputs": [{"name": "alignments", "type": "bam"}]
            },
            {
                "id": 2,
                "tool_id": "variant_calling",
                "annotation": f"Call variants based on: {user_request}",
                "inputs": [{"name": "alignments", "type": "bam"}],
                "outputs": [{"name": "variants", "type": "vcf"}]
            },
            {
                "id": 3,
                "tool_id": "variant_annotation",
                "annotation": "Annotate and filter variants",
                "inputs": [{"name": "variants", "type": "vcf"}],
                "outputs": [{"name": "annotated_variants", "type": "vcf"}]
            }
        ]

    def _create_quality_control_steps(self, user_request: str, base_workflow: Dict = None) -> List[Dict]:
        """Create quality control specific workflow steps."""
        return [
            {
                "id": 1,
                "tool_id": "fastq_quality_check",
                "annotation": f"Initial quality assessment for: {user_request}",
                "inputs": [],
                "outputs": [{"name": "quality_metrics", "type": "html"}]
            },
            {
                "id": 2,
                "tool_id": "quality_filtering",
                "annotation": "Filter low-quality sequences",
                "inputs": [{"name": "raw_data", "type": "fastq"}],
                "outputs": [{"name": "filtered_data", "type": "fastq"}]
            },
            {
                "id": 3,
                "tool_id": "quality_summary",
                "annotation": "Generate quality summary report",
                "inputs": [{"name": "filtered_data", "type": "fastq"}],
                "outputs": [{"name": "summary_report", "type": "html"}]
            }
        ]

    def _create_assembly_steps(self, user_request: str, base_workflow: Dict = None) -> List[Dict]:
        """Create assembly specific workflow steps."""
        return [
            {
                "id": 1,
                "tool_id": "read_preprocessing",
                "annotation": f"Preprocess reads for assembly: {user_request}",
                "inputs": [],
                "outputs": [{"name": "clean_reads", "type": "fastq"}]
            },
            {
                "id": 2,
                "tool_id": "genome_assembly",
                "annotation": f"Assemble genome for: {user_request}",
                "inputs": [{"name": "clean_reads", "type": "fastq"}],
                "outputs": [{"name": "contigs", "type": "fasta"}]
            },
            {
                "id": 3,
                "tool_id": "assembly_evaluation",
                "annotation": "Evaluate assembly quality",
                "inputs": [{"name": "contigs", "type": "fasta"}],
                "outputs": [{"name": "assembly_stats", "type": "tabular"}]
            }
        ]

    def _create_generic_analysis_steps(self, user_request: str, base_workflow: Dict = None) -> List[Dict]:
        """Create generic analysis workflow steps."""
        return [
            {
                "id": 1,
                "tool_id": "data_preprocessing",
                "annotation": f"Prepare data for analysis: {user_request}",
                "inputs": [],
                "outputs": [{"name": "processed_data", "type": "data"}]
            },
            {
                "id": 2,
                "tool_id": "main_analysis",
                "annotation": f"Main analysis step for: {user_request}",
                "inputs": [{"name": "processed_data", "type": "data"}],
                "outputs": [{"name": "analysis_results", "type": "data"}]
            },
            {
                "id": 3,
                "tool_id": "results_visualization",
                "annotation": "Visualize and format results",
                "inputs": [{"name": "analysis_results", "type": "data"}],
                "outputs": [{"name": "final_output", "type": "data"}]
            }
        ]

    def _extract_request_tags(self, user_request_text: str) -> List[str]:
        """Extract relevant tags from user request."""
        request_lower = user_request_text.lower()
        tags = []

        if any(word in request_lower for word in ['rna', 'expression', 'transcriptome']):
            tags.append("rna-seq")
        if any(word in request_lower for word in ['variant', 'mutation', 'snp']):
            tags.append("variant-analysis")
        if any(word in request_lower for word in ['quality', 'qc']):
            tags.append("quality-control")
        if any(word in request_lower for word in ['assembly', 'genome']):
            tags.append("genome-assembly")
        if any(word in request_lower for word in ['protein', 'proteome']):
            tags.append("proteomics")
        if any(word in request_lower for word in ['microbiome', 'metagenom']):
            tags.append("metagenomics")

        return tags[:3]  # Limit to 3 tags