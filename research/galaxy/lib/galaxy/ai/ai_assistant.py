"""
Galaxy AI Assistant

Main orchestrator that combines all AI components to provide intelligent research assistance.
"""

import uuid
from typing import Dict, List, Any, Optional
from datetime import datetime

from .types import (
    UserRequest, AIResponse, Task, Tool, ToolRecommendation,
    WorkflowTemplate, WorkflowStep, IntentType
)
from .config import AIConfig, DEFAULT_AI_CONFIG
from .intent_parser import IntentParser
from .task_decomposer import TaskDecomposer
from .tool_recommender import ToolRecommender
from .tool_discovery import ToolIndexer, ToolDiscoveryEngine
from .workflow_generator import WorkflowGenerator
from .rag_workflow_loader import RAGWorkflowRecommender
from .workflow_templates import WorkflowTemplateLibrary
from .workflow_optimizer import WorkflowOptimizer, WorkflowValidator, OptimizationStrategy


class AIAssistant:
    """Main Galaxy AI Assistant that orchestrates the entire AI pipeline."""
    
    def __init__(self, config: Optional[AIConfig] = None, galaxy_app=None, crawler_data_path: str = None):
        self.config = config or DEFAULT_AI_CONFIG
        self.config.validate()
        
        self.galaxy_app = galaxy_app
        
        # Initialize AI components
        self.intent_parser = IntentParser(self.config)
        self.task_decomposer = TaskDecomposer(self.config)
        self.tool_recommender = ToolRecommender(self.config)
        # Use basic workflow generator as fallback
        self.workflow_generator = WorkflowGenerator(self.config)

        # Initialize RAG workflow recommender if crawler data is available
        self.rag_recommender = None
        print(f"🔍 DEBUG: Initializing RAG with crawler_data_path = {crawler_data_path}")
        if crawler_data_path:
            try:
                self.rag_recommender = RAGWorkflowRecommender(crawler_data_path)
                print(f"✅ RAG workflow recommender initialized successfully")
                print(f"🔍 DEBUG: RAG system status = {self.rag_recommender is not None}")
                if self.rag_recommender:
                    workflow_count = len(self.rag_recommender.workflows)
                    print(f"🔍 DEBUG: Loaded {workflow_count} workflows for RAG")
            except Exception as e:
                print(f"❌ Warning: Could not initialize RAG recommender: {e}")
                import traceback
                traceback.print_exc()
        else:
            print(f"❌ Warning: No crawler_data_path provided, RAG system disabled")
        
        self.template_library = WorkflowTemplateLibrary()
        self.workflow_optimizer = WorkflowOptimizer(self.config)
        self.workflow_validator = WorkflowValidator(self.config)
        
        # Initialize tool discovery system
        self.tool_indexer = ToolIndexer(self.config)
        self.tool_discovery = ToolDiscoveryEngine(self.config, self.tool_indexer)
        
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
            
            # Step 4: Generate workflow template - prioritize RAG approach
            workflow_template = None
            is_valid = False
            execution_plan = None
            workflow_recommendations = []
            
            try:
                # Step 1: Always get workflow recommendations first (for user to choose from)
                if self.rag_recommender:
                    rag_result = self.rag_recommender.get_workflow_recommendations(user_request.request_text, max_recommendations=5)

                    if rag_result.get("status") == "success" and rag_result.get("recommendations"):
                        workflow_recommendations = rag_result["recommendations"]
                        # Don't automatically generate workflow - let user choose
                        is_valid = False  # No workflow generated yet
                        execution_plan = f"Found {len(workflow_recommendations)} similar workflow recommendations"
                        warnings.append(f"Retrieved {len(workflow_recommendations)} similar workflows for your review")
                    else:
                        warnings.append("No similar workflows found in RAG database")
                        workflow_recommendations = []
                else:
                    # Fallback to basic workflow generator
                    warnings.append("RAG system not available, using basic workflow recommendations")
                    workflow_recommendations = []
                        
            except Exception as e:
                workflow_template = None
                is_valid = False
                execution_plan = None
                warnings.append(f"Error in workflow generation: {str(e)}")
            
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
    
    def generate_custom_workflow(self, user_request: UserRequest) -> AIResponse:
        """
        Generate a custom workflow based on user prompt (Step 2 of the two-step process).
        This is called when user is not satisfied with recommended workflows and wants a new one.
        """
        request_id = str(uuid.uuid4())
        warnings = []
        workflow_template = None
        is_valid = False
        execution_plan = None

        try:
            # Parse user intent
            parsed_intent = self.intent_parser.parse_intent(user_request)

            # Decompose request into tasks
            tasks = self.task_decomposer.decompose_request(user_request, parsed_intent)
            if not tasks:
                warnings.append("Could not decompose request into actionable tasks")
                return AIResponse(
                    request_id=request_id,
                    parsed_intent=parsed_intent.get('intent', IntentType.UNKNOWN),
                    decomposed_tasks=[],
                    tool_recommendations=[],
                    workflow_template=None,
                    confidence=0.0,
                    execution_plan="Failed to decompose request",
                    warnings=warnings
                )

            # Get tool recommendations for each task
            tool_recommendations = {}
            for task in tasks:
                recommendations = self.tool_recommender.recommend_tools(task)
                tool_recommendations[task.id] = recommendations

            # Force pure LLM generation (no RAG, no template matching)
            try:
                # Use pure LLM generation method
                workflow_result = self.workflow_generator.generate_pure_llm_workflow(user_request)
                workflow_template = self._convert_workflow_result_to_template(workflow_result, user_request)
                is_valid = True
                execution_plan = f"Pure LLM-generated workflow: {workflow_template.name if workflow_template else 'Unknown'} (confidence: {workflow_result.get('confidence', 0):.0%})"
                warnings.append("Generated completely new custom workflow using AI without any template bias")
            except Exception as gen_error:
                warnings.append(f"Pure LLM workflow generation failed: {str(gen_error)}")
                workflow_template = None
                is_valid = False
                execution_plan = "Pure LLM workflow generation failed"

            # Calculate confidence
            overall_confidence = sum(task.confidence for task in tasks) / len(tasks) if tasks else 0

            # Collect all tool recommendations
            all_recommendations = []
            for recommendations in tool_recommendations.values():
                all_recommendations.extend(recommendations)

            ai_response = AIResponse(
                request_id=request_id,
                parsed_intent=parsed_intent.get('intent', IntentType.UNKNOWN),
                decomposed_tasks=tasks,
                tool_recommendations=all_recommendations,
                workflow_template=workflow_template if is_valid else None,
                confidence=overall_confidence,
                execution_plan=execution_plan,
                warnings=warnings
            )

            ai_response.workflow_recommendations = []  # No recommendations for custom generation
            return ai_response

        except Exception as e:
            return AIResponse(
                request_id=request_id,
                parsed_intent=IntentType.UNKNOWN,
                decomposed_tasks=[],
                tool_recommendations=[],
                workflow_template=None,
                confidence=0.0,
                execution_plan=None,
                warnings=[f"Error generating custom workflow: {str(e)}"]
            )

    def suggest_similar_workflows(self, user_request: UserRequest) -> List[WorkflowTemplate]:
        """Suggest similar existing workflows based on user request."""
        
        # Parse intent to understand what user wants
        parsed_intent = self.intent_parser.parse_request(user_request)

        # In a real implementation, this would query a workflow database
        # based on parsed_intent
        # For now, return empty list
        return []
    
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
    
    def get_tool_alternatives(self, target_tool_id: str, task_context: Optional[Task] = None) -> List[ToolRecommendation]:
        """Get alternative tools for a specific tool."""
        
        if task_context:
            # Use task context to find similar tools to target_tool_id
            alternatives = self.tool_recommender.recommend_tools(task_context)
            # Filter to exclude the target tool itself
            return [alt for alt in alternatives if alt.tool.id != target_tool_id]
        else:
            # Find tools with similar functionality to target_tool_id
            # This would query the tool discovery system for alternatives
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

        # Use resource-optimized strategy with constraints
        constraints = {}
        if max_cores is not None:
            constraints['max_cores'] = max_cores
        if max_memory_gb is not None:
            constraints['max_memory_gb'] = max_memory_gb

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
            
            for _, tool in toolbox.tools():
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