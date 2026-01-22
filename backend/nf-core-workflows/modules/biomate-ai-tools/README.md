# Biomate AI Tools - Nextflow Modules

Nextflow modules for cutting-edge bioinformatics AI tools.

## Available Modules

### Structure Prediction
| Module | Process | Description | GPU |
|--------|---------|-------------|-----|
| `esmfold` | ESMFOLD | Fast structure prediction (API) | No |
| `alphafold` | ALPHAFOLD_DB | Retrieve from 200M+ structures | No |
| `alphafold` | ALPHAFOLD3_SERVER | Format for AF3 Server | No |
| `boltz` | BOLTZ | Protein-ligand + affinity | Yes |
| `chai1` | CHAI1 | Multi-modal (protein/DNA/RNA/ligand) | Yes |

### Drug Discovery
| Module | Process | Description | GPU |
|--------|---------|-------------|-----|
| `drugclip` | DRUGCLIP | 10M× faster virtual screening | Optional |
| `drugclip` | DRUGCLIP_API | Pre-computed database search | No |
| `syncraft` | SYNCRAFT | AI retrosynthesis planning | No |

### Protein Analysis
| Module | Process | Description | GPU |
|--------|---------|-------------|-----|
| `protrek` | PROTREK_SEARCH | Trimodal protein search | Optional |
| `protrek` | PROTREK_EMBED | Generate embeddings | Yes |
| `profam` | PROFAM_SCORE | Score protein variants | Yes |
| `profam` | PROFAM_GENERATE | Generate sequences | Yes |

### Single-Cell
| Module | Process | Description | GPU |
|--------|---------|-------------|-----|
| `state` | STATE_PERTURB | Perturbation response prediction | Yes |
| `state` | STATE_EMBED | Cell state embeddings | Yes |

### Antibody Design
| Module | Process | Description | GPU |
|--------|---------|-------------|-----|
| `scfv-pmpnn` | SCFV_DESIGN | AI antibody design | Yes |
| `scfv-pmpnn` | SCFV_PREDICT | Structure prediction | Yes |

## Quick Start

### 1. Pull from ECR

```bash
# Login to ECR
aws ecr get-login-password --region us-west-2 | \
    docker login --username AWS --password-stdin \
    399683337364.dkr.ecr.us-west-2.amazonaws.com

# Pull images
docker pull 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/esmfold:latest
docker pull 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/boltz:latest
# ... etc
```

### 2. Include Module

```nextflow
include { ESMFOLD } from './modules/biomate-ai-tools/esmfold/main'
include { BOLTZ } from './modules/biomate-ai-tools/boltz/main'
include { DRUGCLIP } from './modules/biomate-ai-tools/drugclip/main'
```

### 3. Use in Workflow

```nextflow
workflow {
    // Structure prediction with ESMFold (FREE API)
    ESMFOLD(protein_fasta_ch)

    // Drug screening with DrugCLIP
    DRUGCLIP(
        protein_fasta_ch,
        compounds_ch
    )

    // Perturbation prediction with STATE
    STATE_PERTURB(scrnaseq_ch)
}
```

## Example Pipelines

### Structure Prediction Pipeline

```nextflow
#!/usr/bin/env nextflow

include { ESMFOLD } from './modules/biomate-ai-tools/esmfold/main'
include { BOLTZ } from './modules/biomate-ai-tools/boltz/main'

workflow STRUCTURE_PREDICTION {
    take:
    fasta_ch  // channel: [ val(meta), path(fasta) ]

    main:
    // Try ESMFold first (fast, free)
    ESMFOLD(fasta_ch)

    // For complex structures, use Boltz
    BOLTZ(fasta_ch, [])

    emit:
    esmfold_pdb = ESMFOLD.out.pdb
    boltz_pdb = BOLTZ.out.pdb
}
```

### Drug Discovery Pipeline

```nextflow
#!/usr/bin/env nextflow

include { DRUGCLIP } from './modules/biomate-ai-tools/drugclip/main'
include { SYNCRAFT } from './modules/biomate-ai-tools/syncraft/main'

workflow DRUG_DISCOVERY {
    take:
    target_ch    // channel: [ val(meta), path(protein_fasta) ]
    library_ch   // channel: path(compounds_sdf)

    main:
    // Screen compound library
    DRUGCLIP(target_ch, library_ch)

    // Plan synthesis for top hits
    top_smiles_ch = DRUGCLIP.out.top_hits
        .map { meta, hits -> [meta, hits.text.split('\n')[1].split(',')[0]] }

    SYNCRAFT(top_smiles_ch)

    emit:
    screening_results = DRUGCLIP.out.scores
    synthesis_routes = SYNCRAFT.out.route
}
```

## Environment Variables

| Variable | Required For | Description |
|----------|--------------|-------------|
| `GEMINI_API_KEY` | SynCraft | Google Gemini API key |
| `AWS_ACCESS_KEY_ID` | ECR | AWS credentials |
| `AWS_SECRET_ACCESS_KEY` | ECR | AWS credentials |

## Docker Images

All images available at:
```
399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/
├── syncraft     (~1 GB)   - CPU only
├── drugclip     (~1.5 GB) - CPU/GPU
├── protrek      (~8 GB)   - GPU recommended
├── profam       (~8.5 GB) - GPU required
├── scfv-pmpnn   (~8.5 GB) - GPU required
├── state        (~8.7 GB) - GPU required
├── boltz        (~15 GB)  - GPU required
└── chai1        (~16 GB)  - GPU required
```

## Resource Requirements

| Tool | Min GPU VRAM | Min RAM | Notes |
|------|--------------|---------|-------|
| ESMFold | - | 4 GB | API only |
| AlphaFold DB | - | 1 GB | API only |
| DrugCLIP | 8 GB (optional) | 16 GB | CPU mode available |
| SynCraft | - | 4 GB | CPU only, needs GEMINI_API_KEY |
| ProTrek | 8 GB (optional) | 16 GB | CPU mode available |
| ProFam | 8 GB | 16 GB | GPU required |
| STATE | 16 GB | 32 GB | GPU required |
| scFv-pMPNN | 16 GB | 32 GB | GPU required |
| Boltz | 16-40 GB | 64 GB | GPU required |
| Chai-1 | 24-80 GB | 64 GB | GPU required |

## Practical Setup Guide

### Step 1: Download Model Weights

```bash
# Run setup script (downloads ~30 GB)
./bin/setup_models.sh /path/to/models

# Or download individually
huggingface-cli download judewells/ProFam-1 --local-dir /models/profam
huggingface-cli download arcinstitute/SE-600M --local-dir /models/state
```

### Step 2: Configure Nextflow

Create `nextflow.config`:
```groovy
params {
    models_dir = '/path/to/models'  // Local
    // models_dir = 's3://biomate-models'  // S3
}

docker {
    enabled = true
    runOptions = '-v /path/to/models:/models'
}

aws {
    region = 'us-west-2'
    batch.cliPath = '/home/ec2-user/miniconda/bin/aws'
}
```

### Step 3: Run Pipeline

```bash
# Structure prediction (FREE, no models needed)
nextflow run workflows/structure_prediction.nf \
    --input proteins.fasta \
    --method esmfold \
    --outdir results/

# Drug screening
nextflow run workflows/drug_discovery.nf \
    --target_fasta target.fasta \
    --compounds library.sdf \
    --top_k 100

# With models mounted
nextflow run workflows/perturbation.nf \
    --input scrnaseq.h5ad \
    --models_dir /path/to/models
```

### Model Storage Options

| Option | Pros | Cons |
|--------|------|------|
| Local disk | Fast, no network | Limited to one machine |
| NFS/EFS | Shared across nodes | Network latency |
| S3 | Scalable, durable | Download time |
| Pre-baked in AMI | Fastest startup | Large AMI size |

### For AWS Batch

```bash
# Upload models to S3
aws s3 sync /path/to/models s3://biomate-models/

# In nextflow.config
process {
    withLabel: 'needs_models' {
        beforeScript = 'aws s3 sync s3://biomate-models /models'
    }
}
```

---

## License

Tools are provided under their original licenses:
- Boltz-2: MIT
- Chai-1: Apache 2.0
- DrugCLIP: MIT
- ProTrek: Apache 2.0
- ProFam: MIT
- STATE: Apache 2.0
