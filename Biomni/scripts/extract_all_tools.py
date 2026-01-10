#!/usr/bin/env python3
"""
Comprehensive tool-function extraction from Biomni code.
Extracts:
1. Python library calls (cv2, scanpy, etc.)
2. Command-line tools via subprocess (bwa, samtools, etc.)
3. API calls (requests, REST APIs)
"""

import ast
import re
from collections import defaultdict
from pathlib import Path

# Python libraries -> Tool name
PYTHON_LIBS = {
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
    'squidpy': 'Squidpy',
    'cellxgene': 'cellxgene',

    # Genomics
    'pysam': 'PySAM',
    'Bio': 'Biopython',
    'gget': 'gget',
    'pyensembl': 'PyEnsembl',
    'pybedtools': 'pybedtools',
    'pyfaidx': 'pyfaidx',
    'pyranges': 'PyRanges',

    # Structure
    'pymol': 'PyMOL',
    'biotite': 'Biotite',
    'mdtraj': 'MDTraj',
    'prody': 'ProDy',
    'graphein': 'Graphein',
    'biopandas': 'BioPandas',

    # Chemistry
    'rdkit': 'RDKit',
    'openbabel': 'Open Babel',
    'deepchem': 'DeepChem',

    # Systems biology
    'cobra': 'COBRApy',
    'tellurium': 'Tellurium',
    'libsbml': 'libSBML',
    'biomodels': 'BioModels',

    # Machine learning
    'torch': 'PyTorch',
    'tensorflow': 'TensorFlow',
    'keras': 'Keras',
    'sklearn': 'scikit-learn',
    'xgboost': 'XGBoost',
    'lightgbm': 'LightGBM',

    # Deep learning bio
    'esm': 'ESM',
    'transformers': 'HuggingFace',

    # Data/stats
    'numpy': 'NumPy',
    'pandas': 'pandas',
    'scipy': 'SciPy',
    'statsmodels': 'statsmodels',
    'pingouin': 'Pingouin',

    # Visualization
    'matplotlib': 'Matplotlib',
    'seaborn': 'Seaborn',
    'plotly': 'Plotly',
    'bokeh': 'Bokeh',

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

    # Web/API
    'requests': 'HTTP/REST',
    'aiohttp': 'HTTP/REST',
    'httpx': 'HTTP/REST',
}

# CLI tools that may be called via subprocess
CLI_TOOLS = [
    # Alignment
    'bwa', 'bowtie', 'bowtie2', 'hisat2', 'star', 'minimap2',
    'blastn', 'blastp', 'blastx', 'tblastn', 'makeblastdb',

    # SAM/BAM
    'samtools', 'bcftools', 'bedtools', 'bamtools',

    # Variant calling
    'gatk', 'mutect2', 'freebayes', 'varscan', 'deepvariant',
    'snpeff', 'vep', 'annovar',

    # RNA-seq
    'salmon', 'kallisto', 'rsem', 'htseq-count',
    'featurecounts', 'stringtie', 'cufflinks',

    # QC/trimming
    'fastqc', 'multiqc', 'trimmomatic', 'cutadapt', 'fastp',
    'trimgalore', 'bbduk',

    # Peak calling
    'macs2', 'macs3', 'homer', 'sicer',

    # Motif
    'meme', 'fimo', 'mast',

    # Assembly
    'spades', 'megahit', 'velvet', 'trinity', 'rnaspades',

    # Annotation
    'prokka', 'bakta', 'eggnog-mapper', 'interproscan',

    # Protein structure
    'alphafold', 'colabfold', 'esmfold', 'rosettafold',
    'foldseek', 'mmseqs', 'mmseqs2',

    # Phylogenetics
    'raxml', 'iqtree', 'fasttree', 'mafft', 'muscle', 'clustalo',

    # Metagenomics
    'kraken2', 'metaphlan', 'humann', 'bracken',

    # Single-cell
    'cellranger', 'velocyto', 'starsolo',

    # Other
    'picard', 'qualimap', 'preseq', 'seqkit', 'seqtk',
    'pigz', 'bgzip', 'tabix',

    # Workflow
    'nextflow', 'snakemake', 'cwl', 'wdl',
    'conda', 'mamba', 'pip',
]


class ComprehensiveExtractor(ast.NodeVisitor):
    """Extract all tool calls from Python code."""

    def __init__(self, source_code):
        self.source = source_code
        self.source_lines = source_code.split('\n')
        self.imports = {}
        self.python_calls = defaultdict(set)
        self.cli_calls = defaultdict(set)
        self.api_calls = set()
        self.current_function = None
        self.function_tools = defaultdict(lambda: {'python': defaultdict(set), 'cli': set(), 'api': set()})

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
        # Check for Python library calls
        call_str = self._get_call_string(node.func)
        if call_str:
            parts = call_str.split('.')
            base = parts[0]

            if base in self.imports:
                module = self.imports[base].split('.')[0]
                if module in PYTHON_LIBS:
                    tool_name = PYTHON_LIBS[module]
                    self.python_calls[tool_name].add(call_str)
                    if self.current_function:
                        self.function_tools[self.current_function]['python'][tool_name].add(call_str)
            elif base in PYTHON_LIBS:
                tool_name = PYTHON_LIBS[base]
                self.python_calls[tool_name].add(call_str)
                if self.current_function:
                    self.function_tools[self.current_function]['python'][tool_name].add(call_str)

        # Check for subprocess calls
        if call_str and ('subprocess' in call_str or call_str.endswith('.run') or
                         call_str.endswith('.Popen') or call_str.endswith('.check_output')):
            self._extract_cli_from_call(node)

        self.generic_visit(node)

    def _extract_cli_from_call(self, node):
        """Extract CLI tool name from subprocess call."""
        for arg in node.args:
            if isinstance(arg, ast.List):
                if arg.elts and isinstance(arg.elts[0], ast.Constant):
                    cmd = str(arg.elts[0].value).lower()
                    for tool in CLI_TOOLS:
                        if tool in cmd:
                            self.cli_calls[tool].add(cmd)
                            if self.current_function:
                                self.function_tools[self.current_function]['cli'].add(tool)
            elif isinstance(arg, ast.Constant):
                cmd = str(arg.value).lower()
                for tool in CLI_TOOLS:
                    if tool in cmd:
                        self.cli_calls[tool].add(f"shell:{cmd[:50]}")
                        if self.current_function:
                            self.function_tools[self.current_function]['cli'].add(tool)

    def _get_call_string(self, node):
        if isinstance(node, ast.Name):
            return node.id
        elif isinstance(node, ast.Attribute):
            value = self._get_call_string(node.value)
            if value:
                return f"{value}.{node.attr}"
        return None


def extract_cli_from_strings(source):
    """Extract CLI tools from string literals in source code."""
    cli_found = defaultdict(set)

    for tool in CLI_TOOLS:
        # Look for tool in command strings
        patterns = [
            rf'\[[\'"]{tool}[\'"]',  # ["tool" or ['tool'
            rf'subprocess\.run\([^)]*{tool}',  # subprocess.run(...tool...)
            rf'f[\'"]\{{{tool}\}}',  # f"{tool}"
            rf'[\'"]{tool}\s',  # "tool " at start of command
        ]
        for pattern in patterns:
            if re.search(pattern, source, re.IGNORECASE):
                cli_found[tool].add(f"detected_in_source")

    return cli_found


def analyze_file(filepath):
    """Analyze a single Python file."""
    try:
        with open(filepath, 'r') as f:
            source = f.read()
        tree = ast.parse(source)
        extractor = ComprehensiveExtractor(source)
        extractor.visit(tree)

        # Also extract CLI from string patterns
        cli_from_strings = extract_cli_from_strings(source)
        for tool, calls in cli_from_strings.items():
            extractor.cli_calls[tool].update(calls)

        return {
            'python': dict(extractor.python_calls),
            'cli': dict(extractor.cli_calls),
            'function_tools': dict(extractor.function_tools)
        }
    except Exception as e:
        print(f"Error parsing {filepath}: {e}")
        return {'python': {}, 'cli': {}, 'function_tools': {}}


def main():
    tool_dir = Path("/home/yzhang/biomate/Biomni/biomni/tool")
    skip_files = {'__init__.py', 'tool_registry.py', 'support_tools.py'}

    all_python = defaultdict(set)
    all_cli = defaultdict(set)
    all_function_tools = {}
    domain_summary = {}

    print("=" * 80)
    print("COMPREHENSIVE BIOMNI TOOL EXTRACTION")
    print("=" * 80)

    for py_file in sorted(tool_dir.glob("*.py")):
        if py_file.name in skip_files:
            continue

        domain = py_file.stem
        result = analyze_file(py_file)

        # Aggregate
        for tool, calls in result['python'].items():
            all_python[tool].update(calls)
        for tool, calls in result['cli'].items():
            all_cli[tool].update(calls)
        all_function_tools[domain] = result['function_tools']

        # Summary for domain
        num_funcs = len(result['function_tools'])
        python_tools = list(result['python'].keys())
        cli_tools = list(result['cli'].keys())

        domain_summary[domain] = {
            'functions': num_funcs,
            'python_tools': python_tools,
            'cli_tools': cli_tools,
            'total_python_calls': sum(len(c) for c in result['python'].values()),
            'total_cli_calls': sum(len(c) for c in result['cli'].values())
        }

    # Print Python Library Summary
    print("\n## PYTHON LIBRARIES USED\n")
    print(f"{'Library':<25} {'Functions':<10} Examples")
    print("-" * 80)

    total_python_funcs = 0
    for lib in sorted(all_python.keys()):
        calls = sorted(all_python[lib])
        total_python_funcs += len(calls)
        examples = ', '.join(calls[:3])
        if len(calls) > 3:
            examples += f" +{len(calls)-3}"
        print(f"{lib:<25} {len(calls):<10} {examples}")
    print(f"{'TOTAL':<25} {total_python_funcs}")

    # Print CLI Tools Summary
    print("\n\n## COMMAND-LINE TOOLS USED\n")
    print(f"{'Tool':<25} {'Calls':<10}")
    print("-" * 80)

    for tool in sorted(all_cli.keys()):
        calls = all_cli[tool]
        print(f"{tool:<25} {len(calls)}")
    print(f"{'TOTAL CLI TOOLS':<25} {len(all_cli)}")

    # Print Domain Summary
    print("\n\n## DOMAIN SUMMARY\n")
    print(f"{'Domain':<25} {'Funcs':<8} {'PyTools':<10} {'CLITools':<10} Notable Tools")
    print("-" * 100)

    total_funcs = 0
    for domain in sorted(domain_summary.keys()):
        s = domain_summary[domain]
        total_funcs += s['functions']
        notable = s['python_tools'][:3] + s['cli_tools'][:2]
        notable_str = ', '.join(notable)
        if len(s['python_tools']) + len(s['cli_tools']) > 5:
            notable_str += f" +{len(s['python_tools']) + len(s['cli_tools']) - 5}"
        print(f"{domain:<25} {s['functions']:<8} {len(s['python_tools']):<10} {len(s['cli_tools']):<10} {notable_str}")
    print("-" * 100)
    print(f"{'TOTAL':<25} {total_funcs}")

    # Classify functions
    print("\n\n## FUNCTION CLASSIFICATION\n")

    single_step = []
    multi_step = []

    for domain, funcs in all_function_tools.items():
        for func_name, tools in funcs.items():
            py_count = sum(len(calls) for calls in tools['python'].values())
            cli_count = len(tools['cli'])
            total = py_count + cli_count

            if total <= 1:
                single_step.append((domain, func_name, tools))
            else:
                multi_step.append((domain, func_name, tools, total))

    print(f"Single-step functions (0-1 tool calls): {len(single_step)}")
    print(f"Multi-step functions (2+ tool calls): {len(multi_step)}")

    # Show multi-step examples
    print("\n### Multi-step Functions (need .ga workflows)")
    print("-" * 80)

    for domain, func_name, tools, total in sorted(multi_step, key=lambda x: -x[3])[:30]:
        tool_list = []
        for t, calls in tools['python'].items():
            tool_list.append(f"{t}({len(calls)})")
        for t in tools['cli']:
            tool_list.append(f"CLI:{t}")
        print(f"  {domain}.{func_name}: {', '.join(tool_list)} = {total} calls")

    if len(multi_step) > 30:
        print(f"  ... and {len(multi_step) - 30} more")

    # Final summary
    print("\n\n" + "=" * 80)
    print("FINAL SUMMARY")
    print("=" * 80)
    print(f"Total Python libraries used: {len(all_python)}")
    print(f"Total Python tool-functions: {total_python_funcs}")
    print(f"Total CLI tools used: {len(all_cli)}")
    print(f"Total Biomni functions: {total_funcs}")
    print(f"  - Single-step (atomic): {len(single_step)} → XML tools only")
    print(f"  - Multi-step (workflows): {len(multi_step)} → need .ga workflows")
    print("=" * 80)

    # Print all unique tool-functions
    print("\n\n## ALL UNIQUE TOOL-FUNCTIONS (for XML generation)")
    print("-" * 80)

    print("\n### Python Libraries")
    for lib in sorted(all_python.keys()):
        print(f"\n{lib}:")
        for func in sorted(all_python[lib]):
            print(f"  - {func}")

    print("\n### CLI Tools")
    for tool in sorted(all_cli.keys()):
        print(f"  - {tool}")


if __name__ == "__main__":
    main()
