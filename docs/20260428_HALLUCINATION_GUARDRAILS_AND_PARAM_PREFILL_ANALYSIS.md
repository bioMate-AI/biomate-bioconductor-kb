# Hallucination Guardrails + Param Prefill Analysis
**Date:** 2026-04-28  
**Session scope:** Hallucination detection strategy, guardrail implementation, param_prefill root-cause analysis

---

## 1. Hallucination Strategy: Detection → Guardrail

The goal is not to measure a hallucination rate for reporting. The goal is to find where BioMate confabulates and block it. Detection is the diagnostic; the guardrail is the fix.

### Three hallucination types in BioMate

| Type | Where | Example |
|---|---|---|
| **Enum value** | Param extraction | `genome="Human"` (not a valid nf-core value) |
| **Fabricated finding** | AI Findings panel | LLM asserts IC50=0.3 µM not present in any output file |
| **Entity** | Knowledge queries | ENSG ID or HPO term that doesn't exist in dataset |

### Current measured rates
- BiomniEval1 v20: **16.6%** (25 hallucinated / 151 grounded+hallucinated) — most reliable
- SGI-Bench v1: **25.5%** — high but expected (model cites papers it cannot access)
- Routing: **44.9%** — miscategorized; routing errors ≠ factual confabulation, excluded

---

## 2. Guardrail #1: Param Schema Validation (LIVE)

**File:** `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py`

### What was built

**`_parse_nextflow_params` extended** to extract allowed enum values from pipe-separated options in `.nf` file comments:
```
params.aligner = 'star_salmon'  // Alignment tool: star_salmon | hisat2 | star_rsem
```
→ parsed as `allowed_values = ["star_salmon", "hisat2", "star_rsem"]`

**`_validate_extracted_params` added** — runs after every LLM extraction call:
- `genome`: always normalized via canonical alias map (`human` → `GRCh38`, `mouse` → `GRCm39`, etc.)
- `strandedness`: normalized via alias map (`dUTP` → `reverse`, `ligation` → `forward`, etc.)
- Any param with `allowed_values` in schema: case-insensitive match; non-matching values dropped with log warning

**Impact:** Prevents wrong enum values from reaching the workflow CLI and causing silent failures (e.g., `--genome Human` causes nf-core to crash at genome index lookup).

### nf-core stub files updated
Safe to modify (pure param extraction, not executed):
- `nfcore/rnaseq/main.nf` — added `single_end`, `read_length`
- `nfcore/sarek/main.nf` — added `genome_coverage`, `analysis_type`, tools enum updated to include `Mutect2`
- `nfcore/atacseq/main.nf` — added `paired_end`, `keep_mito`, `max_fragment_size`
- `nfcore/chipseq/main.nf` — added `qvalue`
- `nfcore/methylseq/main.nf` — added `min_coverage`
- `nfcore/proteomicslfq/main.nf` — new file with `labeling_reagent` enum

**Critical distinction:** Only modify files under `biomni_workflows/nfcore/` (pure stubs). Never modify production workflow `.nf` files under `nextflow_nfcore/subworkflows/` — those are executed by Nextflow and params must match the Groovy code.

---

## 3. Guardrail #2: AI Findings Grounding (LIVE)

**File:** `frontend/server/routes.ts` — `/api/workflows/runs/:id/findings` endpoint

### Problem
When no output files were readable, the LLM was given:
```
"(No readable output files found — provide general guidance based on workflow type.)"
```
This explicitly invited hallucination — the LLM invented key_results values.

Even with files present, the LLM generated `citations` with fabricated PMIDs.

### Fixes applied

1. **No-file case**: LLM is never called. Returns a safe static response:
   ```
   key_results: []
   summary: "Output files not yet readable — check the Outputs tab."
   ```

2. **System prompt hardened**: explicit grounding rules:
   - "Every numeric value in key_results MUST appear verbatim in the provided output files"
   - "Do NOT invent, estimate, or round values not present in the files"
   - Citations field removed from schema entirely

3. **Post-generation cross-check**: each numeric value in `key_results` is verified against a set of all numbers extracted from the actual output files. Values containing numbers not found in any output file are dropped.

---

## 4. Param Prefill Root-Cause Analysis

**Current score:** 49.9% (v3/v4). Target: ≥70%.

### Category breakdown

| Category | Cases | Score | Root cause |
|---|---|---|---|
| `genome_inference` | ~20 | ~80% | Mostly working; alias normalization fixes some |
| `strandedness_inference` | ~10 | ~75% | Working after alias fix |
| `numeric_param_inference` | ~15 | ~60% | LLM misses non-obvious numeric fields |
| `reference_file_selection` | ~10 | ~45% | Genome name in path context |
| `multi_param_inference` | ~20 | ~40% | Multiple params from one sentence |
| `negative_cases` | ~10 | ~90% | Correctly not filling |
| `param_name_disambiguation` | 15 | ~8% | See below |

### param_name_disambiguation: Two-problem analysis

**Problem 1 — Benchmark design error (param name mismatch):**
The expected param names don't match the actual workflow schema. Test expects `micrograph_pixel_size` but cryosparc workflow uses `pixel_size`; test expects `accelerating_voltage` but workflow uses `voltage`.

Fix: Update test cases to use actual workflow param names. Do NOT add non-existent params to production workflow files.

**Problem 2 — True context interpretation (BioMate capability gap):**
These require either unit conversion or semantic negation — genuine capability the LLM struggles with:

| Test case | User says | Expected | Challenge |
|---|---|---|---|
| pf_108 | "100 ns, timestep 2 fs" | `n_steps=50000000, dt=0.002` | Unit conversion (ns+fs → steps) |
| pf_113 | "remove mitochondrial reads" | `keep_mito=false` | Negation handling |
| pf_109 | "q-value 0.01" | `qvalue=0.01` | Field name mapping |
| pf_110 | "stranded library" | `strandedness=forward` | Ambiguous (forward or reverse?) |
| pf_115 | "10x coverage minimum" | `min_coverage=10` | Context-to-field mapping |
| pf_114 | "generate 5000 molecules" | `num_molecules=5000` | Requires workflow code to accept |

### LLM weakness: numbers

LLMs are unreliable at multi-step numeric reasoning:
- "100 ns with 2 fs timestep" → n_steps = 100×10⁶/2 = 50,000,000 — LLM often gets the exponent wrong
- "10x coverage" → coverage=10, NOT 10× something — LLM sometimes treats as multiplier
- Unit-aware conversions (ps↔fs, Å↔nm) fail non-deterministically

**Solution: rule-based computation for numeric conversions** in `_rule_based_param_inference`, not LLM. The rules are deterministic and exact.

### Negation handling
LLMs handle negation better than arithmetic:
- "remove mitochondrial reads" → `keep_mito=false` — reliably extracted
- "skip trimming" → `skip_trimming=true` — reliable
- "do not use" → `use_x=false` — mostly reliable

Negation cases can stay as LLM tasks; arithmetic/unit conversion must be rule-based.

---

## 5. BiomniEval1 Failure Analysis

### gwas_variant_prioritization: 46.5%

**Root cause:** GWAS Catalog fallback lookup (`lookup_gwas_catalog`) shows ALL associations for each rsID without filtering by query trait. The LLM picks the strongest p-value it sees, which may belong to an unrelated trait.

Example: query "Homocysteine", rsID rs12550729 has p=6e-110 for "5-oxoproline measurement". The LLM picks rs12550729 even though the ground truth is rs9369898 (the true homocysteine GWAS hit).

**Fix applied:**
1. `_trait_relevance_score` extended with measurement-suffix stripping: "Homocysteine measurement" now correctly matches query "Homocysteine" (strips " measurement" before comparing)
2. Fallback `lookup_gwas_catalog` now labels each association `[RELEVANT to <trait>]` or `[NOT relevant to <trait>]`
3. Format instruction strengthened: numbered mandatory rules, explicit instruction to ignore `[NOT relevant]` labeled associations

### screen_gene_retrieval: 40%

**Root cause 1 — Refusals:** When `_parse_screen_gene_question` fails to extract perturbation, `lookup_crispr_screen_context` returns `""`. The format instruction said "use PubMed literature provided above" — model refused when none was provided.

**Root cause 2 — Training data bias:** For known drug-resistance screens, LLM picks "famous" pathway genes (SLFN11 for selinexor, XPO1 for nuclear export) rather than the empirical screen hit (which may be an obscure transporter or lncRNA).

**Fix applied:** Format instruction rewritten with explicit rules:
- "DO NOT refuse. There is always a best answer — commit to one gene."
- "DO NOT say 'no reference list was provided'" 
- Specific anti-bias guidance: lncRNAs, transporters, uncharacterized ORFs are common screen hits

---

## 6. Open Issues

- **n_steps unit conversion**: rule-based fix still to implement in `_rule_based_param_inference`
- **param_name_disambiguation test case corrections**: Problem 1 cases need expected values corrected to match actual workflow schemas
- **param_prefill v5 run**: needed to measure post-guardrail improvement
- **BiomniEval1 v23**: gwas_variant and screen_gene targeted re-runs in progress
- **PBPK benchmark scoring**: `incomplete_no_params` cases penalized unfairly (score=0 when BioMate correctly launches with defaults); needs re-run after scoring fix
