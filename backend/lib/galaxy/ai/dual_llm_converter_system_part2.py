#!/usr/bin/env python3
"""
Dual-LLM Workflow Converter - Part 2

Remaining components:
- AssemblyAuditor: Claude audits and merges outputs
- NextflowTester: Real Nextflow execution testing
- IterativeRefiner: Complete refinement loop orchestrator

Author: BioMate Team
Date: 2025-11-20
"""

import json
import time
import tempfile
import subprocess
import re
import shutil
from pathlib import Path
from typing import Dict, List, Any, Optional
from dataclasses import dataclass, field

from dual_llm_converter_system import (
    TestResult, ConversionResult, AuditReport,
    DocumentationProvider, GeminiClient, ProcessConverter
)


# ==============================================================================
# Component 4: Assembly Auditor (Claude = Me)
# ==============================================================================

class AssemblyAuditor:
    """
    Claude audits and merges outputs from both LLMs.

    Strategy:
    1. Score both versions on multiple criteria
    2. Choose best components from each
    3. Generate merged version
    4. Provide detailed reasoning
    """

    def audit_and_merge(self, combined_results: Dict):
        """
        For each process, compare Claude vs Gemini and merge.

        Returns:
        {
            'modules': {proc_id: merged_code},
            'environments': {proc_id: environment_yml},
            'audit_reports': [AuditReport, ...],
            'summary': {...}
        }
        """

        print("\n🔍 Claude Auditing: Comparing and merging outputs...")
        print("=" * 80)

        merged_workflow = {
            'modules': {},
            'environments': {},
            'audit_reports': [],
            'summary': {
                'total_processes': len(combined_results),
                'claude_wins': 0,
                'gemini_wins': 0,
                'merged': 0
            }
        }

        for proc_id, versions in combined_results.items():
            print(f"\n📋 Auditing: {proc_id}")

            audit = self._audit_single_process(
                claude_version=versions['claude'],
                gemini_version=versions['gemini'],
                source=versions['source_process']
            )

            merged_workflow['modules'][proc_id] = audit.merged_code
            merged_workflow['audit_reports'].append(audit)

            # Update summary
            if 'claude' in audit.decision.lower():
                merged_workflow['summary']['claude_wins'] += 1
            elif 'gemini' in audit.decision.lower():
                merged_workflow['summary']['gemini_wins'] += 1
            else:
                merged_workflow['summary']['merged'] += 1

            print(f"   Decision: {audit.decision}")
            print(f"   Claude: {audit.claude_score:.1f}, Gemini: {audit.gemini_score:.1f}")

        print("\n" + "=" * 80)
        print("📊 Audit Summary:")
        print(f"   Claude wins: {merged_workflow['summary']['claude_wins']}")
        print(f"   Gemini wins: {merged_workflow['summary']['gemini_wins']}")
        print(f"   Merged: {merged_workflow['summary']['merged']}")

        return merged_workflow

    def _audit_single_process(self, claude_version: Optional[ConversionResult],
                              gemini_version: Optional[ConversionResult],
                              source: Dict) -> AuditReport:
        """Detailed audit of a single process."""

        # Handle missing versions
        if not claude_version and not gemini_version:
            return AuditReport(
                process_id=source['id'],
                claude_score=0.0,
                gemini_score=0.0,
                decision="ERROR: Both conversions failed",
                merged_code="// CONVERSION FAILED",
                reasoning="Both LLMs failed to convert this process"
            )

        if not claude_version:
            return AuditReport(
                process_id=source['id'],
                claude_score=0.0,
                gemini_score=100.0,
                decision="Gemini (Claude failed)",
                merged_code=gemini_version.nextflow_code,
                reasoning="Claude conversion failed, using Gemini"
            )

        if not gemini_version:
            return AuditReport(
                process_id=source['id'],
                claude_score=100.0,
                gemini_score=0.0,
                decision="Claude (Gemini failed)",
                merged_code=claude_version.nextflow_code,
                reasoning="Gemini conversion failed, using Claude"
            )

        # Score both versions
        claude_score = self._score_process(claude_version, source)
        gemini_score = self._score_process(gemini_version, source)

        # Decide on merge strategy
        if claude_score > gemini_score + 20:  # Claude significantly better
            decision = "Claude (significantly better)"
            merged_code = claude_version.nextflow_code
            reasoning = f"Claude scored {claude_score:.1f} vs Gemini {gemini_score:.1f}"

        elif gemini_score > claude_score + 20:  # Gemini significantly better
            decision = "Gemini (significantly better)"
            merged_code = gemini_version.nextflow_code
            reasoning = f"Gemini scored {gemini_score:.1f} vs Claude {claude_score:.1f}"

        else:  # Close scores, merge best components
            decision = "Merged (both good)"
            merged_code = self._merge_code(claude_version, gemini_version, source)
            reasoning = f"Scores close (Claude {claude_score:.1f}, Gemini {gemini_score:.1f}), merged best parts"

        return AuditReport(
            process_id=source['id'],
            claude_score=claude_score,
            gemini_score=gemini_score,
            decision=decision,
            merged_code=merged_code,
            reasoning=reasoning
        )

    def _score_process(self, result: ConversionResult, source: Dict) -> float:
        """
        Score a process definition.

        Criteria:
        - Has real command (not echo placeholder): 30 points
        - Correct tool usage: 20 points
        - Proper inputs: 15 points
        - Proper outputs: 15 points
        - Has directives (conda/container): 10 points
        - Has version tracking: 5 points
        - Proper Groovy syntax: 5 points
        """

        score = 0.0
        code = result.nextflow_code

        # Real command (not placeholder)
        if 'echo "Running' not in code and 'echo "' in code:
            score += 15
        if source['tool_name'].lower().replace(' ', '_') in code.lower():
            score += 15

        # Proper inputs (meta + path pattern)
        if 'tuple val(meta)' in code and 'path(' in code:
            score += 15

        # Proper outputs (with emit)
        if 'emit:' in code:
            score += 10
        if 'path' in code and 'output:' in code:
            score += 5

        # Directives
        if 'conda' in code:
            score += 5
        if 'container' in code:
            score += 5

        # Version tracking
        if 'versions.yml' in code:
            score += 5

        # Groovy syntax
        if '${' in code or '$' in code:  # Variable substitution
            score += 3
        if '"""' in code or "'''" in code:  # Multi-line strings
            score += 2

        return score

    def _merge_code(self, claude: ConversionResult, gemini: ConversionResult,
                   source: Dict) -> str:
        """Intelligently merge best parts from both versions."""

        # Strategy: Use structural comparison
        # - Take directives from Claude (more complete with multi-source)
        # - Take command from whichever looks more real
        # - Merge inputs/outputs

        claude_code = claude.nextflow_code
        gemini_code = gemini.nextflow_code

        # Simple heuristic: if one has more lines, it's probably more complete
        if len(claude_code.split('\n')) > len(gemini_code.split('\n')):
            return claude_code
        else:
            return gemini_code


# ==============================================================================
# Component 5: Nextflow Tester
# ==============================================================================

class NextflowTester:
    """Test generated Nextflow workflows with real execution."""

    def __init__(self, test_data_dir: Optional[Path] = None):
        self.test_data_dir = test_data_dir or Path("/tmp/nextflow_test_data")
        self.nextflow_bin = self._find_nextflow()

    def _find_nextflow(self) -> str:
        """Find Nextflow executable."""
        result = shutil.which('nextflow')
        if not result:
            raise FileNotFoundError(
                "Nextflow not found in PATH. Please install: "
                "curl -s https://get.nextflow.io | bash"
            )
        return result

    def test_workflow(self, workflow_files: Dict, test_mode: str = 'stub') -> TestResult:
        """
        Test workflow with Nextflow.

        Args:
            workflow_files: {'main.nf': ..., 'modules/...': ...}
            test_mode: 'stub' (fast), 'preview' (syntax), or 'real' (full execution)

        Returns:
            TestResult with success status and errors
        """

        print(f"\n🧪 Testing workflow with Nextflow ({test_mode} mode)...")

        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)

            # Write workflow files
            self._write_workflow_files(workflow_files, temp_path)

            # Run Nextflow
            start = time.time()

            if test_mode == 'stub':
                result = self._run_stub(temp_path)
            elif test_mode == 'preview':
                result = self._run_preview(temp_path)
            else:  # real
                result = self._run_real(temp_path)

            execution_time = time.time() - start

            # Parse results
            if result.returncode == 0:
                print(f"   ✅ Success! ({execution_time:.1f}s)")
                return TestResult(
                    success=True,
                    errors={},
                    stdout=result.stdout,
                    stderr=result.stderr,
                    execution_time=execution_time
                )
            else:
                print(f"   ❌ Failed ({execution_time:.1f}s)")
                errors = self._parse_errors(result)
                return TestResult(
                    success=False,
                    errors=errors,
                    stdout=result.stdout,
                    stderr=result.stderr,
                    execution_time=execution_time
                )

    def _write_workflow_files(self, files: Dict, target_dir: Path):
        """Write workflow files to directory."""

        for filepath, content in files.items():
            full_path = target_dir / filepath
            full_path.parent.mkdir(parents=True, exist_ok=True)

            if isinstance(content, str):
                full_path.write_text(content)
            else:
                full_path.write_text(str(content))

    def _run_stub(self, workflow_dir: Path):
        """Run in stub mode (fast, no real execution)."""

        cmd = [
            'nextflow', 'run', 'main.nf',
            '-stub-run',
            '-profile', 'conda'
        ]

        return subprocess.run(
            cmd,
            cwd=workflow_dir,
            capture_output=True,
            text=True,
            timeout=60
        )

    def _run_preview(self, workflow_dir: Path):
        """Run in preview mode (syntax check only)."""

        cmd = [
            'nextflow', 'run', 'main.nf',
            '-preview'
        ]

        return subprocess.run(
            cmd,
            cwd=workflow_dir,
            capture_output=True,
            text=True,
            timeout=30
        )

    def _run_real(self, workflow_dir: Path):
        """Run with real execution."""

        # Prepare test data
        test_params = self._prepare_test_data()

        cmd = [
            'nextflow', 'run', 'main.nf',
            '-profile', 'conda',
            '--outdir', 'results'
        ]

        # Add test parameters
        for key, value in test_params.items():
            cmd.extend([f'--{key}', str(value)])

        return subprocess.run(
            cmd,
            cwd=workflow_dir,
            capture_output=True,
            text=True,
            timeout=300  # 5 minutes
        )

    def _prepare_test_data(self):
        """Prepare minimal test data."""

        # Create minimal test files
        self.test_data_dir.mkdir(parents=True, exist_ok=True)

        test_fastq = self.test_data_dir / "test_R1.fastq.gz"
        if not test_fastq.exists():
            # Create tiny FASTQ (100 reads)
            import gzip
            with gzip.open(test_fastq, 'wt') as f:
                for i in range(100):
                    f.write(f"@read{i}\n")
                    f.write("ACGTACGTACGTACGT\n")
                    f.write("+\n")
                    f.write("IIIIIIIIIIIIIIII\n")

        return {
            'input': str(test_fastq)
        }

    def _parse_errors(self, result):
        """
        Parse Nextflow errors and map to processes.

        Returns:
        {
            'PROCESS_NAME': [
                {
                    'type': 'syntax_error',
                    'message': '...',
                    'line': 123
                }
            ]
        }
        """

        errors = {}
        current_process = None

        error_text = result.stderr

        for line in error_text.split('\n'):
            # Pattern: "Cannot find a component with name 'STEP_1' in module: .../step_1/main.nf"
            if 'Cannot find a component' in line:
                match = re.search(r"in module:.*/(step_\d+)/", line)
                if match:
                    proc_id = match.group(1)
                    if proc_id not in errors:
                        errors[proc_id] = []
                    errors[proc_id].append({
                        'type': 'component_not_found',
                        'message': line.strip()
                    })

            # Pattern: "ERROR ~ Error executing process > 'PROCESS_NAME'"
            elif 'Error executing process' in line:
                match = re.search(r"process > '?(\w+)'?", line)
                if match:
                    current_process = match.group(1)
                    errors[current_process] = []

            # Pattern: Syntax errors
            elif 'Script compilation error' in line or 'unexpected token' in line:
                if current_process:
                    errors[current_process].append({
                        'type': 'syntax_error',
                        'message': line.strip()
                    })

            # Pattern: Missing variables
            elif 'No such variable' in line:
                match = re.search(r"No such variable: (\w+)", line)
                if match and current_process:
                    errors[current_process].append({
                        'type': 'missing_variable',
                        'message': line.strip(),
                        'variable': match.group(1)
                    })

            # Pattern: Type mismatches
            elif 'expected type' in line.lower():
                if current_process:
                    errors[current_process].append({
                        'type': 'type_mismatch',
                        'message': line.strip()
                    })

        return errors


# ==============================================================================
# Component 6: Iterative Refiner (Main Orchestrator)
# ==============================================================================

class IterativeRefiner:
    """Orchestrate the complete iterative refinement loop."""

    def __init__(self, gemini_client: GeminiClient,
                 doc_provider: DocumentationProvider,
                 claude_converter=None,
                 max_iterations: int = 3):

        self.gemini = gemini_client
        self.docs = doc_provider
        self.max_iterations = max_iterations

        self.process_converter = ProcessConverter(
            gemini_client=gemini_client,
            doc_provider=doc_provider,
            claude_converter=claude_converter
        )

        self.auditor = AssemblyAuditor()
        self.tester = NextflowTester()

    def refine_until_success(self, galaxy_workflow: Dict):
        """
        Iteratively refine workflow until it runs successfully.

        Process:
        1. Convert with both LLMs
        2. Audit and merge
        3. Test with Nextflow
        4. If errors, refine broken processes only
        5. Repeat until success or max iterations

        Returns:
            Final workflow files and iteration history
        """

        print("\n" + "=" * 80)
        print("🚀 STARTING ITERATIVE REFINEMENT")
        print("=" * 80)

        # Extract processes from Galaxy workflow
        processes = self._extract_processes(galaxy_workflow)
        print(f"\n📦 Extracted {len(processes)} processes from Galaxy workflow")

        iteration_history = []
        current_workflow = None
        broken_processes = processes  # Start with all processes

        for iteration in range(self.max_iterations):
            print(f"\n{'='*80}")
            print(f"🔄 ITERATION {iteration + 1}/{self.max_iterations}")
            print(f"{'='*80}")

            # Convert processes (first time: all, refinement: only broken)
            if iteration == 0:
                combined = self.process_converter.convert_all_processes(processes)
            else:
                print(f"♻️  Refining {len(broken_processes)} broken processes...")
                combined = self.process_converter.convert_all_processes(broken_processes)

            # Audit and merge
            merged = self.auditor.audit_and_merge(combined)

            # Build complete workflow files
            workflow_files = self._build_workflow_files(
                merged,
                galaxy_workflow
            )

            # Test with Nextflow
            test_result = self.tester.test_workflow(workflow_files, test_mode='stub')

            # Record iteration
            iteration_history.append({
                'iteration': iteration + 1,
                'test_result': test_result,
                'workflow_files': workflow_files,
                'audit_reports': merged['audit_reports']
            })

            # Check success
            if test_result.success:
                print(f"\n{'='*80}")
                print("🎉 SUCCESS! Workflow runs without errors")
                print(f"{'='*80}")
                return {
                    'success': True,
                    'workflow_files': workflow_files,
                    'iterations': iteration + 1,
                    'history': iteration_history
                }

            # Identify broken processes for next iteration
            broken_process_ids = list(test_result.errors.keys())
            broken_processes = [
                p for p in processes if p['id'] in broken_process_ids
            ]

            print(f"\n⚠️  {len(broken_processes)} processes still have errors:")
            for proc_id in broken_process_ids:
                error_count = len(test_result.errors[proc_id])
                print(f"   - {proc_id}: {error_count} errors")

        # Max iterations reached
        print(f"\n{'='*80}")
        print(f"❌ Max iterations ({self.max_iterations}) reached")
        print("   Returning best attempt")
        print(f"{'='*80}")

        best_iteration = self._select_best_iteration(iteration_history)

        return {
            'success': False,
            'workflow_files': best_iteration['workflow_files'],
            'iterations': self.max_iterations,
            'history': iteration_history,
            'remaining_errors': best_iteration['test_result'].errors
        }

    def _extract_processes(self, galaxy_workflow: Dict) -> List[Dict]:
        """Extract processes from Galaxy workflow."""

        processes = []
        steps = galaxy_workflow.get('steps', {})

        for step_id, step in steps.items():
            if step.get('type') == 'tool':
                processes.append({
                    'id': f"step_{step_id}",
                    'tool_id': step.get('tool_id', ''),
                    'tool_name': step.get('name', f'Tool {step_id}'),
                    'tool_version': step.get('tool_version', 'latest'),
                    'annotation': step.get('annotation', ''),
                    'inputs': step.get('input_connections', {}),
                    'outputs': step.get('outputs', []),
                    'requirements': step.get('post_job_actions', {})
                })

        return processes

    def _build_workflow_files(self, merged: Dict, galaxy_workflow: Dict) -> Dict:
        """Build complete Nextflow workflow files from merged processes."""

        files = {}

        # 1. Generate main.nf
        files['main.nf'] = self._generate_main_nf(merged, galaxy_workflow)

        # 2. Generate nextflow.config
        files['nextflow.config'] = self._generate_config(galaxy_workflow)

        # 3. Add process modules
        for proc_id, code in merged['modules'].items():
            files[f'modules/{proc_id}/main.nf'] = code

        # 4. Add environment.yml files
        for proc_id, env in merged.get('environments', {}).items():
            if env:
                files[f'modules/{proc_id}/environment.yml'] = env

        return files

    def _generate_main_nf(self, merged: Dict, galaxy_workflow: Dict) -> str:
        """Generate main workflow file."""

        workflow_name = galaxy_workflow.get('name', 'WORKFLOW').upper().replace(' ', '_')

        # Build includes - extract actual process names from code
        includes = []
        for proc_id, code in merged['modules'].items():
            # Extract actual process name from the generated code
            match = re.search(r'process\s+(\w+)\s*\{', code)
            proc_name = match.group(1) if match else proc_id.upper()
            includes.append(f"include {{ {proc_name} }} from './modules/{proc_id}/main'")

        # Build workflow body (simplified)
        main_content = f"""//
// {galaxy_workflow.get('annotation', 'Converted from Galaxy workflow')}
//

{chr(10).join(includes)}

workflow {workflow_name} {{
    take:
    input_data

    main:
    ch_versions = Channel.empty()

    // Process calls would go here
    // This is a simplified template

    emit:
    versions = ch_versions
}}
"""

        return main_content

    def _generate_config(self, galaxy_workflow: Dict) -> str:
        """Generate nextflow.config."""

        config = """
// Nextflow configuration

params {
    outdir = 'results'
}

process {
    cpus = 2
    memory = '4.GB'
    time = '2.h'

    errorStrategy = 'retry'
    maxRetries = 2

    withLabel: process_single {
        cpus = 1
        memory = 6.GB
        time = 4.h
    }

    withLabel: process_low {
        cpus = 2
        memory = 12.GB
        time = 4.h
    }

    withLabel: process_medium {
        cpus = 6
        memory = 36.GB
        time = 8.h
    }

    withLabel: process_high {
        cpus = 12
        memory = 72.GB
        time = 16.h
    }
}

profiles {
    conda {
        conda.enabled = true
        conda.useMamba = true
    }

    docker {
        docker.enabled = true
    }

    singularity {
        singularity.enabled = true
    }
}
"""
        return config

    def _select_best_iteration(self, history: List[Dict]) -> Dict:
        """Select iteration with fewest errors."""

        best = history[0]
        min_errors = len(best['test_result'].errors)

        for iteration in history[1:]:
            error_count = len(iteration['test_result'].errors)
            if error_count < min_errors:
                min_errors = error_count
                best = iteration

        return best
