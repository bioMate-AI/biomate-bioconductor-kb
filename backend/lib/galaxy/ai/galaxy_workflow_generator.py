"""
Galaxy Workflow Generator with Tool Validation and Dataset Integration

Generates Galaxy .ga workflow JSON using:
1. UnifiedToolSearch - multi-stage retrieval (LLM + vector + FTS5)
2. Claude LLM - generate workflow from retrieved tools only
3. WorkflowDatasetSelector - add datasets to workflow steps
4. ToolKnowledgeProvider - inject citations and best practices

This ensures NO non-existent tools are used in generated workflows.
"""

import os
import json
import logging
from typing import Dict, List, Any, Optional, Tuple
from pathlib import Path

from .domain_workflow_patterns import (
    AnalysisDomain, detect_domain, get_domain_pattern,
    format_phases_for_llm, get_phases_for_domain
)

log = logging.getLogger(__name__)

# Lazy import for tool knowledge provider
_tool_knowledge_provider = None

def get_tool_knowledge_provider():
    """Get singleton tool knowledge provider."""
    global _tool_knowledge_provider
    if _tool_knowledge_provider is None:
        try:
            from .tool_knowledge_provider import ToolKnowledgeProvider
            _tool_knowledge_provider = ToolKnowledgeProvider()
            log.info("Initialized ToolKnowledgeProvider for citation injection")
        except Exception as e:
            log.warning(f"Failed to initialize ToolKnowledgeProvider: {e}")
    return _tool_knowledge_provider


class GalaxyWorkflowGenerator:
    """
    LLM-based Galaxy workflow generator with tool validation.

    Architecture:
    1. Tool Retrieval: UnifiedToolSearch with LLM + vector + FTS5
    2. Workflow Generation: LLM creates workflow using ONLY retrieved tools
    3. Dataset Integration: WorkflowDatasetSelector adds datasets
    4. .ga JSON Output: Generate Galaxy workflow format
    """

    def __init__(
        self,
        tool_search_index=None,
        dataset_selector=None,
        config=None
    ):
        """Initialize workflow generator with tool index and dataset selector."""
        # Use LLMClient for multi-provider support (OpenAI, Anthropic, etc.)
        if config is None:
            from .config import DEFAULT_AI_CONFIG
            config = DEFAULT_AI_CONFIG

        self.config = config
        from .llm_client import LLMClient
        self.llm_client = LLMClient(config)

        # Tool search - lazy loaded to avoid heavy imports
        self._tool_search = tool_search_index
        self._tool_search_loaded = False

        # Dataset selector for dataset integration
        if dataset_selector is None:
            from .workflow_dataset_selector import WorkflowDatasetSelector
            self.dataset_selector = WorkflowDatasetSelector()
        else:
            self.dataset_selector = dataset_selector

        # LLM Parameter Generator for intelligent parameter inference
        from .llm_parameter_generator import LLMParameterGenerator
        self.parameter_generator = LLMParameterGenerator(config=self.config)

    @property
    def tool_index(self):
        """Lazy-load unified tool search on first access."""
        if not self._tool_search_loaded:
            if self._tool_search is None:
                # Use UnifiedToolSearch for multi-stage retrieval
                try:
                    from .unified_tool_search import create_unified_search
                    self._tool_search = create_unified_search(
                        llm_client=self.llm_client
                    )
                    log.info("Initialized UnifiedToolSearch with LLM support")
                except Exception as e:
                    log.warning(f"Failed to initialize UnifiedToolSearch: {e}")
                    # Fallback to basic ToolSearchIndex
                    from galaxy.tools.search_index import ToolSearchIndex
                    self._tool_search = ToolSearchIndex()
                    log.info("Fallback to basic ToolSearchIndex")
            self._tool_search_loaded = True
        return self._tool_search

    def generate_workflow(
        self,
        user_intent: str,
        max_tools_search: int = 30,
        progress_callback: callable = None
    ) -> Dict[str, Any]:
        """
        Generate complete Galaxy workflow with datasets and progress tracking.

        Args:
            user_intent: User's research goal
                Example: "Identify metabolites from human serum LC-MS data"
            max_tools_search: Max tools to retrieve from index for LLM context
            progress_callback: Optional callback function for progress updates
                Signature: callback(step: str, progress: float, message: str, details: dict)

        Returns:
            Dict with:
            - workflow_ga: Galaxy .ga JSON
            - tool_selections: Tools selected from index
            - dataset_assignments: Datasets assigned to steps
            - reasoning: LLM reasoning for workflow design
            - generation_progress: List of progress steps taken
        """

        # Progress tracking
        progress_steps = []

        def report_progress(step: str, progress: float, message: str, details: dict = None):
            """Report progress to callback and log."""
            progress_info = {
                "step": step,
                "progress": progress,
                "message": message,
                "details": details or {}
            }
            progress_steps.append(progress_info)
            log.info(f"[WorkflowGen Progress] {step}: {message} ({progress*100:.0f}%)")
            if progress_callback:
                try:
                    progress_callback(step, progress, message, details or {})
                except Exception as e:
                    log.warning(f"Progress callback failed: {e}")

        # STEP 0: Detect analysis domain from user intent
        detected_domain = detect_domain(user_intent)
        report_progress("domain_detection", 0.05, f"Detected domain: {detected_domain.value}", {
            "domain": detected_domain.value,
            "domain_description": get_domain_pattern(detected_domain).description
        })

        # STEP 1: Retrieve available tools from index
        report_progress("tool_search", 0.1, "Searching for relevant tools...", {"user_intent": user_intent})
        log.info(f"Retrieving tools for: {user_intent}")
        available_tools = self._retrieve_tools_from_index(user_intent, max_tools_search)

        if not available_tools:
            return {
                "success": False,
                "error": "No tools found in index matching the query",
                "message": f"No tools found for query: {user_intent}"
            }

        log.info(f"Retrieved {len(available_tools)} tools from index")
        report_progress("tool_search", 0.2, f"Found {len(available_tools)} relevant tools", {"tool_count": len(available_tools)})

        # STEP 2: Generate workflow structure using LLM (ONLY from retrieved tools)
        report_progress("workflow_design", 0.3, f"Designing {detected_domain.value} workflow structure...", {
            "phase": "llm_generation",
            "domain": detected_domain.value
        })
        log.info(f"Generating {detected_domain.value} workflow structure with LLM...")
        workflow_structure = self._generate_workflow_structure(
            user_intent,
            available_tools,
            detected_domain=detected_domain
        )

        if not workflow_structure or 'error' in workflow_structure:
            report_progress("workflow_design", 0.3, "Workflow design failed", {"error": workflow_structure.get('error', 'Unknown error')})
            return {
                "success": False,
                "error": "Workflow generation failed",
                "message": workflow_structure.get('error', 'Unknown error')
            }

        step_count = len(workflow_structure.get('steps', []))
        phases = workflow_structure.get('phases', [])
        report_progress("workflow_design", 0.5, f"Designed {step_count}-step workflow", {
            "step_count": step_count,
            "phases": [p.get('phase') for p in phases] if phases else [],
            "workflow_name": workflow_structure.get('workflow_name', '')
        })

        # STEP 2.5: Validate tool chain compatibility
        is_compatible, compatibility_warnings = self.validate_workflow_compatibility(workflow_structure)
        if compatibility_warnings:
            log.warning(f"Workflow compatibility warnings: {compatibility_warnings}")
            report_progress("validation", 0.55, f"Compatibility check: {len(compatibility_warnings)} warnings", {
                "warnings": compatibility_warnings
            })
        else:
            report_progress("validation", 0.55, "Workflow compatibility validated", {})

        # STEP 3: Select datasets for workflow steps
        report_progress("dataset_selection", 0.6, "Selecting datasets for workflow...", {"phase": "dataset_matching"})
        log.info("Selecting datasets for workflow steps...")
        dataset_assignments = self.dataset_selector.select_datasets_for_workflow(
            workflow=workflow_structure,
            user_intent=user_intent
        )
        report_progress("dataset_selection", 0.7, "Datasets assigned to workflow steps", {"assignments": len(dataset_assignments.get('workflow_steps', []))})

        # STEP 4: Build Galaxy .ga JSON with LLM parameter generation
        report_progress("workflow_build", 0.8, "Building Galaxy workflow with parameters...", {"phase": "ga_json_generation"})
        log.info("Building Galaxy .ga workflow JSON...")
        galaxy_workflow, generated_parameters = self._build_galaxy_workflow_json(
            workflow_structure,
            dataset_assignments,
            user_intent=user_intent
        )
        report_progress("workflow_build", 0.9, "Workflow JSON created", {"parameter_count": len(generated_parameters)})

        # STEP 5: Collect citations and generate methods section
        report_progress("finalization", 0.95, "Collecting citations and finalizing...", {"phase": "citations"})
        citations = []
        methods_section = None
        knowledge_provider = get_tool_knowledge_provider()
        if knowledge_provider:
            try:
                # Collect citations for all tools
                for step in workflow_structure.get('steps', []):
                    tool_id = step.get('tool_id', '')
                    if tool_id:
                        knowledge = knowledge_provider.get_tool_knowledge(tool_id)
                        if knowledge and knowledge.citation:
                            citations.append({
                                "tool_id": tool_id,
                                "tool_name": step.get('tool_name', tool_id),
                                "citation": knowledge.citation.to_dict()
                            })

                # Generate methods section if we have citations
                if citations:
                    try:
                        from .methods_generator import MethodsSectionGenerator
                        methods_gen = MethodsSectionGenerator(knowledge_provider)
                        methods_section = methods_gen.generate(
                            galaxy_workflow,
                            citation_style="short",
                            include_parameters=True
                        )
                    except Exception as e:
                        log.debug(f"Methods generation failed: {e}")

            except Exception as e:
                log.warning(f"Failed to collect citations: {e}")

        # Final progress report
        report_progress("complete", 1.0, "Workflow generation complete!", {
            "workflow_name": workflow_structure.get('workflow_name', ''),
            "step_count": len(workflow_structure.get('steps', [])),
            "citation_count": len(citations)
        })

        return {
            "success": True,
            "workflow_ga": galaxy_workflow,
            "workflow_structure": workflow_structure,
            "dataset_assignments": dataset_assignments,
            "tool_selections": available_tools,
            "user_intent": user_intent,
            "detected_domain": detected_domain.value,  # Domain-specific workflow type
            "domain_description": get_domain_pattern(detected_domain).description,
            "generated_parameters": generated_parameters,  # LLM-generated parameters with confidence scores
            "citations": citations,  # Tool citations with DOI/PMID
            "methods_section": methods_section,  # Auto-generated methods text
            "generation_progress": progress_steps,  # Progress tracking for UI
            "compatibility_validated": is_compatible,  # Tool chain compatibility
            "compatibility_warnings": compatibility_warnings  # Any format mismatches detected
        }

    def _retrieve_tools_from_index(
        self,
        user_intent: str,
        limit: int = 30
    ) -> List[Dict[str, Any]]:
        """
        Retrieve available tools using UnifiedToolSearch.

        Uses multi-stage retrieval:
        1. LLM query analysis (extract entities, infer category)
        2. Direct entity matching
        3. Vector similarity search
        4. FTS5 full-text search
        5. Result fusion with RRF

        This ensures we only use tools that exist in Galaxy.
        """
        try:
            log.info(f"Searching for tools with query: {user_intent}")

            # Use unified search - handles query analysis and multi-stage retrieval
            results = self.tool_index.search(user_intent, limit=limit)

            log.info(f"Found {len(results)} tools from unified search")

            # Format tools for LLM context - include rich metadata for parameter generation
            formatted_tools = []
            for tool in results:
                # Parse JSON fields if they're strings
                parameters = tool.get('parameters', [])
                if isinstance(parameters, str):
                    try:
                        parameters = json.loads(parameters)
                    except:
                        parameters = []

                help_text = tool.get('help_text', {})
                if isinstance(help_text, str):
                    try:
                        help_text = json.loads(help_text)
                    except:
                        help_text = {}

                examples = tool.get('examples', [])
                if isinstance(examples, str):
                    try:
                        examples = json.loads(examples)
                    except:
                        examples = []

                scientific_context = tool.get('scientific_context', {})
                if isinstance(scientific_context, str):
                    try:
                        scientific_context = json.loads(scientific_context)
                    except:
                        scientific_context = {}

                # best_practice_functions: ordered function sequence with I/O
                # (98% coverage for Bioconductor, 14% for Galaxy ToolShed)
                best_practice_functions = tool.get('best_practice_functions', {})
                if isinstance(best_practice_functions, str):
                    try:
                        best_practice_functions = json.loads(best_practice_functions)
                    except Exception:
                        best_practice_functions = {}

                formatted_tools.append({
                    'tool_id': tool['tool_id'],
                    'name': tool['name'],
                    'description': tool.get('description', ''),
                    'version': tool.get('version', ''),
                    'category': tool.get('category', ''),
                    'keywords': tool.get('keywords', ''),
                    'repo_owner': tool.get('repo_owner', ''),
                    'repo_name': tool.get('repo_name', ''),
                    'relevance_score': tool.get('rrf_score', 0),
                    'wrapper_path': tool.get('wrapper_path', ''),  # path to .nf file if available
                    'language': tool.get('language', ''),
                    # Rich metadata for LLM parameter generation
                    'parameters': parameters,
                    'help_text': help_text,
                    'examples': examples,
                    'scientific_context': scientific_context,
                    'usage_guide': tool.get('usage_guide', ''),
                    'best_practice_functions': best_practice_functions,
                })

            return formatted_tools

        except Exception as e:
            log.error(f"Tool retrieval failed: {e}")
            return []

    def _sanitize_fts_query(self, query: str) -> str:
        """
        Sanitize FTS5 query to prevent syntax errors.

        Handles common bioinformatics terms:
        - LC-MS → lcms
        - MS/MS → msms
        - m/z → mz
        """
        # Special character replacements for bioinformatics terms
        replacements = {
            'LC-MS': 'lcms',
            'MS/MS': 'msms',
            'm/z': 'mz',
            '-': ' ',
            '/': ' ',
            '(': ' ',
            ')': ' ',
            '"': '',
            "'": '',
            ':': ' ',
            ';': ' ',
            '!': ' ',
            '?': ' ',
        }

        sanitized = query
        for old, new in replacements.items():
            sanitized = sanitized.replace(old, new)

        # Remove multiple spaces
        sanitized = ' '.join(sanitized.split())

        # Remove FTS5 reserved words that could cause errors if used alone
        # But keep them if they're part of longer words
        reserved_words = ['NOT', 'AND', 'OR', 'NEAR']
        words = sanitized.split()
        words = [w for w in words if w.upper() not in reserved_words or len(w) > 3]

        return ' '.join(words)

    def _transform_intent_to_fts_query(self, user_intent: str) -> str:
        """
        Transform user intent to FTS5-compatible search query using LLM.

        FTS5 rules:
        - No special chars (hyphens, slashes, parentheses)
        - Use OR for alternatives
        - Use simple keywords
        """

        prompt = f"""Transform this user intent into a SQLite FTS5 search query.

User Intent: "{user_intent}"

# FTS5 Rules:
1. Extract 3-5 key technical terms (tools, methods, data types)
2. Remove special characters (-, /, parentheses)
3. Replace: "LC-MS" → "lcms", "MS/MS" → "msms", "m/z" → "mz"
4. Join keywords with OR for broad matching
5. Keep it simple - just keywords, no complex syntax

# Examples:
- "Identify metabolites from LC-MS data" → "metabolite OR metabolomics OR lcms OR identification"
- "Peak detection in chromatogram" → "peak OR detection OR chromatogram"
- "XCMS analysis" → "xcms OR peak OR msnbase"

Return ONLY the FTS5 query string, nothing else."""

        try:
            response = self.llm_client.generate(prompt, max_tokens=100)
            fts_query = response.strip()
            # Remove quotes if LLM added them
            fts_query = fts_query.strip('"').strip("'")

            return fts_query

        except Exception as e:
            log.error(f"Query transformation failed: {e}")
            # Fallback: simple keyword extraction
            words = user_intent.lower().split()
            keywords = [w for w in words if len(w) > 3][:5]
            return ' OR '.join(keywords)

    def _generate_workflow_structure(
        self,
        user_intent: str,
        available_tools: List[Dict[str, Any]],
        detected_domain: Optional[AnalysisDomain] = None
    ) -> Dict[str, Any]:
        """
        Generate intelligent workflow structure using LLM.

        CRITICAL: LLM can ONLY use tools from available_tools list.

        Uses domain-specific workflow phases (transcriptomics, genomics, proteomics, etc.)
        to guide workflow design following biological best practices.
        """

        # Detect domain if not provided
        tool_names = [t['name'] for t in available_tools]
        if detected_domain is None:
            detected_domain = detect_domain(user_intent, tool_names)

        log.info(f"Detected analysis domain: {detected_domain.value}")

        # Get domain-specific phases
        domain_phases_text = format_phases_for_llm(detected_domain)
        domain_pattern = get_domain_pattern(detected_domain)

        # Build tool catalog for LLM
        tool_catalog = self._build_tool_catalog(available_tools)

        system_prompt = f"""You are an expert bioinformatics workflow architect for BioMate.

Your task is to design COMPLETE, INTELLIGENT workflows that fully satisfy user needs.

## DETECTED ANALYSIS DOMAIN: {detected_domain.value.upper()}

## AVAILABLE TOOLS (Use ONLY these exact tool_ids):

{tool_catalog}

## GENERAL WORKFLOW DESIGN PRINCIPLES:

A well-designed workflow should follow these universal principles:

### PHASE 1: DATA VALIDATION (early)
- Check data quality and format
- Validate input parameters
- Report potential data issues

### PHASE 2: CORE ANALYSIS (middle)
- Perform the main analysis task requested by user
- Use appropriate tools in logical sequence
- Ensure outputs satisfy user's information needs

### PHASE 3: POST-PROCESSING (late, if applicable)
- Format results for readability
- Generate summaries and statistics
- Create visualizations (plots, charts)

### PHASE 4: OUTPUT PREPARATION (late)
- Prepare downloadable results
- Generate reports if appropriate
- Provide results in user-requested format

## DOMAIN-SPECIFIC IMPLEMENTATION:

For {detected_domain.value.upper()} analysis, the general principles map to these specific phases:

{domain_phases_text}

## WORKFLOW DESIGN GUIDANCE:

1. Apply GENERAL PRINCIPLES as overarching structure
2. Use DOMAIN-SPECIFIC phases for detailed implementation
3. Each phase should use appropriate tools from the AVAILABLE TOOLS list
4. Required domain phases MUST be included; optional phases based on user needs

## IMPORTANT GUIDELINES:

1. Use ONLY tools from the AVAILABLE TOOLS list (exact tool_id)
2. Consider what information the user ACTUALLY needs
3. Include visualization if it helps understanding
4. Provide summary/statistics where meaningful
5. Design for user convenience - ready-to-download outputs
6. Keep workflows efficient - don't add unnecessary steps

## TOOL SELECTION PRIORITY (CRITICAL):

When multiple tools can accomplish the same task, follow this STRICT priority order:

1. **[LOCAL] tools** - STRONGLY PREFERRED. These are pre-installed and ready to use immediately.
   - Tool IDs starting with "biomni/" are local tools
   - Tool IDs starting with "biomate_ai_tools/" are local docker-based tools
   - These have zero installation overhead and are fully tested

2. **[REQUIRES_INSTALL] tools** - Use ONLY when no local alternative exists.
   - Tool IDs starting with "toolshed.g2.bx.psu.edu/" require installation
   - These add delay and may fail due to dependency issues

ALWAYS prefer a local tool even if a ToolShed tool seems more feature-rich.
Only use ToolShed tools when the required functionality has NO local equivalent.

## CRITICAL - PARAMETER SELECTION FOR DATABASE/API TOOLS:

When selecting tools that query databases or APIs, pay attention to their parameters:

- If a tool has BOTH 'prompt' (natural language) AND 'endpoint' (direct API URL) parameters:
  - PREFER 'endpoint' when the query can be expressed as a specific API call
  - ONLY use 'prompt' for truly ambiguous queries that need LLM interpretation
  - Example: For "BRCA1 human protein" query, use endpoint like:
    "https://rest.uniprot.org/uniprotkb/search?query=gene:BRCA1+AND+organism_id:9606&format=json"
  - NOT prompt: "Find information about BRCA1 human protein"

- This avoids unnecessary LLM calls inside tools and provides direct, reliable results
- The workflow system (BioMate) should interpret user intent, NOT delegate to tool-internal LLMs

## OUTPUT FORMAT (JSON):

{{
  "workflow_name": "Descriptive title reflecting the analysis",
  "workflow_description": "Brief description of what this workflow accomplishes",
  "domain": "{detected_domain.value}",
  "user_need_addressed": "How this workflow satisfies the user's request",
  "phases": [
    {{
      "general_phase": "data_validation|core_analysis|post_processing|output_preparation",
      "domain_phase": "specific phase name from DOMAIN-SPECIFIC section",
      "phase_description": "What this phase accomplishes"
    }}
  ],
  "steps": [
    {{
      "step": 1,
      "general_phase": "data_validation|core_analysis|post_processing|output_preparation",
      "domain_phase": "specific domain phase name",
      "tool_id": "exact tool_id from AVAILABLE TOOLS",
      "tool_name": "human readable name",
      "purpose": "What this step does and why it's needed",
      "expected_output": "What output this step produces",
      "user_benefit": "How this step helps the user"
    }}
  ],
  "reasoning": "Overall workflow design rationale",
  "output_summary": "What outputs the user will receive from this workflow",
  "missing_capabilities": ["List any capabilities the user asked for that cannot be fulfilled"]
}}
"""

        # Build phase guidance for user prompt
        phase_names = [p.name for p in domain_pattern.phases if p.required]
        phase_list = '\n'.join([f"  - {name}" for name in phase_names])

        user_prompt = f"""## USER REQUEST:
{user_intent}

## DETECTED DOMAIN: {detected_domain.value.upper()}

## TASK:
Design a complete, intelligent workflow that:
1. Follows GENERAL PRINCIPLES: data_validation → core_analysis → post_processing → output_preparation
2. Implements DOMAIN-SPECIFIC phases for {detected_domain.value}:
{phase_list}

Consider:
- What information does the user actually need?
- Which domain phases are essential for this specific request?
- What format would be most useful for them?
- Should results include visualizations?

Design the workflow using ONLY tools from the AVAILABLE TOOLS list.
Return valid JSON only - no additional text.
"""

        try:
            # Combine system and user prompts for LLMClient
            full_prompt = f"{system_prompt}\n\n{user_prompt}"
            response_text = self.llm_client.generate(full_prompt, max_tokens=4096)

            log.info(f"LLM response received: {len(response_text)} chars")

            # Parse JSON response
            import re
            json_match = re.search(r'\{.*\}', response_text, re.DOTALL)
            if json_match:
                result = json.loads(json_match.group(0))

                # Validate that all tools exist in catalog
                valid = self._validate_tool_ids(result, available_tools)
                if not valid['success']:
                    log.warning(f"Tool validation failed: {valid['message']}")
                    result['validation_errors'] = valid['errors']

                return result
            else:
                log.error("Failed to parse LLM response")
                return {"error": "JSON parsing failed", "response": response_text}

        except Exception as e:
            log.error(f"Workflow structure generation failed: {e}", exc_info=True)
            return {"error": str(e)}

    def _build_tool_catalog(self, tools: List[Dict[str, Any]]) -> str:
        """
        Build a rich tool catalog for LLM workflow design.

        Includes:
        - wrapper_path: indicates a .nf file exists on disk (use include{})
        - best_practice_functions: ordered step sequence with I/O typing
        - scientific_context: primary omics/applicability
        - usage_guide: R/Python code snippets
        - parameters: Galaxy tool parameters (when available)
        """
        catalog = ""
        for i, tool in enumerate(tools, 1):
            tool_id = tool['tool_id']
            category = tool.get('category', 'Unknown')
            keywords = tool.get('keywords', '')
            wrapper_path = tool.get('wrapper_path', '')
            language = tool.get('language', '')

            # Tag: NF-WRAPPER means an .nf file exists and can be included directly
            if wrapper_path:
                source_tag = "[NF-WRAPPER]"
            elif language in ('nextflow', 'r', 'python'):
                source_tag = f"[{language.upper()}]"
            else:
                availability = tool.get('availability_status', 'installable')
                source_tag = "[LOCAL]" if availability in ('ready', 'docker', 'api') else "[INSTALL]"

            catalog += f"{i}. {source_tag} {tool['name']}\n"
            catalog += f"   Tool ID : {tool_id}\n"
            catalog += f"   Category: {category}\n"

            desc = tool.get('description', '')
            if desc:
                catalog += f"   Desc    : {desc[:200]}\n"

            if keywords:
                catalog += f"   Keywords: {keywords}\n"

            # .nf wrapper — show the include directive the LLM should emit
            if wrapper_path:
                catalog += f"   NF path : {wrapper_path}\n"
                catalog += f"   Usage   : include {{ PROCESS }} from '<path>/{wrapper_path}'\n"

            # best_practice_functions — step-by-step function sequence with I/O
            bpf = tool.get('best_practice_functions', {})
            if bpf and isinstance(bpf, dict):
                steps_shown = 0
                seen_steps: set = set()
                catalog += "   Steps   :\n"
                for fn_name, fn_meta in bpf.items():
                    if steps_shown >= 5:
                        catalog += f"             ... and {len(bpf) - steps_shown} more functions\n"
                        break
                    step_label = fn_meta.get('step', '')
                    if step_label in seen_steps:
                        continue
                    seen_steps.add(step_label)
                    inp = fn_meta.get('inputs', [])
                    out = fn_meta.get('outputs', [])
                    io = f"{' → '.join(inp)} → {' → '.join(out)}" if (inp or out) else ""
                    catalog += f"             [{step_label}] {fn_name}({io})\n"
                    steps_shown += 1

            # scientific_context — primary omics applicability
            sci_ctx = tool.get('scientific_context', {})
            if isinstance(sci_ctx, dict):
                omics = sci_ctx.get('omics_applicability', {}).get('primary_omics', [])
                if omics:
                    catalog += f"   Omics   : {', '.join(omics)}\n"

            # Galaxy parameters (when available; empty for most Bioconductor entries)
            parameters = tool.get('parameters', [])
            if parameters:
                catalog += "   Params  :\n"
                for param in parameters[:4]:
                    p_name = param.get('name', 'unknown')
                    p_type = param.get('type', '')
                    p_help = (param.get('help', '') or '')[:80]
                    optional = "opt" if param.get('optional', False) else "req"
                    catalog += f"             - {p_name} ({p_type},{optional})"
                    if p_help:
                        catalog += f": {p_help}"
                    catalog += "\n"
                if len(parameters) > 4:
                    catalog += f"             ... +{len(parameters) - 4} more\n"

            # Usage guide (code snippet)
            usage_guide = tool.get('usage_guide', '')
            if usage_guide:
                snippet = usage_guide[:150]
                catalog += f"   Guide   : {snippet}{'...' if len(usage_guide) > 150 else ''}\n"

            catalog += "\n"
        return catalog

    def _validate_tool_ids(
        self,
        workflow_structure: Dict[str, Any],
        available_tools: List[Dict[str, Any]]
    ) -> Dict[str, Any]:
        """Validate that all tool IDs in workflow exist in available tools."""
        valid_tool_ids = {t['tool_id'] for t in available_tools}
        errors = []

        for step in workflow_structure.get('steps', []):
            tool_id = step.get('tool_id', '')
            if tool_id not in valid_tool_ids:
                errors.append({
                    'step': step.get('step'),
                    'invalid_tool_id': tool_id,
                    'message': f"Tool ID not found in available tools: {tool_id}"
                })

        if errors:
            return {
                'success': False,
                'errors': errors,
                'message': f"Found {len(errors)} invalid tool IDs in workflow"
            }
        else:
            return {'success': True, 'errors': []}

    def _build_galaxy_workflow_json(
        self,
        workflow_structure: Dict[str, Any],
        dataset_assignments: Dict[str, Any],
        user_intent: Optional[str] = None
    ) -> Tuple[Dict[str, Any], List[Dict[str, Any]]]:
        """
        Build Galaxy .ga workflow JSON with embedded datasets and parameter templates.

        Galaxy workflow format:
        {
          "a_galaxy_workflow": "true",
          "format-version": "0.1",
          "name": "Workflow Name",
          "steps": {
            "0": {
              "tool_id": "...",
              "inputs": {...},
              "annotation": "Help text from tool documentation",
              "tool_state": "JSON with parameter defaults"
              ...
            }
          }
        }

        Returns:
            Tuple of (workflow_json, generated_parameters_list)
        """

        # Create dataset assignments lookup
        dataset_lookup = {}
        for step_data in dataset_assignments.get('workflow_steps', []):
            step_num = step_data.get('step')
            if step_data.get('dataset_needed') and step_data.get('selected_datasets'):
                dataset_lookup[step_num] = step_data['selected_datasets']

        # Track generated parameters for all steps
        generated_parameters_list = []

        # Build Galaxy steps with parameters and help text
        galaxy_steps = {}
        for step in workflow_structure.get('steps', []):
            step_num = step['step']
            # Original tool ID from AI database (uses slashes for Biomni tools)
            db_tool_id = step['tool_id']
            # Normalize tool ID for Galaxy (uses underscores for Biomni tools)
            tool_id = self._normalize_tool_id(db_tool_id)
            tool_name = step['tool_name']

            # Get tool parameters and help from database (use original DB format)
            tool_params, tool_help = self._get_tool_parameters_and_help(db_tool_id)

            # Determine if this is a data source tool that needs LLM parameter generation
            is_data_source = self._is_data_source_tool(tool_id)

            # Generate parameters using LLM for data source tools
            tool_state_json = None
            param_metadata = None

            if is_data_source and user_intent and tool_params:
                log.info(f"[WorkflowGen] Generating parameters for data source tool: {tool_id}")
                try:
                    parameters, confidence, reasoning = self.parameter_generator.generate_parameters(
                        tool_id=tool_id,
                        tool_name=tool_name,
                        user_intent=user_intent,
                        tool_parameters=tool_params,
                        context={
                            'step_number': step_num,
                            'previous_steps': workflow_structure.get('steps', [])[:step_num-1]
                        }
                    )

                    # Build tool state from generated parameters
                    tool_state_json = json.dumps(parameters)

                    # Track generated parameters
                    param_metadata = {
                        "step_id": step_num,
                        "tool_id": tool_id,
                        "tool_name": tool_name,
                        "parameters": parameters,
                        "confidence": confidence,
                        "reasoning": reasoning
                    }
                    generated_parameters_list.append(param_metadata)

                    log.info(f"[WorkflowGen] Generated parameters with confidence {confidence:.2f}")

                except Exception as e:
                    log.error(f"[WorkflowGen] Failed to generate parameters for {tool_id}: {e}")
                    # Fallback to defaults
                    tool_state_json = self._build_tool_state(tool_params)
            else:
                # Regular tool or no parameters - use defaults
                tool_state_json = self._build_tool_state(tool_params)

            # Base step structure
            galaxy_step = {
                "id": step_num - 1,  # Galaxy uses 0-based indexing
                "tool_id": tool_id,
                "tool_version": None,  # Will be resolved by Galaxy
                "type": "tool",
                "name": tool_name,
                "tool_state": tool_state_json,
                "annotation": self._build_step_annotation(step, tool_help),
                "inputs": [],
                "position": {
                    "left": 200 + (step_num - 1) * 300,  # Horizontal spacing
                    "top": 200
                }
            }

            # Add dataset inputs if assigned
            if step_num in dataset_lookup:
                datasets = dataset_lookup[step_num]
                for i, dataset in enumerate(datasets):
                    galaxy_step['inputs'].append({
                        f"reference_db_{i}": {
                            "src": "ldda",  # Library dataset
                            "id": dataset['id'],
                            "path": dataset['path']
                        }
                    })

            galaxy_steps[str(step_num - 1)] = galaxy_step

        # Build complete workflow
        galaxy_workflow = {
            "a_galaxy_workflow": "true",
            "format-version": "0.1",
            "name": workflow_structure.get('workflow_name', 'AI-Generated Workflow'),
            "annotation": workflow_structure.get('reasoning', ''),
            "tags": ["ai-generated", "comprehensive-index"],
            "steps": galaxy_steps
        }

        return galaxy_workflow, generated_parameters_list

    def _get_tool_parameters_and_help(self, tool_id: str) -> tuple:
        """Get tool parameters and help text from comprehensive database."""
        import sqlite3

        try:
            db_path = Path(__file__).parent.parent.parent.parent / "galaxy_ai_tools.db"
            with sqlite3.connect(str(db_path)) as conn:
                conn.row_factory = sqlite3.Row
                cursor = conn.cursor()

                cursor.execute("""
                    SELECT parameters, help_text
                    FROM tools
                    WHERE id = ?
                """, (tool_id,))

                row = cursor.fetchone()

                if row:
                    params = json.loads(row['parameters']) if row['parameters'] else []
                    help_text = json.loads(row['help_text']) if row['help_text'] else {}
                    return params, help_text
                else:
                    return [], {}

        except Exception as e:
            log.warning(f"Could not get parameters for {tool_id}: {e}")
            return [], {}

    def _build_tool_state(self, parameters: List[Dict[str, Any]]) -> str:
        """Build tool_state JSON with parameter defaults."""
        if not parameters:
            return "{}"

        tool_state = {}
        for param in parameters:
            param_name = param.get('name', '')
            param_type = param.get('type', 'text')

            # Set default values based on parameter type
            if param_type == 'data':
                tool_state[param_name] = None
            elif param_type == 'boolean':
                tool_state[param_name] = False
            elif param_type in ['integer', 'float']:
                tool_state[param_name] = param.get('default', 0)
            else:
                tool_state[param_name] = param.get('default', '')

        return json.dumps(tool_state)

    def _build_step_annotation(self, step: Dict[str, Any], help_text: Dict[str, Any]) -> str:
        """Build step annotation from tool help text and citations."""
        annotations = []

        # Add step description from workflow structure
        if step.get('description'):
            annotations.append(step['description'])

        # Add "What it does" from help text
        if help_text.get('what_it_does'):
            annotations.append(f"What it does: {help_text['what_it_does']}")

        # Add input/output descriptions
        if help_text.get('input_description'):
            annotations.append(f"Input: {help_text['input_description']}")

        # Inject citation from tool knowledge provider
        tool_id = step.get('tool_id', '')
        knowledge_provider = get_tool_knowledge_provider()
        if knowledge_provider and tool_id:
            try:
                knowledge = knowledge_provider.get_tool_knowledge(tool_id)
                if knowledge and knowledge.citation:
                    citation = knowledge.citation
                    citation_text = f"Citation: {citation.format_short()}"
                    if citation.doi:
                        citation_text += f" (doi:{citation.doi})"
                    annotations.append(citation_text)

                    # Add key limitations as warnings
                    if knowledge.limitations:
                        limit_text = "; ".join(knowledge.limitations[:2])
                        annotations.append(f"Note: {limit_text}")
            except Exception as e:
                log.debug(f"Failed to get knowledge for {tool_id}: {e}")

        return " | ".join(annotations) if annotations else step.get('tool_name', '')

    def _normalize_tool_id(self, tool_id: str) -> str:
        """
        Normalize tool ID to match Galaxy's loaded tool format.

        The AI database stores tool IDs with slashes (biomni/database/query_uniprot)
        but Galaxy loads tools with underscores (biomni_database_query_uniprot).

        Args:
            tool_id: Tool ID from AI database (may use slashes or underscores)

        Returns:
            Normalized tool ID using underscores
        """
        if tool_id.startswith('biomni/'):
            # Convert biomni/X/Y to biomni_X_Y
            return tool_id.replace('/', '_')
        return tool_id

    def _is_data_source_tool(self, tool_id: str) -> bool:
        """
        Determine if a tool is a data source tool that needs parameter generation.

        Data source tools include:
        - BioMate data source API tools (biomate_ds_api_*) - 31 Galaxy tools
        - BioMni data lake tools (biomate_dm_*)
        - BioMate legacy API tools (biomate_datasource_api_*)
        - Galaxy native data source tools (biomart, ucsc_table_direct, etc.)

        Args:
            tool_id: Tool identifier

        Returns:
            True if tool is a data source tool
        """
        # BioMate data source API tools (primary - 31 tools for database queries)
        # These are the Galaxy tools that replaced Biomni query functions
        if tool_id.startswith('biomate_ds_api_'):
            return True

        # BioMni data management tools (local data lakes)
        if tool_id.startswith('biomate_dm_'):
            return True

        # BioMate legacy API data source tools
        if tool_id.startswith('biomate_datasource_api_'):
            return True

        # Galaxy native data source tools
        galaxy_data_sources = [
            'biomart', 'ucsc_table_direct', 'ebi_sra_main',
            'flymine', 'wormbase', 'yeastmine',
            'ncbi_datasets', 'uniprot_rest',
            'query_tabular'  # Generic query tool
        ]

        if tool_id in galaxy_data_sources:
            return True

        # Check if tool name contains data source indicators
        tool_id_lower = tool_id.lower()
        data_source_keywords = ['query', 'fetch', 'download', 'retrieve', 'datasource', 'data_source']

        for keyword in data_source_keywords:
            if keyword in tool_id_lower:
                return True

        return False

    def validate_workflow_compatibility(
        self,
        workflow_structure: Dict[str, Any]
    ) -> Tuple[bool, List[str]]:
        """
        Validate tool chain compatibility in a workflow.

        Checks that output formats from each step are compatible with
        input formats expected by subsequent steps.

        Args:
            workflow_structure: Workflow structure with 'steps' list

        Returns:
            Tuple of (is_valid, list_of_warnings)
        """
        import sqlite3

        warnings = []
        steps = workflow_structure.get('steps', [])

        if len(steps) < 2:
            return True, []  # No connections to validate

        # Cache for tool I/O types
        io_cache: Dict[str, Dict[str, List[str]]] = {}

        # Get database path
        db_path = Path(__file__).parent.parent.parent.parent / "galaxy_ai_tools.db"
        if not db_path.exists():
            log.warning(f"Tool database not found: {db_path}")
            return True, ["Tool database not available for validation"]

        def get_tool_io(tool_id: str) -> Dict[str, List[str]]:
            """Get tool input/output types from database."""
            if tool_id in io_cache:
                return io_cache[tool_id]

            try:
                conn = sqlite3.connect(str(db_path))
                cursor = conn.cursor()

                # Normalize tool_id for lookup
                lookup_id = tool_id.replace('_', '/') if tool_id.startswith('biomni_') else tool_id

                cursor.execute(
                    "SELECT inputs, outputs FROM tools WHERE tool_id = ? OR id = ?",
                    (lookup_id, tool_id)
                )
                row = cursor.fetchone()
                conn.close()

                if row:
                    inputs = json.loads(row[0]) if row[0] else []
                    outputs = json.loads(row[1]) if row[1] else []
                    io_cache[tool_id] = {'inputs': inputs, 'outputs': outputs}
                else:
                    io_cache[tool_id] = {'inputs': [], 'outputs': []}

            except Exception as e:
                log.debug(f"Error getting I/O for {tool_id}: {e}")
                io_cache[tool_id] = {'inputs': [], 'outputs': []}

            return io_cache[tool_id]

        def formats_compatible(outputs: List[str], inputs: List[str]) -> bool:
            """Check if output formats are compatible with input formats."""
            if not outputs or not inputs:
                return True  # Unknown = assume compatible

            # Normalize format names
            def normalize(fmt: str) -> str:
                fmt = fmt.lower().strip()
                # Handle compressed variants
                fmt = fmt.replace('.gz', '').replace('.bz2', '')
                # Handle format aliases
                aliases = {
                    'fa': 'fasta', 'fq': 'fastq',
                    'sam': 'bam', 'vcf': 'bcf',
                    'bed': 'interval', 'gff': 'gff3'
                }
                return aliases.get(fmt, fmt)

            out_normalized = {normalize(f) for f in outputs}
            in_normalized = {normalize(f) for f in inputs}

            # Check for any overlap
            return bool(out_normalized & in_normalized) or 'data' in in_normalized

        # Check each consecutive step pair
        for i in range(len(steps) - 1):
            current_step = steps[i]
            next_step = steps[i + 1]

            current_tool = current_step.get('tool_id', '')
            next_tool = next_step.get('tool_id', '')

            current_io = get_tool_io(current_tool)
            next_io = get_tool_io(next_tool)

            if current_io['outputs'] and next_io['inputs']:
                if not formats_compatible(current_io['outputs'], next_io['inputs']):
                    warnings.append(
                        f"Step {i+1} ({current_step.get('tool_name', current_tool)}) outputs "
                        f"{current_io['outputs']} but Step {i+2} ({next_step.get('tool_name', next_tool)}) "
                        f"expects {next_io['inputs']}"
                    )

        is_valid = len(warnings) == 0
        return is_valid, warnings

    def save_workflow(self, workflow_data: Dict[str, Any], output_path: str):
        """Save workflow to .ga JSON file."""
        with open(output_path, 'w') as f:
            json.dump(workflow_data['workflow_ga'], f, indent=2)
        log.info(f"Workflow saved to {output_path}")


def main():
    """Test the workflow generator."""
    import argparse

    parser = argparse.ArgumentParser(description='Galaxy workflow generator with tool validation')
    parser.add_argument('--intent', required=True, help='User research intent')
    parser.add_argument('--output', default='generated_workflow.ga', help='Output workflow file')
    parser.add_argument('--max-tools', type=int, default=30, help='Max tools to retrieve')

    args = parser.parse_args()

    # Initialize generator
    generator = GalaxyWorkflowGenerator()

    # Generate workflow
    result = generator.generate_workflow(
        user_intent=args.intent,
        max_tools_search=args.max_tools
    )

    if result['success']:
        # Save workflow
        generator.save_workflow(result, args.output)

        print(f"\n✓ Workflow generated successfully!")
        print(f"  Workflow file: {args.output}")
        print(f"  Tools used: {len(result['tool_selections'])}")
        print(f"  Steps: {len(result['workflow_structure']['steps'])}")

        # Print summary
        print(f"\n{result['workflow_structure']['workflow_name']}")
        print("=" * 60)
        print(f"Reasoning: {result['workflow_structure']['reasoning']}\n")

        for step in result['workflow_structure']['steps']:
            print(f"Step {step['step']}: {step['tool_name']}")
            print(f"  Tool ID: {step['tool_id']}")
            print(f"  Purpose: {step['purpose']}")

            # Show datasets if assigned
            for step_data in result['dataset_assignments']['workflow_steps']:
                if step_data['step'] == step['step'] and step_data.get('selected_datasets'):
                    print(f"  Datasets:")
                    for ds in step_data['selected_datasets']:
                        print(f"    - {ds['name']}")
            print()

    else:
        print(f"\n✗ Workflow generation failed!")
        print(f"  Error: {result.get('error')}")
        print(f"  Message: {result.get('message')}")


if __name__ == '__main__':
    main()
