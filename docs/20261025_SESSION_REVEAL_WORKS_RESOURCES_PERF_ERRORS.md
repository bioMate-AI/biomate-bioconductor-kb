# Full reveal — works, resources, performances, errors (cyclic-peptide / αvβ6 program review)

**2026-10-25.** A complete, honest accounting of this review session and the prior work it audited:
what was done, what was collected, every performance number (with its honest status), every error/over-claim
caught, and additional findings mined from the subagent review outputs. Nothing here is spun — the whole
exercise exists to stop over-claims reaching a manuscript.

---

## 1. Works done (this session)

| Work | Output |
|---|---|
| State-of-study review (docs + result JSONs) | per-approach verdict table; "nothing validated vs SOTA" |
| Code review (implementation realness + metal model) | per-module REAL/STUB/PARTIAL; metal model unvalidated |
| Gold-standard ground-truth lock (αvβ6 FEP benchmark) | A1/A2 measured series found; A20FMDV2 prereg set debunked |
| Read 2 external works (user-flagged) | SynCraft (Nature MI); Landry availability (bioRxiv) |
| C1 experiments on Landry data (ran live) | mini-C1, random-CV (leakage), 3-fam LODO, 7-domain LODO |
| **Built + shipped a real model** | `peptide_availability.py` + gate-chain wiring (commits 3ebab5f8e, d97abf609) |

## 2. Resources collected (with provenance)

- **Landry in-cell peptide dataset** — `github.com/Landrylab/Lemieux_et_al2026` (CC BY-NC-ND) + SRA `PRJNA1499819`.
  Files pulled/used: `data/PCA1/med_ppi_score.csv` (in-cell PPI, 7 SH3 domains, 3043 variants), `med_avail_score.csv`
  (measured availability), `PWM_scores.csv` (phage/in-vitro proxy), `in_silico_prediction/results/04_analysis/all_ddg.csv`
  (FoldX + FlexDDG ΔΔG, 3240 rows, 3 domains). Paper: Lemieux…Landry, bioRxiv doi:10.64898/2026.09.21.752983.
- **Gold-standard αvβ6 affinity series** (for FEP ground truth):
  - **A1** cyclic nonapeptides c[X-RGDL-A-X-dPro-NMeK], X∈{F,Y}: FF/YF/FY/YY IC50 = 0.17/3.3/2.8/0.84 nM (ELISA).
    Quigley et al., RSC Med Chem 2023 (PMID 38099056) + EJNMMI 2022 (PMID 34559266). **This is our exact chemotype;
    Trivehexin-monomer = YY, avebehexin = FF.**
  - **A2** cyclic pentapeptide [RGD-Chg-E] N-methyl scan (SDM17): IC50 1.3 nM→>5000 nM. Tomassi et al., JMC 2021 (PMID 33961417).
  - Selectivity (measured ELISA): FF 2494× over αvβ3; A20FMDV2 ≥85×; B6_BP_dslf >1000×.
- **SynCraft** — Li & Lai (PKU), Nature Machine Intelligence 2026 / arXiv 2512.20333; code `catalystforyou/SynCraft-Core`.
- **αvβ6 co-structures** (MIDAS metals): 8TCG (cryo-EM 3.4 Å, 0 unmodeled), 4UM9 (X-ray 2.5 Å), 9XMM (2.88 Å, cyclic RGD).

## 3. Performances — every number with its honest status

| Approach | Measured | Bar | Status |
|---|---|---|---|
| PepGLAD cyclic FT (M2c) | DockQ **0.437** | PepGLAD 0.592 (diff task) | PLATEAUED, below; number-shopped across sets (0.506 on PepBDB, 0.326 elsewhere — not comparable) |
| UniMoMo cyclic FT | +0.0097 (95% CI spans 0) | base UniMoMo 0.403 | NULL; `training_qualified:false` (79 OOM) |
| UniMoMo linear 0.7754 "reproduced" | — | 0.7592 | UNCONFIRMED (MKL failure; docs conflict) |
| BoltzGen cyclic FT (LOTO) | Δiptm **−0.16** | base BoltzGen | FAILED/superseded |
| Within-target display selector | AUC 0.94–0.99; hPCSK9 **0.343** | abundance null AUC 1.0/0.997 | CIRCULAR + below null; below chance on hPCSK9 |
| Cross-target transfer (v3.1, xtarget_fm) | NULL; Spearman 0.26 | field 3–8% | NULL |
| Chemical binding model (847 tgt, GLOO) | RF **0.42** ceiling | "strong" | NULL ceiling |
| Permeability learned-rep | R² 0.12–0.30 | CycPeptMP 0.77 | FAILED vs SOTA |
| MM-GBSA αvβ6 metal-free | +5.38…−26.5 | — | RULED INVALID (metal dropped) |
| MM-GBSA αvβ6 metal-aware (Li-Merz Mn) | Trivehexin −7.2 vs avebehexin **−122.2** (115 kcal/mol apart) | controls must converge | RULED INADMISSIBLE |
| **FEP control edge (Y1F+Y7F)** | ΔΔG **−0.18 ± 0.15** | **measured −0.95** (found this session) | **MISS; metal-blind edge; "expected ≈0" was false** |
| DPO permeability close (cluster-disjoint) | **+0.098** (6/6 seeds, p=0.031); placebo +0.124 vs +0.014 (p=0.004) | — | WORKS narrowly (ML oracle, not binding) |
| Rule-constrained DPO arm | identical to unconstrained (+0.2513) | — | NULL for the gate (never bound) |
| FTO novelty | 20/22 "novel"; `patents_checked:false` | — | similarity filter only; αvβ6 monomer FTO-BLOCKED (CA2998968) |
| CRO panels | αvβ6 panelB **0/12 have RGD**; PD-L1 panelA 0/10 pass | our own gate | FAILED own gate; no wet-lab result exists |
| Renal cross-target | LOTO ρ **−0.26** (p=0.11); fuller ρ +0.02 | generalize | NULL (prior +0.27 = charge artifact; +0.78 was αvβ3 n=8+αvβ6 n=4) |
| **Availability model (THIS SESSION, shipped)** | in-sample ρ **0.72**; **LODO ρ 0.40** (robust 0.23–0.49) | — | **WORKS — transfers (peptide-intrinsic); shipped as a gate** |
| Binding + availability (3-fam) | random-CV 0.736 → **LODO 0.282** (< physics 0.316) | physics 0.316 | leakage-inflated; collapses out-of-domain |
| Binding + availability (7-domain) | PWM 0.265 → +hydro 0.286 → +measured-avail 0.319 | PWM 0.265 | marginal/inconsistent — not SOTA |

## 4. Errors & over-claims caught (the point of the review)

1. **FEP "control recovered the expected ≈0 → validated"** — FALSE on both counts. Control edge = YY→FF, measured
   ΔΔG = **−0.95 kcal/mol** (FF ~5× tighter, Quigley), not 0; our FEP gave −0.18 → a *miss*, not a validation.
   The "A2 anchor cleared" claim in the controls doc / cyclic-LLM paper / committee review is **wrong and must be corrected.**
2. **Three leakage-inflated "wins"** caught by proper held-out splits: (a) selector AUC 0.94 (circular: label = conditioning
   signal, confirmed in code `harvest_display_ngs_multitarget.py:186-188`); (b) renal ρ 0.27 (charge artifact); (c) C1 random-CV
   0.74 (within-domain leakage → LODO 0.28).
3. **MM-GBSA metal mishandling** — metal-free dropped Mn (positive ΔG); metal-aware diverged 115 kcal/mol on controls. Both
   correctly ruled unusable — but were nearly cited as a binding signal.
4. **Prereg ground-truth was fictional** — the A20FMDV2 "Ala/Cit/Arg19 series" named in `20261024_AVB6_FEP_GOLD_BENCHMARK_PREREG.md`
   does not exist as stated (Cardle 2021 = cyclized analogs within ~0.2 kcal/mol of each other; cannot anchor FEP).
5. **Control-species mismatch** — docs quote Trivehexin "~47 pM" (that is the **trimer**); the monomer control YY = 0.84 nM.
6. **"20/22 passed" read as readiness** — it was the FTO novelty gate only (`patents_checked:false`); non-binders pass trivially.
7. **CRO panelB ordered without RGD** — 0/12 contain the pharmacophore; by our own rule none can bind.
8. **"validated lead" K-05 / "physics-verified closed cycle"** — K-05 has no experimental validation; the "closed cycle" uses
   an ML permeability oracle, not MM-GBSA/FEP.

## 5. Additional findings mined from the subagent review outputs

- **The FEP guard is on the dead path.** `MDRUN_CMD_READY=False` lives in the superseded `fep_batch.py`; the live
  `fep_production.py` has **no guard** and submits once an S3 `npt.gro` exists. "Production FEP is gated until go" is untrue of
  the path that runs.
- **Fan-out is not HREX.** `fep_production.py` runs independent λ windows → `gmx bar`, contradicting the mdp's "HREX" language;
  with 0.5 ns/window on 205k atoms, the error bars are analytic-BAR-only and optimistic; the `gmx bar` total-line regex can
  silently yield `None`.
- **The only FEP edge is metal-blind and the admissibility gate keys off it** (`physics_dispatch.py:144-165`) — so passing it
  would manufacture false confidence in metal-dependent ΔΔGs. The staged positive control that *would* exercise the metal
  (RGD **Asp→Ala**) is stubbed at `build_fep_setup.sh:95` but never run.
- **`neural_generator` is a re-ranker, not a generator** — it scores ~80 enumerated flank-triples by LM log-likelihood,
  conditioned on *permeability / null-target*, explicitly **not** αvβ6 affinity. The "closed optimizer loop" `revise()` is a
  hand-coded deterministic rule stand-in (self-labelled); gradient RLVR is not wired.
- **`methodology_close` is the only genuinely closed reward→update loop** — real gradient DPO with a cluster-disjoint evaluator
  and a placebo control — but it optimizes permeability/enrichment, **never binding**. Its honesty is exemplary; its objective
  is not the one that matters.
- **RFpeptides — the physics prior the synthesis doc named as the real cross-target generalizer — was PARKED, never fired**
  (`PROGRAM_CHALLENGE_MAP.md` C5).
- **hPCSK9 selector is below chance** (0.266 after the enrichment-sort null); the unified-v4 "rescue 0.34→0.82" is a rescue
  inside a circular eval.
- **The in-silico predictor Landry shipped is physics affinity (FoldX + FlexDDG), not ML/availability** — so our availability
  angle is non-overlapping with theirs; but their ΔΔG exists for only **3 of 7** domains (expensive), which is why our 3-domain
  LODO was underpowered and the 7-domain PCA data was the right test.
- **A clean single-residue *protein* selectivity edge exists** — B6_BP A39K: β6 1.7→0.11 nM, β8 7.3→580 nM (Roy 2023) — a
  future selectivity-FEP anchor, though large for FEP.

## 6. Net state and the one real deliverable

**Across every binding/affinity/cross-context direction, nothing survives rigorous held-out testing** — the consistent wall is
**generalization**, not capacity. There is still **no non-circular, experimentally-grounded binding signal** in the program, and
**no wet-lab data of any kind.**

The one thing that *is* real, useful, and honest: **the availability model** — peptide-intrinsic, so it transfers (LODO ρ 0.40,
robust), grounded in Landry's measured data, shipped into BioMate's gate chain as an informational score (never gates a surface
binder), and screened across our v2 panel. Modest but real, with generalization honestly tested. That is the correct kind of
contribution for this program right now.

**Required follow-up (integrity):** correct the "FEP control recovered ≈0 / A2 anchor cleared" claim in
`20261022_CYCLIC_LLM_CLOSED_CYCLE_CONTROLS.md`, the cyclic-LLM manuscript, and the committee-review record, to the measured
−0.95 vs computed −0.18 *miss*.
