# Paper skeleton — Automated, cross-modality preprocessing-QC ("clean + prove it")

Date: 2026-08-12. Honest draft skeleton. Companion evidence:
20260811_ALIGNMENT_QC_FEASIBILITY.md, 20260812_PREPROCESSING_CAPABILITY_LEVERAGE_AUDIT.md,
scripts/{gate1_alignment_qc_overcorrection,gate2_*,clean_and_verify_qc_proofpoint,qc_battery}.py.

## Working title
"Verify, don't just clean: an automated cross-modality quality gate that detects
over-correction in single-cell and bulk preprocessing."

## The one honest sentence of novelty
Not new metrics — the metrics are published (scIB/Luecken 2022; kBET 2019; LISI 2019;
**RBET 2025**). The contribution is **operationalizing** them into an automated,
plain-English, closed-loop *verdict* that (i) works uniformly across bulk and single-cell,
(ii) fires when over-correction really happens and stays silent when integration is fine, and
(iii) is validated to catch silent failures that standard practice (report batch-mixing, eyeball
a UMAP) misses. Position as a tool/systems Applications Note, NOT a methods paper.

## Prior art (cite up front — do NOT claim "first to detect over-correction")
- scIB / Luecken et al. 2022 Nat Methods — batch-removal vs bio-conservation tradeoff (iLISI/kBET
  vs cLISI/ARI). The metric substrate.
- kBET (Büttner 2019), LISI/iLISI/cLISI (Korsunsky/Harmony 2019).
- **RBET (Hu 2025, Comm Biol)** — explicitly over-correction estimation. Closest prior art;
  our delta is automation + cross-modality + platform gate, not the detection idea.
- Erasure-of-signal literature (bioRxiv 2021.11.15.468733).
- Competitive scans (docs/20260811_OMICS_ALIGNMENT_LANDSCAPE.md): NO commercial/cloud platform
  productizes over-correction detection as a user-facing feature — the honest white space.

## Claims → the experiment that must support each
1. **C1 — Batch-only metrics are fooled/misled by over-correction; a biology-conservation panel
   catches it.**
   - Evidence: Gate-1 simulation (batch-only |AUC|~0.6 vs bio |AUC|=1.0). DONE.
2. **C2 — Holds on real cells, in the confounded regime, and stays quiet on clean data.**
   - Evidence: Gate-2 real scIB pancreas — clean θ-sweep = no over-correction (gate quiet);
     confounded subset = biology ARI 0.21→0.00 while iLISI rises (batch-only misled). DONE.
3. **C3 — Generalizes to bulk with the real ComBat algorithm (the mass-market task).**
   - Evidence: clean_and_verify proof-point — clean=TRUSTED, confounded=OVER-CORRECTED. DONE.
4. **C4 — Across a battery (method × confound × seed), the gate predicts an INDEPENDENT
   downstream failure (condition unrecoverable after cleaning) while the batch metric does not;
   standard practice false-accepts over-corrected results at a rate the gate does not.**
   - Evidence: `scripts/qc_battery.py` — real ComBat (bulk) + real Harmony (sc), confound sweep
     {0,.25,.5,.75,.95}, seeds, downstream = 5-fold CV condition-classification (independent of
     the gate metric). RESULTS:
     - **Bulk / ComBat (n=50, 7 over-corrected): STRONG.** corr(GATE, downstream)=**+0.58**;
       corr(BATCH-removal, downstream)=**−0.86** (the better batch removal looks, the *more*
       biology is destroyed); **standard-practice false-accept of over-corrected = 0.14 vs
       GATE = 0.00.** ← the money result.
     - **SC / Harmony (n=30): 0 over-corrections triggered** — even at θ=200/confound=0.95
       downstream stayed 1.000. Harmony's soft-clustering *preserves* structure; and this sim
       put condition/batch on orthogonal genes, which Harmony leaves intact. **Key honest
       finding: over-correction is METHOD-DEPENDENT** — location-scale/linear methods (ComBat,
       limma removeBatchEffect — the bulk GEO/TCGA default the tutorial teaches) over-correct
       readily; Harmony largely resists it. The gate correctly STAYS QUIET for robust methods
       and FIRES for aggressive ones — desirable behavior, not a miss.
     - **SC real-data anchor:** Gate-2b (real scIB pancreas, confounded alpha/beta) already
       showed Harmony *can* over-correct on genuinely entangled real cells (ARI 0.21→0.00) —
       so the cross-modality claim rests on the bulk battery + the real-pancreas anchor, not
       the orthogonal-gene sc sim.
   - **Refinement for the paper:** the value proposition sharpens to "the gate is essential for
     the aggressive/linear corrections that dominate bulk practice, and a safe no-op for
     structure-preserving ones" — a more defensible, more useful claim than "all methods
     over-correct."
5. **C5 — It's a real, integrated capability, not a script.**
   - Evidence: productionized as a BioMate auto-loop QC gate (contract {name,measured,threshold,
     pass} → _evaluate_qc_from_s3); leverage audit shows the tools already exist. TO BUILD.

## Structure (Applications Note / GigaScience)
- **Advantage:** automated + plain-English + closed-loop + cross-modality; catches silent GIGO
  at the step everyone crashes on (the "最关键" batch/normalize step); unclaimed by any platform.
- **Challenges (state them honestly — credibility):**
  - technical vs biological variation is *unidentifiable* under confounding (no method escapes it);
  - the verdict needs a *biology reference* (labels / pre-integration clusters / markers) users may
    lack post-integration;
  - no gold standard for the *tunable-confounded* case → must simulate (validity rests on sim
    realism); real confounded data (scIB isolated labels) gives natural-but-not-tunable anchors;
  - the metrics are not novel — RBET/scIB precede us.
- **Solutions:** the verdict logic + thresholds; the gold-standard battery (sc-mixology/scIB/sim,
  docs/20260811_ALIGNMENT_QC_FEASIBILITY.md); the auto-loop gate integration; the multi-arm
  validation (C1–C4) + the "beats standard practice" comparison.

## What still must be done before submission (honest)
- [ ] C4 battery with CIs (running) → the headline figure.
- [ ] Extend battery to ≥1 more real dataset (sc-mixology) + ≥1 more method (limma removeBatch /
      scanorama) so "cross-method/dataset" isn't overstated.
- [ ] C5: productionize the gate as a runnable BioMate subworkflow + auto-loop gate; report a
      real end-to-end run.
- [ ] Optional: small reproducibility/usability angle for the tool-paper venue.
- [ ] Threshold calibration ON the gold standard (not hand-set), reported with sensitivity.

## Venue + framing
Bioinformatics (Applications Note) / GigaScience / BMC Bioinformatics. Frame as
"first automated, platform-integrated, cross-modality preprocessing-verification gate,"
citing RBET/scIB/kBET as the operationalized methods. Do NOT claim novel detection science.
[[feedback_overclaiming_conclusions]] [[feedback_citation_integrity]]
