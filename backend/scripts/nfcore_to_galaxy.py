#!/usr/bin/env python3
"""
nf-core to Galaxy Tool Converter

Automatically converts nf-core Nextflow modules to Galaxy tool XML wrappers.
Handles conda dependencies and Docker/Singularity containers.
"""

import os
import re
import yaml
import json
from pathlib import Path
from typing import Dict, List, Optional, Tuple
import xml.etree.ElementTree as ET
from xml.dom import minidom


class NFCoreToGalaxyConverter:
    def __init__(self, nfcore_modules_dir: str, output_dir: str):
        """
        Initialize converter.

        Args:
            nfcore_modules_dir: Path to nf-core/modules repository
            output_dir: Where to write Galaxy tool XMLs
        """
        self.nfcore_dir = Path(nfcore_modules_dir)
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)

        # Modules already in Galaxy (from previous analysis)
        self.in_galaxy = {
            'trimmomatic', 'fastqc', 'iqtree', 'mafft', 'cutadapt', 'multiqc',
            'spades', 'trinity', 'vcftools', 'trimgalore', 'megahit', 'sortmerna',
            'quast', 'fastme', 'medaka', 'gffread', 'freebayes', 'fastp', 'prodigal'
            # ... add all 40 from biomni_galaxy_comparison.json
        }

    def parse_main_nf(self, main_nf_path: Path) -> Dict:
        """Parse Nextflow main.nf file to extract process information."""
        with open(main_nf_path, 'r') as f:
            content = f.read()

        # Extract process name
        process_match = re.search(r'process\s+(\w+)\s*{', content)
        process_name = process_match.group(1) if process_match else "UNKNOWN"

        # Extract container info
        container_match = re.search(
            r'container\s+["\']([^"\']+)["\']',
            content,
            re.MULTILINE
        )
        container = container_match.group(1) if container_match else None

        # Extract command/script section
        script_match = re.search(
            r'script:\s*\n(.*?)"""(.*?)"""',
            content,
            re.DOTALL
        )
        command_template = script_match.group(2).strip() if script_match else ""

        # Extract inputs
        input_match = re.search(
            r'input:\s*\n(.*?)(?=output:|when:|script:)',
            content,
            re.DOTALL
        )
        inputs_raw = input_match.group(1).strip() if input_match else ""

        # Extract outputs
        output_match = re.search(
            r'output:\s*\n(.*?)(?=when:|script:)',
            content,
            re.DOTALL
        )
        outputs_raw = output_match.group(1).strip() if output_match else ""

        return {
            'process_name': process_name,
            'container': container,
            'command': command_template,
            'inputs_raw': inputs_raw,
            'outputs_raw': outputs_raw
        }

    def parse_environment_yml(self, env_yml_path: Path) -> List[str]:
        """Parse conda environment.yml to extract dependencies."""
        if not env_yml_path.exists():
            return []

        with open(env_yml_path, 'r') as f:
            env_data = yaml.safe_load(f)

        dependencies = []
        for dep in env_data.get('dependencies', []):
            if isinstance(dep, str):
                # Format: "bioconda::fastqc=0.12.1" or "fastqc=0.12.1"
                dep_parts = dep.split('::')
                dep_spec = dep_parts[-1]  # Get the package spec
                dependencies.append(dep_spec)

        return dependencies

    def parse_meta_yml(self, meta_yml_path: Path) -> Dict:
        """Parse meta.yml to extract tool metadata."""
        if not meta_yml_path.exists():
            return {}

        with open(meta_yml_path, 'r') as f:
            meta_data = yaml.safe_load(f)

        return {
            'name': meta_data.get('name', ''),
            'description': meta_data.get('description', ''),
            'keywords': meta_data.get('keywords', []),
            'tools': meta_data.get('tools', {}),
            'input': meta_data.get('input', []),
            'output': meta_data.get('output', {})
        }

    def parse_nfcore_inputs(self, inputs_raw: str, meta_data: Dict) -> List[Dict]:
        """Convert Nextflow inputs to Galaxy param definitions."""
        galaxy_inputs = []

        # Parse tuple val(meta), path(reads) style inputs
        for line in inputs_raw.split('\n'):
            line = line.strip()
            if not line:
                continue

            # Match: tuple val(meta), path(reads)
            if 'path(' in line:
                path_match = re.search(r'path\((\w+)\)', line)
                if path_match:
                    param_name = path_match.group(1)

                    # Determine format from meta.yml
                    format_type = "data"
                    label = param_name.replace('_', ' ').title()

                    # Check if it's reads (FASTQ)
                    if 'read' in param_name.lower() or 'fastq' in param_name.lower():
                        format_type = "fastq,fastqsanger,fastqsanger.gz"
                        label = "Input reads"

                    galaxy_inputs.append({
                        'type': 'data',
                        'name': param_name,
                        'label': label,
                        'format': format_type
                    })

            # Match: val(string_param)
            elif 'val(' in line and 'meta' not in line:
                val_match = re.search(r'val\((\w+)\)', line)
                if val_match:
                    param_name = val_match.group(1)
                    galaxy_inputs.append({
                        'type': 'text',
                        'name': param_name,
                        'label': param_name.replace('_', ' ').title(),
                        'value': ''
                    })

        return galaxy_inputs

    def parse_nfcore_outputs(self, outputs_raw: str, meta_data: Dict) -> List[Dict]:
        """Convert Nextflow outputs to Galaxy output definitions."""
        galaxy_outputs = []

        for line in outputs_raw.split('\n'):
            line = line.strip()
            if not line or line.startswith('//'):
                continue

            # Match: tuple val(meta), path("*.html"), emit: html
            # Match: path "versions.yml", emit: versions
            emit_match = re.search(r'emit:\s*(\w+)', line)
            path_match = re.search(r'path[(\s]+["\']([^"\']+)["\']', line)

            if emit_match and path_match:
                emit_name = emit_match.group(1)
                pattern = path_match.group(1)

                # Determine format from pattern
                format_type = "data"
                if pattern.endswith('.html'):
                    format_type = "html"
                elif pattern.endswith('.zip'):
                    format_type = "zip"
                elif pattern.endswith('.txt') or pattern.endswith('.log'):
                    format_type = "txt"
                elif 'yml' in pattern or 'yaml' in pattern:
                    format_type = "yaml"
                elif pattern.endswith('.bam'):
                    format_type = "bam"
                elif pattern.endswith('.vcf'):
                    format_type = "vcf"

                galaxy_outputs.append({
                    'name': emit_name,
                    'format': format_type,
                    'from_work_dir': pattern,
                    'label': emit_name.replace('_', ' ').title()
                })

        return galaxy_outputs

    def generate_galaxy_xml(self, module_name: str, module_data: Dict) -> str:
        """Generate Galaxy tool XML from parsed nf-core module data."""

        # Create root tool element
        tool = ET.Element('tool', {
            'id': f"nfcore_{module_name}",
            'name': f"nf-core {module_name}",
            'version': "1.0.0",  # Will be updated from conda package version
            'profile': "20.01"
        })

        # Description
        description = ET.SubElement(tool, 'description')
        description.text = module_data.get('meta', {}).get('description',
                                                            f"Run {module_name} from nf-core")

        # Requirements
        requirements = ET.SubElement(tool, 'requirements')

        # Add conda requirements
        for dep in module_data.get('conda_deps', []):
            dep_name = dep.split('=')[0].split('::')[-1]
            dep_version = dep.split('=')[1] if '=' in dep else ''
            req = ET.SubElement(requirements, 'requirement', {'type': 'package'})
            if dep_version:
                req.set('version', dep_version)
            req.text = dep_name

        # Add container if available
        if module_data.get('container'):
            container = ET.SubElement(requirements, 'container', {
                'type': 'docker'
            })
            container.text = module_data['container']

        # Command
        command = ET.SubElement(tool, 'command', {'detect_errors': 'exit_code'})
        command.text = f"<![CDATA[\n{module_data.get('command', '')}\n]]>"

        # Inputs
        inputs = ET.SubElement(tool, 'inputs')
        for inp in module_data.get('inputs', []):
            if inp['type'] == 'data':
                param = ET.SubElement(inputs, 'param', {
                    'type': 'data',
                    'name': inp['name'],
                    'format': inp['format'],
                    'label': inp['label']
                })
            elif inp['type'] == 'text':
                param = ET.SubElement(inputs, 'param', {
                    'type': 'text',
                    'name': inp['name'],
                    'label': inp['label'],
                    'value': inp.get('value', '')
                })

        # Outputs
        outputs = ET.SubElement(tool, 'outputs')
        for out in module_data.get('outputs', []):
            data = ET.SubElement(outputs, 'data', {
                'name': out['name'],
                'format': out['format'],
                'label': out['label']
            })
            if out.get('from_work_dir'):
                data.set('from_work_dir', out['from_work_dir'])

        # Help
        help_elem = ET.SubElement(tool, 'help')
        help_text = f"""
**What it does**

{module_data.get('meta', {}).get('description', f'Runs {module_name} analysis')}

**nf-core Module**

This tool is automatically generated from nf-core modules repository.

Module: {module_name}
Container: {module_data.get('container', 'N/A')}

**More Information**

For more information about this tool, visit:
https://github.com/nf-core/modules/tree/master/modules/nf-core/{module_name}
        """
        help_elem.text = f"<![CDATA[\n{help_text.strip()}\n]]>"

        # Pretty print XML
        xml_str = ET.tostring(tool, encoding='unicode')
        dom = minidom.parseString(xml_str)
        return dom.toprettyxml(indent="  ")

    def convert_module(self, module_path: Path) -> Optional[Tuple[str, str]]:
        """
        Convert a single nf-core module to Galaxy XML.

        Returns:
            Tuple of (module_name, xml_content) or None if should skip
        """
        module_name = module_path.name

        # Skip if already in Galaxy
        if module_name.lower() in self.in_galaxy:
            print(f"⊗ Skipping {module_name} (already in Galaxy)")
            return None

        # Parse module files
        main_nf = module_path / "main.nf"
        env_yml = module_path / "environment.yml"
        meta_yml = module_path / "meta.yml"

        if not main_nf.exists():
            print(f"✗ Skipping {module_name} (no main.nf)")
            return None

        print(f"⊕ Converting {module_name}...")

        # Extract data from all files
        nf_data = self.parse_main_nf(main_nf)
        conda_deps = self.parse_environment_yml(env_yml)
        meta_data = self.parse_meta_yml(meta_yml)

        # Parse inputs/outputs
        inputs = self.parse_nfcore_inputs(nf_data['inputs_raw'], meta_data)
        outputs = self.parse_nfcore_outputs(nf_data['outputs_raw'], meta_data)

        # Compile module data
        module_data = {
            'meta': meta_data,
            'conda_deps': conda_deps,
            'container': nf_data['container'],
            'command': nf_data['command'],
            'inputs': inputs,
            'outputs': outputs
        }

        # Generate Galaxy XML
        xml_content = self.generate_galaxy_xml(module_name, module_data)

        return (module_name, xml_content)

    def convert_all_modules(self) -> Dict[str, str]:
        """Convert all nf-core modules to Galaxy tools."""
        modules_dir = self.nfcore_dir / "modules" / "nf-core"

        if not modules_dir.exists():
            raise FileNotFoundError(f"Modules directory not found: {modules_dir}")

        converted = {}
        skipped = []
        errors = []

        print("="*80)
        print("nf-core to Galaxy Converter")
        print("="*80)
        print(f"Source: {modules_dir}")
        print(f"Output: {self.output_dir}")
        print("")

        for module_path in sorted(modules_dir.iterdir()):
            if not module_path.is_dir():
                continue

            try:
                result = self.convert_module(module_path)
                if result:
                    module_name, xml_content = result

                    # Save XML file
                    output_file = self.output_dir / f"{module_name}.xml"
                    with open(output_file, 'w') as f:
                        f.write(xml_content)

                    converted[module_name] = str(output_file)
                    print(f"  ✓ Saved to {output_file.name}")
                else:
                    skipped.append(module_path.name)

            except Exception as e:
                errors.append((module_path.name, str(e)))
                print(f"  ✗ Error: {e}")

        # Summary
        print("")
        print("="*80)
        print("CONVERSION COMPLETE")
        print("="*80)
        print(f"✓ Converted: {len(converted)} modules")
        print(f"⊗ Skipped: {len(skipped)} modules (already in Galaxy)")
        print(f"✗ Errors: {len(errors)} modules")

        if errors:
            print("\nErrors:")
            for name, error in errors[:10]:
                print(f"  - {name}: {error}")

        # Save summary
        summary = {
            'converted': list(converted.keys()),
            'skipped': skipped,
            'errors': dict(errors),
            'total_converted': len(converted),
            'output_dir': str(self.output_dir)
        }

        summary_file = self.output_dir / "conversion_summary.json"
        with open(summary_file, 'w') as f:
            json.dump(summary, f, indent=2)

        print(f"\n📄 Summary saved to: {summary_file}")

        return converted


def main():
    """Main entry point."""
    import argparse

    parser = argparse.ArgumentParser(
        description="Convert nf-core modules to Galaxy tools"
    )
    parser.add_argument(
        '--nfcore-dir',
        default='/Users/jingqiwang/nf-core-modules',
        help='Path to nf-core/modules repository'
    )
    parser.add_argument(
        '--output-dir',
        default='/Users/jingqiwang/biomate/backend/tools/nfcore_generated',
        help='Output directory for Galaxy tools'
    )

    args = parser.parse_args()

    converter = NFCoreToGalaxyConverter(
        nfcore_modules_dir=args.nfcore_dir,
        output_dir=args.output_dir
    )

    converter.convert_all_modules()


if __name__ == '__main__':
    main()
