"""
LLM Parameter Generator for Galaxy AI Assistant

Generates parameter values for dataset query tools using LLM inference from user intent.
"""

import json
import logging
from typing import Dict, Any, Optional, Tuple, List
from .llm_client import LLMClient
from .config import AIConfig

log = logging.getLogger(__name__)


class LLMParameterGenerator:
    """
    Generate tool parameters using LLM inference from user intent.

    This module uses LLM to intelligently infer parameter values for dataset
    query tools (BioMni datasets, external APIs) based on user's natural language
    request.

    Example:
        User: "Get mouse genes from Ensembl related to immune response"
        Generated: {
            "organism": "mouse",
            "filter_column": "go_term",
            "filter_value": "immune response"
        }
    """

    def __init__(self, config: Optional[AIConfig] = None):
        """Initialize parameter generator with LLM client."""
        from .config import DEFAULT_AI_CONFIG
        self.config = config or DEFAULT_AI_CONFIG
        self.llm_client = LLMClient(self.config)

    def generate_parameters(
        self,
        tool_id: str,
        tool_name: str,
        user_intent: str,
        tool_parameters: List[Dict[str, Any]],
        context: Optional[Dict[str, Any]] = None
    ) -> Tuple[Dict[str, Any], float, str]:
        """
        Generate parameter values for a tool using LLM inference.

        Args:
            tool_id: Tool identifier
            tool_name: Human-readable tool name
            user_intent: User's natural language request
            tool_parameters: List of tool parameter specifications
            context: Additional context (previous steps, datasets, etc.)

        Returns:
            Tuple of (parameters_dict, confidence_score, reasoning)

        Example:
            >>> generator = LLMParameterGenerator()
            >>> params, conf, reasoning = generator.generate_parameters(
            ...     tool_id="biomate_dm_ensembl_genes",
            ...     tool_name="Ensembl Gene Query",
            ...     user_intent="Get mouse genes related to kinase",
            ...     tool_parameters=[...]
            ... )
            >>> params
            {'organism': 'mouse', 'filter_column': 'description',
             'filter_value': 'kinase'}
            >>> conf
            0.92
        """
        try:
            # Format parameter schema for LLM
            param_schema = self._format_parameter_schema(tool_parameters)

            # Build LLM prompt
            prompt = self._build_parameter_prompt(
                tool_id=tool_id,
                tool_name=tool_name,
                user_intent=user_intent,
                param_schema=param_schema,
                context=context
            )

            # Generate parameters using LLM
            log.info(f"[LLMParamGen] Generating parameters for {tool_id}")
            log.debug(f"[LLMParamGen] Prompt: {prompt[:200]}...")

            response = self.llm_client.generate(
                prompt=prompt,
                temperature=0.0,  # Low temperature for consistent parameter generation
                max_tokens=1000
            )

            # Parse LLM response
            result = self._parse_llm_response(response)

            # Validate parameters against schema
            validated_params = self._validate_parameters(
                parameters=result['parameters'],
                tool_parameters=tool_parameters
            )

            confidence = result.get('confidence', 0.5)
            reasoning = result.get('reasoning', 'Parameters inferred from user query')

            log.info(f"[LLMParamGen] Generated parameters with confidence {confidence:.2f}")
            log.debug(f"[LLMParamGen] Parameters: {validated_params}")

            return (validated_params, confidence, reasoning)

        except Exception as e:
            log.error(f"[LLMParamGen] Error generating parameters: {e}", exc_info=True)
            # Return defaults on failure
            return (self._get_default_parameters(tool_parameters), 0.0,
                    f"Failed to generate parameters: {str(e)}")

    def _format_parameter_schema(self, tool_parameters: List[Dict[str, Any]]) -> str:
        """
        Format tool parameters into human-readable schema for LLM.

        Args:
            tool_parameters: List of parameter specifications

        Returns:
            Formatted schema string
        """
        if not tool_parameters:
            return "No parameters required"

        schema_lines = []
        for param in tool_parameters:
            param_name = param.get('name', 'unknown')
            param_type = param.get('type', 'text')
            param_label = param.get('label', param_name)
            param_help = param.get('help', '')
            param_default = param.get('default', '')
            param_options = param.get('options', [])

            line = f"- {param_name} ({param_type})"
            if param_label:
                line += f": {param_label}"
            if param_help:
                line += f"\n  Description: {param_help}"
            if param_default:
                line += f"\n  Default: {param_default}"
            if param_options:
                line += f"\n  Options: {', '.join(str(opt) for opt in param_options)}"

            schema_lines.append(line)

        return "\n".join(schema_lines)

    def _build_parameter_prompt(
        self,
        tool_id: str,
        tool_name: str,
        user_intent: str,
        param_schema: str,
        context: Optional[Dict[str, Any]] = None
    ) -> str:
        """
        Build LLM prompt for parameter generation.

        Args:
            tool_id: Tool identifier
            tool_name: Tool name
            user_intent: User's request
            param_schema: Formatted parameter schema
            context: Additional context

        Returns:
            Complete prompt for LLM
        """
        # Extract context information
        context_info = ""
        if context:
            if context.get('previous_steps'):
                context_info += f"\nPrevious workflow steps: {context['previous_steps']}"
            if context.get('available_datasets'):
                context_info += f"\nAvailable datasets: {context['available_datasets']}"

        prompt = f"""You are a bioinformatics workflow parameter generator. Your task is to infer parameter values for a tool based on the user's natural language request.

**Tool Information:**
- Tool ID: {tool_id}
- Tool Name: {tool_name}

**User Request:**
"{user_intent}"
{context_info}

**Tool Parameters:**
{param_schema}

**Task:**
1. Analyze the user's request carefully
2. Extract relevant information for each parameter
3. Infer appropriate parameter values
4. Assign confidence scores (0.0-1.0) based on how certain you are
5. Provide reasoning for your choices

**Rules:**
- Use default values if the user's request doesn't specify that parameter
- For organism parameters, infer from mentions like "mouse", "human", "yeast"
- For filter/query parameters, extract keywords from the user's request
- For numeric parameters, use sensible defaults based on the parameter description
- Be conservative with confidence scores (0.7-0.8 for inferred, 0.9-1.0 for explicit)
- Set confidence < 0.6 if you're uncertain

**Output Format (JSON only, no additional text):**
```json
{{
  "parameters": {{
    "param_name_1": "value1",
    "param_name_2": "value2"
  }},
  "confidence": 0.85,
  "reasoning": "Explanation of your parameter choices"
}}
```

Generate the parameters now:"""

        return prompt

    def _parse_llm_response(self, response: str) -> Dict[str, Any]:
        """
        Parse LLM response into structured format.

        Args:
            response: LLM response string

        Returns:
            Parsed result dictionary
        """
        try:
            # Extract JSON from response (handle markdown code blocks)
            json_text = response.strip()

            # Remove markdown code blocks if present
            if json_text.startswith('```'):
                lines = json_text.split('\n')
                json_text = '\n'.join(lines[1:-1])  # Remove first and last line

            # Parse JSON
            result = json.loads(json_text)

            # Validate structure
            if 'parameters' not in result:
                raise ValueError("Response missing 'parameters' field")

            # Ensure confidence is float
            if 'confidence' in result:
                result['confidence'] = float(result['confidence'])
            else:
                result['confidence'] = 0.5  # Default

            # Ensure reasoning is string
            if 'reasoning' not in result:
                result['reasoning'] = "Parameters inferred from user query"

            return result

        except (json.JSONDecodeError, ValueError) as e:
            log.error(f"[LLMParamGen] Failed to parse LLM response: {e}")
            log.debug(f"[LLMParamGen] Response was: {response}")

            # Return empty parameters with low confidence
            return {
                'parameters': {},
                'confidence': 0.0,
                'reasoning': f"Failed to parse LLM response: {str(e)}"
            }

    def _validate_parameters(
        self,
        parameters: Dict[str, Any],
        tool_parameters: List[Dict[str, Any]]
    ) -> Dict[str, Any]:
        """
        Validate generated parameters against tool schema.

        Args:
            parameters: Generated parameters
            tool_parameters: Tool parameter specifications

        Returns:
            Validated parameters (with defaults for missing/invalid ones)
        """
        validated = {}
        param_specs = {p.get('name'): p for p in tool_parameters if p.get('name')}

        for param_name, param_spec in param_specs.items():
            param_type = param_spec.get('type', 'text')

            # Get generated value or default
            if param_name in parameters:
                value = parameters[param_name]
            else:
                value = param_spec.get('default', '')

            # Type validation and coercion
            try:
                if param_type == 'integer':
                    value = int(value) if value else param_spec.get('default', 0)
                elif param_type == 'float':
                    value = float(value) if value else param_spec.get('default', 0.0)
                elif param_type == 'boolean':
                    if isinstance(value, str):
                        value = value.lower() in ('true', 'yes', '1', 'on')
                    value = bool(value)
                elif param_type == 'select':
                    # Validate against options
                    options = param_spec.get('options', [])
                    if options and value not in options:
                        value = param_spec.get('default', options[0] if options else '')
                else:
                    # text, data, etc.
                    value = str(value) if value is not None else ''

                validated[param_name] = value

            except (ValueError, TypeError) as e:
                log.warning(f"[LLMParamGen] Invalid value for {param_name}: {value}, using default")
                validated[param_name] = param_spec.get('default', '')

        return validated

    def _get_default_parameters(self, tool_parameters: List[Dict[str, Any]]) -> Dict[str, Any]:
        """
        Get default values for all parameters.

        Args:
            tool_parameters: Tool parameter specifications

        Returns:
            Dictionary with default values
        """
        defaults = {}
        for param in tool_parameters:
            param_name = param.get('name')
            if not param_name:
                continue

            param_type = param.get('type', 'text')
            default_value = param.get('default')

            if default_value is not None:
                defaults[param_name] = default_value
            elif param_type == 'integer':
                defaults[param_name] = 0
            elif param_type == 'float':
                defaults[param_name] = 0.0
            elif param_type == 'boolean':
                defaults[param_name] = False
            else:
                defaults[param_name] = ''

        return defaults
