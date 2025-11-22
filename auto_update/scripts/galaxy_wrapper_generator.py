#!/usr/bin/env python3
"""
Galaxy Wrapper Generator - Generate Galaxy XML tool wrappers from detected tools

Generates Galaxy tool wrappers from:
- Tool metadata (from detect_github_tools.py)
- Documentation (from documentation_fetcher.py)

Usage:
    python galaxy_wrapper_generator.py --metadata tool_metadata.json --docs tool_docs.json
    python galaxy_wrapper_generator.py --discovery data/discoveries/github_tools_*.json --repo owner/name
"""

import argparse
import json
import logging
import re
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from xml.etree import ElementTree as ET
from xml.dom import minidom

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class CommandExtractor:
    """
    Extracts command-line usage from documentation.
    """

    def extract_command(self, documentation: Dict, metadata: Dict = None) -> Optional[str]:
        """
        Extract primary command from examples and README.
        """
        # Check usage examples first
        examples = documentation.get('usage_examples', [])
        for example in examples:
            # Look for command-line invocations
            commands = self._find_commands(example)
            if commands:
                return commands[0]

        # Fall back to README
        readme = documentation.get('readme', '')
        commands = self._find_commands(readme)
        if commands:
            return commands[0]

        # Check for common executable patterns in installation instructions
        installation = documentation.get('installation', '')
        if installation:
            # Look for entry points or command examples
            install_commands = self._find_commands(installation)
            if install_commands:
                return install_commands[0]

        # Try to infer from tool name and language
        if metadata:
            tool_name = metadata.get('name', '').lower()
            language = metadata.get('language', '').lower()

            # For Python tools, try common patterns
            if language in ['python', 'jupyter notebook']:
                # Common patterns: tool_name, tool-name, or python -m tool_name
                return f'{tool_name} --help || python -m {tool_name} --help'

            # For compiled tools, usually just the tool name
            elif language in ['c', 'c++', 'go', 'rust']:
                return tool_name

        return None

    def _find_commands(self, text: str) -> List[str]:
        """
        Find command-line patterns in text.
        """
        commands = []

        # Pattern 1: python script.py
        pattern1 = re.findall(r'python[3]?\s+[\w\-\.]+\.py.*', text, re.MULTILINE)
        commands.extend(pattern1)

        # Pattern 2: tool_name --arg
        pattern2 = re.findall(r'^[\w\-]+\s+--[\w\-]+.*$', text, re.MULTILINE)
        commands.extend(pattern2)

        # Pattern 3: Rscript script.R
        pattern3 = re.findall(r'Rscript\s+[\w\-\.]+\.R.*', text, re.MULTILINE)
        commands.extend(pattern3)

        return commands[:5]  # Return first 5 matches


class ParameterInferrer:
    """
    Infers input/output parameters from documentation.
    """

    def infer_inputs(self, documentation: Dict, command: str) -> List[Dict]:
        """
        Infer input parameters from examples and command.
        """
        inputs = []

        # Extract flags from command
        flags = re.findall(r'--?([\w\-]+)', command)

        # Common input file parameters
        file_params = ['input', 'in', 'file', 'data', 'fastq', 'bam', 'vcf']

        for flag in flags:
            param = {
                'name': flag.replace('-', '_'),
                'label': flag.replace('-', ' ').title(),
                'type': self._infer_type(flag, documentation),
                'optional': self._is_optional(flag, command),
                'help': self._extract_help(flag, documentation)
            }
            inputs.append(param)

        return inputs

    def infer_outputs(self, documentation: Dict, command: str) -> List[Dict]:
        """
        Infer output files from documentation.
        """
        outputs = []

        # Look for output flags
        output_flags = ['output', 'out', 'result', 'results']
        flags = re.findall(r'--?([\w\-]+)', command)

        for flag in flags:
            if any(of in flag.lower() for of in output_flags):
                output = {
                    'name': flag.replace('-', '_'),
                    'label': flag.replace('-', ' ').title(),
                    'format': self._infer_format(flag, documentation)
                }
                outputs.append(output)

        # If no outputs found, add a generic one
        if not outputs:
            outputs.append({
                'name': 'output',
                'label': 'Output file',
                'format': 'txt'
            })

        return outputs

    def _infer_type(self, param: str, docs: Dict) -> str:
        """Infer parameter type from name and docs"""
        param_lower = param.lower()

        # File types
        if any(x in param_lower for x in ['file', 'input', 'fastq', 'bam', 'vcf', 'bed']):
            return 'data'

        # Integer types
        if any(x in param_lower for x in ['count', 'num', 'threads', 'cores', 'size', 'length']):
            return 'integer'

        # Float types
        if any(x in param_lower for x in ['threshold', 'cutoff', 'alpha', 'beta', 'pvalue', 'qvalue', 'rate']):
            return 'float'

        # Boolean types
        if any(x in param_lower for x in ['enable', 'disable', 'verbose', 'debug', 'force']):
            return 'boolean'

        # Default to text
        return 'text'

    def _is_optional(self, param: str, command: str) -> bool:
        """Check if parameter is optional (has [ ] around it)"""
        return f'[--{param}]' in command or f'[-{param}]' in command

    def _extract_help(self, param: str, docs: Dict) -> str:
        """Extract help text for parameter from documentation"""
        readme = docs.get('readme', '')

        # Look for parameter description
        patterns = [
            rf'--{param}\s+(.{{20,100}})',
            rf'-{param}\s+(.{{20,100}})',
            rf'{param}:\s+(.{{20,100}})'
        ]

        for pattern in patterns:
            match = re.search(pattern, readme, re.IGNORECASE)
            if match:
                help_text = match.group(1).strip()
                # Clean up
                help_text = help_text.split('\n')[0]
                help_text = help_text[:100]
                return help_text

        return f"Parameter for {param}"

    def _infer_format(self, param: str, docs: Dict) -> str:
        """Infer output file format"""
        param_lower = param.lower()

        format_map = {
            'bam': 'bam',
            'vcf': 'vcf',
            'bed': 'bed',
            'fastq': 'fastq',
            'fasta': 'fasta',
            'csv': 'csv',
            'tsv': 'tabular',
            'txt': 'txt',
            'pdf': 'pdf',
            'png': 'png',
            'html': 'html',
            'json': 'json'
        }

        for fmt, galaxy_fmt in format_map.items():
            if fmt in param_lower:
                return galaxy_fmt

        return 'txt'


class ContainerResolver:
    """
    Resolves container images for tools.
    """

    def resolve_container(
        self,
        metadata: Dict,
        documentation: Dict
    ) -> Optional[Dict]:
        """
        Find appropriate container for tool.

        Returns:
            {
                'type': 'docker' | 'singularity',
                'image': 'biocontainers/tool:version'
            }
        """
        container_info = documentation.get('container_info', {})
        tool_name = metadata.get('name', '').lower()
        language = metadata.get('language', '').lower()

        # Check if tool has Dockerfile
        if container_info.get('has_dockerfile'):
            # First try BioContainers (more reliable for bio tools)
            biocontainer = self._check_biocontainers(tool_name)
            if biocontainer:
                return biocontainer

            # Fall back to Docker Hub (check if it exists)
            # Note: This may not always work, better to use language containers
            logger.warning(f"Tool {tool_name} has Dockerfile but no BioContainer - using language container")
            # Fall through to language-based containers below

        # Check biocontainers (common bioinformatics tools)
        biocontainer = self._check_biocontainers(tool_name)
        if biocontainer:
            return biocontainer

        # Language-based container fallbacks
        language_containers = self._get_language_container(language, metadata, documentation)
        if language_containers:
            return language_containers

        # Check if tool is available on PyPI or Conda
        package_container = self._check_package_managers(tool_name, language, documentation)
        if package_container:
            return package_container

        # Check if Singularity available
        if container_info.get('has_singularity'):
            return {
                'type': 'singularity',
                'image': f'library://{metadata.get("full_name")}:latest'
            }

        # Last resort: use generic base image with package install
        return self._generate_generic_container(tool_name, language, documentation)

    def _check_biocontainers(self, tool_name: str) -> Optional[Dict]:
        """
        Check if tool is available in biocontainers by querying the API.

        Returns the latest available tag from quay.io/biocontainers.
        """
        import requests

        # Query BioContainers API
        url = f"https://quay.io/api/v1/repository/biocontainers/{tool_name}/tag/"

        try:
            response = requests.get(url, timeout=10)
            if response.status_code == 200:
                data = response.json()
                tags = data.get('tags', [])

                if tags:
                    # Get the most recent tag
                    # Tags are usually sorted by newest first
                    latest_tag = tags[0]['name']

                    logger.info(f"Found BioContainer for {tool_name}: {latest_tag}")

                    return {
                        'type': 'docker',
                        'image': f'quay.io/biocontainers/{tool_name}:{latest_tag}'
                    }
                else:
                    logger.debug(f"No tags found for biocontainer {tool_name}")
            else:
                logger.debug(f"BioContainer not found for {tool_name} (status: {response.status_code})")

        except requests.exceptions.RequestException as e:
            logger.debug(f"Error querying BioContainers for {tool_name}: {e}")
        except Exception as e:
            logger.debug(f"Unexpected error checking BioContainers for {tool_name}: {e}")

        return None

    def _get_language_container(
        self,
        language: str,
        metadata: Dict,
        documentation: Dict
    ) -> Optional[Dict]:
        """
        Get appropriate container based on programming language.
        """
        tool_name = metadata.get('name', '').lower()

        # Python tools
        if language in ['python', 'jupyter notebook']:
            return {
                'type': 'docker',
                'image': 'python:3.9-slim',
                'setup_commands': [f'pip install {tool_name}']
            }

        # R tools
        elif language == 'r':
            return {
                'type': 'docker',
                'image': 'r-base:4.3.1',
                'setup_commands': [f'R -e "install.packages(\'{tool_name}\')"']
            }

        # Java tools
        elif language == 'java':
            return {
                'type': 'docker',
                'image': 'openjdk:11-jre-slim'
            }

        # C/C++ tools
        elif language in ['c', 'c++', 'cpp']:
            return {
                'type': 'docker',
                'image': 'gcc:13.2.0'
            }

        # Go tools
        elif language == 'go':
            return {
                'type': 'docker',
                'image': 'golang:1.19'
            }

        # Rust tools
        elif language == 'rust':
            return {
                'type': 'docker',
                'image': 'rust:1.75.0'
            }

        return None

    def _check_package_managers(
        self,
        tool_name: str,
        language: str,
        documentation: Dict
    ) -> Optional[Dict]:
        """
        Check if tool is available via package managers (PyPI, Conda, CRAN).
        """
        readme = documentation.get('readme', '').lower()
        installation = documentation.get('installation', '').lower()

        # Check for pip install
        if 'pip install' in installation or 'pip install' in readme:
            return {
                'type': 'docker',
                'image': 'python:3.9-slim',
                'setup_commands': [f'pip install {tool_name}']
            }

        # Check for conda install
        if 'conda install' in installation or 'conda install' in readme:
            return {
                'type': 'docker',
                'image': 'continuumio/miniconda3',
                'setup_commands': [f'conda install -c bioconda {tool_name}']
            }

        # Check for R package
        if language == 'r' and ('install.packages' in installation or 'bioconductor' in readme):
            return {
                'type': 'docker',
                'image': 'bioconductor/bioconductor_docker:RELEASE_3_18',
                'setup_commands': [f'R -e "BiocManager::install(\'{tool_name}\')"']
            }

        return None

    def _generate_generic_container(
        self,
        tool_name: str,
        language: str,
        documentation: Dict
    ) -> Optional[Dict]:
        """
        Generate a generic container configuration as last resort.
        """
        # Prefer Python for unknown tools
        if language in ['python', 'jupyter notebook', '']:
            return {
                'type': 'docker',
                'image': 'python:3.9-slim',
                'setup_commands': [f'pip install {tool_name} || echo "Package not found"']
            }

        # For other languages, use appropriate base
        language_map = {
            'r': 'r-base:4.3.1',
            'java': 'openjdk:11-jre-slim',
            'javascript': 'node:16-slim',
            'typescript': 'node:16-slim',
            'ruby': 'ruby:3.0-slim',
            'perl': 'perl:5.34',
            'go': 'golang:1.19',
            'rust': 'rust:1.75.0'
        }

        base_image = language_map.get(language, 'ubuntu:20.04')
        return {
            'type': 'docker',
            'image': base_image
        }


class GalaxyWrapperGenerator:
    """
    Generates Galaxy XML tool wrappers.
    """

    def __init__(self):
        self.command_extractor = CommandExtractor()
        self.param_inferrer = ParameterInferrer()
        self.container_resolver = ContainerResolver()

    def generate_wrapper(
        self,
        metadata: Dict,
        documentation: Dict
    ) -> str:
        """
        Generate complete Galaxy XML wrapper.

        Args:
            metadata: Tool metadata from detector
            documentation: Documentation from fetcher

        Returns:
            XML string
        """
        logger.info(f"Generating wrapper for {metadata.get('name')}")

        # Extract command with metadata context
        command = self.command_extractor.extract_command(documentation, metadata)
        if not command:
            # Final fallback to tool name
            tool_name = metadata.get('name', 'tool')
            language = metadata.get('language', '').lower()
            if language == 'python':
                command = f'python -m {tool_name}'
            else:
                command = tool_name
            logger.warning(f"Could not extract command, using: {command}")

        # Infer parameters
        inputs = self.param_inferrer.infer_inputs(documentation, command)
        outputs = self.param_inferrer.infer_outputs(documentation, command)

        # Resolve container
        container = self.container_resolver.resolve_container(metadata, documentation)

        # Generate XML
        xml = self._build_xml(
            metadata=metadata,
            documentation=documentation,
            command=command,
            inputs=inputs,
            outputs=outputs,
            container=container
        )

        return xml

    def _build_xml(
        self,
        metadata: Dict,
        documentation: Dict,
        command: str,
        inputs: List[Dict],
        outputs: List[Dict],
        container: Optional[Dict]
    ) -> str:
        """
        Build Galaxy XML structure.
        """
        # Create root element
        tool = ET.Element('tool')
        tool.set('id', self._generate_tool_id(metadata))
        tool.set('name', metadata.get('name', 'Unknown Tool'))
        tool.set('version', '1.0.0')  # TODO: Extract from repo

        # Description
        description = ET.SubElement(tool, 'description')
        description.text = metadata.get('description', '')[:100]

        # Requirements (container)
        if container:
            requirements = ET.SubElement(tool, 'requirements')
            req = ET.SubElement(requirements, 'container')
            req.set('type', container['type'])
            req.text = container['image']

        # Command
        command_elem = ET.SubElement(tool, 'command')
        command_elem.set('detect_errors', 'exit_code')

        # Include setup commands if present in container
        setup_commands = container.get('setup_commands', []) if container else []
        command_elem.text = self._build_command_template(command, inputs, outputs, setup_commands)

        # Inputs
        inputs_elem = ET.SubElement(tool, 'inputs')
        for inp in inputs:
            self._add_input_param(inputs_elem, inp)

        # Outputs
        outputs_elem = ET.SubElement(tool, 'outputs')
        for out in outputs:
            self._add_output_param(outputs_elem, out)

        # Help
        help_elem = ET.SubElement(tool, 'help')
        help_elem.text = documentation.get('help_text', metadata.get('description', ''))

        # Citations
        if metadata.get('has_paper'):
            citations = ET.SubElement(tool, 'citations')
            citation = ET.SubElement(citations, 'citation')
            citation.set('type', 'doi')
            citation.text = 'TODO: Extract DOI'

        # Pretty print XML
        return self._prettify_xml(tool)

    def _generate_tool_id(self, metadata: Dict) -> str:
        """Generate Galaxy tool ID from metadata"""
        name = metadata.get('name', 'unknown').lower()
        name = re.sub(r'[^a-z0-9_]', '_', name)
        return f"auto_{name}"

    def _build_command_template(
        self,
        command: str,
        inputs: List[Dict],
        outputs: List[Dict],
        setup_commands: List[str] = None
    ) -> str:
        """
        Build Galaxy command template with variable substitution.
        """
        # Build command sections
        cmd_parts = []

        # Add setup commands if present
        if setup_commands:
            cmd_parts.append("# Setup environment")
            for setup_cmd in setup_commands:
                cmd_parts.append(setup_cmd)
            cmd_parts.append("")
            cmd_parts.append("# Run tool")

        # Start with base command
        cmd_template = command

        # Replace input references with Galaxy variables
        for inp in inputs:
            param_name = inp['name']
            # Look for various patterns
            patterns = [
                f"--{param_name}",
                f"-{param_name}",
                f"{param_name}"
            ]

            for pattern in patterns:
                if pattern in cmd_template:
                    if inp['type'] == 'data':
                        cmd_template = cmd_template.replace(
                            pattern + ' <file>',
                            f"{pattern} ${param_name}"
                        )
                    else:
                        cmd_template = cmd_template.replace(
                            pattern + ' <value>',
                            f"{pattern} ${param_name}"
                        )

        # Add output references
        for out in outputs:
            param_name = out['name']
            cmd_template = cmd_template.replace(
                '--output <file>',
                f"--output ${param_name}"
            )

        # Add the actual command
        cmd_parts.append(cmd_template)

        # Combine all parts
        full_command = '\n'.join(cmd_parts) if cmd_parts else cmd_template

        return f"<![CDATA[\n{full_command}\n]]>"

    def _add_input_param(self, parent: ET.Element, param: Dict):
        """Add input parameter to XML"""
        param_elem = ET.SubElement(parent, 'param')
        param_elem.set('name', param['name'])
        param_elem.set('type', param['type'])
        param_elem.set('label', param['label'])

        if param.get('optional'):
            param_elem.set('optional', 'true')

        if param.get('help'):
            param_elem.set('help', param['help'])

        # Add format for data inputs
        if param['type'] == 'data':
            param_elem.set('format', 'txt,fastq,bam,vcf')  # Common formats

    def _add_output_param(self, parent: ET.Element, param: Dict):
        """Add output parameter to XML"""
        data_elem = ET.SubElement(parent, 'data')
        data_elem.set('name', param['name'])
        data_elem.set('format', param.get('format', 'txt'))
        data_elem.set('label', param['label'])

    def _prettify_xml(self, elem: ET.Element) -> str:
        """Pretty print XML with proper indentation"""
        rough_string = ET.tostring(elem, encoding='unicode')
        reparsed = minidom.parseString(rough_string)
        return reparsed.toprettyxml(indent="  ")


def load_metadata(metadata_file: Path) -> Dict:
    """Load tool metadata from JSON file"""
    with open(metadata_file) as f:
        return json.load(f)


def load_documentation(docs_file: Path) -> Dict:
    """Load documentation from JSON file"""
    with open(docs_file) as f:
        return json.load(f)


def save_wrapper(wrapper_xml: str, output_file: Path):
    """Save wrapper XML to file"""
    output_file.parent.mkdir(parents=True, exist_ok=True)
    with open(output_file, 'w') as f:
        f.write(wrapper_xml)
    logger.info(f"Wrapper saved to: {output_file}")


def main():
    parser = argparse.ArgumentParser(
        description='Generate Galaxy tool wrappers from detected tools'
    )
    parser.add_argument(
        '--metadata',
        type=str,
        help='Tool metadata JSON file (from detector)'
    )
    parser.add_argument(
        '--docs',
        type=str,
        help='Documentation JSON file (from fetcher)'
    )
    parser.add_argument(
        '--discovery',
        type=str,
        help='Discovery file with all tools (alternative to --metadata)'
    )
    parser.add_argument(
        '--repo',
        type=str,
        help='Specific repo to generate wrapper for (with --discovery)'
    )
    parser.add_argument(
        '--output',
        type=str,
        default='data/wrappers',
        help='Output directory for wrappers'
    )

    args = parser.parse_args()

    # Load inputs
    if args.discovery and args.repo:
        # Load from discovery file
        discoveries = json.load(open(args.discovery))
        metadata = next((d for d in discoveries if d['full_name'] == args.repo), None)
        if not metadata:
            logger.error(f"Repo {args.repo} not found in discoveries")
            return 1

        # Need to fetch docs
        logger.error("--discovery mode requires running documentation_fetcher first")
        return 1

    elif args.metadata and args.docs:
        metadata = load_metadata(Path(args.metadata))
        documentation = load_documentation(Path(args.docs))
    else:
        logger.error("Either --metadata and --docs, or --discovery and --repo required")
        return 1

    # Generate wrapper
    generator = GalaxyWrapperGenerator()
    wrapper_xml = generator.generate_wrapper(metadata, documentation)

    # Save wrapper
    tool_name = metadata.get('name', 'unknown')
    output_file = Path(args.output) / f"{tool_name}.xml"
    save_wrapper(wrapper_xml, output_file)

    print(f"\nGenerated wrapper for: {metadata.get('name')}")
    print(f"Output: {output_file}")
    print(f"\nPreview:")
    print(wrapper_xml[:500])

    return 0


if __name__ == '__main__':
    exit(main())
