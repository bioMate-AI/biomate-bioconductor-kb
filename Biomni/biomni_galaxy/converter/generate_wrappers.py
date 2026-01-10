#!/usr/bin/env python3
"""
Generate Python wrapper scripts for all Biomni Galaxy tools.

This script creates Galaxy-compatible Python wrappers for each Biomni function
that can be executed independently or within a Galaxy workflow.
"""

import ast
import os
import sys
from pathlib import Path

BIOMNI_ROOT = Path(__file__).parent.parent.parent
TOOLS_PATH = BIOMNI_ROOT / "biomni_galaxy" / "tools"
BIOMNI_TOOL_PATH = BIOMNI_ROOT / "biomni" / "tool"

DOMAINS = [
    "biochemistry", "bioengineering", "biophysics", "cancer_biology", "cell_biology",
    "database", "genetics", "genomics", "glycoengineering", "immunology",
    "lab_automation", "literature", "microbiology", "molecular_biology", "pathology",
    "pharmacology", "physiology", "protocols", "support_tools", "synthetic_biology",
    "systems_biology"
]


def extract_function_info(domain: str, func_name: str):
    """Extract function signature and docstring from source."""
    domain_file = BIOMNI_TOOL_PATH / f"{domain}.py"
    if not domain_file.exists():
        return None

    with open(domain_file, "r") as f:
        content = f.read()

    try:
        tree = ast.parse(content)
    except SyntaxError:
        return None

    for node in ast.walk(tree):
        if isinstance(node, ast.FunctionDef) and node.name == func_name:
            params = []
            defaults = node.args.defaults
            num_defaults = len(defaults)
            num_args = len(node.args.args)

            for i, arg in enumerate(node.args.args):
                param = {
                    "name": arg.arg,
                    "type": ast.unparse(arg.annotation) if arg.annotation else "str",
                    "required": i < (num_args - num_defaults)
                }

                if i >= (num_args - num_defaults):
                    default_idx = i - (num_args - num_defaults)
                    try:
                        param["default"] = ast.literal_eval(ast.unparse(defaults[default_idx]))
                    except (ValueError, SyntaxError):
                        param["default"] = ast.unparse(defaults[default_idx])
                else:
                    param["default"] = None

                params.append(param)

            docstring = ""
            if (node.body and isinstance(node.body[0], ast.Expr) and
                isinstance(node.body[0].value, ast.Constant)):
                docstring = node.body[0].value.value

            return {
                "name": func_name,
                "domain": domain,
                "params": params,
                "docstring": docstring
            }

    return None


def generate_wrapper(func_info: dict) -> str:
    """Generate a Python wrapper script for a Biomni function."""
    domain = func_info["domain"]
    func_name = func_info["name"]
    params = func_info["params"]
    docstring = func_info["docstring"] or f"Galaxy wrapper for {func_name}"

    # Build argparse arguments
    arg_lines = []
    for param in params:
        name = param["name"]
        ptype = param["type"]
        required = param["required"]
        default = param["default"]

        if "int" in ptype.lower():
            type_str = "int"
        elif "float" in ptype.lower():
            type_str = "float"
        elif "bool" in ptype.lower():
            type_str = "str"  # Parse as string, convert later
        else:
            type_str = "str"

        if required:
            arg_lines.append(
                f'    parser.add_argument("--{name}", type={type_str}, required=True, help="{name}")'
            )
        else:
            default_repr = repr(default) if default is not None else "None"
            arg_lines.append(
                f'    parser.add_argument("--{name}", type={type_str}, default={default_repr}, help="{name}")'
            )

    args_str = "\n".join(arg_lines)

    # Build kwargs construction
    kwargs_lines = []
    for param in params:
        name = param["name"]
        ptype = param["type"]

        if "bool" in ptype.lower():
            kwargs_lines.append(
                f'    if args.{name} is not None:\n'
                f'        kwargs["{name}"] = str(args.{name}).lower() in ("true", "yes", "1")'
            )
        elif "list" in ptype.lower():
            kwargs_lines.append(
                f'    if args.{name} is not None:\n'
                f'        kwargs["{name}"] = args.{name}.split(",") if isinstance(args.{name}, str) else args.{name}'
            )
        else:
            kwargs_lines.append(
                f'    if args.{name} is not None:\n'
                f'        kwargs["{name}"] = args.{name}'
            )

    kwargs_str = "\n".join(kwargs_lines)

    wrapper = f'''#!/usr/bin/env python3
"""
Galaxy Tool Wrapper: {func_name}

{docstring.split(chr(10))[0] if docstring else "Biomni function wrapper"}

Auto-generated wrapper for Galaxy integration.
"""

import argparse
import json
import os
import sys

# Add Biomni to path
sys.path.insert(0, os.environ.get('BIOMNI_HOME', '/opt/biomni/src'))

from biomni.tool.{domain} import {func_name}


def main():
    parser = argparse.ArgumentParser(
        description="""{docstring.split(chr(10))[0] if docstring else func_name}"""
    )

    # Input parameters
{args_str}

    # Output
    parser.add_argument("--output", "-o", required=True, help="Output file")

    args = parser.parse_args()

    # Build kwargs
    kwargs = {{}}
{kwargs_str}

    try:
        # Call the Biomni function
        result = {func_name}(**kwargs)

        # Write output
        with open(args.output, 'w') as f:
            if isinstance(result, (dict, list)):
                json.dump(result, f, indent=2, default=str)
            else:
                f.write(str(result))

        print(f"Output written to {{args.output}}")

    except Exception as e:
        print(f"Error: {{e}}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
'''
    return wrapper


def generate_all_wrappers():
    """Generate wrappers for all functions in all domains."""
    generated = 0
    skipped = 0

    for domain in DOMAINS:
        domain_file = BIOMNI_TOOL_PATH / f"{domain}.py"
        if not domain_file.exists():
            print(f"Skipping domain {domain} - file not found")
            continue

        # Get all function names from the XML files we already generated
        xml_dir = TOOLS_PATH / domain
        if not xml_dir.exists():
            continue

        for xml_file in xml_dir.glob("*.xml"):
            func_name = xml_file.stem
            py_file = xml_dir / f"{func_name}.py"

            # Skip if wrapper already exists
            if py_file.exists():
                skipped += 1
                continue

            func_info = extract_function_info(domain, func_name)
            if func_info is None:
                print(f"  Could not extract info for {domain}/{func_name}")
                continue

            wrapper = generate_wrapper(func_info)

            with open(py_file, "w") as f:
                f.write(wrapper)

            os.chmod(py_file, 0o755)
            generated += 1
            print(f"  Generated: {domain}/{func_name}.py")

    print(f"\nGenerated {generated} wrappers, skipped {skipped} existing")


if __name__ == "__main__":
    generate_all_wrappers()
