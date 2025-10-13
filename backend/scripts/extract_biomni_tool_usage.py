#!/usr/bin/env python3
"""
Extract Actual Tool Usage from BioMni Code

Parses the 258 BioMni functions to extract which actual bioinformatics tools
and library functions are called internally.
"""

import ast
import json
import re
from pathlib import Path
from collections import defaultdict
from typing import Dict, List, Set, Tuple


class BioMniToolExtractor(ast.NodeVisitor):
    """AST visitor to extract tool and library usage from BioMni code."""

    def __init__(self):
        self.imports = set()  # Imported modules
        self.function_calls = defaultdict(set)  # module.function calls
        self.subprocess_calls = []  # Command-line tool calls
        self.current_function = None

    def visit_Import(self, node):
        """Track import statements."""
        for alias in node.names:
            self.imports.add(alias.name)
        self.generic_visit(node)

    def visit_ImportFrom(self, node):
        """Track 'from X import Y' statements."""
        if node.module:
            self.imports.add(node.module)
            for alias in node.names:
                self.imports.add(f"{node.module}.{alias.name}")
        self.generic_visit(node)

    def visit_FunctionDef(self, node):
        """Track function definitions."""
        old_function = self.current_function
        self.current_function = node.name
        self.generic_visit(node)
        self.current_function = old_function

    def visit_Call(self, node):
        """Track function calls."""
        # Extract function name
        func_name = self._get_call_name(node.func)

        if func_name:
            # Check for subprocess calls
            if any(cmd in func_name for cmd in ['subprocess', 'os.system', 'os.popen', 'Popen']):
                # Try to extract command
                if node.args:
                    cmd = self._extract_command(node.args[0])
                    if cmd:
                        self.subprocess_calls.append({
                            'function': self.current_function,
                            'command': cmd,
                            'call': func_name
                        })

            # Track library function calls (e.g., sc.tl.rank_genes_groups)
            if '.' in func_name:
                parts = func_name.split('.')
                if len(parts) >= 2:
                    module = parts[0]
                    method = '.'.join(parts[1:])
                    self.function_calls[module].add(method)

        self.generic_visit(node)

    def _get_call_name(self, node) -> str:
        """Recursively extract function call name."""
        if isinstance(node, ast.Name):
            return node.id
        elif isinstance(node, ast.Attribute):
            value = self._get_call_name(node.value)
            return f"{value}.{node.attr}" if value else node.attr
        return ""

    def _extract_command(self, node) -> str:
        """Extract command string from argument."""
        if isinstance(node, ast.Constant):
            return node.value
        elif isinstance(node, ast.Str):  # Python < 3.8
            return node.s
        elif isinstance(node, ast.JoinedStr):  # f-string
            parts = []
            for value in node.values:
                if isinstance(value, ast.Constant):
                    parts.append(str(value.value))
                else:
                    parts.append("{}")
            return ''.join(parts)
        return ""


def analyze_biomni_module(module_path: Path) -> Dict:
    """Analyze a single BioMni module file."""
    try:
        with open(module_path) as f:
            tree = ast.parse(f.read())

        extractor = BioMniToolExtractor()
        extractor.visit(tree)

        return {
            'file': module_path.name,
            'imports': sorted(list(extractor.imports)),
            'function_calls': {k: sorted(list(v)) for k, v in extractor.function_calls.items()},
            'subprocess_calls': extractor.subprocess_calls
        }
    except Exception as e:
        print(f"⚠️  Error parsing {module_path.name}: {e}")
        return {
            'file': module_path.name,
            'error': str(e)
        }


def categorize_tools(all_imports: Set[str], all_function_calls: Dict) -> Dict:
    """Categorize extracted tools into bioinformatics vs general libraries."""

    # Known bioinformatics tools and libraries
    bioinformatics_packages = {
        'scanpy', 'anndata', 'scrublet', 'scvi', 'pyscenic', 'cellpose',
        'gget', 'gseapy', 'pydeseq2', 'edger', 'limma',
        'biopython', 'Bio', 'biotite', 'biopandas',
        'pysam', 'pybedtools', 'pyfaidx', 'cyvcf2',
        'skbio', 'qiime2', 'biom',
        'rdkit', 'deeppurpose', 'descriptastorus',
        'cooler', 'fanc', 'hicstraw',
        'cellxgene', 'cellxgene_census',
        'cobra', 'cobrapy',
        'msprime', 'tskit',
        'cryosparc', 'cryosparc_tools',
        'flowkit', 'flowio',
        'autosite', 'pymol',
        'igraph', 'graph_tool', 'networkit',
        'snakemake', 'nextflow',
    }

    bioinformatics_r_packages = {
        'DESeq2', 'edgeR', 'limma', 'clusterProfiler',
        'Seurat', 'Monocle', 'SingleCellExperiment',
        'WGCNA', 'ggplot2', 'dplyr', 'tidyr',
    }

    command_line_tools = {
        'samtools', 'bcftools', 'bedtools', 'vcftools',
        'bwa', 'bowtie', 'bowtie2', 'hisat2', 'star',
        'salmon', 'kallisto', 'featureCounts',
        'fastqc', 'multiqc', 'trimmomatic', 'cutadapt',
        'blast', 'blat', 'diamond', 'hmmer',
        'mafft', 'muscle', 'clustalw', 'iqtree', 'raxml',
        'gatk', 'picard', 'freebayes', 'varscan',
        'macs2', 'homer', 'epic2', 'sicer',
        'deeptools', 'ucsc', 'kent',
    }

    bio_tools = {
        'python_libraries': [],
        'r_packages': [],
        'command_line_tools': [],
        'other': []
    }

    # Categorize imports
    for imp in all_imports:
        base_module = imp.split('.')[0]

        if base_module in bioinformatics_packages:
            bio_tools['python_libraries'].append(imp)
        elif base_module in bioinformatics_r_packages:
            bio_tools['r_packages'].append(imp)
        elif base_module in command_line_tools:
            bio_tools['command_line_tools'].append(imp)

    # Categorize function calls
    for module, functions in all_function_calls.items():
        if module in bioinformatics_packages:
            for func in functions:
                bio_tools['python_libraries'].append(f"{module}.{func}")

    return bio_tools


def main():
    print("=" * 80)
    print("EXTRACTING TOOL USAGE FROM BIOMNI CODE")
    print("=" * 80)

    biomni_tool_dir = Path("/Users/jingqiwang/Biomni/biomni/tool")

    if not biomni_tool_dir.exists():
        print(f"❌ BioMni tool directory not found: {biomni_tool_dir}")
        return

    # Analyze all modules
    print(f"\n1. Analyzing BioMni modules in {biomni_tool_dir}...")
    module_analyses = []
    all_imports = set()
    all_function_calls = defaultdict(set)
    all_subprocess_calls = []

    for module_file in sorted(biomni_tool_dir.glob("*.py")):
        if module_file.stem.startswith('_'):
            continue

        print(f"   Analyzing {module_file.name}...", end=" ")
        analysis = analyze_biomni_module(module_file)

        if 'error' not in analysis:
            module_analyses.append(analysis)
            all_imports.update(analysis['imports'])
            for module, funcs in analysis['function_calls'].items():
                all_function_calls[module].update(funcs)
            all_subprocess_calls.extend(analysis['subprocess_calls'])
            print(f"✓ ({len(analysis['imports'])} imports, {len(analysis['subprocess_calls'])} subprocess calls)")
        else:
            print(f"✗ {analysis['error']}")

    print(f"\n2. Categorizing extracted tools...")
    categorized = categorize_tools(all_imports, all_function_calls)

    print(f"   Python libraries: {len(categorized['python_libraries'])}")
    print(f"   R packages: {len(categorized['r_packages'])}")
    print(f"   Command-line tools: {len(categorized['command_line_tools'])}")
    print(f"   Subprocess calls: {len(all_subprocess_calls)}")

    # Build complete report
    report = {
        "metadata": {
            "timestamp": "2025-10-13",
            "source": str(biomni_tool_dir),
            "modules_analyzed": len(module_analyses)
        },
        "summary": {
            "total_imports": len(all_imports),
            "total_function_calls": sum(len(v) for v in all_function_calls.values()),
            "total_subprocess_calls": len(all_subprocess_calls),
            "bioinformatics_python_libraries": len(categorized['python_libraries']),
            "bioinformatics_r_packages": len(categorized['r_packages']),
            "command_line_tools": len(categorized['command_line_tools'])
        },
        "categorized_tools": categorized,
        "all_imports": sorted(list(all_imports)),
        "all_function_calls": {k: sorted(list(v)) for k, v in all_function_calls.items()},
        "subprocess_calls": all_subprocess_calls,
        "module_details": module_analyses
    }

    # Save report
    output_file = Path("backend/BIOMNI_TOOL_USAGE_EXTRACTION_2025-10-13.json")
    with open(output_file, 'w') as f:
        json.dump(report, f, indent=2)

    print(f"\n3. Saved extraction report to: {output_file}")

    # Print summary
    print("\n" + "=" * 80)
    print("EXTRACTION SUMMARY")
    print("=" * 80)
    print(f"Modules analyzed: {len(module_analyses)}")
    print(f"Total imports: {len(all_imports)}")
    print(f"Total function calls: {sum(len(v) for v in all_function_calls.values())}")
    print()
    print("Bioinformatics Tools Found:")
    print(f"  Python libraries: {len(categorized['python_libraries'])}")
    print(f"  R packages: {len(categorized['r_packages'])}")
    print(f"  Command-line tools: {len(categorized['command_line_tools'])}")
    print(f"  Subprocess calls: {len(all_subprocess_calls)}")
    print()

    # Show top Python libraries
    print("Top Python bioinformatics libraries used:")
    py_libs = defaultdict(int)
    for lib in categorized['python_libraries']:
        base = lib.split('.')[0]
        py_libs[base] += 1

    for lib, count in sorted(py_libs.items(), key=lambda x: x[1], reverse=True)[:15]:
        print(f"  {lib}: {count} calls")

    print("\n" + "=" * 80)
    print("✅ EXTRACTION COMPLETE")
    print("=" * 80)
    print("\nNext steps:")
    print("1. Map extracted tools to Galaxy tool equivalents")
    print("2. Check which tools are missing from Galaxy")
    print("3. Generate Galaxy wrappers for missing tool-functions")


if __name__ == "__main__":
    main()
