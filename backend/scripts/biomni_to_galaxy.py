#!/usr/bin/env python3
"""
BioMni to Galaxy Tool Converter

Automatically converts BioMni Python functions to Galaxy tool XML wrappers.
Extracts dependencies from import statements and function signatures.
"""

import os
import re
import ast
import json
from pathlib import Path
from typing import Dict, List, Optional, Tuple, Set
import xml.etree.ElementTree as ET
from xml.dom import minidom
import inspect


class BioMniToGalaxyConverter:
    def __init__(self, biomni_dir: str, output_dir: str):
        """
        Initialize converter.

        Args:
            biomni_dir: Path to Biomni repository
            output_dir: Where to write Galaxy tool XMLs
        """
        self.biomni_dir = Path(biomni_dir)
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)

        # Tools already in Galaxy (from CORRECTED_BIOMNI_GALAXY_OVERLAP)
        self.in_galaxy = {
            'blast', 'blast+', 'blastn', 'blastp', 'matrix', 'bedtools', 'seurat',
            'bwa', 'dada2', 'deseq2', 'community', 'rdkit', 'scanpy', 'cooler',
            'bowtie2', 'wgcna', 'biopython', 'clusterprofile', 'clusterprofiler',
            'salmon', 'samtools', 'diamond', 'muscle', 'mafft', 'trimmomatic',
            'fastqc', 'fasttree', 'homer', 'iqtree', 'limma', 'edger', 'macs',
            'macs2', 'viennarna', 'xcms'
        }

        # Map Python imports to conda packages
        self.import_to_conda = {
            # Genomics
            'pysam': 'pysam',
            'pyfaidx': 'pyfaidx',
            'pyranges': 'pyranges',
            'pybigwig': 'pybigwig',
            'pybedtools': 'pybedtools',
            'cyvcf2': 'cyvcf2',
            # Single-cell
            'cellpose': 'cellpose',
            'scvelo': 'scvelo',
            'scvi': 'scvi-tools',
            'scanpy': 'scanpy',
            # Analysis
            'gget': 'gget',
            'gseapy': 'gseapy',
            'scikit-bio': 'scikit-bio',
            # Metabolomics
            'cobra': 'cobra',
            'pymzml': 'pymzml',
            # ML
            'umap': 'umap-learn',
            'harmony': 'harmony-pytorch',
            'faiss': 'faiss-cpu',
            # Common
            'numpy': 'numpy',
            'pandas': 'pandas',
            'scipy': 'scipy',
            'matplotlib': 'matplotlib',
            'sklearn': 'scikit-learn',
            'Bio': 'biopython'
        }

    def extract_imports_from_file(self, file_path: Path) -> Set[str]:
        """Extract all import statements from a Python file."""
        imports = set()

        with open(file_path, 'r') as f:
            try:
                tree = ast.parse(f.read())

                for node in ast.walk(tree):
                    if isinstance(node, ast.Import):
                        for alias in node.names:
                            imports.add(alias.name.split('.')[0])
                    elif isinstance(node, ast.ImportFrom):
                        if node.module:
                            imports.add(node.module.split('.')[0])

            except SyntaxError as e:
                print(f"  ⚠ Warning: Could not parse {file_path.name}: {e}")

        return imports

    def parse_function(self, func_node: ast.FunctionDef, source_code: str) -> Dict:
        """Extract function metadata from AST node."""
        # Get function signature
        args = []
        for arg in func_node.args.args:
            args.append({
                'name': arg.arg,
                'annotation': ast.unparse(arg.annotation) if arg.annotation else None
            })

        # Get docstring
        docstring = ast.get_docstring(func_node) or ""

        # Try to extract parameters from docstring
        param_descriptions = {}
        if docstring:
            # Parse Parameters section
            param_section = re.search(
                r'Parameters?\s*[-:]*\s*\n(.*?)(?:\n\s*\n|\n[A-Z]|\Z)',
                docstring,
                re.DOTALL | re.IGNORECASE
            )
            if param_section:
                param_text = param_section.group(1)
                # Match: - param_name (type): description
                # or: param_name: description
                for match in re.finditer(
                    r'[-\s]*(\w+)\s*(?:\(([^)]+)\))?\s*:([^\n]+)',
                    param_text
                ):
                    param_name = match.group(1)
                    param_type = match.group(2)
                    param_desc = match.group(3).strip()
                    param_descriptions[param_name] = {
                        'type': param_type,
                        'description': param_desc
                    }

        return {
            'name': func_node.name,
            'args': args,
            'docstring': docstring,
            'param_descriptions': param_descriptions
        }

    def get_conda_requirements(self, imports: Set[str]) -> List[str]:
        """Convert Python imports to conda package names."""
        conda_pkgs = []

        for imp in imports:
            if imp in self.import_to_conda:
                conda_pkg = self.import_to_conda[imp]
                if conda_pkg not in conda_pkgs:
                    conda_pkgs.append(conda_pkg)

        return sorted(conda_pkgs)

    def infer_param_type(self, param_name: str, param_info: Dict) -> str:
        """Infer Galaxy parameter type from Python param."""
        name_lower = param_name.lower()
        param_type_str = param_info.get('type', '').lower() if param_info else ''

        # File inputs
        if any(x in name_lower for x in ['file', 'path', 'filename', 'adata']):
            if 'h5ad' in name_lower or 'anndata' in param_type_str:
                return 'data_h5ad'
            elif 'csv' in name_lower or 'tsv' in name_lower:
                return 'data_tabular'
            return 'data'

        # Directory inputs
        if 'dir' in name_lower or 'directory' in name_lower:
            return 'text'  # Galaxy doesn't have directory type, use text for path

        # List/array inputs
        if 'list' in param_type_str or 'array' in param_type_str:
            return 'text'  # Will need to parse in wrapper

        # Boolean
        if 'bool' in param_type_str or param_name in ['use_raw', 'copy', 'verbose']:
            return 'boolean'

        # Integer
        if 'int' in param_type_str or param_name in ['n_pcs', 'n_genes', 'resolution']:
            return 'integer'

        # Float
        if 'float' in param_type_str:
            return 'float'

        # Default to text
        return 'text'

    def generate_galaxy_xml_for_function(
        self,
        func_data: Dict,
        tool_name: str,
        conda_reqs: List[str],
        source_module: str
    ) -> str:
        """Generate Galaxy tool XML for a BioMni function."""

        # Create root tool element
        tool = ET.Element('tool', {
            'id': f"biomni_{func_data['name']}",
            'name': f"BioMni: {func_data['name'].replace('_', ' ').title()}",
            'version': "1.0.0",
            'profile': "20.01"
        })

        # Description from first line of docstring
        description = ET.SubElement(tool, 'description')
        first_line = func_data['docstring'].split('\n')[0] if func_data['docstring'] else f"{func_data['name']}"
        description.text = first_line[:200]  # Limit length

        # Requirements
        requirements = ET.SubElement(tool, 'requirements')
        requirements.append(ET.Comment(' BioMni Python function wrapper '))

        # Add conda requirements
        for pkg in conda_reqs:
            req = ET.SubElement(requirements, 'requirement', {'type': 'package'})
            req.text = pkg

        # Add biomni itself
        req = ET.SubElement(requirements, 'requirement', {'type': 'package'})
        req.text = 'biomni'

        # Command - Python wrapper script
        command = ET.SubElement(tool, 'command', {'detect_errors': 'exit_code'})

        # Build command
        cmd_parts = ["python '$__tool_directory__/wrapper.py'"]
        for arg in func_data['args']:
            arg_name = arg['name']
            if arg_name in ['data_lake_path', 'config']:
                continue  # Skip internal args
            cmd_parts.append(f"--{arg_name} '{arg_name}'")

        command.text = f"<![CDATA[\n{' '.join(cmd_parts)}\n]]>"

        # Inputs
        inputs = ET.SubElement(tool, 'inputs')
        for arg in func_data['args']:
            arg_name = arg['name']

            # Skip internal parameters
            if arg_name in ['data_lake_path', 'config', 'llm']:
                continue

            param_info = func_data['param_descriptions'].get(arg_name, {})
            param_type = self.infer_param_type(arg_name, param_info)
            param_label = arg_name.replace('_', ' ').title()
            param_help = param_info.get('description', '') if param_info else ''

            if param_type.startswith('data'):
                param = ET.SubElement(inputs, 'param', {
                    'type': 'data',
                    'name': arg_name,
                    'label': param_label,
                    'help': param_help
                })
                if param_type == 'data_h5ad':
                    param.set('format', 'h5ad')
                elif param_type == 'data_tabular':
                    param.set('format', 'tabular,csv,tsv')

            elif param_type == 'boolean':
                param = ET.SubElement(inputs, 'param', {
                    'type': 'boolean',
                    'name': arg_name,
                    'label': param_label,
                    'help': param_help,
                    'checked': 'false'
                })

            elif param_type == 'integer':
                param = ET.SubElement(inputs, 'param', {
                    'type': 'integer',
                    'name': arg_name,
                    'label': param_label,
                    'help': param_help,
                    'value': '10'
                })

            elif param_type == 'float':
                param = ET.SubElement(inputs, 'param', {
                    'type': 'float',
                    'name': arg_name,
                    'label': param_label,
                    'help': param_help,
                    'value': '0.0'
                })

            else:  # text
                param = ET.SubElement(inputs, 'param', {
                    'type': 'text',
                    'name': arg_name,
                    'label': param_label,
                    'help': param_help,
                    'value': ''
                })

        # Outputs - Infer from function (most return data files)
        outputs = ET.SubElement(tool, 'outputs')
        data = ET.SubElement(outputs, 'data', {
            'name': 'output',
            'format': 'auto',
            'label': f"{func_data['name']} output"
        })

        # Help
        help_elem = ET.SubElement(tool, 'help')
        help_text = f"""
**What it does**

{func_data['docstring']}

**Source**

This tool wraps the BioMni function: `{func_data['name']}`

Module: {source_module}

**BioMni**

BioMni is a Python library for biological data analysis.
For more information: https://github.com/batmen-lab/BioMni

**Requirements**

This tool requires the following conda packages:
{', '.join(conda_reqs)}
        """
        help_elem.text = f"<![CDATA[\n{help_text.strip()}\n]]>"

        # Pretty print XML
        xml_str = ET.tostring(tool, encoding='unicode')
        dom = minidom.parseString(xml_str)
        return dom.toprettyxml(indent="  ")

    def create_wrapper_script(self, func_data: Dict, source_module: str, output_dir: Path):
        """Create Python wrapper script that calls BioMni function."""

        wrapper_code = f'''#!/usr/bin/env python3
"""
Galaxy wrapper for BioMni function: {func_data['name']}
Source module: {source_module}
"""

import argparse
import sys
from biomni.tool.{source_module} import {func_data['name']}


def main():
    parser = argparse.ArgumentParser(
        description="BioMni {func_data['name']} wrapper"
    )

'''

        # Add arguments
        for arg in func_data['args']:
            arg_name = arg['name']
            if arg_name in ['data_lake_path', 'config', 'llm']:
                continue

            param_info = func_data['param_descriptions'].get(arg_name, {})
            param_type = self.infer_param_type(arg_name, param_info)

            if param_type == 'boolean':
                wrapper_code += f"    parser.add_argument('--{arg_name}', action='store_true')\n"
            else:
                wrapper_code += f"    parser.add_argument('--{arg_name}', required=False)\n"

        wrapper_code += '''
    args = parser.parse_args()

    # Call BioMni function
    try:
'''

        # Build function call
        call_args = []
        for arg in func_data['args']:
            arg_name = arg['name']
            if arg_name in ['data_lake_path', 'config']:
                continue
            if arg_name == 'llm':
                call_args.append('llm="claude-3-5-sonnet-20241022"')
            else:
                call_args.append(f"{arg_name}=args.{arg_name}")

        wrapper_code += f"        result = {func_data['name']}({', '.join(call_args)})\n"
        wrapper_code += '''        print(f"Success: {result}")
        sys.exit(0)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
'''

        # Save wrapper script
        wrapper_file = output_dir / "wrapper.py"
        with open(wrapper_file, 'w') as f:
            f.write(wrapper_code)

        return wrapper_file

    def convert_tool_module(self, module_path: Path) -> Dict[str, str]:
        """Convert all functions in a BioMni tool module."""
        module_name = module_path.stem
        converted = {}

        print(f"\n⊕ Processing module: {module_name}")

        # Extract imports
        imports = self.extract_imports_from_file(module_path)
        conda_reqs = self.get_conda_requirements(imports)

        if not conda_reqs:
            print(f"  ⊗ Skipping (no identifiable conda requirements)")
            return converted

        # Check if main dependency is in Galaxy
        main_dep = conda_reqs[0] if conda_reqs else None
        if main_dep and main_dep.lower() in self.in_galaxy:
            print(f"  ⊗ Skipping (main dependency '{main_dep}' already in Galaxy)")
            return converted

        # Parse all functions
        with open(module_path, 'r') as f:
            try:
                tree = ast.parse(f.read())
            except SyntaxError:
                print(f"  ✗ Could not parse file")
                return converted

        functions = [node for node in ast.walk(tree) if isinstance(node, ast.FunctionDef)]

        # Filter to public functions (not starting with _)
        public_funcs = [f for f in functions if not f.name.startswith('_')]

        print(f"  Found {len(public_funcs)} public functions, {len(conda_reqs)} conda requirements")

        for func_node in public_funcs[:5]:  # Limit to 5 functions per module
            try:
                func_data = self.parse_function(func_node, "")

                # Create output directory for this tool
                tool_dir = self.output_dir / f"{module_name}_{func_data['name']}"
                tool_dir.mkdir(exist_ok=True)

                # Generate XML
                xml_content = self.generate_galaxy_xml_for_function(
                    func_data,
                    tool_name=f"{module_name}_{func_data['name']}",
                    conda_reqs=conda_reqs,
                    source_module=module_name
                )

                # Save XML
                xml_file = tool_dir / f"{module_name}_{func_data['name']}.xml"
                with open(xml_file, 'w') as f:
                    f.write(xml_content)

                # Create wrapper script
                wrapper_file = self.create_wrapper_script(func_data, module_name, tool_dir)

                converted[func_data['name']] = str(xml_file)
                print(f"    ✓ {func_data['name']}")

            except Exception as e:
                print(f"    ✗ {func_node.name}: {e}")

        return converted

    def convert_all_tools(self) -> Dict:
        """Convert all BioMni tool modules."""
        tool_dir = self.biomni_dir / "biomni" / "tool"

        if not tool_dir.exists():
            raise FileNotFoundError(f"Tool directory not found: {tool_dir}")

        converted = {}
        skipped = []
        errors = []

        print("="*80)
        print("BioMni to Galaxy Converter")
        print("="*80)
        print(f"Source: {tool_dir}")
        print(f"Output: {self.output_dir}")

        # Process each tool module
        for tool_file in sorted(tool_dir.glob("*.py")):
            if tool_file.name.startswith('__') or tool_file.name.startswith('support_'):
                continue

            try:
                module_converted = self.convert_tool_module(tool_file)
                if module_converted:
                    converted.update(module_converted)
                else:
                    skipped.append(tool_file.stem)

            except Exception as e:
                errors.append((tool_file.stem, str(e)))
                print(f"  ✗ Error: {e}")

        # Summary
        print("\n" + "="*80)
        print("CONVERSION COMPLETE")
        print("="*80)
        print(f"✓ Converted: {len(converted)} functions from BioMni")
        print(f"⊗ Skipped: {len(skipped)} modules")
        print(f"✗ Errors: {len(errors)} modules")

        # Save summary
        summary = {
            'converted': list(converted.keys()),
            'skipped': skipped,
            'errors': dict(errors),
            'total_converted': len(converted),
            'output_dir': str(self.output_dir)
        }

        summary_file = self.output_dir / "biomni_conversion_summary.json"
        with open(summary_file, 'w') as f:
            json.dump(summary, f, indent=2)

        print(f"\n📄 Summary saved to: {summary_file}")

        return converted


def main():
    """Main entry point."""
    import argparse

    parser = argparse.ArgumentParser(
        description="Convert BioMni functions to Galaxy tools"
    )
    parser.add_argument(
        '--biomni-dir',
        default='/Users/jingqiwang/Biomni',
        help='Path to Biomni repository'
    )
    parser.add_argument(
        '--output-dir',
        default='/Users/jingqiwang/biomate/backend/tools/biomni_generated',
        help='Output directory for Galaxy tools'
    )

    args = parser.parse_args()

    converter = BioMniToGalaxyConverter(
        biomni_dir=args.biomni_dir,
        output_dir=args.output_dir
    )

    converter.convert_all_tools()


if __name__ == '__main__':
    main()
