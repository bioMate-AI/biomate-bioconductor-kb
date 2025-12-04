# Biomni Galaxy Docker Build Status

**Date:** November 30, 2025, 02:00 UTC
**Status:** COMPLETE - All 21 domains working

---

## Docker Image: `biomate/biomni-tools:latest`

### Build Command
```bash
docker build -t biomate/biomni-tools:latest -f biomni_galaxy/docker/Dockerfile .
```

### Image Structure

```
/opt/biomni/
├── bin/
│   ├── biomni-tool          # Domain wrapper CLI
│   └── create_manifest.py   # Manifest generator
├── src/
│   └── biomni/              # Biomni Python package
├── galaxy_tools/            # 271 Galaxy tool wrappers
│   ├── biochemistry/        (9 tools)
│   ├── bioengineering/      (12 tools)
│   ├── biophysics/          (3 tools)
│   ├── cancer_biology/      (7 tools)
│   ├── cell_biology/        (5 tools)
│   ├── database/            (53 tools)
│   ├── genetics/            (10 tools)
│   ├── genomics/            (22 tools)
│   ├── glycoengineering/    (3 tools)
│   ├── immunology/          (14 tools)
│   ├── lab_automation/      (6 tools)
│   ├── literature/          (9 tools)
│   ├── microbiology/        (17 tools)
│   ├── molecular_biology/   (28 tools)
│   ├── pathology/           (7 tools)
│   ├── pharmacology/        (51 tools)
│   ├── physiology/          (11 tools)
│   ├── protocols/           (2 tools)
│   ├── support_tools/       (8 tools)
│   ├── synthetic_biology/   (8 tools)
│   └── systems_biology/     (8 tools)
└── tool_manifest.json       # Tool registry
```

### Installed Dependencies

| Domain | Key Packages |
|--------|--------------|
| Core | numpy, scipy, pandas, matplotlib, biopython, scikit-learn |
| molecular_biology | primer3-py |
| genomics | scanpy, gseapy, gget, pybedtools |
| database | bioservices |
| pharmacology | rdkit, pubchempy |
| systems_biology | cobra, networkx |
| bioimaging | scikit-image, nibabel, Pillow |
| immunology/cell_biology | flowio |
| literature | arxiv, scholarly, PyPDF2, beautifulsoup4 |

### Usage Examples

```bash
# Run container interactively
docker run -it biomate/biomni-tools:latest bash

# List available domains
docker run biomate/biomni-tools:latest biomni-tool --list-domains

# List functions in a domain
docker run biomate/biomni-tools:latest biomni-tool molecular_biology --list-functions

# Execute a specific function
docker run -v $(pwd)/data:/data biomate/biomni-tools:latest \
    biomni-tool molecular_biology annotate_open_reading_frames \
    --sequence "ATGATGATGATGATG" --min_length 9 --output /data/results.json
```

### For Galaxy Integration

Each tool in `galaxy_tools/` has:
- `{function_name}.xml` - Galaxy tool definition
- `{function_name}.py` - Python wrapper script

To integrate with Galaxy:
1. Copy the XML files to your Galaxy tools directory
2. Add entries to `tool_conf.xml`
3. Restart Galaxy

---

## Files Created

| File | Description |
|------|-------------|
| `docker/Dockerfile` | Main Docker build file |
| `docker/domain_wrapper.py` | CLI wrapper for all domains |
| `docker/create_manifest.py` | Manifest generator |
| `tools/**/*.py` | 271 Python wrapper scripts |
| `tools/**/*.xml` | 271 Galaxy tool XML definitions |

---

## Test Results

### Domain Import Test: 21/21 PASSED

```
✓ biochemistry
✓ bioengineering
✓ biophysics
✓ cancer_biology
✓ cell_biology
✓ database
✓ genetics
✓ genomics
✓ glycoengineering
✓ immunology
✓ lab_automation
✓ literature
✓ microbiology
✓ molecular_biology
✓ pathology
✓ pharmacology
✓ physiology
✓ protocols
✓ support_tools
✓ synthetic_biology
✓ systems_biology
```

### Tool Execution Test: PASSED

```bash
$ docker run --rm biomate/biomni-tools:latest biomni-tool molecular_biology annotate_open_reading_frames \
    --sequence "ATGATGATGATGATG..." --min_length 9
# Returns valid JSON with ORF analysis
```

### Image Size: 4.42GB

---

## Key Dependencies Installed

| Package | Purpose | Domain(s) |
|---------|---------|-----------|
| torch (CPU) | Deep learning | genetics, genomics, bioimaging |
| fair-esm | Protein language model | genomics |
| esm | ESM3 package | genomics |
| googlesearch-python | Web search | literature |
| scanpy | Single-cell analysis | genomics |
| rdkit | Chemistry toolkit | pharmacology |
| cobra | Metabolic modeling | systems_biology |
| transformers | NLP models | genetics, genomics |
| biopython | Core bioinformatics | all domains |

---

## Next Steps

1. Push to Docker Hub (optional)
2. Integrate with Galaxy server
3. Test additional tool functions as needed

---

*Build completed at 2025-11-30 02:00 UTC*
