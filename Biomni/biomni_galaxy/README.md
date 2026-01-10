# Biomni Galaxy Tools Docker Image

A containerized version of all 271 Biomni bioinformatics tools, organized by 21 domains, ready for Galaxy integration.

## Quick Start

### For ARM64 Users (Apple Silicon Mac, AWS Graviton, etc.)

The pre-built image is available locally:

```bash
# List all available domains
docker run --rm biomate/biomni-tools:latest biomni-tool --list-domains

# List functions in a specific domain
docker run --rm biomate/biomni-tools:latest biomni-tool genomics --list-functions

# Run a tool with data
docker run --rm -v $(pwd)/data:/data biomate/biomni-tools:latest \
    biomni-tool molecular_biology annotate_open_reading_frames \
    --sequence "ATGATGATGATGATG" --min_length 9 --output /data/results.json
```

### For AMD64/x86_64 Users (Most Linux servers, Intel Macs)

You need to rebuild the image for your architecture:

```bash
cd /path/to/Biomni
docker build -t biomate/biomni-tools:latest -f biomni_galaxy/docker/Dockerfile .
```

Build time: ~10-15 minutes depending on network speed.

---

## Architecture Information

| Current Build | Architecture | Compatible Systems |
|--------------|--------------|-------------------|
| `biomate/biomni-tools:latest` | ARM64 | Apple Silicon Mac (M1/M2/M3), AWS Graviton, Raspberry Pi 4, Oracle Ampere |

**To run on AMD64/x86_64 systems**, you must rebuild the image (see above).

---

## Container Structure

```
/opt/biomni/
├── bin/
│   ├── biomni-tool           # Main CLI wrapper
│   ├── create_manifest.py    # Tool manifest generator
│   └── verify-domains.sh     # Domain import verification
├── src/
│   └── biomni/               # Biomni Python package (editable install)
├── galaxy_tools/             # 271 Galaxy tool wrappers
│   ├── biochemistry/         (9 tools)
│   ├── bioengineering/       (12 tools)
│   ├── bioimaging/           (tools)
│   ├── biophysics/           (3 tools)
│   ├── cancer_biology/       (7 tools)
│   ├── cell_biology/         (5 tools)
│   ├── database/             (53 tools)
│   ├── genetics/             (10 tools)
│   ├── genomics/             (22 tools)
│   ├── glycoengineering/     (3 tools)
│   ├── immunology/           (14 tools)
│   ├── lab_automation/       (6 tools)
│   ├── literature/           (9 tools)
│   ├── microbiology/         (17 tools)
│   ├── molecular_biology/    (28 tools)
│   ├── pathology/            (7 tools)
│   ├── pharmacology/         (51 tools)
│   ├── physiology/           (11 tools)
│   ├── protocols/            (2 tools)
│   ├── support_tools/        (8 tools)
│   ├── synthetic_biology/    (8 tools)
│   └── systems_biology/      (8 tools)
└── tool_manifest.json        # JSON registry of all tools

/data/                        # Default working directory (mount your data here)
```

---

## Usage Examples

### 1. Basic Tool Execution

```bash
# Annotate ORFs in a DNA sequence
docker run --rm biomate/biomni-tools:latest \
    biomni-tool molecular_biology annotate_open_reading_frames \
    --sequence "ATGATGATGATGATGATGATGATGATGATGATGATGATGATGATGATGATGATGATGATG" \
    --min_length 9

# Output: JSON with ORF locations, sequences, and translations
```

### 2. Working with Files

```bash
# Mount a local directory to /data in the container
docker run --rm -v /path/to/your/data:/data biomate/biomni-tools:latest \
    biomni-tool genomics gene_set_enrichment_analysis \
    --genes "TP53,BRCA1,EGFR,MYC" \
    --output /data/enrichment_results.json
```

### 3. Interactive Mode

```bash
# Start an interactive shell inside the container
docker run -it --rm -v $(pwd):/data biomate/biomni-tools:latest bash

# Inside container:
biomni-tool --list-domains
biomni-tool pharmacology --list-functions
python3 -c "from biomni.tool.genomics import gene_set_enrichment_analysis; help(gene_set_enrichment_analysis)"
```

### 4. Get Help for a Specific Function

```bash
docker run --rm biomate/biomni-tools:latest \
    biomni-tool molecular_biology annotate_open_reading_frames --help
```

---

## All 21 Domains

| Domain | Description | Example Functions |
|--------|-------------|-------------------|
| `biochemistry` | Enzyme kinetics, protein analysis | `analyze_enzyme_kinetics_assay`, `analyze_protein_conservation` |
| `bioengineering` | Bioprocess, particle tracking | `analyze_particle_tracking`, `design_bioreactor` |
| `bioimaging` | Image analysis, microscopy | `segment_cells`, `analyze_fluorescence` |
| `biophysics` | Molecular dynamics, structure | `analyze_md_trajectory`, `calculate_binding_energy` |
| `cancer_biology` | Tumor analysis, biomarkers | `analyze_tumor_heterogeneity`, `identify_driver_mutations` |
| `cell_biology` | Cell cycle, organelles | `analyze_cell_cycle`, `track_organelles` |
| `database` | Biological databases | `query_uniprot`, `fetch_pdb_structure`, `search_chembl` |
| `genetics` | Population genetics, GWAS | `run_gwas_analysis`, `calculate_ld` |
| `genomics` | NGS, single-cell, ChIP-seq | `gene_set_enrichment_analysis`, `annotate_celltype_scRNA` |
| `glycoengineering` | Glycan analysis | `predict_glycosylation_sites`, `analyze_glycan_structure` |
| `immunology` | Immune profiling | `analyze_tcr_repertoire`, `predict_epitopes` |
| `lab_automation` | Protocol automation | `design_experiment`, `generate_protocol` |
| `literature` | Paper search, PDF extraction | `query_pubmed`, `query_arxiv`, `extract_pdf_content` |
| `microbiology` | Microbiome, AMR | `analyze_microbiome_composition`, `predict_amr` |
| `molecular_biology` | ORFs, primers, cloning | `annotate_open_reading_frames`, `design_primers` |
| `pathology` | Histology, diagnosis | `analyze_histology_image`, `classify_tissue` |
| `pharmacology` | Drug discovery, ADMET | `predict_drug_target`, `calculate_admet` |
| `physiology` | Organ systems, signals | `analyze_ecg`, `model_pharmacokinetics` |
| `protocols` | Experimental protocols | `generate_protocol`, `validate_protocol` |
| `support_tools` | Utilities, format conversion | `convert_file_format`, `validate_data` |
| `synthetic_biology` | Circuit design, parts | `design_genetic_circuit`, `optimize_codon_usage` |
| `systems_biology` | Metabolic modeling, networks | `run_fba_analysis`, `analyze_network_topology` |

---

## Installed Dependencies

The Docker image includes all dependencies for all 21 domains:

### Core Packages
- `numpy`, `scipy`, `pandas`, `matplotlib`, `seaborn`
- `biopython` - Core bioinformatics
- `scikit-learn` - Machine learning
- `langchain`, `langchain-core` - LLM integration

### Domain-Specific Packages

| Category | Packages |
|----------|----------|
| **Genomics/Single-cell** | `scanpy`, `gseapy`, `gget`, `pybedtools`, `pybiomart`, `msprime`, `cooler` |
| **Deep Learning** | `torch` (CPU), `transformers`, `accelerate`, `sentencepiece` |
| **Protein Analysis** | `fair-esm`, `esm` (ESM3) |
| **Chemistry** | `rdkit`, `pubchempy` |
| **Systems Biology** | `cobra`, `networkx`, `python-libsbml` |
| **Image Processing** | `scikit-image`, `opencv-python-headless`, `Pillow`, `nibabel`, `SimpleITK` |
| **Flow Cytometry** | `flowio`, `flowkit`, `FlowCytometryTools` |
| **Literature** | `arxiv`, `scholarly`, `PyPDF2`, `beautifulsoup4`, `googlesearch-python` |
| **Tracking** | `trackpy`, `pykalman` |

---

## Galaxy Integration

Each tool in `galaxy_tools/` has two files:

1. **`{function_name}.xml`** - Galaxy tool definition
2. **`{function_name}.py`** - Python wrapper script

### To integrate with Galaxy:

1. Copy XML files to your Galaxy tools directory:
   ```bash
   docker cp $(docker create biomate/biomni-tools:latest):/opt/biomni/galaxy_tools ./galaxy_tools
   ```

2. Add entries to `tool_conf.xml`:
   ```xml
   <section id="biomni" name="Biomni Tools">
     <tool file="biomni/molecular_biology/annotate_open_reading_frames.xml" />
     <tool file="biomni/genomics/gene_set_enrichment_analysis.xml" />
     <!-- ... more tools ... -->
   </section>
   ```

3. Configure Galaxy to use the Docker container for tool execution.

---

## Building for Different Architectures

### Multi-Architecture Build (requires Docker Buildx)

```bash
# Create builder for multi-arch
docker buildx create --name multiarch --use

# Build for both AMD64 and ARM64
docker buildx build --platform linux/amd64,linux/arm64 \
    -t biomate/biomni-tools:latest \
    -f biomni_galaxy/docker/Dockerfile \
    --push .
```

### Build for AMD64 Only

```bash
docker build --platform linux/amd64 \
    -t biomate/biomni-tools:amd64 \
    -f biomni_galaxy/docker/Dockerfile .
```

### Build for ARM64 Only

```bash
docker build --platform linux/arm64 \
    -t biomate/biomni-tools:arm64 \
    -f biomni_galaxy/docker/Dockerfile .
```

---

## Troubleshooting

### "exec format error"
You're trying to run an ARM64 image on AMD64 or vice versa. Rebuild for your architecture.

### Import errors inside container
Run the verification script:
```bash
docker run --rm biomate/biomni-tools:latest python3 -c "
domains = ['biochemistry', 'bioengineering', 'biophysics', 'cancer_biology', 'cell_biology',
           'database', 'genetics', 'genomics', 'glycoengineering', 'immunology',
           'lab_automation', 'literature', 'microbiology', 'molecular_biology', 'pathology',
           'pharmacology', 'physiology', 'protocols', 'support_tools', 'synthetic_biology',
           'systems_biology']
for d in domains:
    try:
        __import__(f'biomni.tool.{d}')
        print(f'✓ {d}')
    except Exception as e:
        print(f'✗ {d}: {e}')
"
```

### Memory issues
Some tools (especially those using PyTorch) require significant memory:
```bash
docker run --rm --memory=8g biomate/biomni-tools:latest ...
```

---

## Image Details

- **Base Image**: `python:3.11-slim`
- **Size**: ~4.5 GB
- **Total Tools**: 271 across 21 domains
- **Python Version**: 3.11

---

## Files in This Directory

```
biomni_galaxy/
├── docker/
│   ├── Dockerfile              # Main build file
│   ├── domain_wrapper.py       # CLI wrapper (biomni-tool)
│   └── create_manifest.py      # Tool manifest generator
├── tools/                      # 271 Galaxy tool wrappers
│   ├── {domain}/
│   │   ├── {function}.xml      # Galaxy tool definition
│   │   └── {function}.py       # Python wrapper
├── converter/
│   ├── generate_xml.py         # XML generator
│   └── generate_wrappers.py    # Wrapper generator
└── README.md                   # This file
```

---

## Contact

For issues or questions, contact the BioMate team.
