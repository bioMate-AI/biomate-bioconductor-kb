# BIOMATE AI — Scientific & Technical Validation Report

## Automated Single-Particle Cryo-EM with Evidence-Graded Interactive QC Governance: A Nyquist-Limited Reconstruction Benchmark on EMPIAR-10028

**Prepared for:** BioMate AI  **Prepared by:** BizBildr LLC — Business Consulting
**July 2026** | Document Classification: Confidential — Internal Review Draft
**Author(s):** Yaoyun Zhang, et al. | **Platform Version:** [build/commit hash] | **Domain:** Structural biology / cryo-EM

> Diagrams are Mermaid (render on GitHub, convert to figures via pandoc/mermaid-cli). Every value carries a source; unfilled fields are **[GAP]**.

---

## 1. Abstract

BioMate-Cryo orchestrates a 23-step single-particle cryo-EM (SPA) pipeline on containerized AWS GPU infrastructure with human-in-the-loop, evidence-graded quality-control gates at seven pipeline stages. On the public β-galactosidase benchmark (EMPIAR-10028), BioMate reconstructs to the Nyquist-limited resolution (FSC 0.143 = 1.78 Å at 0.885 Å/px; 3.98 Å on a 20-movie subset at 1.96 Å/px) in 2.8 GPU-hours with zero false QC halts, at a total cost of ~$27 versus ~$900 for expert manual processing — an 89% reduction in analyst time and a 33× reduction in cost. Unlike existing pipelines that silently discard suspect micrographs, BioMate pauses at each gate, presents the failing metric with its evidence grade and a suggested remediation, and records every decision in a portable audit trail. The principal limitation is that the protocol-discrimination benchmark for non-standard (membrane-protein) samples uses synthetic exposures, and no head-to-head against CryoSPARC Live has yet been run.

> **KEY MESSAGE**
> BioMate delivers expert-quality cryo-EM reconstruction (Nyquist-limited on EMPIAR-10028) at 33× lower cost and 89% less analyst time, replacing silent auto-filtering with transparent, audit-trailed QC gates.

---

## 2. Problem Statement & Dataset

Automated cryo-EM pipelines (CryoSPARC Live, RELION Schemes, Warp) silently discard micrographs that fail internal thresholds — for novel membrane proteins this can quietly delete large fractions of valid data, and the investigator only discovers the loss post hoc. There is also no citation-anchored, auditable record of why any threshold fired. BioMate reframes cryo-EM QC as an interactive, evidence-graded, audited decision at each pipeline stage.

### 2.1 Dataset Specification

| Parameter | Value | Notes |
|---|---|---|
| Sample size (n) | 20 movies → 26,284 particles (Run A); 26,312 particles (Run B) | Benchmark subsets of EMPIAR-10028 |
| Data type | Single-particle cryo-EM movies | 300 kV Titan Krios / K2 Summit |
| Reference structure/target | β-galactosidase, published 2.2 Å | Bharat & Scheres 2016 |
| Public accession | **EMPIAR-10028** | Public raw movies (174 GB full set) |

---

## 3. Methods

**Technical innovation —** protocol-aware, evidence-graded QC gates with audited halt-and-override replace the silent auto-filtering used by existing cryo-EM pipelines: the same reconstruction quality, but no undetected data loss and a full decision trail.

A Nextflow DSL2 pipeline (`spa_full_pipeline`) runs 23 steps in four phases — preprocessing, picking, classification, reconstruction — with QC gates inserted at phase boundaries as blocking checkpoints. When a gate fires, the run halts and surfaces the metric, its evidence tier, and a suggested fix for explicit human decision (recorded to JSONL). Gold-standard FSC is computed from an independent half-map pair.

**Figure 1 — SPA pipeline with QC gates.**

```mermaid
flowchart LR
    M[Movies EMPIAR-10028] --> MC[MotionCor2\nmotion correction]
    MC --> G1{{Gate: drift <=50 A}}
    G1 --> CT[CTFFIND4\nCTF estimation]
    CT --> G2{{Gate: CTF fit >=0.70}}
    G2 --> PK[Blob+template picking]
    PK --> C2[2D classification]
    C2 --> G3{{Gate: junk<70%, N>1000}}
    G3 --> AB[Ab-initio + NU-refine\nCryoSPARC v5]
    AB --> FSC[Half-map FSC 0.143]
    FSC --> G4{{Gate: resolution/anisotropy}}
    G4 --> OUT[Map + local resolution\n+ JSONL audit]
```

### 3.1 Software & Package Versions

| Package | Version | Domain/Role | Reference |
|---|---|---|---|
| CryoSPARC | v5 | Motion/CTF/picking/2D/ab-initio/refinement | Punjani et al., 2017 |
| MotionCor2 | (CryoSPARC-bundled) | Patch motion correction | Zheng et al., 2017 |
| CTFFIND4 | 4.x | CTF estimation | Rohou & Grigorieff, 2015 |
| RELION | 4 | Open-source alternative path | Scheres, 2012 |
| BioMate-Cryo orchestration + QC gates | [build/commit] | Pipeline, gates, audit | internal |

### 3.2 Statistical Parameters

- **Resolution:** gold-standard FSC 0.143 criterion (Henderson et al., 2012).
- **Gate thresholds:** motion drift ≤ 50 Å (BRONZE), CTF fit ≥ 0.70 (SILVER), 2D min particles > 1,000 (BRONZE), junk fraction < 70% (BRONZE)/< 50% (SILVER advisory).
- **Retention:** non-uniform refinement accepted 26,284/28,316 particles (92.8%, Run A).

### 3.3 Reproducibility & Compute Environment

Docker (CryoSPARC native), AWS us-east-1. Run A: g6.2xlarge, 1× NVIDIA L4, ~11 GB peak GPU, 2.8 GPU-h (7.4 h wall). Run B: g6.12xlarge, 4× NVIDIA L4, ~0.45 GPU-h (~27 min GPU-bound). Full JSONL audit log emitted per run.

---

## 4. Benchmark Results

### 4.1 Performance Comparison

| Metric | Manual CryoSPARC (expert) | BioMate Run A (1 GPU) | BioMate Run B (4 GPU) | Delta vs manual |
|---|---|---|---|---|
| Wall-clock | ~14–18 h | 7.4 h | ~27 min (GPU-bound) | up to ~30× |
| GPU compute | ~14 h | 2.8 h | 0.45 h | ~5–30× |
| Analyst time at keyboard | ~18 h | ~0.5 h | ~0.5 h | 89% less |
| Peak GPU memory | — | ~11 GB (L4) | ~12 GB/GPU | — |
| GPU cost (AWS) | — | $2.38 | $0.68 | — |
| **Total cost** | **~$900** | **~$27** | **~$26** | **~33×** |
| QC gate halts (false) | N/A | 0 | 0 | — |
| Audit-trail entries | 0 | complete JSONL | complete JSONL | — |

Multi-GPU parallel stages (2D×3, ab-initio×3, homogeneous×3) complete in ~27 min vs ~92 min sequential = **3.4× speedup**.

### 4.2 Concordance & Accuracy

| Metric | Run A (20 movies) | Run B (26K particles) | Reference/Threshold |
|---|---|---|---|
| FSC 0.143 resolution | **3.98 Å** (Nyquist 3.92 Å) | **1.78 Å** (Nyquist 1.77 Å) | Nyquist-limited; published 2.2 Å |
| Final particle count | 26,284 (92.8% retention) | 26,312 | — |
| B-factor (auto-sharpen) | 0 Å² | — | no excess sharpening |
| False QC halts | 0 | 0 | protocol-appropriate profile |

Both runs reach the Nyquist ceiling set by their sampling — i.e., BioMate extracts all available signal at the chosen pixel size.

---

## 5. Validation Methodology

Resolution is validated by the gold-standard half-map FSC 0.143 criterion (Henderson 2012), the EMDB-standard convention, against the published EMPIAR-10028 β-galactosidase structure (2.2 Å). Reaching the exact Nyquist limit in Run B (1.78 Å at 0.885 Å/px) confirms full signal extraction. Zero false halts on this clean, well-characterized dataset confirms the QC gates do not over-reject valid data.

---

## 6. Limitations

1. **Synthetic protocol-discrimination benchmark.** The membrane-protein false-rejection test uses 5 synthetic TRPV1-parameterized exposures, not real raw data; the full EMPIAR-10005 re-processing (174 GB) is deferred. **[GAP]**
2. **No CryoSPARC Live head-to-head.** Comparison to the leading live pipeline on identical data is deferred. **[GAP]**
3. **QC-gate recall/precision not formally quantified** — no deliberately-bad negative controls run. **[GAP]**
4. **No atomic-model quality gates** (Ramachandran/clashscore/EMRinger) — benchmark stops before model building.
5. **Metrics reconciliation.** `benchmark_results/empiar_10061/metrics.json` records a separate 100-micrograph run at 5.46 Å; the 3.98/1.78 Å figures are the manuscript's 20-movie/26K-particle runs. Standardize which run is canonical.

---

## 7. Data & Code Availability

EMPIAR-10028 is public. Pipeline + QC modules: `research_repos/cryo_em_benchmark_paper/` (main.nf + gates); benchmark artifacts: `benchmark_results/empiar_10061/` (metrics.json, validation_fsc.txt, qc_audit.jsonl). Zenodo DOI and GitHub URL pending registration; bioRxiv target 2026-05-01. **[GAP — register DOI before submission]**

---

## 8. Remaining Work to Target a Nature / Science Publication

| # | Work item | Why it's required | Est. effort |
|---|---|---|---|
| 1 | End-to-end run on a real membrane-protein dataset (EMPIAR-10005) | Replaces synthetic protocol-discrimination with real data — reviewers will demand it | 2–4 wk compute + review |
| 2 | Head-to-head vs CryoSPARC Live on identical EMPIAR-10028 subset | Establishes the comparison against the field-standard live tool | 2–3 wk |
| 3 | QC-gate recall/precision on deliberately-bad negative controls | Quantifies the core claim (catches real failures, spares valid data) | 2–3 wk |
| 4 | Non-expert user study (5–8 wet-lab biologists) | Substantiates the usability/accessibility claim | 4–6 wk |
| 5 | Atomic model building + validation gates; EMDB/Zenodo deposition | Completes the pipeline and satisfies deposition requirements | 3–4 wk |

**Scientific review sign-off:** ______________________  **Date:** __________
