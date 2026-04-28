# Auto-Loop Knowledge Audit — What Is Actually Supported
**Date:** 2026-04-16  
**Scope:** `cryo_em_autoloop_ux/knowledge_base.py` — every gate threshold and remediation action  
**Sources checked:** BioMate skill docs (`docs/cryo_em_skills/`), CryoSPARC official guide, CryoSPARC discuss forum  

---

## Methodology

Three source tiers were checked in this order:

1. **BioMate skill docs** (`docs/cryo_em_skills/00–08`) — extracted Methods sections from 8 published structural biology papers, written by BioMate team. Each entry states the file path and verbatim line(s) used.
2. **CryoSPARC official guide** (`guide.cryosparc.com`) — parameter descriptions, defaults, and guidance for Patch CTF Estimation, Patch Motion Correction, and Blob Picker. Fetched live.
3. **CryoSPARC discuss forum** (`discuss.cryosparc.com`) — practitioner troubleshooting threads. Searched and fetched live.

Each gate is labelled: ✅ **REAL TEXT FOUND** / ⚠️ **PARTIAL** / ❌ **NOT FOUND IN ANY SOURCE**.

---

## Gate-by-Gate Audit

### Gate: `motion_drift` — Total drift < 50 Å

**Rating: ✅ STRONGLY SUPPORTED — 3 independent lab protocols say the same number.**

| Source | File | Verbatim text |
|--------|------|--------------|
| VMAT2 Nature 2023 | `02_VMAT2_nature2023.md:199` | `"Micrograph QC: Motion (total): < 50 Å"` |
| μOR Cell 2022 | `05_muOR_cell2022.md:215` | `"Motion: < 50 Å total"` |
| General Framework | `00_GENERAL_FRAMEWORK.md` G6 | `"Motion correction \| < 50 Å total drift \| Check stage, increase blot time"` |

**CryoSPARC guide:** No numerical drift threshold stated anywhere. Says "default parameters often sufficient."  
**Forum:** Practitioners discuss severe drift qualitatively ("reduce late frames", "adjust stage") but no consensus on a discard number. The 50 Å value lives only in the published protocols.

**Remediation prescribed by docs:** "Check stage, increase blot time" — physical/operator actions.  
**Remediation in our code:** `micrograph_batch_size` halved. **This specific software parameter change is NOT in any source.** It is engineering judgment.

---

### Gate: `per_frame_drift` — Per-frame drift as a separate gate

**Rating: ❌ NOT IN ANY SOURCE.**

No skill document, no CryoSPARC guide page, and no forum thread found that treats per-frame drift as a separate gated metric distinct from total drift. The 50 Å total drift threshold is the only motion gate that appears in published protocols. This gate is entirely our own construction.

---

### Gate: `ctf_fit_quality` — CTF FOM threshold

**Rating: ⚠️ PARTIALLY SUPPORTED — threshold exists in papers but the metric and scale differ from our implementation.**

| Source | File | Verbatim text |
|--------|------|--------------|
| VMAT2 Nature 2023 | `02_VMAT2_nature2023.md:195–196` | `"CTF figure of merit threshold: > 0.1 / Resolution threshold: < 4.5 Å (keep)"` |
| CaV1.2 Cell 2023 | `03_CaV1_2_cell2023.md:177` | `"CTFFIND4: 30–5 Å, threshold CTF-FOM > 0.1"` |
| μOR Cell 2022 | `05_muOR_cell2022.md:211` | `"CTFFIND4: 30–5 Å, FOM > 0.1"` |
| General Framework | `00_GENERAL_FRAMEWORK.md` G7 | `"CTF quality \| FOM > 0.1, resolution < 4.5 Å, defocus in target range"` |

**Critical caveat:**  
The papers cite **CTFFIND4's raw FOM** (range ≈ 0.05–0.40; threshold 0.1). Our QC evaluator (`qc_evaluator.py`) uses **CryoSPARC's internal `ctf/cross_corr_ctffind`** metric, which is on a 0–1 normalized scale with our gate at 0.70.

From the **CryoSPARC forum** (thread: "Threshold for CTF fit in Patch CTF", `discuss.cryosparc.com/t/threshold-for-ctf-fit-in-patch-ctf/5449`):  
> CryoSPARC developer: *"Yes that's correct"* — confirming the internal Patch CTF threshold is **0.3** (not 0.1, not 0.7).

**The 0.70 threshold in our code has no source.** The published papers support 0.1 (different metric). The forum confirms the CryoSPARC-native threshold is 0.3. Our 0.70 was set in `docs/QC/20260224_QC_THRESHOLDS_EVIDENCE.md` as `[SILVER] "CryoSPARC v4 CTF score scale (0–1); values < 0.7 indicate unreliable CTF estimates"` — but no citation is given there either.

**Remediation in our code:** Broaden CTF fit window. **Not in any source as a software parameter change.**

---

### Gate: `astigmatism` — < 1000 Å

**Rating: ⚠️ ONE STUDY ONLY, and our own QC doc explicitly flags it as [BRONZE].**

| Source | File | Verbatim text |
|--------|------|--------------|
| VMAT2 Nature 2023 | `02_VMAT2_nature2023.md:194` | `"Astigmatism: 1000 Å (max)"` |

No other study in the skill docs states an astigmatism threshold.

From `docs/QC/20260224_QC_THRESHOLDS_EVIDENCE.md`:
> *"No published consensus exists for using raw astigmatism as a hard gating criterion. Published high-resolution structures (< 3 Å) have been obtained from datasets with 500–2,000 Å astigmatism."*

Correctly rated `[BRONZE]` and downgraded to **advisory** in the QC system in Feb 2026. Our `knowledge_base.py` cites it as if it's a firm gate — it should be labelled advisory.

---

### Gate: `junk_fraction` — High junk fraction threshold

**Rating: ❌ NO NUMERIC THRESHOLD IN ANY SOURCE.**

| Source | File | Verbatim text |
|--------|------|--------------|
| General Framework | `00_GENERAL_FRAMEWORK.md` G8 | `"2D classification \| Clear secondary structure in top classes \| Repick; adjust box; change protein"` |
| MFSD2B preprint | `01_MFSD2B_preprint.md:145` | `"Discard junk; keep classes with secondary structure"` |
| VMAT2 Nature 2023 | `02_VMAT2_nature2023.md` Phase 4 | `"Yield: ~60–70% of picks (keep ~1.5–2.5M per dataset)"` — implies 30–40% rejection is normal |

**What is NOT in any source:** Any numeric junk fraction threshold (e.g., > 50% = HALT). The field uses a qualitative visual criterion (secondary structure visible in top classes). Junk fraction as a computable metric with a halt threshold is our invention.

**Remediation in our code:** Reduce `particle_diameter_angstroms` by 10%. **Completely absent from any source.** The docs say "repick; adjust box; change protein" — all physical decisions. No document prescribes a 10% diameter reduction formula.

---

### Gate: `particle_yield` — Minimum particle count

**Rating: ✅ SUPPORTED for final count targets; ⚠️ per-phase gate thresholds are ours.**

| Source | File | Verbatim text |
|--------|------|--------------|
| Index | `00_INDEX.md` | `"Final particle count \| > 50K for routine; > 200K for < 3 Å \| More particles = better resolution"` |

These are **end-of-pipeline** targets. No source gives a per-phase picking yield threshold that should halt the pipeline.

---

### Gate: `orientation_anisotropy` — Preferred orientation anisotropy score

**Rating: ❌ THE METRIC, FORMULA, AND THRESHOLDS ARE ENTIRELY OURS.**

| Source | File | Verbatim text |
|--------|------|--------------|
| General Framework | `00_GENERAL_FRAMEWORK.md` failure modes | `"Disk-like particles (membrane view = ring) \| Preferred orientation \| Add 0.05% OG to grid sample; tilt stage 30°"` |
| General Framework | principle 8 | `"Never symmetrize without experimental evidence: Applying C2/D2/I symmetry speeds refinement but can mask asymmetric features. Start C1, verify symmetry from 2D classes."` |
| MFSD2B preprint | `01_MFSD2B_preprint.md:114` | `"If preferred orientation → add 0.4 mM fluorinated OM (as done here)"` |

**The C1 symmetry principle is real.** But:
- Our sin-weighted theta-bin anisotropy score (numeric, used in the gate) has no source
- The thresholds (> 3.0 = advisory, > 5.0 = halt) have no source
- The prescribed software fix (increase num_2d_classes) has no source; docs prescribe physical fixes (OG detergent, stage tilt)

**Forum evidence:** (`discuss.cryosparc.com/t/preferred-orientation-issue/14664`) — practitioners use CryoSPARC's "Rebalance Orientations" tool with percentage cutoffs (~89–92%) determined empirically per-dataset. No consensus values exist.

---

### Gate: `class_quality` — Mean 2D class quality score

**Rating: ❌ NOT IN ANY SOURCE.**

G8 ("clear secondary structure in top classes") is a qualitative visual criterion. No numeric class quality score or threshold is stated in any source. Our 0.15 advisory threshold has no backing.

---

### Gates: `abinitio_class_score`, `abinitio_resolution`

**Rating: ⚠️ PARTIALLY SUPPORTED for the direction; ❌ NOT SUPPORTED for specific thresholds.**

| Source | File | Verbatim text |
|--------|------|--------------|
| General Framework | `00_GENERAL_FRAMEWORK.md` G9 | `"Ab initio 3D \| Recognizable 3D structure at 15 Å \| More particles; fix heterogeneity"` |
| General Framework | failure modes | `"Good 2D, bad 3D \| Wrong ab initio reference \| Try 6–8 ab initio classes; use known low-res reference"` |
| VMAT2 Nature 2023 | `02_VMAT2_nature2023.md:221` | `"CryoSPARC Ab initio: Number of classes: 4 / Use subset: 200K particles"` |

**Supported:** The direction (try more classes when ab initio fails) and the 6–8 class range come from the General Framework.  
**Not supported:** Our 0.25 numeric class score threshold; our "+2 per retry" step formula; our 20 Å resolution halt threshold.

**Forum evidence** (`discuss.cryosparc.com/t/number-of-classes-particles-for-an-ab-initio-job/10271`): *"run again with 2, 3, 4, 5 classes"* to find what works. No consensus number. Practitioners test empirically.

---

### Gate: `fsc_resolution` — FSC 0.143 criterion

**Rating: ✅ STRONGLY SUPPORTED — universal across all 8 source studies.**

| Source | File | Verbatim text |
|--------|------|--------------|
| Index | `00_INDEX.md` | `"FSC criterion \| 0.143 (gold-standard) \| Always report; never use 0.5 as primary criterion"` |
| General Framework | `00_GENERAL_FRAMEWORK.md` principle 1 | `"Gold-standard FSC at 0.143: Always report. Never use 0.5 as primary resolution criterion."` |
| General Framework | G10 | `"Gold-standard FSC \| 0.143 crossing visible (not just asymptote) \| More particles; improve CTF"` |
| VMAT2 Nature 2023 | FSC visualization | Resolution at 0.143 = 2.7 Å / 2.9 Å (reported per dataset) |
| CaV1.2 Cell 2023 | FSC visualization | FSC curves (×7) — 0.143 criterion applied |
| μOR Cell 2022 | FSC visualization | `"FSC curves (×2) \| 2.7 Å (fentanyl) / 2.9 Å (morphine) \| 0.143 criterion"` |

The FSC 0.143 criterion is the one gate where both the threshold and the underlying principle are fully verified.

---

## CryoSPARC Official Guide — What It Actually Says

Fetched live from `guide.cryosparc.com` for three relevant job types:

### Patch CTF Estimation
- **"The default parameters for this job are often sufficient for high-quality results."**
- No numerical CTF FOM threshold stated. Diagnostic outputs include 1D defocus search plots and 2D defocus landscape — visual inspection expected.
- No guidance on when to discard micrographs based on CTF score.

### Patch Motion Correction
- Patch size is **500 Å, fixed — cannot be resized by the user**.
- No drift threshold mentioned anywhere.
- `Start frame` and `End frame` parameters allow removing problematic frames manually.
- No quality gate numbers.

### Blob Picker
- Min/Max diameter define the search range; **no guidance on setting these from junk fraction**.
- Described as *"fast but generally the least accurate"* picking method.
- *"In almost all cases, particles picked on denoised micrographs are higher quality."*
- No junk fraction threshold or remediation rule.

**Conclusion from tool docs:** The CryoSPARC guide provides parameter descriptions and defaults but **no quality thresholds and no automated remediation guidance**. It tells you what knobs exist; it does not tell you when to turn them.

---

## CryoSPARC Forum — What It Actually Contains

Searched and fetched live from `discuss.cryosparc.com`:

| Topic | Forum finding | Usefulness |
|-------|--------------|------------|
| Motion drift threshold | Qualitative troubleshooting ("reduce late frames", "adjust stage"); no 50 Å consensus | Low — no numbers |
| CTF FOM threshold | Developer confirmed CryoSPARC Patch CTF internal threshold is **0.3** (thread: `t/threshold-for-ctf-fit-in-patch-ctf/5449`) | Medium — gives the native CryoSPARC value we should use |
| Blob picker / junk fraction | Range examples (70–170 Å, 100–200 Å) but lowpass filter settings considered more important than diameter; **no systematic junk-fraction → diameter rule** | Low for our use case |
| Orientation anisotropy | Practitioners use "Rebalance Orientations" with empirical % cutoffs (~89–92%); *"you will always have to sacrifice some particles"* | Low — confirms no consensus threshold |
| Ab initio class count | *"run again with 2, 3, 4, 5 classes"*; practitioners test empirically; no consensus | Low — confirms empirical nature |

**What forums do provide that papers don't:**
- The CryoSPARC-native CTF threshold (0.3) — a specific number from a developer
- Practical diameter ranges people actually use (70–200 Å) for blob picker
- Confirmation that preferred orientation remediation is empirical and dataset-specific
- Troubleshooting patterns (*when* to suspect a specific cause)

**What forums do NOT provide:**
- Systematic "if metric X > Y then change parameter Z by amount W" rules
- Validated threshold values with sample size or statistical backing
- Membrane vs. soluble protein distinctions in parameter choices

---

## Summary Table

| Gate | Threshold supported? | Remediation action supported? | Notes |
|------|---------------------|-------------------------------|-------|
| `motion_drift < 50 Å` | ✅ 3 lab protocols | ❌ Batch size halving = invented | Docs say "check stage, increase blot time" |
| `per_frame_drift` | ❌ Not in any source | ❌ | Gate itself has no basis |
| `ctf_fit_quality > 0.70` | ❌ Wrong metric/scale | ❌ | Papers: FOM > 0.1 (CTFFIND4 raw); Forum: CryoSPARC native = 0.3 |
| `astigmatism < 1000 Å` | ⚠️ One study; our own QC doc flags as [BRONZE]+advisory | ❌ | Should be advisory-only |
| `junk_fraction < 50%` | ❌ No numeric threshold anywhere | ❌ Diameter reduction % = invented | Docs: visual only ("secondary structure visible") |
| `particle_yield > 5000` | ⚠️ Final count targets only | ❌ | Per-phase halt number is ours |
| `orientation_anisotropy` | ❌ Metric and thresholds entirely ours | ❌ | C1 symmetry principle is real; rest is ours |
| `class_quality > 0.15` | ❌ Qualitative visual criterion only | ❌ | |
| `abinitio_class_score > 0.25` | ❌ Direction supported; threshold not | ⚠️ "+2 classes" loosely from "try 6–8" | |
| `abinitio_resolution < 20 Å` | ⚠️ "15 Å recognizable structure" qualitative | ❌ | |
| `fsc_resolution` (0.143) | ✅ Universal across all 8 studies | N/A | Best-supported gate |

---

## What Needs Fixing

### Immediate (misrepresented in current knowledge_base.py)

1. **CTF metric disambiguation**: Our gate uses CryoSPARC's normalized scale (0.70); knowledge_base.py cites CTFFIND4 raw FOM (0.1). These are different things. The knowledge entry must say this explicitly, and the gate threshold should be reconsidered — the CryoSPARC forum confirms the native threshold is 0.3, not 0.70.

2. **Astigmatism**: Must be labelled advisory-only with [BRONZE] confidence. Our own QC doc (`docs/QC/20260224_QC_THRESHOLDS_EVIDENCE.md`) already says this.

3. **per_frame_drift gate**: Should be removed or clearly labelled as having no source.

4. **Remediation actions**: Every parameter change in `param_tuner.py` should carry a source label. Currently all the "how to tune" logic is unlabelled engineering judgment.

### Medium-term (forum data would fill these gaps)

The specific rules that forums partially contain but don't systematize:
- CTF FOM 0.3 (CryoSPARC-native) vs 0.1 (CTFFIND4 raw) — which scale to use and when
- Practical blob picker diameter ranges by protein class (membrane vs. soluble)
- When practitioners actually give up on a dataset vs. retry (the halt-vs-retry decision)
- Orientation anisotropy: what percentage rebalancing cutoffs practitioners find effective

### Long-term (would require systematic forum crawl)

A structured crawl of `discuss.cryosparc.com` with categories:
- Motion correction troubleshooting
- CTF estimation quality
- Particle picking optimization
- Preferred orientation
- Ab initio troubleshooting

Each thread contains: symptom → what was tried → what worked. This is exactly the "if metric X > threshold → try action Y" pattern our auto-loop needs. It is not in papers. It is in forums. But it needs extraction and structuring, not just linking.

---

## Appendix: Source Files

| File | DOI / URL | Used for |
|------|-----------|----------|
| `docs/cryo_em_skills/00_GENERAL_FRAMEWORK.md` | BioMate internal | QC gate table G6–G14, principles 1–8, failure modes |
| `docs/cryo_em_skills/00_INDEX.md` | BioMate internal | Cross-cutting parameters: pixel size, FSC, particle count |
| `docs/cryo_em_skills/02_VMAT2_nature2023.md` | 10.1038/s41586-023-06328-6 | Motion < 50 Å, CTF FOM > 0.1, astigmatism 1000 Å |
| `docs/cryo_em_skills/03_CaV1_2_cell2023.md` | 10.1016/j.cell.2023.08.002 | CTF FOM > 0.1 (independent confirmation) |
| `docs/cryo_em_skills/05_muOR_cell2022.md` | 10.1016/j.cell.2022.06.017 | Motion < 50 Å, CTF FOM > 0.1 (independent confirmation) |
| `docs/QC/20260224_QC_THRESHOLDS_EVIDENCE.md` | BioMate internal | Existing threshold audit; CTF 0.70 [SILVER], astigmatism [BRONZE] |
| `guide.cryosparc.com` (Patch CTF, Motion Correction, Blob Picker) | Fetched 2026-04-16 | Official parameter defaults; **no threshold values given** |
| `discuss.cryosparc.com/t/threshold-for-ctf-fit-in-patch-ctf/5449` | Fetched 2026-04-16 | CryoSPARC developer confirms Patch CTF native threshold = **0.3** |
| `discuss.cryosparc.com/t/number-of-classes-particles-for-an-ab-initio-job/10271` | Fetched 2026-04-16 | Ab initio class count: empirical, no consensus |
| `discuss.cryosparc.com/t/preferred-orientation-issue/14664` | Fetched 2026-04-16 | Preferred orientation: empirical % cutoffs, no consensus |
