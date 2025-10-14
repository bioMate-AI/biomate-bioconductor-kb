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
    from galaxy.ai.types import UserRequest, TaskType, IntentType
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
            
            _ai_assistant_instance = AIAssistant(ai_config, galaxy_app=app)
            log.info("AI Assistant initialized successfully")
            
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
        
        ai_response = ai_assistant.process_request(user_request)
        
        if not ai_response.workflow_template:
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
                "workflow_url": f"/workflow/editor?id={encoded_id}",
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
        
        # Get workflow recommendations
        recommendations = ai_assistant.workflow_generator.get_workflow_recommendations(user_request)
        
        return {
            "recommendations": recommendations,
            "total_options": len(recommendations),
            "status": "success"
        }
        
    except Exception as e:
        log.error(f"Error getting workflow recommendations: {e}")
        raise HTTPException(status_code=500, detail=f"Error getting recommendations: {str(e)}")


@router.post(
    "/api/ai_assistant/generate_workflow",
    summary="Generate workflow using unified search-first approach."
)
def generate_workflow_unified(
    request: AIRequestModel,
    trans: ProvidesUserContext = DependsOnTrans
) -> Dict[str, Any]:
    """
    Generate workflow using unified search-first approach.

    This endpoint uses the complete unified architecture:
    1. Search existing templates first (WorkflowSearchRAG)
    2. If high confidence (>0.8): Reuse template
    3. If medium confidence (0.5-0.8): Adapt template
    4. If low confidence (<0.5): Generate from scratch with tool constraint
    5. Always assign datasets via WorkflowDatasetSelector
    """

    ai_assistant = get_ai_assistant(trans)
    if not ai_assistant:
        raise HTTPException(status_code=503, detail="AI Assistant not available")

    try:
        # Extract uploaded dataset IDs if provided
        uploaded_datasets = None
        if request.available_datasets:
            uploaded_datasets = [ds.get('id') for ds in request.available_datasets if ds.get('id')]

        # Generate workflow using unified approach
        result = ai_assistant.generate_workflow_unified(
            user_intent=request.request_text,
            uploaded_datasets=uploaded_datasets
        )

        if result['success']:
            return {
                'success': True,
                'workflow_ga': result['workflow_ga'],
                'source': result['source'],
                'confidence': result['confidence'],
                'template_match_score': result.get('template_match_score', 0.0),
                'datasets_assigned': result.get('datasets_assigned', False),
                'generated_parameters': result.get('generated_parameters', []),
                'message': result.get('message', 'Workflow generated successfully'),
                'note': f"Generated using {result['source']} strategy"
            }
        else:
            return {
                'success': False,
                'error': result.get('error', 'Unknown error'),
                'message': result.get('message', 'Workflow generation failed')
            }

    except Exception as e:
        log.error(f"Error in unified workflow generation: {e}")
        raise HTTPException(status_code=500, detail=f"Error generating workflow: {str(e)}")


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