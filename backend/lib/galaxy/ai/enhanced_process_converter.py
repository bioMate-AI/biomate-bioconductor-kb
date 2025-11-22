#!/usr/bin/env python3
"""
Enhanced Process Converter

Integrates EnhancedPromptBuilder and NextflowBestPracticesScorer into the
existing ProcessConverter to improve conversion quality.

Author: BioMate Team
Date: 2025-11-22
"""

from typing import Dict, List, Optional
from concurrent.futures import ThreadPoolExecutor, as_completed
import time

from dual_llm_converter_system import (
    GeminiClient,
    DocumentationProvider,
    ConversionResult
)

from improved_galaxy_to_nextflow import (
    EnhancedPromptBuilder,
    NextflowBestPracticesScorer,
    TypeInference,
    ToolGroup
)


class EnhancedProcessConverter:
    """
    Enhanced ProcessConverter that uses:
    1. EnhancedPromptBuilder for better prompts
    2. NextflowBestPracticesScorer for quality assessment
    3. Type information for context-aware conversion
    """

    def __init__(self,
                 gemini_client: GeminiClient,
                 doc_provider: DocumentationProvider,
                 claude_converter=None,
                 prompt_builder: Optional[EnhancedPromptBuilder] = None,
                 scorer: Optional[NextflowBestPracticesScorer] = None):
        """
        Initialize enhanced converter.

        Args:
            gemini_client: Gemini API client
            doc_provider: Documentation provider for nf-core context
            claude_converter: Optional Claude converter
            prompt_builder: Enhanced prompt builder (creates if None)
            scorer: Best practices scorer (creates if None)
        """

        self.gemini = gemini_client
        self.docs = doc_provider
        self.claude_converter = claude_converter

        # New components
        self.prompt_builder = prompt_builder or EnhancedPromptBuilder()
        self.scorer = scorer or NextflowBestPracticesScorer()

    def convert_all_processes(self,
                             processes: List[Dict],
                             type_map: Optional[Dict[str, TypeInference]] = None,
                             tool_groups: Optional[List[ToolGroup]] = None):
        """
        Convert all processes with enhanced prompts and scoring.

        Args:
            processes: List of Galaxy process definitions
            type_map: Inferred types for inputs (from GalaxyTypeInferencer)
            tool_groups: Grouped tools for conditional merging (from ToolGrouper)

        Returns:
            Combined results from both LLMs with quality scores
        """

        print(f"\n🔄 Converting {len(processes)} processes with enhanced dual-LLM...")
        print("=" * 80)

        type_map = type_map or {}
        tool_groups = tool_groups or []

        # Identify which processes are in groups (for conditional conversion)
        grouped_step_ids = set()
        for group in tool_groups:
            grouped_step_ids.update(group.steps)

        # Start both conversions in parallel
        with ThreadPoolExecutor(max_workers=2) as executor:
            # Claude conversion
            print("🤖 Claude: Starting conversion...")
            claude_future = executor.submit(
                self._convert_with_claude,
                processes,
                type_map,
                grouped_step_ids
            )

            # Gemini conversion with enhanced prompts
            print("🤖 Gemini: Starting conversion with enhanced prompts...")
            gemini_future = executor.submit(
                self._convert_with_gemini_enhanced,
                processes,
                type_map,
                grouped_step_ids
            )

            claude_results = claude_future.result()
            gemini_results = gemini_future.result()

        # Combine results and add quality scores
        combined = {}
        for proc in processes:
            proc_id = proc['id']

            claude_result = claude_results.get(proc_id)
            gemini_result = gemini_results.get(proc_id)

            # Score both results
            if claude_result and claude_result.nextflow_code:
                claude_score = self.scorer.score_process(
                    claude_result.nextflow_code,
                    proc
                )
                claude_result.quality_score = claude_score
            else:
                claude_score = 0.0

            if gemini_result and gemini_result.nextflow_code:
                gemini_score = self.scorer.score_process(
                    gemini_result.nextflow_code,
                    proc
                )
                gemini_result.quality_score = gemini_score
            else:
                gemini_score = 0.0

            combined[proc_id] = {
                'claude': claude_result,
                'gemini': gemini_result,
                'source_process': proc,
                'claude_score': claude_score,
                'gemini_score': gemini_score
            }

            # Print scores
            print(f"\n📊 {proc_id} quality scores:")
            print(f"   Claude: {claude_score:.1f}/100")
            print(f"   Gemini: {gemini_score:.1f}/100")

        print("=" * 80)
        return combined

    def _convert_with_claude(self,
                            processes: List[Dict],
                            type_map: Dict,
                            grouped_step_ids: set):
        """Convert with Claude using existing converter."""

        results = {}

        if self.claude_converter:
            from galaxy.ai.workflow_abstraction import DetailedStep

            for proc in processes:
                # Check if this is part of a group (skip individual conversion)
                if proc['id'] in grouped_step_ids:
                    print(f"   ⏭️  {proc['id']} (part of conditional group)")
                    continue

                detailed_step = DetailedStep(
                    step_id=proc['id'],
                    tool_id=proc.get('tool_id', ''),
                    tool_name=proc.get('tool_name', ''),
                    tool_version=proc.get('tool_version', 'latest'),
                    description=proc.get('annotation', ''),
                    annotation=proc.get('annotation', '')
                )

                result = self.claude_converter._generate_process_definition(detailed_step)
                env_yml = self.claude_converter._generate_environment_yml(detailed_step)

                results[proc['id']] = ConversionResult(
                    process_id=proc['id'],
                    nextflow_code=result,
                    environment_yml=env_yml,
                    confidence=0.9,
                    model='claude-sonnet-4.5'
                )
                print(f"   ✅ {proc['id']}")
        else:
            print("   ⚠️  No Claude converter provided, skipping")

        return results

    def _convert_with_gemini_enhanced(self,
                                     processes: List[Dict],
                                     type_map: Dict,
                                     grouped_step_ids: set):
        """
        Convert with Gemini using enhanced prompts.

        This is the key improvement: we use EnhancedPromptBuilder
        instead of the basic doc_provider prompts.
        """

        print(f"   Converting {len(processes)} processes with enhanced prompts...")
        start = time.time()

        results = {}
        with ThreadPoolExecutor(max_workers=10) as executor:
            futures = {}

            for process in processes:
                proc_id = process['id']

                # Check if part of group (skip individual conversion)
                if proc_id in grouped_step_ids:
                    print(f"   ⏭️  {proc_id} (part of conditional group)")
                    continue

                # Build enhanced prompt
                enhanced_prompt = self._build_enhanced_prompt(
                    process,
                    type_map
                )

                # Get nf-core documentation context
                doc_context = self.docs.get_prefix()

                # Combine
                full_prompt = f"{doc_context}\n\n{enhanced_prompt}"

                # Submit for conversion
                future = executor.submit(
                    self.gemini._convert_single,
                    proc_id,
                    full_prompt
                )
                futures[future] = proc_id

            # Collect results
            for future in as_completed(futures):
                proc_id = futures[future]
                try:
                    result = future.result()
                    results[proc_id] = result
                    print(f"   ✅ {proc_id}")
                except Exception as e:
                    print(f"   ❌ {proc_id}: {e}")
                    results[proc_id] = None

        elapsed = time.time() - start
        success_count = sum(1 for r in results.values() if r is not None)
        print(f"   Gemini completed: {success_count}/{len(processes)} in {elapsed:.1f}s")

        return results

    def _build_enhanced_prompt(self,
                              process: Dict,
                              type_map: Dict) -> str:
        """
        Build enhanced prompt using EnhancedPromptBuilder.

        Args:
            process: Galaxy process definition
            type_map: Inferred types for inputs

        Returns:
            Enhanced prompt string
        """

        # Extract types relevant to this process
        process_types = {}

        # Get input connections to find relevant types
        input_connections = process.get('input_connections', {})
        for input_name, connection in input_connections.items():
            if isinstance(connection, dict):
                source_step_id = str(connection.get('id'))
                if source_step_id in type_map:
                    process_types[input_name] = type_map[source_step_id]

        # Build prompt using EnhancedPromptBuilder
        prompt = self.prompt_builder.build_process_prompt(
            galaxy_step=process,
            inferred_types=process_types,
            is_conditional_group=False,  # Individual process
            group_info=None,
            doc_context=""  # Will be added separately
        )

        return prompt

    def convert_conditional_group(self,
                                 group: ToolGroup,
                                 group_steps: List[Dict],
                                 type_map: Dict) -> Dict:
        """
        Convert a group of alternative tools into single conditional process.

        Args:
            group: ToolGroup information
            group_steps: List of Galaxy steps in this group
            type_map: Inferred types

        Returns:
            Combined results from both LLMs
        """

        print(f"\n🔀 Converting conditional group: {group.group_id}")
        print(f"   Tools: {len(group.tools)} alternatives")
        print(f"   Strategy: {group.merge_strategy}")

        # Extract types for this group
        group_types = {}
        for step in group_steps:
            for input_name, connection in step.get('input_connections', {}).items():
                if isinstance(connection, dict):
                    source_id = str(connection.get('id'))
                    if source_id in type_map:
                        group_types[input_name] = type_map[source_id]

        # Build conditional prompt
        conditional_prompt = self.prompt_builder.build_process_prompt(
            galaxy_step=group_steps[0],  # Use first step as template
            inferred_types=group_types,
            is_conditional_group=True,
            group_info=group,
            doc_context=""
        )

        # Get doc context
        doc_context = self.docs.get_prefix()
        full_prompt = f"{doc_context}\n\n{conditional_prompt}"

        # Convert with Gemini (could also do Claude in parallel)
        print("   🤖 Gemini: Converting conditional group...")

        try:
            result = self.gemini._convert_single(group.group_id, full_prompt)

            # Score the result
            if result and result.nextflow_code:
                score = self.scorer.score_process(
                    result.nextflow_code,
                    group_steps[0]  # Use first step for context
                )
                result.quality_score = score

                print(f"   ✅ Converted: {group.group_id} (score: {score:.1f}/100)")

                return {
                    'gemini': result,
                    'claude': None,  # Could add Claude here too
                    'source_group': group,
                    'gemini_score': score,
                    'claude_score': 0.0
                }
            else:
                print(f"   ❌ Conversion failed")
                return None

        except Exception as e:
            print(f"   ❌ Error: {e}")
            return None
