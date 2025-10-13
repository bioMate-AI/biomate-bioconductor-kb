#!/usr/bin/env python3
"""
Generate tool_conf.xml section for BioMate custom tools.

This creates the XML configuration needed to register custom tools with Galaxy.
"""

import os
from pathlib import Path
import xml.etree.ElementTree as ET


def generate_tool_conf_section(base_path=None, output_format='xml'):
    """
    Generate tool_conf.xml section for BioMate custom tools.

    Args:
        base_path: Base path for tool files (defaults to backend/tools)
        output_format: 'xml' for tool_conf.xml, 'yaml' for galaxy.yml section
    """

    if base_path is None:
        base_path = Path(__file__).parent.parent / 'tools'
    else:
        base_path = Path(base_path)

    # Find all tool directories
    tool_dirs = [
        ('nfcore_lcms', 'nf-core LC-MS Tools'),
        ('nfcore_general', 'nf-core General Tools'),
        ('nfcore_missing', 'nf-core Additional Tools'),
        ('biomni_missing', 'BioMni Python/R Tools'),
    ]

    if output_format == 'xml':
        return generate_xml_config(base_path, tool_dirs)
    elif output_format == 'yaml':
        return generate_yaml_config(base_path, tool_dirs)
    else:
        raise ValueError(f"Unknown format: {output_format}")


def generate_xml_config(base_path, tool_dirs):
    """Generate XML format tool configuration."""

    xml_lines = ['<?xml version="1.0" encoding="utf-8"?>']
    xml_lines.append('<toolbox>')
    xml_lines.append('  <!-- BioMate Custom Tools - Auto-generated -->')

    tool_count = 0

    for dir_name, section_label in tool_dirs:
        tool_dir = base_path / dir_name

        if not tool_dir.exists():
            continue

        xml_files = sorted(tool_dir.glob('*.xml'))

        if not xml_files:
            continue

        xml_lines.append(f'  <section id="biomate_{dir_name}" name="{section_label}">')

        for xml_file in xml_files:
            # Use relative path from Galaxy's perspective
            # Assuming tools will be in galaxy/tools/biomate_custom/
            rel_path = f"biomate_custom/{dir_name}/{xml_file.name}"
            xml_lines.append(f'    <tool file="{rel_path}"/>')
            tool_count += 1

        xml_lines.append('  </section>')

    xml_lines.append('</toolbox>')
    xml_lines.append('')
    xml_lines.append(f'<!-- Total tools: {tool_count} -->')

    return '\n'.join(xml_lines)


def generate_yaml_config(base_path, tool_dirs):
    """Generate YAML format tool configuration (for galaxy.yml)."""

    yaml_lines = ['# BioMate Custom Tools Configuration']
    yaml_lines.append('# Add this to galaxy.yml')
    yaml_lines.append('')
    yaml_lines.append('tool_config_file:')
    yaml_lines.append('  - config/tool_conf.xml')
    yaml_lines.append('  - config/tool_conf_biomate.xml  # BioMate custom tools')
    yaml_lines.append('')
    yaml_lines.append('# Alternative: inline tool paths')
    yaml_lines.append('# tool_path:')
    yaml_lines.append('#   - tools')
    yaml_lines.append('#   - tools/biomate_custom')

    return '\n'.join(yaml_lines)


def generate_install_script(base_path, galaxy_root):
    """Generate bash script to install tools into Galaxy."""

    script_lines = ['#!/bin/bash']
    script_lines.append('# Install BioMate custom tools into Galaxy')
    script_lines.append('')
    script_lines.append('set -e  # Exit on error')
    script_lines.append('')
    script_lines.append(f'BIOMATE_TOOLS="{base_path}"')
    script_lines.append(f'GALAXY_ROOT="{galaxy_root}"')
    script_lines.append('GALAXY_TOOLS="$GALAXY_ROOT/tools/biomate_custom"')
    script_lines.append('')
    script_lines.append('echo "Installing BioMate custom tools to Galaxy..."')
    script_lines.append('')
    script_lines.append('# Create target directory')
    script_lines.append('mkdir -p "$GALAXY_TOOLS"')
    script_lines.append('')
    script_lines.append('# Copy tool directories')
    script_lines.append('for dir in nfcore_lcms nfcore_general nfcore_missing biomni_missing; do')
    script_lines.append('  if [ -d "$BIOMATE_TOOLS/$dir" ]; then')
    script_lines.append('    echo "Copying $dir..."')
    script_lines.append('    cp -r "$BIOMATE_TOOLS/$dir" "$GALAXY_TOOLS/"')
    script_lines.append('  fi')
    script_lines.append('done')
    script_lines.append('')
    script_lines.append('# Generate tool config')
    script_lines.append('python3 "$(dirname "$0")/generate_tool_conf_section.py" > "$GALAXY_ROOT/config/tool_conf_biomate.xml"')
    script_lines.append('')
    script_lines.append('echo "✅ Tools installed successfully!"')
    script_lines.append('echo "Next steps:"')
    script_lines.append('echo "1. Add to galaxy.yml: tool_config_file: config/tool_conf.xml,config/tool_conf_biomate.xml"')
    script_lines.append('echo "2. Restart Galaxy: cd $GALAXY_ROOT && ./run.sh restart"')

    return '\n'.join(script_lines)


def main():
    """Main execution."""
    import argparse

    parser = argparse.ArgumentParser(
        description='Generate Galaxy tool configuration for BioMate custom tools'
    )
    parser.add_argument(
        '--format', '-f',
        choices=['xml', 'yaml', 'install'],
        default='xml',
        help='Output format (default: xml)'
    )
    parser.add_argument(
        '--tools-path', '-t',
        help='Path to BioMate tools directory (default: backend/tools)'
    )
    parser.add_argument(
        '--galaxy-root', '-g',
        help='Path to Galaxy root directory (required for install script)'
    )
    parser.add_argument(
        '--output', '-o',
        help='Output file (default: stdout)'
    )

    args = parser.parse_args()

    # Generate output
    if args.format == 'install':
        if not args.galaxy_root:
            parser.error('--galaxy-root is required for install script')
        tools_path = args.tools_path or str(Path(__file__).parent.parent / 'tools')
        output = generate_install_script(tools_path, args.galaxy_root)
    else:
        output = generate_tool_conf_section(args.tools_path, args.format)

    # Write output
    if args.output:
        with open(args.output, 'w') as f:
            f.write(output)
        print(f"✅ Generated {args.format} configuration: {args.output}")
    else:
        print(output)


if __name__ == '__main__':
    main()
