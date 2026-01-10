#!/usr/bin/env python3
"""
Extract all tool-functions (external library calls) from Biomni code.
This identifies the atomic units that should have XML wrappers in Galaxy.
"""

import ast
import os
import re
from collections import defaultdict
from pathlib import Path

# Known bioinformatics/scientific libraries used by Biomni
KNOWN_TOOLS = {
    # Image processing
    'cv2': 'OpenCV',
    'skimage': 'scikit-image',
    'PIL': 'Pillow',
    'imageio': 'ImageIO',

    # Single-cell / omics
    'scanpy': 'Scanpy',
    'anndata': 'AnnData',
    'muon': 'Muon',
    'scvi': 'scvi-tools',
    'cellrank': 'CellRank',

    # Genomics
    'pysam': 'PySAM',
    'Bio': 'Biopython',
    'gget': 'gget',
    'pyensembl': 'PyEnsembl',
    'pybedtools': 'pybedtools',
    'pyfaidx': 'pyfaidx',

    # Structure
    'pymol': 'PyMOL',
    'biotite': 'Biotite',
    'mdtraj': 'MDTraj',
    'prody': 'ProDy',
    'graphein': 'Graphein',

    # Chemistry
    'rdkit': 'RDKit',
    'openbabel': 'Open Babel',

    # Systems biology
    'cobra': 'COBRApy',
    'tellurium': 'Tellurium',
    'libsbml': 'libSBML',

    # Machine learning
    'torch': 'PyTorch',
    'tensorflow': 'TensorFlow',
    'sklearn': 'scikit-learn',

    # Data/stats
    'numpy': 'NumPy',
    'pandas': 'pandas',
    'scipy': 'SciPy',
    'statsmodels': 'statsmodels',

    # Visualization
    'matplotlib': 'Matplotlib',
    'seaborn': 'Seaborn',
    'plotly': 'Plotly',

    # Network
    'networkx': 'NetworkX',
    'igraph': 'igraph',

    # Lab automation
    'opentrons': 'Opentrons',

    # Other bio tools
    'primer3': 'Primer3',
    'mygene': 'MyGene',
    'bioservices': 'BioServices',
    'gprofiler': 'g:Profiler',
    'goatools': 'GOATOOLS',
}

# Command-line tools called via subprocess
CLI_TOOLS = {
    'bwa': 'BWA',
    'samtools': 'SAMtools',
    'bcftools': 'BCFtools',
    'bedtools': 'BEDTools',
    'bowtie2': 'Bowtie2',
    'hisat2': 'HISAT2',
    'star': 'STAR',
    'salmon': 'Salmon',
    'kallisto': 'Kallisto',
    'minimap2': 'Minimap2',
    'gatk': 'GATK',
    'mutect2': 'Mutect2',
    'snpeff': 'SnpEff',
    'vep': 'VEP',
    'fastqc': 'FastQC',
    'trimmomatic': 'Trimmomatic',
    'cutadapt': 'Cutadapt',
    'picard': 'Picard',
    'deseq2': 'DESeq2',
    'featurecounts': 'featureCounts',
    'stringtie': 'StringTie',
    'cufflinks': 'Cufflinks',
    'tophat': 'TopHat',
    'macs2': 'MACS2',
    'homer': 'HOMER',
    'meme': 'MEME',
    'blast': 'BLAST',
    'hmmer': 'HMMER',
    'mmseqs': 'MMseqs2',
    'foldseek': 'Foldseek',
    'alphafold': 'AlphaFold',
    'esmfold': 'ESMFold',
    'rosettafold': 'RoseTTAFold',
    'nextflow': 'Nextflow',
    'snakemake': 'Snakemake',
    'conda': 'Conda',
}

class ToolFunctionExtractor(ast.NodeVisitor):
    """Extract external library function calls from Python code."""

    def __init__(self):
        self.imports = {}  # alias -> module
        self.tool_calls = defaultdict(set)  # tool -> {functions}
        self.current_function = None
        self.function_tool_calls = defaultdict(lambda: defaultdict(set))  # func -> tool -> {calls}

    def visit_Import(self, node):
        for alias in node.names:
            name = alias.asname or alias.name.split('.')[0]
            self.imports[name] = alias.name
        self.generic_visit(node)

    def visit_ImportFrom(self, node):
        if node.module:
            base = node.module.split('.')[0]
            for alias in node.names:
                name = alias.asname or alias.name
                self.imports[name] = f"{node.module}.{alias.name}"
        self.generic_visit(node)

    def visit_FunctionDef(self, node):
        self.current_function = node.name
        self.generic_visit(node)
        self.current_function = None

    def visit_Call(self, node):
        call_str = self._get_call_string(node.func)
        if call_str:
            parts = call_str.split('.')
            base = parts[0]

            # Check if it's from a known tool
            if base in self.imports:
                module = self.imports[base].split('.')[0]
                if module in KNOWN_TOOLS:
                    tool_name = KNOWN_TOOLS[module]
                    func_name = call_str
                    self.tool_calls[tool_name].add(func_name)
                    if self.current_function:
                        self.function_tool_calls[self.current_function][tool_name].add(func_name)
            elif base in KNOWN_TOOLS:
                tool_name = KNOWN_TOOLS[base]
                self.tool_calls[tool_name].add(call_str)
                if self.current_function:
                    self.function_tool_calls[self.current_function][tool_name].add(call_str)

        self.generic_visit(node)

    def _get_call_string(self, node):
        """Convert call node to string representation."""
        if isinstance(node, ast.Name):
            return node.id
        elif isinstance(node, ast.Attribute):
            value = self._get_call_string(node.value)
            if value:
                return f"{value}.{node.attr}"
        return None


def analyze_file(filepath):
    """Analyze a single Python file for tool-function calls."""
    try:
        with open(filepath, 'r') as f:
            source = f.read()
        tree = ast.parse(source)
        extractor = ToolFunctionExtractor()
        extractor.visit(tree)
        return extractor.tool_calls, extractor.function_tool_calls
    except Exception as e:
        print(f"Error parsing {filepath}: {e}")
        return {}, {}


def main():
    tool_dir = Path("/home/yzhang/biomate/Biomni/biomni/tool")

    # Aggregate results
    all_tool_calls = defaultdict(set)
    all_function_calls = {}
    domain_stats = {}

    # Skip non-domain files
    skip_files = {'__init__.py', 'tool_registry.py', 'support_tools.py'}

    for py_file in sorted(tool_dir.glob("*.py")):
        if py_file.name in skip_files:
            continue

        domain = py_file.stem
        tool_calls, function_calls = analyze_file(py_file)

        # Aggregate
        for tool, funcs in tool_calls.items():
            all_tool_calls[tool].update(funcs)

        all_function_calls[domain] = function_calls

        # Stats for this domain
        total_funcs = len(function_calls)
        total_tool_calls = sum(len(funcs) for funcs in tool_calls.values())
        tools_used = list(tool_calls.keys())

        domain_stats[domain] = {
            'biomni_functions': total_funcs,
            'tool_calls': total_tool_calls,
            'tools_used': tools_used
        }

    # Print results
    print("=" * 80)
    print("BIOMNI TOOL-FUNCTION EXTRACTION REPORT")
    print("=" * 80)

    print("\n## SUMMARY BY EXTERNAL TOOL/LIBRARY\n")
    print(f"{'Tool':<25} {'Functions':<10} {'Examples'}")
    print("-" * 80)

    total_tool_functions = 0
    for tool in sorted(all_tool_calls.keys()):
        funcs = sorted(all_tool_calls[tool])
        total_tool_functions += len(funcs)
        examples = ', '.join(funcs[:3])
        if len(funcs) > 3:
            examples += f", ... (+{len(funcs)-3} more)"
        print(f"{tool:<25} {len(funcs):<10} {examples}")

    print("-" * 80)
    print(f"{'TOTAL':<25} {total_tool_functions:<10}")

    print("\n\n## SUMMARY BY BIOMNI DOMAIN\n")
    print(f"{'Domain':<25} {'Functions':<12} {'Tool Calls':<12} Tools Used")
    print("-" * 80)

    total_biomni_funcs = 0
    for domain in sorted(domain_stats.keys()):
        stats = domain_stats[domain]
        total_biomni_funcs += stats['biomni_functions']
        tools = ', '.join(stats['tools_used'][:4])
        if len(stats['tools_used']) > 4:
            tools += f" +{len(stats['tools_used'])-4}"
        print(f"{domain:<25} {stats['biomni_functions']:<12} {stats['tool_calls']:<12} {tools}")

    print("-" * 80)
    print(f"{'TOTAL':<25} {total_biomni_funcs:<12}")

    print("\n\n## DETAILED TOOL-FUNCTION LIST\n")
    for tool in sorted(all_tool_calls.keys()):
        funcs = sorted(all_tool_calls[tool])
        print(f"\n### {tool} ({len(funcs)} functions)")
        for func in funcs:
            print(f"  - {func}")

    print("\n\n## BIOMNI FUNCTION → TOOL-FUNCTION MAPPING\n")
    print("(showing functions that use 2+ tool-functions = multi-step workflows)")

    multi_step_count = 0
    single_step_count = 0

    for domain in sorted(all_function_calls.keys()):
        func_calls = all_function_calls[domain]
        multi_step_funcs = []

        for func_name, tool_dict in func_calls.items():
            total_calls = sum(len(calls) for calls in tool_dict.values())
            if total_calls >= 2:
                multi_step_funcs.append((func_name, tool_dict, total_calls))
                multi_step_count += 1
            else:
                single_step_count += 1

        if multi_step_funcs:
            print(f"\n### {domain}")
            for func_name, tool_dict, total in sorted(multi_step_funcs, key=lambda x: -x[2]):
                tools_summary = []
                for tool, calls in tool_dict.items():
                    tools_summary.append(f"{tool}({len(calls)})")
                print(f"  {func_name}: {', '.join(tools_summary)} = {total} calls")

    print("\n\n## FINAL STATISTICS")
    print("=" * 80)
    print(f"Total external tools/libraries used: {len(all_tool_calls)}")
    print(f"Total unique tool-functions: {total_tool_functions}")
    print(f"Total Biomni functions analyzed: {total_biomni_funcs}")
    print(f"  - Multi-step (2+ tool calls): {multi_step_count} → need .ga workflows")
    print(f"  - Single-step (0-1 tool calls): {single_step_count} → atomic tools")
    print("=" * 80)


if __name__ == "__main__":
    main()
