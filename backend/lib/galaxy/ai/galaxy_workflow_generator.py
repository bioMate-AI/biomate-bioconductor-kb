"""
Galaxy Workflow Generator with Tool Validation and Dataset Integration

Generates Galaxy .ga workflow JSON using:
1. ToolSearchIndex - retrieve available tools (VALIDATION)
2. Claude LLM - generate workflow from retrieved tools only
3. WorkflowDatasetSelector - add datasets to workflow steps

This ensures NO non-existent tools are used in generated workflows.
"""

import os
import json
import logging
from typing import Dict, List, Any, Optional, Tuple
from pathlib import Path

log = logging.getLogger(__name__)


class GalaxyWorkflowGenerator:
    """
    LLM-based Galaxy workflow generator with tool validation.

    Architecture:
    1. Tool Retrieval: Search ToolSearchIndex for available tools
    2. Workflow Generation: LLM creates workflow using ONLY retrieved tools
    3. Dataset Integration: WorkflowDatasetSelector adds datasets
    4. .ga JSON Output: Generate Galaxy workflow format
    """

    def __init__(
        self,
        tool_search_index=None,
        dataset_selector=None,
        api_key: str = None
    ):
        """Initialize workflow generator with tool index and dataset selector."""
        self.api_key = api_key or os.environ.get('ANTHROPIC_API_KEY')

        # Validate API key is provided
        if not self.api_key:
            raise ValueError(
                "ANTHROPIC_API_KEY is required. Provide via:\n"
                "  1. api_key parameter in constructor\n"
                "  2. ANTHROPIC_API_KEY environment variable"
            )

        # Tool search index for validation
        if tool_search_index is None:
            from galaxy.tools.search_index import ToolSearchIndex
            self.tool_index = ToolSearchIndex()
        else:
            self.tool_index = tool_search_index

        # Dataset selector for dataset integration
        if dataset_selector is None:
            from galaxy.ai.workflow_dataset_selector import WorkflowDatasetSelector
            self.dataset_selector = WorkflowDatasetSelector(api_key=self.api_key)
        else:
            self.dataset_selector = dataset_selector

        # LLM Parameter Generator for intelligent parameter inference
        from .llm_parameter_generator import LLMParameterGenerator
        from .config import DEFAULT_AI_CONFIG
        self.parameter_generator = LLMParameterGenerator(config=DEFAULT_AI_CONFIG)

        import anthropic
        self.client = anthropic.Anthropic(api_key=self.api_key)
        self.model = "claude-sonnet-4-5-20250929"

    def generate_workflow(
        self,
        user_intent: str,
        max_tools_search: int = 30
    ) -> Dict[str, Any]:
        """
        Generate complete Galaxy workflow with datasets.

        Args:
            user_intent: User's research goal
                Example: "Identify metabolites from human serum LC-MS data"
            max_tools_search: Max tools to retrieve from index for LLM context

        Returns:
            Dict with:
            - workflow_ga: Galaxy .ga JSON
            - tool_selections: Tools selected from index
            - dataset_assignments: Datasets assigned to steps
            - reasoning: LLM reasoning for workflow design
        """

        # STEP 1: Retrieve available tools from index
        log.info(f"Retrieving tools for: {user_intent}")
        available_tools = self._retrieve_tools_from_index(user_intent, max_tools_search)

        if not available_tools:
            return {
                "success": False,
                "error": "No tools found in index matching the query",
                "message": f"No tools found for query: {user_intent}"
            }

        log.info(f"Retrieved {len(available_tools)} tools from index")

        # STEP 2: Generate workflow structure using LLM (ONLY from retrieved tools)
        log.info("Generating workflow structure with LLM...")
        workflow_structure = self._generate_workflow_structure(
            user_intent,
            available_tools
        )

        if not workflow_structure or 'error' in workflow_structure:
            return {
                "success": False,
                "error": "Workflow generation failed",
                "message": workflow_structure.get('error', 'Unknown error')
            }

        # STEP 3: Select datasets for workflow steps
        log.info("Selecting datasets for workflow steps...")
        dataset_assignments = self.dataset_selector.select_datasets_for_workflow(
            user_intent=user_intent,
            workflow_structure=workflow_structure.get('steps', [])
        )

        # STEP 4: Build Galaxy .ga JSON with LLM parameter generation
        log.info("Building Galaxy .ga workflow JSON...")
        galaxy_workflow, generated_parameters = self._build_galaxy_workflow_json(
            workflow_structure,
            dataset_assignments,
            user_intent=user_intent
        )

        return {
            "success": True,
            "workflow_ga": galaxy_workflow,
            "workflow_structure": workflow_structure,
            "dataset_assignments": dataset_assignments,
            "tool_selections": available_tools,
            "user_intent": user_intent,
            "generated_parameters": generated_parameters  # NEW: LLM-generated parameters with confidence scores
        }

    def _retrieve_tools_from_index(
        self,
        user_intent: str,
        limit: int = 30
    ) -> List[Dict[str, Any]]:
        """
        Retrieve available tools from ToolSearchIndex.

        This ensures we only use tools that exist in Galaxy.
        """
        try:
            # Transform user intent to FTS5-compatible query using LLM
            raw_query = self._transform_intent_to_fts_query(user_intent)
            # Sanitize to prevent FTS5 syntax errors
            fts_query = self._sanitize_fts_query(raw_query)
            log.info(f"Transformed query: {raw_query} → Sanitized: {fts_query}")

            # Search tool index with sanitized query
            results = self.tool_index.search(fts_query, limit=limit)

            # Format tools for LLM context (include keywords!)
            formatted_tools = []
            for tool in results:
                formatted_tools.append({
                    'tool_id': tool['tool_id'],
                    'name': tool['name'],
                    'description': tool.get('description', ''),
                    'version': tool.get('version', ''),
                    'category': tool.get('category', ''),
                    'keywords': tool.get('keywords', ''),  # Include keywords
                    'repo_owner': tool.get('repo_owner', ''),
                    'repo_name': tool.get('repo_name', '')
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
            response = self.client.messages.create(
                model=self.model,
                max_tokens=100,
                messages=[{"role": "user", "content": prompt}]
            )

            fts_query = response.content[0].text.strip()
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
        Generate workflow structure using LLM.

        CRITICAL: LLM can ONLY use tools from available_tools list.
        """

        # Build tool catalog for LLM
        tool_catalog = self._build_tool_catalog(available_tools)

        system_prompt = f"""You are a scientific workflow design expert for Galaxy bioinformatics platform.

Available tools for this workflow:

{tool_catalog}

Guidelines:
1. Use ONLY tools from the list above (exact tool_id)
2. Select tools based on Category and Keywords
3. Design logical workflow steps
4. Each step: step number, tool_id, tool_name, purpose

Return JSON:
{{
  "workflow_name": "title",
  "steps": [
    {{
      "step": 1,
      "tool_id": "exact tool_id from list",
      "tool_name": "tool name",
      "purpose": "what this step does"
    }}
  ],
  "reasoning": "workflow rationale",
  "missing_tools": []
}}
"""

        user_prompt = f"""Scientific Research Goal: {user_intent}

Task: Design workflow using ONLY the tools from the provided list.

Steps:
1. Select tools from catalog (exact tool_id)
2. Order them logically
3. Explain each step purpose
4. Note missing tools

Return JSON only.
"""

        try:
            response = self.client.messages.create(
                model=self.model,
                max_tokens=4096,
                system=system_prompt,
                messages=[{"role": "user", "content": user_prompt}]
            )

            # Debug: log full response
            log.debug(f"Full LLM response: {response}")

            # Check if response has content
            if not response.content or len(response.content) == 0:
                log.error(f"LLM returned empty response. Full response: {response}")
                return {"error": "Empty LLM response"}

            response_text = response.content[0].text
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
            tool_id = step['tool_id']
            tool_name = step['tool_name']

            # Get tool parameters and help from database
            tool_params, tool_help = self._get_tool_parameters_and_help(tool_id)

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
            db_path = Path(__file__).parent.parent.parent / "galaxy_ai_tools.db"
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
        """Build step annotation from tool help text."""
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

        return " | ".join(annotations) if annotations else step.get('tool_name', '')

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
