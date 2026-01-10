#!/usr/bin/env python3
"""
Generate proper Galaxy XML tool wrappers from Biomni functions.

This creates Galaxy-compatible tool wrappers that:
1. Call Biomni functions directly via a wrapper script
2. Handle file inputs/outputs correctly
3. Support all parameter types
"""

import ast
import json
import re
from pathlib import Path
from typing import Any
import inspect


def get_python_type_to_galaxy(py_type: str) -> dict:
    """Convert Python type annotation to Galaxy param type."""
    type_map = {
        'str': {'type': 'text', 'format': None},
        'int': {'type': 'integer', 'format': None},
        'float': {'type': 'float', 'format': None},
        'bool': {'type': 'boolean', 'format': None},
        'list': {'type': 'text', 'format': None},  # JSON list
        'list[str]': {'type': 'text', 'format': None},
        'list[int]': {'type': 'text', 'format': None},
        'Path': {'type': 'data', 'format': 'data'},
    }

    # File path types
    if 'path' in py_type.lower() or 'file' in py_type.lower():
        return {'type': 'data', 'format': 'data'}
    if 'h5ad' in py_type.lower():
        return {'type': 'data', 'format': 'h5ad'}
    if 'csv' in py_type.lower():
        return {'type': 'data', 'format': 'csv'}
    if 'fasta' in py_type.lower() or 'fa' in py_type.lower():
        return {'type': 'data', 'format': 'fasta'}
    if 'fastq' in py_type.lower() or 'fq' in py_type.lower():
        return {'type': 'data', 'format': 'fastq'}

    return type_map.get(py_type, {'type': 'text', 'format': None})


def parse_function_signature(func_node: ast.FunctionDef) -> dict:
    """Extract function signature details from AST node."""
    params = []

    # Get defaults
    defaults = func_node.args.defaults
    num_defaults = len(defaults)
    num_args = len(func_node.args.args)

    for i, arg in enumerate(func_node.args.args):
        if arg.arg in ('self', 'cls'):
            continue

        param = {
            'name': arg.arg,
            'type': 'str',
            'required': True,
            'default': None,
            'description': ''
        }

        # Get type annotation
        if arg.annotation:
            try:
                param['type'] = ast.unparse(arg.annotation)
            except:
                param['type'] = 'str'

        # Check if has default
        default_idx = i - (num_args - num_defaults)
        if default_idx >= 0:
            param['required'] = False
            try:
                default_val = defaults[default_idx]
                if isinstance(default_val, ast.Constant):
                    param['default'] = default_val.value
                elif isinstance(default_val, ast.Name) and default_val.id in ('None', 'True', 'False'):
                    param['default'] = None if default_val.id == 'None' else default_val.id == 'True'
            except:
                pass

        params.append(param)

    # Get docstring
    docstring = ast.get_docstring(func_node) or ""

    # Parse parameter descriptions from docstring
    param_section = False
    current_param = None
    for line in docstring.split('\n'):
        stripped = line.strip()
        if stripped.startswith('Parameters') or stripped.startswith('Args'):
            param_section = True
            continue
        if stripped.startswith('Returns') or stripped.startswith('Examples'):
            param_section = False
            continue
        if param_section and stripped:
            # Match "param_name : type" or "param_name (type)"
            match = re.match(r'^(\w+)\s*[:\(]', stripped)
            if match:
                current_param = match.group(1)
            elif current_param and stripped:
                for p in params:
                    if p['name'] == current_param:
                        p['description'] = stripped
                        break

    return {
        'name': func_node.name,
        'params': params,
        'docstring': docstring,
        'summary': docstring.split('\n')[0] if docstring else ''
    }


def generate_xml_tool(func_info: dict, domain: str) -> str:
    """Generate Galaxy XML tool wrapper for a Biomni function with Docker support."""
    tool_id = f"biomni_{domain}_{func_info['name']}"
    tool_name = f"Biomni: {func_info['name'].replace('_', ' ').title()}"

    # Build inputs section
    inputs_xml = []
    for param in func_info['params']:
        galaxy_type = get_python_type_to_galaxy(param['type'])

        if galaxy_type['type'] == 'data':
            fmt = galaxy_type['format'] or 'data'
            optional = 'optional="true"' if not param['required'] else ''
            inputs_xml.append(f'''        <param name="{param['name']}" type="data" format="{fmt}" label="{param['name'].replace('_', ' ').title()}" help="{param['description']}" {optional}/>''')
        elif galaxy_type['type'] == 'boolean':
            checked = 'checked="true"' if param['default'] else ''
            inputs_xml.append(f'''        <param name="{param['name']}" type="boolean" truevalue="true" falsevalue="false" label="{param['name'].replace('_', ' ').title()}" help="{param['description']}" {checked}/>''')
        elif galaxy_type['type'] == 'integer':
            default_val = f'value="{param["default"]}"' if param['default'] is not None else ''
            optional = 'optional="true"' if not param['required'] else ''
            inputs_xml.append(f'''        <param name="{param['name']}" type="integer" label="{param['name'].replace('_', ' ').title()}" help="{param['description']}" {default_val} {optional}/>''')
        elif galaxy_type['type'] == 'float':
            default_val = f'value="{param["default"]}"' if param['default'] is not None else ''
            optional = 'optional="true"' if not param['required'] else ''
            inputs_xml.append(f'''        <param name="{param['name']}" type="float" label="{param['name'].replace('_', ' ').title()}" help="{param['description']}" {default_val} {optional}/>''')
        else:
            default_val = f'value="{param["default"]}"' if param['default'] is not None else ''
            optional = 'optional="true"' if not param['required'] else ''
            inputs_xml.append(f'''        <param name="{param['name']}" type="text" label="{param['name'].replace('_', ' ').title()}" help="{param['description']}" {default_val} {optional}/>''')

    # Build command arguments
    cmd_args = []
    for param in func_info['params']:
        galaxy_type = get_python_type_to_galaxy(param['type'])
        if galaxy_type['type'] == 'data':
            cmd_args.append(f"--{param['name']} '${param['name']}'")
        elif galaxy_type['type'] == 'boolean':
            cmd_args.append(f"#if ${param['name']}\n    --{param['name']}\n#end if")
        else:
            if param['required']:
                cmd_args.append(f"--{param['name']} '${param['name']}'")
            else:
                cmd_args.append(f"#if ${param['name']}\n    --{param['name']} '${param['name']}'\n#end if")

    xml = f'''<?xml version="1.0"?>
<tool id="{tool_id}" name="{tool_name}" version="1.0.0">
    <description>{func_info['summary']}</description>
    <requirements>
        <container type="docker">biomate/biomni-tools:latest</container>
    </requirements>
    <command detect_errors="exit_code"><![CDATA[
python -c "
import sys
import json
from biomni.tool.{domain} import {func_info['name']}

# Parse arguments
args = {{}}
i = 1
while i < len(sys.argv):
    if sys.argv[i].startswith('--'):
        key = sys.argv[i][2:]
        if i + 1 < len(sys.argv) and not sys.argv[i + 1].startswith('--'):
            val = sys.argv[i + 1]
            # Type conversion
            if val.lower() == 'true': val = True
            elif val.lower() == 'false': val = False
            else:
                try: val = int(val)
                except:
                    try: val = float(val)
                    except: pass
            args[key] = val
            i += 2
        else:
            args[key] = True
            i += 1
    else:
        i += 1

# Call function
result = {func_info['name']}(**args)

# Write output
output_path = args.get('output', '/dev/stdout')
with open(output_path, 'w') as f:
    if isinstance(result, str):
        f.write(result)
    elif isinstance(result, (dict, list)):
        json.dump(result, f, indent=2, default=str)
    else:
        f.write(str(result))
" --output '$output'
    {chr(10).join(cmd_args)}
]]></command>
    <inputs>
{chr(10).join(inputs_xml)}
    </inputs>
    <outputs>
        <data name="output" format="txt" label="${{tool.name}} on ${{on_string}}"/>
    </outputs>
    <help><![CDATA[
**{tool_name}**

{func_info['docstring']}

**Domain**: {domain}
**Function**: {func_info['name']}
]]></help>
</tool>
'''
    return xml


def generate_wrapper_script() -> str:
    """Generate the Python wrapper script that Galaxy will call."""
    return '''#!/usr/bin/env python3
"""
Biomni Galaxy Wrapper Script

This script is called by Galaxy tool wrappers to execute Biomni functions.
"""

import argparse
import importlib
import json
import sys
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description='Execute Biomni function')
    parser.add_argument('--function', required=True, help='Function to call (domain.function_name)')
    parser.add_argument('--output', required=True, help='Output file path')

    # Parse known args, rest are function parameters
    args, unknown = parser.parse_known_args()

    # Parse function parameters
    func_args = {}
    i = 0
    while i < len(unknown):
        if unknown[i].startswith('--'):
            param_name = unknown[i][2:]
            if i + 1 < len(unknown) and not unknown[i + 1].startswith('--'):
                value = unknown[i + 1]
                # Try to parse as JSON for lists/dicts
                try:
                    value = json.loads(value)
                except:
                    # Try to convert to int/float/bool
                    if value.lower() == 'true':
                        value = True
                    elif value.lower() == 'false':
                        value = False
                    else:
                        try:
                            value = int(value)
                        except:
                            try:
                                value = float(value)
                            except:
                                pass
                func_args[param_name] = value
                i += 2
            else:
                # Flag without value (boolean)
                func_args[param_name] = True
                i += 1
        else:
            i += 1

    # Import and call the function
    domain, func_name = args.function.split('.')

    try:
        module = importlib.import_module(f'biomni.tool.{domain}')
        func = getattr(module, func_name)

        # Call function
        result = func(**func_args)

        # Write output
        with open(args.output, 'w') as f:
            if isinstance(result, str):
                f.write(result)
            elif isinstance(result, (dict, list)):
                json.dump(result, f, indent=2, default=str)
            else:
                f.write(str(result))

        print(f"Successfully executed {args.function}")

    except Exception as e:
        print(f"Error executing {args.function}: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
'''


def extract_functions_from_file(py_file: Path) -> list:
    """Extract all public functions from a Python file."""
    with open(py_file, 'r') as f:
        source = f.read()

    tree = ast.parse(source)
    functions = []

    for node in ast.walk(tree):
        if isinstance(node, ast.FunctionDef):
            if not node.name.startswith('_'):
                func_info = parse_function_signature(node)
                functions.append(func_info)

    return functions


def main():
    biomni_tool_dir = Path("/home/yzhang/biomate/Biomni/biomni/tool")
    output_dir = Path("/home/yzhang/biomate/Biomni/biomni_galaxy/tools/biomni")

    # Create output directory
    output_dir.mkdir(parents=True, exist_ok=True)

    # Write wrapper script
    wrapper_path = output_dir / "biomni_wrapper.py"
    with open(wrapper_path, 'w') as f:
        f.write(generate_wrapper_script())
    print(f"Created wrapper script: {wrapper_path}")

    # Process each domain file
    skip_files = {'__init__.py', 'tool_registry.py', 'support_tools.py'}
    total_tools = 0

    tool_conf_sections = []

    for py_file in sorted(biomni_tool_dir.glob("*.py")):
        if py_file.name in skip_files:
            continue

        domain = py_file.stem
        functions = extract_functions_from_file(py_file)

        if not functions:
            continue

        # Create domain subdirectory
        domain_dir = output_dir / domain
        domain_dir.mkdir(exist_ok=True)

        tool_files = []

        for func in functions:
            xml_content = generate_xml_tool(func, domain)
            xml_path = domain_dir / f"{func['name']}.xml"

            with open(xml_path, 'w') as f:
                f.write(xml_content)

            tool_files.append(f"biomni/{domain}/{func['name']}.xml")
            total_tools += 1

        # Track for tool_conf.xml
        tool_conf_sections.append({
            'domain': domain,
            'tools': tool_files
        })

        print(f"Generated {len(functions)} tools for {domain}")

    # Generate tool_conf.xml section
    tool_conf_path = output_dir / "tool_conf_biomni.xml"
    with open(tool_conf_path, 'w') as f:
        f.write('<?xml version="1.0"?>\n')
        f.write('<toolbox>\n')
        f.write('  <section id="biomni" name="Biomni Tools">\n')
        for section in tool_conf_sections:
            f.write(f'    <section id="biomni_{section["domain"]}" name="{section["domain"].title()}">\n')
            for tool in section['tools']:
                f.write(f'      <tool file="{tool}"/>\n')
            f.write('    </section>\n')
        f.write('  </section>\n')
        f.write('</toolbox>\n')

    print(f"\nGenerated {total_tools} Galaxy tool wrappers")
    print(f"Tool conf section: {tool_conf_path}")


if __name__ == "__main__":
    main()
