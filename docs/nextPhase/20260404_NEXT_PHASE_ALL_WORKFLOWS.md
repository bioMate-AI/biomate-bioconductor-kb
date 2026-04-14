# Next Phase — All-Workflow Production Readiness Plan

**Date**: 2026-04-04
**Scope**: All BioMate Nextflow workflows beyond the drug_discovery domain
**Total non-drug-discovery workflows**: ~2069 (including 1818 bioconductor)
**Priority**: Production readiness = mock_mode=false + dual-container + E2E coverage

---

## 0. Summary of Work Done This Session (drug_discovery)

| Task | Status |
|------|--------|
| mock_mode=false in all drug_discovery main.nf + nextflow.config | ✅ Done (23 files) |
| Dual-container pattern in all drug_discovery workflows | ✅ Done |
| S1–S6 pilot workflows dual-container + proper ECR | ✅ Done |
| S5/S6 new workflows created + DB registered | ✅ Done |
| Comprehensive E2E test `drug-discovery-full-e2e.e2e.ts` (11 workflows) | ✅ Done |
| Session audit doc `20260404_DRUG_DISCOVERY_WORKFLOW_AUDIT.md` | ✅ Done |
| ECR image `biomni-drug-discovery-nf:x86` — needs x86 build + push | ⚠️ Pending |

---

## 1. Domain Audit Summary

### Workflows requiring immediate action (mock_mode=true or critical issues)

| Domain | # Workflows | mock_true | Local-only containers | Priority |
|--------|-------------|-----------|----------------------|----------|
| `cryo_em` | 15 | **15** | 0 (uses ECR already) | P1 — all mock |
| `cryo_et` | 5 | **5** | 0 (uses ECR already) | P1 — all mock |
| `genomics` | 31 | 5 | 27 | P1 — core domain |
| `pharmacology` | 28 | 0 | 24 | P2 — containers |
| `molecular_biology` | 26 | 0 | 22 | P2 |
| `bioimaging` | 22 | 0 | 22 | P2 |
| `microbiology` | 16 | 0 | 15 | P2 |
| `physiology` | 14 | 0 | 14 | P3 |
| `bioengineering` | 13 | 0 | 11 | P3 |
| `immunology` | 13 | 0 | 13 | P3 |
| `genetics` | 11 | 0 | 11 | P3 |
| `biochemistry` | 9 | 0 | 9 | P3 |
| `bioconductor` | 1818 | 1 | 0 | Low — auto-generated |

### Local-only containers needing dual-container pattern
The dominant pattern across non-drug-discovery domains is:
```groovy
container 'biomate/biomni-tools:latest'  // 474 occurrences
```
This needs to become:
```groovy
container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes']
  ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86'
  : 'biomate/biomni-tools:latest'
```
**Total affected workflows**: ~230 across 20+ domains.

---

## 2. Phase Plan

### Phase 1 — Critical Fixes (P1, ~1 week)

#### P1.1 cryo_em domain — fix all 15 mock_mode=true
- All 15 workflows in `cryo_em/` have `params.mock_mode = true`
- Same Python-based fix as drug_discovery
- Container: already using ECR `biomni-structural:x86` (from memory)
- Command: `python3 fix_mock.py cryo_em cryo_et`

#### P1.2 cryo_et domain — fix all 5 mock_mode=true
- Same approach as cryo_em

#### P1.3 genomics domain — fix 5 mock_mode + 27 local-only containers
- 5 workflows have `mock_mode=true` (likely variant_calling or nf-core based)
- 27 workflows use `biomate/biomni-tools:latest` → need dual-container
- Key genomics workflows: `nf-core/sarek`, `nf-core/rnaseq`, `nf-core/differentialabundance`

#### P1.4 Build and push `biomni-tools:x86` to ECR
- This is the single most impactful infrastructure task
- **474 workflow files** use `biomate/biomni-tools:latest`
- Builds on `biomni-tools` locally, cross-compile to AMD64 and push
- Command: `docker buildx build --platform linux/amd64 -t 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86 --push .`

#### P1.5 Build and push `biomni-drug-discovery-nf:x86` to ECR
- Required for: aizynthfinder, scaffold_hopping, drug_moa_rnaseq, gromacs, reinvent4
- Contains: REINVENT4, AiZynthFinder, RDKit, DESeq2, GROMACS, Python data stack
- Build from local `biomni-drug-discovery-nf:latest` (ARM) on x86 build machine

---

### Phase 2 — Container Standardization (P2, ~2 weeks)

#### P2.1 Bulk dual-container patch for `biomate/biomni-tools:latest`
Apply to all 20+ domains with local-only containers.
```python
# Automated patch script (pending approval)
for domain in ['pharmacology', 'molecular_biology', 'bioimaging', 'microbiology',
               'physiology', 'immunology', 'genetics', 'biochemistry',
               'synthetic_biology', 'cancer_biology', 'cell_biology',
               'lab_automation', 'pathology', 'glycoengineering', 'biophysics',
               'literature', 'database', 'bioengineering', 'proteomics']:
    patch_domain(domain,
        local='biomate/biomni-tools:latest',
        aws='399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86')
```

#### P2.2 Domain-specific containers requiring individual attention

| Domain | Current Container | Correct ECR |
|--------|------------------|-------------|
| `cryo_em` | `biomni-structural:x86` (already ECR) | ✅ already correct |
| `cryo_et` | Same as cryo_em | ✅ already correct |
| `genomics` (nf-core) | nf-core containers | Keep as-is (nf-core handles) |
| `pharmacology/nlmixr2` | `nlmixr2/nlmixr2:latest` | Keep as-is (specialized R container) |
| `lab_automation` | `biomate/biomni-tools:latest` | `biomni-tools:x86` |

---

### Phase 3 — E2E Test Coverage (P3, ~3 weeks)

#### P3.1 Genomics E2E suite
- `nf-core/sarek` (germline variant calling): existing `germline-complete-e2e.e2e.ts` ✅
- `nf-core/rnaseq`: needs full E2E test
- `nf-core/differentialabundance`: needs test
- ATAC-seq, ChIP-seq, scRNA-seq: needs tests

#### P3.2 CryoEM E2E suite
- Focus on full pipeline: raw micrographs → CTF → picking → 2D class → 3D refinement
- Key: RELION, cryoSPARC, CTFFIND4
- License gate: cryoSPARC requires per-user license (user_must_provide=True)

#### P3.3 Multi-domain E2E smoke test
For the 200+ remaining workflows:
- **Smoke test approach**: AI generation only (h1Pass check), no execution
- Covers: bioimaging, molecular_biology, microbiology, physiology, immunology, etc.
- File: `frontend/e2e/multi-domain-smoke-e2e.e2e.ts`

#### P3.4 Pharmacology E2E suite
- S1/S2 (predict_admet, ivive) already in pilot ✅
- Add: QSAR, docking_autodock_vina, NMR, PK modeling (nlmixr2), TxGNN drug repurposing

---

### Phase 4 — Bioconductor (Low Priority)

1818 bioconductor workflows use auto-generated `bioconductor_nf` format.
- Container: `bioconductor/bioconductor_docker:RELEASE_3_18` (already public ECR-accessible)
- mock_mode: 1 remaining instance (negligible)
- E2E: existing bioconductor test coverage via `full-workflow-e2e.e2e.ts`
- Action: Verify all bioconductor containers are accessible from AWS Batch; no code changes needed

---

## 3. ECR Container Build Plan

| Image | Contents | # Workflows Affected | Build Priority |
|-------|----------|---------------------|----------------|
| `biomni-tools:x86` | Python data stack, common bioinformatics | **474** | P1 — most impactful |
| `biomni-drug-discovery-nf:x86` | REINVENT4, AiZynthFinder, RDKit, DESeq2 | ~15 | P1 |
| `biomni-pharma:x86` | ADMET, pharmacokinetics, IVIVE | 6 (pilot) | ✅ exists |
| `biomni-structure-to-drug:x86` | fpocket, RDKit, structure tools | 4 (pilot) | ✅ exists |
| `biomni-structural:x86` | RELION, CryoSPARC, CTFFIND4 | 20 (cryo) | ✅ exists |

---

## 4. Infrastructure Requirements

### AWS Batch Setup Checklist
- [ ] ECR repository `biomate/biomni-tools` needs x86 image pushed
- [ ] ECR repository `biomate/biomni-drug-discovery-nf` needs x86 image pushed
- [ ] AWS Batch compute environment configured for GPU (for AMBER, GROMACS)
- [ ] S3 bucket `biomate-structure-db` populated:
  - `/alphafold/human/` — AlphaFold DB human proteome structures
  - `/aizynthfinder/models/` — AiZynthFinder route expansion models

### License Management
| Tool | License Type | Status | Action |
|------|-------------|--------|--------|
| AMBER | Commercial (academic free) | Not applied | Apply at ambermd.org |
| Schrödinger | Commercial | Not applied | Contact sales |
| MOE | Commercial (academic) | Not applied | Apply at chemcomp.com |
| CryoSPARC | Per-user free | user_must_provide=True | Users bring own |
| AlphaFold3 | Docker auth | Not applied | Apply at alphafold.ebi.ac.uk |

---

## 5. Testing Strategy by Domain

### Tier 1 — Full E2E (generation + execution + output viz + download)
Already covered: drug_discovery (S1–S6 pilot, DA-1–DB-7 full suite)
Next: genomics, cryo_em, pharmacology, molecular_biology

### Tier 2 — Generation + execution start
For workflows requiring licenses or specialized hardware (AMBER, Glide, MOE, GPU).
Assert: workflow card generated + runId returned + output_files 200.

### Tier 3 — Generation only (smoke test)
For the long tail of ~200+ workflows across 20+ domains.
Assert: AI generates correct workflow card with run button.
File: `frontend/e2e/multi-domain-smoke-e2e.e2e.ts` (to be created in Phase 3)

---

## 6. Success Metrics

| Metric | Current | Target (Phase 1) | Target (Phase 3) |
|--------|---------|-----------------|-----------------|
| Workflows with mock_mode=false | ~90% | 100% | 100% |
| Workflows with dual-container | ~15 | ~50 | ~300 |
| Workflows with ECR containers | ~15 | ~50 | ~300 |
| E2E full execution coverage | 6 (pilot) | 17 (pilot + full DD) | 50+ |
| E2E smoke coverage | 17 | 50 | 300+ |
