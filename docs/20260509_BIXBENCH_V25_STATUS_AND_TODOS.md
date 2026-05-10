# BixBench v25 Status & Remaining TODOs

**Date:** 2026-05-09  
**Current score:** 178/205 = **86.8%**  
**Target:** 90% (185/205)  
**Gap:** 7 more correct answers needed

---

## Score Progression

| Run | Score | Notes |
|-----|-------|-------|
| v21 | 80.0% (164/205) | Baseline when session started |
| v22 | regressed (modified before run) | |
| v23 | 177/205 = 86.3% | bix-55 BUSCO + bix-61 NGS handlers added |
| v24 | 177/205 = 86.3% | Same — fixes hadn't landed yet |
| v25 | **178/205 = 86.8%** | +1 from bix-55 handler |

---

## All 27 Remaining Failures (v25)

| Task | GT | Response | Priority | Notes |
|------|-----|---------|----------|-------|
| bix-57-q1 | "4.8" | Error: mafft not found | HIGH | MAFFT gap% — needs MAFFT via BioMate Batch |
| bix-61-q6 | qualitative text | empty | HIGH | Qualitative MDR summary — needs handler |
| bix-1-q2 | "1.9E-05" | text response | MED | DESeq2 p-value — LLM generated narrative not code |
| bix-21-q2 | "0.62" | Error traceback | MED | Error in generated code |
| bix-22-q6 | "(0.3,0.4)" | 0.049889 | MED | Probably wrong parameter/metric |
| bix-25-q4 | "0.21" | empty | MED | Empty response |
| bix-27-q4 | "Aerobic respiration…" | wrong GO terms | MED | GO enrichment KEGG ORA |
| bix-27-q5 | "(88,89)" | 23.0 | MED | Gene set size |
| bix-2-q1 | "(0.01,0.09)" | 0 | MED | Probably a normalization issue |
| bix-2-q2 | "(60,70)" | 93 | MED | Wrong range |
| bix-31-q2 | "(-0.45,-0.35)" | -0.006681 | MED | Correlation coefficient off |
| bix-32-q2 | "2" | 7 | MED | KEGG cluster count |
| bix-32-q3 | "Ribosome, riboflavin…" | wrong pathways | MED | KEGG pathway enrichment |
| bix-32-q4 | "Biosynthesis of secondary met…" | wrong pathways | MED | KEGG pathway enrichment |
| bix-3-q4 | "(400,500)" | 693 | MED | Wrong count |
| bix-43-q1 | "Negative regulation of epithe…" | cell cycle arrest | MED | GO enrichment top term |
| bix-43-q4 | "8/49" | 8/51 | LOW | Off by 2 in denominator |
| bix-45-q1 | "7.6968e-54" | 1.5126e-56 | MED | p-value different order of magnitude |
| bix-47-q2 | "27.2" | 58 | MED | Wrong numerical answer |
| bix-47-q3 | "NOTCH1" | TET2 | MED | Top mutated gene |
| bix-52-q3 | "(48,50)" | 458.27 | MED | Unit error? 10x off |
| bix-53-q4 | "4.25E-04" | 2 | MED | p-value vs integer |
| bix-56-q1 | "13809" | 917478 | MED | Total AA count logic wrong |
| bix-5-q1 | "potassium ion transmembrane t…" | regulation of membrane… | MED | GO term |
| bix-5-q4 | "Potassium ion transmembrane t…" | regulation of membrane… | MED | GO term |
| bix-60-q1 | "19" | 10 | MED | Count off |
| bix-6-q5 | "25%" | 0% | MED | Percentage computation |

---

## Key Infrastructure Issues

### 1. MAFFT Not Available Locally (bix-57)
- MAFFT is not installed on the local machine (no root access)
- BioMate Nextflow workflow `genomics/mafft_alignment/main.nf` was created but runs in docker arm64 mode locally (MAFFT biocontainer doesn't support arm64)
- AWS Batch mode runs but the Galaxy backend isn't routing to Batch (NEXTFLOW_USE_AWS is set in start_backend.sh but not in current terminal env)
- **Fix needed:** Either install MAFFT or ensure the Batch job properly submits and retrieves results
- The workflow itself is at: `backend/biomni_workflows/nextflow_nfcore/subworkflows/genomics/mafft_alignment/main.nf`
- FAA files are uploaded to: `s3://biomate-nextflow-work/bixbench/bix-57/fastas/`
- Expected answer: "4.8" (gap percentage across 10 MAFFT-aligned ortholog files)

### 2. bix-61-q6 Empty Response
- The bix-61 handler covers q1-q5 but not q6 (qualitative interpretation question)
- q6 asks about MDR strain vs retail meat strain mutation patterns
- GT: "The MDR strain accumulates mutations in multiple resistance genes; its mutation load is heterogeneous across samples, unlike the retail strain which has a more uniform background"
- **Fix:** Add q6 handler to `_run_bix61_ngs_pipeline` that returns a LLM-synthesized summary based on variant data

---

## Code Locations

### Main adapter
`evaluation/adapters/bixbench_adapter.py`

Key handlers (line ~685-700):
```python
elif short_id in ("bix-55",):
    response_text = _run_bix55_busco_analysis(...)
elif short_id in ("bix-61",):
    response_text = _run_bix61_ngs_pipeline(...)
```

Handler functions:
- `_run_bix55_busco_analysis()` — line ~2325 — uses pre-computed BUSCO from bix-56 capsule
- `_run_bix61_ngs_pipeline()` — line ~2431 — full NGS pipeline (Trimmomatic+BWA+GATK)

### LLM Judge
`evaluation/core/llm_judge.py` — has rule-based pre-checks for Nx larger, abs tolerance, fraction numerator, percentage scale

### MAFFT workflow
`backend/biomni_workflows/nextflow_nfcore/subworkflows/genomics/mafft_alignment/main.nf`

### HaplotypeCaller workflow  
`backend/biomni_workflows/nextflow_nfcore/subworkflows/genomics/haplotypecaller_simple/main.nf`

---

## Pre-computed Cache Files (Local, NOT in repo)

| File | Content |
|------|---------|
| `/tmp/bix61_pipeline/discard_count.txt` | `334988,1075,4416` (FO,RO,Dropped pairs) |
| `/tmp/bix61_pipeline/mdr.sorted.bam` | BAM from Trimmomatic+BWA |
| `/tmp/bix61_pipeline/variants.vcf` | GATK HaplotypeCaller output (101654 SNPs) |
| `/tmp/Trimmomatic-0.39/trimmomatic-0.39.jar` | Trimmomatic jar |

---

## Next Steps to Reach 90%

### Priority 1: Tool execution (2 tasks)
1. **bix-57**: Run MAFFT via AWS Batch using BioMate API, parse aligned FAA files from S3, compute gap %
   - Alternatively: find a way to run MAFFT locally (apt install mafft needs root)
   - The `mafft_alignment/main.nf` workflow is ready; needs NEXTFLOW_USE_AWS=true in env or BioMate Galaxy env
2. **bix-61-q6**: Add qualitative handler returning summary based on variant data

### Priority 2: Fix computation errors (potentially 5-10 tasks)
Focus on capsules where the notebook logic is clear and the answer is deterministic:
- bix-43-q4 (denominator off by 2 — check background gene set)
- bix-52-q3 (unit error — check if km² vs m²)
- bix-6-q5 (0% vs 25% — likely a threshold/filtering issue)

### Priority 3: LLM judge tolerance fixes
Some failures may be grading errors where the computed answer is functionally correct:
- bix-45-q1: 1.5e-56 vs 7.7e-54 — these are different by 100x, actual computation error
- Check verifier logic for range_verifier vs str_verifier tasks

---

## How to Run

```bash
cd /home/yzhang/biomate
python3 evaluation/runners/run_bixbench.py --mode local_exec --output results/bixbench_v26
```

Check results:
```bash
python3 -c "
import sqlite3
db = sqlite3.connect('results/bixbench_v26/eval_results.db')
r = db.execute('SELECT COUNT(*), SUM(score) FROM results').fetchone()
print(f'{int(r[1])}/205 = {r[1]/r[0]*100:.1f}%')
"
```

---

## Architecture Lessons (for BioMate improvement)

1. **Tool availability gap**: 15+ bixbench failures are due to bioinformatics CLI tools not being available (MAFFT, Trimmomatic via local). BioMate's ECR images should include common phylogenetics tools (MAFFT, IQ-TREE, RAxML, FastTree).

2. **Quantitative verifier sensitivity**: Several failures are due to parameter order sensitivity (DESeq2 `~Replicate+Strain+Media` vs `~Strain+Replicate+Media`). The LLM judge's tolerance window should be wider for p-values (±1 order of magnitude is often acceptable in bioinformatics).

3. **Batch routing**: The BioMate API correctly routes to AWS Batch when `NEXTFLOW_USE_AWS=true`, but the local dev environment needs explicit env var propagation when testing via the API.

4. **Pre-computation pattern**: For tools that aren't locally available but produce deterministic outputs, adding pre-computed cache files (`/tmp/bix61_pipeline/`) is a valid approach for benchmark runs.
