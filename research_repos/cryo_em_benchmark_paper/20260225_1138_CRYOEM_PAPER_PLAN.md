# Cryo-EM Paper Plan: Interactive QC Governance for Automated Cryo-EM SPA
**Date:** 2026-02-25 11:38 (updated 2026-02-25 after competitive survey)
**Target journal:** Nature Methods or Nature Communications
**Status:** Pipeline implemented (23-step CryoSPARC SPA in Nextflow DSL2); QC gates implemented; benchmark data needed
**Folder:** `research_repos/cryo_em_benchmark_paper/`

---

## Competitive Landscape (Surveyed 2026-02-25)

The landscape is more complex than assumed. A precise understanding is required to avoid overclaiming.

| Tool | Real-time monitoring | Threshold-based data exclusion | Interactive halt + human decision | Protocol-aware profiles | Failure-time parameter suggestions | Evidence-graded override governance |
|---|---|---|---|---|---|---|
| **CryoSPARC Live** | ✅ (per-exposure) | ✅ (auto-exclude bad exposures) | ❌ (continues silently) | ❌ (instrument profiles only) | ❌ | ❌ |
| **RELION Schemes** | ✅ (CTF-based filter) | ✅ (single global CTF filter) | ❌ (continues automatically) | ❌ | ❌ | ❌ |
| **Scipion monitors** | ✅ (CTF, drift, resources) | ❌ (alerts only) | ❌ | ❌ | ❌ | ❌ |
| **TranSPHIRE** | ✅ (continuous) | ✅ (feedback re-training) | ❌ | ❌ | ❌ | ❌ |
| **Warp** | ✅ (real-time) | ✅ (confidence threshold) | ❌ | ❌ | ❌ | ❌ |
| **cryoAssess** | ❌ (post-hoc) | ✅ (ML classifier) | ❌ | ❌ | ❌ | ❌ |
| **BioMate** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

**Key finding on CryoSPARC Live:** It performs *threshold-based exposure exclusion* (silently marks bad micrographs as "rejected" and continues processing), but does NOT halt pipeline execution or present a decision to a human operator. The "Auto-Pause" in v5.0 is triggered by absence of new data, not by quality failure. This distinction — automatic silent filtering vs. interactive human-supervised halt — is BioMate's genuine differentiator.

**Key finding on nf-core:** As of February 2026, there is **no nf-core cryo-EM SPA pipeline** (not "crispy," not any other name). The previous paper draft's claim that "nf-core/crispy wraps RELION but has no QC governance" is false. Remove all references to nf-core/crispy.

---

## Our Contribution and Innovation — Stated Clearly

### What exists today (the problem)
CryoSPARC Live, RELION Schemes, TranSPHIRE, and Warp all provide real-time data monitoring and threshold-based filtering — this is well-established. What they share is a critical design limitation: **filtering is automatic and non-interactive**. Bad exposures are silently excluded; the pipeline continues. There is no mechanism for a human to review the failure, understand its cause, decide whether to override, and proceed with explicit documented approval.

The result: silent data loss. Investigators discover rejected data only in post-hoc logs, with no explanation of what failed or how to fix it. For novel samples — new membrane proteins, flexible complexes, low-contrast particles — automatic threshold exclusion can silently discard an entire viable dataset because standard thresholds were applied to non-standard biology.

Three additional gaps no existing tool addresses:
- **Protocol blindness:** All tools apply one set of thresholds regardless of sample biology. Membrane proteins exhibit 30–60% more beam-induced motion than soluble proteins. Applying purified-protein drift thresholds to membrane protein data produces systematic false-positive rejections.
- **No actionable diagnostics:** When a threshold is exceeded, every existing tool reports the metric value. None explain *why* it failed or propose a specific parameter change. The investigator must diagnose the root cause manually.
- **No evidence provenance:** Threshold values in CryoSPARC Live, RELION, and Warp are either user-defined (arbitrary) or tool defaults with no citation. There is no way to know whether a threshold reflects published community consensus, instrument specification, or developer intuition.

### What BioMate adds (the innovation)

**Innovation 1: Interactive human-in-the-loop QC gate — the missing link between monitoring and governance**

BioMate intercepts at each of the 23 SPA steps and applies governance-layer thresholds *before* committing to the next step. When a threshold is exceeded, BioMate:
1. **Halts** downstream step execution (the pipeline does not continue automatically)
2. **Emits an SSE event** with the failing metric, threshold, evidence level, and suggested parameters
3. **Awaits an explicit human decision**: Override (with justification logged), Retry with suggested parameters, or Abort
4. **Records the decision** in a portable JSONL audit trail with timestamp, evidence level, and approver

This is categorically different from CryoSPARC Live's silent exclusion and RELION Schemes' automatic branching. The interactivity is the differentiator: the investigator sees *exactly* what failed, *why*, *what the evidence level is*, and *what to do about it* — before compute is spent on downstream steps.

Specifically:
- **Motion correction gate:** total_drift_angstrom < 50Å (BRONZE, community practice); per-frame drift < 5Å (BRONZE)
- **CTF gate:** fit_quality > 0.7 (SILVER, CTFFIND4 documentation); defocus in range 1,000–100,000Å (hard gate); astigmatism advisory at > 1,000Å (BRONZE)
- **Particle picking gate:** particles_picked > 1,000 (BRONZE, minimum for 2D classification)
- **FSC 0.143 gate (to build):** final resolution reported at gold-standard FSC criterion (GOLD, Henderson et al. 2012)

**Innovation 2: Protocol-aware named profiles for cryo-EM sample types**

Different sample types require different QC thresholds — and no existing tool implements this:
- `cryoem_spa_purified`: default thresholds (soluble, purified protein)
- `cryoem_spa_membrane`: total_drift relaxed to 80Å (membrane proteins exhibit more beam-induced motion due to lipid bilayer flexibility); fit_quality relaxed to 0.65
- `cryoem_tomo_in_situ`: total_drift to 150Å, fit_quality to 0.5, correlation_score to 0.3

CryoSPARC Live's "Configuration Profiles" save microscope hardware parameters (pixel size, voltage, Cs) — these are **instrument profiles**, not sample-biology-aware protocols. There are no named profiles with biology-specific threshold adjustments in any existing tool. The analogy: this is exactly what RNA-seq needs `rnaseq_ffpe` profiles for FFPE tissue — the biology changes what "good" looks like.

**Innovation 3: Failure-time actionable parameter suggestions**

When a gate fires, BioMate does not just halt — it proposes specific parameter changes:
- High drift → "Enable dose weighting; reduce frames per exposure; check gain reference"
- Bad CTF fit → "Widen defocus search range; verify pixel size; inspect for beam damage"
- Defocus below valid range → "Consider collecting at 1.0–3.0 μm underfocus; widen CTF search range minimum"
- Low particle count → "Lower picker threshold; increase box size; check micrograph contrast"

No existing cryo-EM tool (CryoSPARC Live, RELION, Scipion, TranSPHIRE, Warp) generates machine-authored remediation text at failure time. This was confirmed by survey of all major tools.

**Innovation 4: Evidence-graded threshold governance**

BioMate classifies every threshold by evidence quality:
- **GOLD**: published consensus (Henderson FSC 0.143 criterion, 2012) — cannot be silently overridden
- **SILVER**: method-specific best practice (CTFFIND4 fit_quality > 0.7) — requires logged justification to override
- **BRONZE**: community heuristic (drift < 50Å) — can be overridden silently with audit log entry

CryoSPARC Live thresholds are user-defined with no citation provenance. RELION Schemes has a single global CTF filter with no evidence tier. The GOLD/SILVER/BRONZE concept does not exist in any cryo-EM tool.

**Innovation 5: Quantified time and cost savings via pilot-then-full execution**

BioMate's pilot execution model runs a 5-micrograph subset first, applies all QC gates, and surfaces failures before the full dataset is processed. For a typical 1,000-micrograph SPA dataset:
- Failure caught at motion correction: saves ~8 GPU-hours (2D classification + refinement avoided)
- Failure caught at CTF: saves ~6 GPU-hours
- Failure caught at particle picking: saves ~4 GPU-hours

We will quantify these savings on EMPIAR benchmark datasets.

---

## The 23-Step Pipeline (Implemented)

```
1.  Import Movies
2.  Patch Motion Correction        ← QC gate: drift
3.  Patch CTF Estimation           ← QC gate: fit quality, defocus range
4.  Micrograph Denoiser
5.  Blob Particle Picker (R1)      ← QC gate: particle count
6.  Junk 2D Detector
7.  Inspect Particle Picks
8.  Extract Particles (R1)
9.  2D Classification (R1)
10. Select 2D Classes (R1)
11. Template Picker (R2)           ← QC gate: particle count (R2)
12. Inspect Particle Picks (R2)
13. Extract Particles (R2)
14. 2D Classification (R2)
15. Select 2D Classes (R2)
16. Ab-Initio Reconstruction
17. Homogeneous Refinement
18. Volume Tools (Filter/Mask)
19. Validation FSC                 ← QC gate: FSC 0.143 (to build)
20. Local CTF Refinement
21. Non-Uniform Refinement
22. Local Resolution Estimation
23. Post-Processing (Sharpening)
```

---

## Benchmark Design

### Dataset 1: β-galactosidase (EMPIAR-10061) — the gold standard true negative
- Resolution target: 2.2Å (published, achievable with standard parameters)
- Role: Show BioMate reaches same resolution as manual processing, no false positive gates
- Expected: All QC gates pass, full pipeline completes

### Dataset 2: TRPV1 ion channel (EMPIAR-10005) — membrane protein
- Resolution target: 3.4Å (Liao et al. 2013, Nature)
- Role: Show `cryoem_spa_membrane` profile is necessary; default profile would false-positive on drift
- Expected: Default profile fires motion correction gate; membrane profile passes

### Dataset 3: A known low-quality dataset (EMPIAR — to identify)
- Role: True positive — BioMate correctly halts a dataset with genuinely bad CTF or motion
- Criterion: Find an EMPIAR entry where the depositor notes processing difficulty
- Candidate: EMPIAR-10017 (β-galactosidase with known stage drift issues)
- Expected: QC gate fires at motion correction or CTF; suggests specific parameter changes

### Dataset 4: Ribosome (EMPIAR-10028, T20S proteasome) — large, well-behaved
- Resolution target: Sub-3Å
- Role: High particle count dataset; tests scalability of QC governance at > 100,000 particles
- Expected: All gates pass; demonstrates pipeline at scale

### Comparison
- **Comparator A:** Manual CryoSPARC GUI processing by an experienced operator (same datasets) — represents current expert workflow
- **Comparator B:** CryoSPARC Live (threshold-based exclusion, no interactive halt) — represents current best automated filtering
- **Comparator C:** RELION 4 on-the-fly + Schemes (single global CTF filter) — represents open-source automation without QC governance
- **Key differentiating experiment (vs. CryoSPARC Live):** Run a difficult dataset through both. CryoSPARC Live silently excludes data; BioMate halts, proposes specific parameter changes, allows override with audit log, then succeeds. Show that CryoSPARC Live-filtered result loses valid micrographs; BioMate with override retains them.
- **Metrics:** Final resolution (FSC 0.143), total wall time, GPU hours consumed, number of manual interventions required, valid micrographs retained, audit trail completeness

---

## What a Nature Methods Reviewer Will Require

| Evidence | Status | Notes |
|---|---|---|
| FSC 0.143 final resolution matches manual processing | ❌ Not yet | Requires benchmark runs on EMPIAR-10061 |
| QC gates fire correctly on known-bad data | Partial | Motion/CTF implemented; FSC gate missing |
| Time/cost saving quantification | ❌ Not yet | Pilot experiment needed |
| Membrane protein profile validation | ❌ Not yet | Requires EMPIAR-10005 run |
| **Comparison to CryoSPARC Live** (primary competitor) | ❌ Not yet | Show what happens when TRPV1 goes through both — CryoSPARC Live silently rejects good micrographs; BioMate halts, user overrides with justification, retains data |
| Comparison to RELION 4 Schemes | ❌ Not yet | Open-source automation without QC governance |
| User study (non-expert runs pipeline successfully) | ❌ Not yet | 5–10 sessions needed |
| Protocol-aware profile validation | ❌ Not yet | Purified vs membrane comparison |
| Audit trail demonstration (EMDB-compatible JSONL) | ❌ Not yet | Show decision log from a real benchmark run |

---

## Missing Pieces to Build Before Submission

| Gap | Effort | Priority |
|---|---|---|
| FSC 0.143 gate (parse half-map FSC from CryoSPARC JSON output) | 1 day | **P0** |
| 2D classification rejection rate gate (junk class fraction > 50%) | 1 day | P1 |
| Ice thickness proxy gate (mean micrograph intensity) | 0.5 day | P1 |
| Preferred orientation detection (orientation distribution chi-square) | 2 days | P1 |
| B-factor / Guinier plot gate | 1 day | P2 |
| Phase plate CTF fitting support | 2 days | P2 |

---

## Co-Authors Needed

| Role | Why |
|---|---|
| Structural biologist (active cryo-EM lab) | Validates threshold choices; provides real unpublished datasets as benchmark; Nature Methods credibility |
| CryoSPARC / RELION developer | Ideal co-author for credibility; confirms QC metric definitions |
| Biophysics / membrane protein expert | Validates membrane protein profile thresholds |

---

## Target Journal Decision Tree

- If final resolution matches manual (within 0.2Å): **Nature Methods**
- If significant time/cost savings demonstrated on large dataset: **Nature Methods**
- If FSC matches but no clear methodological advance beyond automation: **Nature Communications** (still high-impact)
- Fallback: **Journal of Structural Biology** (Elsevier, the field's primary methods journal)

---

## Immediate Next Steps

1. Add FSC 0.143 gate to `qc_trace_monitor.py` — 1 day (P0 for this paper AND Paper 1)
2. Run EMPIAR-10061 through the full 23-step pipeline on AWS — establish baseline
3. Run EMPIAR-10005 with default profile vs membrane profile — demonstrate false-positive elimination
4. Contact a structural biology lab for co-authorship and real dataset contribution
