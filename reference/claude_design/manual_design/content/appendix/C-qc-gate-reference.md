# Appendix C — QC Gate Reference (Thresholds with Citations)

Every QC gate BioMate applies has a **cited threshold** and a **verdict** (PASS / ADVISORY / HALT).
This appendix compiles the gates documented in the domain chapters and pins each threshold to its source.

> **Primary source of truth:** `backend/config/qc_evidence.yaml` — a provenance ledger that records, per
> gate, the paper/guidance the threshold is anchored on and an **evidence tier**. The domain chapters'
> verified gates are cross-checked against it. Where a threshold is *code-enforced*, the enforcing file
> is `backend/lib/galaxy/jobs/qc_trace_monitor.py` (or the ADMET `qc_evaluator.py`), as noted per row.

## Evidence tiers (from `qc_evidence.yaml`)

- **GOLD** — the threshold is stated in the cited paper/guidance verbatim.
- **SILVER** — a community convention attributed to the paper; the paper supports the underlying
  method/metric but does not state the exact cutoff.
- **BRONZE** — an operational heuristic with no peer-reviewed anchor (cited reference is context only).
- **GOLD-metric / SILVER-tier** — a common hybrid: the **metric** is gold-standard (verbatim in the
  paper) but the numeric **pass/fail cutoff** is operational/community. Marked as such below.

## Verdict semantics

- **HALT** — stops the run at that gate (ADMET also triggers auto-loop remediation). A hard threshold.
- **ADVISORY** — flagged in the report, run continues. A concern, not a stop.
- **PASS** — the metric met its threshold.

---

## Drug discovery — ADMET

Enforced in `backend/experiments/admet_autoloop/qc_evaluator.py`. Thresholds shift by QC profile
(`admet_standard` / `admet_cns` / `admet_oncology`).

| Gate | Threshold / verdict | Tier | Source |
|---|---|---|---|
| **hERG** | HALT if IC50 ≤ 10 µM (`admet_standard`) | **GOLD-metric / SILVER-tier** | Redfern et al. Cardiovasc Res 2003 (10.1016/S0008-6363(02)00846-5); 10 µM floor is Bowes 2012 industry convention (10.1038/nrd3845); ICH S7B requires the assay but states **no** numeric IC50 cutoff |
| **DILI** | HALT if probability > 0.5 (operational midpoint) OR risk > medium | **SILVER** | Lammert et al. Hepatology 2010 (10.1002/hep.23317) — logP + daily-dose as risk drivers; no guideline mandates the screen |
| **Ames** | HALT if probability > 0.5 or any toxicophore alert | **SILVER** (Kazius alert set **GOLD**; 0.5 threshold operational) | Kazius et al. J Med Chem 2005 (10.1021/jm040835a); ICH S2(R1) genotoxicity |
| **Rule of Five (Ro5)** | ADVISORY only (never HALT) on > 1 violation; logP > 5 / MW > 500 | **GOLD** (Ro5 as heuristic; advisory-only is correct — no guideline mandates Ro5) | Lipinski et al. Adv Drug Deliv Rev 1997 (10.1016/S0169-409X(96)00423-1) |
| **CYP DDI (R1)** | HALT if R1 ≥ 1.1; ADVISORY 1.02 ≤ R1 < 1.1 | **GOLD** (verbatim FDA threshold) | FDA In Vitro DDI Guidance 2020 |
| **CYP DDI (R2)** | HALT if R2 ≤ 0.71; ADVISORY 0.71 < R2 ≤ 0.79 | **GOLD** (verbatim FDA threshold) | FDA In Vitro DDI Guidance 2020 |

**Remediation (auto-loop):** on HALT, BioMate tightens *screening thresholds* (e.g. `logp_max`,
`mw_max_da`, `ames_strict`) with a was→now diff and re-runs (≤ 2 retries, then escalate). It does **not**
generate analogues (see Domain: Drug discovery → IND, and Appendix E).

## Pharmacology / PK

| Gate | Threshold / verdict | Tier | Source |
|---|---|---|---|
| **NCA AUC extrapolation** | ADVISORY / FAIL by context (default healthy: advisory ≥ 20%, FAIL ≥ 30%; oncology 30/50; etc.) | **GOLD-metric / SILVER-tier** | FDA bioavailability/bioequivalence guidance (fda.gov/media/70958) — 20% metric gold; per-population tiers operational |
| **Allometric scaling** | R² gate ≥ 0.85 for cross-species fit | operational (see Domain chapter) | HED exponent 0.33 is **GOLD** (FDA 2005, fda.gov/media/72309); R² floor operational |
| **PBPK mass balance / model checks** | ADVISORY on mass-balance violation | **SILVER** | EMA PBPK reporting guideline |

## Structural biology — AlphaFold / prediction

| Gate | Threshold / verdict | Tier | Source |
|---|---|---|---|
| **pLDDT** | Metric is AlphaFold per-residue confidence (0–100); confident ≈ > 70 | **GOLD** (metric) | Jumper et al. Nature 2021 (10.1038/s41586-021-03819-2) |
| **Confident fraction** | ADVISORY if fraction of residues with pLDDT > 70 is below 0.70 | **SILVER** (cutoff operational) | Tunyasuvunakool et al. Nature 2021 (10.1038/s41586-021-03828-1) |
| **PAE** | ADVISORY if PAE > 8 Å (skipped for single-domain proteins) | **SILVER** (cutoff operational) | Tunyasuvunakool et al. Nature 2021 (10.1038/s41586-021-03828-1) |
| **Docking binding score** | ADVISORY if binding_score > −7 kcal/mol | community heuristic | Trott & Olson (AutoDock Vina), 10.1002/jcc.21334 |

## Transcriptomics — bulk RNA-seq

Metrics enforced in `qc_trace_monitor.py`; anchors in `qc_evidence.yaml` (`bioc_alignment_mapping_qc`).

| Gate | Threshold / verdict | Tier | Source / note |
|---|---|---|---|
| **STAR uniquely-mapped rate** | PASS > 70% · ADVISORY 50–70% · FAIL < 50% — **code-enforced** (default 70.0) | **SILVER** (metric gold, 70% is ENCODE community floor) | ENCODE RNA-seq standards; `qc_trace_monitor.py:4589` |
| **Salmon mapping rate** | **code default 50%** (tutorial spec says 70%) | **SILVER** | `qc_trace_monitor.py:4625`; the manual states the **enforced 50%** and treats 70% as an interpretive target — see Appendix E |
| **DESeq2 sample-distance clustering** | **VISUAL / ADVISORY only** — the plot is produced; there is **no** automated 2-cluster pass check | n/a (diagnostic) | no gate in `qc_trace_monitor.py`; do not present as an enforced gate |

> There is **no** bulk-RNA auto-loop: QC fails are surfaced for a manual metadata/reference fix and
> re-run (only ADMET has auto-remediation).

## Single-cell RNA-seq

| Gate | Threshold / verdict | Tier | Source / note |
|---|---|---|---|
| **Mitochondrial fraction (pct_mito)** | PASS if pct_mito < 10% (most tissues); < 20% tolerated for brain/liver | **GOLD-metric / SILVER-tier** | Luecken & Theis Mol Syst Biol 2019 (10.15252/msb.20188746). **Code note:** the pipeline `.nf` default is `max_pct_mito = 20%`; the manual documents the code truth (20%) with a 10% interpretive tip (see Domain: Single-cell) |
| **n_features (genes/cell)** | PASS > 200 (floor); n_counts > 500 | **SILVER** (floor operational) | Luecken & Theis 2019 |

## Variant calling (germline)

Code-enforced in `qc_trace_monitor.py`.

| Gate | Threshold / verdict | Tier | Source / note |
|---|---|---|---|
| **Mapped fraction** | PASS ≥ 70% — code-enforced | **SILVER** | BWA-MEM (Li 2009, 10.1093/bioinformatics/btp324); `qc_trace_monitor.py:4640` |
| **Duplication rate** | PASS ≤ 40% (profile-overridable) — code-enforced | operational | `qc_trace_monitor.py:4649` |
| **Coverage / depth** | PASS ≥ 30× (WGS) / ≥ 50× (WES) — code-enforced | **GOLD-metric / SILVER-tier** | Strelka2 (Kim et al. Nat Methods 2018, 10.1038/s41592-018-0051-x) reports 30× as standard depth; GATK best-practice depth floors; `qc_trace_monitor.py:4773–4790` |
| **Ts/Tv ratio (1.8–2.2)** | **in-pipeline ADVISORY**, not an enforced gate | community | reported via MultiQC; do **not** present as a HALT |

> Somatic (Mutect2 tumour-normal) variant calling has **no** documented QC chain or gold demo — see
> Appendix E. Hard-filter (not VQSR) is the single-sample default.

## Cryo-EM

Enforced in `qc_trace_monitor.py` (41–45) / ADMET-shared `qc_evaluator.py:77`; anchors in
`qc_evidence.yaml` (`cryo_em_fsc_resolution`, `cryo_em_ctf`).

| Gate | Threshold / verdict | Tier | Source |
|---|---|---|---|
| **FSC 0.143 resolution** | PASS ≤ 4 Å (publication-quality) · ADVISORY 4–8 Å · FAIL > 15 Å | **metric GOLD, cutoffs SILVER** | Rosenthal & Henderson J Mol Biol 2003 (10.1016/j.jmb.2003.07.013) defines the FSC 0.143 **metric** verbatim; the Å cutoffs are operational |
| **CTF fit quality** | PASS ≥ 0.70; 0.5 red-line | **SILVER** | Punjani et al. (CryoSPARC) Nat Methods 2017 (10.1038/nmeth.4169) |

> **Note (see Domain: Cryo-EM):** older tutorial prose cited MotionCor2/Topaz/DeepEMhancer, CTF > 0.2,
> GSFSC < 3.5 Å, hetero-refine — that does **not** match the CryoSPARC-native production pipeline. The
> code truth (≥ 0.70 CTF, ≤ 4 Å FSC, no hetero-refine) is authoritative.

---

## How to read a gate in a report

1. **Verdict first** — PASS / ADVISORY / HALT tells you whether the run stopped or continued.
2. **Two numbers** — measured value vs threshold (shown side by side; colored).
3. **Tier tells you how hard the line is** — GOLD = a real regulatory/paper line; SILVER/BRONZE = a
   sensible operational default you may adjust with a QC profile.
4. **A HALT is not "your data is bad"** — for ADMET it means auto-loop tightened the filter; for RNA-seq
   it means fix metadata/reference and re-run. See Appendix D.

---
*Cross-references: per-domain "QC gates & how to read them" sections; Appendix E for gates/paths not yet
enforced (somatic, cryo autoloop, etc.).*
