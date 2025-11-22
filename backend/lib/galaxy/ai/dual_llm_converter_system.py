#!/usr/bin/env python3
"""
Dual-LLM Workflow Converter with Iterative Refinement

This system uses both Claude and Gemini to convert Galaxy workflows to Nextflow,
then tests and refines them iteratively until they run successfully.

Architecture:
1. DocumentationProvider - Loads and caches reference docs (optimized for Gemini caching)
2. GeminiClient - Handles Gemini API with implicit caching
3. ProcessConverter - Orchestrates both LLMs for parallel conversion
4. AssemblyAuditor - Claude audits and merges both outputs
5. NextflowTester - Tests with real Nextflow execution
6. IterativeRefiner - Manages the complete refinement loop

Author: BioMate Team
Date: 2025-11-20
"""

import json
import time
import tempfile
import subprocess
import re
from pathlib import Path
from typing import Dict, List, Any, Optional
from dataclasses import dataclass, field
from concurrent.futures import ThreadPoolExecutor, as_completed
import google.generativeai as genai

# ==============================================================================
# Data Structures
# ==============================================================================

@dataclass
class TestResult:
    """Result from Nextflow testing."""
    success: bool
    errors: Dict[str, List[Dict]] = field(default_factory=dict)
    stdout: str = ""
    stderr: str = ""
    execution_time: float = 0.0


@dataclass
class ConversionResult:
    """Result from LLM conversion."""
    process_id: str
    nextflow_code: str
    environment_yml: Optional[str] = None
    confidence: float = 0.0
    model: str = "unknown"


@dataclass
class AuditReport:
    """Audit report from Claude."""
    process_id: str
    claude_score: float
    gemini_score: float
    decision: str
    merged_code: str
    reasoning: str


# ==============================================================================
# Component 1: Documentation Provider
# ==============================================================================

class DocumentationProvider:
    """
    Manages documentation for LLM context with implicit caching optimization.

    Strategy:
    - Load all reference docs once
    - Build stable prefix for Gemini (enables implicit caching)
    - Reuse prefix across all requests
    """

    def __init__(self, project_root: Path):
        self.project_root = project_root
        self.research_dir = project_root / "research"
        self.backend_dir = project_root / "backend"

        print("📚 Loading documentation...")
        self.galaxy_docs = self._load_galaxy_docs()
        self.nextflow_docs = self._load_nextflow_docs()
        self.comparison_docs = self._load_comparison_docs()
        self.examples = self._load_examples()

        # Build stable prefix for Gemini caching
        self.gemini_prefix = self._build_gemini_prefix()
        print(f"   ✅ Documentation loaded ({len(self.gemini_prefix)} chars prefix)")

    def _load_galaxy_docs(self):
        """Load Galaxy format documentation."""
        docs = {}

        # Load comparison document
        comp_file = self.research_dir / "GALAXY_VS_NEXTFLOW_TECHNICAL_COMPARISON.md"
        if comp_file.exists():
            docs['comparison'] = comp_file.read_text()

        return docs

    def _load_nextflow_docs(self):
        """Load Nextflow format documentation."""
        docs = {}

        # Load nf-core examples
        nfcore_dir = self.backend_dir / "nf-core-workflows"
        if nfcore_dir.exists():
            # Load sample process definitions
            process_files = list(nfcore_dir.glob("**/modules/nf-core/**/main.nf"))[:3]
            docs['examples'] = []
            for pf in process_files:
                docs['examples'].append({
                    'path': str(pf),
                    'content': pf.read_text()[:2000]  # First 2000 chars
                })

        return docs

    def _load_comparison_docs(self):
        """Load comparison analysis."""
        docs = {}

        # Load gap analysis
        gap_file = self.research_dir / "GALAXY_TO_NEXTFLOW_GAP_ANALYSIS_20251120.md"
        if gap_file.exists():
            docs['gap_analysis'] = gap_file.read_text()

        return docs

    def _load_examples(self):
        """Load real-world examples."""
        examples = {
            'galaxy_workflows': [],
            'nextflow_modules': []
        }

        # Load sample Galaxy workflows
        galaxy_wf_dir = self.backend_dir / "galaxy_workflows_reformatted"
        if galaxy_wf_dir.exists():
            wf_files = list(galaxy_wf_dir.glob("*.ga"))[:2]
            for wf in wf_files:
                examples['galaxy_workflows'].append({
                    'name': wf.stem,
                    'path': str(wf)
                })

        return examples

    def _build_gemini_prefix(self):
        """
        Build stable prefix for Gemini implicit caching.

        CRITICAL: This must be IDENTICAL for all requests to maximize cache hits.
        Put large, common content first.
        """

        prefix = """# GALAXY TO NEXTFLOW CONVERSION REFERENCE DOCUMENTATION

You are an expert at converting Galaxy workflows to Nextflow DSL2 format.

## TASK OVERVIEW

You will be given a Galaxy tool/process definition and must convert it to a complete,
runnable Nextflow process definition following nf-core best practices.

## GALAXY WORKFLOW FORMAT

Galaxy workflows are JSON files (.ga) containing:
- Steps: Individual tool executions
- tool_id: ToolShed reference (e.g., "toolshed.g2.bx.psu.edu/repos/...")
- tool_version: Version string
- inputs: Input datasets and parameters
- outputs: Output datasets
- requirements: Dependencies (conda packages, containers)

## NEXTFLOW DSL2 FORMAT

Nextflow processes are Groovy scripts with structure:
```groovy
process PROCESS_NAME {
    tag "$meta.id"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "biocontainers/tool:version"

    input:
    tuple val(meta), path(reads)

    output:
    tuple val(meta), path("*.bam"), emit: bam
    path "versions.yml", emit: versions

    script:
    \"\"\"
    tool_command \\
        --input $reads \\
        --output output.bam

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        tool: \$(tool --version)
    END_VERSIONS
    \"\"\"
}
```

## CRITICAL REQUIREMENTS

1. MUST include real tool command (not placeholder echo)
2. MUST handle inputs correctly (meta + files pattern)
3. MUST generate proper outputs with emit names
4. MUST include version tracking (versions.yml)
5. MUST use proper Groovy syntax ($variable, ${expression})
6. MUST include conda directive with environment.yml
7. MUST include container directive (biocontainers)
8. SHOULD use appropriate resource label

## RESOURCE LABELS (nf-core standard)

- process_single: 1 CPU, 6GB RAM - simple tools
- process_low: 2 CPUs, 12GB RAM - QC, trimming
- process_medium: 6 CPUs, 36GB RAM - quantification
- process_high: 12 CPUs, 72GB RAM - alignment, assembly
- process_high_memory: 12 CPUs, 200GB RAM - memory-intensive

"""

        # Add comparison docs if available
        if 'comparison' in self.galaxy_docs:
            prefix += f"\n## GALAXY VS NEXTFLOW TECHNICAL COMPARISON\n\n"
            prefix += self.galaxy_docs['comparison'][:5000]  # First 5000 chars
            prefix += "\n\n"

        # Add Nextflow examples
        if 'examples' in self.nextflow_docs:
            prefix += "\n## REAL NEXTFLOW PROCESS EXAMPLES (from nf-core)\n\n"
            for i, example in enumerate(self.nextflow_docs['examples'][:2], 1):
                prefix += f"### Example {i}: {example['path']}\n```groovy\n"
                prefix += example['content']
                prefix += "\n```\n\n"

        prefix += "\n---\n\n"

        return prefix

    def get_gemini_prompt(self, process_specific_content: str):
        """
        Build complete prompt for Gemini with caching.

        Stable prefix + variable content = cache hit on prefix
        """
        return self.gemini_prefix + process_specific_content

    def format_process_for_conversion(self, process: Dict):
        """Format Galaxy process for conversion prompt."""

        prompt = f"""## CONVERSION TASK

Convert the following Galaxy process to Nextflow DSL2 format.

### Galaxy Process Information

- Tool ID: {process.get('tool_id', 'unknown')}
- Tool Name: {process.get('tool_name', 'unknown')}
- Tool Version: {process.get('tool_version', 'latest')}
- Description: {process.get('annotation', '')}

### Galaxy Requirements

```json
{json.dumps(process.get('requirements', []), indent=2)}
```

### Galaxy Inputs

```json
{json.dumps(process.get('inputs', []), indent=2)}
```

### Galaxy Outputs

```json
{json.dumps(process.get('outputs', []), indent=2)}
```

### INSTRUCTIONS

Generate a COMPLETE, RUNNABLE Nextflow process definition that:

1. Uses the REAL tool command (not echo placeholder)
2. Properly handles all inputs with meta tuple pattern
3. Generates all outputs with correct emit names
4. Includes conda environment directive
5. Includes container directive
6. Includes version tracking
7. Uses appropriate resource label
8. Follows nf-core conventions

### OUTPUT FORMAT

Return ONLY the Nextflow process definition in this format:

```groovy
process TOOL_NAME {{
    // ... complete process definition
}}
```

Also provide the environment.yml content:

```yaml
channels:
  - conda-forge
  - bioconda
dependencies:
  - tool_name=version
```
"""
        return prompt


# ==============================================================================
# Component 2: Gemini Client
# ==============================================================================

class GeminiClient:
    """Gemini API client optimized for implicit caching."""

    def __init__(self, api_key: str):
        genai.configure(api_key=api_key)
        self.model = genai.GenerativeModel('gemini-2.0-flash-exp')

    def convert_processes_parallel(self, processes: List[Dict],
                                   doc_provider: DocumentationProvider):
        """
        Convert multiple processes in parallel with cache optimization.

        Strategy:
        1. All requests use same prefix (from doc_provider)
        2. Sent in quick succession for temporal cache locality
        3. Parallel execution reduces total time
        """

        print(f"🤖 Gemini: Converting {len(processes)} processes (parallel)...")
        start = time.time()

        results = {}
        with ThreadPoolExecutor(max_workers=10) as executor:
            futures = {}

            # Submit all requests quickly (cache optimization)
            for process in processes:
                process_content = doc_provider.format_process_for_conversion(process)
                full_prompt = doc_provider.get_gemini_prompt(process_content)

                future = executor.submit(self._convert_single, process['id'], full_prompt)
                futures[future] = process['id']

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

    def _convert_single(self, proc_id: str, prompt: str):
        """Convert single process."""
        try:
            response = self.model.generate_content(prompt)
            return self._parse_response(proc_id, response.text)
        except Exception as e:
            print(f"⚠️  Gemini error for {proc_id}: {e}")
            return None

    def _parse_response(self, proc_id: str, text: str):
        """Parse Gemini response to extract process definition and environment.yml."""

        # Extract Groovy process definition
        groovy_match = re.search(r'```groovy\n(.*?)```', text, re.DOTALL)
        process_code = groovy_match.group(1).strip() if groovy_match else text

        # Extract environment.yml
        yaml_match = re.search(r'```yaml\n(.*?)```', text, re.DOTALL)
        env_yml = yaml_match.group(1).strip() if yaml_match else None

        return ConversionResult(
            process_id=proc_id,
            nextflow_code=process_code,
            environment_yml=env_yml,
            confidence=0.8,  # Gemini default confidence
            model='gemini-2.0-flash-exp'
        )


# ==============================================================================
# Component 3: Process Converter (Orchestrator)
# ==============================================================================

class ProcessConverter:
    """Convert Galaxy processes using both Claude and Gemini."""

    def __init__(self, gemini_client: GeminiClient,
                 doc_provider: DocumentationProvider,
                 claude_converter=None):
        self.gemini = gemini_client
        self.docs = doc_provider
        self.claude_converter = claude_converter

    def convert_all_processes(self, processes: List[Dict]):
        """
        Convert all processes with both LLMs in parallel.

        Returns:
        {
            'process_1': {
                'claude': ConversionResult,
                'gemini': ConversionResult,
                'source_process': {...}
            },
            ...
        }
        """

        print(f"\n🔄 Converting {len(processes)} processes with both LLMs...")
        print("=" * 80)

        # Start both conversions in parallel
        with ThreadPoolExecutor(max_workers=2) as executor:
            # Claude conversion (using existing converter)
            print("🤖 Claude: Starting conversion...")
            claude_future = executor.submit(
                self._convert_with_claude, processes
            )

            # Gemini conversion (parallel for all processes)
            gemini_future = executor.submit(
                self.gemini.convert_processes_parallel,
                processes,
                self.docs
            )

            claude_results = claude_future.result()
            gemini_results = gemini_future.result()

        # Combine results
        combined = {}
        for proc in processes:
            proc_id = proc['id']
            combined[proc_id] = {
                'claude': claude_results.get(proc_id),
                'gemini': gemini_results.get(proc_id),
                'source_process': proc
            }

        print("=" * 80)
        return combined

    def _convert_with_claude(self, processes: List[Dict]):
        """Convert processes with Claude (using existing converter)."""

        results = {}

        if self.claude_converter:
            # Use existing UnifiedToNextflowConverter
            for proc in processes:
                result = self.claude_converter._generate_process_definition(proc)
                env_yml = self.claude_converter._generate_environment_yml(proc)

                results[proc['id']] = ConversionResult(
                    process_id=proc['id'],
                    nextflow_code=result,
                    environment_yml=env_yml,
                    confidence=0.9,  # Claude confidence
                    model='claude-sonnet-4.5'
                )
                print(f"   ✅ {proc['id']}")
        else:
            print("   ⚠️  No Claude converter provided, skipping")

        return results


# ==============================================================================
# PLACEHOLDER: Remaining components defined in next file
# ==============================================================================

# Will continue with:
# - AssemblyAuditor
# - NextflowTester
# - IterativeRefiner
# in dual_llm_converter_system_part2.py
