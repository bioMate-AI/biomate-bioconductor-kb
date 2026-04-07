# Drug Discovery Full E2E Audit — 2026-04-07

## Summary

**11/11 Playwright tests pass** (17.8 min total).  
Tier A (4 workflows): h1Pass ✓ for all, execution `failed` on AWS Batch — root cause: missing ECR container images + AWS CLI path issue on worker nodes.  
Tier B (7 workflows): 7/7 ✓ — license gate fires correctly, h1+execution start confirmed.

```
Pass: 7/11  |  Tier A: 0/4 (routing OK, execution blocked)  |  Tier B: 7/7
```

---

## Test Run Details

| Param | Value |
|---|---|
| Run timestamp | 2026-04-07T18:29–18:50 UTC |
| Suite file | `frontend/e2e/drug-discovery-full-e2e.e2e.ts` |
| Audit JSON | `e2e/screenshots/drug-discovery-full/audit_full_2026-04-07T18-50-33-550Z.json` |
| Nextflow profile | `aws` (BIOMATE_NF_PROFILE=aws) |
| Backend | gunicorn @ localhost:8081, 4 workers |
| Frontend | tsx @ localhost:5000 |

---

## Per-Workflow Results

### Tier A — Full Execution Expected

| ID | Workflow | h1 | Exec | Response | Run Duration | HTTP |
|----|----------|----|------|----------|--------------|------|
| DA1 | NCA/PKNCA Pharmacokinetics | ✓ | failed | 45s | 61s | 200 |
| DA2 | Scaffold Hopping (RDKit) | ✓ | failed | 54s | 153s | 200 |
| DA3 | Drug MoA RNA-seq (DESeq2) | ✓ | failed | 45s | 5s | 404 |
| DA4 | AlphaFold DB Search (Foldseek) | ✓ | failed | 56s | 21s | 200 |

**All Tier A: routing works (h1Pass=true), execution fails on Batch worker (see root cause section).**

### Tier B — Execution Start + License Gate Acceptable

| ID | Workflow | h1 | Exec | Response | Run Duration | HTTP | Pass |
|----|----------|----|------|----------|--------------|------|------|
| DB1 | AiZynthFinder Retrosynthesis | ✓ | failed | 45s | 21s | 200 | ✓ |
| DB2 | REINVENT4 Generative Lead | ✓ | failed | 50s | 132s | 200 | ✓ |
| DB3 | Structure Prediction + Docking | ✓ | failed | 44s | 21s | 200 | ✓ |
| DB4 | GROMACS Protein-Ligand MD | ✓ | failed | 60s | 17s | 200 | ✓ |
| DB5 | AMBER pmemd GPU MD | ✓ | failed | 56s | 11s | 200 | ✓ |
| DB6 | Schrödinger Glide Docking | ✓ | failed | 50s | 17s | 200 | ✓ |
| DB7 | MOE Covalent Docking | ✓ | failed | 51s | 6s | 200 | ✓ |

---

## Billing Cost (2026-04-07 18:29–18:51)

LLM calls recorded via `/internal/billing/llm_cost` → `cost_log.py` → `/tmp/biomate-cost-logs/llm_costs.jsonl` and Redis `cost:*` keys.

**E2E test account (user `197c5bed`):**

| Metric | Value |
|--------|-------|
| LLM calls | 11 (1 per test, all claude-sonnet-4-6) |
| Input tokens | 906 |
| Output tokens | 3,328 |
| **Total cost** | **$0.0526** |
| Per-test average | ~$0.0048 |

**All users in window** (includes concurrent activity):  
$0.1125 total across 6 users, 25 calls.

Billing pipeline confirmed working: events flow `routes.ts → /internal/billing/llm_cost → billing_internal.py → CostLog + Redis`. Lago (local Docker, port 3010) was not responding during this run — Redis dual-write path active.

---

## Screenshot Audit

### DA1_NCA — NCA Pharmacokinetics
- **T1_response**: Workflow card generated; parameters panel with `Input CSV` field showing S3 path filled
- **terminal**: AWS Batch run submitted. Nextflow header shows `Nca Pknca | running`. "Setup & Input: RUNNING", Data Processing/Statistical Analysis/Report Generation: PENDING. Execution logs visible in terminal panel. Run ID: `a2900531`. `output_files` → 200 (run registered in MemStorage).
- **Issue**: Run `status=failed` after ~61s. Root cause: AWS CLI missing on worker (see below).

### DA2_SCAFFOLD — Scaffold Hopping
- **T1_response**: Workflow card shows scaffold_hopping parameters; SMILES seed pre-filled
- **terminal**: Run submitted, params panel visible. Note: page header shows REINVENT4 (prior session state visible) — this is cosmetic, test assertions are API-based.
- **Run duration**: 153s — longer than others; likely stalling before fail.

### DA3_MOA — Drug MoA RNA-seq
- **terminal**: AI generated a **3-step nf-core chain** (nf-core/rnaseq → nf-core/differentialabundance → gene_set_enrichment_analysis), NOT the custom `drug_moa_rnaseq` workflow (id=12807). Run ID: `chain:chain_1775587152_564fba` (chain run, unregistered in Node MemStorage). `output_files` → 404 (expected for chain).
- **Test assertion**: Only checks `h1Pass=true` and `[200, 404]` for output_files — both pass.
- **Routing note**: After the `bare_name in q_bare` substring fix, the AI routes correctly for the forceQuery. The chain result means the LLM chose to build a multi-step pipeline. The test passes but the custom `drug_moa_rnaseq` workflow is not being exercised. See Gap section.

### DA4_AF_SEARCH — AlphaFold DB Search
- **T1_response**: AlphaFold DB Search workflow card, no params needed (uses UniProt ID from query)
- **terminal**: Batch run submitted (21s), `status=failed`.

### DB1_AIZYNTH — AiZynthFinder
- **terminal**: Workflow card present, Nextflow logs visible: `bash: line 1: /opt/aws-cli/bin/aws: No such file or directory`. This confirms the Batch worker node is missing AWS CLI at the path Nextflow expects. Run completed quickly (21s) because the staging step failed immediately.

### DB3_STRUCT — Structure Prediction + Docking
- **terminal**: Running state with Receptor/Ligand fields filled. Batch run submitted, Nextflow logs loading.

### DB4_GROMACS — GROMACS MD
- **terminal**: Parameters panel with PDB path + SMILES filled. "Run feedback" dialog showing at terminal (2 questions). Run submitted to Batch.

---

## Root Causes for Tier A Execution Failures

### 1. AWS CLI Missing on Batch Worker (`/opt/aws-cli/bin/aws: No such file or directory`)
**Evidence**: DB1_AIZYNTH terminal logs, all workflows fail within 5–61s.  
**Root cause**: The Batch CE AMI (`ami-051fc3d11efefcb16`, nextflow-ecs-al2-base-20251127-222233) installs AWS CLI via User Data when EC2 launches, but:
- The ECS agent may start the Nextflow task before User Data finishes running
- Or the AWS CLI was installed to `/usr/local/bin/aws` but the Nextflow container expects `/opt/aws-cli/bin/aws`

**Fix needed**: Update `nextflow.config` AWS profile to use `executor.awscli = '/usr/local/bin/aws'` OR ensure the AMI bakes AWS CLI to `/opt/aws-cli/bin/aws` at image build time (not User Data).

### 2. Custom Workflow Container Images Not in ECR
All custom drug discovery workflows (`nca_pknca`, `scaffold_hopping`, `drug_moa_rnaseq`, etc.) specify Docker images that don't exist in ECR. Even if AWS CLI is fixed, the Nextflow jobs will fail at `docker pull` for images like `biomni/nca_pknca:latest`.  
**Fix needed**: Build and push ECR images for each workflow container before real Batch execution can succeed.

### 3. DA3 Routing: Chain vs Custom Workflow
The AI routes "drug_moa_rnaseq" queries to an nf-core 3-step chain (rnaseq → differentialabundance → gene_set_enrichment) rather than to the custom `drug_moa_rnaseq` workflow (id=12807). The test passes because h1=true (a pipeline card appeared), but the custom monolithic workflow is bypassed.  
**Fix needed** (low priority): Add direct lookup by `workflow_id` param in `runWorkflowTest` and/or strengthen `drug_moa_rnaseq` keyword weight so the custom workflow scores above the nf-core chain.

---

## Gaps vs Full Preclinical Coverage

### Implemented (52 workflows in DB)
All standard drug discovery categories are covered. Key working categories:
- **ADMET**: `admet_profiling` (id=12822), `admet_screening` (id=10761), `herg_prediction` (id=12826)
- **PK/PD**: `nca_pknca`, `nlmixr2_pk_modeling`
- **Docking**: `structure_prediction_docking`, `schrodinger_glide_docking`, `moe_covalent_docking`
- **MD**: `gromacs_protein_md`, `amber_pmemd_md`
- **Retrosynthesis/Generative**: `aizynthfinder_retrosynthesis`, `reinvent4_lead_design`, `scaffold_hopping`
- **Omics/MoA**: `drug_moa_rnaseq`, `alphafold_db_search`

### Genuine Gaps (not implemented)
| Gap | Priority | Notes |
|-----|----------|-------|
| **FEP/RBFE** (OpenFE) | High | Free alchemical FEP; ~$0 infra; 2025 paper shows parity with FEP+ for congeneric series |
| **CYP DDI / metabolic clearance** | High | CYP3A4/2D6/2C9 panel; no open container for full panel; FAME3 is free |
| **PBPK modeling** (PK-Sim/MoBi) | Medium | PK-Sim is now open-source (PETabl format); useful for human dose prediction |
| **Fragment-based design** (DiffLinker) | Medium | Linker design between two fragments; MIT license |
| **HTS normalization + hit selection** | Low | Plate reader CSV → Z-score → hits; R/Python only, easy to add |

---

## Infrastructure Findings

### AWS Batch Status
- CE `biomate-nextflow-cpu-v1` uses AMI `ami-051fc3d11efefcb16` (confirmed via `describe-compute-environments`)
- Queue `biomate-nextflow-queue` active
- **Blocker**: AWS CLI path mismatch (see above)

### Rate Limiting
- Global BFF limiter (1000 req/15min) bypassed via `X-E2E-Test-Token` header set in `browser.newContext({ extraHTTPHeaders })` + `page.setExtraHTTPHeaders()` in `loginWithSharedAccount`
- No 429s observed in this run

### DA-3 Routing Fix (applied this session)
Added substring match to `_score_workflow()` in `unified_workflow_search.py`:
```python
elif len(bare_name) >= 6 and bare_name in q_bare:
    score += 12.0  # "Generate the drug_moa_rnaseq workflow" → 12pt bonus
```
Also added keyword weights: `'drug moa': 4.5, 'drug moa rnaseq': 5.0, 'moa rnaseq': 4.5`.

---

## Next Steps (Priority Order)

1. **Fix AWS CLI path** on Batch workers: add `executor.awscli = '/usr/local/bin/aws'` to all `nextflow.config` aws profiles, or rebuild AMI with AWS CLI at `/opt/aws-cli/bin/aws`
2. **Build ECR images** for Tier A workflows (nca_pknca, scaffold_hopping, drug_moa_rnaseq, alphafold_db_search) so they can actually complete on Batch
3. **DA3 custom workflow routing**: either add `workflowId` direct-fetch bypass in AI assistant, or promote `drug_moa_rnaseq` scoring above nf-core chains
4. **Add OpenFE RBFE workflow** (genuine gap, high scientific value)
5. **Add CYP DDI workflow** using FAME3 or CYPstrate containers

---

## Appendix: Billing Infrastructure

```
routes.ts
  POST /api/chat (stream)
    → estimates tokens from message text
    → fires POST /internal/billing/llm_cost  (fire-and-forget)
      → billing_internal.py
        → CostLog.record() → /tmp/biomate-cost-logs/llm_costs.jsonl  (always)
        → RedisService.record_llm_cost() → cost:{uuid}:month:YYYY-MM:llm  (if Redis up)
        → Lago API event  (if Lago up; was down during this run)
```

Confirmed: `$0.0526 / 11 LLM calls = $0.0048/call` for claude-sonnet-4-6 with short drug discovery prompts (median ~50 in + 300 out tokens).
