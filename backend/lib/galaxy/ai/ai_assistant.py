"""
Galaxy AI Assistant

Main orchestrator that combines all AI components to provide intelligent research assistance.
"""

import uuid
from typing import Dict, List, Any, Optional
from datetime import datetime

from .types import (
    UserRequest, AIResponse, Task, Tool, ToolRecommendation,
    WorkflowTemplate, WorkflowStep, IntentType, TaskType
)
from .config import AIConfig, DEFAULT_AI_CONFIG
from .intent_parser import IntentParser
from .task_decomposer import TaskDecomposer
from .tool_recommender import ToolRecommender
from .tool_discovery import ToolIndexer, ToolDiscoveryEngine
from .enhanced_workflow_generator import EnhancedWorkflowGenerator
from .workflow_templates import WorkflowTemplateLibrary
from .workflow_optimizer import WorkflowOptimizer, WorkflowValidator, OptimizationStrategy
# NEW: Unified workflow generation components
from .workflow_search_rag import WorkflowSearchRAG
from .galaxy_workflow_generator import GalaxyWorkflowGenerator
from .workflow_dataset_selector import WorkflowDatasetSelector
from .biomni_dataset_rag import BioMNIDatasetRAG
import logging

log = logging.getLogger(__name__)


class AIAssistant:
    """Main Galaxy AI Assistant that orchestrates the entire AI pipeline."""
    
    def __init__(self, config: Optional[AIConfig] = None, galaxy_app=None):
        self.config = config or DEFAULT_AI_CONFIG
        self.config.validate()

        self.galaxy_app = galaxy_app

        # Initialize AI components
        self.intent_parser = IntentParser(self.config)
        self.task_decomposer = TaskDecomposer(self.config)
        self.tool_recommender = ToolRecommender(self.config)
        self.workflow_generator = EnhancedWorkflowGenerator(self.config, galaxy_app)
        self.template_library = WorkflowTemplateLibrary()
        self.workflow_optimizer = WorkflowOptimizer(self.config)
        self.workflow_validator = WorkflowValidator(self.config)

        # Initialize tool discovery system
        self.tool_indexer = ToolIndexer(self.config)
        self.tool_discovery = ToolDiscoveryEngine(self.config, self.tool_indexer)

        # NEW: Initialize unified workflow generation components
        self.workflow_search = WorkflowSearchRAG(galaxy_app)
        self.constrained_generator = GalaxyWorkflowGenerator()
        self.dataset_selector = WorkflowDatasetSelector()
        self.dataset_rag = BioMNIDatasetRAG()

        log.info("AIAssistant initialized with unified workflow generation")
        log.info(f"  - Template library: {len(self.workflow_search.templates)} templates")
        log.info(f"  - Dataset catalog: {len(self.dataset_rag.dataset_index)} datasets")

        # Cache for frequently used data
        self._tool_cache = {}
        self._workflow_cache = {}

        # Initialize with Galaxy tools if available
        if galaxy_app:
            self._index_galaxy_tools()
    
    def process_request(self, user_request: UserRequest) -> AIResponse:
        """Process a complete user research request and generate AI response."""
        
        request_id = str(uuid.uuid4())
        warnings = []
        
        try:
            # Step 1: Parse user intent
            parsed_intent = self.intent_parser.parse_request(user_request)
            
            # Step 2: Decompose into tasks
            tasks = self.task_decomposer.decompose_request(user_request, parsed_intent)
            
            # Step 3: Get tool recommendations for each task
            tool_recommendations = {}
            for task in tasks:
                recommendations = self.tool_recommender.recommend_tools(task)
                tool_recommendations[task.id] = recommendations
            
            # Step 4: Generate workflow template using enhanced generator
            try:
                # First get workflow recommendations
                workflow_recommendations = self.workflow_generator.get_workflow_recommendations(user_request)
                
                if workflow_recommendations:
                    warnings.append(f"Found {len(workflow_recommendations)} workflow options")
                    
                    # Generate actual workflow template from the best recommendation
                    best_recommendation = workflow_recommendations[0]
                    try:
                        workflow_result = self.workflow_generator.generate_workflow(user_request)
                        workflow_template = self._convert_workflow_result_to_template(workflow_result, user_request)
                        is_valid = True
                        execution_plan = f"Generated workflow: {workflow_template.name if workflow_template else 'Unknown'} (confidence: {workflow_result.get('confidence', 0):.0%})"
                    except Exception as gen_error:
                        warnings.append(f"Workflow generation failed: {str(gen_error)}")
                        workflow_template = None
                        is_valid = False
                        execution_plan = f"Found {len(workflow_recommendations)} workflow options but failed to generate template"
                else:
                    workflow_template = None
                    is_valid = False
                    execution_plan = None
                    warnings.append("No suitable workflow recommendations found")
                    
            except Exception as e:
                workflow_template = None
                is_valid = False
                execution_plan = None
                warnings.append(f"Error generating workflow: {str(e)}")
            
            # Calculate overall confidence
            task_confidences = [task.confidence for task in tasks if task.confidence > 0]
            tool_confidences = [
                rec.confidence for recs in tool_recommendations.values() 
                for rec in recs if rec.confidence > 0
            ]
            
            all_confidences = task_confidences + tool_confidences
            overall_confidence = sum(all_confidences) / len(all_confidences) if all_confidences else 0.0
            
            # Flatten tool recommendations for response
            all_recommendations = []
            for recs in tool_recommendations.values():
                all_recommendations.extend(recs)
            
            # Create AI response - add workflow_recommendations as custom field
            ai_response = AIResponse(
                request_id=request_id,
                parsed_intent=parsed_intent['intent'],
                decomposed_tasks=tasks,
                tool_recommendations=all_recommendations,
                workflow_template=workflow_template if is_valid else None,
                confidence=overall_confidence,
                execution_plan=execution_plan,
                warnings=warnings
            )
            
            # Add workflow recommendations as custom attribute
            if 'workflow_recommendations' in locals() and workflow_recommendations:
                ai_response.workflow_recommendations = workflow_recommendations
            else:
                ai_response.workflow_recommendations = []
            
            return ai_response
            
        except Exception as e:
            # Return error response
            return AIResponse(
                request_id=request_id,
                parsed_intent=IntentType.UNKNOWN,
                decomposed_tasks=[],
                tool_recommendations=[],
                workflow_template=None,
                confidence=0.0,
                execution_plan=None,
                warnings=[f"Error processing request: {str(e)}"]
            )
    
    def suggest_similar_workflows(self, user_request: UserRequest) -> List[WorkflowTemplate]:
        """Suggest similar existing workflows based on user request."""

        # Parse intent to understand what user wants
        parsed_intent = self.intent_parser.parse_request(user_request)

        # In a real implementation, this would query a workflow database
        # For now, return empty list
        return []

    def generate_workflow_unified(self, user_intent: str, uploaded_datasets: Optional[List[str]] = None) -> Dict[str, Any]:
        """
        Unified workflow generation with search-first approach.

        This implements the complete architecture from UNIFIED_ARCHITECTURE_SUMMARY.md:
        1. Search existing templates (WorkflowSearchRAG)
        2. If high confidence (>0.8): Reuse workflow + update datasets
        3. If medium confidence (0.5-0.8): Use EnhancedWorkflowGenerator (adapt template)
        4. If low confidence (<0.5): Use GalaxyWorkflowGenerator (tool-constrained from scratch)
        5. Always assign datasets via WorkflowDatasetSelector

        Args:
            user_intent: Natural language description of workflow goal
            uploaded_datasets: Optional list of user-uploaded dataset IDs

        Returns:
            Dictionary containing:
            - success: bool
            - workflow_ga: Galaxy .ga JSON (if successful)
            - source: 'template_reuse' | 'template_adapt' | 'tool_constrained'
            - confidence: float (0-1)
            - message: str
            - datasets_assigned: bool
        """
        log.info(f"[UnifiedWorkflowGeneration] Starting for intent: {user_intent}")

        try:
            # Step 1: Search existing templates
            log.info("[UnifiedWorkflowGeneration] Step 1: Searching templates...")
            search_results = self.workflow_search.search(user_intent, limit=5)

            if not search_results:
                log.info("[UnifiedWorkflowGeneration] No templates found, will generate from scratch")
                score = 0.0
            else:
                score = search_results[0]['score']
                log.info(f"[UnifiedWorkflowGeneration] Best match: {search_results[0]['name']} (score: {score:.2f})")

            workflow_ga = None
            source = None
            datasets_assigned = False

            # Step 2: Decide strategy based on template match score
            if score > 0.8:
                # High confidence - reuse existing workflow
                log.info("[UnifiedWorkflowGeneration] High confidence match - reusing workflow")
                workflow = search_results[0]['workflow']
                source = 'template_reuse'

                # Extract workflow structure for dataset assignment
                workflow_steps = workflow.get('workflow_steps', [])

                # Assign datasets via WorkflowDatasetSelector
                log.info("[UnifiedWorkflowGeneration] Assigning datasets...")
                dataset_assignments = self.dataset_selector.select_datasets_for_workflow(
                    user_intent=user_intent,
                    workflow_structure=workflow_steps
                )

                # Build Galaxy .ga JSON with datasets
                workflow_ga = self._build_workflow_ga_from_template(workflow, dataset_assignments)
                datasets_assigned = True

                message = f"Reused existing workflow: {workflow['name']}"

            elif score > 0.5:
                # Medium confidence - adapt template using enhanced generator
                log.info("[UnifiedWorkflowGeneration] Medium confidence - adapting template")
                source = 'template_adapt'

                # Use enhanced generator (multi-strategy)
                user_request_obj = UserRequest(
                    request_id=str(uuid.uuid4()),
                    request_text=user_intent,
                    user_id="system",
                    timestamp=datetime.now()
                )

                workflow_result = self.workflow_generator.generate_workflow(user_request_obj)

                if workflow_result.get('success'):
                    workflow_data = workflow_result.get('workflow', {})
                    workflow_steps = workflow_data.get('steps', [])

                    # Add dataset assignment (enhanced generator doesn't do this)
                    log.info("[UnifiedWorkflowGeneration] Assigning datasets to adapted workflow...")
                    dataset_assignments = self.dataset_selector.select_datasets_for_workflow(
                        user_intent=user_intent,
                        workflow_structure=workflow_steps
                    )

                    workflow_ga = self._build_workflow_ga_from_generated(workflow_data, dataset_assignments)
                    datasets_assigned = True
                    message = f"Adapted workflow template with {len(workflow_steps)} steps"
                else:
                    raise Exception(f"Enhanced generator failed: {workflow_result.get('error')}")

            else:
                # Low confidence - generate from scratch with tool constraint
                log.info("[UnifiedWorkflowGeneration] Low confidence - generating from scratch with tool constraint")
                source = 'tool_constrained'

                # Use constrained generator (prevents hallucinated tools)
                result = self.constrained_generator.generate_workflow(
                    user_intent=user_intent,
                    max_tools_search=30
                )

                if result['success']:
                    workflow_ga = result['workflow_ga']
                    datasets_assigned = True  # Constrained generator includes dataset assignment
                    generated_parameters = result.get('generated_parameters', [])  # NEW: Get LLM-generated parameters
                    message = f"Generated new workflow with {len(result['workflow_structure']['steps'])} steps (tool-constrained)"
                else:
                    raise Exception(f"Constrained generator failed: {result['error']}")

            # Return success response
            return {
                'success': True,
                'workflow_ga': workflow_ga,
                'source': source,
                'confidence': score if score > 0 else 0.3,  # Default low confidence for scratch generation
                'message': message,
                'datasets_assigned': datasets_assigned,
                'template_match_score': score,
                'generated_parameters': generated_parameters  # NEW: Include LLM-generated parameters with confidence scores
            }

        except Exception as e:
            log.error(f"[UnifiedWorkflowGeneration] Error: {str(e)}", exc_info=True)
            return {
                'success': False,
                'error': str(e),
                'message': f"Workflow generation failed: {str(e)}"
            }

    def _build_workflow_ga_from_template(self, template: Dict, dataset_assignments: Dict) -> Dict:
        """
        Build Galaxy .ga workflow JSON from template with dataset assignments.

        Args:
            template: Template dictionary from WorkflowSearchRAG
            dataset_assignments: Dataset assignments from WorkflowDatasetSelector

        Returns:
            Galaxy .ga workflow JSON
        """
        # Extract template structure
        workflow_name = template.get('name', 'Generated Workflow')
        workflow_desc = template.get('description', '')
        workflow_steps = template.get('workflow_steps', [])

        # Build .ga format
        ga_workflow = {
            'a_galaxy_workflow': 'true',
            'annotation': workflow_desc,
            'format-version': '0.1',
            'name': workflow_name,
            'steps': {}
        }

        # Convert template steps to Galaxy .ga format
        for i, step in enumerate(workflow_steps):
            step_id = str(i)
            tool_id = step.get('tool_id', 'unknown')

            ga_workflow['steps'][step_id] = {
                'id': i,
                'tool_id': tool_id,
                'type': 'tool',
                'annotation': step.get('description', ''),
                'tool_state': {},
                'inputs': []
            }

            # Add dataset assignments for this step
            step_datasets = self._get_datasets_for_step(i, dataset_assignments)
            if step_datasets:
                ga_workflow['steps'][step_id]['inputs'] = step_datasets

        return ga_workflow

    def _build_workflow_ga_from_generated(self, workflow_data: Dict, dataset_assignments: Dict) -> Dict:
        """
        Build Galaxy .ga workflow JSON from enhanced generator output with dataset assignments.
        """
        # Similar to _build_workflow_ga_from_template
        # This is a simplified version - real implementation would be more complex
        workflow_name = workflow_data.get('name', 'Generated Workflow')
        workflow_desc = workflow_data.get('description', '')
        steps = workflow_data.get('steps', [])

        ga_workflow = {
            'a_galaxy_workflow': 'true',
            'annotation': workflow_desc,
            'format-version': '0.1',
            'name': workflow_name,
            'steps': {}
        }

        for i, step in enumerate(steps):
            step_id = str(i)
            ga_workflow['steps'][step_id] = step

            # Add dataset assignments
            step_datasets = self._get_datasets_for_step(i, dataset_assignments)
            if step_datasets:
                if 'inputs' not in ga_workflow['steps'][step_id]:
                    ga_workflow['steps'][step_id]['inputs'] = []
                ga_workflow['steps'][step_id]['inputs'].extend(step_datasets)

        return ga_workflow

    def _get_datasets_for_step(self, step_index: int, dataset_assignments: Dict) -> List[Dict]:
        """Extract dataset assignments for a specific step."""
        datasets = []
        workflow_steps = dataset_assignments.get('workflow_steps', [])

        for step_data in workflow_steps:
            if step_data.get('step') == step_index + 1:  # Steps are 1-indexed in assignments
                for dataset_info in step_data.get('datasets', []):
                    datasets.append({
                        'name': dataset_info.get('name', 'reference_db'),
                        'src': 'ldda',
                        'path': dataset_info.get('path', '')
                    })

        return datasets

    def explain_workflow(self, workflow_template: WorkflowTemplate) -> str:
        """Generate a human-readable explanation of a workflow."""
        
        explanation_parts = [
            f"Workflow: {workflow_template.name}",
            f"Description: {workflow_template.description}",
            "",
            "Steps:"
        ]
        
        for i, step in enumerate(workflow_template.steps, 1):
            tool_name = step.tool_id.replace('_', ' ').title()
            annotation = step.annotation or f"Execute {tool_name}"
            explanation_parts.append(f"{i}. {annotation}")
        
        explanation_parts.extend([
            "",
            f"Estimated runtime: {self._estimate_workflow_runtime(workflow_template)} minutes",
            f"Required inputs: {len(workflow_template.inputs)}",
            f"Expected outputs: {len(workflow_template.outputs)}"
        ])
        
        return "\n".join(explanation_parts)
    
    def get_tool_alternatives(self, tool_id: str, task_context: Optional[Task] = None) -> List[ToolRecommendation]:
        """Get alternative tools for a specific tool."""
        
        if task_context:
            # Use task context to find similar tools
            return self.tool_recommender.recommend_tools(task_context)
        else:
            # Find tools with similar functionality
            # This would query the tool discovery system
            return []
    
    def estimate_workflow_cost(self, workflow_template: WorkflowTemplate) -> Dict[str, Any]:
        """Estimate computational cost for workflow execution."""
        
        optimizer = WorkflowOptimizer(self.config)
        parallel_groups = optimizer._identify_parallel_groups(
            optimizer._build_dependency_graph(workflow_template.steps)
        )
        
        total_runtime = optimizer._estimate_total_runtime(workflow_template.steps, parallel_groups)
        peak_resources = optimizer._estimate_peak_resources(workflow_template.steps, parallel_groups)
        
        # Simple cost calculation (in a real system, this would use actual pricing)
        compute_cost = peak_resources.cores * total_runtime * 0.01  # $0.01 per core-minute
        storage_cost = peak_resources.disk_gb * 0.001  # $0.001 per GB
        
        return {
            'estimated_runtime_minutes': total_runtime,
            'peak_cores': peak_resources.cores,
            'peak_memory_gb': peak_resources.memory_gb,
            'peak_disk_gb': peak_resources.disk_gb,
            'estimated_compute_cost_usd': round(compute_cost, 2),
            'estimated_storage_cost_usd': round(storage_cost, 2),
            'total_estimated_cost_usd': round(compute_cost + storage_cost, 2)
        }
    
    def optimize_for_resources(
        self,
        workflow_template: WorkflowTemplate,
        max_cores: Optional[int] = None,
        max_memory_gb: Optional[float] = None
    ) -> WorkflowTemplate:
        """Optimize workflow to fit within resource constraints."""
        
        # Use resource-optimized strategy
        optimization_result = self.workflow_optimizer.optimize_workflow(
            workflow_template, OptimizationStrategy.MINIMIZE_RESOURCES
        )
        
        # Create new workflow template with optimized steps
        optimized_workflow = WorkflowTemplate(
            name=f"{workflow_template.name} (Resource Optimized)",
            description=f"{workflow_template.description}\n\nOptimized for resource efficiency.",
            steps=optimization_result.optimized_steps,
            inputs=workflow_template.inputs,
            outputs=workflow_template.outputs,
            tags=workflow_template.tags + ['resource-optimized'],
            created_at=datetime.now()
        )
        
        return optimized_workflow
    
    def _index_galaxy_tools(self):
        """Index available Galaxy tools for discovery."""
        
        if not self.galaxy_app:
            return
        
        try:
            # Get tools from Galaxy toolbox
            toolbox = getattr(self.galaxy_app, 'toolbox', None)
            if not toolbox:
                return
            
            for tool_id, tool in toolbox.tools():
                # Convert Galaxy tool to our Tool format
                galaxy_tool = self._convert_galaxy_tool(tool)
                if galaxy_tool:
                    self.tool_indexer.index_tool(galaxy_tool)
                    
        except Exception as e:
            print(f"Error indexing Galaxy tools: {e}")
    
    def _convert_galaxy_tool(self, galaxy_tool) -> Optional[Tool]:
        """Convert a Galaxy tool to our Tool format."""
        
        try:
            # Extract tool information
            tool_id = galaxy_tool.id
            name = galaxy_tool.name or tool_id
            version = getattr(galaxy_tool, 'version', 'unknown')
            description = getattr(galaxy_tool, 'description', '')
            
            # Extract inputs and outputs
            inputs = []
            outputs = []
            
            # This would need to be adapted based on Galaxy's actual tool structure
            # For now, create minimal tool representation
            
            return Tool(
                id=tool_id,
                name=name,
                version=version,
                description=description,
                inputs=inputs,
                outputs=outputs,
                requirements=[],
                edam_operations=[],
                edam_topics=[],
                citations=[]
            )
            
        except Exception as e:
            print(f"Error converting Galaxy tool {galaxy_tool.id}: {e}")
            return None
    
    def _create_execution_plan(self, optimization_result) -> str:
        """Create a human-readable execution plan."""
        
        plan_parts = [
            "Workflow Execution Plan:",
            f"- Total steps: {len(optimization_result.optimized_steps)}",
            f"- Parallel groups: {len(optimization_result.parallel_groups)}",
            f"- Estimated runtime: {optimization_result.estimated_total_runtime} minutes",
            f"- Peak resources: {optimization_result.estimated_peak_resources.cores} cores, "
            f"{optimization_result.estimated_peak_resources.memory_gb}GB memory",
            "",
            "Execution sequence:"
        ]
        
        for i, group in enumerate(optimization_result.parallel_groups, 1):
            if len(group) == 1:
                step_id = group[0]
                step = next(s for s in optimization_result.optimized_steps if s.step_id == step_id)
                plan_parts.append(f"{i}. Execute {step.tool_id}")
            else:
                plan_parts.append(f"{i}. Execute in parallel:")
                for step_id in group:
                    step = next(s for s in optimization_result.optimized_steps if s.step_id == step_id)
                    plan_parts.append(f"   - {step.tool_id}")
        
        if optimization_result.optimization_notes:
            plan_parts.extend(["", "Optimization notes:"])
            for note in optimization_result.optimization_notes:
                plan_parts.append(f"- {note}")
        
        return "\n".join(plan_parts)
    
    def _estimate_workflow_runtime(self, workflow_template: WorkflowTemplate) -> int:
        """Estimate total workflow runtime."""
        
        optimizer = WorkflowOptimizer(self.config)
        parallel_groups = optimizer._identify_parallel_groups(
            optimizer._build_dependency_graph(workflow_template.steps)
        )
        
        return optimizer._estimate_total_runtime(workflow_template.steps, parallel_groups)
    
    def _convert_workflow_result_to_template(self, workflow_result: Dict[str, Any], user_request: UserRequest) -> Optional[WorkflowTemplate]:
        """Convert workflow generation result to WorkflowTemplate object."""
        
        try:
            workflow_data = workflow_result.get('workflow', {})
            
            if not workflow_data:
                return None
            
            # Create WorkflowTemplate from the generated workflow
            
            # Convert steps if they exist
            steps = []
            if 'steps' in workflow_data:
                for step_data in workflow_data['steps']:
                    if isinstance(step_data, dict):
                        # Handle both old and new step formats
                        step_id = step_data.get('id', step_data.get('step_number', len(steps) + 1))
                        tool_id = step_data.get('tool_id', 'unknown')
                        
                        step = WorkflowStep(
                            step_id=step_id,
                            tool_id=tool_id,
                            tool_version=step_data.get('tool_version', 'latest'),
                            input_connections=step_data.get('input_connections', {}),
                            parameters=step_data.get('parameters', {}),
                            annotation=step_data.get('annotation', step_data.get('description', f'Step {step_id}')),
                            position=step_data.get('position', {'left': 200 + len(steps) * 300, 'top': 200})
                        )
                        steps.append(step)
            
            workflow_template = WorkflowTemplate(
                name=workflow_data.get('name', f'Generated Workflow for {user_request.request_text[:50]}'),
                description=workflow_data.get('description', f'AI-generated workflow for: {user_request.request_text}'),
                steps=steps,
                inputs=workflow_data.get('inputs', []),
                outputs=workflow_data.get('outputs', []),
                tags=workflow_data.get('tags', ['ai-generated']),
                created_at=datetime.now()
            )
            
            return workflow_template
            
        except Exception as e:
            print(f"Error converting workflow result to template: {e}")
            return None
    
    def get_status(self) -> Dict[str, Any]:
        """Get AI assistant status and statistics."""
        
        return {
            'config': self.config.to_dict(),
            'components': {
                'intent_parser': 'ready',
                'task_decomposer': 'ready',
                'tool_recommender': 'ready',
                'workflow_generator': 'ready',
                'workflow_optimizer': 'ready',
                'tool_discovery': 'ready'
            },
            'cache_stats': {
                'tools_cached': len(self._tool_cache),
                'workflows_cached': len(self._workflow_cache)
            },
            'ready': True
        }