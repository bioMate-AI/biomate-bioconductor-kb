"""
Enhanced AI Assistant API for Conversational Workflow Generation

⚠️ **NEW FILE** - This is a completely new file that extends the existing AI functionality
without modifying any existing files. It provides enhanced conversational workflow generation.

Safe to add - does not modify existing functionality.
"""
from galaxy.managers.context import ProvidesUserContext

import logging
from typing import Dict, List, Any, Optional
from fastapi import HTTPException, Depends
from pydantic import BaseModel, Field

from galaxy.webapps.galaxy.api import DependsOnTrans, Router
# Try to import existing components with fallbacks
try:
    from galaxy.webapps.galaxy.api.ai_assistant import AI_AVAILABLE, log
    if not AI_AVAILABLE:
        raise ImportError("AI Assistant not available")
except ImportError:
    AI_AVAILABLE = False
    log = logging.getLogger(__name__)

try:
    from galaxy.ai.ai_assistant import AIAssistant
except ImportError:
    # Fallback AIAssistant class
    class AIAssistant:
        def __init__(self):
            pass
        
        async def process_conversation(self, **kwargs):
            return {"response_text": "AI Assistant not available"}

# Import other necessary components
try:
    from galaxy.ai.types import UserRequest
except ImportError:
    class UserRequest:
        def __init__(self, **kwargs):
            for key, value in kwargs.items():
                setattr(self, key, value)

router = Router(tags=["ai_assistant_enhanced"])

class ConversationContext(BaseModel):
    session_id: str
    current_task: Optional[str] = None
    workflow_in_progress: Optional[Dict] = None
    user_preferences: Dict[str, Any] = Field(default_factory=dict)
    session_history: List[Dict] = Field(default_factory=list)

class EnhancedAIRequest(BaseModel):
    message: str
    context: Optional[ConversationContext] = None
    intent_hints: List[str] = Field(default_factory=list)

class ConversationResponse(BaseModel):
    response: str
    context_update: Optional[Dict] = None
    suggested_actions: List[Dict] = Field(default_factory=list)
    workflow_templates: List[Dict] = Field(default_factory=list)
    requires_clarification: bool = False
    clarification_questions: List[str] = Field(default_factory=list)

@router.post("/api/ai_assistant/chat", summary="Enhanced conversational AI")
async def enhanced_chat(
    request: EnhancedAIRequest,
    trans: ProvidesUserContext = DependsOnTrans
) -> ConversationResponse:
    """
    Enhanced conversational AI endpoint with context management
    """
    if not AI_AVAILABLE:
        raise HTTPException(status_code=503, detail="AI Assistant not available")
    
    try:
        # Initialize AI assistant with context
        ai_assistant = AIAssistant()
        
        # Process message with context
        result = await ai_assistant.process_conversation(
            message=request.message,
            context=request.context,
            user_context=trans.user,
            intent_hints=request.intent_hints
        )
        
        return ConversationResponse(
            response=result.response_text,
            context_update=result.context_update,
            suggested_actions=result.suggested_actions,
            workflow_templates=result.workflow_templates,
            requires_clarification=result.requires_clarification,
            clarification_questions=result.clarification_questions
        )
        
    except Exception as e:
        log.error(f"Enhanced chat error: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/api/ai_assistant/workflow/generate", summary="Generate workflow from conversation")
async def generate_workflow_from_conversation(
    request: Dict[str, Any],
    trans: ProvidesUserContext = DependsOnTrans
):
    """
    Generate workflow based on conversation context
    """
    if not AI_AVAILABLE:
        raise HTTPException(status_code=503, detail="AI Assistant not available")
    
    try:
        ai_assistant = AIAssistant()
        workflow_result = await ai_assistant.generate_workflow_from_context(
            conversation_context=request.get('context'),
            user_requirements=request.get('requirements'),
            available_tools=trans.app.toolbox.get_tool_ids()
        )
        
        return {
            "workflow_template": workflow_result.template,
            "execution_plan": workflow_result.execution_plan,
            "warnings": workflow_result.warnings,
            "missing_tools": workflow_result.missing_tools
        }
        
    except Exception as e:
        log.error(f"Workflow generation error: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))