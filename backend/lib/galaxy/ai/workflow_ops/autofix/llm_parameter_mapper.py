"""
LLM-Driven Universal Parameter Mapper for AutoFix System

This is an enhanced version that prioritizes LLM intelligence over static configuration.
Features:
- LLM-first approach for maximum adaptability
- Automatic learning and caching
- Self-improving through usage
- Handles any pipeline without pre-configuration
"""

import logging
import yaml
import json
from typing import Dict, Any, Optional, List
from pathlib import Path
from datetime import datetime

log = logging.getLogger(__name__)


class LLMParameterMapper:
    """
    LLM驱动的智能参数映射器

    核心理念：
    - LLM是主要方案，配置文件是辅助
    - 自动学习和缓存映射规则
    - 即使全新的pipeline也能自动处理
    - 持续优化，越用越智能

    Examples:
        >>> from galaxy.ai.workflow_ops.llm_client import LLMClient
        >>> llm_client = LLMClient(app.config)
        >>> mapper = LLMParameterMapper(llm_client=llm_client)
        >>>
        >>> # 即使是从未见过的pipeline也能自动映射
        >>> fix_params = {'sensitivity': 'high', 'max_reads': '1000000'}
        >>> mapped = mapper.map_fix_params('brand_new_pipeline', fix_params)
        >>> # LLM会分析pipeline schema并自动生成正确的映射
    """

    def __init__(self,
                 llm_client,
                 config_path: Optional[str] = None,
                 cache_path: Optional[str] = None,
                 enable_learning: bool = True):
        """
        Initialize LLM-driven parameter mapper

        Args:
            llm_client: LLM client for intelligent inference (required)
            config_path: Optional path to static mappings (for override)
            cache_path: Path to persistent cache file
            enable_learning: If True, automatically cache successful mappings
        """
        if not llm_client:
            raise ValueError("LLM client is required for LLMParameterMapper")

        self.llm_client = llm_client
        self.enable_learning = enable_learning

        # Load static configuration (optional, for override)
        if config_path is None:
            galaxy_root = Path(__file__).parent.parent.parent.parent.parent.parent
            config_path = galaxy_root / 'config' / 'pipeline_parameter_mappings.yml'

        self.static_mappings = self._load_mappings(config_path)

        # Load persistent cache
        if cache_path is None:
            galaxy_root = Path(__file__).parent.parent.parent.parent.parent.parent
            cache_path = galaxy_root / 'database' / 'ai_workflow_ops' / 'llm_parameter_mapping_cache.json'

        self.cache_path = Path(cache_path)
        self.cache = self._load_cache()

        log.info(f"🤖 LLMParameterMapper initialized (LLM-first mode)")
        log.info(f"   Static mappings: {len(self.static_mappings)} pipelines")
        log.info(f"   Learned mappings: {len(self.cache)} cached entries")
        log.info(f"   Learning enabled: {enable_learning}")

    def _load_mappings(self, config_path: Path) -> Dict[str, Any]:
        """Load optional static parameter mappings from YAML file"""
        try:
            if not Path(config_path).exists():
                log.info(f"No static config found at {config_path}, using pure LLM mode")
                return {}

            with open(config_path, 'r') as f:
                mappings = yaml.safe_load(f)

            log.info(f"Loaded {len(mappings)} static pipeline mappings from {config_path}")
            return mappings or {}

        except Exception as e:
            log.warning(f"Failed to load static mappings: {e}, using pure LLM mode")
            return {}

    def _load_cache(self) -> Dict[str, Any]:
        """Load persistent cache of LLM-inferred mappings"""
        try:
            if not self.cache_path.exists():
                log.info("No cache file found, starting with empty cache")
                return {}

            with open(self.cache_path, 'r') as f:
                cache = json.load(f)

            log.info(f"Loaded {len(cache)} cached mappings from {self.cache_path}")
            return cache

        except Exception as e:
            log.warning(f"Failed to load cache: {e}, starting fresh")
            return {}

    def _save_cache(self):
        """Save cache to persistent storage"""
        try:
            self.cache_path.parent.mkdir(parents=True, exist_ok=True)

            with open(self.cache_path, 'w') as f:
                json.dump(self.cache, f, indent=2)

            log.debug(f"Saved {len(self.cache)} cached mappings to {self.cache_path}")

        except Exception as e:
            log.error(f"Failed to save cache: {e}")

    def map_fix_params(self,
                       pipeline_name: str,
                       fix_params: Dict[str, Any],
                       pipeline_schema: Optional[Dict] = None,
                       workflow_config: Optional[Dict] = None) -> Dict[str, Any]:
        """
        Map AutoFix parameters to pipeline-specific parameters using LLM intelligence

        Args:
            pipeline_name: Pipeline name (e.g., 'clipseq', 'rnaseq', or unknown)
            fix_params: Logical fix parameters from AutoFix
            pipeline_schema: Pipeline's nextflow_schema.json (if available)
            workflow_config: Runtime workflow configuration (if available)

        Returns:
            Mapped parameters ready for pipeline execution
        """
        if not fix_params:
            return {}

        log.info(f"🤖 LLM mapping {len(fix_params)} parameters for pipeline '{pipeline_name}'")
        log.debug(f"   Input: {fix_params}")

        # 策略1: 检查缓存 (最快)
        cache_key = self._make_cache_key(pipeline_name, fix_params)
        if cache_key in self.cache:
            cached_entry = self.cache[cache_key]
            log.info(f"✅ Using cached mapping (created: {cached_entry.get('created_at', 'unknown')})")
            log.info(f"   Reasoning: {cached_entry.get('reasoning', 'N/A')}")
            return cached_entry['mapped_params']

        # 策略2: 检查静态配置 (作为hint给LLM)
        static_hint = None
        if pipeline_name in self.static_mappings:
            log.info(f"📋 Found static mapping for {pipeline_name}, will use as hint for LLM")
            static_hint = self.static_mappings[pipeline_name]

        # 策略3: LLM智能推断 (核心功能)
        log.info(f"🔍 Using LLM to infer parameter mapping...")

        try:
            mapped_params, reasoning = self._llm_infer_mapping(
                pipeline_name=pipeline_name,
                fix_params=fix_params,
                pipeline_schema=pipeline_schema,
                workflow_config=workflow_config,
                static_hint=static_hint
            )

            log.info(f"✅ LLM mapping successful:")
            log.info(f"   Reasoning: {reasoning}")
            log.info(f"   Output: {mapped_params}")

            # 学习：缓存成功的映射
            if self.enable_learning:
                self._cache_mapping(cache_key, mapped_params, reasoning, pipeline_name, fix_params)

            return mapped_params

        except Exception as e:
            log.error(f"❌ LLM mapping failed: {e}")

            # Fallback: 使用静态配置
            if static_hint:
                log.warning(f"Falling back to static config for {pipeline_name}")
                from .parameter_mapper import UniversalParameterMapper
                static_mapper = UniversalParameterMapper(llm_client=None)
                return static_mapper._apply_config_mapping(pipeline_name, fix_params)

            # 最后fallback: 直接映射
            log.warning(f"No fallback available, using direct mapping (may not work)")
            return fix_params

    def _make_cache_key(self, pipeline_name: str, fix_params: Dict[str, Any]) -> str:
        """Generate cache key from pipeline name and parameter names"""
        param_signature = ','.join(sorted(fix_params.keys()))
        return f"{pipeline_name}:{param_signature}"

    def _cache_mapping(self,
                      cache_key: str,
                      mapped_params: Dict[str, Any],
                      reasoning: str,
                      pipeline_name: str,
                      original_params: Dict[str, Any]):
        """Cache a successful mapping for future use"""
        self.cache[cache_key] = {
            'mapped_params': mapped_params,
            'reasoning': reasoning,
            'pipeline_name': pipeline_name,
            'original_params': original_params,
            'created_at': datetime.now().isoformat(),
            'usage_count': 1
        }

        self._save_cache()
        log.info(f"📚 Learned new mapping for {pipeline_name} (total: {len(self.cache)} entries)")

    def _llm_infer_mapping(self,
                          pipeline_name: str,
                          fix_params: Dict[str, Any],
                          pipeline_schema: Optional[Dict],
                          workflow_config: Optional[Dict],
                          static_hint: Optional[Dict]) -> tuple[Dict[str, Any], str]:
        """
        Use LLM to intelligently infer parameter mapping

        Returns:
            (mapped_params, reasoning)
        """
        # 构建上下文信息
        context_parts = []

        # 1. Pipeline schema
        if pipeline_schema:
            schema_str = json.dumps(pipeline_schema, indent=2)[:3000]
            context_parts.append(f"Pipeline Schema (from nextflow_schema.json):\n{schema_str}")

        # 2. Workflow config
        if workflow_config:
            config_str = json.dumps(workflow_config, indent=2)[:1000]
            context_parts.append(f"\nCurrent Workflow Config:\n{config_str}")

        # 3. Static hint
        if static_hint:
            hint_str = yaml.dump(static_hint, default_flow_style=False)[:1000]
            context_parts.append(f"\nReference Mapping (as hint):\n{hint_str}")

        context = "\n\n".join(context_parts) if context_parts else "No schema or config available"

        # 构建LLM prompt
        prompt = f"""You are an expert in Nextflow pipeline parameter mapping for bioinformatics workflows.

**Task**: Map AutoFix's logical parameter suggestions to the actual parameters supported by this pipeline.

**Pipeline**: {pipeline_name}

**AutoFix Parameter Suggestions**:
{json.dumps(fix_params, indent=2)}

**Available Context**:
{context}

**Your Job**:
1. Analyze the pipeline's parameter structure
2. Identify if parameters are:
   - Direct mappings (one-to-one, possibly with name changes)
   - Composite strings (multiple logical params merged into one string)
   - Complex structures (nested or conditional)
3. Map each AutoFix parameter to the correct pipeline parameter format
4. Preserve the semantic meaning of each parameter value
5. Only use parameters that actually exist in the pipeline

**Important Rules**:
- If a parameter is a composite string (like bowtie_params, star_params), construct the full string
- If parameter names don't match exactly, find the closest semantic match
- If you're unsure, be explicit about assumptions in your reasoning
- Prefer working solutions over theoretical perfection

**Output Format** (JSON only, no markdown):
{{
  "mapped_params": {{
    "actual_param_name_1": "value1",
    "actual_param_name_2": "value2"
  }},
  "reasoning": "Brief explanation of mapping decisions, especially for composite params or name changes"
}}
"""

        # 调用LLM
        response = self.llm_client.call(prompt, max_tokens=2000)

        # 解析响应
        content = response.get('content', [])
        if isinstance(content, list):
            text = ''.join([block.get('text', '') for block in content if block.get('type') == 'text'])
        else:
            text = content

        # 提取JSON (处理可能的markdown包装)
        text = text.strip()
        if text.startswith('```'):
            # Remove markdown code blocks
            lines = text.split('\n')
            text = '\n'.join(line for line in lines if not line.startswith('```'))
            text = text.strip()

        result = json.loads(text)

        mapped_params = result.get('mapped_params', {})
        reasoning = result.get('reasoning', 'No reasoning provided')

        return mapped_params, reasoning

    def get_cache_stats(self) -> Dict[str, Any]:
        """Get statistics about cached mappings"""
        pipeline_counts = {}
        for entry in self.cache.values():
            pipeline = entry.get('pipeline_name', 'unknown')
            pipeline_counts[pipeline] = pipeline_counts.get(pipeline, 0) + 1

        return {
            'total_cached': len(self.cache),
            'pipelines_learned': len(pipeline_counts),
            'by_pipeline': pipeline_counts,
            'cache_path': str(self.cache_path)
        }

    def clear_cache(self, pipeline_name: Optional[str] = None):
        """Clear cache (all or for specific pipeline)"""
        if pipeline_name:
            # Clear only specific pipeline
            keys_to_remove = [
                key for key, entry in self.cache.items()
                if entry.get('pipeline_name') == pipeline_name
            ]
            for key in keys_to_remove:
                del self.cache[key]
            log.info(f"Cleared {len(keys_to_remove)} cached entries for {pipeline_name}")
        else:
            # Clear all
            self.cache = {}
            log.info("Cleared all cached mappings")

        self._save_cache()
