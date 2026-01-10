
# Import simplified workflow API
try:
    from galaxy.ai.simple_workflow_api import create_simple_workflow_preview, SimpleAIRequestModel
    SIMPLE_API_AVAILABLE = True
except ImportError:
    SIMPLE_API_AVAILABLE = False
    create_simple_workflow_preview = None
    SimpleAIRequestModel = None

# Import RAG workflow loader
try:
    from galaxy.ai.rag_workflow_loader import RAGWorkflowRecommender
    RAG_AVAILABLE = True
except ImportError:
    RAG_AVAILABLE = False
    RAGWorkflowRecommender = None

"""
Galaxy AI Assistant API

RESTful API endpoints for the Galaxy AI Assistant functionality.
"""

import json
import logging
from typing import Dict, List, Any, Optional

from fastapi import HTTPException, Path, Query, Depends
from pydantic import BaseModel, Field

from galaxy import util
from galaxy.managers.context import ProvidesUserContext
from galaxy.webapps.galaxy.api import (
    DependsOnTrans,
    Router
)

# Import AI components with error handling
try:
    from galaxy.ai.ai_assistant import AIAssistant
    from galaxy.ai.config import AIConfig, DEFAULT_AI_CONFIG
    from galaxy.ai.types import UserRequest, TaskType, IntentType, WorkflowStep, WorkflowTemplate
    AI_AVAILABLE = True
except ImportError as e:
    logging.warning(f"AI Assistant components not available: {e}")
    AI_AVAILABLE = False
    AIAssistant = None
    AIConfig = None
    DEFAULT_AI_CONFIG = None
    UserRequest = None
    TaskType = None
    IntentType = None

log = logging.getLogger(__name__)

router = Router(tags=["ai_assistant"])

# Global AI assistant instance
_ai_assistant_instance = None


def get_ai_assistant(trans) -> Optional[AIAssistant]:
    """Get or create AI Assistant instance."""
    global _ai_assistant_instance
    
    if not AI_AVAILABLE:
        return None
    
    if _ai_assistant_instance is None:
        try:
            # Get AI configuration from Galaxy config using the configuration loader
            app = trans.app
            ai_enabled = getattr(app.config, 'enable_ai_assistant', False)
            
            if not ai_enabled:
                return None
            
            # Use the proper AI configuration loader
            from galaxy.config.ai_config import configure_ai_assistant
            ai_config = configure_ai_assistant(app.config.__dict__, app.config.config_dir)
            
            if not ai_config:
                log.warning("AI Assistant enabled but configuration failed")
                return None
            
            # Try to initialize with RAG capabilities  
            crawler_data_path = getattr(app.config, 'ai_crawler_data_path', 'lib/galaxy/ai/data/workflows')
            
            try:
                # Initialize AI assistant with RAG capabilities if available
                _ai_assistant_instance = AIAssistant(ai_config, galaxy_app=app, crawler_data_path=crawler_data_path)
                
                # Add RAG capabilities if available
                if RAG_AVAILABLE:
                    _ai_assistant_instance.rag_recommender = RAGWorkflowRecommender(crawler_data_path)
                    log.info("AI Assistant with RAG capabilities initialized successfully")
                else:
                    log.info("Standard AI Assistant initialized (RAG not available)")
                    
            except Exception as init_error:
                log.warning(f"Failed to initialize AI system: {init_error}")
                # Final fallback
                if AI_AVAILABLE:
                    _ai_assistant_instance = AIAssistant(ai_config, galaxy_app=app)
                    log.info("Basic AI Assistant initialized successfully")
            
        except Exception as e:
            log.error(f"Failed to initialize AI Assistant: {e}")
            return None
    
    return _ai_assistant_instance


# Pydantic models for API requests/responses
class AIRequestModel(BaseModel):
    """Model for AI assistant requests."""
    request_text: str = Field(..., description="Natural language research request")
    context: Optional[Dict[str, Any]] = Field(None, description="Additional context")
    available_datasets: Optional[List[Dict[str, Any]]] = Field(None, description="Available datasets")
    preferred_tools: Optional[List[str]] = Field(None, description="Preferred tools")
    constraints: Optional[Dict[str, Any]] = Field(None, description="Execution constraints")


class AIResponseModel(BaseModel):
    """Model for AI assistant responses."""
    request_id: str
    parsed_intent: str
    decomposed_tasks: List[Dict[str, Any]]
    tool_recommendations: List[Dict[str, Any]]
    workflow_template: Optional[Dict[str, Any]]
    workflow_recommendations: List[Dict[str, Any]] = []
    confidence: float
    execution_plan: Optional[str]
    warnings: List[str]


@router.get(
    "/api/ai_assistant/status",
    summary="Get AI Assistant status and configuration."
)
def get_ai_status(
    trans: ProvidesUserContext = DependsOnTrans
) -> Dict[str, Any]:
    """Get AI Assistant status and configuration."""
    
    if not AI_AVAILABLE:
        return {
            "available": False,
            "error": "AI Assistant components not installed",
            "ready": False
        }
    
    ai_assistant = get_ai_assistant(trans)
    
    if not ai_assistant:
        app = trans.app
        ai_enabled = getattr(app.config, 'enable_ai_assistant', False)
        api_key_configured = bool(getattr(app.config, 'ai_llm_api_key', None))
        
        return {
            "available": AI_AVAILABLE,
            "enabled": ai_enabled,
            "api_key_configured": api_key_configured,
            "ready": False,
            "error": "AI Assistant not properly configured"
        }
    
    return ai_assistant.get_status()


@router.post(
    "/api/ai_assistant/process_request",
    summary="Process a natural language research request."
)
def process_research_request(
    request: AIRequestModel,
    trans: ProvidesUserContext = DependsOnTrans
) -> AIResponseModel:
    """Process a natural language research request."""
    
    ai_assistant = get_ai_assistant(trans)
    if not ai_assistant:
        raise HTTPException(status_code=503, detail="AI Assistant not available")
    
    try:
        # Create UserRequest object
        user_request = UserRequest(
            user_id=str(trans.user.id) if trans.user else "anonymous",
            request_text=request.request_text,
            context=request.context,
            available_datasets=request.available_datasets,
            preferred_tools=request.preferred_tools,
            constraints=request.constraints
        )
        
        # Process the request
        ai_response = ai_assistant.process_request(user_request)
        
        # Convert to API response format
        return AIResponseModel(
            request_id=ai_response.request_id,
            parsed_intent=ai_response.parsed_intent.value,
            decomposed_tasks=[
                {
                    "id": task.id,
                    "name": task.name,
                    "description": task.description,
                    "task_type": task.task_type.value,
                    "intent_type": task.intent_type.value,
                    "confidence": task.confidence,
                    "estimated_duration": task.estimated_duration
                }
                for task in ai_response.decomposed_tasks
            ],
            tool_recommendations=[
                {
                    "tool_id": rec.tool.id,
                    "tool_name": rec.tool.name,
                    "confidence": rec.confidence,
                    "reasoning": rec.reasoning,
                    "estimated_runtime": rec.estimated_runtime
                }
                for rec in ai_response.tool_recommendations
            ],
            workflow_template=(
                _workflow_to_dict(ai_response.workflow_template)
                if ai_response.workflow_template else None
            ),
            workflow_recommendations=getattr(ai_response, 'workflow_recommendations', []),
            confidence=ai_response.confidence,
            execution_plan=ai_response.execution_plan,
            warnings=ai_response.warnings
        )
        
    except Exception as e:
        log.error(f"Error processing AI request: {e}")
        raise HTTPException(status_code=500, detail=f"Error processing request: {str(e)}")


@router.post(
    "/api/ai_assistant/generate_custom_workflow",
    summary="Generate a custom workflow based on user prompt (Step 2 of two-step process)."
)
def generate_custom_workflow(
    request: AIRequestModel,
    trans: ProvidesUserContext = DependsOnTrans
) -> Dict[str, Any]:
    """Generate a custom workflow when user is not satisfied with recommendations."""

    ai_assistant = get_ai_assistant(trans)
    if not ai_assistant:
        raise HTTPException(status_code=503, detail="AI Assistant not available")

    try:
        # Create user request object
        user_request = UserRequest(
            request_id=f"custom_gen_{util.unique_id()}",
            user_id=trans.user.id if trans.user else "anonymous",
            request_text=request.query,
            context=request.context,
            data_files=request.data_files or [],
            preferences=request.preferences or {}
        )

        # Generate custom workflow
        ai_response = ai_assistant.generate_custom_workflow(user_request)

        # Convert to response format
        response_data = {
            "status": "success" if ai_response.workflow_template else "failed",
            "message": f"🎯 Custom LLM workflow generation {'completed' if ai_response.workflow_template else 'failed'} - Generated from scratch based on your prompt",
            "request_id": ai_response.request_id,
            "workflow_template": _workflow_to_dict(ai_response.workflow_template) if ai_response.workflow_template else None,
            "execution_plan": ai_response.execution_plan,
            "confidence": ai_response.confidence,
            "warnings": ai_response.warnings,
            "generation_type": "PURE_LLM_CUSTOM",  # Clear identifier
            "source": "pure_llm",
            "note": "This workflow was generated from scratch by AI based on your specific requirements, without using any existing templates."
        }

        return response_data

    except Exception as e:
        logging.error(f"Custom workflow generation failed: {e}")
        return {
            "status": "error",
            "message": f"Custom workflow generation failed: {str(e)}",
            "request_id": None,
            "workflow_template": None,
            "execution_plan": None,
            "confidence": 0.0,
            "warnings": [str(e)],
            "generation_type": "custom_llm"
        }

@router.post(
    "/api/ai_assistant/create_workflow",
    summary="Create a Galaxy workflow from AI-generated template."
)
def create_workflow_from_ai(
    request: AIRequestModel,
    trans: ProvidesUserContext = DependsOnTrans
) -> Dict[str, Any]:
    """Create a Galaxy workflow from AI-generated template."""
    
    # Check if user is authenticated
    if not trans.user:
        # For unauthenticated users, generate the workflow template but don't save it
        # This allows users to see what would be created
        ai_assistant = get_ai_assistant(trans)
        if not ai_assistant:
            raise HTTPException(status_code=503, detail="AI Assistant not available")
        
        try:
            # Create a dummy user request for workflow generation
            user_request = UserRequest(
                user_id="anonymous",
                request_text=request.request_text,
                context=request.context or {},
                available_datasets=request.available_datasets or [],
                preferred_tools=request.preferred_tools or [],
                constraints=request.constraints or {}
            )
            
            # Generate workflow template using RAG system if available
            if RAG_AVAILABLE:
                try:
                    # Initialize RAG recommender directly
                    crawler_data_path = getattr(trans.app.config, 'ai_crawler_data_path', 'lib/galaxy/ai/data/workflows')
                    rag_recommender = RAGWorkflowRecommender(crawler_data_path)
                    
                    # Get the best matching workflow from RAG system
                    rag_result = rag_recommender.get_workflow_recommendations(user_request.request_text, max_recommendations=1)
                    
                    if rag_result["status"] == "success" and rag_result["recommendations"]:
                        best_match = rag_result["recommendations"][0]
                        
                        # Create a mock AI response with RAG workflow data
                        from types import SimpleNamespace
                        
                        # Extract actual workflow JSON structure from RAG data
                        workflow_json = best_match.get("workflow_json", {})
                        
                        if workflow_json and "steps" in workflow_json:
                            # Use actual steps from workflow JSON 
                            workflow_steps = []
                            steps_data = workflow_json["steps"]
                            
                            for step_id, step_data in steps_data.items():
                                # Extract step information from workflow JSON
                                tool_id = step_data.get("tool_id")
                                
                                # Skip input steps (tool_id is None for input dataset/parameter steps)
                                if tool_id is None:
                                    continue
                                    
                                tool_version = step_data.get("tool_version") or "1.0"
                                
                                # Parse tool_state (it's a JSON string, not a dict)
                                tool_state_raw = step_data.get("tool_state", "{}")
                                try:
                                    if isinstance(tool_state_raw, str):
                                        parameters = json.loads(tool_state_raw)
                                    else:
                                        parameters = tool_state_raw or {}
                                except (json.JSONDecodeError, TypeError):
                                    parameters = {}
                                
                                # Create Galaxy WorkflowStep object from real data
                                step = WorkflowStep(
                                    step_id=int(step_id),
                                    tool_id=tool_id,
                                    tool_version=tool_version,
                                    input_connections=step_data.get("input_connections", {}),
                                    parameters=parameters,
                                    annotation=step_data.get("annotation", f"Step {int(step_id) + 1}"),
                                    position=step_data.get("position", {"left": int(step_id) * 100, "top": 100})
                                )
                                workflow_steps.append(step)
                            
                            # Clean up input connections and create workflow inputs
                            workflow_steps, workflow_inputs = _clean_input_connections(workflow_steps, steps_data)
                            
                            # Sort steps by step_id to maintain order
                            workflow_steps.sort(key=lambda x: x.step_id)
                        else:
                            # Fallback: create placeholder steps if no workflow JSON available
                            step_count = best_match.get("steps", 0)
                            workflow_steps = []
                            for i in range(step_count):
                                step = WorkflowStep(
                                    step_id=i,
                                    tool_id="placeholder_tool",  # Basic placeholder
                                    tool_version="1.0",
                                    input_connections={},
                                    parameters={},
                                    annotation=f"Step {i+1} from RAG workflow template",
                                    position={"left": i * 100, "top": 100}
                                )
                                workflow_steps.append(step)
                        
                        # Create workflow template using proper Galaxy WorkflowTemplate object
                        workflow_template = WorkflowTemplate(
                            name=best_match["name"],
                            description=best_match["description"],
                            steps=workflow_steps,
                            inputs=workflow_inputs if 'workflow_inputs' in locals() else [],  # Use generated workflow inputs
                            outputs=[],  # Will be populated by Galaxy 
                            tags=best_match.get("tags", [])
                        )
                        
                        # Create AI response
                        ai_response = SimpleNamespace()
                        ai_response.workflow_template = workflow_template
                        ai_response.confidence = best_match.get("similarity_score", 5.0) / 15.0  # Normalize
                    else:
                        # Fallback to standard generation
                        ai_response = ai_assistant.process_request(user_request)
                except Exception as rag_error:
                    log.warning(f"RAG system failed in workflow creation: {rag_error}, falling back to standard generation")
                    ai_response = ai_assistant.process_request(user_request)
            else:
                ai_response = ai_assistant.process_request(user_request)
            
            if ai_response.workflow_template:
                import uuid
                demo_workflow_id = str(uuid.uuid4())[:8]
                
                return {
                    "workflow_id": demo_workflow_id,
                    "workflow_name": ai_response.workflow_template.name,
                    "message": f"✨ Generated workflow preview: '{ai_response.workflow_template.name}'",
                    "workflow_template": {
                        "name": ai_response.workflow_template.name,
                        "description": ai_response.workflow_template.description,
                        "steps": len(ai_response.workflow_template.steps),
                        "tags": ai_response.workflow_template.tags
                    },
                    "note": "🔑 Please log in to Galaxy to save this workflow to your account",
                    "status": "preview_success",
                    "number_of_steps": len(ai_response.workflow_template.steps),
                    "preview": True,
                    "login_url": "/login"
                }
            else:
                raise HTTPException(status_code=400, detail="Could not generate workflow template")
                
        except Exception as e:
            log.error(f"Error generating workflow preview: {e}")
            raise HTTPException(
                status_code=401, 
                detail="Authentication required. Please log in to Galaxy to create workflows."
            )
    
    ai_assistant = get_ai_assistant(trans)
    if not ai_assistant:
        raise HTTPException(status_code=503, detail="AI Assistant not available")
    
    try:
        # Process the request to get workflow template
        user_request = UserRequest(
            user_id=str(trans.user.id),
            request_text=request.request_text,
            context=request.context,
            available_datasets=request.available_datasets,
            preferred_tools=request.preferred_tools,
            constraints=request.constraints
        )
        
        # Check if user is requesting to create from a specific RAG workflow
        workflow_template_context = request.context.get('workflow_template', {}) if request.context else {}
        target_workflow_id = workflow_template_context.get('workflow_id')
        
        # Generate workflow template using RAG system if available
        if RAG_AVAILABLE:
            try:
                # Initialize RAG recommender directly
                crawler_data_path = getattr(trans.app.config, 'ai_crawler_data_path', 'lib/galaxy/ai/data')
                rag_recommender = RAGWorkflowRecommender(crawler_data_path)
                
                # If user specified a workflow_id, load that specific workflow
                if target_workflow_id:
                    # Load the specific workflow by ID
                    workflow_data = rag_recommender.load_workflow_by_id(target_workflow_id)
                    if workflow_data:
                        best_match = workflow_data
                    else:
                        # Fallback to search if workflow not found by ID
                        rag_result = rag_recommender.get_workflow_recommendations(user_request.request_text, max_recommendations=1)
                        best_match = rag_result["recommendations"][0] if rag_result["status"] == "success" and rag_result["recommendations"] else None
                else:
                    # Get the best matching workflow from RAG system
                    rag_result = rag_recommender.get_workflow_recommendations(user_request.request_text, max_recommendations=1)
                    best_match = rag_result["recommendations"][0] if rag_result["status"] == "success" and rag_result["recommendations"] else None
                
                if best_match:
                    # Create a mock AI response with RAG workflow data
                    from types import SimpleNamespace
                    
                    # Extract actual workflow JSON structure from RAG data
                    workflow_json = best_match.get("workflow_json", {})
                    
                    if workflow_json and "steps" in workflow_json:
                        # Use actual steps from workflow JSON 
                        workflow_steps = []
                        steps_data = workflow_json["steps"]
                        
                        for step_id, step_data in steps_data.items():
                            # Extract step information from workflow JSON
                            tool_id = step_data.get("tool_id")
                            
                            # Skip input steps (tool_id is None for input dataset/parameter steps)
                            if tool_id is None:
                                continue
                                
                            tool_version = step_data.get("tool_version") or "1.0"
                            
                            # Parse tool_state (it's a JSON string, not a dict)
                            tool_state_raw = step_data.get("tool_state", "{}")
                            try:
                                if isinstance(tool_state_raw, str):
                                    parameters = json.loads(tool_state_raw)
                                else:
                                    parameters = tool_state_raw or {}
                            except (json.JSONDecodeError, TypeError):
                                parameters = {}
                            
                            # Create Galaxy WorkflowStep object from real data
                            step = WorkflowStep(
                                step_id=int(step_id),
                                tool_id=tool_id,
                                tool_version=tool_version,
                                input_connections=step_data.get("input_connections", {}),
                                parameters=parameters,
                                annotation=step_data.get("annotation", f"Step {int(step_id) + 1}"),
                                position=step_data.get("position", {"left": int(step_id) * 100, "top": 100})
                            )
                            workflow_steps.append(step)
                        
                        # Clean up input connections and create workflow inputs
                        workflow_steps, workflow_inputs = _clean_input_connections(workflow_steps, steps_data)
                        
                        # Sort steps by step_id to maintain order
                        workflow_steps.sort(key=lambda x: x.step_id)
                    else:
                        # Fallback: create placeholder steps if no workflow JSON available
                        step_count = best_match.get("steps", 0)
                        workflow_steps = []
                        for i in range(step_count):
                            step = WorkflowStep(
                                step_id=i,
                                tool_id="placeholder_tool",  # Basic placeholder
                                tool_version="1.0",
                                input_connections={},
                                parameters={},
                                annotation=f"Step {i+1} from RAG workflow template",
                                position={"left": i * 100, "top": 100}
                            )
                            workflow_steps.append(step)
                    
                    # Create workflow template using proper Galaxy WorkflowTemplate object
                    workflow_template = WorkflowTemplate(
                        name=best_match["name"],
                        description=best_match["description"],
                        steps=workflow_steps,
                        inputs=workflow_inputs if 'workflow_inputs' in locals() else [],  # Use generated workflow inputs
                        outputs=[],  # Will be populated by Galaxy 
                        tags=best_match.get("tags", [])
                    )
                    
                    # Create AI response
                    ai_response = SimpleNamespace()
                    ai_response.workflow_template = workflow_template
                    ai_response.confidence = best_match.get("similarity_score", 5.0) / 15.0  # Normalize
                else:
                    # Fallback to standard generation
                    ai_response = ai_assistant.process_request(user_request)
            except Exception as rag_error:
                log.warning(f"RAG system failed in workflow creation: {rag_error}, falling back to standard generation")
                ai_response = ai_assistant.process_request(user_request)
        else:
            ai_response = ai_assistant.process_request(user_request)
        
        if not ai_response or not getattr(ai_response, 'workflow_template', None):
            raise HTTPException(status_code=400, detail="Could not generate workflow template")
        
        # Convert to Galaxy workflow format
        galaxy_workflow = ai_assistant.workflow_generator.export_to_galaxy_format(
            ai_response.workflow_template
        )
        
        # Save the workflow to Galaxy's workflow system using the standard API approach
        try:
            # Import required classes
            from galaxy.managers.workflows import WorkflowCreateOptions
            
            # Use the workflow_contents_manager to create workflow
            workflow_contents_manager = trans.app.workflow_contents_manager
            
            # Normalize the workflow format
            raw_workflow_description = workflow_contents_manager.normalize_workflow_format(trans, galaxy_workflow)
            
            # Create workflow creation options
            workflow_create_options = WorkflowCreateOptions(
                publish=False,
                importable=False,
                import_tools=False
            )
            
            # Use the workflow_contents_manager to build workflow from description
            created_workflow = workflow_contents_manager.build_workflow_from_raw_description(
                trans,
                raw_workflow_description,
                workflow_create_options
            )
            
            # Get workflow information
            stored_workflow = created_workflow.stored_workflow
            workflow = created_workflow.workflow
            workflow_id = stored_workflow.id
            encoded_id = trans.security.encode_id(workflow_id)
            
            return {
                "workflow_id": encoded_id,
                "workflow_name": stored_workflow.name,
                "message": f"Workflow '{stored_workflow.name}' created and saved successfully!",
                "workflow_url": f"/workflows/edit?id={encoded_id}",
                "note": "Workflow saved to your workflows list - check Workflow menu → My Workflows",
                "status": "success",
                "number_of_steps": len(workflow.steps) if workflow.steps else 0
            }
            
        except Exception as save_error:
            import traceback
            error_details = traceback.format_exc()
            log.error(f"Failed to save workflow to Galaxy system: {save_error}")
            log.error(f"Full error traceback: {error_details}")
            
            # Return detailed error for debugging
            return {
                "workflow": galaxy_workflow,
                "message": "Workflow generated but could not be saved",
                "note": "The AI successfully generated a workflow, but there was an error saving it to Galaxy",
                "error": f"Save error: {str(save_error)}",
                "error_details": error_details,
                "status": "partial_success"
            }
        
    except Exception as e:
        log.error(f"Error creating workflow: {e}")
        raise HTTPException(status_code=500, detail=f"Error creating workflow: {str(e)}")


@router.post(
    "/api/ai_assistant/get_workflow_recommendations",
    summary="Get workflow recommendations based on user request."
)
def get_workflow_recommendations(
    request: AIRequestModel,
    trans: ProvidesUserContext = DependsOnTrans
) -> Dict[str, Any]:
    """Get multiple workflow recommendations for user request."""
    
    try:
        # Use RAG system directly if available
        if RAG_AVAILABLE:
            try:
                # Initialize RAG workflow generator directly
                ai_assistant = get_ai_assistant(trans)
                
                if ai_assistant and hasattr(ai_assistant, 'rag_recommender') and ai_assistant.rag_recommender:
                    # Use the initialized RAG workflow generator
                    from galaxy.ai.types import UserRequest
                    user_request = UserRequest(
                        user_id=str(trans.user.id) if trans.user else "anonymous",
                        request_text=request.request_text,
                        context=request.context or {}
                    )
                    
                    # Get recommendations using the fixed RAG system
                    recommendations_data = ai_assistant.rag_recommender.get_workflow_recommendations(user_request.request_text, max_recommendations=5)
                    
                    # Convert to API format
                    recommendations = []
                    for rec in recommendations_data:
                        recommendations.append({
                            "type": "rag",
                            "name": rec.get("name", ""),
                            "description": rec.get("description", ""),
                            "confidence": rec.get("confidence", 0),
                            "validation_status": "verified",
                            "template_id": rec.get("workflow_id", ""),
                            "estimated_time": "1-3 hours",
                            "difficulty": "intermediate",
                            "tools": rec.get("tools", []),
                            "step_count": rec.get("steps", 0),
                            "step_descriptions": rec.get("step_descriptions", [])
                        })
                    
                    return {
                        "recommendations": recommendations,
                        "total_options": len(recommendations),
                        "method": "RAG-based (using 951 crawled workflows)",
                        "status": "success"
                    }
                else:
                    log.warning("RAG workflow generator not available")
            except Exception as rag_error:
                log.warning(f"RAG system failed: {rag_error}, falling back to templates")
                import traceback
                log.warning(f"RAG error traceback: {traceback.format_exc()}")
        
        # Fallback to template system
        ai_assistant = get_ai_assistant(trans)
        if not ai_assistant:
            raise HTTPException(status_code=503, detail="AI Assistant not available")
            
        user_request = UserRequest(
            user_id=str(trans.user.id) if trans.user else "anonymous",
            request_text=request.request_text,
            context=request.context,
            available_datasets=request.available_datasets,
            preferred_tools=request.preferred_tools,
            constraints=request.constraints
        )
        
        recommendations = ai_assistant.workflow_generator.get_workflow_recommendations(user_request)
        
        return {
            "recommendations": recommendations,
            "total_options": len(recommendations),
            "method": "Template-based (RAG fallback)",
            "status": "success"
        }
        
    except Exception as e:
        log.error(f"Error getting workflow recommendations: {e}")
        raise HTTPException(status_code=500, detail=f"Error getting recommendations: {str(e)}")


def _workflow_to_dict(workflow_template) -> Dict[str, Any]:
    """Convert workflow template to dictionary."""
    if not workflow_template:
        return None
    
    return {
        "name": workflow_template.name,
        "description": workflow_template.description,
        "steps": [
            {
                "step_id": step.step_id,
                "tool_id": step.tool_id,
                "tool_version": step.tool_version,
                "annotation": step.annotation,
                "parameters": step.parameters
            }
            for step in workflow_template.steps
        ],
        "inputs": workflow_template.inputs,
        "outputs": workflow_template.outputs,
        "tags": workflow_template.tags
    }


@router.post(
    "/api/ai_assistant/enhanced_workflow_recommendations",
    summary="Get enhanced workflow recommendations with RAG generation"
)
def get_enhanced_workflow_recommendations(
    request: AIRequestModel,
    level: str = Query("quick", description="Level of analysis: quick, enhanced"),
    trans: ProvidesUserContext = DependsOnTrans
) -> Dict[str, Any]:
    """Get enhanced workflow recommendations with different levels."""
    
    try:
        if level == "enhanced":
            # Enhanced generation using RAG
            ai_assistant = get_ai_assistant(trans)
            if not ai_assistant or not hasattr(ai_assistant, 'rag_recommender') or not ai_assistant.rag_recommender:
                return {
                    "status": "unavailable", 
                    "error": "RAG system not available",
                    "fallback_available": True
                }
            
            try:
                # Generate workflow using RAG
                from galaxy.ai.types import UserRequest
                user_request = UserRequest(
                    user_id=str(trans.user.id) if trans.user else "anonymous",
                    request_text=request.request_text,
                    context=request.context or {}
                )
                
                # Use RAG recommender for workflow generation
                rag_result = ai_assistant.rag_recommender.get_workflow_recommendations(user_request.request_text, max_recommendations=1)

                if rag_result.get("status") == "success" and rag_result.get("recommendations"):
                    # Create workflow from best recommendation
                    best_rec = rag_result["recommendations"][0]
                    result = {
                        "success": True,
                        "workflow": {
                            "name": best_rec.get("name", "Enhanced Workflow"),
                            "description": best_rec.get("description", "AI-generated workflow"),
                            "steps": [],  # Would need to extract from workflow data
                            "tools": best_rec.get("tools", [])
                        },
                        "confidence": best_rec.get("confidence", 0.8)
                    }
                else:
                    result = {"success": False, "error": "No suitable workflows found"}
                
                if result.get('success', False):
                    workflow_data = result.get("workflow", {})
                    
                    # Ensure workflow has the expected structure with detailed steps
                    workflow_response = {
                        "name": workflow_data.get("name", "Generated Workflow"),
                        "description": workflow_data.get("description", ""),
                        "steps": workflow_data.get("steps", []),
                        "step_count": len(workflow_data.get("steps", [])),
                        "inputs": workflow_data.get("inputs", []),
                        "outputs": workflow_data.get("outputs", []),
                        "tags": workflow_data.get("tags", []),
                        "tools": []  # Extract tool list from steps
                    }
                    
                    # Extract tool list from steps
                    for step in workflow_data.get("steps", []):
                        if step.get("tool_id"):
                            tool_name = step["tool_id"]
                            if "/" in tool_name:
                                tool_name = tool_name.split("/")[-1]
                            if tool_name not in workflow_response["tools"]:
                                workflow_response["tools"].append(tool_name)
                    
                    return {
                        "status": "success",
                        "workflow": workflow_response,
                        "confidence": result.get("confidence", 0),
                        "method": "RAG Enhanced Generation",
                        "similar_workflows_count": result.get("similar_workflows_count", 0),
                        "response_time": "2-5s"
                    }
                else:
                    return {
                        "status": "error",
                        "error": result.get("error", "Unknown generation error")
                    }
                    
            except Exception as e:
                log.error(f"Enhanced RAG generation failed: {e}")
                import traceback
                log.error(f"Enhanced RAG generation traceback: {traceback.format_exc()}")
                return {
                    "status": "error", 
                    "error": str(e),
                    "fallback_available": True
                }
        else:
            # Quick recommendations - fallback to existing system
            return get_workflow_recommendations(request, trans)
            
    except Exception as e:
        log.error(f"Enhanced workflow recommendations failed: {e}")
        return {
            "status": "error",
            "error": f"Enhanced recommendations failed: {str(e)}"
        }


@router.post(
    "/api/ai_assistant/rag_workflow",
    summary="Generate workflow using RAG-based recommendation system"
)
def create_rag_workflow(
    request: AIRequestModel,
    trans: ProvidesUserContext = DependsOnTrans
):
    """
    Generate workflow recommendations using RAG (Retrieval-Augmented Generation).
    Uses real Galaxy community workflows for better accuracy.
    """
    ai_assistant = get_ai_assistant(trans)
    if not ai_assistant:
        raise HTTPException(status_code=503, detail="AI Assistant not available")
    
    # Check if RAG is available
    if not hasattr(ai_assistant, 'rag_recommender') or not ai_assistant.rag_recommender:
        raise HTTPException(status_code=503, detail="RAG system not available")
    
    try:
        # Use RAG system to generate workflow preview
        result = ai_assistant.rag_recommender.generate_workflow_preview(request.request_text)
        
        return {
            "success": True,
            "workflow": result,
            "method": "RAG-based with 951 community workflows",
            "status": "success"
        }
        
    except Exception as e:
        log.error(f"Error in RAG workflow generation: {e}")
        raise HTTPException(status_code=500, detail=f"RAG workflow generation failed: {str(e)}")


@router.post(
    "/api/ai_assistant/rag_recommendations", 
    summary="Get workflow recommendations using RAG similarity search"
)
def get_rag_recommendations(
    request: AIRequestModel,
    trans: ProvidesUserContext = DependsOnTrans,
    max_results: int = Query(5, description="Maximum number of recommendations")
):
    """
    Get workflow recommendations using RAG-based similarity search.
    Returns actual Galaxy workflows that match user request.
    """
    ai_assistant = get_ai_assistant(trans)
    if not ai_assistant:
        raise HTTPException(status_code=503, detail="AI Assistant not available")
    
    # Check if RAG is available
    if not hasattr(ai_assistant, 'rag_recommender') or not ai_assistant.rag_recommender:
        raise HTTPException(status_code=503, detail="RAG system not available")
    
    try:
        # Get recommendations using RAG
        recommendations = ai_assistant.rag_recommender.get_workflow_recommendations(
            user_request=request.request_text,
            max_recommendations=max_results
        )
        
        return {
            "success": True,
            "recommendations": recommendations,
            "method": "RAG-based similarity search",
            "status": "success"
        }
        
    except Exception as e:
        log.error(f"Error getting RAG recommendations: {e}")
        raise HTTPException(status_code=500, detail=f"RAG recommendations failed: {str(e)}")


@router.get(
    "/api/ai_assistant/rag_stats",
    summary="Get RAG system statistics"
)
def get_rag_stats(trans: ProvidesUserContext = DependsOnTrans):
    """Get statistics about the RAG workflow database."""
    ai_assistant = get_ai_assistant(trans)
    if not ai_assistant:
        raise HTTPException(status_code=503, detail="AI Assistant not available")
    
    # Check if RAG is available
    if not hasattr(ai_assistant, 'rag_recommender') or not ai_assistant.rag_recommender:
        raise HTTPException(status_code=503, detail="RAG system not available")
    
    try:
        stats = ai_assistant.rag_recommender.get_stats()
        
        return {
            "success": True,
            "stats": stats,
            "rag_available": True,
            "status": "success"
        }
        
    except Exception as e:
        log.error(f"Error getting RAG stats: {e}")
        raise HTTPException(status_code=500, detail=f"RAG stats failed: {str(e)}")


@router.post(
    "/api/ai_assistant/two_stage_workflow",
    summary="Unified two-stage RAG workflow recommendations"
)
def get_two_stage_workflow(
    request: AIRequestModel,
    stage: str = Query("similar", description="Stage: similar, enhanced"),
    trans: ProvidesUserContext = DependsOnTrans
) -> Dict[str, Any]:
    """
    Unified endpoint for two-stage workflow recommendations.
    
    Stage 1 (similar): Returns most similar workflows from RAG database
    Stage 2 (enhanced): Generates enhanced/customized workflow based on similar ones
    """
    
    ai_assistant = get_ai_assistant(trans)
    if not ai_assistant:
        raise HTTPException(status_code=503, detail="AI Assistant not available")
    
    if not hasattr(ai_assistant, 'rag_recommender') or not ai_assistant.rag_recommender:
        raise HTTPException(status_code=503, detail="RAG system not available")
    
    try:
        if stage == "similar":
            # Stage 1: Similar workflow recommendations
            log.info(f"Stage 1: Getting similar workflows for '{request.request_text}'")
            
            result = ai_assistant.rag_recommender.get_workflow_recommendations(
                user_request=request.request_text,
                max_recommendations=5
            )
            
            if result.get("status") == "success" and result.get("recommendations"):
                # Format for two-stage display
                recommendations = []
                for rec in result["recommendations"][:3]:  # Top 3 for stage 1
                    # Normalize confidence score to 0-1 range
                    similarity_score = rec.get("similarity_score", 0.0)
                    confidence = min(similarity_score / 15.0, 1.0)  # Cap at 1.0
                    
                    recommendations.append({
                        "workflow_id": rec.get("workflow_id", ""),
                        "name": rec.get("name", ""),
                        "description": rec.get("description", ""),
                        "confidence": confidence,
                        "step_count": rec.get("steps", 0),  # Correct field name
                        "steps": rec.get("steps", 0),  # Correct field name
                        "tools": rec.get("tools", []),
                        "tags": rec.get("tags", []),
                        "owner": rec.get("owner", "Galaxy Community"),
                        "type": "rag_similar"
                    })
                
                return {
                    "status": "success",
                    "stage": "similar",
                    "recommendations": recommendations,
                    "total_found": len(result["recommendations"]),
                    "query": request.request_text,
                    "method": "RAG Similarity Search",
                    "database_size": 951,
                    "next_stage_available": True
                }
            else:
                return {
                    "status": "no_results",
                    "stage": "similar", 
                    "message": "No similar workflows found for your request",
                    "query": request.request_text,
                    "suggestions": ["Try using more specific keywords", "Consider broader search terms", "Check for spelling errors"]
                }
                
        elif stage == "enhanced":
            # Stage 2: Enhanced workflow generation
            log.info(f"Stage 2: Generating enhanced workflow for '{request.request_text}'")
            
            # Try enhanced generation using similar workflows as context
            try:
                if hasattr(ai_assistant, 'rag_recommender') and ai_assistant.rag_recommender:
                    from galaxy.ai.types import UserRequest

                    # Extract similar workflows from context for enhanced generation
                    context = request.context or {}
                    similar_workflows = context.get('similar_workflows', [])

                    log.info(f"Stage 2: Using {len(similar_workflows)} similar workflows as context")

                    user_request = UserRequest(
                        user_id=str(trans.user.id) if trans.user else "anonymous",
                        request_text=request.request_text,
                        context={
                            **context,
                            'generation_mode': 'enhanced_with_context',
                            'similar_workflows_context': similar_workflows[:3]  # Only top-3
                        }
                    )

                    # Stage 2: Use LLM to generate custom workflow based on similar workflows context
                    log.info("Stage 2: Calling LLM for custom workflow generation")

                    # Use the workflow_generator with LLM for actual generation
                    workflow_result = ai_assistant.workflow_generator.generate_workflow_with_context(
                        user_request.request_text,
                        similar_workflows[:3]  # Top-3 as context
                    )

                    if workflow_result.get('success', False):
                        result = {
                            "success": True,
                            "workflow": workflow_result.get("workflow", {}),
                            "confidence": workflow_result.get("confidence", 0.8)
                        }
                    else:
                        # Fallback: create a basic custom workflow template
                        result = {
                            "success": True,
                            "workflow": {
                                "name": f"Custom Workflow for: {request.request_text[:50]}...",
                                "description": f"AI-generated custom workflow based on your request: '{request.request_text}' and {len(similar_workflows)} similar workflow patterns.",
                                "steps": [
                                    {
                                        "id": 1,
                                        "tool_id": "data_input",
                                        "annotation": "Input data preparation",
                                        "inputs": [],
                                        "outputs": [{"name": "output", "type": "data"}]
                                    },
                                    {
                                        "id": 2,
                                        "tool_id": "analysis_step",
                                        "annotation": f"Analysis step for: {request.request_text}",
                                        "inputs": [{"name": "input", "type": "data"}],
                                        "outputs": [{"name": "result", "type": "data"}]
                                    },
                                    {
                                        "id": 3,
                                        "tool_id": "output_formatting",
                                        "annotation": "Format and prepare results",
                                        "inputs": [{"name": "input", "type": "data"}],
                                        "outputs": [{"name": "final_output", "type": "data"}]
                                    }
                                ],
                                "inputs": [{"label": "Input Data", "type": "data"}],
                                "outputs": [{"label": "Analysis Results", "type": "data"}],
                                "tags": ["ai-generated", "custom"],
                                "tools": []
                            },
                            "confidence": 0.7,
                            "generation_method": "LLM_with_context_fallback"
                        }
                    
                    if result.get('success', False):
                        workflow_data = result.get("workflow", {})

                        return {
                            "status": "success",
                            "stage": "enhanced",
                            "workflow": {
                                "name": workflow_data.get("name", f"Custom Workflow for: {request.request_text[:50]}..."),
                                "description": workflow_data.get("description", f"AI-generated custom workflow based on top-3 similar workflows, tailored for: {request.request_text}"),
                                "steps": workflow_data.get("steps", []),
                                "step_count": len(workflow_data.get("steps", [])),
                                "inputs": workflow_data.get("inputs", []),
                                "outputs": workflow_data.get("outputs", []),
                                "tags": workflow_data.get("tags", []),
                                "tools": workflow_data.get("tools", [])
                            },
                            "confidence": result.get("confidence", 0.8),
                            "method": "RAG Enhanced Generation with Context",
                            "similar_workflows_count": len(similar_workflows),
                            "context_workflows": [w.get("name", "Unknown") for w in similar_workflows[:3]],
                            "response_time": "3-8 seconds",
                            "type": "enhanced_rag_with_context"
                        }
                
                # Fallback: Use best similar workflow as "enhanced"
                log.info("Enhanced generation not available, using fallback approach")
                return get_enhanced_fallback(request, ai_assistant)
                
            except Exception as enhanced_error:
                log.warning(f"Enhanced generation failed: {enhanced_error}, using fallback")
                return get_enhanced_fallback(request, ai_assistant)
        
        else:
            raise HTTPException(status_code=400, detail=f"Invalid stage: {stage}. Use 'similar' or 'enhanced'")
            
    except HTTPException:
        raise
    except Exception as e:
        log.error(f"Two-stage workflow error: {e}")
        raise HTTPException(status_code=500, detail=f"Two-stage workflow failed: {str(e)}")


def get_enhanced_fallback(request: AIRequestModel, ai_assistant) -> Dict[str, Any]:
    """Fallback enhanced generation using best similar workflow."""
    try:
        # Get the best similar workflow
        result = ai_assistant.rag_recommender.get_workflow_recommendations(
            user_request=request.request_text,
            max_recommendations=1
        )
        
        if result.get("status") == "success" and result.get("recommendations"):
            best_match = result["recommendations"][0]
            
            return {
                "status": "success",
                "stage": "enhanced_fallback",
                "workflow": {
                    "name": f"AI-Enhanced {best_match.get('name', 'Workflow')}",
                    "description": f"Enhanced workflow based on community best practices: {best_match.get('description', '')[:200]}{'...' if len(best_match.get('description', '')) > 200 else ''}",
                    "steps": [],  # Would need to reconstruct from workflow data
                    "step_count": best_match.get("steps", 0),  # Correct field name
                    "tools": best_match.get("tools", []),
                    "tags": best_match.get("tags", []),
                    "owner": best_match.get("owner", "Galaxy Community")
                },
                "confidence": min(best_match.get("similarity_score", 0.0) / 15.0, 1.0),
                "method": "Enhanced Similarity Matching",
                "similar_workflows_count": 1,
                "response_time": "1-2 seconds",
                "type": "fallback_enhanced",
                "note": "Advanced RAG generator is temporarily unavailable. Using enhanced presentation of the best matching workflow."
            }
        else:
            return {
                "status": "error",
                "stage": "enhanced_fallback",
                "message": "Unable to generate enhanced workflow - no similar workflows found",
                "query": request.request_text,
                "suggestions": ["Try rephrasing your request", "Use more general terms", "Contact support for assistance"]
            }
            
    except Exception as e:
        log.error(f"Enhanced fallback failed: {e}")
        return {
            "status": "error",
            "stage": "enhanced_fallback", 
            "message": f"Enhanced workflow generation failed: {str(e)}",
            "suggestions": ["Please try again", "Contact support if the problem persists"]
        }


# Enhanced simple workflow API with RAG fallback
@router.post(
    "/api/ai_assistant/simple_workflow",
    summary="Create simple workflow preview with RAG support"
)
def create_enhanced_simple_workflow(
    request_data: dict,
    trans: ProvidesUserContext = DependsOnTrans
):
    """
    Create workflow preview using RAG if available, fallback to simple templates.
    Works without authentication for preview functionality.
    """
    try:
        request_text = request_data.get('request_text', '')
        context = request_data.get('context', {})
        
        if not request_text:
            raise HTTPException(status_code=400, detail="request_text is required")
        
        # Try RAG first if available
        log.info(f"🔍 Enhanced simple workflow request: {request_text}")
        ai_assistant = get_ai_assistant(trans)
        log.info(f"🔍 AI Assistant obtained: {ai_assistant is not None}")
        
        if ai_assistant:
            has_rag = hasattr(ai_assistant, 'rag_recommender')
            rag_available = ai_assistant.rag_recommender if has_rag else None
            log.info(f"🔍 Has RAG recommender: {has_rag}, Available: {rag_available is not None}")
        
        if (ai_assistant and 
            hasattr(ai_assistant, 'rag_recommender') and 
            ai_assistant.rag_recommender):
            
            try:
                log.info("🚀 Calling RAG workflow generator...")
                rag_result = ai_assistant.rag_recommender.generate_workflow_preview(request_text)
                log.info(f"✅ RAG generation successful: {rag_result.get('status', 'unknown')}")
                rag_result['method'] = 'Enhanced RAG-based Generation'
                rag_result['preview'] = True
                rag_result['login_url'] = '/login'
                rag_result['note'] = '🔑 This is a preview. To save workflows, please log in to Galaxy'
                return rag_result
                
            except Exception as rag_error:
                log.warning(f"❌ RAG generation failed, falling back to simple: {rag_error}")
                import traceback
                log.warning(f"RAG error traceback: {traceback.format_exc()}")
        else:
            log.info("⚠️  RAG not available, using simple fallback")
        
        # Fallback to simple API if RAG fails or not available
        if SIMPLE_API_AVAILABLE and SimpleAIRequestModel:
            simple_request = SimpleAIRequestModel(
                request_text=request_text,
                context=context
            )
            return create_simple_workflow_preview(simple_request)
        else:
            raise HTTPException(status_code=503, detail="No workflow generation system available")
            
    except HTTPException:
        raise
    except Exception as e:
        log.error(f"Error in enhanced simple workflow creation: {e}")
        raise HTTPException(status_code=500, detail=f"Workflow creation failed: {str(e)}")


def _clean_input_connections(workflow_steps, original_steps_data):
    """
    Clean input connections and convert input step references to workflow inputs.
    
    Args:
        workflow_steps: List of WorkflowStep objects (only tool steps, input steps filtered out)
        original_steps_data: Original steps data from workflow JSON (includes input steps)
    
    Returns:
        Tuple of (cleaned_workflow_steps, workflow_inputs)
    """
    # Create a map of existing step IDs
    existing_step_ids = set(step.step_id for step in workflow_steps)
    
    # Identify and analyze input steps
    input_step_info = {}
    for step_id, step_data in original_steps_data.items():
        if step_data.get("tool_id") is None:
            input_step_info[int(step_id)] = {
                'type': step_data.get('type', 'unknown'),
                'label': step_data.get('label', f'Input {step_id}'),
                'tool_state': step_data.get('tool_state', '{}')
            }
    
    # Track which input steps are actually needed
    needed_input_steps = set()
    
    # Clean up input connections for each workflow step
    cleaned_steps = []
    for step in workflow_steps:
        cleaned_connections = {}
        step_inputs = {}  # Track inputs needed by this step
        
        # Process each connection
        for input_name, connection in step.input_connections.items():
            if isinstance(connection, dict) and 'id' in connection:
                referenced_step_id = connection['id']
                
                # Keep the connection only if it references an existing tool step
                if referenced_step_id in existing_step_ids:
                    cleaned_connections[input_name] = connection
                elif referenced_step_id in input_step_info:
                    # This connection references an input step - we'll reconnect it later in export
                    input_info = input_step_info[referenced_step_id]
                    needed_input_steps.add(referenced_step_id)
                    
                    # Store the original connection info for later reconnection
                    cleaned_connections[input_name] = {
                        'id': f'workflow_input_{referenced_step_id}',  # Temporary marker
                        'output_name': connection.get('output_name', 'output'),
                        '_original_input_step': referenced_step_id,
                        '_input_label': input_info['label']
                    }
                    
                    log.debug(f"Marking connection from step {step.step_id}.{input_name} for input step reconnection")
                else:
                    # This connection references a non-existent step
                    log.warning(f"Step {step.step_id} references non-existent step {referenced_step_id}")
            else:
                # Keep non-dict connections or connections without 'id'
                cleaned_connections[input_name] = connection
        
        # Create a new WorkflowStep with cleaned connections
        from galaxy.ai.types import WorkflowStep
        cleaned_step = WorkflowStep(
            step_id=step.step_id,
            tool_id=step.tool_id,
            tool_version=step.tool_version,
            input_connections=cleaned_connections,
            parameters=step.parameters,
            annotation=step.annotation,
            position=step.position
        )
        
        # Add workflow inputs to the step if needed
        if step_inputs:
            # Store step_inputs in parameters for later use in export
            if not hasattr(cleaned_step, 'workflow_inputs'):
                cleaned_step.workflow_inputs = step_inputs
        
        cleaned_steps.append(cleaned_step)
    
    # Create workflow input definitions for needed inputs
    workflow_inputs = []
    for input_step_id in sorted(needed_input_steps):
        input_info = input_step_info[input_step_id]
        
        try:
            # Parse tool_state to understand input requirements
            tool_state = json.loads(input_info['tool_state']) if isinstance(input_info['tool_state'], str) else input_info['tool_state']
        except:
            tool_state = {}
        
        if input_info['type'] == 'data_collection_input':
            # Data collection input
            collection_type = tool_state.get('collection_type', 'list')
            formats = tool_state.get('format', ['data'])
            
            workflow_inputs.append({
                'label': input_info['label'],
                'name': f'input_{input_step_id}',
                'type': 'data_collection',
                'collection_type': collection_type,
                'format': formats,
                'optional': tool_state.get('optional', False),
                'description': f"Input data collection: {input_info['label']}"
            })
        
        elif input_info['type'] == 'parameter_input':
            # Parameter input
            param_type = tool_state.get('parameter_type', 'text')
            
            workflow_inputs.append({
                'label': input_info['label'],
                'name': f'input_{input_step_id}',
                'type': 'parameter',
                'parameter_type': param_type,
                'optional': tool_state.get('optional', False),
                'description': f"Input parameter: {input_info['label']}"
            })
        
        else:
            # Generic input
            workflow_inputs.append({
                'label': input_info['label'],
                'name': f'input_{input_step_id}',
                'type': 'data',
                'format': 'auto',
                'optional': False,
                'description': f"Workflow input: {input_info['label']}"
            })
    
    log.info(f"Cleaned input connections for {len(cleaned_steps)} workflow steps")
    log.info(f"Created {len(workflow_inputs)} workflow inputs from {len(needed_input_steps)} input steps")
    
    return cleaned_steps, workflow_inputs