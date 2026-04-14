# Workflow Param Declaration & Container Issues — All Domains

**Date**: 2026-04-05
**Scope**: Drug discovery (fixed this session) + all remaining BioMate domains (next-phase action items)

---

## 1. Issue 1 — Undeclared Required Parameters

### Root Cause
Nextflow workflows use `params.X` in the workflow block but omit the declaration from the top-level params block. Since `_parse_nextflow_params` only reads declared params, the AI and the prereq check are unaware of these inputs. Result: the Run button is enabled with null/empty values, causing a runtime error deep inside the workflow instead of a clean prereq gate.

### Rule
**Every parameter used in the workflow block MUST be declared** in the top-level params section with either:
- `params.X = null` — required input (prereq check blocks Run until user fills it)
- `params.X = <default>` — optional with a sensible default

### Fixed (drug_discovery, this session)

| Workflow | Param Added | Type |
|----------|-------------|------|
| `pocket_detection_druggability` | `params.pdb_input = null` | PDB ID or file path |
| `pharmacophore_filtering` | `params.reference_actives = null` | SMILES (one per line) |
| `pharmacophore_filtering` | `params.compound_library = null` | SMILES/SDF to screen |
| `aizynthfinder_retrosynthesis` | `params.smiles_file = null` | SMILES file or inline |
| `aizynthfinder_retrosynthesis` | `params.seed_smiles = null` | Single SMILES string |
| `structure_prediction_docking` | `params.fasta_input = null` | FASTA/sequence input |
| `structure_prediction_docking` | `params.ligand_sdf = null` | Ligand SDF for docking |
| `structure_prediction_docking` | `params.json = null` | AF3 JSON input |

### Also Fixed — Silent Empty-String Fallbacks

Workflows with `params.X = ''` (empty string, not null) bypass the prereq check and silently pass empty data:

| Workflow | Param | Before | After |
|----------|-------|--------|-------|
| `assay_ingestion_and_ranking` | `assay_csv` | `= ''` | `= null` + error guard |
| `cro_submission_export` | `compound_csv` | `= ''` | `= null` + error guard |

The channel fallback `params.X ?: 'header_only_default'` was also removed and replaced with an explicit `error "X is required"`.

### How to Apply to All Remaining Domains
Run this audit for each domain:
```python
import re, glob
BASE = 'backend/biomni_workflows/nextflow_nfcore/subworkflows'
for nf in glob.glob(f'{BASE}/**/main.nf', recursive=True):
    txt = open(nf).read()
    declared = set(re.findall(r'^params\.(\w+)\s*=', txt, re.MULTILINE))
    used = set(re.findall(r'params\.(\w+)', txt)) - declared
    used -= {'mock_mode','outdir','publish_dir_mode'}  # internal params
    if used:
        print(f'{nf}: UNDECLARED {used}')
```

---

## 2. Issue 2 — mock_mode is NEVER Acceptable

### Policy
`mock_mode` is never an acceptable default or permanent behavior in BioMate workflows. Every workflow must run real tools.

- `params.mock_mode = false` is the **only** acceptable default
- If a tool requires a license (CryoSPARC, AMBER, Schrödinger, MOE), use the **license registry** (`license_registry.py`) to gate access — the license gate prompts the user for credentials before execution
- The `if (params.mock_mode) { synthetic_data } else { real_tool }` branches should eventually be removed as each domain achieves production readiness

### Fixed This Session
- **drug_discovery**: All 23 files fixed (previous session) ✅
- **cryo_em**: All 17 files fixed (this session) ✅
- **cryo_et**: All 5 files fixed (this session) ✅

### Remaining (Next Phase)
Domains that still need audit for mock_mode:

| Domain | Estimated Files | Action |
|--------|-----------------|--------|
| `genomics` | 31 workflows | Audit + fix |
| `pharmacology` | 28 workflows | Audit + fix |
| `molecular_biology` | 26 workflows | Audit + fix |
| `bioimaging` | 22 workflows | Audit + fix |
| `microbiology` | 16 workflows | Audit + fix |
| `physiology` | 14 workflows | Audit + fix |
| `bioengineering` | 13 workflows | Audit + fix |
| `immunology` | 13 workflows | Audit + fix |
| `genetics` | 11 workflows | Audit + fix |
| `biochemistry` | 9 workflows | Audit + fix |
| `bioconductor` | 1818 workflows | 1 remaining instance (negligible) |

Bulk fix command (same pattern as drug_discovery):
```python
import re, glob
BASE = 'backend/biomni_workflows/nextflow_nfcore/subworkflows'
mock_re = re.compile(r'(params\.mock_mode\s*=\s*)true', re.IGNORECASE)
for nf in glob.glob(f'{BASE}/**/main.nf', recursive=True):
    txt = open(nf).read()
    if mock_re.search(txt):
        open(nf, 'w').write(mock_re.sub(r'\1false', txt))
        print(f'Fixed: {nf}')
```

---

## 3. Issue 3 — Container ECR Status

### Current ECR State (as of 2026-04-05)

| ECR Repository | Tags Available | Notes |
|----------------|----------------|-------|
| `biomate/biomni-pharma` | `x86`, `arm64`, `latest` | ✅ Ready for AWS Batch |
| `biomate/biomni-structure-to-drug` | `x86`, `arm64`, `latest` | ✅ Ready for AWS Batch |
| `biomate/biomni-structural` | `x86`, `latest` | ✅ Ready (cryo_em/cryo_et) |
| `biomate/biomni-microbiology` | `x86`, `latest` | ✅ Ready |
| `biomate/biomni-cloning` | `x86`, `arm64` | ✅ Ready |
| `biomate/biomni-systems` | `x86`, `latest` | ✅ Ready |
| `biomate/rnaseq` | `x86` | ✅ Ready |
| `biomate/singlecell` | `x86` | ✅ Ready |
| `biomate/cutandrun` | `x86` | ✅ Ready |
| `biomate/biomni-tools` | **EMPTY** | ⚠️ Build + push needed (474 workflows) |
| `biomate/biomni-drug-discovery-nf` | **DOES NOT EXIST** | ⚠️ Create repo + build + push (15 workflows) |
| `biomate/biomni-crispr` | `arm64`, `latest` (no x86) | ⚠️ x86 build needed |
| `biomate/biomni-synbio` | `arm64`, `latest` (no x86) | ⚠️ x86 build needed |

### Critical Builds Required

1. **`biomate/biomni-tools:x86`** — Highest priority (474 workflow files)
   - Dockerfile: `backend/biomni_workflows/galaxy/docker/Dockerfile` (or `Dockerfile.x86-comprehensive` for comprehensive x86 with foldseek/mmseqs2)
   - Build: `docker buildx build --platform linux/amd64 -t 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86 --push .`

2. **`biomate/biomni-drug-discovery-nf:x86`** — Required for DA-2/DA-3/DB-1/DB-2/DB-4 workflows
   - Dockerfile: `backend/docker/drug-discovery-nf/Dockerfile`
   - Create ECR repo first: `aws ecr create-repository --repository-name biomate/biomni-drug-discovery-nf --region us-west-2`
   - Contents: AiZynthFinder (with USPTO models), pydeseq2, gseapy, RDKit (inherits from biomni-structure-to-drug)

### Dual-Container Pattern (All Workflows)
Every process container directive must use the dual-container pattern:
```groovy
container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes']
  ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/IMAGE:x86'
  : 'biomate/IMAGE:latest'
```
**474 workflow files** across 20+ domains currently use `biomate/biomni-tools:latest` without the dual-container pattern. This bulk fix is Phase 2 work.

---

## 4. Remediation Priority for All Non-Drug Domains

### Phase 1 (Immediate — same session or next session)
1. Fix mock_mode in all remaining domains (bulk Python script, ~15 min)
2. Audit undeclared params in genomics + pharmacology + molecular_biology
3. Build `biomni-drug-discovery-nf:x86` ECR image (enables 15 drug discovery workflows on AWS Batch)

### Phase 2 (~1–2 weeks)
1. Build `biomni-tools:x86` (highest impact — unblocks 474 workflows)
2. Bulk dual-container patch for all domains
3. Fix undeclared params in all remaining domains

### Phase 3 (~2–3 weeks)
1. E2E smoke test suite for all domains
2. Verify bioconductor containers accessible from AWS Batch
3. Build missing x86 images (biomni-crispr, biomni-synbio)

---

## 5. E2E Test Pattern for Required Params

The E2E test must simulate real user behavior: if a workflow has required params with null defaults, the test fills them in before clicking Run.

Pattern added to `drug-discovery-pilot-e2e.e2e.ts`:
```typescript
await executeWorkflowSession(page, result, {
  pdb_input: '1IEP',        // S3: PDB ID from user query
  assay_csv: '<csv_data>',  // S5: inline CSV from user query
  compound_csv: '<csv>',    // S6: compound data from user query
});
```

The `fillWorkflowParams()` helper locates `[id="paramName"]` inputs and fills them using Playwright's `fill()` + React change events.

This pattern applies to ALL domain E2E tests going forward.
