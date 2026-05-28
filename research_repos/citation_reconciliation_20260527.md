# Citation Reconciliation — 2026-05-27

Pre-bioRxiv verification for AutoLoop/Flagship and BioMate-Cryo manuscripts.

## Task 1 — Aronov 2008 hERG citation

### Finding: BOTH citations in BioMate are incorrect. No Aronov 2008 *J Med Chem* paper exists.

PubMed search of all "Aronov AM hERG" publications returns:

| Year | Journal | Citation | DOI |
|------|---------|----------|-----|
| 2004 | Bioorg Med Chem | 12(9):2307–15 | 10.1016/j.bmc.2004.02.003 |
| 2005 | Drug Discov Today | 10(2):149–55 | 10.1016/S1359-6446(04)03278-7 |
| 2006 | J Med Chem | **49(23):6917–21** | 10.1021/jm060500o |
| **2008** | **Curr Opin Drug Discov Devel** | **11(1):128–40** ("Tuning out of hERG") | PMID 18175275 |
| 2008 | Curr Top Med Chem | 8(13):1113–27 | 10.2174/156802608785700061 |

- DOIs `10.1021/jm0707476` and `10.1021/jm800467u` both return **404 / 403** from ACS — neither resolves to a real Aronov hERG paper.
- The 2006 J Med Chem paper (jm060500o) is the only Aronov *J Med Chem* paper on hERG; its pages are **6917–6921**, not 6632–6642 or 2577–2586. Volume is 49 (2006), not 51 (2008).
- The widely cited paper "A quantitative assessment of hERG liability as a function of lipophilicity" (Bioorg Med Chem Lett 2007;17(6):1759–64, doi:10.1016/j.bmcl.2006.12.061) is by **Waring & Johnstone**, *not Aronov*. This appears to be the source of the "logP/hERG correlation, 10 µM cutoff" claim that BioMate attributes to Aronov.

### The 10 µM hERG IC50 cutoff

This cutoff is industry convention (Bowes et al. 2012 *Nat Rev Drug Discov*) and is the operational threshold used in safety pharmacology pre-clinical screens; it traces to ICH S7B (2005) and to Redfern et al. 2003 *Cardiovasc Res* 58:32–45 (30× safety margin → ~10 µM for a 0.3 µM Cmax). It is **not** introduced by Aronov.

### Recommended citation for BioMate

Replace both Aronov 2008 *J Med Chem* citations (Flagship §1 and `knowledge_base.py` lines 25/106) with one of:

1. **Aronov AM. "Tuning out of hERG." *Curr Opin Drug Discov Devel*. 2008;11(1):128–140. PMID 18175275** — for the lipophilicity/property-tuning narrative
2. **Waring MJ, Johnstone C. *Bioorg Med Chem Lett.* 2007;17(6):1759–64. doi:10.1016/j.bmcl.2006.12.061** — for the quantitative logP↔IC50 relationship
3. **Redfern WS et al. *Cardiovasc Res.* 2003;58:32–45** — for the 10 µM / 30× safety margin
4. **Bowes J et al. *Nat Rev Drug Discov.* 2012;11:909–22** — for the industry-standard 10 µM IC50 cutoff in screening panels

Flagship §1 should cite (3) + (4) for the threshold. `knowledge_base.py` should cite (1) for the framework and (2) for the regression.

## Task 2 — BioMate-Cryo "7 QC gate modules" reconciliation

### Finding: Possibility (c) — two parallel subsystems with a partial overlap. The paper claim is internally consistent; the central catalog is partial.

Evidence:

1. **Paper §2.2 (Table 1)** explicitly enumerates **7 named gates**: motion_correction, ctf_estimation, particle_picking, 2D_classification_junk, orientation_anisotropy, fsc_validation, atomic_model_quality.
2. **`backend/experiments/cryo_em_autoloop/qc_evaluator.py`** implements **11 internal gate evaluations** (`motion_drift`, `per_frame_drift`, `ctf_fit_quality`, `astigmatism`, `junk_fraction`, `particle_yield`, `orientation_anisotropy`, `class_quality`, `abinitio_class_score`, `abinitio_resolution`, `fsc_resolution`). These collapse cleanly to the paper's 7 modules:
   - Gate 1 motion_correction = motion_drift + per_frame_drift
   - Gate 2 ctf_estimation = ctf_fit_quality + astigmatism
   - Gate 3 particle_picking = particle_yield
   - Gate 4 2D junk = junk_fraction + class_quality
   - Gate 5 orientation = orientation_anisotropy
   - Gate 6 fsc_validation = fsc_resolution (+ abinitio_resolution as preliminary)
   - Gate 7 atomic_model_quality = (not in qc_evaluator.py; lives in Phenix/ModelAngelo post-processing path)
3. **`backend/config/qc_evidence.yaml`** lists only **3 cryo_em entries** (`cryo_em_fsc_resolution` GOLD, `cryo_em_motion_drift` SILVER, `cryo_em_particle_count` SILVER) — this is a *citation/evidence catalog*, not the gate inventory. It surfaces only those metrics that have been wired into the central evidence-graded YAML for cross-domain auto-loop reporting; the cryo_em_autoloop module evaluates gates locally with its own profile thresholds.

Architecturally, BioMate currently has **two parallel QC paths**:
- The cryo-specific `experiments/cryo_em_autoloop/qc_evaluator.py` (full 11-gate / 7-module implementation, profile-aware)
- The cross-domain `config/qc_evidence.yaml` (3 entries — partial mirror used by the generic auto-loop UI)

### Recommended fixes

**BioMate-Cryo manuscript (`MANUSCRIPT_DRAFT.md`):**
- §2.2 is correct as written — keep "Seven QC gate modules". No paper change required for the count claim.
- Optional clarification in §2.2 or §6 (Code Availability): add one sentence noting that the 7 paper-level gate modules decompose into 11 metric-level evaluations in the implementation (one-to-many for motion_correction and ctf_estimation); cite `backend/experiments/cryo_em_autoloop/qc_evaluator.py`.
- §6 also: note that Gate 7 (atomic_model_quality) is implemented in the Phenix/ModelAngelo post-processing path, not in `qc_evaluator.py` itself, to avoid reviewer confusion if they grep the file.

**Backend (no edits this session — user batches):**
- Add the missing 4 cryo gate entries to `backend/config/qc_evidence.yaml` so the central catalog matches the paper: `cryo_em_ctf_fit_quality` (SILVER, Rohou & Grigorieff 2015), `cryo_em_junk_fraction` (BRONZE), `cryo_em_orientation_sphericity` (SILVER, Tan et al. 2017), `cryo_em_ramachandran_favored` (GOLD, wwPDB).
- OR document explicitly in a header comment that qc_evidence.yaml is a "cross-domain reporting subset" and the authoritative cryo gate inventory lives in `cryo_em_autoloop/qc_evaluator.py`.

**Flagship/AutoLoop paper:**
- Update the Aronov citation (Section 1) per Task 1 above. Replace the bare "Aronov 2008" with Redfern 2003 + Bowes 2012 (for the 10 µM cutoff) and Aronov 2008 *Curr Opin Drug Discov Devel* 11:128–140 (for the property-tuning framework). Same fix in `backend/experiments/admet_autoloop/knowledge_base.py` lines 25, 106, 107.
