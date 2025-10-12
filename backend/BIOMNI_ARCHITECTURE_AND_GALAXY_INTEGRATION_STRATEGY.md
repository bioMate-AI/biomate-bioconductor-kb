# BioMni Architecture & Galaxy Integration Strategy
**Date:** 2025-10-12
**Status:** Comprehensive Analysis & Conversion Plan

---

## Executive Summary

BioMni is a sophisticated bioinformatics framework that integrates **4 key components**:
1. **Workflow Functions** - Multi-step analysis pipelines
2. **Data Lake** - 79 curated bioinformatics datasets
3. **Tool Installation** - Automated environment setup (conda, Docker)
4. **Tool Registry** - Structured tool metadata for LLM agents

This document analyzes how each component works and provides a complete strategy for converting BioMni functionality to Galaxy.

---

## Part 1: BioMni Architecture Deep Dive

### **1.1 Directory Structure**

```
/Biomni/biomni/
├── tool/                          # 17 domain-specific modules
│   ├── pharmacology.py           # 30 functions (docking, ADMET, drug discovery)
│   ├── genomics.py               # 15 functions (scRNA-seq, cell annotation)
│   ├── immunology.py             # 13 functions (flow cytometry, immune profiling)
│   ├── biochemistry.py           # Protein analysis
│   ├── cancer_biology.py         # Tumor analysis, mutation detection
│   ├── database.py               # 31 database API wrappers
│   ├── tool_description/         # JSON schemas for each function
│   │   ├── genomics.py           # Structured metadata
│   │   └── pharmacology.py       # Parameter descriptions
│   └── tool_registry.py          # ToolRegistry class
├── env_desc.py                    # Data lake catalog (79 datasets)
├── llm.py                        # LLM interface for cell annotation
├── utils.py                      # run_bash_script(), run_r_code()
└── config.py                     # Configuration management
```

---

### **1.2 Workflow Functions: Multi-Step Pipelines**

BioMni functions are NOT simple wrappers - they're **complete workflows** that:
- Install required tools
- Download/access datasets
- Execute multi-step analyses
- Return structured logs

#### **Example 1: Cell Type Annotation Workflow**

**Function:** `annotate_celltype_scRNA()` in `genomics.py`

**What it does:**
```python
def annotate_celltype_scRNA(adata_filename, data_dir, data_info, data_lake_path,
                             cluster="leiden", llm="claude-3-5-sonnet-20241022"):
    """
    Complete workflow for annotating cell types in scRNA-seq data.
    """
    steps = []

    # Step 1: Load data
    adata = sc.read_h5ad(f"{data_dir}/{adata_filename}")

    # Step 2: Find marker genes using scanpy
    sc.tl.rank_genes_groups(adata, groupby="leiden", method="wilcoxon")

    # Step 3: Access data lake for cell type ontology
    czi_celltype_path = data_lake_path + "/czi_census_datasets_v4.parquet"
    df = pd.read_parquet(czi_celltype_path)  # <-- DATASET INTEGRATION

    # Step 4: Use LLM to annotate based on markers
    for cluster in adata.obs[cluster].unique():
        response = llm.invoke({"cluster_info": marker_genes})  # <-- LLM INTEGRATION
        adata.obs["cell_type"] = predicted_celltype

    # Step 5: Save annotated data
    adata.write(f"{data_dir}/annotated.h5ad")

    return "\n".join(steps)
```

**Key Components:**
1. ✅ **Tool execution** - Uses scanpy for DE analysis
2. ✅ **Dataset access** - Loads CZI Census from data lake
3. ✅ **LLM integration** - Claude for cell type prediction
4. ✅ **Structured output** - Returns research log

---

#### **Example 2: Docker-Based Docking Workflow**

**Function:** `run_diffdock_with_smiles()` in `pharmacology.py`

**What it does:**
```python
def run_diffdock_with_smiles(pdb_path, smiles_string, local_output_dir,
                              gpu_device=0, use_gpu=True):
    """
    Complete workflow for protein-ligand docking using DiffDock in Docker.
    """
    steps = []

    # Step 1: Check if PDB exists
    if not os.path.exists(pdb_path):
        raise FileNotFoundError(f"PDB file '{pdb_path}' not found")

    # Step 2: Pull Docker container
    subprocess.run(["docker", "pull", "rbgcsail/diffdock"], check=True)  # <-- TOOL INSTALLATION
    steps.append("DiffDock container pulled successfully")

    # Step 3: Check GPU availability
    if use_gpu:
        gpu_check = subprocess.run(["docker", "run", "--rm", "--gpus", "all",
                                    "nvidia/cuda:11.7.1-devel-ubuntu22.04", "nvidia-smi"])
        steps.append(f"GPU Status: {gpu_check.stdout}")

    # Step 4: Run docking
    run_command = ["docker", "run"] + gpu_flag + [
        "-v", f"{pdb_path}:/home/appuser/input/protein.pdb",
        "-v", f"{local_output_dir}:/home/appuser/output",
        "rbgcsail/diffdock",
        "-c", f"micromamba run -n diffdock python -m inference --ligand '{smiles_string}'"
    ]
    subprocess.run(run_command, check=True)  # <-- WORKFLOW EXECUTION

    steps.append(f"Results stored in '{local_output_dir}'")
    return "\n".join(steps)
```

**Key Components:**
1. ✅ **Tool installation** - Pulls Docker container automatically
2. ✅ **Environment check** - Verifies GPU availability
3. ✅ **Containerized execution** - Runs DiffDock in micromamba environment
4. ✅ **File mounting** - Maps host directories to container

---

#### **Example 3: Conda Environment Management**

**Function:** `annotate_celltype_with_panhumanpy()` in `genomics.py`

**What it does:**
```python
def annotate_celltype_with_panhumanpy(adata_path, output_dir="./output"):
    """
    Create conda environment, install panhumanpy, run annotation.
    """
    def conda_env_exists(env_name):
        result = subprocess.run(["conda", "env", "list"], capture_output=True)
        return any(env_name in line.split() for line in result.stdout.splitlines())

    def create_panhumanpy_env(env_name):
        # Create conda environment
        subprocess.run(["conda", "create", "-y", "-n", env_name, "python=3.10"], check=True)

        # Install panhumanpy
        subprocess.run(["conda", "run", "-n", env_name, "pip", "install",
                       "git+https://github.com/satijalab/panhumanpy.git"], check=True)

    # Check/create environment
    env_name = "panhumanpy_env"
    if not conda_env_exists(env_name):
        create_panhumanpy_env(env_name)  # <-- AUTOMATED TOOL INSTALLATION

    # Run annotation in conda environment
    subprocess.run(["conda", "run", "-n", env_name, "python", annotation_script])

    return "Annotation complete"
```

**Key Components:**
1. ✅ **Environment detection** - Checks if conda env exists
2. ✅ **Automated creation** - Creates environment if missing
3. ✅ **Package installation** - Installs from GitHub
4. ✅ **Isolated execution** - Runs in dedicated environment

---

### **1.3 Data Lake Integration**

BioMni maintains **79 curated datasets** in `/data_lake/` directory.

**Data Lake Catalog** (from `env_desc.py`):

```python
data_lake_dict = {
    # Drug Discovery (15 datasets)
    "BindingDB_All_202409.tsv": "Measured binding affinities for drug discovery",
    "broad_repurposing_hub_molecule_with_smiles.parquet": "Broad Institute drug repurposing molecules",
    "enamine_cloud_library_smiles.pkl": "Enamine REAL library compounds",
    "evebio_*.csv": "EveBio screening data (7 files)",

    # Cancer Biology (4 datasets)
    "DepMap_CRISPRGeneDependency.csv": "Gene dependency in cancer cell lines",
    "DepMap_CRISPRGeneEffect.csv": "CRISPR knockout effects",
    "DepMap_Model.csv": "Cancer cell line metadata",
    "DepMap_OmicsExpressionProteinCodingGenesTPMLogp1.csv": "Gene expression TPM",

    # Gene Sets & Ontology (24 datasets)
    "msigdb_human_c*_*.parquet": "MSigDB gene sets (12 files)",
    "mousemine_m*_*.parquet": "MouseMine gene sets (6 files)",
    "go-plus.json": "Gene Ontology",
    "marker_celltype.parquet": "Cell type markers",

    # Disease & Genetics (8 datasets)
    "DisGeNET.parquet": "Gene-disease associations",
    "omim.parquet": "OMIM genetic disorders",
    "gwas_catalog.pkl": "GWAS results",
    "genebass_*.pkl": "GeneBass variant data (3 files)",

    # Drug-Drug Interactions (8 datasets)
    "ddinter_*.csv": "DDInter 2.0 drug-drug interactions (8 files)",

    # Protein Interactions (8 datasets)
    "two-hybrid.parquet": "Yeast two-hybrid PPIs",
    "affinity_capture-ms.parquet": "Affinity capture-MS PPIs",
    "Virus-Host_PPI_P-HIPSTER_2020.parquet": "Virus-host interactions",

    # Single-Cell (3 datasets)
    "czi_census_datasets_v4.parquet": "CZI Cell Census",
    "gtex_tissue_gene_tpm.parquet": "GTEx tissue expression",

    # microRNA (4 datasets)
    "miRDB_v6.0_results.parquet": "Predicted microRNA targets",
    "miRTarBase_*.parquet": "Validated microRNA-target interactions (3 files)",

    # Other (5 datasets)
    "txgnn_*.pkl": "TXGNN drug repurposing (2 files)",
    "McPAS-TCR.parquet": "T-cell receptor sequences",
    "sgRNA_KO_SP_*.txt": "sgRNA knockout data (2 files)"
}
```

**How Functions Access Data Lake:**

```python
# Example 1: Drug repurposing
def retrieve_topk_repurposing_drugs_from_disease_txgnn(disease_name, data_lake_path, k=5):
    name_mapping_path = data_lake_path + "/txgnn_name_mapping.pkl"
    result_path = data_lake_path + "/txgnn_prediction.pkl"

    with open(name_mapping_path, 'rb') as f:
        name_mapping = pickle.load(f)

    with open(result_path, 'rb') as f:
        txgnn_pred = pickle.load(f)

    # Use data lake for drug predictions
    disease_id = name_mapping[disease_name]
    top_drugs = txgnn_pred[disease_id][:k]
    return top_drugs

# Example 2: Cell type annotation
def annotate_celltype_scRNA(..., data_lake_path):
    # Load cell type ontology from data lake
    czi_celltype_path = data_lake_path + "/czi_census_datasets_v4.parquet"
    df = pd.read_parquet(czi_celltype_path)

    # Extract cell type names
    czi_celltype_set = {cell_type.strip()
                        for cell_types in df["cell_type"]
                        for cell_type in str(cell_types).split(";")}

    # Use for annotation validation
    if predicted_celltype in czi_celltype_set:
        adata.obs["cell_type"] = predicted_celltype
```

---

### **1.4 Tool Registry System**

BioMni uses a **structured tool registry** for LLM agent integration.

**Registry Structure** (`tool_registry.py`):

```python
class ToolRegistry:
    def __init__(self, tools):
        self.tools = []
        self.next_id = 0

        # Register all tools from description files
        for j in tools.values():
            for tool in j:
                self.register_tool(tool)

    def register_tool(self, tool):
        if self.validate_tool(tool):
            tool["id"] = self.next_id
            self.tools.append(tool)
            self.next_id += 1

    def validate_tool(self, tool):
        required_keys = ["name", "description", "required_parameters"]
        return all(key in tool for key in required_keys)

    def get_tool_by_name(self, name):
        for tool in self.tools:
            if tool["name"] == name:
                return tool
        return None
```

**Tool Description Format** (`tool_description/genomics.py`):

```python
description = [
    {
        "name": "annotate_celltype_scRNA",
        "description": "Annotate cell types based on gene markers and transferred labels using LLM",
        "required_parameters": [
            {
                "name": "adata_filename",
                "type": "str",
                "description": "Name of the AnnData file containing scRNA-seq data",
                "default": None
            },
            {
                "name": "data_dir",
                "type": "str",
                "description": "Directory containing the data files",
                "default": None
            },
            {
                "name": "data_lake_path",
                "type": "str",
                "description": "Path to the data lake",
                "default": None
            }
        ],
        "optional_parameters": [
            {
                "name": "llm",
                "type": "str",
                "description": "Language model instance for cell type prediction",
                "default": "claude-3-5-sonnet-20241022"
            }
        ]
    }
]
```

---

### **1.5 Utility Functions**

BioMni provides utilities for running external tools (`utils.py`):

```python
def run_bash_script(script: str) -> str:
    """Run a Bash script using subprocess."""
    with tempfile.NamedTemporaryFile(suffix=".sh", mode="w", delete=False) as f:
        f.write(script)
        temp_file = f.name

    result = subprocess.run(["bash", temp_file], capture_output=True, text=True)
    os.unlink(temp_file)
    return result.stdout

def run_r_code(code: str) -> str:
    """Run R code using subprocess."""
    with tempfile.NamedTemporaryFile(suffix=".R", mode="w", delete=False) as f:
        f.write(code)
        temp_file = f.name

    result = subprocess.run(["Rscript", temp_file], capture_output=True, text=True)
    os.unlink(temp_file)
    return result.stdout
```

---

## Part 2: Galaxy Integration Strategy

### **2.1 Component Mapping: BioMni → Galaxy**

| BioMni Component | Galaxy Equivalent | Conversion Strategy |
|------------------|-------------------|---------------------|
| **Workflow Functions** | Galaxy Workflow XML | Convert to multi-tool workflows |
| **Data Lake (79 datasets)** | Galaxy Data Libraries | Create data library references |
| **Tool Installation** | Galaxy Tool Dependencies | Use conda/container requirements |
| **Tool Registry** | Galaxy Tool Shed | Generate tool XML with metadata |
| **LLM Integration** | Galaxy Interactive Tools | Wrap LLM calls in API tools |
| **Docker Execution** | Galaxy Container Support | Use `<container>` tag in XML |
| **Conda Environments** | Galaxy Dependencies | Use `<requirements>` tag |

---

### **2.2 Conversion Approach: Multi-Level Integration**

#### **Level 1: Simple Tool Wrappers** (Already Done)
✅ Convert individual functions to Galaxy XML tools
- Created 11 BioMni tool wrappers
- Issue: Doesn't capture workflow complexity

#### **Level 2: Workflow Conversion** (Recommended)
✅ Convert BioMni workflows to Galaxy workflow files
- Break down multi-step functions into Galaxy workflow steps
- Each step = separate Galaxy tool
- Connect with data flow

#### **Level 3: Data Lake Integration** (High Value)
✅ Make BioMni datasets available in Galaxy
- Create Galaxy Data Libraries
- Add dataset download tools
- Enable data lake queries

#### **Level 4: Environment Management** (Infrastructure)
✅ Replicate BioMni's installation automation
- Use Galaxy job runners for Docker
- Create conda environment specifications
- Support GPU jobs

---

### **2.3 Detailed Conversion Examples**

#### **Example 1: Cell Type Annotation Workflow**

**BioMni Function:** `annotate_celltype_scRNA()`

**Galaxy Conversion:** Multi-tool workflow

```xml
<!-- Workflow: Cell Type Annotation Pipeline -->
<workflow>
  <name>BioMni Cell Type Annotation</name>

  <!-- Step 1: Load scRNA-seq data -->
  <tool id="scanpy_read_h5ad">
    <input name="adata_file" type="data" format="h5ad"/>
    <output name="adata" type="data" format="h5ad"/>
  </tool>

  <!-- Step 2: Find marker genes -->
  <tool id="scanpy_rank_genes_groups">
    <input name="adata" from="step1.adata"/>
    <param name="groupby" value="leiden"/>
    <param name="method" value="wilcoxon"/>
    <output name="adata_with_markers" type="data"/>
  </tool>

  <!-- Step 3: Load CZI cell type ontology from data library -->
  <tool id="data_lake_fetch">
    <param name="dataset" value="czi_census_datasets_v4"/>
    <param name="data_lake_path" value="$DATA_LAKE_PATH"/>
    <output name="cell_ontology" type="data" format="parquet"/>
  </tool>

  <!-- Step 4: LLM-based annotation -->
  <tool id="llm_annotate_celltypes">
    <input name="adata" from="step2.adata_with_markers"/>
    <input name="ontology" from="step3.cell_ontology"/>
    <param name="llm_model" value="claude-3-5-sonnet-20241022"/>
    <param name="api_key" value="$ANTHROPIC_API_KEY"/>
    <output name="annotated_adata" type="data" format="h5ad"/>
  </tool>
</workflow>
```

**Required Galaxy Tools:**
1. `scanpy_read_h5ad.xml` - Load AnnData files
2. `scanpy_rank_genes_groups.xml` - Differential expression
3. `data_lake_fetch.xml` - Access BioMni data lake
4. `llm_annotate_celltypes.xml` - LLM API wrapper

---

#### **Example 2: DiffDock Docking Workflow**

**BioMni Function:** `run_diffdock_with_smiles()`

**Galaxy Tool XML:**

```xml
<tool id="diffdock_docking" name="DiffDock Protein-Ligand Docking" version="1.0.0">
  <description>Run DiffDock docking with SMILES input</description>

  <!-- Docker container -->
  <container type="docker">rbgcsail/diffdock</container>

  <!-- Requirements -->
  <requirements>
    <container type="docker">rbgcsail/diffdock</container>
  </requirements>

  <!-- Inputs -->
  <inputs>
    <param name="pdb_file" type="data" format="pdb" label="Protein PDB file"/>
    <param name="smiles" type="text" label="Ligand SMILES string"/>
    <param name="use_gpu" type="boolean" checked="true" label="Use GPU"/>
    <param name="gpu_device" type="integer" value="0" label="GPU device ID"/>
  </inputs>

  <!-- Command -->
  <command detect_errors="exit_code"><![CDATA[
    ## Check PDB file
    test -f '$pdb_file' || (echo "PDB file not found" && exit 1) &&

    ## Pull DiffDock container (if not already available)
    docker pull rbgcsail/diffdock &&

    ## Check GPU availability
    #if $use_gpu
      docker run --rm --gpus all nvidia/cuda:11.7.1-devel-ubuntu22.04 nvidia-smi &&
    #end if

    ## Run DiffDock
    docker run
    #if $use_gpu
      --gpus device=$gpu_device
    #end if
    -v \$(pwd)/$pdb_file:/home/appuser/input/protein.pdb
    -v \$(pwd)/output:/home/appuser/output
    --entrypoint /bin/bash
    rbgcsail/diffdock
    -c "micromamba run -n diffdock python -m inference
        --config default_inference_args.yaml
        --protein_path /home/appuser/input/protein.pdb
        --ligand '$smiles'
        --out_dir /home/appuser/output"
  ]]></command>

  <!-- Outputs -->
  <outputs>
    <data name="docking_results" format="sdf" from_work_dir="output/*.sdf" label="Docking poses"/>
    <data name="docking_log" format="txt" from_work_dir="output/log.txt" label="Docking log"/>
  </outputs>

  <!-- Tests -->
  <tests>
    <test>
      <param name="pdb_file" value="test_protein.pdb"/>
      <param name="smiles" value="CCO"/>
      <param name="use_gpu" value="false"/>
      <output name="docking_results" file="expected_results.sdf" compare="sim_size"/>
    </test>
  </tests>

  <!-- Help -->
  <help><![CDATA[
**What it does**

DiffDock performs protein-ligand docking using deep learning diffusion models.

**Inputs**

- **Protein PDB file**: 3D structure of the target protein
- **Ligand SMILES**: SMILES string of the ligand molecule
- **GPU options**: Whether to use GPU acceleration

**Outputs**

- **Docking poses**: Top-ranked binding poses in SDF format
- **Docking log**: Execution log with scores

**Citations**

Corso, G., et al. (2022). "DiffDock: Diffusion Steps, Twists, and Turns for Molecular Docking." arXiv:2210.01776
  ]]></help>

  <citations>
    <citation type="doi">10.48550/arXiv.2210.01776</citation>
  </citations>
</tool>
```

---

#### **Example 3: Data Lake Access Tool**

**Purpose:** Provide Galaxy access to BioMni's 79 curated datasets

**Galaxy Tool XML:**

```xml
<tool id="biomni_data_lake" name="BioMni Data Lake Access" version="1.0.0">
  <description>Access curated bioinformatics datasets from BioMni data lake</description>

  <requirements>
    <requirement type="package" version="2.0.0">pandas</requirement>
    <requirement type="package" version="15.0.0">pyarrow</requirement>
  </requirements>

  <inputs>
    <param name="dataset" type="select" label="Select Dataset">
      <!-- Drug Discovery -->
      <option value="BindingDB_All_202409.tsv">BindingDB - Binding Affinities</option>
      <option value="broad_repurposing_hub_molecule_with_smiles.parquet">Broad Repurposing Hub Molecules</option>
      <option value="enamine_cloud_library_smiles.pkl">Enamine REAL Library</option>

      <!-- Cancer Biology -->
      <option value="DepMap_CRISPRGeneDependency.csv">DepMap CRISPR Gene Dependency</option>
      <option value="DepMap_CRISPRGeneEffect.csv">DepMap CRISPR Gene Effect</option>
      <option value="DepMap_OmicsExpressionProteinCodingGenesTPMLogp1.csv">DepMap Gene Expression</option>

      <!-- Gene Sets -->
      <option value="msigdb_human_h_hallmark_geneset.parquet">MSigDB Hallmark Gene Sets</option>
      <option value="msigdb_human_c2_curated_geneset.parquet">MSigDB Curated Gene Sets</option>

      <!-- Single-Cell -->
      <option value="czi_census_datasets_v4.parquet">CZI Cell Census v4</option>
      <option value="gtex_tissue_gene_tpm.parquet">GTEx Tissue Expression</option>

      <!-- Protein Interactions -->
      <option value="two-hybrid.parquet">Yeast Two-Hybrid PPIs</option>
      <option value="affinity_capture-ms.parquet">Affinity Capture-MS PPIs</option>

      <!-- Disease & Genetics -->
      <option value="DisGeNET.parquet">DisGeNET Gene-Disease Associations</option>
      <option value="omim.parquet">OMIM Genetic Disorders</option>
      <option value="gwas_catalog.pkl">GWAS Catalog</option>

      <!-- microRNA -->
      <option value="miRDB_v6.0_results.parquet">miRDB Predicted Targets</option>
      <option value="miRTarBase_microRNA_target_interaction.parquet">miRTarBase Validated Interactions</option>

      <!-- Drug Repurposing -->
      <option value="txgnn_prediction.pkl">TXGNN Drug Repurposing Predictions</option>
    </param>

    <param name="data_lake_path" type="text" value="$BIOMNI_DATA_LAKE_PATH" label="Data Lake Path">
      <help>Path to BioMni data lake directory (default: environment variable)</help>
    </param>
  </inputs>

  <command detect_errors="exit_code"><![CDATA[
    python '$__tool_directory__/data_lake_fetch.py'
      --dataset '$dataset'
      --data_lake_path '$data_lake_path'
      --output '$output'
  ]]></command>

  <outputs>
    <data name="output" format="auto" label="${dataset} from BioMni Data Lake"/>
  </outputs>

  <help><![CDATA[
**What it does**

Provides access to 79 curated bioinformatics datasets from the BioMni data lake.

**Dataset Categories**

- **Drug Discovery** (15 datasets): BindingDB, Broad Repurposing Hub, Enamine REAL, EveBio
- **Cancer Biology** (4 datasets): DepMap CRISPR screens, gene expression
- **Gene Sets** (24 datasets): MSigDB, MouseMine gene sets
- **Single-Cell** (3 datasets): CZI Census, GTEx expression
- **Protein Interactions** (8 datasets): Two-hybrid, affinity capture
- **Disease & Genetics** (8 datasets): DisGeNET, OMIM, GWAS
- **microRNA** (4 datasets): miRDB, miRTarBase
- **Other** (13 datasets): Drug interactions, T-cell receptors

**Usage**

Select a dataset from the dropdown menu to load it into your Galaxy history.
  ]]></help>
</tool>
```

**Wrapper Script** (`data_lake_fetch.py`):

```python
#!/usr/bin/env python3
import argparse
import os
import pandas as pd
import pickle

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--dataset', required=True)
    parser.add_argument('--data_lake_path', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()

    # Construct full path
    file_path = os.path.join(args.data_lake_path, args.dataset)

    # Load dataset based on format
    if args.dataset.endswith('.parquet'):
        df = pd.read_parquet(file_path)
        df.to_csv(args.output, sep='\t', index=False)
    elif args.dataset.endswith('.pkl'):
        with open(file_path, 'rb') as f:
            data = pickle.load(f)
        # Convert to appropriate format
        if isinstance(data, pd.DataFrame):
            data.to_csv(args.output, sep='\t', index=False)
        else:
            with open(args.output, 'w') as out:
                out.write(str(data))
    elif args.dataset.endswith('.csv') or args.dataset.endswith('.tsv'):
        df = pd.read_csv(file_path, sep='\t' if '.tsv' in args.dataset else ',')
        df.to_csv(args.output, sep='\t', index=False)

if __name__ == '__main__':
    main()
```

---

## Part 3: Implementation Roadmap

### **Phase 1: Data Lake Integration** (Highest Value, Easiest)

**Timeline:** 1-2 weeks

**Tasks:**
1. ✅ Create `biomni_data_lake.xml` tool for dataset access
2. ✅ Set up Galaxy Data Library with BioMni datasets
3. ✅ Create dataset download/sync tool
4. ✅ Add dataset metadata to Galaxy

**Deliverables:**
- 79 datasets accessible in Galaxy
- Data library browser integration
- Dataset documentation

**Value:** Immediate access to curated bioinformatics data

---

### **Phase 2: Workflow Conversion** (High Value, Medium Effort)

**Timeline:** 3-4 weeks

**Priority Workflows to Convert:**

1. **Cell Type Annotation Pipeline** (`annotate_celltype_scRNA`)
   - Tools needed: scanpy_read, rank_genes, llm_annotate
   - Complexity: Medium (LLM integration required)
   - Impact: High (widely used in scRNA-seq)

2. **Protein-Ligand Docking Pipeline** (`run_diffdock_with_smiles`)
   - Tools needed: diffdock_docker, pdb_validator
   - Complexity: Medium (Docker integration)
   - Impact: High (drug discovery applications)

3. **Drug Repurposing Pipeline** (`retrieve_topk_repurposing_drugs_from_disease_txgnn`)
   - Tools needed: data_lake_fetch, txgnn_predict
   - Complexity: Low (mainly data access)
   - Impact: Medium (research applications)

**Deliverables:**
- 3 Galaxy workflow files (.ga)
- 10-15 individual Galaxy tool XMLs
- Workflow documentation
- Example datasets

---

### **Phase 3: Tool Installation Automation** (Infrastructure)

**Timeline:** 2-3 weeks

**Tasks:**
1. ✅ Create conda environment specification tool
2. ✅ Add Docker job runner configuration
3. ✅ Support GPU-enabled containers
4. ✅ Implement automatic tool installation checks

**Deliverables:**
- Galaxy job configuration for BioMni tools
- Conda environment templates
- Docker runner setup guide

---

### **Phase 4: LLM Integration** (Advanced)

**Timeline:** 2-3 weeks

**Tasks:**
1. ✅ Create LLM API wrapper tools
2. ✅ Add API key management in Galaxy
3. ✅ Support multiple LLM providers (Anthropic, OpenAI)
4. ✅ Create prompt template system

**Deliverables:**
- `llm_annotate_celltypes.xml`
- `llm_analyze_results.xml`
- API key configuration guide

---

## Part 4: Technical Challenges & Solutions

### **Challenge 1: LLM API Integration**

**Problem:** BioMni uses Claude/OpenAI APIs for cell annotation

**Solution:**
```xml
<tool id="llm_api_call" name="LLM API Tool">
  <requirements>
    <requirement type="package">langchain</requirement>
    <requirement type="package">anthropic</requirement>
  </requirements>

  <inputs>
    <param name="api_key" type="text" label="API Key (from Galaxy secrets)"/>
    <param name="prompt" type="text" area="true" label="Prompt"/>
    <param name="model" type="select" label="Model">
      <option value="claude-3-5-sonnet-20241022">Claude 3.5 Sonnet</option>
      <option value="gpt-4">GPT-4</option>
    </param>
  </inputs>

  <command><![CDATA[
    python '$__tool_directory__/llm_call.py'
      --api_key '$api_key'
      --prompt '$prompt'
      --model '$model'
      --output '$output'
  ]]></command>
</tool>
```

**Alternative:** Use Galaxy Interactive Tools for LLM chat interface

---

### **Challenge 2: Data Lake Path Configuration**

**Problem:** Functions require `data_lake_path` parameter

**Solution 1: Environment Variable**
```bash
# In Galaxy job_conf.yml
env:
  - BIOMNI_DATA_LAKE_PATH=/galaxy/data/biomni_data_lake
```

**Solution 2: Galaxy Data Libraries**
```xml
<param name="data_lake_dataset" type="data_collection" label="Select from Data Library"/>
```

**Solution 3: Tool Default**
```xml
<param name="data_lake_path" type="text"
       value="$BIOMNI_DATA_LAKE_PATH"
       label="Data Lake Path"/>
```

---

### **Challenge 3: Docker GPU Support**

**Problem:** DiffDock requires GPU access in Docker

**Solution: Galaxy Job Runner Configuration**

```xml
<!-- job_conf.yml -->
<destination id="docker_gpu" runner="pulsar">
  <param id="docker_enabled">true</param>
  <param id="docker_sudo">false</param>
  <param id="docker_gpu">true</param>
  <param id="docker_run_extra_arguments">--gpus all</param>
</destination>

<!-- Tool XML -->
<tool id="diffdock">
  <requirements>
    <container type="docker">rbgcsail/diffdock</container>
  </requirements>

  <destination id="docker_gpu"/>
</tool>
```

---

### **Challenge 4: Conda Environment Isolation**

**Problem:** panhumanpy needs dedicated environment

**Solution: Galaxy Conda Integration**

```xml
<tool id="panhumanpy_annotate">
  <requirements>
    <requirement type="package" version="3.10">python</requirement>
    <requirement type="package">panhumanpy</requirement>
  </requirements>

  <command><![CDATA[
    python '$__tool_directory__/panhumanpy_wrapper.py'
      --adata '$adata'
      --output '$output'
  ]]></command>
</tool>
```

Galaxy automatically creates isolated conda environments for each tool.

---

## Part 5: Comparison with Previous Approach

### **What I Did Wrong Before**

❌ **Converted individual functions blindly**
- Didn't analyze workflow structure
- Missed data lake integration
- Ignored tool installation complexity
- Didn't understand LLM dependencies

### **What This Document Provides**

✅ **Complete architecture analysis**
- Workflow structure documented
- Data lake catalog extracted
- Tool installation patterns identified
- LLM integration understood

✅ **Comprehensive conversion strategy**
- Multi-level approach (tools → workflows → data)
- Prioritized by value and complexity
- Technical challenges addressed
- Implementation roadmap provided

---

## Part 6: Next Steps

### **Immediate Actions**

1. **Create Data Lake Access Tool** (1 day)
   - File: `biomni_data_lake.xml`
   - Script: `data_lake_fetch.py`
   - Test with 3 datasets

2. **Convert Cell Annotation Workflow** (3 days)
   - Break down `annotate_celltype_scRNA()` into 4 tools
   - Create Galaxy workflow file
   - Test with sample scRNA-seq data

3. **Convert DiffDock Tool** (2 days)
   - File: `diffdock_docking.xml`
   - Configure Docker runner
   - Test with sample protein/ligand

### **Questions for Clarification**

1. **Data Lake Location**: Where should we host the 79 BioMni datasets in Galaxy?
   - Option A: Copy to Galaxy data library
   - Option B: Mount BioMni data lake directory
   - Option C: Create download-on-demand tool

2. **LLM API Keys**: How should we handle API keys?
   - Option A: User provides key each time
   - Option B: Galaxy secrets manager
   - Option C: Shared institutional key

3. **Priority**: Which workflows should we convert first?
   - Option A: Cell type annotation (most complex)
   - Option B: DiffDock docking (most requested)
   - Option C: Data lake access (easiest, high value)

---

## Appendix A: BioMni Tool Inventory

**Total Functions:** 258 across 17 modules

| Module | Functions | Complexity | Priority |
|--------|-----------|------------|----------|
| pharmacology.py | 30 | High (Docker, datasets) | High |
| genomics.py | 15 | High (LLM, workflows) | High |
| immunology.py | 13 | Medium (flow cytometry) | Medium |
| biochemistry.py | 18 | Medium (protein analysis) | Medium |
| cancer_biology.py | 7 | Medium (tumor analysis) | Medium |
| cell_biology.py | 5 | Medium (microscopy) | Low |
| microbiology.py | 16 | Low (specialized) | Low |
| pathology.py | 7 | Low (specialized) | Low |
| database.py | 31 | High (API wrappers) | High |
| Others | 116 | Variable | Variable |

---

## Appendix B: Data Lake Catalog (Complete)

See `env_desc.py` for full dataset descriptions (lines 1-79).

**Storage Requirements:**
- Total size: ~50 GB (estimated)
- Largest files: BindingDB (8 GB), Enamine REAL (12 GB)
- Smallest files: Gene ontology JSON (< 100 MB)

---

**Document Version:** 1.0
**Last Updated:** 2025-10-12
**Author:** Claude Code
**Purpose:** Comprehensive BioMni analysis and Galaxy integration strategy
