# Integrated program plan — one calibrated verification system, built from what we already have (2026-10-26)

**Why this document exists.** The user's critique (2026-10-26): the program keeps restarting with small standalone studies instead of reusing and improving what exists, and restarts do not produce a deep contribution for a high-end journal. Correct. Much of this session retired wrong claims (necessary) but did not harvest what survived. This plan fixes that: ONE system, ONE claim, ONE evaluation, every existing asset assigned a role.

## 1. The claim (proposed — NOT yet validated)
A generator proposes cyclic-peptide candidates; a **ladder of verification tiers** checks each one; every tier is **calibrated against measured data** and **abstains when out of its domain**; the loop learns only from **verified** rewards. Claim to test: *the ladder yields shortlists with higher, calibrated precision at a stated abstention rate than the standard confidence-only pipeline, on held-out documents and receptors.*
Novelty is **UNVERIFIED** (no systematic prior-art search done on the integrated claim). Closest known pieces: sample selection/reranking for co-folding, AfCycDesign/CyclicBoltz1 (ring closure inside the model), multi-fidelity BO. "LLM + rules + computation" alone is not novel (SynCraft).

## 2. Assets → tiers (status as measured, not as hoped)
| tier | asset | measured status | gap before it can be used |
|---|---|---|---|
| T0 rules/knowledge | `acceptance_gate`, `knowledge_liability_flags`, FTO, `score.py` (target-aware rule gate) | working; tests pass; v2 panel fails H5 (no chelator Lys) | per-target rule sets (PD-L1 has none — "not applicable") |
| T1 structure | pose selector + ring-validity (`scripts/selector.py`, `stageB_eval.py`) | pilot: Boltz default 80.8 % ≈ random 80.3 % ≈ oracle 96.2 % (n=26); Stage B one-shot test generating (317 train / 117 test, 56 receptor clusters) | the one-shot result |
| T2 developability | availability (LODO ρ≈0.40), permeability (noise-ceiling + models, agent run unfinished) | availability transfers; permeability unverified | permeability verdict; applicability domains for cyclic/ncAA |
| T3 affinity | ChEMBL potency model (beats null on unseen documents: RMSE −0.125, CI −0.185…−0.069; external Kapp panel inconclusive, n=20), metal-aware FEP (CaDA-Mn passes a 1 ns structural screen: 3 Mn, 5–7 O each, ligand Asp kept in 21/21 frames) | potency model = real but modest; FEP unvalidated for ΔΔG (control edge measured −0.95 vs computed −0.18 on a metal-free pocket; rerun pending) | 10 ns × 3 replicas, YY→FF, Asp→Ala, A1 grid; calibration map computed→measured |
| anchors | **542 αvβ6 compounds / 35 ChEMBL documents (610 measurements)**, Kapp 34×6 matrix (204 cells, all re-verified), A1/A2 series | exist; used for calibration and held-out testing, never for training and testing the same claim | document-level splits only |
| optimizer | `methodology_close` verified-reward DPO + shuffled-reward placebo (+0.098, 6/6 seeds; gate was a no-op — fixed) | real but on a permeability oracle only | rerun with the integrated reward; matched best-of-N baseline |
| lessons | audit trail: circular labels, charge artifact, leakage, metal-free FEP, YAML typing, swallowed exit codes | documented | encode as automated tests (done in part) |

## 3. Evaluation (all retrospective, pre-registered, cluster/document-held-out)
- **E1 structure tier:** Stage B one-shot (running). Claim rule already fixed (A2/A3 in `PREREG.md`).
- **E2 affinity tier:** leave-document-out on the 35 αvβ6 documents: does the calibrated tier rank actives and say "unsure" correctly? Metrics: precision/enrichment at fixed coverage, calibration error, abstention curve. Nulls: per-document mean, promiscuity, 1-NN (already implemented in `integrin_chembl`).
- **E3 developability tiers:** applicability-domain checks on cyclic/ncAA peptides; permeability on source-held-out splits.
- **E4 loop:** DPO on the integrated verified reward vs matched best-of-N and shuffled-reward placebo, scored by an INDEPENDENT oracle.
- **E5 end-to-end:** shortlist precision vs abstention for {confidence-only pipeline, + T1, + T1–T3, full ladder}. This is the headline figure.

## 4. What is NOT available, stated plainly
No wet-lab data → the ceiling is a rigorous computational paper, not prospective validation. FEP is not calibrated. The integrated claim has had no prior-art search. If E2/E5 show no gain over the baseline pipeline, the honest outcome is a negative result and the program stops pretending.

## 5. Work order (no more standalone studies)
1. Finish E1 (Stage B): Spark GB10 + AWS spot generating in parallel (Spark: torch 2.14+cu130, Boltz 2.2.1, DockQ on 9CDT_2 identical to AWS T4; ~3.6 min / complex incl. one-time weights).
2. Resume permeability to a verdict (its predictions M1–M5 exist, uncommitted by the dead agent — recover and evaluate).
3. Metal/FEP: 10 ns × 3 replicas → YY→FF vs −0.95 → Asp→Ala → A1 grid; build the computed→measured calibration map (this is the only way FEP enters T3).
4. Implement the ladder interface: typed evidence + abstention + calibration state per tier (`claim_ledger`, `calibrated_reward`) — committee A/D/E/F convergent design.
5. Run E2–E5; write ONE manuscript around the result, whichever way it comes out.
6. Prior-art search on the integrated claim before any novelty wording.
