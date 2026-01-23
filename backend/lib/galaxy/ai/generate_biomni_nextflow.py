#!/usr/bin/env python3
"""
Generate complete Nextflow workflows from Galaxy Biomni tools.

This script:
1. Parses Galaxy XML tool definitions
2. Extracts parameters, types, and defaults
3. Generates proper Nextflow workflows with actual biomni calls
"""

import os
import re
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Dict, List, Any, Optional
from dataclasses import dataclass


@dataclass
class ToolParam:
    """Represents a tool parameter."""
    name: str
    param_type: str  # text, integer, float, boolean, data
    label: str
    help: str
    default: Optional[str] = None
    optional: bool = False


@dataclass
class GalaxyTool:
    """Represents a Galaxy tool definition."""
    tool_id: str
    name: str
    description: str
    domain: str
    function_name: str
    params: List[ToolParam]
    container: str = "biomate/biomni-tools:latest"


def fix_xml_attribute_quotes(content: str) -> str:
    """Fix embedded double quotes in XML attribute values."""
    lines = content.split('\n')
    fixed_lines = []

    for line in lines:
        # Skip XML declaration and special lines
        stripped = line.strip()
        if stripped.startswith('<?') or stripped.startswith('<!') or stripped.startswith(']]'):
            fixed_lines.append(line)
            continue

        # Skip lines without attributes
        if '="' not in line:
            fixed_lines.append(line)
            continue

        # Process attribute values - find all attr="..." patterns
        # Use a state machine to properly handle nested quotes
        result = []
        i = 0
        while i < len(line):
            # Look for attribute pattern: word="
            match = re.match(r'(\w+)="', line[i:])
            if match:
                attr_name = match.group(1)
                result.append(f'{attr_name}="')
                i += len(match.group(0))

                # Now find the closing quote - it should be followed by:
                # - space + another attribute name + =
                # - space + />
                # - space + >
                # - /> directly
                # - > directly
                # - end of line
                value_chars = []
                while i < len(line):
                    char = line[i]
                    # Check if this quote is the closing one
                    if char == '"':
                        # Look ahead to see if this ends the attribute
                        rest = line[i+1:]

                        # Check for end-of-attribute patterns
                        is_closing = False

                        # End of line
                        if not rest.strip():
                            is_closing = True
                        # Direct /> or >
                        elif rest.startswith('/>') or rest.startswith('>'):
                            is_closing = True
                        # Space followed by /> or > or another attribute
                        elif rest.startswith(' ') or rest.startswith('\t'):
                            # Skip whitespace and check what follows
                            rest_stripped = rest.lstrip()
                            if not rest_stripped:
                                is_closing = True
                            elif rest_stripped.startswith('/>') or rest_stripped.startswith('>'):
                                is_closing = True
                            elif re.match(r'\w+="', rest_stripped):
                                # Another attribute follows - this is the closing quote
                                is_closing = True

                        if is_closing:
                            # This is the closing quote
                            break
                        else:
                            # This is an embedded quote - escape it
                            value_chars.append('&quot;')
                            i += 1
                            continue
                    # Escape < and > characters in attribute values
                    elif char == '<':
                        value_chars.append('&lt;')
                        i += 1
                        continue
                    elif char == '>' and i > 0 and line[i-1] != '/':
                        # Only escape > if it's not part of />
                        value_chars.append('&gt;')
                        i += 1
                        continue
                    value_chars.append(char)
                    i += 1

                result.append(''.join(value_chars))
                result.append('"')
                i += 1  # skip the closing quote
            else:
                result.append(line[i])
                i += 1

        fixed_lines.append(''.join(result))

    return '\n'.join(fixed_lines)


def parse_galaxy_xml(xml_path: Path) -> Optional[GalaxyTool]:
    """Parse a Galaxy tool XML file."""
    try:
        # Read and sanitize XML content
        content = xml_path.read_text(encoding='utf-8', errors='replace')
        # Fix common XML issues - escape unescaped ampersands and angle brackets in text
        content = re.sub(r'&(?!(amp|lt|gt|quot|apos);)', '&amp;', content)

        # Fix embedded double quotes in attribute values
        content = fix_xml_attribute_quotes(content)

        # Parse from string
        root = ET.fromstring(content)

        tool_id = root.get('id', '')
        name = root.get('name', '')

        # Get description
        desc_elem = root.find('description')
        description = desc_elem.text.strip() if desc_elem is not None and desc_elem.text else ''

        # Get container
        container = "biomate/biomni-tools:latest"
        container_elem = root.find('.//container')
        if container_elem is not None and container_elem.text:
            container = container_elem.text.strip()

        # Extract domain and function from help section
        domain = ""
        function_name = ""
        help_elem = root.find('help')
        if help_elem is not None and help_elem.text:
            help_text = help_elem.text
            domain_match = re.search(r'\*\*Domain\*\*:\s*(\w+)', help_text)
            func_match = re.search(r'\*\*Function\*\*:\s*(\w+)', help_text)
            if domain_match:
                domain = domain_match.group(1)
            if func_match:
                function_name = func_match.group(1)

        # If not found in help, extract from tool_id
        if not domain or not function_name:
            parts = tool_id.replace('biomni_', '').split('_', 1)
            if len(parts) >= 2:
                domain = parts[0]
                function_name = parts[1]
            elif len(parts) == 1:
                function_name = parts[0]

        # Parse parameters
        params = []
        inputs_elem = root.find('inputs')
        if inputs_elem is not None:
            for param_elem in inputs_elem.findall('param'):
                param_name = param_elem.get('name', '')
                param_type = param_elem.get('type', 'text')
                label = param_elem.get('label', param_name)
                help_text = param_elem.get('help', '')
                default = param_elem.get('value')
                optional = param_elem.get('optional', 'false').lower() == 'true'

                # Skip output parameter
                if param_name == 'output':
                    continue

                params.append(ToolParam(
                    name=param_name,
                    param_type=param_type,
                    label=label,
                    help=help_text,
                    default=default,
                    optional=optional
                ))

        return GalaxyTool(
            tool_id=tool_id,
            name=name,
            description=description,
            domain=domain,
            function_name=function_name,
            params=params,
            container=container
        )

    except Exception as e:
        print(f"Error parsing {xml_path}: {e}")
        return None


def get_nextflow_type(param: ToolParam) -> str:
    """Convert Galaxy param type to Nextflow type."""
    if param.param_type == 'data':
        return 'path'
    elif param.param_type == 'integer':
        return 'val'
    elif param.param_type == 'float':
        return 'val'
    elif param.param_type == 'boolean':
        return 'val'
    else:
        return 'val'


def get_python_value(param: ToolParam, is_nextflow_param: bool = True) -> str:
    """Get Python representation of parameter value."""
    prefix = "params." if is_nextflow_param else ""

    if param.param_type == 'text':
        return f'"${{{prefix}{param.name}}}"'
    elif param.param_type in ('integer', 'float'):
        return f"${{{prefix}{param.name}}}"
    elif param.param_type == 'boolean':
        return f"${{{prefix}{param.name}}}"
    elif param.param_type == 'data':
        return f'"${{{param.name}}}"'
    else:
        return f'"${{{prefix}{param.name}}}"'


def get_default_value(param: ToolParam) -> str:
    """Get default value for Nextflow params."""
    if param.default:
        if param.param_type in ('integer', 'float'):
            return param.default
        elif param.param_type == 'boolean':
            return 'true' if param.default.lower() in ('true', '1', 'yes') else 'false'
        else:
            return f"'{param.default}'"
    else:
        if param.param_type in ('integer', 'float'):
            return '0'
        elif param.param_type == 'boolean':
            return 'false'
        else:
            return 'null'


def generate_nextflow_workflow(tool: GalaxyTool) -> str:
    """Generate a complete Nextflow workflow for a Galaxy tool."""

    # Separate file inputs from value parameters
    file_params = [p for p in tool.params if p.param_type == 'data']
    value_params = [p for p in tool.params if p.param_type != 'data']

    # Generate process name
    process_name = tool.function_name.upper()
    workflow_name = f"BIOMNI_{tool.domain.upper()}_{tool.function_name.upper()}"

    # Build params section
    params_lines = []
    params_lines.append("params.outdir = './results'")
    for p in tool.params:
        default = get_default_value(p)
        params_lines.append(f"params.{p.name} = {default}")
    params_section = "\n".join(params_lines)

    # Build input section
    input_lines = []
    for p in file_params:
        input_lines.append(f"    path({p.name})")
    for p in value_params:
        # Value params come from params, not input channels
        pass
    input_section = "\n".join(input_lines) if input_lines else "    // No file inputs"

    # Build function call arguments
    func_args = []
    for p in tool.params:
        if p.param_type == 'data':
            func_args.append(f'    {p.name}="${{{p.name}}}"')
        else:
            if p.param_type in ('integer', 'float'):
                func_args.append(f'    {p.name}=${{params.{p.name}}}')
            elif p.param_type == 'boolean':
                # Pass boolean as True/False string that Python can evaluate
                func_args.append(f'    {p.name}=${{params.{p.name} ? "True" : "False"}}')
            else:
                func_args.append(f'    {p.name}="${{params.{p.name}}}"')
    func_args_str = ",\n".join(func_args)

    # Build validation section
    required_params = [p for p in tool.params if not p.optional and p.param_type != 'data']
    validation_lines = []
    for p in required_params:
        if p.param_type == 'text':
            validation_lines.append(f'''    if (!params.{p.name}) {{
        error "Please provide --{p.name} parameter"
    }}''')
    validation_section = "\n".join(validation_lines) if validation_lines else ""

    # Build channel creation for file inputs
    channel_lines = []
    for p in file_params:
        channel_lines.append(f"    ch_{p.name} = Channel.fromPath(params.{p.name}, checkIfExists: true)")
    channel_section = "\n".join(channel_lines) if channel_lines else ""

    # Build workflow call arguments
    workflow_call_args = ", ".join([f"ch_{p.name}" for p in file_params]) if file_params else ""

    # Build take section
    take_lines = [f"    ch_{p.name}" for p in file_params]
    take_section = "\n".join(take_lines) if take_lines else "    // No file inputs"

    # Build process call
    process_call_args = ", ".join([f"ch_{p.name}" for p in file_params]) if file_params else ""

    # Generate the workflow
    workflow = f'''#!/usr/bin/env nextflow
/*
 * {tool.tool_id}
 * {tool.description}
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
{params_section}

// Main process
process {process_name} {{
    tag "${{task.process}}"
    label 'process_medium'
    publishDir "${{params.outdir}}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
{input_section}

    output:
    path("{tool.function_name}_results.json"), emit: results
    path("{tool.function_name}_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.{tool.domain} import {tool.function_name}

# Run the tool
try:
    result = {tool.function_name}(
{func_args_str}
    )
except Exception as e:
    result = {{"error": str(e)}}

# Save results as JSON
with open("{tool.function_name}_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("{tool.function_name}_output.txt", "w") as f:
    f.write("{tool.name} Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("{tool.function_name} completed successfully")
PYEOF
    """
}}

// Workflow definition
workflow {workflow_name} {{
    take:
{take_section}

    main:
    {process_name}({process_call_args})

    emit:
    results = {process_name}.out.results
    output = {process_name}.out.output
}}

// Entry workflow
workflow {{
{validation_section}
{channel_section}

    {workflow_name}({workflow_call_args})
}}
'''

    return workflow


def process_all_tools(galaxy_tools_dir: Path, output_dir: Path) -> Dict[str, Any]:
    """Process all Galaxy tools and generate Nextflow workflows."""

    stats = {
        'total': 0,
        'success': 0,
        'failed': 0,
        'by_domain': {}
    }

    # Find all XML files
    xml_files = list(galaxy_tools_dir.rglob('*.xml'))
    stats['total'] = len(xml_files)

    for xml_path in xml_files:
        # Skip non-tool XML files
        if 'macros' in xml_path.name or 'datatypes' in xml_path.name:
            continue

        tool = parse_galaxy_xml(xml_path)
        if tool is None:
            stats['failed'] += 1
            continue

        # Skip if no function name
        if not tool.function_name:
            stats['failed'] += 1
            continue

        # Generate Nextflow workflow
        try:
            nf_content = generate_nextflow_workflow(tool)

            # Create output directory
            domain_dir = output_dir / "subworkflows" / tool.domain
            domain_dir.mkdir(parents=True, exist_ok=True)

            # Write workflow file
            output_file = domain_dir / f"{tool.function_name}.nf"
            output_file.write_text(nf_content)

            stats['success'] += 1
            stats['by_domain'][tool.domain] = stats['by_domain'].get(tool.domain, 0) + 1

            print(f"Generated: {output_file}")

        except Exception as e:
            print(f"Error generating workflow for {tool.tool_id}: {e}")
            stats['failed'] += 1

    return stats


def generate_nextflow_config(output_dir: Path):
    """Generate a master nextflow.config file."""

    config = '''/*
 * Biomni Nextflow Configuration
 * Generated configuration for running Biomni tools
 */

// Docker configuration
docker.enabled = true
docker.runOptions = '-u $(id -u):$(id -g)'

// Process resource defaults
process {
    withLabel: 'process_low' {
        cpus = 1
        memory = '2.GB'
        time = '1.h'
    }
    withLabel: 'process_medium' {
        cpus = 2
        memory = '4.GB'
        time = '4.h'
    }
    withLabel: 'process_high' {
        cpus = 4
        memory = '8.GB'
        time = '8.h'
    }

    // Default container
    container = 'biomate/biomni-tools:latest'

    // Error handling
    errorStrategy = 'retry'
    maxRetries = 2
}

// Profiles for different execution environments
profiles {
    standard {
        process.executor = 'local'
    }

    docker {
        docker.enabled = true
    }

    singularity {
        singularity.enabled = true
        singularity.autoMounts = true
    }

    aws_batch {
        process.executor = 'awsbatch'
        process.queue = 'biomni-queue'
        aws.region = 'us-west-2'
        workDir = 's3://biomni-work/nextflow'
    }
}

// Output directory
params.outdir = './results'

// Manifest
manifest {
    name = 'biomni-workflows'
    author = 'BioMate Team'
    description = 'Biomni bioinformatics workflows for Nextflow'
    version = '1.0.0'
    nextflowVersion = '>=21.10.0'
}
'''

    config_file = output_dir / "nextflow.config"
    config_file.write_text(config)
    print(f"Generated: {config_file}")


def main():
    """Main entry point."""
    import argparse

    parser = argparse.ArgumentParser(description='Generate Nextflow workflows from Galaxy tools')
    parser.add_argument('--galaxy-dir', type=Path,
                        default=Path('/home/yzhang/biomate/backend/biomni_workflows/galaxy/tools/biomni'),
                        help='Path to Galaxy tools directory')
    parser.add_argument('--output-dir', type=Path,
                        default=Path('/home/yzhang/biomate/backend/biomni_workflows/nextflow_generated'),
                        help='Output directory for Nextflow workflows')

    args = parser.parse_args()

    print(f"Galaxy tools directory: {args.galaxy_dir}")
    print(f"Output directory: {args.output_dir}")
    print()

    # Create output directory
    args.output_dir.mkdir(parents=True, exist_ok=True)

    # Process all tools
    stats = process_all_tools(args.galaxy_dir, args.output_dir)

    # Generate config
    generate_nextflow_config(args.output_dir)

    # Print summary
    print()
    print("=" * 60)
    print("Generation Summary")
    print("=" * 60)
    print(f"Total XML files: {stats['total']}")
    print(f"Successfully generated: {stats['success']}")
    print(f"Failed: {stats['failed']}")
    print()
    print("By domain:")
    for domain, count in sorted(stats['by_domain'].items()):
        print(f"  {domain}: {count}")


if __name__ == '__main__':
    main()
