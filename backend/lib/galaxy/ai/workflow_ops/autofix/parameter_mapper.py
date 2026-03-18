"""
Universal Parameter Mapper for AutoFix System

Maps logical fix parameters to actual pipeline-specific parameters.
Supports both configuration-based mapping and LLM-powered intelligent inference.
"""

import logging
import yaml
import json
from typing import Dict, Any, Optional, List
from pathlib import Path

log = logging.getLogger(__name__)


class UniversalParameterMapper:
    """
    通用参数映射器

    优先级:
    1. 配置文件中的显式映射 (快速、准确)
    2. LLM智能推断 (灵活、适应新pipeline)
    3. 直接映射 (fallback)

    Examples:
        >>> mapper = UniversalParameterMapper()
        >>> fix_params = {'bowtie_mode': 'sensitive', 'alignments': '200'}
        >>> mapped = mapper.map_fix_params('clipseq', fix_params)
        >>> # Returns: {'bowtie_params': '-v 2 -m 200 --norc --best --strata'}
    """

    def __init__(self,
                 llm_client=None,
                 config_path: Optional[str] = None):
        """
        Initialize parameter mapper

        Args:
            llm_client: Optional LLM client for intelligent inference
            config_path: Path to parameter mappings YAML file
        """
        self.llm_client = llm_client

        # Load mapping configuration
        if config_path is None:
            # Default path - find Galaxy root directory
            # Current file is at: lib/galaxy/ai/workflow_ops/autofix/parameter_mapper.py
            # Galaxy root is 5 levels up, then config/
            galaxy_root = Path(__file__).parent.parent.parent.parent.parent.parent
            config_path = galaxy_root / 'config' / 'pipeline_parameter_mappings.yml'

        self.mappings = self._load_mappings(config_path)
        self.cache = {}  # Cache for LLM inferred mappings

        log.info(f"UniversalParameterMapper initialized with {len(self.mappings)} pipeline mappings")

    def _load_mappings(self, config_path: Path) -> Dict[str, Any]:
        """Load parameter mappings from YAML file"""
        try:
            if not Path(config_path).exists():
                log.warning(f"Mapping config not found: {config_path}, using empty mappings")
                return {}

            with open(config_path, 'r') as f:
                mappings = yaml.safe_load(f)

            log.info(f"Loaded parameter mappings for {len(mappings)} pipelines from {config_path}")
            return mappings or {}

        except Exception as e:
            log.error(f"Failed to load parameter mappings: {e}")
            return {}

    def map_fix_params(self,
                       pipeline_name: str,
                       fix_params: Dict[str, Any],
                       pipeline_config: Optional[Dict] = None) -> Dict[str, Any]:
        """
        Map AutoFix logical parameters to actual pipeline parameters

        Args:
            pipeline_name: Pipeline name (e.g., 'clipseq', 'rnaseq')
            fix_params: Logical fix parameters from AutoFix
                       e.g., {'bowtie_mode': 'sensitive', 'alignments': '200'}
            pipeline_config: Optional pipeline config/schema for LLM inference

        Returns:
            Mapped parameters ready for pipeline execution
            e.g., {'bowtie_params': '-v 2 -m 200 --norc --best --strata'}
        """
        if not fix_params:
            return {}

        log.info(f"Mapping {len(fix_params)} fix parameters for pipeline '{pipeline_name}'")
        log.debug(f"Input fix_params: {fix_params}")

        # 1. Try configuration-based mapping
        if pipeline_name in self.mappings:
            log.info(f"Using configuration mapping for {pipeline_name}")
            result = self._apply_config_mapping(pipeline_name, fix_params)
            log.info(f"Mapped to {len(result)} actual parameters: {result}")
            return result

        # 2. Try cached LLM inference
        cache_key = f"{pipeline_name}:{','.join(sorted(fix_params.keys()))}"
        if cache_key in self.cache:
            log.info(f"Using cached LLM mapping for {pipeline_name}")
            return self._apply_cached_mapping(fix_params, self.cache[cache_key])

        # 3. Try LLM intelligent inference
        if self.llm_client and pipeline_config:
            log.info(f"Using LLM inference for {pipeline_name}")
            try:
                mapping_rules = self._llm_infer_mapping(pipeline_name, fix_params, pipeline_config)
                self.cache[cache_key] = mapping_rules
                return mapping_rules
            except Exception as e:
                log.error(f"LLM inference failed: {e}, falling back to direct mapping")

        # 4. Fallback: direct mapping (parameter names unchanged)
        log.warning(f"No mapping found for {pipeline_name}, using direct mapping (may not work)")
        return fix_params

    def _apply_config_mapping(self, pipeline_name: str, fix_params: Dict[str, Any]) -> Dict[str, Any]:
        """Apply configuration-based parameter mapping"""
        pipeline_config = self.mappings[pipeline_name]
        result = {}
        unmapped_params = set(fix_params.keys())

        # Process each configuration section
        for section_name, section_config in pipeline_config.items():
            section_type = section_config.get('type')

            if section_type == 'composite_string':
                # Handle composite string parameters
                mapped = self._map_composite_string(section_config, fix_params)
                if mapped:
                    result.update(mapped)
                    # Remove mapped params from unmapped set
                    for param in section_config.get('logical_params', {}).keys():
                        unmapped_params.discard(param)

            elif section_type == 'direct':
                # Handle direct one-to-one mappings
                mapped = self._map_direct(section_config, fix_params)
                result.update(mapped)
                # Remove mapped params
                for from_param in section_config.get('mappings', {}).keys():
                    unmapped_params.discard(from_param)

        # Apply global mappings for unmapped parameters
        if '_global' in self.mappings and unmapped_params:
            global_config = self.mappings['_global']
            for section_config in global_config.values():
                if section_config.get('type') == 'direct':
                    global_mapped = self._map_direct(section_config, fix_params)
                    result.update(global_mapped)

        return result

    def _map_composite_string(self, config: Dict[str, Any], fix_params: Dict[str, Any]) -> Dict[str, str]:
        """
        Map multiple logical parameters to a single composite string parameter

        Example:
            config = {
                'target_param': 'bowtie_params',
                'template': '-v {mismatches} -m {max_alignments}',
                'defaults': {'mismatches': 2, 'max_alignments': 100},
                'logical_params': {
                    'bowtie_mode': {'sensitive': {'mismatches': 2, 'max_alignments': 200}}
                }
            }
            fix_params = {'bowtie_mode': 'sensitive'}

            Returns: {'bowtie_params': '-v 2 -m 200'}
        """
        target_param = config['target_param']
        template = config['template']
        defaults = config.get('defaults', {})
        logical_params_config = config.get('logical_params', {})

        # Start with defaults
        template_vars = defaults.copy()
        extra_flags = []

        # Process each logical parameter
        for logical_param, value in fix_params.items():
            if logical_param not in logical_params_config:
                continue

            param_config = logical_params_config[logical_param]

            # Check if it's a preset mode
            if isinstance(param_config, dict) and value in param_config:
                # Apply preset values
                preset_values = param_config[value]
                template_vars.update(preset_values)

            # Check if it maps to a template variable
            elif isinstance(param_config, dict) and 'template_var' in param_config:
                template_vars[param_config['template_var']] = value

            # Check if it should be appended to template
            elif isinstance(param_config, dict) and 'append_to_template' in param_config:
                flag = param_config['append_to_template'].format(value=value)
                extra_flags.append(flag)

        # Build final parameter string
        try:
            param_string = template.format(**template_vars)
            if extra_flags:
                param_string += ' ' + ' '.join(extra_flags)

            return {target_param: param_string}

        except KeyError as e:
            log.error(f"Template variable missing: {e}, template: {template}, vars: {template_vars}")
            return {}

    def _map_direct(self, config: Dict[str, Any], fix_params: Dict[str, Any]) -> Dict[str, Any]:
        """
        Map parameters using direct one-to-one mapping

        Example:
            config = {'mappings': {'skip_filter_gtf': 'skip_filter_gtf'}}
            fix_params = {'skip_filter_gtf': True}

            Returns: {'skip_filter_gtf': True}
        """
        mappings = config.get('mappings', {})
        result = {}

        for from_param, to_param in mappings.items():
            if from_param in fix_params:
                result[to_param] = fix_params[from_param]

        return result

    def _apply_cached_mapping(self, fix_params: Dict[str, Any], cached_rules: Dict[str, Any]) -> Dict[str, Any]:
        """Apply cached LLM-inferred mapping rules"""
        # For now, just return the cached result directly
        # In the future, we could apply the rules to new values
        return cached_rules

    def _llm_infer_mapping(self,
                          pipeline_name: str,
                          fix_params: Dict[str, Any],
                          pipeline_config: Dict[str, Any]) -> Dict[str, Any]:
        """
        Use LLM to intelligently infer parameter mapping

        This is used when no configuration mapping exists for the pipeline.
        The LLM analyzes the pipeline's parameter schema and suggests the mapping.
        """
        if not self.llm_client:
            raise ValueError("LLM client not available for inference")

        # Extract relevant schema information
        schema_str = json.dumps(pipeline_config, indent=2)[:2000]  # Limit size

        prompt = f"""You are a Nextflow pipeline parameter mapping expert.

Pipeline: {pipeline_name}

Pipeline parameter schema:
{schema_str}

AutoFix suggested parameter changes:
{json.dumps(fix_params, indent=2)}

Task: Map the fix parameters to the actual parameters supported by this pipeline.

Rules:
1. If the pipeline has composite string parameters (like bowtie_params), merge multiple logical parameters into one
2. If there are direct corresponding parameters, use one-to-one mapping
3. Preserve the meaning of the original parameter values
4. Only return parameters that actually exist in the pipeline schema

Return JSON format:
{{
  "mapped_params": {{"actual_param_name": "value"}},
  "reasoning": "brief explanation of the mapping"
}}
"""

        response = self.llm_client.call(prompt, max_tokens=1000)

        # Parse response
        content = response.get('content', [])
        if isinstance(content, list):
            text = ''.join([block.get('text', '') for block in content if block.get('type') == 'text'])
        else:
            text = content

        result = json.loads(text)

        log.info(f"LLM mapping reasoning: {result.get('reasoning')}")
        return result.get('mapped_params', {})

    def get_supported_pipelines(self) -> List[str]:
        """Get list of pipelines with configured mappings"""
        return [p for p in self.mappings.keys() if not p.startswith('_')]
