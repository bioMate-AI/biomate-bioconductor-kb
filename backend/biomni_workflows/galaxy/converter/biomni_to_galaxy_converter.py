#!/usr/bin/env python3
"""
Biomni to Galaxy Converter

Converts Biomni functions to Galaxy tool XML and subworkflow JSON.
Each Biomni function represents a biological logic unit that becomes a Galaxy subworkflow.

Author: BioMate Development Team
Date: November 29, 2025
"""

import ast
import inspect
import json
import os
import re
import sys
from pathlib import Path
from typing import Any

# Add biomni to path
BIOMNI_ROOT = Path(__file__).parent.parent.parent
sys.path.insert(0, str(BIOMNI_ROOT))


class BiomniFunction:
    """Represents a parsed Biomni function with its metadata."""

    def __init__(self, name: str, domain: str, line_number: int):
        self.name = name
        self.domain = domain
        self.line_number = line_number
        self.docstring = ""
        self.parameters = []
        self.return_type = "Any"
        self.internal_calls = []
        self.complexity = "Medium"
        self.tool_type = "python_wrapper"

    def to_dict(self) -> dict:
        return {
            "name": self.name,
            "domain": self.domain,
            "line_number": self.line_number,
            "docstring": self.docstring,
            "parameters": self.parameters,
            "return_type": self.return_type,
            "internal_calls": self.internal_calls,
            "complexity": self.complexity,
            "tool_type": self.tool_type
        }


class BiomniParser:
    """Parses Biomni tool files to extract function metadata."""

    DOMAINS = [
        "genomics", "database", "molecular_biology", "pharmacology",
        "immunology", "genetics", "microbiology", "bioengineering",
        "synthetic_biology", "cancer_biology", "physiology", "pathology",
        "biochemistry", "systems_biology", "cell_biology", "biophysics",
        "glycoengineering", "literature", "protocols", "support_tools",
        "lab_automation"
    ]

    def __init__(self, biomni_path: Path):
        self.biomni_path = biomni_path
        self.tool_path = biomni_path / "biomni" / "tool"

    def parse_all_domains(self) -> list[BiomniFunction]:
        """Parse all Biomni tool files and extract functions."""
        all_functions = []

        for domain in self.DOMAINS:
            domain_file = self.tool_path / f"{domain}.py"
            if domain_file.exists():
                functions = self.parse_domain_file(domain_file, domain)
                all_functions.extend(functions)

        return all_functions

    def parse_domain_file(self, file_path: Path, domain: str) -> list[BiomniFunction]:
        """Parse a single domain file and extract public functions."""
        functions = []

        with open(file_path, "r") as f:
            content = f.read()

        try:
            tree = ast.parse(content)
        except SyntaxError as e:
            print(f"Warning: Could not parse {file_path}: {e}")
            return functions

        for node in ast.walk(tree):
            if isinstance(node, ast.FunctionDef):
                # Skip private functions
                if node.name.startswith("_"):
                    continue

                func = BiomniFunction(
                    name=node.name,
                    domain=domain,
                    line_number=node.lineno
                )

                # Extract docstring
                if (node.body and isinstance(node.body[0], ast.Expr) and
                    isinstance(node.body[0].value, ast.Constant)):
                    func.docstring = node.body[0].value.value

                # Extract parameters
                func.parameters = self._extract_parameters(node)

                # Extract return type
                if node.returns:
                    func.return_type = ast.unparse(node.returns)

                # Detect internal function calls
                func.internal_calls = self._detect_internal_calls(node, content)

                # Determine complexity and tool type
                func.complexity = self._estimate_complexity(func)
                func.tool_type = self._determine_tool_type(func, content)

                functions.append(func)

        return functions

    def _extract_parameters(self, node: ast.FunctionDef) -> list[dict]:
        """Extract parameter information from function definition."""
        params = []
        defaults = node.args.defaults
        num_defaults = len(defaults)
        num_args = len(node.args.args)

        for i, arg in enumerate(node.args.args):
            param = {
                "name": arg.arg,
                "type": ast.unparse(arg.annotation) if arg.annotation else "Any",
                "required": i < (num_args - num_defaults)
            }

            # Add default value if available
            if i >= (num_args - num_defaults):
                default_idx = i - (num_args - num_defaults)
                default_node = defaults[default_idx]
                try:
                    param["default"] = ast.literal_eval(ast.unparse(default_node))
                except (ValueError, SyntaxError):
                    param["default"] = ast.unparse(default_node)

            params.append(param)

        return params

    def _detect_internal_calls(self, node: ast.FunctionDef, content: str) -> list[str]:
        """Detect calls to other Biomni functions or external tools."""
        calls = []

        for child in ast.walk(node):
            if isinstance(child, ast.Call):
                if isinstance(child.func, ast.Name):
                    calls.append(child.func.id)
                elif isinstance(child.func, ast.Attribute):
                    calls.append(f"{ast.unparse(child.func.value)}.{child.func.attr}")

        # Filter to relevant calls
        relevant_patterns = [
            "subprocess", "requests", "gget", "scanpy", "scipy",
            "sklearn", "Entrez", "align_sequences", "digest_sequence",
            "find_restriction", "macs2", "samtools", "bwa"
        ]

        filtered_calls = []
        for call in calls:
            for pattern in relevant_patterns:
                if pattern.lower() in call.lower():
                    filtered_calls.append(call)
                    break

        return list(set(filtered_calls))

    def _estimate_complexity(self, func: BiomniFunction) -> str:
        """Estimate function complexity based on various factors."""
        score = 0

        # Number of parameters
        score += len(func.parameters) * 0.5

        # Number of internal calls
        score += len(func.internal_calls) * 2

        # Docstring length (indicates complexity)
        if func.docstring:
            score += len(func.docstring) / 500

        # Known complex patterns
        complex_patterns = ["deep", "ml", "llm", "neural", "gpu", "torch", "model"]
        for pattern in complex_patterns:
            if pattern in func.name.lower() or pattern in func.docstring.lower():
                score += 3
                break

        if score < 3:
            return "Low"
        elif score < 7:
            return "Medium"
        else:
            return "High"

    def _determine_tool_type(self, func: BiomniFunction, content: str) -> str:
        """Determine the Galaxy tool type for this function."""
        func_content = self._extract_function_body(func.name, content)

        # Check for CLI tools
        if "subprocess" in func_content:
            return "cli_wrapper"

        # Check for API calls
        if "requests." in func_content or "_API" in str(func.internal_calls):
            return "api_wrapper"

        # Check for ML/DL
        if any(x in func_content.lower() for x in ["torch", "tensorflow", "model.predict"]):
            return "ml_tool"

        # Check for subworkflow (calls other biomni functions)
        biomni_functions = self._get_all_function_names()
        for call in func.internal_calls:
            if call in biomni_functions:
                return "subworkflow"

        # Check for AI/LLM
        if "llm" in func_content.lower() or "claude" in func_content.lower():
            return "ai_workflow"

        # Check for static content
        if "protocol" in func.name.lower() and len(func.internal_calls) == 0:
            return "static"

        return "python_wrapper"

    def _extract_function_body(self, func_name: str, content: str) -> str:
        """Extract the body of a function from source content."""
        pattern = rf"def {func_name}\([^)]*\).*?(?=\ndef |\Z)"
        match = re.search(pattern, content, re.DOTALL)
        return match.group(0) if match else ""

    def _get_all_function_names(self) -> set:
        """Get all public function names across all domains."""
        names = set()
        for domain in self.DOMAINS:
            domain_file = self.tool_path / f"{domain}.py"
            if domain_file.exists():
                with open(domain_file, "r") as f:
                    content = f.read()
                for match in re.finditer(r"^def ([a-z_]+)\(", content, re.MULTILINE):
                    if not match.group(1).startswith("_"):
                        names.add(match.group(1))
        return names


class GalaxyToolGenerator:
    """Generates Galaxy tool XML from Biomni function metadata."""

    # Type mapping from Python to Galaxy
    TYPE_MAP = {
        "str": "text",
        "int": "integer",
        "float": "float",
        "bool": "boolean",
        "list": "text",
        "dict": "text",
        "list[str]": "text",
        "list[int]": "text",
        "list[float]": "text",
        "Any": "text"
    }

    # Format mapping for file types
    FORMAT_MAP = {
        "sequence": "fasta",
        "fasta": "fasta",
        "fastq": "fastq",
        "bam": "bam",
        "vcf": "vcf",
        "pdb": "pdb",
        "h5ad": "h5ad",
        "csv": "tabular",
        "tsv": "tabular",
        "json": "json",
        "image": "png",
        "nii": "nifti1"
    }

    def __init__(self, output_path: Path):
        self.output_path = output_path

    def generate_tool_xml(self, func: BiomniFunction) -> str:
        """Generate Galaxy tool XML for a Biomni function."""
        tool_id = f"biomni_{func.domain}_{func.name}"
        tool_name = func.name.replace("_", " ").title()

        # Extract first line of docstring for description
        description = func.docstring.split("\n")[0] if func.docstring else f"Biomni {tool_name}"

        # Generate inputs section
        inputs_xml = self._generate_inputs(func.parameters)

        # Generate outputs section
        outputs_xml = self._generate_outputs(func)

        # Generate requirements
        requirements_xml = self._generate_requirements(func)

        # Generate command
        command_xml = self._generate_command(func)

        xml = f'''<?xml version="1.0"?>
<tool id="{tool_id}" name="Biomni: {tool_name}" version="1.0.0">
    <description>{description}</description>
    {requirements_xml}
    <command detect_errors="exit_code"><![CDATA[
{command_xml}
    ]]></command>
    <inputs>
{inputs_xml}
    </inputs>
    <outputs>
{outputs_xml}
    </outputs>
    <help><![CDATA[
{func.docstring if func.docstring else "No documentation available."}

**Tool Information**

- Domain: {func.domain}
- Complexity: {func.complexity}
- Type: {func.tool_type}
    ]]></help>
    <citations>
        <citation type="bibtex">
@misc{{biomni2025,
    title={{Biomni: A Comprehensive Biomedical AI Agent}},
    author={{Biomni Team}},
    year={{2025}},
    url={{https://github.com/snap-stanford/Biomni}}
}}
        </citation>
    </citations>
</tool>
'''
        return xml

    def _generate_inputs(self, parameters: list[dict]) -> str:
        """Generate Galaxy inputs XML from parameters."""
        inputs = []

        for param in parameters:
            param_name = param["name"]
            param_type = param.get("type", "Any")
            required = param.get("required", True)
            default = param.get("default")

            # Detect file inputs
            if any(x in param_name.lower() for x in ["file", "path", "data", "input"]):
                galaxy_type = "data"
                format_hint = self._detect_format(param_name, param_type)
                optional = "true" if not required else "false"
                inputs.append(f'        <param name="{param_name}" type="{galaxy_type}" format="{format_hint}" label="{param_name}" optional="{optional}"/>')
            else:
                galaxy_type = self.TYPE_MAP.get(param_type, "text")
                optional = "true" if not required else "false"

                if galaxy_type == "boolean":
                    checked = "true" if default else "false"
                    inputs.append(f'        <param name="{param_name}" type="boolean" truevalue="true" falsevalue="false" checked="{checked}" label="{param_name}"/>')
                elif galaxy_type == "integer":
                    value = default if default is not None else "0"
                    inputs.append(f'        <param name="{param_name}" type="integer" value="{value}" label="{param_name}" optional="{optional}"/>')
                elif galaxy_type == "float":
                    value = default if default is not None else "0.0"
                    inputs.append(f'        <param name="{param_name}" type="float" value="{value}" label="{param_name}" optional="{optional}"/>')
                else:
                    value = default if default is not None else ""
                    inputs.append(f'        <param name="{param_name}" type="text" value="{value}" label="{param_name}" optional="{optional}"/>')

        return "\n".join(inputs) if inputs else '        <param name="input_text" type="text" label="Input"/>'

    def _generate_outputs(self, func: BiomniFunction) -> str:
        """Generate Galaxy outputs XML."""
        # Default to JSON output
        return '        <data name="output" format="json" label="${tool.name} results"/>'

    def _generate_requirements(self, func: BiomniFunction) -> str:
        """Generate Galaxy requirements XML."""
        requirements = ['        <requirement type="package" version="3.11">python</requirement>']

        # Add domain-specific requirements
        domain_requirements = {
            "genomics": ["scanpy", "gseapy"],
            "molecular_biology": ["biopython"],
            "pharmacology": ["rdkit"],
            "bioimaging": ["nibabel", "scikit-image"],
            "systems_biology": ["cobra"]
        }

        if func.domain in domain_requirements:
            for req in domain_requirements[func.domain]:
                requirements.append(f'        <requirement type="package">{req}</requirement>')

        return "    <requirements>\n" + "\n".join(requirements) + "\n    </requirements>"

    def _generate_command(self, func: BiomniFunction) -> str:
        """Generate Galaxy command section."""
        param_args = []
        for param in func.parameters:
            name = param["name"]
            if any(x in name.lower() for x in ["file", "path", "data", "input"]):
                param_args.append(f"--{name} '${{name}}'")
            else:
                param_args.append(f"--{name} '${{{name}}}'")

        args_str = " \\\n            ".join(param_args) if param_args else ""

        return f'''        python '$__tool_directory__/{func.name}.py' \\
            {args_str} \\
            --output '$output'
'''

    def _detect_format(self, param_name: str, param_type: str) -> str:
        """Detect file format from parameter name and type."""
        param_lower = param_name.lower()

        for key, fmt in self.FORMAT_MAP.items():
            if key in param_lower:
                return fmt

        return "data"  # Generic data type

    def save_tool(self, func: BiomniFunction) -> Path:
        """Save Galaxy tool XML to file."""
        domain_dir = self.output_path / func.domain
        domain_dir.mkdir(parents=True, exist_ok=True)

        xml_path = domain_dir / f"{func.name}.xml"
        xml_content = self.generate_tool_xml(func)

        with open(xml_path, "w") as f:
            f.write(xml_content)

        return xml_path


class GalaxySubworkflowGenerator:
    """Generates Galaxy subworkflow JSON from Biomni function metadata."""

    def __init__(self, output_path: Path):
        self.output_path = output_path

    def generate_subworkflow(self, func: BiomniFunction) -> dict:
        """Generate Galaxy subworkflow JSON for a Biomni function."""
        workflow = {
            "a_galaxy_workflow": "true",
            "format-version": "0.1",
            "name": f"biomni_{func.domain}_{func.name}",
            "annotation": func.docstring.split("\n")[0] if func.docstring else "",
            "tags": ["biomni", func.domain, "subworkflow"],
            "steps": {}
        }

        step_id = 0

        # Create input steps for each parameter
        for param in func.parameters:
            if any(x in param["name"].lower() for x in ["file", "path", "data", "input"]):
                workflow["steps"][str(step_id)] = {
                    "type": "data_input",
                    "label": param["name"],
                    "position": {"left": 0, "top": step_id * 100}
                }
                step_id += 1

        # Create tool step
        workflow["steps"][str(step_id)] = {
            "type": "tool",
            "tool_id": f"biomni_{func.domain}_{func.name}",
            "label": func.name,
            "position": {"left": 300, "top": 50},
            "tool_state": {},
            "input_connections": {}
        }

        # Connect inputs to tool
        input_step = 0
        for param in func.parameters:
            if any(x in param["name"].lower() for x in ["file", "path", "data", "input"]):
                workflow["steps"][str(step_id)]["input_connections"][param["name"]] = {
                    "id": input_step,
                    "output_name": "output"
                }
                input_step += 1

        step_id += 1

        # Create output step
        workflow["steps"][str(step_id)] = {
            "type": "tool",
            "tool_id": "cat1",
            "label": "output",
            "position": {"left": 600, "top": 50}
        }

        return workflow

    def save_subworkflow(self, func: BiomniFunction) -> Path:
        """Save Galaxy subworkflow JSON to file."""
        domain_dir = self.output_path / func.domain
        domain_dir.mkdir(parents=True, exist_ok=True)

        json_path = domain_dir / f"{func.name}.ga"
        workflow = self.generate_subworkflow(func)

        with open(json_path, "w") as f:
            json.dump(workflow, f, indent=2)

        return json_path


def main():
    """Main entry point for the converter."""
    import argparse

    parser = argparse.ArgumentParser(description="Convert Biomni functions to Galaxy tools")
    parser.add_argument("--biomni-path", type=Path, default=BIOMNI_ROOT,
                       help="Path to Biomni repository")
    parser.add_argument("--output-path", type=Path,
                       default=BIOMNI_ROOT / "biomni_galaxy" / "tools",
                       help="Output path for Galaxy tools")
    parser.add_argument("--subworkflow-path", type=Path,
                       default=BIOMNI_ROOT / "biomni_galaxy" / "subworkflows",
                       help="Output path for Galaxy subworkflows")
    parser.add_argument("--domain", type=str, default=None,
                       help="Convert only specific domain")
    parser.add_argument("--function", type=str, default=None,
                       help="Convert only specific function")
    parser.add_argument("--list-only", action="store_true",
                       help="Only list functions, don't generate")

    args = parser.parse_args()

    # Parse Biomni functions
    parser = BiomniParser(args.biomni_path)
    functions = parser.parse_all_domains()

    print(f"Found {len(functions)} Biomni functions")

    # Filter if specified
    if args.domain:
        functions = [f for f in functions if f.domain == args.domain]
        print(f"Filtered to {len(functions)} functions in domain '{args.domain}'")

    if args.function:
        functions = [f for f in functions if f.name == args.function]
        print(f"Filtered to function '{args.function}'")

    if args.list_only:
        for func in functions:
            print(f"  {func.domain}/{func.name} ({func.complexity}, {func.tool_type})")
        return

    # Generate Galaxy tools
    tool_generator = GalaxyToolGenerator(args.output_path)
    subworkflow_generator = GalaxySubworkflowGenerator(args.subworkflow_path)

    for func in functions:
        try:
            xml_path = tool_generator.save_tool(func)
            print(f"Generated: {xml_path}")

            json_path = subworkflow_generator.save_subworkflow(func)
            print(f"Generated: {json_path}")
        except Exception as e:
            print(f"Error generating {func.name}: {e}")

    print(f"\nConversion complete! Generated {len(functions)} tools and subworkflows.")


if __name__ == "__main__":
    main()
