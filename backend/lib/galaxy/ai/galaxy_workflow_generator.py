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
            from galaxy.ai.config import DEFAULT_AI_CONFIG
            config = DEFAULT_AI_CONFIG

        self.config = config
        from galaxy.ai.llm_client import LLMClient
        self.llm_client = LLMClient(config)

        # Tool search - lazy loaded to avoid heavy imports
        self._tool_search = tool_search_index
        self._tool_search_loaded = False

        # Dataset selector for dataset integration
        if dataset_selector is None:
            from galaxy.ai.workflow_dataset_selector import WorkflowDatasetSelector
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
                    from galaxy.ai.unified_tool_search import create_unified_search
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
        report_progress("workflow_design", 0.3, "Designing intelligent workflow structure...", {"phase": "llm_generation"})
        log.info("Generating workflow structure with LLM...")
        workflow_structure = self._generate_workflow_structure(
            user_intent,
            available_tools
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
            "generated_parameters": generated_parameters,  # LLM-generated parameters with confidence scores
            "citations": citations,  # Tool citations with DOI/PMID
            "methods_section": methods_section,  # Auto-generated methods text
            "generation_progress": progress_steps  # Progress tracking for UI
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

            # Format tools for LLM context
            formatted_tools = []
            for tool in results:
                formatted_tools.append({
                    'tool_id': tool['tool_id'],
                    'name': tool['name'],
                    'description': tool.get('description', ''),
                    'version': tool.get('version', ''),
                    'category': tool.get('category', ''),
                    'keywords': tool.get('keywords', ''),
                    'repo_owner': tool.get('repo_owner', ''),
                    'repo_name': tool.get('repo_name', ''),
                    'relevance_score': tool.get('rrf_score', 0)  # Include relevance from fusion
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
        available_tools: List[Dict[str, Any]]
    ) -> Dict[str, Any]:
        """
        Generate intelligent workflow structure using LLM.

        CRITICAL: LLM can ONLY use tools from available_tools list.

        Workflow Design Principles:
        1. Data quality check first - validate input data
        2. Core analysis - satisfy user's information needs
        3. Post-processing - format, visualize, summarize results
        4. Output preparation - provide downloadable outputs
        """

        # Build tool catalog for LLM
        tool_catalog = self._build_tool_catalog(available_tools)

        system_prompt = f"""You are an expert bioinformatics workflow architect for the Galaxy platform.

Your task is to design COMPLETE, INTELLIGENT workflows that fully satisfy user needs.

## AVAILABLE TOOLS (Use ONLY these exact tool_ids):

{tool_catalog}

## WORKFLOW DESIGN PRINCIPLES:

A well-designed workflow should follow these phases:

### PHASE 1: DATA VALIDATION (if applicable)
- Check data quality and format
- Validate input parameters
- Report potential data issues

### PHASE 2: CORE ANALYSIS
- Perform the main analysis task requested by user
- Use appropriate tools in logical sequence
- Ensure outputs satisfy user's information needs

### PHASE 3: POST-PROCESSING (if applicable)
- Format results for readability
- Generate summaries and statistics
- Create visualizations (plots, charts)

### PHASE 4: OUTPUT PREPARATION
- Prepare downloadable results
- Generate reports if appropriate
- Provide results in user-requested format

## IMPORTANT GUIDELINES:

1. Use ONLY tools from the AVAILABLE TOOLS list (exact tool_id)
2. Consider what information the user ACTUALLY needs
3. Include visualization if it helps understanding
4. Provide summary/statistics where meaningful
5. Design for user convenience - ready-to-download outputs
6. Keep workflows efficient - don't add unnecessary steps

## OUTPUT FORMAT (JSON):

{{
  "workflow_name": "Descriptive title reflecting the analysis",
  "workflow_description": "Brief description of what this workflow accomplishes",
  "user_need_addressed": "How this workflow satisfies the user's request",
  "phases": [
    {{
      "phase": "data_validation|core_analysis|post_processing|output_preparation",
      "phase_description": "What this phase accomplishes"
    }}
  ],
  "steps": [
    {{
      "step": 1,
      "phase": "data_validation|core_analysis|post_processing|output_preparation",
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

        user_prompt = f"""## USER REQUEST:
{user_intent}

## TASK:
Design a complete, intelligent workflow that:
1. VALIDATES data quality (if applicable)
2. PERFORMS the core analysis to answer the user's question
3. FORMATS and VISUALIZES results (if helpful)
4. PREPARES downloadable outputs

Consider:
- What information does the user actually need?
- What format would be most useful for them?
- Should results include visualizations?
- What summary statistics would be helpful?

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
        """Build a clean tool catalog using keywords and category (avoids content filters)."""
        catalog = ""
        for i, tool in enumerate(tools, 1):
            # Use keywords instead of description to avoid content triggers
            keywords = tool.get('keywords', '')
            category = tool.get('category', 'Unknown')

            catalog += f"{i}. {tool['name']}\n"
            catalog += f"   Tool ID: {tool['tool_id']}\n"
            catalog += f"   Category: {category}\n"

            # Keywords are clean and useful for understanding tool purpose
            if keywords:
                catalog += f"   Keywords: {keywords}\n"

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
        - BioMni data lake tools (biomate_dm_*)
        - BioMate API tools (biomate_datasource_api_*)
        - Galaxy native data source tools (biomart, ucsc_table_direct, etc.)

        Args:
            tool_id: Tool identifier

        Returns:
            True if tool is a data source tool
        """
        # BioMni data management tools (local data lakes)
        if tool_id.startswith('biomate_dm_'):
            return True

        # BioMate API data source tools
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
