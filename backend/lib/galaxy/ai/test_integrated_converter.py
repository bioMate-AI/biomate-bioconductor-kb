#!/usr/bin/env python3
"""
Test script for integrated multi-source dependency converter and resource resolver.

This demonstrates the complete Galaxy → Nextflow conversion pipeline with:
1. Multi-source dependency resolution (Conda, Docker, Singularity, Modules)
2. Resource requirement extraction (from nf-core, Galaxy XML, category inference)
3. Complete Nextflow module generation with environment.yml files
4. Resource selectors in nextflow.config

Author: BioMate Team
Date: 2025-11-20
"""

import sys
import json
import logging
from pathlib import Path

# Add backend/lib to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(levelname)s - %(name)s - %(message)s'
)
log = logging.getLogger(__name__)

# Import converters
from galaxy.ai.workflow_converters.galaxy_converter import GalaxyToUnifiedConverter
from galaxy.ai.workflow_converters.nextflow_converter import UnifiedToNextflowConverter

def test_galaxy_to_nextflow_conversion():
    """Test complete Galaxy to Nextflow conversion with multi-source approach."""

    print("=" * 80)
    print("MULTI-SOURCE DEPENDENCY CONVERTER & RESOURCE RESOLVER TEST")
    print("=" * 80)
    print()

    # 1. Load Galaxy workflow
    galaxy_workflow_path = Path("/home/yzhang/biomate/backend/galaxy_workflows_reformatted/quantify_pseudo_alignment.ga")

    if not galaxy_workflow_path.exists():
        print(f"❌ Galaxy workflow not found: {galaxy_workflow_path}")
        return

    print(f"📂 Loading Galaxy workflow: {galaxy_workflow_path.name}")
    with open(galaxy_workflow_path) as f:
        galaxy_workflow = json.load(f)

    print(f"   Name: {galaxy_workflow.get('name', 'Unknown')}")
    print(f"   Steps: {len(galaxy_workflow.get('steps', {}))}")
    print()

    # 2. Convert Galaxy → BUWF
    print("🔄 Converting Galaxy → BioMate Unified Workflow Format...")
    galaxy_converter = GalaxyToUnifiedConverter()
    unified_workflow = galaxy_converter.convert(galaxy_workflow)
    print(f"   ✅ Created unified workflow with {len(unified_workflow.high_level_steps)} high-level steps")
    print()

    # 3. Convert BUWF → Nextflow with multi-source approach
    print("🔄 Converting BUWF → Nextflow with multi-source dependencies...")

    # Initialize converter with paths for enrichment
    nfcore_base = Path("/home/yzhang/biomate/backend/nf-core-workflows")
    galaxy_tools = Path("/home/yzhang/biomate/backend/database/shed_tools")

    nextflow_converter = UnifiedToNextflowConverter(
        nfcore_base_dir=nfcore_base if nfcore_base.exists() else None,
        galaxy_tools_dir=galaxy_tools if galaxy_tools.exists() else None
    )

    try:
        nextflow_files = nextflow_converter.convert(unified_workflow)
        print(f"   ✅ Generated {len(nextflow_files)} Nextflow files")
        print()

        # 4. Analyze generated files
        print("📊 GENERATED FILES:")
        print("-" * 80)
        for filepath, content in nextflow_files.items():
            print(f"   📄 {filepath} ({len(content)} bytes)")
        print()

        # 5. Show main.nf structure
        if "main.nf" in nextflow_files:
            print("📝 MAIN WORKFLOW (main.nf):")
            print("-" * 80)
            lines = nextflow_files["main.nf"].split('\n')
            for i, line in enumerate(lines[:50], 1):  # First 50 lines
                print(f"   {i:3d} | {line}")
            if len(lines) > 50:
                print(f"   ... ({len(lines) - 50} more lines)")
            print()

        # 6. Show config with resource selectors
        if "nextflow.config" in nextflow_files:
            print("⚙️  CONFIGURATION (nextflow.config):")
            print("-" * 80)
            config_lines = nextflow_files["nextflow.config"].split('\n')

            # Show resource selector section
            in_process_section = False
            for i, line in enumerate(config_lines, 1):
                if 'process {' in line:
                    in_process_section = True
                if in_process_section:
                    print(f"   {i:3d} | {line}")
                if in_process_section and line.strip() == '}':
                    break
            print()

        # 7. Show sample process module with multi-source dependencies
        module_files = [f for f in nextflow_files if f.startswith("modules/") and f.endswith("main.nf")]
        if module_files:
            sample_module = module_files[0]
            print(f"🧬 SAMPLE PROCESS MODULE ({sample_module}):")
            print("-" * 80)
            module_content = nextflow_files[sample_module]
            module_lines = module_content.split('\n')

            # Show process definition (focus on directives)
            for i, line in enumerate(module_lines[:30], 1):
                print(f"   {i:3d} | {line}")
            print()

            # Show corresponding environment.yml if exists
            env_file = sample_module.replace("main.nf", "environment.yml")
            if env_file in nextflow_files:
                print(f"📦 CONDA ENVIRONMENT ({env_file}):")
                print("-" * 80)
                print(nextflow_files[env_file])
                print()

        # 8. Summary statistics
        print("📈 CONVERSION SUMMARY:")
        print("-" * 80)

        module_nf_count = len([f for f in nextflow_files if f.endswith("main.nf") and f != "main.nf"])
        env_yml_count = len([f for f in nextflow_files if f.endswith("environment.yml")])

        print(f"   Total files generated: {len(nextflow_files)}")
        print(f"   Process modules (main.nf): {module_nf_count}")
        print(f"   Conda environments (environment.yml): {env_yml_count}")
        print()

        # 9. Verify multi-source features
        print("✅ MULTI-SOURCE FEATURES VERIFICATION:")
        print("-" * 80)

        # Check if any module has conda directive
        has_conda = any("conda" in content for content in nextflow_files.values())
        print(f"   {'✅' if has_conda else '❌'} Conda directives")

        # Check if any module has container directive
        has_container = any("container" in content and "singularity" in content for content in nextflow_files.values())
        print(f"   {'✅' if has_container else '❌'} Container directives (Docker/Singularity)")

        # Check if config has resource labels
        has_labels = "withLabel: process_medium" in nextflow_files.get("nextflow.config", "")
        print(f"   {'✅' if has_labels else '❌'} Resource labels (process_low/medium/high)")

        # Check if environment.yml files were generated
        has_env_yml = env_yml_count > 0
        print(f"   {'✅' if has_env_yml else '❌'} Conda environment.yml files")

        print()
        print("=" * 80)
        print("✅ INTEGRATION TEST COMPLETE!")
        print("=" * 80)

    except Exception as e:
        log.error(f"Conversion failed: {e}", exc_info=True)
        print(f"❌ Conversion failed: {e}")
        return

if __name__ == "__main__":
    test_galaxy_to_nextflow_conversion()
