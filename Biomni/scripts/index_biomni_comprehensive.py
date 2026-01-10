#!/usr/bin/env python3
"""
Comprehensive Biomni Tool Indexer for Galaxy Integration.

This script properly categorizes:
1. ATOMIC TOOLS (tool-functions): The underlying executable units
   - Python library functions (cv2.imread, scanpy.pp.normalize, etc.)
   - R package functions (DESeq2::DESeq, edgeR::calcNormFactors, etc.)
   - CLI tools (bwa, samtools, macs2, etc.)

2. WORKFLOWS: Biomni functions that orchestrate multiple tool-functions
   - Single-step workflows (1 tool-function call)
   - Multi-step workflows (2+ tool-function calls)

Output:
- Updated tool index database with tool_type field
- Proper implementation_info for Galaxy direct calling
- XML wrappers for atomic tools
- .ga workflow files for Biomni functions
"""

import ast
import json
import os
import re
import sqlite3
import subprocess
from collections import defaultdict
from dataclasses import dataclass, field, asdict
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Any, Optional, Set
import xml.etree.ElementTree as ET
from xml.dom import minidom

# ============================================================================
# PATHS
# ============================================================================
BIOMNI_ROOT = Path("/home/yzhang/biomate/Biomni")
TOOL_DIR = BIOMNI_ROOT / "biomni/tool"
TOOL_DESC_DIR = BIOMNI_ROOT / "biomni/tool/tool_description"
GALAXY_DIR = BIOMNI_ROOT / "biomni_galaxy"
TOOLS_OUTPUT_DIR = GALAXY_DIR / "tools_v2"  # New structure
WORKFLOWS_OUTPUT_DIR = GALAXY_DIR / "workflows"
DB_PATH = BIOMNI_ROOT / "biomni_tools_v2.db"

# ============================================================================
# TOOL TYPE DEFINITIONS
# ============================================================================

@dataclass
class ToolFunction:
    """Represents an atomic tool-function that can be called directly."""
    id: str                      # e.g., "python/biopython/SeqIO.read"
    name: str                    # Human-readable name
    tool_type: str               # "python", "r", "cli"
    library: str                 # e.g., "biopython", "deseq2", "samtools"
    function: str                # e.g., "SeqIO.read", "DESeq", "view"
    description: str = ""
    parameters: List[Dict] = field(default_factory=list)
    inputs: List[Dict] = field(default_factory=list)
    outputs: List[Dict] = field(default_factory=list)
    requirements: List[Dict] = field(default_factory=list)
    implementation: Dict = field(default_factory=dict)

@dataclass
class BiomniWorkflow:
    """Represents a Biomni function as a Galaxy workflow."""
    id: str                      # e.g., "biomni/genomics/annotate_sc_adata"
    name: str                    # Human-readable name
    domain: str                  # Biomni domain
    function_name: str           # Original function name
    description: str = ""
    tool_calls: List[str] = field(default_factory=list)  # List of tool-function IDs
    is_multi_step: bool = False
    parameters: List[Dict] = field(default_factory=list)
    inputs: List[Dict] = field(default_factory=list)
    outputs: List[Dict] = field(default_factory=list)

# ============================================================================
# KNOWN TOOLS REGISTRY
# ============================================================================

# Python libraries with their Galaxy-compatible tool IDs
PYTHON_TOOLS = {
    # Core bioinformatics
    'Bio': {'name': 'Biopython', 'functions': [
        'SeqIO.read', 'SeqIO.write', 'SeqIO.parse',
        'Entrez.efetch', 'Entrez.esearch', 'Entrez.read',
        'AlignIO.read', 'AlignIO.write',
        'Phylo.read', 'Phylo.write', 'Phylo.draw',
        'pairwise2.align.globalms', 'pairwise2.align.globalxx',
        'Restriction.RestrictionBatch', 'Restriction.CommOnly.search',
        'PDBParser', 'PDBIO', 'Superimposer',
    ]},
    'scanpy': {'name': 'Scanpy', 'functions': [
        'pp.normalize_total', 'pp.log1p', 'pp.highly_variable_genes',
        'pp.scale', 'pp.pca', 'pp.neighbors', 'pp.regress_out',
        'tl.pca', 'tl.umap', 'tl.tsne', 'tl.leiden', 'tl.louvain',
        'tl.rank_genes_groups', 'tl.dendrogram',
        'pl.pca', 'pl.umap', 'pl.violin', 'pl.dotplot',
        'read_h5ad', 'read_10x_h5', 'read_loom',
    ]},
    'cv2': {'name': 'OpenCV', 'functions': [
        'imread', 'imwrite', 'cvtColor', 'threshold', 'adaptiveThreshold',
        'GaussianBlur', 'Sobel', 'Canny', 'dilate', 'erode',
        'findContours', 'drawContours', 'morphologyEx',
        'connectedComponents', 'connectedComponentsWithStats',
        'watershed', 'distanceTransform',
    ]},
    'skimage': {'name': 'scikit-image', 'functions': [
        'io.imread', 'io.imsave',
        'filters.threshold_otsu', 'filters.threshold_li', 'filters.gaussian',
        'morphology.remove_small_objects', 'morphology.remove_small_holes',
        'morphology.binary_closing', 'morphology.binary_dilation',
        'measure.regionprops', 'measure.regionprops_table', 'measure.label',
        'segmentation.watershed', 'segmentation.find_boundaries',
        'exposure.equalize_hist', 'exposure.equalize_adapthist',
        'color.rgb2gray', 'color.label2rgb',
    ]},
    'rdkit': {'name': 'RDKit', 'functions': [
        'Chem.MolFromSmiles', 'Chem.MolToSmiles', 'Chem.MolFromMolFile',
        'Descriptors.MolWt', 'Descriptors.MolLogP', 'Descriptors.TPSA',
        'Descriptors.NumHDonors', 'Descriptors.NumHAcceptors',
        'Lipinski.NumHDonors', 'Lipinski.NumHAcceptors',
        'AllChem.EmbedMolecule', 'AllChem.GetMorganFingerprint',
    ]},
    'cobra': {'name': 'COBRApy', 'functions': [
        'io.read_sbml_model', 'io.write_sbml_model', 'io.load_model',
        'flux_analysis.flux_variability_analysis',
        'flux_analysis.single_gene_deletion',
    ]},
    'gget': {'name': 'gget', 'functions': [
        'enrichr', 'archs4', 'blast', 'muscle', 'ref', 'search',
    ]},
    'pysam': {'name': 'PySAM', 'functions': [
        'AlignmentFile', 'VariantFile', 'FastaFile', 'TabixFile',
    ]},
    'torch': {'name': 'PyTorch', 'functions': [
        'load', 'save', 'no_grad', 'from_numpy', 'tensor',
        'nn.Linear', 'nn.Conv2d', 'nn.Sequential',
    ]},
    'numpy': {'name': 'NumPy', 'functions': []},  # Too generic, skip
    'pandas': {'name': 'pandas', 'functions': []},  # Too generic, skip
    'scipy': {'name': 'SciPy', 'functions': []},  # Too generic, skip
    'matplotlib': {'name': 'Matplotlib', 'functions': []},  # Visualization, skip
}

# R packages with their functions
R_PACKAGES = {
    'DESeq2': {'functions': [
        'DESeqDataSetFromMatrix', 'DESeq', 'results', 'plotMA',
        'plotPCA', 'vst', 'rlog', 'lfcShrink',
    ]},
    'edgeR': {'functions': [
        'DGEList', 'calcNormFactors', 'estimateDisp',
        'glmQLFit', 'glmQLFTest', 'topTags',
    ]},
    'limma': {'functions': [
        'lmFit', 'eBayes', 'topTable', 'makeContrasts',
        'removeBatchEffect', 'normalizeBetweenArrays',
    ]},
    'Seurat': {'functions': [
        'CreateSeuratObject', 'NormalizeData', 'FindVariableFeatures',
        'ScaleData', 'RunPCA', 'RunUMAP', 'FindNeighbors',
        'FindClusters', 'FindMarkers',
    ]},
    'clusterProfiler': {'functions': [
        'enrichGO', 'enrichKEGG', 'gseGO', 'gseKEGG',
        'dotplot', 'barplot', 'cnetplot',
    ]},
    'WGCNA': {'functions': [
        'pickSoftThreshold', 'blockwiseModules', 'moduleEigengenes',
        'signedKME', 'labeledHeatmap',
    ]},
    'ggplot2': {'functions': [
        'ggplot', 'geom_point', 'geom_line', 'geom_bar',
        'facet_wrap', 'theme', 'ggsave',
    ]},
    'dplyr': {'functions': [
        'filter', 'select', 'mutate', 'group_by', 'summarize',
        'left_join', 'inner_join', 'arrange',
    ]},
    'harmony': {'functions': [
        'RunHarmony', 'HarmonyMatrix',
    ]},
}

# CLI tools with their subcommands
CLI_TOOLS = {
    'bwa': {'functions': ['index', 'mem', 'aln', 'samse', 'sampe']},
    'samtools': {'functions': ['view', 'sort', 'index', 'flagstat', 'stats', 'merge', 'mpileup', 'faidx']},
    'bcftools': {'functions': ['view', 'call', 'filter', 'stats', 'annotate', 'merge']},
    'bedtools': {'functions': ['intersect', 'merge', 'subtract', 'coverage', 'genomecov', 'getfasta']},
    'macs2': {'functions': ['callpeak', 'bdgcmp', 'bdgdiff']},
    'fastqc': {'functions': ['analyze']},
    'trimmomatic': {'functions': ['PE', 'SE']},
    'cutadapt': {'functions': ['trim']},
    'bowtie2': {'functions': ['build', 'align']},
    'hisat2': {'functions': ['build', 'align']},
    'salmon': {'functions': ['index', 'quant']},
    'kallisto': {'functions': ['index', 'quant']},
    'star': {'functions': ['genomeGenerate', 'align']},
    'featureCounts': {'functions': ['count']},
    'htseq-count': {'functions': ['count']},
    'snpeff': {'functions': ['ann', 'download']},
    'gatk': {'functions': ['HaplotypeCaller', 'Mutect2', 'BaseRecalibrator', 'ApplyBQSR']},
    'plink': {'functions': ['assoc', 'logistic', 'linear', 'pca']},
    'iqtree': {'functions': ['run']},
    'mafft': {'functions': ['align']},
    'muscle': {'functions': ['align']},
    'blast': {'functions': ['blastn', 'blastp', 'blastx', 'tblastn', 'makeblastdb']},
    'mmseqs': {'functions': ['easy-search', 'createdb', 'cluster']},
    'foldseek': {'functions': ['easy-search', 'createdb']},
    'alphafold': {'functions': ['predict']},
    'prokka': {'functions': ['annotate']},
    'kraken2': {'functions': ['classify', 'build']},
    'diamond': {'functions': ['makedb', 'blastp', 'blastx']},
}


# ============================================================================
# EXTRACTORS
# ============================================================================

class BiomniCodeAnalyzer(ast.NodeVisitor):
    """Analyze Biomni Python code to extract tool-function calls."""

    def __init__(self, source: str):
        self.source = source
        self.imports = {}
        self.tool_calls = defaultdict(set)
        self.cli_calls = defaultdict(set)
        self.current_function = None
        self.function_calls = defaultdict(lambda: {'python': defaultdict(set), 'cli': set(), 'r': set()})

    def visit_Import(self, node):
        for alias in node.names:
            name = alias.asname or alias.name.split('.')[0]
            self.imports[name] = alias.name
        self.generic_visit(node)

    def visit_ImportFrom(self, node):
        if node.module:
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

            # Check Python tools
            if base in self.imports:
                module = self.imports[base].split('.')[0]
                if module in PYTHON_TOOLS:
                    self.tool_calls[module].add(call_str)
                    if self.current_function:
                        self.function_calls[self.current_function]['python'][module].add(call_str)
            elif base in PYTHON_TOOLS:
                self.tool_calls[base].add(call_str)
                if self.current_function:
                    self.function_calls[self.current_function]['python'][base].add(call_str)

            # Check for subprocess (CLI tools)
            if 'subprocess' in call_str or call_str.endswith('.run'):
                self._extract_cli_call(node)

            # Check for Rscript calls
            if 'Rscript' in str(node.args):
                self._extract_r_call(node)

        self.generic_visit(node)

    def _get_call_string(self, node):
        if isinstance(node, ast.Name):
            return node.id
        elif isinstance(node, ast.Attribute):
            value = self._get_call_string(node.value)
            if value:
                return f"{value}.{node.attr}"
        return None

    def _extract_cli_call(self, node):
        for arg in node.args:
            if isinstance(arg, ast.List) and arg.elts:
                if isinstance(arg.elts[0], ast.Constant):
                    cmd = str(arg.elts[0].value).lower()
                    for tool in CLI_TOOLS:
                        if tool in cmd:
                            self.cli_calls[tool].add(cmd)
                            if self.current_function:
                                self.function_calls[self.current_function]['cli'].add(tool)

    def _extract_r_call(self, node):
        # Parse R code from Rscript calls
        for arg in node.args:
            if isinstance(arg, ast.Constant) and isinstance(arg.value, str):
                r_code = arg.value
                for pkg in R_PACKAGES:
                    if f'library({pkg})' in r_code or f'{pkg}::' in r_code:
                        if self.current_function:
                            self.function_calls[self.current_function]['r'].add(pkg)


def analyze_biomni_file(filepath: Path) -> Dict:
    """Analyze a single Biomni Python file."""
    try:
        source = filepath.read_text()
        tree = ast.parse(source)
        analyzer = BiomniCodeAnalyzer(source)
        analyzer.visit(tree)
        return {
            'tool_calls': dict(analyzer.tool_calls),
            'cli_calls': dict(analyzer.cli_calls),
            'function_calls': dict(analyzer.function_calls)
        }
    except Exception as e:
        print(f"Error parsing {filepath}: {e}")
        return {}


def extract_all_tool_functions() -> List[ToolFunction]:
    """Extract all atomic tool-functions from the registries."""
    tools = []

    # Python tools
    for lib, info in PYTHON_TOOLS.items():
        if not info['functions']:  # Skip generic libs
            continue
        for func in info['functions']:
            tool_id = f"python/{lib.lower()}/{func.replace('.', '_')}"
            tools.append(ToolFunction(
                id=tool_id,
                name=f"{info['name']}: {func}",
                tool_type='python',
                library=lib,
                function=func,
                description=f"Call {info['name']} {func} function",
                implementation={
                    'type': 'python',
                    'module': lib,
                    'function': func,
                    'call_template': f"from {lib} import ...; result = {func}(...)"
                }
            ))

    # R packages
    for pkg, info in R_PACKAGES.items():
        for func in info['functions']:
            tool_id = f"r/{pkg.lower()}/{func.lower()}"
            tools.append(ToolFunction(
                id=tool_id,
                name=f"{pkg}::{func}",
                tool_type='r',
                library=pkg,
                function=func,
                description=f"Call R {pkg}::{func} function",
                implementation={
                    'type': 'r',
                    'package': pkg,
                    'function': func,
                    'call_template': f"Rscript -e 'library({pkg}); {func}(...)'"
                }
            ))

    # CLI tools
    for tool, info in CLI_TOOLS.items():
        for subcommand in info['functions']:
            tool_id = f"cli/{tool}/{subcommand}"
            tools.append(ToolFunction(
                id=tool_id,
                name=f"{tool} {subcommand}",
                tool_type='cli',
                library=tool,
                function=subcommand,
                description=f"Run {tool} {subcommand} command",
                implementation={
                    'type': 'cli',
                    'executable': tool,
                    'subcommand': subcommand,
                    'call_template': f"{tool} {subcommand} [options] input output"
                }
            ))

    return tools


def extract_biomni_workflows() -> List[BiomniWorkflow]:
    """Extract all Biomni functions as workflows."""
    workflows = []
    skip_files = {'__init__.py', 'tool_registry.py', 'support_tools.py'}

    for py_file in sorted(TOOL_DIR.glob("*.py")):
        if py_file.name in skip_files:
            continue

        domain = py_file.stem
        result = analyze_biomni_file(py_file)

        if not result:
            continue

        # Load tool descriptions for this domain
        desc_file = TOOL_DESC_DIR / f"{domain}.py"
        tool_descs = {}
        if desc_file.exists():
            try:
                local_vars = {}
                exec(desc_file.read_text(), local_vars)
                for desc in local_vars.get('description', []):
                    tool_descs[desc['name']] = desc
            except:
                pass

        for func_name, calls in result.get('function_calls', {}).items():
            if func_name.startswith('_'):
                continue

            # Count tool calls
            py_calls = sum(len(c) for c in calls['python'].values())
            cli_calls = len(calls['cli'])
            r_calls = len(calls['r'])
            total_calls = py_calls + cli_calls + r_calls

            # Get description from tool_description
            desc_info = tool_descs.get(func_name, {})

            workflow_id = f"biomni/{domain}/{func_name}"

            # Build tool call list
            tool_call_ids = []
            for lib, funcs in calls['python'].items():
                for f in funcs:
                    tool_call_ids.append(f"python/{lib.lower()}/{f.replace('.', '_')}")
            for tool in calls['cli']:
                tool_call_ids.append(f"cli/{tool}/run")
            for pkg in calls['r']:
                tool_call_ids.append(f"r/{pkg.lower()}/run")

            workflows.append(BiomniWorkflow(
                id=workflow_id,
                name=desc_info.get('name', func_name.replace('_', ' ').title()),
                domain=domain,
                function_name=func_name,
                description=desc_info.get('description', ''),
                tool_calls=tool_call_ids,
                is_multi_step=total_calls >= 2,
                parameters=[
                    {'name': p['name'], 'type': p.get('type', 'text'), 'required': True}
                    for p in desc_info.get('required_parameters', [])
                ] + [
                    {'name': p['name'], 'type': p.get('type', 'text'), 'required': False, 'default': p.get('default')}
                    for p in desc_info.get('optional_parameters', [])
                ]
            ))

    return workflows


# ============================================================================
# XML GENERATOR
# ============================================================================

def generate_tool_xml(tool: ToolFunction, output_dir: Path) -> Path:
    """Generate Galaxy XML wrapper for an atomic tool-function."""

    # Create directory structure
    type_dir = output_dir / tool.tool_type / tool.library.lower()
    type_dir.mkdir(parents=True, exist_ok=True)

    # Build XML
    root = ET.Element('tool')
    root.set('id', tool.id.replace('/', '_'))
    root.set('name', tool.name)
    root.set('version', '1.0.0')

    # Description
    desc = ET.SubElement(root, 'description')
    desc.text = tool.description

    # Requirements
    reqs = ET.SubElement(root, 'requirements')
    if tool.tool_type == 'python':
        req = ET.SubElement(reqs, 'requirement')
        req.set('type', 'package')
        req.set('version', '')
        req.text = tool.library.lower()
    elif tool.tool_type == 'r':
        req = ET.SubElement(reqs, 'requirement')
        req.set('type', 'package')
        req.text = f'r-{tool.library.lower()}'
    elif tool.tool_type == 'cli':
        req = ET.SubElement(reqs, 'requirement')
        req.set('type', 'package')
        req.text = tool.library

    # Command
    cmd = ET.SubElement(root, 'command')
    cmd.set('detect_errors', 'exit_code')
    if tool.tool_type == 'python':
        cmd.text = f'''<![CDATA[
python3 << 'EOF'
from {tool.library} import *
# Tool implementation
result = {tool.function}(${{input}})
# Save output
EOF
]]>'''
    elif tool.tool_type == 'r':
        cmd.text = f'''<![CDATA[
Rscript -e 'library({tool.library}); {tool.function}()'
]]>'''
    elif tool.tool_type == 'cli':
        cmd.text = f'{tool.library} {tool.function} $input $output'

    # Inputs
    inputs = ET.SubElement(root, 'inputs')
    param = ET.SubElement(inputs, 'param')
    param.set('name', 'input')
    param.set('type', 'data')
    param.set('label', 'Input file')

    # Outputs
    outputs = ET.SubElement(root, 'outputs')
    data = ET.SubElement(outputs, 'data')
    data.set('name', 'output')
    data.set('format', 'data')
    data.set('label', 'Output')

    # Help
    help_elem = ET.SubElement(root, 'help')
    help_elem.text = f'''<![CDATA[
**{tool.name}**

{tool.description}

**Tool Type**: {tool.tool_type}
**Library**: {tool.library}
**Function**: {tool.function}

**Implementation**:
{json.dumps(tool.implementation, indent=2)}
]]>'''

    # Write XML
    xml_path = type_dir / f"{tool.function.replace('.', '_').lower()}.xml"
    xml_str = ET.tostring(root, encoding='unicode')

    # Pretty print
    dom = minidom.parseString(xml_str)
    with open(xml_path, 'w') as f:
        f.write(dom.toprettyxml(indent='  '))

    return xml_path


def generate_workflow_ga(workflow: BiomniWorkflow, output_dir: Path) -> Path:
    """Generate Galaxy workflow (.ga) file for a Biomni function."""

    domain_dir = output_dir / workflow.domain
    domain_dir.mkdir(parents=True, exist_ok=True)

    # Build workflow JSON
    ga_workflow = {
        'a_galaxy_workflow': 'true',
        'format-version': '0.1',
        'name': workflow.id.replace('/', '_'),
        'annotation': workflow.description,
        'tags': ['biomni', workflow.domain, 'multi-step' if workflow.is_multi_step else 'single-step'],
        'steps': {},
        'workflow_outputs': []
    }

    step_id = 0

    # Input steps
    for i, param in enumerate(workflow.parameters):
        if param.get('required', True):
            ga_workflow['steps'][str(step_id)] = {
                'id': step_id,
                'type': 'data_input' if param.get('type') == 'data' else 'parameter_input',
                'label': param['name'],
                'annotation': f"Input: {param['name']}",
                'position': {'left': 0, 'top': i * 100}
            }
            step_id += 1

    # Tool steps
    prev_step = step_id - 1
    for i, tool_call_id in enumerate(workflow.tool_calls[:5]):  # Limit for readability
        ga_workflow['steps'][str(step_id)] = {
            'id': step_id,
            'type': 'tool',
            'tool_id': tool_call_id.replace('/', '_'),
            'label': f"Step {i+1}: {tool_call_id.split('/')[-1]}",
            'position': {'left': 300 * (i + 1), 'top': 50},
            'input_connections': {
                'input': {'id': prev_step, 'output_name': 'output'}
            } if prev_step >= 0 else {}
        }
        prev_step = step_id
        step_id += 1

    # Output step
    ga_workflow['steps'][str(step_id)] = {
        'id': step_id,
        'type': 'data_output',
        'label': 'Output',
        'position': {'left': 300 * (len(workflow.tool_calls[:5]) + 1), 'top': 50},
        'input_connections': {
            'input': {'id': prev_step, 'output_name': 'output'}
        }
    }

    ga_workflow['workflow_outputs'].append({
        'label': 'Result',
        'output_name': 'output',
        'uuid': f"{workflow.function_name}-output"
    })

    # Write .ga file
    ga_path = domain_dir / f"{workflow.function_name}.ga"
    with open(ga_path, 'w') as f:
        json.dump(ga_workflow, f, indent=2)

    return ga_path


# ============================================================================
# DATABASE
# ============================================================================

def init_database():
    """Initialize the tool index database with updated schema."""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # Drop and recreate for clean schema
    cursor.execute("DROP TABLE IF EXISTS tool_functions")
    cursor.execute("DROP TABLE IF EXISTS biomni_workflows")

    # Tool functions table (atomic tools)
    cursor.execute("""
        CREATE TABLE tool_functions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            tool_id TEXT UNIQUE NOT NULL,
            name TEXT NOT NULL,
            tool_type TEXT NOT NULL,  -- 'python', 'r', 'cli'
            library TEXT NOT NULL,
            function TEXT NOT NULL,
            description TEXT,
            parameters TEXT,  -- JSON
            inputs TEXT,  -- JSON
            outputs TEXT,  -- JSON
            requirements TEXT,  -- JSON
            implementation TEXT,  -- JSON with call templates
            xml_path TEXT,
            created_at TEXT,
            updated_at TEXT
        )
    """)

    # Biomni workflows table
    cursor.execute("""
        CREATE TABLE biomni_workflows (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            workflow_id TEXT UNIQUE NOT NULL,
            name TEXT NOT NULL,
            domain TEXT NOT NULL,
            function_name TEXT NOT NULL,
            description TEXT,
            tool_calls TEXT,  -- JSON list of tool_function IDs
            is_multi_step BOOLEAN,
            parameters TEXT,  -- JSON
            inputs TEXT,  -- JSON
            outputs TEXT,  -- JSON
            ga_path TEXT,
            created_at TEXT,
            updated_at TEXT
        )
    """)

    # Indexes
    cursor.execute("CREATE INDEX idx_tool_type ON tool_functions(tool_type)")
    cursor.execute("CREATE INDEX idx_tool_library ON tool_functions(library)")
    cursor.execute("CREATE INDEX idx_workflow_domain ON biomni_workflows(domain)")
    cursor.execute("CREATE INDEX idx_workflow_multi_step ON biomni_workflows(is_multi_step)")

    conn.commit()
    conn.close()
    print(f"Initialized database: {DB_PATH}")


def index_tool_functions(tools: List[ToolFunction]):
    """Index tool-functions into the database."""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    now = datetime.now().isoformat()

    for tool in tools:
        cursor.execute("""
            INSERT OR REPLACE INTO tool_functions (
                tool_id, name, tool_type, library, function,
                description, parameters, inputs, outputs, requirements,
                implementation, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            tool.id, tool.name, tool.tool_type, tool.library, tool.function,
            tool.description,
            json.dumps(tool.parameters),
            json.dumps(tool.inputs),
            json.dumps(tool.outputs),
            json.dumps(tool.requirements),
            json.dumps(tool.implementation),
            now, now
        ))

    conn.commit()
    conn.close()
    print(f"Indexed {len(tools)} tool-functions")


def index_workflows(workflows: List[BiomniWorkflow]):
    """Index Biomni workflows into the database."""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    now = datetime.now().isoformat()

    for wf in workflows:
        cursor.execute("""
            INSERT OR REPLACE INTO biomni_workflows (
                workflow_id, name, domain, function_name,
                description, tool_calls, is_multi_step,
                parameters, inputs, outputs, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            wf.id, wf.name, wf.domain, wf.function_name,
            wf.description, json.dumps(wf.tool_calls), wf.is_multi_step,
            json.dumps(wf.parameters),
            json.dumps(wf.inputs),
            json.dumps(wf.outputs),
            now, now
        ))

    conn.commit()
    conn.close()
    print(f"Indexed {len(workflows)} workflows")


# ============================================================================
# MAIN
# ============================================================================

def main():
    print("=" * 80)
    print("BIOMNI COMPREHENSIVE TOOL INDEXER")
    print("=" * 80)

    # 1. Initialize database
    print("\n[1] Initializing database...")
    init_database()

    # 2. Extract tool-functions
    print("\n[2] Extracting atomic tool-functions...")
    tools = extract_all_tool_functions()
    print(f"    Found {len(tools)} tool-functions:")
    print(f"      - Python: {len([t for t in tools if t.tool_type == 'python'])}")
    print(f"      - R: {len([t for t in tools if t.tool_type == 'r'])}")
    print(f"      - CLI: {len([t for t in tools if t.tool_type == 'cli'])}")

    # 3. Extract Biomni workflows
    print("\n[3] Extracting Biomni workflows...")
    workflows = extract_biomni_workflows()
    multi_step = [w for w in workflows if w.is_multi_step]
    single_step = [w for w in workflows if not w.is_multi_step]
    print(f"    Found {len(workflows)} workflows:")
    print(f"      - Multi-step (2+ tool calls): {len(multi_step)}")
    print(f"      - Single-step (0-1 tool calls): {len(single_step)}")

    # 4. Index to database
    print("\n[4] Indexing to database...")
    index_tool_functions(tools)
    index_workflows(workflows)

    # 5. Generate XML wrappers for ALL atomic tools
    print("\n[5] Generating XML wrappers for atomic tools...")
    TOOLS_OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    xml_count = 0
    xml_errors = 0
    for tool in tools:  # Generate ALL
        try:
            generate_tool_xml(tool, TOOLS_OUTPUT_DIR)
            xml_count += 1
        except Exception as e:
            xml_errors += 1
            if xml_errors <= 5:  # Only show first 5 errors
                print(f"    Error generating XML for {tool.id}: {e}")
    print(f"    Generated {xml_count} XML wrappers, {xml_errors} errors")

    # 6. Generate .ga workflow files for ALL Biomni functions
    print("\n[6] Generating .ga workflow files...")
    WORKFLOWS_OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    ga_count = 0
    ga_errors = 0
    for wf in workflows:  # Generate ALL
        try:
            generate_workflow_ga(wf, WORKFLOWS_OUTPUT_DIR)
            ga_count += 1
        except Exception as e:
            ga_errors += 1
            if ga_errors <= 5:  # Only show first 5 errors
                print(f"    Error generating GA for {wf.id}: {e}")
    print(f"    Generated {ga_count} workflow files, {ga_errors} errors")

    # Summary
    print("\n" + "=" * 80)
    print("SUMMARY")
    print("=" * 80)
    print(f"Database: {DB_PATH}")
    print(f"Tool-functions indexed: {len(tools)}")
    print(f"  - Python library functions: {len([t for t in tools if t.tool_type == 'python'])}")
    print(f"  - R package functions: {len([t for t in tools if t.tool_type == 'r'])}")
    print(f"  - CLI tool commands: {len([t for t in tools if t.tool_type == 'cli'])}")
    print(f"Biomni workflows indexed: {len(workflows)}")
    print(f"  - Multi-step: {len(multi_step)}")
    print(f"  - Single-step: {len(single_step)}")
    print(f"XML wrappers: {TOOLS_OUTPUT_DIR}")
    print(f"Workflow files: {WORKFLOWS_OUTPUT_DIR}")
    print("=" * 80)


if __name__ == "__main__":
    main()
