"""
Enhanced AI Assistant with Conversation Context Management

⚠️ **NEW FILE** - This is a completely new file that extends the existing AI Assistant
without modifying any existing files. It provides conversation context management and
enhanced workflow generation capabilities.

Safe to add - does not modify existing functionality.
"""

import logging
import time
from typing import Dict, List, Optional
from dataclasses import dataclass

# Try to import existing AI components, fallback if not available
try:
    from galaxy.ai.ai_assistant import AIAssistant as BaseAIAssistant
except ImportError:
    # Fallback if AI assistant doesn't exist
    class BaseAIAssistant:
        def __init__(self):
            pass

try:
    from galaxy.ai.types import WorkflowTemplate
except ImportError:
    # Fallback WorkflowTemplate class
    class WorkflowTemplate:
        def __init__(self, **kwargs):
            for key, value in kwargs.items():
                setattr(self, key, value)
        
        def to_dict(self):
            return self.__dict__

log = logging.getLogger(__name__)

@dataclass
class ConversationResult:
    response_text: str
    context_update: Optional[Dict] = None
    suggested_actions: List[Dict] = None
    workflow_templates: List[Dict] = None
    requires_clarification: bool = False
    clarification_questions: List[str] = None

@dataclass 
class WorkflowGenerationResult:
    template: WorkflowTemplate
    execution_plan: str
    warnings: List[str]
    missing_tools: List[str]

class ConversationContextManager:
    """Manages conversation context and state"""
    
    def __init__(self):
        self.sessions = {}
    
    def get_session(self, session_id: str) -> Dict:
        if session_id not in self.sessions:
            self.sessions[session_id] = {
                'history': [],
                'current_task': None,
                'workflow_draft': None,
                'user_preferences': {},
                'extracted_requirements': {}
            }
        return self.sessions[session_id]
    
    def update_session(self, session_id: str, updates: Dict):
        session = self.get_session(session_id)
        session.update(updates)
    
    def add_message(self, session_id: str, message: str, role: str):
        session = self.get_session(session_id)
        session['history'].append({
            'message': message,
            'role': role,
            'timestamp': time.time()
        })

class EnhancedAIAssistant(BaseAIAssistant):
    """Enhanced AI Assistant with conversational workflow generation"""
    
    def __init__(self):
        super().__init__()
        self.context_manager = ConversationContextManager()
        self.workflow_templates = {}
    
    async def process_conversation(
        self,
        message: str,
        context: Optional[Dict] = None,
        intent_hints: Optional[List[str]] = None
    ) -> ConversationResult:
        """Process conversational message with context"""
        
        session_id = context.get('session_id', 'default') if context else 'default'
        session = self.context_manager.get_session(session_id)
        
        # Add user message to history
        self.context_manager.add_message(session_id, message, 'user')
        
        # Analyze intent with context
        intent_analysis = await self._analyze_intent_with_context(
            message, session, intent_hints
        )
        
        if intent_analysis['intent'] == 'workflow_creation':
            return await self._handle_workflow_conversation(
                message, session_id, intent_analysis
            )
        elif intent_analysis['intent'] == 'workflow_modification':
            return await self._handle_workflow_modification(
                message, session_id, intent_analysis
            )
        elif intent_analysis['intent'] == 'clarification_needed':
            return await self._handle_clarification_request(
                message, session_id, intent_analysis
            )
        else:
            return await self._handle_general_conversation(
                message, session_id, intent_analysis
            )
    
    async def _analyze_intent_with_context(
        self, message: str, session: Dict, hints: Optional[List[str]] = None
    ) -> Dict:
        """Analyze user intent considering conversation context"""
        
        # Check if continuing workflow creation
        if session.get('current_task') == 'workflow_creation':
            if any(word in message.lower() for word in ['yes', 'continue', 'next', 'proceed']):
                return {'intent': 'workflow_creation', 'confidence': 0.9}
            elif any(word in message.lower() for word in ['modify', 'change', 'edit', 'update']):
                return {'intent': 'workflow_modification', 'confidence': 0.8}
        
        # Workflow creation keywords
        creation_keywords = [
            'create workflow', 'build workflow', 'generate workflow',
            'make workflow', 'workflow for', 'need workflow',
            'analyze', 'process', 'pipeline'
        ]
        
        if any(keyword in message.lower() for keyword in creation_keywords):
            return {'intent': 'workflow_creation', 'confidence': 0.8}
        
        # Check for clarification needs
        if len(message.split()) < 5 or '?' in message:
            return {'intent': 'clarification_needed', 'confidence': 0.6}
        
        return {'intent': 'general', 'confidence': 0.5}
    
    async def _handle_workflow_conversation(
        self, message: str, session_id: str, intent_analysis: Dict
    ) -> ConversationResult:
        """Handle workflow creation conversation"""
        
        session = self.context_manager.get_session(session_id)
        
        # Extract requirements from message
        requirements = await self._extract_workflow_requirements(message, session)
        
        # Check if we have enough information
        if self._has_sufficient_requirements(requirements):
            # Generate workflow
            try:
                workflow_template = await self._generate_workflow_template(requirements)
                
                # Update session
                self.context_manager.update_session(session_id, {
                    'current_task': 'workflow_creation',
                    'workflow_draft': workflow_template,
                    'extracted_requirements': requirements
                })
                
                response = f"I've created a workflow for {requirements.get('task_description', 'your analysis')}. "
                response += f"It includes {len(workflow_template.steps)} steps: "
                response += ", ".join([step.name for step in workflow_template.steps[:3]])
                if len(workflow_template.steps) > 3:
                    response += f" and {len(workflow_template.steps) - 3} more."
                
                return ConversationResult(
                    response_text=response,
                    workflow_templates=[workflow_template.to_dict()],
                    suggested_actions=[
                        {'id': 'preview', 'label': 'Preview Workflow', 'primary': True},
                        {'id': 'create', 'label': 'Create & Edit', 'primary': True},
                        {'id': 'modify', 'label': 'Modify Requirements', 'primary': False}
                    ]
                )
                
            except Exception as e:
                log.error(f"Workflow generation failed: {e}")
                return ConversationResult(
                    response_text="I encountered an error generating the workflow. Could you provide more specific details about your analysis needs?",
                    requires_clarification=True,
                    clarification_questions=[
                        "What type of data are you working with?",
                        "What analysis do you want to perform?",
                        "Are there specific tools you prefer to use?"
                    ]
                )
        else:
            # Need more information
            missing = self._identify_missing_requirements(requirements)
            questions = self._generate_clarification_questions(missing)
            
            return ConversationResult(
                response_text="I need a bit more information to create the best workflow for you.",
                requires_clarification=True,
                clarification_questions=questions,
                context_update={'partial_requirements': requirements}
            )
    
    async def _extract_workflow_requirements(self, message: str, session: Dict) -> Dict:
        """Extract workflow requirements from user message"""
        
        requirements = session.get('extracted_requirements', {})
        
        # Use AI to extract requirements
        # This would integrate with your existing LLM
        extraction_prompt = f"""
        Extract workflow requirements from this message: "{message}"
        Consider the conversation history: {session.get('history', [])}
        
        Return JSON with:
        - task_description: string
        - input_data_types: list
        - analysis_type: string  
        - preferred_tools: list
        - output_requirements: list
        - quality_thresholds: dict
        """
        
        # Call your LLM here
        extracted = await self._call_llm_for_extraction(extraction_prompt)
        
        # Merge with existing requirements
        requirements.update(extracted)
        
        return requirements
    
    def _has_sufficient_requirements(self, requirements: Dict) -> bool:
        """Check if we have enough information to generate workflow"""
        required_fields = ['task_description', 'input_data_types', 'analysis_type']
        return all(requirements.get(field) for field in required_fields)
    
    async def _generate_workflow_template(self, requirements: Dict) -> WorkflowTemplate:
        """Generate workflow template from requirements"""
        
        # Use your existing workflow generator
        from galaxy.ai.workflow_generator import WorkflowGenerator
        
        generator = WorkflowGenerator()
        template = await generator.generate_from_requirements(requirements)
        
        return template
    
    def _generate_clarification_questions(self, missing_fields: List[str]) -> List[str]:
        """Generate clarification questions for missing requirements"""
        
        question_map = {
            'task_description': "What specific analysis do you want to perform?",
            'input_data_types': "What type of data files will you be working with? (e.g., FASTQ, BAM, VCF)",
            'analysis_type': "What kind of analysis is this? (e.g., variant calling, RNA-seq, assembly)",
            'output_requirements': "What output format do you need for your results?"
        }
        
        return [question_map.get(field, f"Could you provide more details about {field}?") 
                for field in missing_fields]

# Additional helper methods would go here...