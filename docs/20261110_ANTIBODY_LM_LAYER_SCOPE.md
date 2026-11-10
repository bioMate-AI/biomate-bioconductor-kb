# Antibody structural + LM developability layer — scope & compliance decision

**Date:** 2026-11-10
**Question:** add an ESMFold / AntiBERTa "learned" structural + developability layer for SYSUCC's antibody /
ADC / bispecific wave. **Decision: clean reuse on structure; DO NOT ship AntiBERTa2 (license blocker); build
a thin LM subworkflow on a commercially-licensed model.**

## 1. Structure — ALREADY SOLVED, build nothing
- `esmfold` (catalog **id 14464**, `backend/nf-core-workflows/modules/biomate-ai-tools/esmfold/main.nf`,
  container `workflow-lite`, **MIT**). API-based (POSTs to `api.esmatlas.com`, returns PDB; no GPU/weights).
  **Caps:** ≤400 residues → fold an **Fv / scFv / VHH per domain** (not a full ~1300-aa IgG); hard external
  dependency → keep its existing `exit 1` on invalid PDB (honest-failure).
- `nf-core/proteinfold` (id 12759) is a **STUB** (mock PDB) — do NOT route antibody structure to it.
- ESM-2 embeddings already exist (id 10670, `generate_gene_embeddings_with_ESM_models`) — but `fair-esm` is
  not verified in the `workflow-tools` Dockerfile; verify before reuse.

## 2. ⚠️ Compliance: AntiBERTa2 is OFF-LIMITS
HF `alchemab/antiberta2` (202M, RoFormer antibody LM) ships under a **modified Apache-2.0 that is
NON-COMMERCIAL only** and **explicitly forbids creating antibody variants for testing/clinical purposes**
(https://huggingface.co/alchemab/antiberta2/blob/main/LICENSE.md). BioMate is a **commercial** product and
this is the SYSUCC **clinical/CRO** antibody wave — exactly the forbidden use. **Shipping AntiBERTa2 here is a
licensing violation, not a scope choice. Do not use it.**

**Commercial-safe substitutes (same capability):**
- **BALM-paired** (brineylab) — **MIT** (code + weights), paired-antibody LM. ✅ preferred.
- **AbLang2** (oxpig) — antibody-specific embeddings + humanization/restore; confirm exact LICENSE before shipping.
- **ESM-2** — MIT, general PLM, already in-stack (weaker humanness than an antibody-specific LM).

## 3. No new image needed
torch+transformers+huggingface_hub already exist in `biomate-ai-tools/protrek`, `profam`, `state`,
`virtual-cell-gpu` (has `TRANSFORMERS_CACHE` wired), `boltz`. A ≤202M LM scores a handful of candidate
sequences on CPU in seconds — could even add `transformers` to `workflow-tools` for a CPU-only path. A GPU
image is only worth it for batch-scoring hundreds of designs.

## 4. Genuinely additive to the existing rule scanner (not a duplicate)
`pharmacology/antibody_developability` (id 12881/14561) already does the **biophysical/motif** rules
(CamSol aggregation, deamidation NG/NS/DG, oxidation, pI, FcRn). An antibody LM adds what rules cannot:
1. **humanness / naturalness** (pseudo-perplexity vs the human repertoire) as an **immunogenicity proxy** —
   the biggest current gap;
2. learned, context-aware **developability embedding** scores (not motif counts);
3. **humanization / back-mutation** suggestions (AbLang restore);
emitted as **advisory columns alongside** the rule scanner, never replacing it.

## 5. Recommended minimal build (when prioritized)
A thin new subworkflow `drug_discovery/antibody_developability_lm` (or an extra emitted block on 12881):
load **BALM (MIT)** or AbLang2 via `transformers`/`huggingface_hub`, host in `protrek`/`virtual-cell-gpu`
(or add `transformers` to `workflow-tools`), compute humanness + learned developability, emit advisory
columns. **Mandatory honest-scope guards:** LM scores are correlative **advisories, not QC gates** (never
auto-halt a campaign); humanness ≠ a clinical immunogenicity assay (a proxy); fold per-domain (ESMFold 400-aa
cap) and keep the API hard-fail; **pin/vendor the chosen weights to ECR/S3 with their LICENSE file, and verify
AbLang2's license before shipping.**

**This doc's purpose is the compliance firewall:** the structure side is reuse, the value is real, but the
obvious model (AntiBERTa2) is legally unusable for a commercial clinical product — use BALM/ESM-2.

Related: [[project_sysucc_modality_capability]] · [[project_drugdev_capability]] · [[reference_proteomics_engine_licenses]]
