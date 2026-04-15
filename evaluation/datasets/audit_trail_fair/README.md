# Audit Trail FAIR-Reproducibility Benchmark

**Status:** Construction spec — requires running 10 analyses + 3 independent reviewers  
**Timeline:** Phase 3 (June 2026) — needs 3-person-week reviewer commitment  
**This benchmark is the most novel contribution** — no other system provides
citation-backed, human-overridable decision trails with this level of provenance.

## Purpose

Tests whether BioMate's JSONL audit trails enable an independent researcher
to exactly reproduce a published analysis, including all QC decisions and
human override events — something no competitor provides.

**Core claim:** BioMate audit trails enable ≥90% exact reproduction.
MultiQC/nf-core outputs (no decision trail) enable <40% reproduction.

## The 10 analyses to run

| # | Domain | Workflow | Dataset | Why chosen |
|---|---|---|---|---|
| 1 | RNA-seq | nf-core/rnaseq + DESeq2 | ENCSR000AED | Standard; establishes baseline |
| 2 | RNA-seq | nf-core/rnaseq + edgeR | GSE68086 FFPE | Protocol edge case; tests override capture |
| 3 | scRNA-seq | nf-core/scrnaseq | GSE121893 | Multi-step QC; many decisions |
| 4 | scRNA-seq | nf-core/scrnaseq + trajectory | GSE150728 | Complex downstream; many parameters |
| 5 | Proteomics | nf-core/quantms DDA | PXD004732 | Phospho enrichment; protocol-aware |
| 6 | Proteomics | nf-core/quantms DIA | PXD040001 | DIA-NN pipeline; different QC logic |
| 7 | Drug docking | Glide SP + ADMET | sys_001 (CDK2) | Drug discovery pipeline audit |
| 8 | Drug docking | AutoDock + GROMACS | sys_006 (Mpro) | Open-source pipeline audit |
| 9 | Structure pred | Boltz-2 + Glide | sys_009 (β2-AR) | Multi-tool provenance |
| 10 | Metagenomics | nf-core/ampliseq | SRP047083 | Microbiome QC decisions |

## Audit trail format (JSONL)

Each line in the audit trail is a JSON object. BioMate already generates these;
this benchmark validates that they contain enough information for reproduction.

```json
{
  "event_type": "qc_decision",
  "timestamp": "2026-04-01T14:23:11Z",
  "step": "alignment_qc",
  "sample_id": "ENCSR000AED_rep1",
  "criterion": "mapping_rate",
  "measured_value": 0.94,
  "threshold": 0.70,
  "evidence_level": "GOLD",
  "evidence_citation": "10.1038/nmeth.3047",
  "decision": "PASS",
  "override": false
}

{
  "event_type": "human_override",
  "timestamp": "2026-04-01T14:25:33Z",
  "step": "duplication_qc",
  "sample_id": "GSE68086_FFPE_sample3",
  "criterion": "duplication_rate",
  "measured_value": 0.72,
  "threshold": 0.50,
  "evidence_level": "SILVER",
  "evidence_citation": "10.1093/bioinformatics/btu638",
  "original_decision": "FAIL",
  "override_decision": "PASS",
  "override_justification": "FFPE sample; duplication expected per ENCODE FFPE guidelines",
  "override_approver": "yzhang",
  "protocol_profile": "rna_seq_ffpe"
}

{
  "event_type": "parameter_decision",
  "timestamp": "2026-04-01T14:26:00Z",
  "step": "differential_expression",
  "tool": "DESeq2",
  "parameter_name": "padj_threshold",
  "value_chosen": 0.05,
  "alternatives_considered": [0.01, 0.10],
  "rationale": "Standard Benjamini-Hochberg FDR 5% per field consensus",
  "evidence_level": "GOLD",
  "evidence_citation": "10.1186/s13059-014-0550-8"
}
```

## Reviewer protocol

Reviewers receive **only**:
1. The JSONL audit trail file
2. The public dataset accession number(s)
3. A standard computing environment spec (Docker image: `biomate-eval:latest`)

Reviewers are **not** given:
- The original BioMate session
- The final output files
- Any parameter settings not captured in the audit trail

### Reviewer tasks (per analysis, ~2 hours each)

1. **Read the audit trail** — identify all QC decisions, overrides, and parameter choices
2. **Reproduce the analysis** — using accession + audit trail, run the pipeline independently
3. **Compare outputs** — record pass/fail for each output file vs BioMate original
4. **Score decision traceability** — for each QC decision, can you find the cited evidence?
5. **Time the reproduction** — how long did it take?

### Scoring rubric (per analysis)

```yaml
reproduction_score:
  exact_output_match: 0.4      # hash or tolerance match
  approximate_match: 0.2       # same conclusions, minor numerical differences
  decision_traceable: 0.3      # cited evidence found and correct
  reproduction_time_bonus: 0.1 # if completed in < 2 hours

# Example: analysis #1 RNA-seq
- analysis: 1_rnaseq_ENCSR000AED
  reviewer_1_reproduction: EXACT
  reviewer_2_reproduction: APPROXIMATE
  reviewer_3_reproduction: EXACT
  decision_traceability: 0.93   # 13/14 decisions had traceable evidence
  avg_time_hours: 1.4
  final_score: 0.88
```

## Control condition (MultiQC/nf-core)

The same 10 analyses are run through standard nf-core pipelines (without BioMate
governance). The output distributed to reviewers is:
- MultiQC HTML report
- nf-core output files
- NO decision trail, NO override records, NO parameter rationale

Expected: reviewers cannot reproduce QC decisions (no trail), resulting in
<40% reproduction rate on analyses involving non-trivial QC calls.

## Reviewer recruitment

- Target: 3 postdoc/PhD bioinformaticians (not BioMate team members)
- Compensation: $400/person (10 analyses × $40/analysis) or academic authorship
- Time commitment: 1 week
- Required skills: familiar with at least 2 of: RNA-seq, proteomics, drug discovery
- Contact: recruit through nf-core Slack, EMBL-EBI training network, or BioStars

## Files in this directory

```
audit_trail_fair/
├── README.md                    # This file
├── analyses/                    # Created after running the 10 analyses
│   ├── 01_rnaseq_ENCSR000AED/
│   │   ├── audit_trail.jsonl    # BioMate audit trail
│   │   └── outputs/             # Output files (reference)
│   └── ...
├── reviewer_protocol.md         # Detailed instructions for reviewers
├── scoring_rubric.yaml          # Formal scoring criteria
└── results/                     # Filled in by reviewers
    ├── reviewer_1/
    ├── reviewer_2/
    └── reviewer_3/
```
