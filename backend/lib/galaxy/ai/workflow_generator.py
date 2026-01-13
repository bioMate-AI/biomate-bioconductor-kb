"""
Workflow Generator for Galaxy AI Assistant

Generates Galaxy workflow templates from decomposed tasks and tool recommendations.
"""

import json
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
            
            # Detect tool type and container requirement
            tool_type = getattr(tool, 'tool_type', 'default')
            requires_container = tool.requires_containerization() if hasattr(tool, 'requires_containerization') else (tool_type not in ['data_source', 'data_source_async'])

            step = WorkflowStep(
                step_id=step_id,
                tool_id=tool.id,
                tool_version=tool.version,
                input_connections=input_connections,
                parameters=parameters,
                annotation=f"{task.name}: {task.description}",
                position=position,
                tool_type=tool_type,
                requires_container=requires_container
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

        # Get parameter schema from tool metadata
        parameter_schema = tool.get_parameter_schema_for_llm() if hasattr(tool, 'get_parameter_schema_for_llm') else "No parameter information available."

        # Get help text and examples if available
        help_info = ""
        if hasattr(tool, 'help_text') and tool.help_text:
            if isinstance(tool.help_text, dict):
                what_it_does = tool.help_text.get('what_it_does', '')
                how_to_use = tool.help_text.get('how_to_use', '')
                if what_it_does:
                    help_info += f"\nWhat it does: {what_it_does}"
                if how_to_use:
                    help_info += f"\nHow to use: {how_to_use}"
            else:
                help_info = f"\nHelp: {tool.help_text}"

        examples_info = ""
        if hasattr(tool, 'examples') and tool.examples:
            examples_info = f"\n\nUsage Examples:\n" + "\n".join([f"  - {ex}" for ex in tool.examples[:3]])

        usage_guide = ""
        if hasattr(tool, 'usage_guide') and tool.usage_guide:
            usage_guide = f"\n\nUsage Guide: {tool.usage_guide}"

        prompt = f"""
        Generate appropriate parameters for this bioinformatics tool based on the task context.

        Tool: {tool.name} ({tool.id})
        Description: {tool.description}
        {help_info}

        {parameter_schema}
        {examples_info}
        {usage_guide}

        Task Context:
        - Name: {task.name}
        - Description: {task.description}
        - Task Type: {task.task_type.value}
        - Intent: {task.intent_type.value}

        IMPORTANT INSTRUCTIONS:
        1. Use ONLY parameter names from the "Available Parameters" list above.
        2. For API/database query tools with both 'prompt' and 'endpoint' parameters:
           - PREFER using 'endpoint' with a properly constructed API URL when the query is specific
           - Only use 'prompt' for truly ambiguous natural language queries
        3. Generate values appropriate for the task description.
        4. Include required parameters, and optional ones only if needed.
        5. Return ONLY valid parameter name-value pairs as JSON.

        Example: For a UniProt query about "BRCA1 human protein":
        - Use endpoint: "https://rest.uniprot.org/uniprotkb/search?query=gene:BRCA1+AND+organism_id:9606&format=json"
        - NOT prompt: "Find information about BRCA1 human protein"
        """

        try:
            response = self.llm_client.generate_structured(prompt, schema)
            return response.get('parameters', {})
        except Exception as e:
            print(f"Parameter generation failed: {e}")
            return {}
    
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
        
        # Convert steps to Galaxy format
        for step in workflow_template.steps:
            # Separate workflow inputs from step-to-step connections
            valid_connections = {}
            workflow_inputs = {}
            
            for input_name, connection in step.input_connections.items():
                if connection.get('id') is None:
                    # This is a workflow input - add to workflow inputs instead of connections
                    workflow_inputs[input_name] = {
                        'description': f"Input {connection.get('output_name', input_name)} for {step.annotation}",
                        'optional': False
                    }
                else:
                    # This is a valid step-to-step connection
                    valid_connections[input_name] = connection
            
            galaxy_workflow['steps'][str(step.step_id)] = {
                'id': step.step_id,
                'type': 'tool',
                'tool_id': step.tool_id,
                'tool_version': step.tool_version,
                'annotation': step.annotation,
                'input_connections': valid_connections,
                'inputs': workflow_inputs,
                'position': step.position,
                'post_job_actions': {},
                'tool_state': json.dumps(step.parameters)
            }
        
        return galaxy_workflow