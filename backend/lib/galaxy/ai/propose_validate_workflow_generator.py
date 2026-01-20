"""
Propose-Validate Workflow Generator

Implements the LLM-Propose-Then-Validate architecture:
1. LLM proposes workflow using full domain knowledge
2. Validate tools against Galaxy index
3. Validate choices against benchmark knowledge
4. Refine if needed with evidence-based suggestions

This leverages LLM's broad domain knowledge while ensuring:
- Tools actually exist in Galaxy
- Tool choices follow best practices from benchmarks
"""

import json
import logging
from typing import Dict, List, Any, Optional, Tuple
from dataclasses import asdict

from .workflow_proposal_validator import (
    WorkflowProposalValidator,
    WorkflowValidation,
    create_workflow_validator
)
from .domain_workflow_patterns import detect_domain, get_domain_pattern, AnalysisDomain
from .llm_client import LLMClient
from .config import AIConfig

log = logging.getLogger(__name__)


class ProposeValidateWorkflowGenerator:
    """
    Workflow generator using propose-then-validate approach.

    Flow:
    1. LLM proposes ideal workflow (unconstrained)
    2. Validate each tool against index + knowledge
    3. If issues found, LLM refines with validation feedback
    4. Return validated workflow with confidence scores
    """

    MAX_REFINEMENT_ITERATIONS = 2

    def __init__(self, config: AIConfig = None):
        if config is None:
            from .config import DEFAULT_AI_CONFIG
            config = DEFAULT_AI_CONFIG

        self.config = config
        self.llm_client = LLMClient(config)
        self.validator = create_workflow_validator()

    def generate_workflow(
        self,
        user_intent: str,
        data_characteristics: Dict[str, Any] = None,
        constraints: Dict[str, Any] = None
    ) -> Dict[str, Any]:
        """
        Generate a validated workflow using propose-then-validate approach.

        Args:
            user_intent: Natural language description of workflow goal
            data_characteristics: Info about data (read_length, organism, etc.)
            constraints: User constraints (time, resources, etc.)

        Returns:
            Dict with:
            - success: bool
            - workflow: validated workflow structure
            - validation: validation results
            - refinement_history: list of refinement iterations
            - confidence: overall confidence score
        """
        data_characteristics = data_characteristics or {}
        constraints = constraints or {}

        # Detect domain
        domain = detect_domain(user_intent)
        domain_pattern = get_domain_pattern(domain)

        log.info(f"[ProposeValidate] Starting for: {user_intent}")
        log.info(f"[ProposeValidate] Detected domain: {domain.value}")

        refinement_history = []

        # Step 1: LLM proposes initial workflow
        proposed_workflow = self._propose_workflow(
            user_intent, domain, domain_pattern, data_characteristics
        )

        if not proposed_workflow:
            return {
                'success': False,
                'error': 'Failed to generate initial workflow proposal',
                'message': 'LLM did not return a valid workflow structure'
            }

        log.info(f"[ProposeValidate] Initial proposal: {len(proposed_workflow.get('steps', []))} steps")

        # Step 2: Validate and refine loop
        current_workflow = proposed_workflow
        for iteration in range(self.MAX_REFINEMENT_ITERATIONS + 1):
            # Validate current workflow
            validation = self.validator.validate_workflow(
                current_workflow,
                {'data_characteristics': data_characteristics, **constraints}
            )

            refinement_history.append({
                'iteration': iteration,
                'workflow': current_workflow,
                'validation': self._validation_to_dict(validation)
            })

            log.info(f"[ProposeValidate] Iteration {iteration}: "
                    f"available={validation.all_tools_available}, "
                    f"recommended={validation.all_tools_recommended}, "
                    f"confidence={validation.confidence_score:.2f}")

            # Check if we're done
            if not validation.needs_refinement:
                log.info(f"[ProposeValidate] Validation passed after {iteration} iterations")
                break

            # If this was the last iteration, exit with what we have
            if iteration >= self.MAX_REFINEMENT_ITERATIONS:
                log.warning(f"[ProposeValidate] Max iterations reached, using best effort")
                break

            # Step 3: Refine with validation feedback
            log.info(f"[ProposeValidate] Refining workflow...")
            refined_workflow = self._refine_workflow(
                current_workflow, validation, user_intent, domain
            )

            if refined_workflow:
                current_workflow = refined_workflow
            else:
                log.warning(f"[ProposeValidate] Refinement failed, keeping current workflow")
                break

        # Build final result
        final_validation = self.validator.validate_workflow(
            current_workflow,
            {'data_characteristics': data_characteristics, **constraints}
        )

        # Convert to Galaxy-compatible format
        galaxy_workflow = self._build_galaxy_workflow(
            current_workflow, final_validation, user_intent
        )

        return {
            'success': True,
            'workflow': current_workflow,
            'workflow_ga': galaxy_workflow,
            'validation': self._validation_to_dict(final_validation),
            'refinement_history': refinement_history,
            'confidence': final_validation.confidence_score,
            'domain': domain.value,
            'all_tools_available': final_validation.all_tools_available,
            'needs_manual_review': not final_validation.all_tools_available
        }

    def _propose_workflow(
        self,
        user_intent: str,
        domain: AnalysisDomain,
        domain_pattern,
        data_characteristics: Dict
    ) -> Optional[Dict]:
        """Generate initial workflow proposal using LLM."""

        # Build prompt
        phases_text = "\n".join([
            f"- {phase.name}: {phase.description}"
            for phase in domain_pattern.phases
            if phase.required
        ])

        data_info = ""
        if data_characteristics:
            data_info = "DATA CHARACTERISTICS:\n" + "\n".join([
                f"- {k}: {v}" for k, v in data_characteristics.items()
            ])

        prompt = f"""You are an expert bioinformatics workflow designer.

Based on your knowledge of bioinformatics tools and best practices,
propose a workflow for the following task.

USER REQUEST: {user_intent}

ANALYSIS DOMAIN: {domain.value}

RECOMMENDED PHASES for {domain.value} analysis:
{phases_text}

{data_info}

Propose a workflow using the BEST tools you know for this task.
Use standard tool names (e.g., "STAR", "Salmon", "DESeq2", "FastQC").

For each step, provide:
1. step: Step number
2. tool_name: Standard tool name
3. purpose: What this step accomplishes
4. key_parameters: Important parameters to set
5. justification: Why this tool is the best choice

Return ONLY valid JSON (no markdown, no explanation):
{{
  "workflow_name": "Descriptive name for the workflow",
  "description": "Brief description of the workflow",
  "steps": [
    {{
      "step": 1,
      "tool_name": "ToolName",
      "purpose": "What this step does",
      "key_parameters": {{"param1": "value1"}},
      "justification": "Why this tool"
    }}
  ]
}}"""

        try:
            response = self.llm_client.generate(prompt, max_tokens=2000)

            # Parse JSON from response
            workflow = self._parse_json_response(response)

            if workflow and 'steps' in workflow:
                return workflow
            else:
                log.error(f"[ProposeValidate] Invalid workflow structure in response")
                return None

        except Exception as e:
            log.error(f"[ProposeValidate] Failed to propose workflow: {e}")
            return None

    def _refine_workflow(
        self,
        current_workflow: Dict,
        validation: WorkflowValidation,
        user_intent: str,
        domain: AnalysisDomain
    ) -> Optional[Dict]:
        """Refine workflow based on validation feedback."""

        # Generate refinement prompt
        refinement_prompt = self.validator.generate_refinement_prompt(
            validation, current_workflow
        )

        # Add context
        full_prompt = f"""You are refining a bioinformatics workflow for: {user_intent}

{refinement_prompt}

IMPORTANT:
- Use the exact tool names from "Alternatives" when available
- Keep the workflow structure similar but with available tools
- Maintain the same analysis goals

Return ONLY the revised JSON workflow (no explanation):"""

        try:
            response = self.llm_client.generate(full_prompt, max_tokens=2000)
            refined = self._parse_json_response(response)

            if refined and 'steps' in refined:
                return refined
            else:
                log.warning("[ProposeValidate] Refinement returned invalid structure")
                return None

        except Exception as e:
            log.error(f"[ProposeValidate] Refinement failed: {e}")
            return None

    def _parse_json_response(self, response: str) -> Optional[Dict]:
        """Parse JSON from LLM response, handling various formats."""
        response = response.strip()

        # Try direct parse
        try:
            return json.loads(response)
        except json.JSONDecodeError:
            pass

        # Try extracting JSON from markdown code block
        import re
        json_match = re.search(r'```(?:json)?\s*([\s\S]*?)```', response)
        if json_match:
            try:
                return json.loads(json_match.group(1))
            except json.JSONDecodeError:
                pass

        # Try finding JSON object
        json_match = re.search(r'\{[\s\S]*\}', response)
        if json_match:
            try:
                return json.loads(json_match.group(0))
            except json.JSONDecodeError:
                pass

        log.error(f"[ProposeValidate] Could not parse JSON from response: {response[:200]}...")
        return None

    def _validation_to_dict(self, validation: WorkflowValidation) -> Dict:
        """Convert WorkflowValidation to serializable dict."""
        return {
            'workflow_name': validation.workflow_name,
            'all_tools_available': validation.all_tools_available,
            'all_tools_recommended': validation.all_tools_recommended,
            'needs_refinement': validation.needs_refinement,
            'confidence_score': validation.confidence_score,
            'refinement_suggestions': validation.refinement_suggestions,
            'steps': [
                {
                    'step_number': s.step_number,
                    'proposed_tool': s.proposed_tool,
                    'purpose': s.purpose,
                    'tool_status': s.tool_validation.status,
                    'galaxy_tool_id': s.tool_validation.galaxy_tool_id,
                    'confidence': s.tool_validation.confidence,
                    'warnings': s.knowledge_validation.warnings if s.knowledge_validation else []
                }
                for s in validation.steps
            ]
        }

    def _build_galaxy_workflow(
        self,
        workflow: Dict,
        validation: WorkflowValidation,
        user_intent: str
    ) -> Dict:
        """Build Galaxy .ga format workflow from validated structure."""

        steps = {}
        for i, step in enumerate(validation.steps):
            tv = step.tool_validation

            # Use validated tool ID if available, otherwise use proposed name
            tool_id = tv.galaxy_tool_id if tv.galaxy_tool_id else step.proposed_tool

            # Normalize Biomni tool IDs
            if tool_id.startswith('biomni/'):
                tool_id = tool_id.replace('/', '_')

            steps[str(i)] = {
                'id': i,
                'tool_id': tool_id,
                'type': 'tool',
                'name': step.proposed_tool,
                'annotation': step.purpose,
                'tool_state': json.dumps(
                    workflow['steps'][i].get('key_parameters', {})
                ),
                'position': {
                    'left': 200 + i * 300,
                    'top': 200
                },
                'inputs': []
            }

        return {
            'a_galaxy_workflow': 'true',
            'format-version': '0.1',
            'name': workflow.get('workflow_name', 'AI-Generated Workflow'),
            'annotation': workflow.get('description', user_intent),
            'tags': ['ai-generated', 'propose-validate'],
            'steps': steps
        }


def create_propose_validate_generator(config: AIConfig = None) -> ProposeValidateWorkflowGenerator:
    """Factory function to create ProposeValidateWorkflowGenerator."""
    return ProposeValidateWorkflowGenerator(config)
