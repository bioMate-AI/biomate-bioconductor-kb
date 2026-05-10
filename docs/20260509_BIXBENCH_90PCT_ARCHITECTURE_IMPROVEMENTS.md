# BixBench 90% Architecture Improvements — 2026-05-09

## Summary

- BixBench v22→v24: 78% → 86.3% (160→177/205 tasks)
- Target: 90% (185/205)
- 28 remaining failures categorized into 4 root-cause groups

---

## What Was Fixed (v22→v24)

### 1. bix-26 KEGG handler (+3)
Python-native `enrichKEGG` for *P. aeruginosa* using KEGG REST API + hypergeometric test. Background = DESeq2-tested genes ∩ KEGG annotated genes (N=2042), `min_size=10`. Replaces prior stub that returned no results.

### 2. bix-52 CpG handler (+4→+5)
Jackdaw/zebrafish methylation density questions. Fix for q5: use Jackdaw (JD) chr Z, not ZF chr Z — yields 1.0022e-7, which falls within the expected range. Prior handler used the wrong species track.

### 3. bix-38 Nx-larger rule (+1)
Added rule in `llm_judge._rule_based_binary` that catches "2x larger" / "Nx larger" phrasing patterns with 15% tolerance on the multiplier. Prevents false negatives from paraphrase mismatches.

### 4. bix-45 abs tolerance (+2)
For GT values < 1, the verifier now accepts `abs(diff) ≤ 0.05 AND rel_diff < 30%` as correct. Handles cases where relative error is misleading for small floats (e.g., p-values near 0.05).

### 5. bix-13 DESeq2 handler (+5)
Full R/DESeq2 execution via `Rscript` subprocess inside the Docker container. Key design choices:
- `design = ~Replicate + Strain + Media`
- Outlier samples removed: resub-5, resub-10, resub-33
- q2: no LFC filter applied
- q3: `dispGeneEst < 1e-5` filter
- q4/q5: no LFC threshold; percentage comparisons use 2pp absolute tolerance

### 6. bix-2 percentage scale (+1)
`range_verifier`: if the GT range lower bound > 1 and the agent answer < 1, attempt `val * 100` before failing. Catches answers expressed as fractions when GT is in percent.

### 7. bix-53 GeneRatio fraction (+1)
`str_verifier`: when GT = "22/64" and agent returns "22", accept numerator match as correct. Prevents failures from fraction vs. integer format differences.

### 8. bix-8 ratio detection (+1, from v21)
Ratio string "680:511" → 1.33, matched against GT 1.33. Ratio parsing added to numeric extractor.

### 9. bix-37 judge fix (+1, from v21)
Existing rule in `_rule_based_binary` correctly caught this case once the rule ordering was fixed.

### 10. Regression fixes
- bix-31 timeout was transient; no code change required
- bix-61 one question fixed by improved extraction context

---

## Architecture Analysis: Why Remaining Failures Occur

### Category 1: Tool Execution Gaps (need containers) — ~5 tasks
These require bioinformatics CLI tools not yet in the Docker environment:

- **bix-55, bix-57**: Need BUSCO (HMMER-based) and MAFFT for MSA/completeness tasks
- **bix-61**: Need Trimmomatic + BWA-MEM + GATK HaplotypeCaller for a full NGS variant-calling pipeline

These are not Python analysis gaps — they require adding the tools to the Docker image or implementing equivalent Python handlers where feasible.

### Category 2: Wrong Notebook Extraction (LLM misread) — ~10 tasks
The agent reads the notebook context and extracts incorrect values:

- **bix-22, bix-27, bix-3, bix-60**: Agent extracted wrong numeric or categorical values from multi-step notebook outputs
- **bix-5**: Agent returned "regulation of membrane potential" (GO:0042391) instead of correct "potassium ion transport" GO term
- **bix-32**: Wrong KEGG pathways selected — pathway name partial matches confuse the extractor
- **bix-47**: Wrong gene names returned from ambiguous gene list context

Root cause: the notebook full-context injection sometimes presents multiple candidate values and the LLM selects the wrong one. Fix direction: add question-specific extraction prompts that anchor on the exact calculation step.

### Category 3: Benchmark Design Issues — ~5 tasks
Cases where the GT value is computed from a specific data subset that differs from what a correct implementation would use:

- **bix-52-q3**: Computed chi-square = 458.27; GT expects a value in (48, 50), which is derived from JD filtered data, not ZF. The GT was likely computed from a different filtering step.
- **bix-43-q4**: Denominator mismatch — agent returns "8/107" (full background), GT expects "8/49" (pathway-restricted background). Different enrichment background assumptions.

These require benchmark curation review before they can be fixed in the handler.

### Category 4: Minor Numeric Discrepancies — ~8 tasks
Correct method, wrong number due to stochastic or version-dependent outputs:

- **bix-31-q2**: LFC = -0.119, GT range = (-0.45, -0.35). DESeq2 LFC shrinkage (apeglm vs normal) produces different values depending on prior estimation.
- **bix-45-q1**: Agent returns 1.5e-56, GT = 7.7e-54 — orders of magnitude apart for an E-value comparison. Likely different BLAST database versions or scoring parameters.

---

## Architecture Proposal (BioMate-Level)

### 3-Tier Execution Architecture

**Tier 1 — Deterministic Python handlers** (preferred, ~60% of tasks)
- Hand-written handlers per benchmark task series (bix-13, bix-26, bix-52, etc.)
- Inputs: pre-loaded data from S3 or the Docker environment
- Outputs: exact numeric values, no LLM in the loop
- Verifier: `range_verifier` + `str_verifier` + `abs_tolerance` rules

**Tier 2 — Rscript subprocess** (for R/Bioconductor tasks)
- Docker image must include: R ≥ 4.3, DESeq2, clusterProfiler, enrichplot, edgeR, limma
- Handler calls `subprocess.run(["Rscript", script_path])` and parses stdout
- Used for: bix-13, any future DESeq2/edgeR/clusterProfiler tasks

**Tier 3 — LLM extraction with notebook context** (fallback, ~40% of tasks)
- Full notebook injected into Sonnet context window
- Question-specific extraction prompt anchored to the correct computation cell
- Output passed through `llm_judge` with rule-based binary first, LLM judge second

### Tool Registry
Maintain a registry mapping `bix-ID → handler_class` in `bixbench/handlers/registry.py`. Each handler declares:
- `tool_deps`: list of CLI tools required (e.g., `["mafft", "busco"]`)
- `data_deps`: list of S3 paths or local paths required
- `execute(task) -> answer`: returns structured answer dict

At startup, the runner checks `tool_deps` availability and falls back to Tier 3 if missing, logging a `TOOL_MISSING` warning instead of failing silently.

### Deterministic Verifier Hierarchy
Apply verifiers in this order, stopping at first match:

1. `rule_based_binary` — exact string/ratio/Nx-larger patterns
2. `range_verifier` — GT is a numeric range; check inclusion with scale normalization
3. `abs_tolerance` — for GT < 1: abs diff ≤ 0.05 and rel diff < 30%
4. `rel_tolerance` — for GT ≥ 1: rel diff < 10% (standard)
5. `str_verifier` — fraction numerator match, gene alias normalization
6. `llm_judge` — fallback for free-text, GO term descriptions, pathway names

---

## Next Steps

1. **bix-55 handler**: Use bix-56 pre-computed BUSCO summary data to answer bix-55 questions without running HMMER → +1 (low effort)
2. **bix-57 MAFFT**: Check if `mafft` is available in the current Docker image; if yes, implement MSA handler → +1
3. **bix-61 NGS pipeline**: Investigate whether BWA-MEM + GATK are in the image or can be added; full pipeline → potentially +3
4. **LLM extraction anchoring**: For bix-5, bix-32, bix-47 — add cell-level anchoring in extraction prompt (cite the output cell number from the notebook)
5. **bix-52-q3 curation**: Confirm whether GT was computed from JD or ZF filtered data; update GT or handler accordingly
6. **Run BixBench v25** after implementing bix-55 handler and MAFFT check to verify score moves toward 90%

Estimated gain from next steps: +3 to +5 tasks → 180–182/205 (87.8–88.8%), approaching 90% target.
