# Evaluation Issues Found and Fixes Applied
**Date:** 2026-04-28  
**Session scope:** BiomniEval1 regressions, CompBioBench integration, param_prefill improvements

---

## 1. BiomniEval1 Regressions (v20 → v24)

### Symptom
Overall score dropped from **64.6% (v20) → 55.2% (v24)**, driven by two task types:
- `gwas_variant_prioritization`: **72.1% → 37.2%** (−34.9pp, catastrophic)
- `rare_disease_diagnosis`: **76.7% → 40.0%** (−36.7pp, catastrophic)

`patient_gene_detection` and `gwas_causal_gene` were stable.

### Root Cause 1: gwas_variant format instruction over-engineering

**What changed:** In the session, the format instruction for `gwas_variant_prioritization` was replaced with a complex numbered-rules version:
```
MANDATORY RULES:
1. If a GWAS Catalog ranked list is provided, rsID ranked #1 IS the answer.
2. Associations labeled [NOT relevant] must be COMPLETELY IGNORED.
3. If GWAS context shows #1 with [RELEVANT] — that is the answer.
4. If no GWAS context, use training knowledge.
5. Do NOT refuse.
```

**Why it failed:** Rule 4 ("use training knowledge") led the model to cite well-known GWAS hits (e.g., rs1801133 for MTHFR/Homocysteine) that were NOT in the candidate list, then fall back to wrong candidates. The [RELEVANT]/[NOT relevant] labels added noise when the fallback lookup was triggered. Overall: the complex instruction confused the model compared to the simpler v20 version.

**Fix:** Reverted to a simpler instruction:
- Single sentence: select rsID with strongest trait association from GWAS Catalog context
- One bullet: ignore [NOT relevant] labeled associations
- One bullet: if GWAS context missing or inconclusive, use training knowledge
- Final rule: answer MUST be from the candidate list

### Root Cause 2: HPO file version drift causing rare_disease ranking changes

**What changed:** The HPO disease annotation file (`phenotype.hpoa`) is downloaded live from `purl.obolibrary.org` on every run. The file is updated ~quarterly by the HPO consortium. Between v20 (ran April 27) and v24 (ran April 28), the file version may have changed OR the file was the same version but cached differently.

More likely: different HPO versions give different disease-phenotype associations, so the weighted overlap scores for candidate diseases change, and the ranked list presented to the LLM changes. The model then picks based on training knowledge when the ranking is ambiguous.

**Concrete example:**
- Instance 63: GT=Arthrogryposis DA1A (108120), model picked DA2B2 (618435)
- Both are "distal arthrogryposis" subtypes — HPO score difference between them may have flipped
- When top scores are close, model training bias tips the decision to the "more familiar" disease

**Fix:** Pinned HPO file to local cached version (`datasets/hpo/phenotype.hpoa`, version 2026-02-16). Now loads from disk first, falls back to download only if file absent. This ensures reproducible rankings across runs.

---

## 2. Param Prefill Improvements

### Changes made
1. **Schema-based guardrail** (`_validate_extracted_params`): Post-LLM extraction, validates all values against `allowed_values` from `.nf` stub comments. Drops/normalizes values violating schema.
2. **Genome alias normalization**: `human` → `GRCh38`, `mouse` → `GRCm39`, etc. — always applied regardless of schema.
3. **Strandedness normalization**: `dUTP` → `reverse`, `ligation` → `forward`, etc.
4. **Rule-based unit conversion** (`_rule_based_param_inference`): 
   - `N ns + M fs` → `n_steps = N×10⁶/M, dt = M/1000`
   - `Nx coverage` → `genome_coverage = N`
   - `remove mitochondrial` → `keep_mito = False`
   - `single-end` → `single_end = True`
   - `paired-end` → `paired_end = True`
5. **nf-core stub files** updated: `single_end`, `read_length` (rnaseq), `genome_coverage`, `analysis_type` (sarek), `paired_end`, `keep_mito`, `max_fragment_size` (atacseq), `qvalue` (chipseq), `min_coverage` (methylseq), new `proteomicslfq/main.nf` with `labeling_reagent`.

### Score progression
- v3: 49.9% (baseline, pre-fixes)
- v4: 49.5% (rules added but Galaxy not reloaded)
- v5_live: **53.1%** (rules live, after Galaxy restart)

### Key insight: LLM unreliable for arithmetic
Unit conversions (`n_steps` from ns + fs) must be rule-based. LLMs reliably fail at multi-step arithmetic with large numbers (exponents, decimal shifts). The rule computes `int(100 × 10⁶ / 2) = 50000000` exactly; the LLM gives 500000 or 5000000 non-deterministically.

### Critical: never modify production workflow files for benchmark purposes
Only `biomni_workflows/nfcore/*.nf` stub files are safe to edit for param extraction. Production files under `nextflow_nfcore/subworkflows/` are executed by Nextflow — params must match Groovy code. Adding `simulation_length_ns` to gromacs `main.nf` would create a param that's set but silently ignored during execution.

---

## 3. AI Findings Grounding Guardrail

**Problem:** When no output files were readable, LLM was given "provide general guidance based on workflow type" → invented key_results values.

**Fixes:**
1. Skip LLM entirely when `outputSamples.length === 0` → return safe static response
2. System prompt hardened: "Every numeric value in key_results MUST appear verbatim in output files"
3. Citations field removed from schema (was main source of PMID fabrication)
4. Post-generation cross-check: numeric values in `key_results` verified against file content

---

## 4. GWAS Catalog Trait Matching Improvement

**Problem:** `_trait_relevance_score` missed "Homocysteine measurement" when querying for "Homocysteine" because "measurement" was in the stop-word list.

**Fix:** Added measurement-suffix stripping before keyword comparison:
- `"Homocysteine measurement"` → strip `" measurement"` → `"Homocysteine"` → exact match

**Also:** Fallback `lookup_gwas_catalog` now labels each association `[RELEVANT to <trait>]` or `[NOT relevant to <trait>]` so the model can ignore unrelated strong associations.

**Result:** gwas_variant score didn't improve meaningfully (46.5% v23 vs 46.5% v22) because the live GWAS Catalog data doesn't always agree with benchmark ground truth (data drift issue, not a code issue).

---

## 5. CompBioBench Integration

### What CompBioBench tests
100 tasks (genomics, transcriptomics, epigenomics, single-cell, population genetics, ML for biology) requiring code execution, API access, and specific answer extraction. Scored by exact string match via a private answer key on the HuggingFace leaderboard.

**Submission format:** TSV with `question_id`, `answer` columns. Agents must output `FINAL ANSWER:\n<answer>`.

### BioMate's result on 27 no-file tasks
- **8/27 produced specific answers** (30% rate)
- **18/27 confused** (routing to workflow mode, asking for file uploads)
- **1/27 failed silently**

### Good answers (BioMate has direct tool/API access)
- `annotate-variant-gene-impact-q1`: ClinVar → `pathogenic` ✓
- `annotate-variant-gene-impact-q2`: Ensembl VEP → `upstream_gene_variant` ✓
- `annotate-variant-regulatory-overlap-q1`: ENCODE cCRE → `pELS,EH38E1957012` ✓
- `compute-gc-content-interval-q1`: Ensembl sequence → GC% + MD5 ✓
- `extract-rna-secondary-structure-q1`: ViennaRNA → dot-bracket + MFE ✓
- `1000G-retrieve-genotype-q1`: 1000G API → genotype string ✓
- `compute-gccontent-promoter-q1`: Ensembl promoter → formatted string ✓
- `compute-nonoverlapping-exonic-length-q1`: GENCODE GTF → integer ✓

### Root cause of failures
BioMate is optimized for workflow-launching. When CompBioBench asks "retrieve X and compute Y", BioMate interprets it as a workflow task requiring file uploads ("Confirm the intended analysis priority and upload the required inputs"). It doesn't recognize when a question has a direct API-answerable answer.

**Required improvement:** BioMate needs a "direct answer mode" that bypasses workflow routing for knowledge/API questions, uses its ResearchAgent + tool execution directly, and outputs a specific answer rather than a workflow launch suggestion.

### Submission
`results/compbiobench_v1_nofile/submission.tsv` — ready to submit to leaderboard at:
https://huggingface.co/spaces/Genentech/compbiobench-leaderboard-v1

---

## 6. Score Summary (2026-04-28)

| Benchmark | Previous best | Current | Delta |
|---|---|---|---|
| BiomniEval1 (overall) | 64.6% (v20) | 55.2% (v24) | −9.4pp (regression being fixed) |
| gwas_variant | 72.1% (v20) | 37.2% (v24) | −34.9pp (fix applied → v25) |
| rare_disease | 76.7% (v20) | 40.0% (v24) | −36.7pp (HPO pinned → v25) |
| patient_gene | 74.0% | 74.0% | stable |
| screen_gene | 28.0% (v20) | 40.0% (v24) | +12pp |
| Param Prefill | 49.9% (v3) | 53.1% (v5_live) | +3.2pp |
| PBPK | 33.3% (v2) | 50.0% (v3) | +16.7pp |
| BOIN | 80.5% (v2) | — | stable |
| Routing | 94.6% (v11) | — | stable |
| CompBioBench | NEW | 30% (8/27 no-file) | — |

## 7. Open Tasks

- [ ] v25 results pending (gwas_variant + rare_disease targeted runs)
- [ ] CompBioBench: improve BioMate's direct-answer capability (route knowledge questions to ResearchAgent, not workflow launcher)  
- [ ] CompBioBench: download remaining data files to run full 100-task evaluation
- [ ] Update evaluation matrix xlsx with all v28 results
- [ ] Submit CompBioBench answers to HuggingFace leaderboard
