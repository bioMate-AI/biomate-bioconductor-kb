#!/usr/bin/env python3
"""
Main Execution Script for Dual-LLM Workflow Converter

Usage:
    python3 run_dual_llm_converter.py \\
        --galaxy-workflow path/to/workflow.ga \\
        --output output_dir \\
        --gemini-api-key YOUR_KEY \\
        --max-iterations 3

Author: BioMate Team
Date: 2025-11-20
"""

import sys
import json
import argparse
from pathlib import Path

# Add parent directories to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from galaxy.ai.dual_llm_converter_system import (
    DocumentationProvider,
    GeminiClient,
    ProcessConverter
)

from galaxy.ai.dual_llm_converter_system_part2 import (
    AssemblyAuditor,
    NextflowTester,
    IterativeRefiner
)

# Import existing converters if available
try:
    from galaxy.ai.workflow_converters.nextflow_converter import UnifiedToNextflowConverter
    from galaxy.ai.workflow_converters.galaxy_converter import GalaxyToUnifiedConverter
    CLAUDE_CONVERTER_AVAILABLE = True
except ImportError:
    CLAUDE_CONVERTER_AVAILABLE = False
    print("⚠️  Warning: Existing converters not available, using basic conversion")


def main():
    parser = argparse.ArgumentParser(
        description='Dual-LLM Galaxy to Nextflow Workflow Converter'
    )

    parser.add_argument(
        '--galaxy-workflow',
        required=True,
        type=Path,
        help='Path to Galaxy workflow (.ga file)'
    )

    parser.add_argument(
        '--output',
        required=True,
        type=Path,
        help='Output directory for Nextflow files'
    )

    parser.add_argument(
        '--gemini-api-key',
        default='AIzaSyDoFJyQuwTYsfhoLO4DBL1ME9Ojl7VpFHI',
        help='Gemini API key (default: from plan document)'
    )

    parser.add_argument(
        '--max-iterations',
        type=int,
        default=3,
        help='Maximum refinement iterations (default: 3)'
    )

    parser.add_argument(
        '--test-mode',
        choices=['stub', 'preview', 'real'],
        default='stub',
        help='Nextflow test mode (default: stub)'
    )

    parser.add_argument(
        '--skip-testing',
        action='store_true',
        help='Skip Nextflow testing (just convert)'
    )

    args = parser.parse_args()

    # Validate inputs
    if not args.galaxy_workflow.exists():
        print(f"❌ Error: Galaxy workflow not found: {args.galaxy_workflow}")
        sys.exit(1)

    args.output.mkdir(parents=True, exist_ok=True)

    # Load Galaxy workflow
    print(f"\n📂 Loading Galaxy workflow: {args.galaxy_workflow.name}")
    with open(args.galaxy_workflow) as f:
        galaxy_workflow = json.load(f)

    workflow_name = galaxy_workflow.get('name', 'Unknown')
    step_count = len(galaxy_workflow.get('steps', {}))
    print(f"   Name: {workflow_name}")
    print(f"   Steps: {step_count}")

    # Initialize system
    print(f"\n🔧 Initializing Dual-LLM Converter System...")

    # 1. Documentation Provider
    project_root = Path(__file__).parent.parent.parent.parent.parent
    doc_provider = DocumentationProvider(project_root)

    # 2. Gemini Client
    gemini_client = GeminiClient(args.gemini_api_key)
    print(f"   ✅ Gemini client initialized (model: gemini-2.0-flash-exp)")

    # 3. Claude Converter (if available)
    claude_converter = None
    if CLAUDE_CONVERTER_AVAILABLE:
        try:
            nfcore_base = project_root / "backend" / "nf-core-workflows"
            galaxy_tools = project_root / "backend" / "database" / "shed_tools"

            claude_converter = UnifiedToNextflowConverter(
                nfcore_base_dir=nfcore_base if nfcore_base.exists() else None,
                galaxy_tools_dir=galaxy_tools if galaxy_tools.exists() else None
            )
            print(f"   ✅ Claude converter initialized")
        except Exception as e:
            print(f"   ⚠️  Claude converter failed: {e}")

    # 4. Iterative Refiner
    refiner = IterativeRefiner(
        gemini_client=gemini_client,
        doc_provider=doc_provider,
        claude_converter=claude_converter,
        max_iterations=args.max_iterations
    )
    print(f"   ✅ Iterative refiner initialized (max iterations: {args.max_iterations})")

    # Run conversion
    print(f"\n{'='*80}")
    print(f"🚀 STARTING DUAL-LLM CONVERSION")
    print(f"{'='*80}")

    if args.skip_testing:
        print("\n⚠️  Testing disabled, converting only...")

        # Just do one iteration without testing
        processes = refiner._extract_processes(galaxy_workflow)
        combined = refiner.process_converter.convert_all_processes(processes)
        merged = refiner.auditor.audit_and_merge(combined)
        workflow_files = refiner._build_workflow_files(merged, galaxy_workflow)

        result = {
            'success': True,
            'workflow_files': workflow_files,
            'iterations': 1,
            'history': []
        }

    else:
        # Full iterative refinement
        result = refiner.refine_until_success(galaxy_workflow)

    # Save results
    print(f"\n💾 Saving results to: {args.output}")

    for filepath, content in result['workflow_files'].items():
        output_path = args.output / filepath
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(content)
        print(f"   ✅ {filepath}")

    # Save metadata
    metadata = {
        'source_workflow': str(args.galaxy_workflow),
        'workflow_name': workflow_name,
        'success': result['success'],
        'iterations': result['iterations'],
        'output_directory': str(args.output)
    }

    metadata_path = args.output / 'conversion_metadata.json'
    metadata_path.write_text(json.dumps(metadata, indent=2))
    print(f"   ✅ conversion_metadata.json")

    # Summary
    print(f"\n{'='*80}")
    if result['success']:
        print(f"🎉 SUCCESS!")
        print(f"   Workflow converted successfully in {result['iterations']} iteration(s)")
        print(f"   Output: {args.output}")
    else:
        print(f"⚠️  PARTIAL SUCCESS")
        print(f"   Reached max iterations ({args.max_iterations})")
        print(f"   Some processes may still have errors")
        print(f"   Review: {args.output}")

        if 'remaining_errors' in result:
            print(f"\n   Remaining errors:")
            for proc_id, errors in result['remaining_errors'].items():
                print(f"     - {proc_id}: {len(errors)} errors")

    print(f"{'='*80}")

    # Instructions
    print(f"\n📖 To test the generated workflow:")
    print(f"   cd {args.output}")
    print(f"   nextflow run main.nf -stub-run")
    print(f"\n   Or with conda:")
    print(f"   nextflow run main.nf -profile conda")
    print()

    return 0 if result['success'] else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\n\n⚠️  Interrupted by user")
        sys.exit(130)
    except Exception as e:
        print(f"\n\n❌ Fatal error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
