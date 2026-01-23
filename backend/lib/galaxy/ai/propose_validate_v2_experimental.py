"""
Propose-Validate Workflow Generator V2 (Experimental)

Enhanced version with:
1. Search existing workflows for reference before proposing
2. Get available tools for the domain
3. Dynamic confidence-based iteration (not fixed)
4. User feedback refinement support

This is an EXPERIMENTAL implementation for testing.
Do not use in production until validated.
"""

import json
import logging
from typing import Dict, List, Any, Optional, Tuple
from dataclasses import dataclass, field

log = logging.getLogger(__name__)


@dataclass
class ReferenceContext:
    """Context gathered before LLM proposal."""
    similar_workflows: List[Dict] = field(default_factory=list)
    available_tools: List[Dict] = field(default_factory=list)
    decision_rules: List[Dict] = field(default_factory=list)
    domain: str = "generic"


@dataclass
class ProposalResult:
    """Result of workflow proposal with validation."""
    workflow: Dict
    confidence: float
    all_tools_available: bool
    warnings: List[str]
    iteration: int
    needs_refinement: bool


class ProposeValidateV2Experimental:
    """
    Enhanced workflow generator with reference search and dynamic iteration.

    Key differences from V1:
    - Searches existing workflows before proposing (informed proposal)
    - Gets available tools for domain (constrained by reality)
    - Dynamic iteration until confidence threshold (not fixed 2)
    - Support for user feedback refinement
    """

    # Configuration
    CONFIDENCE_THRESHOLD = 0.85  # Continue refining until this
    MAX_ITERATIONS = 5  # Safety limit
    MIN_REFERENCE_WORKFLOWS = 2  # Minimum similar workflows to find

    def __init__(self, config=None):
        self.config = config
        self._workflow_search = None
        self._tool_validator = None
        self._knowledge_db = None
        self._llm_client = None

    def _lazy_init(self):
        """Lazy initialization of dependencies."""
        if self._workflow_search is None:
            try:
                from .unified_workflow_search import get_workflow_search
                self._workflow_search = get_workflow_search()
            except ImportError:
                log.warning("UnifiedWorkflowSearch not available")
                self._workflow_search = None

        if self._tool_validator is None:
            try:
                from .workflow_proposal_validator import ToolIndexValidator
                self._tool_validator = ToolIndexValidator()
            except ImportError:
                log.warning("ToolIndexValidator not available")
                self._tool_validator = None

        if self._knowledge_db is None:
            try:
                from .benchmark_knowledge import BenchmarkKnowledgeDB
                self._knowledge_db = BenchmarkKnowledgeDB()
            except ImportError:
                log.warning("BenchmarkKnowledgeDB not available")
                self._knowledge_db = None

        if self._llm_client is None:
            try:
                from .llm_client import LLMClient
                from .config import DEFAULT_AI_CONFIG
                self._llm_client = LLMClient(self.config or DEFAULT_AI_CONFIG)
            except ImportError:
                log.warning("LLMClient not available")
                self._llm_client = None

    def generate_workflow(
        self,
        user_intent: str,
        data_characteristics: Dict[str, Any] = None,
        constraints: Dict[str, Any] = None
    ) -> Dict[str, Any]:
        """
        Generate workflow with reference search and dynamic iteration.

        Flow:
        1. Gather reference context (search workflows, get tools, get rules)
        2. LLM proposes with context (informed proposal)
        3. Validate and refine until confidence threshold or max iterations
        4. Return with full validation info
        """
        self._lazy_init()

        data_characteristics = data_characteristics or {}
        constraints = constraints or {}

        log.info(f"[ProposeValidateV2] Starting for: {user_intent}")

        # Detect domain
        try:
            from .domain_workflow_patterns import detect_domain
            domain = detect_domain(user_intent)
            domain_value = domain.value
        except ImportError:
            domain_value = "generic"
            domain = None

        log.info(f"[ProposeValidateV2] Domain: {domain_value}")

        # Phase 1: Gather reference context
        log.info("[ProposeValidateV2] Phase 1: Gathering reference context...")
        context = self._gather_reference_context(user_intent, domain_value)

        log.info(f"[ProposeValidateV2] Found {len(context.similar_workflows)} similar workflows, "
                f"{len(context.available_tools)} available tools")

        # Phase 2: LLM proposes with context
        log.info("[ProposeValidateV2] Phase 2: LLM proposing with context...")
        proposal = self._propose_with_context(user_intent, context, data_characteristics)

        if not proposal:
            return {
                'success': False,
                'error': 'Failed to generate workflow proposal',
                'context_gathered': {
                    'similar_workflows': len(context.similar_workflows),
                    'available_tools': len(context.available_tools)
                }
            }

        log.info(f"[ProposeValidateV2] Initial proposal: {len(proposal.get('steps', []))} steps")

        # Phase 3: Dynamic validation and refinement
        log.info("[ProposeValidateV2] Phase 3: Validate and refine...")
        refinement_history = []
        current_workflow = proposal

        iteration = 0
        while iteration < self.MAX_ITERATIONS:
            # Validate current workflow
            validation_result = self._validate_workflow(current_workflow, data_characteristics)

            refinement_history.append({
                'iteration': iteration,
                'workflow': current_workflow,
                'confidence': validation_result['confidence'],
                'all_tools_available': validation_result['all_tools_available'],
                'warnings': validation_result['warnings']
            })

            log.info(f"[ProposeValidateV2] Iteration {iteration}: "
                    f"confidence={validation_result['confidence']:.2f}, "
                    f"all_available={validation_result['all_tools_available']}")

            # Check if confidence threshold reached
            if (validation_result['confidence'] >= self.CONFIDENCE_THRESHOLD
                and validation_result['all_tools_available']):
                log.info(f"[ProposeValidateV2] Confidence threshold reached at iteration {iteration}")
                break

            # Check if no improvement possible (all tools available but low confidence)
            if validation_result['all_tools_available'] and not validation_result['warnings']:
                log.info("[ProposeValidateV2] All tools available, no warnings - accepting current")
                break

            # Refine with feedback
            refined = self._refine_with_feedback(
                current_workflow,
                validation_result,
                user_intent,
                context
            )

            if refined and refined != current_workflow:
                current_workflow = refined
            else:
                log.info("[ProposeValidateV2] No further refinement possible")
                break

            iteration += 1

        # Final validation
        final_validation = self._validate_workflow(current_workflow, data_characteristics)

        # Build Galaxy format
        galaxy_workflow = self._build_galaxy_workflow(current_workflow, final_validation, user_intent)

        return {
            'success': True,
            'workflow': current_workflow,
            'workflow_ga': galaxy_workflow,
            'validation': final_validation,
            'refinement_history': refinement_history,
            'confidence': final_validation['confidence'],
            'domain': domain_value,
            'all_tools_available': final_validation['all_tools_available'],
            'iterations': iteration + 1,
            'context_used': {
                'similar_workflows': len(context.similar_workflows),
                'available_tools': len(context.available_tools),
                'decision_rules': len(context.decision_rules)
            },
            'needs_user_review': final_validation['confidence'] < self.CONFIDENCE_THRESHOLD
        }

    def _gather_reference_context(self, user_intent: str, domain: str) -> ReferenceContext:
        """
        Gather reference context before proposing.

        This is the key difference from V1 - we search for:
        1. Similar existing workflows
        2. Available tools for this domain
        3. Decision rules from benchmarks
        """
        context = ReferenceContext(domain=domain)

        # 1. Search existing workflows
        if self._workflow_search:
            try:
                results = self._workflow_search.search(user_intent, limit=5)
                context.similar_workflows = [
                    {
                        'name': r.name,
                        'description': r.description,
                        'score': r.score,
                        'steps': self._extract_workflow_steps(r)
                    }
                    for r in results[:3]  # Top 3
                ]
                log.info(f"[ProposeValidateV2] Found {len(context.similar_workflows)} similar workflows")
            except Exception as e:
                log.warning(f"[ProposeValidateV2] Workflow search failed: {e}")

        # 2. Get available tools for domain
        if self._tool_validator:
            try:
                # Get common tools that are available
                common_tools = self._get_common_domain_tools(domain)
                for tool_name in common_tools:
                    validation = self._tool_validator.validate_tool(tool_name, domain)
                    if validation.status == "FOUND":
                        context.available_tools.append({
                            'name': tool_name,
                            'galaxy_id': validation.galaxy_tool_id,
                            'confidence': validation.confidence
                        })
                log.info(f"[ProposeValidateV2] Found {len(context.available_tools)} available tools")
            except Exception as e:
                log.warning(f"[ProposeValidateV2] Tool validation failed: {e}")

        # 3. Get decision rules from benchmarks (skip for now - semantic search is slow)
        # TODO: Re-enable once semantic search is optimized
        # if self._knowledge_db:
        #     try:
        #         results = self._knowledge_db.query_semantic(
        #             f"{domain} analysis best practices tools",
        #             top_k=5
        #         )
        #         context.decision_rules = [
        #             {'description': r.get('description', r.get('content', ''))}
        #             for r in results
        #         ] if results else []
        #     except Exception as e:
        #         log.warning(f"[ProposeValidateV2] Knowledge lookup failed: {e}")
        context.decision_rules = []  # Skip slow semantic search for now

        return context

    def _get_common_domain_tools(self, domain: str) -> List[str]:
        """Get common tools for a domain to check availability."""
        domain_tools = {
            'transcriptomics': ['FastQC', 'Trimmomatic', 'HISAT2', 'STAR', 'Salmon',
                               'featureCounts', 'DESeq2', 'edgeR', 'Kallisto'],
            'variant_calling': ['FastQC', 'BWA', 'Bowtie2', 'SAMtools', 'BCFtools',
                               'GATK', 'FreeBayes', 'VCFtools'],
            'chip_seq': ['FastQC', 'Bowtie2', 'BWA', 'SAMtools', 'MACS2',
                        'deepTools', 'bedtools', 'HOMER'],
            'metagenomics': ['FastQC', 'Trimmomatic', 'MetaPhlAn', 'Kraken2',
                           'HUMAnN', 'QIIME2', 'MEGAHIT'],
            'proteomics': ['MaxQuant', 'Perseus', 'MSFragger', 'SearchGUI',
                          'PeptideShaker'],
            'generic': ['FastQC', 'Trimmomatic', 'BWA', 'SAMtools', 'bedtools']
        }
        return domain_tools.get(domain, domain_tools['generic'])

    def _extract_workflow_steps(self, workflow_result) -> List[Dict]:
        """Extract step info from workflow search result."""
        steps = []
        try:
            if hasattr(workflow_result, 'workflow_json') and workflow_result.workflow_json:
                wf_data = json.loads(workflow_result.workflow_json) if isinstance(
                    workflow_result.workflow_json, str) else workflow_result.workflow_json
                if 'steps' in wf_data:
                    for step_id, step_data in wf_data['steps'].items():
                        if step_data.get('tool_id'):
                            steps.append({
                                'tool_id': step_data.get('tool_id'),
                                'name': step_data.get('name', ''),
                                'annotation': step_data.get('annotation', '')
                            })
        except Exception as e:
            log.debug(f"Could not extract steps: {e}")
        return steps

    def _propose_with_context(
        self,
        user_intent: str,
        context: ReferenceContext,
        data_characteristics: Dict
    ) -> Optional[Dict]:
        """
        Generate proposal using LLM WITH reference context.

        This is informed proposal - LLM sees:
        - Similar existing workflows
        - Available tools
        - Best practices from benchmarks
        """
        if not self._llm_client:
            log.error("[ProposeValidateV2] LLM client not available")
            return None

        # Build context for prompt
        workflow_examples = ""
        if context.similar_workflows:
            workflow_examples = "SIMILAR EXISTING WORKFLOWS (use as reference):\n"
            for wf in context.similar_workflows[:2]:
                workflow_examples += f"- {wf['name']}: {wf.get('description', '')[:100]}\n"
                if wf.get('steps'):
                    workflow_examples += f"  Steps: {', '.join(s.get('name', s.get('tool_id', '')) for s in wf['steps'][:5])}\n"

        available_tools_text = ""
        if context.available_tools:
            available_tools_text = "AVAILABLE TOOLS IN OUR SYSTEM (prefer these):\n"
            available_tools_text += ", ".join(t['name'] for t in context.available_tools[:15])
            available_tools_text += "\n"

        rules_text = ""
        if context.decision_rules:
            rules_text = "BEST PRACTICES:\n"
            for rule in context.decision_rules[:3]:
                rules_text += f"- {rule.get('description', rule.get('rule', ''))}\n"

        data_info = ""
        if data_characteristics:
            data_info = "DATA CHARACTERISTICS:\n" + "\n".join([
                f"- {k}: {v}" for k, v in data_characteristics.items()
            ])

        prompt = f"""You are an expert bioinformatics workflow designer.

Design a workflow for this task:
USER REQUEST: {user_intent}

DOMAIN: {context.domain}

{workflow_examples}
{available_tools_text}
{rules_text}
{data_info}

IMPORTANT INSTRUCTIONS:
1. PREFER tools from the "AVAILABLE TOOLS" list - they are confirmed to work in our system
2. Reference the similar workflows for structure guidance
3. Follow best practices from the rules provided
4. Use standard tool names (FastQC, HISAT2, DESeq2, etc.)

Return ONLY valid JSON (no markdown, no explanation):
{{
  "workflow_name": "Descriptive name",
  "description": "Brief description",
  "steps": [
    {{
      "step": 1,
      "tool_name": "ToolName",
      "purpose": "What this step does",
      "key_parameters": {{}},
      "justification": "Why this tool"
    }}
  ]
}}"""

        try:
            response = self._llm_client.generate(prompt, max_tokens=2000)
            return self._parse_json_response(response)
        except Exception as e:
            log.error(f"[ProposeValidateV2] LLM proposal failed: {e}")
            return None

    def _validate_workflow(self, workflow: Dict, data_characteristics: Dict) -> Dict:
        """Validate workflow and return structured result."""
        if not workflow or 'steps' not in workflow:
            return {
                'confidence': 0.0,
                'all_tools_available': False,
                'warnings': ['Invalid workflow structure'],
                'step_validations': []
            }

        step_validations = []
        all_available = True
        warnings = []
        total_confidence = 0.0

        for step in workflow.get('steps', []):
            tool_name = step.get('tool_name', '')
            purpose = step.get('purpose', '')

            step_result = {
                'tool_name': tool_name,
                'purpose': purpose,
                'status': 'UNKNOWN',
                'galaxy_tool_id': None,
                'confidence': 0.5,
                'warnings': []
            }

            if self._tool_validator:
                try:
                    validation = self._tool_validator.validate_tool(tool_name, purpose)
                    step_result['status'] = validation.status
                    step_result['galaxy_tool_id'] = validation.galaxy_tool_id
                    step_result['confidence'] = validation.confidence

                    if validation.status == "MISSING":
                        all_available = False
                        warnings.append(f"Tool '{tool_name}' not available")
                    elif validation.status == "SUBSTITUTE":
                        warnings.append(f"Tool '{tool_name}' substituted with '{validation.galaxy_tool_id}'")
                except Exception as e:
                    log.warning(f"Tool validation failed for {tool_name}: {e}")

            total_confidence += step_result['confidence']
            step_validations.append(step_result)

        avg_confidence = total_confidence / len(step_validations) if step_validations else 0.0

        return {
            'confidence': avg_confidence,
            'all_tools_available': all_available,
            'warnings': warnings,
            'step_validations': step_validations
        }

    def _refine_with_feedback(
        self,
        workflow: Dict,
        validation: Dict,
        user_intent: str,
        context: ReferenceContext
    ) -> Optional[Dict]:
        """Refine workflow based on validation feedback."""
        if not self._llm_client:
            return None

        # Build feedback summary
        issues = []
        for step_val in validation.get('step_validations', []):
            if step_val['status'] == 'MISSING':
                issues.append(f"- Tool '{step_val['tool_name']}' is NOT AVAILABLE")
            elif step_val['status'] == 'SUBSTITUTE':
                issues.append(f"- Tool '{step_val['tool_name']}' was substituted")

        if not issues:
            return workflow  # No refinement needed

        # Available alternatives
        alternatives = ""
        if context.available_tools:
            alternatives = "AVAILABLE ALTERNATIVES:\n" + ", ".join(
                t['name'] for t in context.available_tools
            )

        prompt = f"""Your proposed workflow needs refinement.

ORIGINAL WORKFLOW:
{json.dumps(workflow, indent=2)}

ISSUES FOUND:
{chr(10).join(issues)}

{alternatives}

Please revise the workflow:
1. Replace unavailable tools with available alternatives
2. Keep the same analysis goals
3. Maintain workflow structure

Return ONLY the revised JSON workflow:"""

        try:
            response = self._llm_client.generate(prompt, max_tokens=2000)
            return self._parse_json_response(response)
        except Exception as e:
            log.error(f"[ProposeValidateV2] Refinement failed: {e}")
            return None

    def refine_with_user_feedback(
        self,
        workflow: Dict,
        user_feedback: str,
        feedback_type: str = "chat"
    ) -> Dict[str, Any]:
        """
        Refine workflow based on user feedback.

        Args:
            workflow: Current workflow
            user_feedback: User's feedback (e.g., "Use Salmon instead of HISAT2")
            feedback_type: Type of feedback ('chat', 'modify_step', 'add_step', 'remove_step')

        Returns:
            Updated workflow with validation
        """
        self._lazy_init()

        if not self._llm_client:
            return {
                'success': False,
                'error': 'LLM client not available'
            }

        prompt = f"""Modify this bioinformatics workflow based on user feedback.

CURRENT WORKFLOW:
{json.dumps(workflow, indent=2)}

USER FEEDBACK: {user_feedback}

Apply the user's requested changes while maintaining workflow validity.
Return ONLY the modified JSON workflow:"""

        try:
            response = self._llm_client.generate(prompt, max_tokens=2000)
            refined = self._parse_json_response(response)

            if refined:
                validation = self._validate_workflow(refined, {})
                return {
                    'success': True,
                    'workflow': refined,
                    'validation': validation,
                    'feedback_applied': user_feedback
                }
            else:
                return {
                    'success': False,
                    'error': 'Could not parse refined workflow'
                }
        except Exception as e:
            return {
                'success': False,
                'error': str(e)
            }

    def _parse_json_response(self, response: str) -> Optional[Dict]:
        """Parse JSON from LLM response."""
        import re
        response = response.strip()

        # Try direct parse
        try:
            return json.loads(response)
        except json.JSONDecodeError:
            pass

        # Try markdown code block
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

        return None

    def _build_galaxy_workflow(self, workflow: Dict, validation: Dict, user_intent: str) -> Dict:
        """Build Galaxy .ga format."""
        steps = {}
        for i, step in enumerate(workflow.get('steps', [])):
            step_val = validation['step_validations'][i] if i < len(validation['step_validations']) else {}
            tool_id = step_val.get('galaxy_tool_id') or step.get('tool_name', 'unknown')

            if tool_id.startswith('biomni/'):
                tool_id = tool_id.replace('/', '_')

            steps[str(i)] = {
                'id': i,
                'tool_id': tool_id,
                'type': 'tool',
                'name': step.get('tool_name', ''),
                'annotation': step.get('purpose', ''),
                'tool_state': json.dumps(step.get('key_parameters', {})),
                'position': {'left': 200 + i * 300, 'top': 200},
                'inputs': []
            }

        return {
            'a_galaxy_workflow': 'true',
            'format-version': '0.1',
            'name': workflow.get('workflow_name', 'AI-Generated Workflow'),
            'annotation': workflow.get('description', user_intent),
            'tags': ['ai-generated', 'propose-validate-v2'],
            'steps': steps
        }


def create_v2_generator(config=None) -> ProposeValidateV2Experimental:
    """Factory function."""
    return ProposeValidateV2Experimental(config)
