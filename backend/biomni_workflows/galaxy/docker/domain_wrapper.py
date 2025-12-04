#!/usr/bin/env python3
"""
Biomni Domain Wrapper

Provides a unified CLI interface to call Biomni tools by domain/function.
Usage: biomni-tool <domain> <function> [args...]

Example:
    biomni-tool molecular_biology annotate_open_reading_frames --sequence "ATGATG..." --min_length 100
    biomni-tool genomics gene_set_enrichment_analysis --genes "TP53,BRCA1,EGFR"
"""

import argparse
import importlib
import inspect
import json
import sys
from typing import Any


DOMAINS = [
    "biochemistry", "bioengineering", "biophysics", "cancer_biology", "cell_biology",
    "database", "genetics", "genomics", "glycoengineering", "immunology",
    "lab_automation", "literature", "microbiology", "molecular_biology", "pathology",
    "pharmacology", "physiology", "protocols", "support_tools", "synthetic_biology",
    "systems_biology"
]


def get_function(domain: str, function_name: str):
    """Import and return a function from a Biomni domain module."""
    try:
        module = importlib.import_module(f"biomni.tool.{domain}")
        func = getattr(module, function_name)
        return func
    except ImportError as e:
        print(f"Error: Could not import domain '{domain}': {e}", file=sys.stderr)
        sys.exit(1)
    except AttributeError:
        print(f"Error: Function '{function_name}' not found in domain '{domain}'", file=sys.stderr)
        sys.exit(1)


def list_functions(domain: str):
    """List all public functions in a domain."""
    try:
        module = importlib.import_module(f"biomni.tool.{domain}")
        functions = []
        for name in dir(module):
            if not name.startswith("_"):
                obj = getattr(module, name)
                if callable(obj) and hasattr(obj, "__module__"):
                    if obj.__module__ == f"biomni.tool.{domain}":
                        doc = obj.__doc__ or ""
                        first_line = doc.split("\n")[0].strip() if doc else "No description"
                        functions.append({"name": name, "description": first_line})
        return functions
    except ImportError as e:
        print(f"Error: Could not import domain '{domain}': {e}", file=sys.stderr)
        return []


def get_function_signature(func) -> dict:
    """Get the signature of a function for argument parsing."""
    sig = inspect.signature(func)
    params = {}
    for name, param in sig.parameters.items():
        param_info = {
            "type": str(param.annotation) if param.annotation != inspect.Parameter.empty else "Any",
            "required": param.default == inspect.Parameter.empty,
            "default": None if param.default == inspect.Parameter.empty else param.default
        }
        params[name] = param_info
    return params


def parse_value(value: str, param_type: str) -> Any:
    """Parse a string value to the appropriate Python type."""
    if value is None:
        return None

    if "int" in param_type.lower():
        return int(value)
    elif "float" in param_type.lower():
        return float(value)
    elif "bool" in param_type.lower():
        return value.lower() in ("true", "yes", "1")
    elif "list" in param_type.lower():
        # Parse comma-separated list
        return [v.strip() for v in value.split(",")]
    elif "dict" in param_type.lower():
        return json.loads(value)
    else:
        # Try to auto-detect type for unannotated parameters
        # Try integer first
        try:
            return int(value)
        except ValueError:
            pass
        # Try float
        try:
            return float(value)
        except ValueError:
            pass
        # Check for boolean strings
        if value.lower() in ("true", "false", "yes", "no"):
            return value.lower() in ("true", "yes")
        # Return as string
        return value


def main():
    parser = argparse.ArgumentParser(
        description="Biomni Domain Wrapper - Call bioinformatics tools by domain/function",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    # List all domains
    biomni-tool --list-domains

    # List functions in a domain
    biomni-tool molecular_biology --list-functions

    # Call a function
    biomni-tool molecular_biology annotate_open_reading_frames --sequence "ATGATG..." --min_length 100

    # Get function help
    biomni-tool molecular_biology annotate_open_reading_frames --help
"""
    )

    parser.add_argument("domain", nargs="?", help="Domain name (e.g., molecular_biology, genomics)")
    parser.add_argument("function", nargs="?", help="Function name")
    parser.add_argument("--list-domains", action="store_true", help="List all available domains")
    parser.add_argument("--list-functions", action="store_true", help="List functions in a domain")
    parser.add_argument("--output", "-o", help="Output file (default: stdout)")
    parser.add_argument("--format", choices=["json", "text"], default="json", help="Output format")

    # Parse known args first to get domain and function
    args, remaining = parser.parse_known_args()

    if args.list_domains:
        print("Available domains:")
        for domain in DOMAINS:
            print(f"  - {domain}")
        return

    if not args.domain:
        parser.print_help()
        return

    if args.domain not in DOMAINS:
        print(f"Error: Unknown domain '{args.domain}'", file=sys.stderr)
        print(f"Available domains: {', '.join(DOMAINS)}", file=sys.stderr)
        sys.exit(1)

    if args.list_functions:
        functions = list_functions(args.domain)
        print(f"Functions in {args.domain}:")
        for func in functions:
            print(f"  - {func['name']}: {func['description']}")
        return

    if not args.function:
        print(f"Error: Please specify a function name", file=sys.stderr)
        print(f"Use --list-functions to see available functions in {args.domain}", file=sys.stderr)
        sys.exit(1)

    # Get the function
    func = get_function(args.domain, args.function)

    # Get function signature
    params = get_function_signature(func)

    # Build argument parser for this function
    func_parser = argparse.ArgumentParser(
        prog=f"biomni-tool {args.domain} {args.function}",
        description=func.__doc__ or f"Call {args.function} from {args.domain}"
    )

    for name, info in params.items():
        if info["required"]:
            func_parser.add_argument(f"--{name}", required=True, help=f"({info['type']}) Required")
        else:
            func_parser.add_argument(f"--{name}", default=info["default"],
                                    help=f"({info['type']}) Default: {info['default']}")

    func_parser.add_argument("--output", "-o", help="Output file (default: stdout)")

    # Parse function arguments
    func_args = func_parser.parse_args(remaining)

    # Build kwargs for function call
    kwargs = {}
    for name, info in params.items():
        value = getattr(func_args, name)
        if value is not None:
            kwargs[name] = parse_value(str(value), info["type"])

    # Call the function
    try:
        result = func(**kwargs)

        # Output result
        if args.format == "json":
            output = json.dumps(result, indent=2, default=str)
        else:
            output = str(result)

        if func_args.output:
            with open(func_args.output, "w") as f:
                f.write(output)
            print(f"Output written to {func_args.output}")
        else:
            print(output)

    except Exception as e:
        print(f"Error executing {args.function}: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
