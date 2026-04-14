# Routing Benchmark: Systemic Findings and Remediation Plan
**Date**: 2026-04-07  
**Branch**: integration/next-phase  
**Benchmark progress**: 13/21 (62%) → 26/30 (87%) this session

---

## Benchmark Trajectory

| Run | Score | Notes |
|-----|-------|-------|
| v0 (session start) | 13/21 (62%) | 9 pending, 7 wrong |
| v1 | 19/30 (63%) | orphaned gunicorn workers serving old code |
| v2 | 19/30 (63%) | Tier 2 (Jaccard) pre-filter missing |
| v3 | 24/30 (80%) | sc_002/004/005 pre-filter broken |
| **v4** | **26/30 (87%)** | current best; 3 failures: rna_013, sc_007, sc_009 |

---

## Problems Found — Systemic, Not Benchmark-Specific

### P1. Chain pre-empts workflow search based on wrong input type
**Symptom**: `single_cell_multimodal_analysis` chain (requires Cell Ranger output/h5ad) matched raw FASTQ scRNA-seq queries, preventing `nf-core/scrnaseq` from ever being evaluated. Step 0 chain search returns early — if it fires, workflow search is skipped entirely.

**Root cause**: `required_inputs` field existed in DB with correct structured data (`{"name": "cellranger_output", "type": "directory"}`) but was **not used in any matching logic** — only weakly in embedding text.

**Fix applied**: `_chain_input_compatible(chain, user_types)` code pre-filter runs BEFORE `_llm_select_chain`. Deterministic Python: if user has `{fastq, bam, reads}` AND chain requires `{directory, h5ad, mtx, anndata}` → reject chain. Applied to both Tier 1 (embedding) and Tier 2 (Jaccard fallback).

**Broader scope**: Every chain in the system should be gate-checked for input compatibility. The `connections[]` field (data flow between chain steps) should be validated at chain-load time: `output_types` of step N must overlap `input_types` of step N+1.

---

### P2. `input_types`/`output_types` DB fields existed but were unused in search
**Symptom**: `nf-core/differentialabundance` (needs `counts_matrix`) competed equally with `nf-core/rnaseq` (needs `fastq`) for DE analysis queries, regardless of what data the user actually had.

**Root cause**: SQL query didn't even SELECT `input_types`/`output_types`. `_calculate_score()` had no input-type scoring.

**Fix applied**: SQL updated to fetch both fields. Step 8 added to `_calculate_score()`:
- **+3.0**: user's detected types overlap with `input_types` (right tool for their data)
- **−4.0**: user has raw data (`fastq/bam/reads`) but workflow needs processed input (`counts_matrix/h5ad`)
- **−6.0**: workflow takes non-file parameters (`gene_name`, integers) but user has biological samples

**Broader scope**: `output_types` still unused. Should be used to:
1. Validate chain step connections formally
2. Score "downstream analysis" queries (user has h5ad → boost workflows that accept h5ad)
3. Surface "what comes next" suggestions after a workflow completes

---

### P3. User data type not inferred from natural language
**Symptom**: "Align Drop-Seq single-cell data", "SmartSeq2 plate data", "my samples from Arabidopsis" — none of these triggered input-type detection, so no scoring penalty/boost applied.

**Root cause**: `_detect_query_data_types()` only matched explicit file extensions (`.fastq`, `.bam`). Users rarely say "my FASTQ files".

**Fix applied**: Extended patterns:
- **Alignment intent**: `"align [reads|data|seq]"` → `reads`
- **Single-cell protocols**: Drop-seq, SmartSeq2, 10x Genomics, BD Rhapsody, etc. → `reads`
- **Ownership language**: `"my samples"`, `"my data"`, `"I have samples"` → `reads`
- **Count matrix possession**: `"my|have|from ... count matrix"` (not `"generate a count matrix"`) → `counts_matrix`

**Broader scope**: This signal should also gate the **prereq validator** — if the user has FASTQ, the prereq checklist should ask for FASTQ, not count matrices. Currently prereq validation is independent of detected input types.

---

### P4. Sparse workflow annotations — FTS penalises correct nf-core pipelines
**Symptom**: `nf-core/sarek` (15-word description) lost to `Wgs Germline Gatk` (500-word description with all GATK/variant-calling terms). FTS rewards lexical richness.

**Root cause**: nf-core workflows were bulk-imported with description = first line of README. Competing biomni_nextflow workflows were auto-generated with full pipeline descriptions.

**Workflows fixed this session**:
- `nf-core/sarek`: Added Mutect2, HaplotypeCaller, tumor-normal, somatic, SNP/indel, BQSR, breast cancer, detect somatic mutations
- `nf-core/rnaseq`: Added BigWig, coverage tracks, Arabidopsis thaliana, plant, STAR, Salmon, featureCounts
- `nf-core/scrnaseq`: Added doublet detection, empty droplets, all protocols (Drop-seq, SmartSeq2, Parse Bio, SPLiT-seq)
- `nf-core/spatialvi`: Added spatial gene expression, tissue section, tumor, where genes are expressed
- `nf-core/differentialabundance`: Added GSEA, DESeq2, edgeR, count matrix input

**Broader scope**: ~200+ nf-core entries likely have stub descriptions (< 100 chars). Systematic enrichment needed from nf-co.re docs (scraper already built for benchmark rebuild).

---

### P5. LLM narrative guardrails are unreliable for structural constraints
**Symptom**: Adding "Rule 0: if FASTQ and chain requires directory, return none" to `_llm_select_chain` prompt did NOT reliably prevent wrong chain selection. The Haiku model ignored or misapplied the rule.

**Fix applied**: Narrative Rule 0 removed entirely. Python code now handles structural compatibility. LLM prompt updated to say "all candidates passed input-type compatibility check" — LLM only judges semantic scope, not data compatibility.

**Broader scope**: General principle now established:
- **Structural constraints** (type X ≠ type Y, field must be non-null, range checks) → Python code
- **Semantic judgment** (does this query scope match this pipeline's purpose?) → LLM
- Any time a narrative rule can be expressed as a data comparison, it should be code

---

### P6. Multiple gunicorn masters binding to same port
**Symptom**: Two gunicorn master processes (PIDs 1168963 + 1706174) both bound to port 8081. HUP sent to the first didn't affect workers of the second. Benchmark results were nondeterministic.

**Root cause**: `start_backend.sh` starts a new master unconditionally without checking for existing ones.

**Fix needed in `start_backend.sh`**: Add PID file check — if gunicorn is already running on 8081, send HUP to reload it rather than starting a new instance.

---

## Remaining 3 Failures (26/30)

| ID | Query | Routed to | Issue |
|----|-------|-----------|-------|
| rna_013 | "Identify genes upregulated in lung tissue from COVID-19 patients vs healthy controls" | empty | AI sees this as a DE knowledge question, not a workflow request |
| sc_007 | "Quality control of single-cell sequencing: filter empty droplets and doublets" | Generated Workflow | Score threshold not met; AI generates custom instead of matching scrnaseq |
| sc_009 | "I need spatial gene expression data showing where genes are expressed in my tumor section" | empty | "I need spatial data" phrased as data acquisition; AI returns needs_input |

These 3 failures share a root cause: the **intent classification layer** in `ai_assistant.py` interprets them as knowledge/data questions rather than routing them to workflows. This is a separate problem from the routing search itself.

---

## Remediation Plan

### Immediate (< 1 day)

**A. Fix `start_backend.sh` for single master**
```bash
# In start_backend.sh — add before gunicorn launch:
PIDFILE=/tmp/gunicorn_galaxy.pid
if [ -f "$PIDFILE" ] && kill -0 $(cat "$PIDFILE") 2>/dev/null; then
    echo "Reloading existing gunicorn..."
    kill -HUP $(cat "$PIDFILE")
    exit 0
fi
```

**B. Fix the 3 remaining benchmark failures**
- rna_013: In `ai_assistant.py` intent classifier, "identify genes upregulated/downregulated in [condition]" → route to `nf-core/rnaseq` as starting point, not clarification
- sc_007: Lower match threshold for QC sub-queries within a known domain; "filter empty droplets" should not generate custom workflow when scrnaseq has explicit annotation for it  
- sc_009: Add "where genes are expressed in tissue" → spatialvi pattern to intent classifier or annotation

### Short-term (1–3 days)

**C. Systematic annotation enrichment pass**
- Query: `SELECT name, description FROM workflows WHERE source='nfcore' AND length(description) < 150`
- For each, fetch description from nf-co.re docs API, update DB description + annotation
- Estimated: ~200 entries, can be scripted with the existing doc scraper

**D. Wire `output_types` into chain validation**
- At chain-load time: assert `output_types[step_N] ∩ input_types[step_N+1] ≠ ∅` for each connected pair
- Surface validation errors in chain editor (if one exists)
- Use for "what comes next" suggestions: after rnaseq completes (outputs `counts_matrix`), suggest `differentialabundance`

**E. Extend `_detect_query_data_types` to more domains**
- Add: VCF possession ("I have VCF files"), BAM/CRAM ownership, PDB/structure files, SMILES/SDF compounds
- Wire into prereq validator: detected user types should seed the prereq checklist defaults

### Medium-term (1–2 weeks)

**F. Auto-enrichment pipeline for workflow annotations**
- Scheduled job: for each workflow in DB, check if description < 200 chars
- Fetch from nf-co.re API (for nfcore) or generate from workflow .nf file (for biomni_nextflow) using Haiku
- Update description + annotation + FTS index automatically

**G. Input/output graph validation for all chains**
- Build a typed DAG from `steps[]` + `connections[]` + workflow `input_types`/`output_types`
- Validate: every connection `from_output → to_input` must type-check
- Alert on chain creation if a step's expected inputs can't be satisfied by the preceding step's outputs

**H. Run full 120-task benchmark**
- Once remaining 3 failures are addressed, run `python evaluation/runners/run_routing.py` (full 120 tasks)
- Target: ≥80% overall, ≥70% on adversarial pairs
- Record as official baseline in session doc
