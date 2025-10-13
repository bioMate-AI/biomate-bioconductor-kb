#!/usr/bin/env python3
"""
Extract all tool functions from bioMni with descriptions and parameters.
This will help identify which tools can be added to BioMate/Galaxy.
"""

import re
import json
from pathlib import Path
from typing import Dict, List, Any

class BioMniFunctionExtractor:
    def __init__(self, biomni_path: str = "/Users/jingqiwang/biomni"):
        self.biomni_path = Path(biomni_path)
        self.tool_dir = self.biomni_path / "biomni" / "tool"

    def extract_function_info(self, file_path: Path) -> List[Dict[str, Any]]:
        """Extract function definitions and their decorators/docstrings"""
        functions = []

        with open(file_path, 'r') as f:
            content = f.read()

        # Find all functions with @tool decorator
        pattern = r'@tool\([^)]*\)\s*\ndef\s+(\w+)\s*\((.*?)\)\s*(?:->.*?)?\s*:\s*"""(.*?)"""'
        matches = re.finditer(pattern, content, re.DOTALL)

        for match in matches:
            func_name = match.group(1)
            params = match.group(2).strip()
            docstring = match.group(3).strip()

            # Extract description (first line of docstring)
            desc_lines = [line.strip() for line in docstring.split('\n') if line.strip()]
            description = desc_lines[0] if desc_lines else ""

            # Parse parameters
            param_list = []
            for param in params.split(','):
                param = param.strip()
                if param and param != 'self':
                    # Extract parameter name and type hint
                    if ':' in param:
                        name, type_hint = param.split(':', 1)
                        name = name.strip()
                        type_hint = type_hint.split('=')[0].strip()
                        param_list.append({'name': name, 'type': type_hint})
                    else:
                        param_list.append({'name': param.split('=')[0].strip(), 'type': 'Any'})

            functions.append({
                'name': func_name,
                'description': description,
                'parameters': param_list,
                'module': file_path.stem,
                'full_docstring': docstring
            })

        # Also find functions without @tool decorator but are still public
        pattern_no_decorator = r'^def\s+([a-z]\w+)\s*\((.*?)\)\s*(?:->.*?)?\s*:\s*"""(.*?)"""'
        matches_no_dec = re.finditer(pattern_no_decorator, content, re.MULTILINE | re.DOTALL)

        for match in matches_no_dec:
            func_name = match.group(1)
            # Skip if already found with decorator
            if any(f['name'] == func_name for f in functions):
                continue
            # Skip private functions
            if func_name.startswith('_'):
                continue

            params = match.group(2).strip()
            docstring = match.group(3).strip()

            desc_lines = [line.strip() for line in docstring.split('\n') if line.strip()]
            description = desc_lines[0] if desc_lines else ""

            param_list = []
            for param in params.split(','):
                param = param.strip()
                if param and param != 'self':
                    if ':' in param:
                        name, type_hint = param.split(':', 1)
                        name = name.strip()
                        type_hint = type_hint.split('=')[0].strip()
                        param_list.append({'name': name, 'type': type_hint})
                    else:
                        param_list.append({'name': param.split('=')[0].strip(), 'type': 'Any'})

            functions.append({
                'name': func_name,
                'description': description,
                'parameters': param_list,
                'module': file_path.stem,
                'full_docstring': docstring,
                'has_tool_decorator': False
            })

        return functions

    def extract_all_functions(self) -> Dict[str, List[Dict[str, Any]]]:
        """Extract functions from all tool modules"""
        all_functions = {}

        for py_file in self.tool_dir.glob("*.py"):
            if py_file.name == '__init__.py':
                continue
            if py_file.name == 'tool_registry.py':
                continue

            functions = self.extract_function_info(py_file)
            if functions:
                all_functions[py_file.stem] = functions

        return all_functions

    def generate_report(self, output_file: str = "BIOMNI_FUNCTIONS_ANALYSIS_2025-10-13.md"):
        """Generate comprehensive markdown report"""
        all_functions = self.extract_all_functions()

        # Count totals
        total_modules = len(all_functions)
        total_functions = sum(len(funcs) for funcs in all_functions.values())

        with open(output_file, 'w') as f:
            f.write("# BioMni Tool Functions Analysis (2025-10-13)\n\n")
            f.write("## Executive Summary\n\n")
            f.write(f"**Total modules:** {total_modules}\n")
            f.write(f"**Total tool functions:** {total_functions}\n\n")

            # Summary by module
            f.write("## Functions by Module\n\n")
            f.write("| Module | Functions | Category |\n")
            f.write("|--------|-----------|----------|\n")

            module_categories = {
                'database': 'Database Query APIs',
                'pharmacology': 'Drug & Pharmacology',
                'genomics': 'Genomics & Sequencing',
                'molecular_biology': 'Molecular Biology',
                'genetics': 'Genetics & Variants',
                'immunology': 'Immunology & Immune System',
                'microbiology': 'Microbiology & Pathogens',
                'cancer_biology': 'Cancer Biology',
                'cell_biology': 'Cell Biology',
                'biochemistry': 'Biochemistry & Metabolism',
                'systems_biology': 'Systems & Network Biology',
                'synthetic_biology': 'Synthetic Biology',
                'bioengineering': 'Bioengineering',
                'pathology': 'Pathology & Disease',
                'physiology': 'Physiology',
                'biophysics': 'Biophysics',
                'literature': 'Literature & Publications',
                'support_tools': 'Support Tools'
            }

            for module in sorted(all_functions.keys(), key=lambda x: len(all_functions[x]), reverse=True):
                func_count = len(all_functions[module])
                category = module_categories.get(module, 'Other')
                f.write(f"| **{module}** | {func_count} | {category} |\n")

            # Detailed function listings
            f.write("\n## Detailed Function Listings\n\n")

            for module in sorted(all_functions.keys()):
                functions = all_functions[module]
                category = module_categories.get(module, 'Other')

                f.write(f"\n### {module.replace('_', ' ').title()} ({len(functions)} functions)\n")
                f.write(f"**Category:** {category}\n\n")

                for i, func in enumerate(functions, 1):
                    f.write(f"{i}. **`{func['name']}`**\n")
                    f.write(f"   - **Description:** {func['description']}\n")

                    if func['parameters']:
                        param_str = ', '.join([f"{p['name']}: {p['type']}" for p in func['parameters']])
                        f.write(f"   - **Parameters:** {param_str}\n")
                    else:
                        f.write(f"   - **Parameters:** None\n")

                    if not func.get('has_tool_decorator', True):
                        f.write(f"   - **Note:** No @tool decorator (may be internal)\n")

                    f.write("\n")

            # Galaxy integration recommendations
            f.write("\n## Recommendations for Galaxy Integration\n\n")

            f.write("### Priority 1: Database Query APIs (Database Module)\n\n")
            db_funcs = all_functions.get('database', [])
            f.write(f"**{len(db_funcs)} functions** providing direct database access:\n\n")
            for func in db_funcs[:10]:  # First 10
                f.write(f"- `{func['name']}`: {func['description']}\n")
            if len(db_funcs) > 10:
                f.write(f"\n... and {len(db_funcs) - 10} more database query functions\n")

            f.write("\n**These should be converted to Galaxy tool wrappers as they:**\n")
            f.write("- Provide unique database access not available in Galaxy\n")
            f.write("- Return structured data that can be used in workflows\n")
            f.write("- Don't require complex tool installations\n\n")

            f.write("### Priority 2: Pharmacology & Drug Discovery\n\n")
            pharm_funcs = all_functions.get('pharmacology', [])
            f.write(f"**{len(pharm_funcs)} functions** for drug discovery and pharmacology:\n\n")
            for func in pharm_funcs[:10]:
                f.write(f"- `{func['name']}`: {func['description']}\n")
            if len(pharm_funcs) > 10:
                f.write(f"\n... and {len(pharm_funcs) - 10} more pharmacology functions\n")

            f.write("\n### Priority 3: Genomics & Molecular Biology\n\n")
            genomics_funcs = all_functions.get('genomics', []) + all_functions.get('molecular_biology', [])
            f.write(f"**{len(genomics_funcs)} functions** for sequence analysis and molecular data:\n\n")
            for func in genomics_funcs[:10]:
                f.write(f"- `{func['name']}`: {func['description']}\n")

            f.write("\n## Implementation Strategy\n\n")
            f.write("1. **Database APIs** → Galaxy Data Source tools\n")
            f.write("   - Wrap Python functions in Galaxy XML\n")
            f.write("   - Return tabular/JSON outputs\n")
            f.write("   - 31 priority functions\n\n")

            f.write("2. **Analysis Functions** → Galaxy Tools\n")
            f.write("   - Convert to standalone Galaxy tools\n")
            f.write("   - Add proper input/output handling\n")
            f.write("   - ~50-70 high-value functions\n\n")

            f.write("3. **Data Lakes** → Galaxy Data Libraries\n")
            f.write("   - Expose pre-computed datasets\n")
            f.write("   - 79 curated datasets\n\n")

            f.write("**Total potential tools to add:** ~150+ Galaxy wrappers\n\n")

            f.write("---\n")
            f.write("*Generated: 2025-10-13*\n")
            f.write(f"*Source: bioMni {self.biomni_path}*\n")

        # Also save JSON for programmatic access
        json_output = f"{output_file.replace('.md', '.json')}"
        with open(json_output, 'w') as f:
            json.dump(all_functions, f, indent=2)

        print(f"Generated report: {output_file}")
        print(f"Generated JSON: {json_output}")
        print(f"\nTotal modules: {total_modules}")
        print(f"Total functions: {total_functions}")

        return all_functions

if __name__ == "__main__":
    extractor = BioMniFunctionExtractor()
    functions = extractor.generate_report()

    print("\nTop modules by function count:")
    sorted_modules = sorted(functions.items(), key=lambda x: len(x[1]), reverse=True)
    for module, funcs in sorted_modules[:10]:
        print(f"  {module}: {len(funcs)} functions")
