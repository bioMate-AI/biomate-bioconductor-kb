# Understanding BioMate QC Output

BioMate checks quality metrics at each pipeline step and emits structured QC events in
real time. This page explains how to read QC output, what the gate levels mean, and what
to do when something fails.

---

## QC Gate Levels

Every QC threshold is tagged with one of three enforcement levels:

| Level | Meaning | Pipeline behaviour |
|---|---|---|
| **GOLD** | Mandated by ENCODE4, GATK Best Practices, or equivalent authoritative guideline. Cannot be relaxed via `qc_overrides`. | Pipeline **stops** immediately. |
| **SILVER** | Blocking threshold backed by published literature or community consensus. Can be relaxed by providing an explicit `qc_overrides` value. | Pipeline **stops** unless overridden. |
| **BRONZE** | Advisory — the metric is outside the recommended range but the data may still be usable. | Pipeline **continues**; a warning is attached to the step. |

---

## Near-Threshold Warnings

In addition to gate failures, BioMate emits advisory warnings when a metric is within
approximately 10% of a threshold — even if no gate has triggered. These appear as
`qc_warning` events (distinct from `qc_failed` events).

Example: if the ATAC-seq TSS enrichment score is 5.3 and the GOLD threshold is 5.0,
the gate passes but BioMate emits:

```
⚠️ NEAR-THRESHOLD: tss_enrichment = 5.3 (threshold: ≥5.0 GOLD) — approaching limit
```

This early warning is useful when running a pilot before committing the full cohort.

---

## Example QC Output Block

The following illustrates a typical RNA-seq run that passed with two advisories:

```
QC PASSED — 2 advisories

Step: TRIM_GALORE
  [OK] reads_surviving_pct: 87.4%  (threshold: >=70%)
  [OK] q30_pct: 91.2%              (threshold: >=75%)

Step: STAR_ALIGN
  [OK] alignment_rate: 91.2%       (threshold: >=70% SILVER)
  [OK] rrna_contamination: 2.8%    (threshold: <15%)

Step: MARKDUPLICATES
  [OK] duplication_rate: 28.3%     (threshold: <40%)

Step: FEATURECOUNTS
  [OK] assigned_reads_pct: 73.1%   (threshold: >=50%)

Step: DESEQ2_DIFFERENTIAL
  [OK] 842 significant genes (FDR < 0.05)
  [ADVISORY BRONZE] dispersion_fit_type: 'local'
      Recommended: 'parametric'. Local fitting may be less stable on small
      sample sizes. Review MA plot before interpreting results.

Step: DESEQ2_DIFFERENTIAL (sample-level)
  [ADVISORY BRONZE] sample GSM001_T3: outlier Cook's distance > 4x median
      Consider removing this sample and re-running if the result is sensitive
      to its inclusion.
```

A failed run looks like this:

```
QC FAILED — pipeline halted after STAR_ALIGN

Step: STAR_ALIGN
  [FAIL SILVER] alignment_rate: 31.4%  (threshold: >=70%)
      Possible causes:
        - Wrong genome index (species mismatch)
        - Adapter contamination not trimmed (check TRIM_GALORE stats)
        - Non-directional library mapped with --rna-strandness setting
```

---

## Domain-Specific QC Thresholds

Selected thresholds across five domains. The full table is available at
`GET /api/qc/profiles` and in the platform's QC Threshold Evidence document.

| Domain | Step / metric | Threshold | Level | Authority |
|---|---|---|---|---|
| RNA-seq | `alignment_rate` | ≥70% | SILVER | ENCODE post-2020 |
| RNA-seq | `reads_surviving_pct` | ≥70% | SILVER | nf-core/rnaseq defaults |
| RNA-seq | `assigned_reads_pct` | ≥50% | SILVER | nf-core/rnaseq defaults |
| scRNA-seq | `mito_fraction_pct` | <20% | BRONZE (advisory) | 10x Genomics Cell Ranger v7 |
| scRNA-seq | `median_genes_per_cell` | ≥500 | BRONZE (advisory) | 10x Genomics Cell Ranger v7 |
| ATAC-seq | `tss_enrichment` | ≥5.0 | GOLD | ENCODE4 ATAC-seq Standards (2022) |
| ATAC-seq | `nrf_score` | ≥0.9 | GOLD | ENCODE4 ATAC-seq Standards (2022) |
| ATAC-seq | `frip_score` | ≥0.2 | GOLD | ENCODE4 ATAC-seq Standards (2022) |
| WGS (germline) | `mean_coverage` | ≥30× | SILVER | GATK Best Practices (2023) |
| WES (clinical) | `mean_coverage` | ≥80× | SILVER | ACMG/AMP NGS Technical Standards (2016) |
| Cryo-EM SPA | `fit_quality` (CTF) | ≥0.7 | GOLD | EMDB validation; cryoSPARC v4 defaults |
| Cryo-EM SPA | `max_motion_px` | ≤50Å | SILVER | MotionCor2 best practices |
| Cryo-EM SPA | `junk_2d_fraction` | <70% | SILVER | cryoSPARC SPA pipeline defaults |
| Drug discovery | `herg_ic50_um` | >1 μM | GOLD | ICH S7B / hERG safety pharmacology |
| Drug discovery | `dili_prediction` | not "high" | GOLD | DILIrank database |
| Metagenomics (gut) | `classified_pct` | ≥50% | SILVER | HMP Consortium (2012) |

---

## QC Overrides

If you need to relax a SILVER threshold for a scientifically justified reason, pass a
`qc_overrides` dictionary when launching the workflow. In the chat interface, you can
specify this in natural language:

> "Run the RNA-seq pipeline with alignment_rate relaxed to 50% — this is FFPE-degraded
> RNA."

BioMate translates this into:

```json
{
  "qc_overrides": {
    "alignment_rate": 50.0
  }
}
```

**GOLD metrics cannot be overridden.** Attempts to override a GOLD metric (e.g.,
`tss_enrichment`, `fit_quality`) are silently ignored and a warning is recorded in the
audit log at `work_dir/qc_overrides_audit.jsonl`.

**Red-line clamping:** a small set of absolute safety bounds (e.g., `alignment_rate`
cannot be set below 5%, `mito_fraction_pct` cannot exceed 80%) are enforced regardless
of any override. If an override would cross a red line, it is clamped to the bound and
logged.

---

## Named QC Profiles

Instead of specifying individual overrides, you can select a curated profile designed
for a specific assay type. Profiles are applied at a lower precedence than explicit
`qc_overrides` — you can always add per-metric adjustments on top.

Available profiles (retrieve the full list at `GET /api/qc/profiles`):

| Profile name | Intended use |
|---|---|
| `rnaseq_polya_standard` | Standard polyA RNA-seq (platform default) |
| `rnaseq_ribodepleted` | Total RNA with RiboZero / RiboMinus depletion (relaxed alignment) |
| `rnaseq_ffpe` | FFPE-preserved tissue RNA-seq (relaxed alignment, q30) |
| `rnaseq_single_nucleus` | snRNA-seq — intronic-dominant libraries |
| `rnaseq_nonmodel_organism` | Draft genome / incomplete annotation |
| `wgs_germline_standard` | Germline WGS at 30× (GATK default) |
| `wgs_germline_lowpass` | Low-pass WGS (4×) for imputation studies |
| `wgs_somatic_tumor_only` | Tumor-only somatic calling (80× required) |
| `wes_research` | Research WES at 50× |
| `wes_clinical_germline` | Clinical-grade WES at 80× (ACMG standard) |
| `scrna_standard` | Standard 10x Chromium scRNA-seq |
| `scrna_cardiac` | Cardiac / cardiomyocyte samples (relaxed mito to 40%) |
| `scrna_neuronal` | Brain / neuronal samples (relaxed mito to 30%) |
| `scrna_perturbation` | Perturb-seq / CROP-seq screens (guide coverage + doublet gates) |
| `metagenomics_human_gut` | Human gut shotgun metagenomics |
| `metagenomics_soil` | Soil metagenomics (high dark-matter fraction) |
| `metagenomics_marine` | Marine metagenomics (TARA Oceans style) |
| `metagenomics_clinical_pathogen` | Clinical pathogen detection (CSF, blood) |
| `cryoem_spa_purified` | Standard SPA of purified soluble complexes |
| `cryoem_spa_membrane` | Membrane proteins (GPCRs, channels — relaxed motion) |
| `cryoem_spa_phase_plate` | Volta phase-plate data (relaxed CTF fit quality) |

To request a profile, include it in your query:

> "Run the RNA-seq pipeline with the `rnaseq_ffpe` profile."

Or pass it via the API:

```json
{
  "qc_profile": "rnaseq_ffpe",
  "qc_overrides": {}
}
```

---

## Exporting a QC Report

At the end of a run, click **"Export QC Report (HTML)"** on the workflow card.
The HTML report is self-contained and includes:

- Per-step pass/fail summary with threshold values and literature citations.
- Metric values plotted against thresholds (bar charts with pass/fail colouring).
- The `qc_profile` used, any explicit `qc_overrides`, and the override audit trail.
- Software versions and Nextflow process identifiers for reproducibility.

Via the API:

```
POST /api/export/qc_report
{
  "invocation_id": "<workflow-invocation-id>"
}
```

---

## What to Do When QC Fails

### Pipeline stopped at a SILVER gate

1. **Read the failure message.** BioMate includes a "Possible causes" list for every
   known failure mode.
2. **Check upstream steps.** A low alignment rate often originates from a trimming
   problem visible in FASTQC / Trim Galore stats.
3. **Relax the threshold (if justified).** If your sample type genuinely requires a
   different threshold, select the appropriate named profile or provide an explicit
   override with a scientific justification.
4. **Re-run from the failed step.** Use the "Resume" button on the workflow card. Nextflow
   resumes from the cached last successful step — you do not need to start from scratch.

### Pipeline stopped at a GOLD gate

GOLD gates represent hard scientific limits. Common examples:

- **Cryo-EM CTF fit quality < 0.7:** The micrographs are too thick, too tilted, or the
  defocus range is outside the estimation window. Collect new data or pre-screen
  micrographs manually.
- **ATAC-seq TSS enrichment < 5.0:** The ATAC library has failed — likely chromatin
  accessibility was not preserved during nuclei isolation. The data should not be
  analysed further.
- **hERG IC50 ≤ 1 μM (drug discovery):** The compound poses a cardiac safety risk.
  Medicinal chemistry optimisation is required before further in vitro / in vivo testing.

GOLD failures cannot be overridden. If you believe the gate is incorrect for your assay
context, contact your platform administrator to initiate a threshold review (which
requires a new evidence citation and a code review).

### Advisory warnings only (pipeline completed)

BRONZE advisories do not stop the pipeline, but they should be reviewed before
publication. Each advisory includes a recommended action — for example, removing an
outlier sample, switching a DESeq2 fitting mode, or inspecting a 2D class average for
junk particles.
