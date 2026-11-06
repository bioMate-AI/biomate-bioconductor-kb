# Reviewer G_medchem_output -- z-ai/glm-5.3-prime
_(elapsed 43s; usage {'prompt_tokens': 30809, 'completion_tokens': 3558, 'total_tokens': 34367, 'cost': 0.1175756, 'is_byok': False, 'prompt_tokens_details': {'cached_tokens': 0, 'cache_write_tokens': 0, 'audio_tokens': 0, 'video_tokens': 0}, 'cost_details': {'upstream_inference_cost': 0.1175756, 'upstream_inference_prompt_cost': 0.0862652, 'upstream_inference_completions_cost': 0.0313104}, 'completion_tokens_details': {'reasoning_tokens': 24, 'image_tokens': 0, 'audio_tokens': 0}})_

## 1. VERDICT ON OUR FINDINGS

**Right:**
- The audit discipline is the program's most valuable asset. Catching the FEP "null control" fiction (measured −0.95 vs computed −0.18, Doc 2 §4.1), the metal-never-in-pocket bug (Doc 3), and three leakage-inflated wins (Doc 2 §4.2) is exactly what most computational programs fail to do before a manuscript.
- The availability model (Doc 4) is correctly scoped: informational for surface targets, LODO-validated, honest about ρ ≈ 0.40. This is the right *kind* of contribution.
- The A1/A2 measured SAR series (Doc 2 §2) is a genuine asset — 10+ points on the *exact* chemotype with measured selectivity ratios. Underused so far (see below).

**Wrong / overclaimed:**
- *Claim (Doc 2 §6): "the one real deliverable is the availability model."* → Problem: for a PDAC radioligand program, a solubility proxy trained on intracellular SH3 peptides is not the deliverable; it's a side contribution. The deliverable the program *could* produce — a falsifiable, pre-registered αvβ6 candidate dossier with calibrated physics — doesn't exist yet. Evidence needed: a dossier artifact in the repo.
- *Claim (score.py): `ddg_fep` labelled "trustworthy arbiter."* → Problem: the only FEP edge ever run was metal-blind, single-replica, 0.5 ns/window, analytic-BAR-only, and missed the measured value by ~5×. Nothing about it is trustworthy yet. The comment manufactures confidence the code hasn't earned. Evidence needed: rebuilt metal-correct control edge within ±0.5 kcal/mol of −0.95, with replica exchange and converged overlap.
- *Claim (reward.py): selectivity is "first-class."* → Problem: `selectivity_gap` is `"pending"` for every αvβ6 candidate and has never been computed vs αvβ3/5/8. A first-class term that is always 0 is not first-class. Evidence needed: at least a docking/pose-based selectivity proxy for β3/β5/β8 before the term means anything.
- *Claim (Doc 4): "no deployable availability predictor existed."* → [UNVERIFIED] — plausible but I cannot confirm no prior peptide solubility/aggregation predictor exists; hydrophobicity-based solubility heuristics are common. Evidence needed: a short prior-art search before making the novelty claim publicly.

**Missing (my mandate):**
1. **No radioligand-specific design axis anywhere.** Nothing on chelator conjugation site, linker, renal retention (the dominant dose-limiting toxicity for RGD radiotherapeutics — the whole reason αvβ6 trimer/monomer chemistry exists), or in vivo stability of the c[RGDLXX] scaffold. For a PDAC imaging/therapy program this is not a detail; it is the *product profile*.
2. **No dossier format.** The output today is a JSON with `binding_dG: "pending"` and `patents_checked: false`. That cannot go to a CRO or a clinician.
3. **No cheapest-informative-experiment plan.** The team has 10 measured SAR points and zero plan for what the first 96-well plate buys.
4. **FTO realism is thin.** `fto_score` is similarity + literal-genus matching with `patents_checked: false`. DoE analysis of a claim genus (e.g., "X = aromatic amino acid") requires actual claim construction, not a string match. The 2Nal "escape" in `loop.py:revise()` (swap P7→2Nal to exit the literal genus) is exactly the move a litigator would predict and a claim-drafting team would have covered with "or an aromatic analogue thereof."

## 2. YOUR PROPOSAL FOR MY MANDATE AREA

**A. Decision-grade candidate dossier — new module `cyclic_llm/dossier.py` + `docs/DOSSIER_TEMPLATE.md`.**

One candidate = one Markdown + JSON pair, machine-generated from `score()` records, with a mandatory schema:

- **Identity:** HELM, monomer table, MW, net charge, cLogP-proxy, N-methyl/ncAA count, synthetic route feasibility (solid-phase, one cyclization, ncAA availability from commercial catalogs — a lookup table, not a guess).
- **Provenance block:** every number carries `{value, method, calibration_status, citation}`. Calibration status ∈ {measured, FEP-validated, FEP-unvalidated, proxy, heuristic}. The FEP-unvalidated label is *mandatory* until the rebuilt control edge lands within tolerance — this kills the "trustworthy arbiter" overclaim structurally.
- **Calibrated uncertainty:** for each physics prediction, a prediction interval derived from the control-edge error. Today that means: "FEP ΔΔG error ≥ 0.8 kcal/mol (single observed miss of 0.77 kcal/mol on the only validated edge; n=1, so treat as a floor, not a CI)." State n=1 honestly.
- **Pre-registered falsifiable predictions** (the core): for each dossier, a `predictions.json` written *before* any experiment: predicted IC50 rank vs the A1 grid, predicted selectivity ratio vs αvβ3 (target: ≥100×, measured FF = 2494×), predicted N-methyl-scan sensitivity pattern vs A2 (which positions tolerate NMe), predicted microsomal/plasma stability half-life band. Each with a pass/fail threshold and a date. The A2 N-methyl scan is the perfect template: 10+ positions, measured 1.3 nM → >5000 nM — predict the *pattern* per position, not just the anchor.
- **Liability register:** deamidation/isomerization flags (already in `developability`), plus radioligand-specific: renal-retention risk (net charge, hydrophobicity — positively charged/hydrophobic peptides show higher kidney uptake [UNVERIFIED magnitude]), chelator-site impact on affinity (flag: any conjugation at the RGD-flank positions is high-risk; the dP/NMeK tail is the candidate linker site).
- **FTO section:** verdict + DoE + explicit `patents_checked: false` caveat + the *specific claims* of CA2998968 quoted, not a similarity score.

Wire it: `loop.py:optimize()` calls `dossier.build(rec, target)` for the Pareto set; output goes to `target_kb/dossiers/`.

**B. Cheapest informative wet-lab experiments (pre-registered, not ordered yet).**

- **αvβ6:** a competitive binding ELISA (the Quigley format — same assay as the A1 anchor, so results are directly comparable, no inter-assay conversion). One 96-well plate: 12 candidates × triplicate + 4-point controls (FF, YY, A20FMDV2, RGD-blank). Include 3 deliberate *predicted-weak* compounds (e.g., non-aromatic flank variants) — a model that only predicts its top picks can't fail. Total: ~12 compounds, ~$5–15k at a CRO, one round trip. Decision it buys: does our rank order match the A1-anchored physics? Spearman ρ ≥ 0.6 across the plate = the first non-circular binding signal in the program. Also run αvβ3 counter-screen on the same plate (doubles cost marginally, gives the first measured selectivity datum for our own compounds).
- **PD-L1:** a cell-based PD-1/PD-L1 blockade reporter assay (commercially standard, e.g. Jurkat-based luciferase) — 10 compounds, single concentration triage then dose–response on hits. Cheaper and more decision-relevant than SPR for a PPI blocker, because it tests *functional* blockade, not just binding.
- Both must be gated on the dossier predictions existing first — otherwise it's measurement without falsification.

**C. Radioligand-specific concerns — add to `score.py` as an informational block `radioligand(helm)`.**
- Renal retention: flag net charge ≥ +2 and mean hydrophobicity > 0.7 as elevated kidney-uptake risk; note that the c[RGDLXX] chemotype's whole design history is a fight against kidney dose. [UNVERIFIED thresholds — literature on RGD peptide renal uptake exists but I won't quote numbers I can't confirm.]
- Chelator: assume conjugation at the NMeK/dP tail (distal from pharmacophore); dossier must state "affinity assumed unchanged by conjugation — unverified" until a conjugated vs naked IC50 pair exists.
- Selectivity: αvβ3 is the *on-target-family* risk (αvβ3 expression in vasculature → off-tumor uptake); αvβ5/β8 are secondary. The dossier must carry the measured FF 2494×-over-β3 number as the bar and our predicted ratio with its (currently absent) uncertainty.

**D. Community deliverable:** package the A1+A2 SAR tables + the pre-registered prediction protocol + the availability model as a small benchmark: "αvβ6-cyclic-RGD: 10-shot SAR extrapolation + N-methyl-scan pattern prediction." That's a task the peptide-design community genuinely lacks and it's cheap to host.

## 3. THE ONE INNOVATION I WOULD BET ON

**Pre-registered, per-position falsification dossiers as the output artifact — "the dossier *is* the experiment."**

Concretely: every candidate ships with a machine-readable prediction set whose *only* purpose is to be wrong in public, scored automatically when assay data returns (`dossier.score_predictions(pred, measured)`). Prior art I know: pre-registration exists in clinical trials and (recently) in ML-for-science benchmarking; "model cards" and "datasheets" document models, not *falsifiable per-compound predictions*; prospective-computational-study papers exist but are hand-written narratives, not generated artifacts tied to a design loop. I am not aware of a design system whose loop output is a structured, auto-scored prediction ledger [UNVERIFIED — there may be internal pharma systems doing this]. SynCraft (cited in Doc 2 §2) is about synthesis edits, not falsification structure — non-overlapping.

Why defensible: it converts the program's *weakness* (no wet lab, no validated oracle) into the contribution. With n=1 validated FEP edge and 10 SAR points, you cannot claim predictive power — but you can claim a *falsification infrastructure* that the field lacks, demonstrated on a real target with real measured anchors, and the A2 N-methyl-scan pattern prediction is a genuinely hard, cheap, publishable test.

**Falsification criterion:** if, when the first plate returns, the auto-scored predictions show the system's rank order is no better than the A1-grid-mean baseline (Spearman ρ ≤ 0.2 vs ρ_baseline), the innovation has failed — the dossier machinery was decoration over a non-predictive model.

## 4. 30-DAY PLAN (no wet lab)

1. **Days 1–3 (cheap, CPU):** Build `dossier.py` + template; generate dossiers for the current Pareto set. Gate: every gated candidate has a complete dossier with zero "pending"-as-value fields (pendings must be explicit labeled absences). 
2. **Days 3–5 (cheap):** Encode A1 (2×2 grid) + A2 (N-methyl scan) + selectivity ratios into `target_kb/avb6_measured_sar.json` with citations. Gate: 100% of numbers traceable to PMID; no number without one.
3. **Days 5–10 (cheap):** Write pre-registered predictions for the A2 N-methyl scan pattern using current physics/rules (which positions break affinity when NMe'd). Gate: predictions committed with hash + date before any FEP on those edges; ≥8 positions predicted.
4. **Days 8–15 (moderate, spot GPU):** Run the restrained equilibration + unrestrained ≥1 ns metal validation (Doc 3 to-dos 4a/4b). Gate: every Mn keeps ≥2 protein/ligand O throughout; else CaDA-Mn is dead and we say so.
5. **Days 15–25 (expensive, spot GPU):** If 4 passes: re-run the YY→FF control edge with ≥3 replicas/window, ≥2 ns/window, replica exchange, against −0.95. Gate: |computed − (−0.95)| ≤ 0.5 kcal/mol with converged overlap. If it fails, the FEP tier is demoted to "unvalidated proxy" in every dossier — permanently, until fixed.
6. **Days 20–25 (cheap):** Add `radioligand()` informational block + FTO claim-text extraction (quote actual claims from CA2998968). Gate: DoE analysis references real claim language, not similarity scores.
7. **Days 25–30 (cheap):** Package the community benchmark (SAR tables + prediction protocol + availability model); draft the CRO plate spec (12 compounds, controls, ELISA format) as a *quotation-ready* document, not an order. Gate: an external medicinal chemist could read the dossier and know exactly what to order and what would prove us wrong.

## 5. STOP DOING

- **Stop calling `ddg_fep` the "trustworthy arbiter"** in code comments and reward weights (reward.py gives it weight 0.90). It is unvalidated; the weight should be 0 until the control edge passes.
- **Stop generating more candidates.** The free-position space is ~80 triples, mostly enumerated. Candidate generation is saturated; prediction quality is the bottleneck.
- **Stop the SOTA-chasing fine-tunes** (PepGLAD/UniMoMo/BoltzGen cyclic FT) — four consecutive nulls is a answered question. The generalization wall is established; more attempts burn the team's credibility budget.
- **Stop the FTO "2Nal escape" move** as a strategy — it's a one-move puzzle a claim-drafting team already solved. Divergence needs a real claim-construction analysis or a genuinely different scaffold.
- **Stop letting the manuscript narrative run ahead of artifacts.** Two corrections already needed (Doc 2 §4.1, §4.8); a third will kill the paper.

## 6. BIGGEST RISK WE ARE MISSING

**The program optimizes what it can compute, not what kills radioligands.** For an αvβ6 PDAC radioligand, the historical failure modes are not sub-nanomolar affinity — FF is already 0.17 nM and *still* needed a trimer for the intended indication. The failure modes are kidney retention, metabolic instability of the macrocycle in plasma, chelator-induced affinity loss, and tumor-to-background ratios. None of these has a single line of code, a single flag, or a single dossier field. The team could deliver a "perfect" gated candidate that is radiopharmaceutically dead, and the current `score()` would report it as the top of the Pareto set. Worse: because the reward function (reward.py) sums exactly the computable terms, any future RL loop will *systematically* optimize toward the wrong objective — reward hacking by omission, which is invisible to the placebo control because the placebo permutes the same incomplete reward.

Second, quieter risk: **the metal question may be unanswerable at the needed fidelity.** The Quigley ELISA's metal identity/occupancy is unverified (Doc 3 to-do 6); if the assay ran with Mg/Ca at MIDAS/ADMIDAS/SyMBS while the FEP assumes 3× Mn, the −0.95 anchor is being fit to the wrong physics, and no amount of replica exchange fixes a wrong reference state. Verify the assay buffer before spending GPU on step 5 — it's a literature lookup, nearly free, and it gates everything downstream.