# Governed self-improvement for cyclic-peptide binder design: a verifier-ladder protocol and the leakage controls that separate capability from artifact

**Author:** Yaoyun Zhang (BioMate / Guangzhou all-atom cyclic-peptide program)
**Date:** 2026-10-28
**Status:** `PREPRINT DRAFT — v1 (computational; no wet-lab validation — wet lab is v2). Awaiting author final review before submission. Not for external distribution.`

> **TOPOLOGY — DECIDED (two papers, cross-referenced; user approval 2026-10-28).** This is
> **Paper B (evidence standard; companion)**: the governance contribution — the verifier
> ladder + biology-structured leakage firewall and the catalogue of artifacts it caught
> (§5, now incl. the §5.6 additions). **Paper A (method; lead)** is the own-method
> contribution — knowledge-constrained, novelty-controlled closed-loop design (framework +
> all-atom LM + KN-1/KN-2 + within-source loop), drafted at
> `docs/20261027_PREPRINT_V1_PUBLIC/manuscript_knowledge_novelty.md` (owned by the method
> session — not edited here). Shared artifacts are defined once in Paper A and cited here.
> The RSI spine is `docs/20261027_BIOMATE_NATIVE_RSI_THESIS.md` (SRVL); component benchmarks
> live in `docs/20261021_CYCLIC_LLM_PAPER_DRAFT.md`; the split rationale and reconciliation are
> in `docs/20261028_RECONCILIATION_NOTE_peptide_manuscripts.md` §D. See the handoff
> `docs/20261028_HANDOFF_cyclic_peptide_RSI_manuscript.md`.

---

## Abstract

De novo cyclic-peptide binder design is data-starved — only low hundreds of bound cyclic
co-structures exist — which makes a *self-improving* design loop attractive: generate, score
against increasingly expensive verifiers, synthesize the best, assay them, and retrain on the
result. The danger is that in a data-poor regime such a loop most readily improves its own
*apparent* score by fitting artifacts, not biology. We present a cyclic-peptide design loop built
as **governed recursive self-improvement**: a four-stage Design→Verify→Select→Learn cycle whose
reward is a **cost-ordered verifier ladder** (L0 free deterministic gates → L1 real execution →
L2 in-silico physics: co-folding, MM-GBSA, relative FEP → L3 wet-lab assay), and whose promotion
of any learned change is gated by a **biology-structured leakage firewall** (held-out *target*,
*scaffold*, *assay*, not held-out instances). Our central result is **not** a performance win —
the loop is presently computational-only and cross-target generalization is unsolved. It is that
**the governance did its job**: the firewall caught three improvements that looked real and were
not — (i) a display-enrichment selector that beats sequence-composition baselines but **not an
abundance null** (the label is abundance-circular) and whose apparent signal is in part **family
memorization** (a trivial k-mer logistic matches it on random splits and both collapse under
family-disjoint splits); (ii) a renal-clearance cross-target signal
(Spearman ρ = 0.27, p = 0.036) traced to a **charge-feature bug** and retracted to null-to-negative
(ρ = −0.26, p = 0.11); and (iii) a metal-dependent **relative-FEP** result invalidated by a
box-centering frame bug that left the catalytic Mn²⁺ ions 30–37 Å outside the pocket for the entire
alchemical leg, plus a control edge that *missed* a measured −0.95 kcal/mol by ~5× — and it flagged
a fourth, a permeability retro-loop, as a **pooled-source confound** (78 % of the top decile from one
source) whose honest **within-source verdict is still pending** a pre-registered re-run. We argue the
evidential contribution of a self-improvement system in a data-poor science is its **refutation
machinery**, and we pre-register the single prospective closed-loop round — with completed
leave-one-target-out and re-validated physics — that would constitute the first honest RSI datapoint
(v2). The protocol and verifiers are built; the measured RSI result is future work. This paper is
the evidence-standard **companion (Paper B)** to a method paper (**Paper A**: knowledge-constrained,
novelty-controlled closed-loop design) with which it shares artifacts and cross-references.

---

## 1. Introduction

Cyclic and macrocyclic peptides engage flat protein–protein interfaces that small molecules miss.
Modern generators (BoltzGen, RFpeptides) produce pocket-conditioned designs, but the hard, open
problem is **cross-target generalization** — binders for a target unseen in training — where honest
hit rates sit in a low single-digit-to-~8% regime, and the obstacle is data: per-target structural
and affinity labels are scarce and expensive.

A self-improving loop is the obvious response: let the system propose designs, verify them, synthesize
and assay the survivors, and retrain on what comes back, so capability compounds. But a loop that
scores its own proposals and then trains on those scores is exactly the setting in which **reward
inflation** is easiest: in a data-poor regime the cheapest way to raise an apparent score is to fit a
confound that correlates with the label, not the biology. Every surveyed self-improving-agent system
guards against this with *empirical validation on held-out data*; in a lab-coupled science the
held-out axis must be *biological* (a target, a chemical scaffold, an assay), because that is the
dimension in which a claim must generalize to matter.

This manuscript reports a cyclic-peptide design loop built as **governed RSI** and makes a deliberately
inverted claim. We do not report that the loop improves hit rate — it does not yet; the loop is
computational-only and cross-target transfer is null in our leakage-controlled tests. We report that
the **governance works**: the verifier ladder and the biology-structured firewall *caught* three
candidate improvements that passed naive checks and were artifacts. In a field where positive results
from under-powered, confound-rich loops are the norm, a demonstrated refutation machinery is the
contribution, and it is the precondition for any later performance claim being believable.

## 2. The loop

A four-stage cycle (tooling in parentheses; full spec `docs/20260930_CYCLIC_PEPTIDE_END_TO_END_PROCESS.md`):

- **Stage 0 — Target prep.** RCSB mmCIF → pocket = receptor residues < 5 Å of native ligand → design
  spec (`boltzgen_ourtarget.sh`, gemmi).
- **Stage 1 — Generate.** De-novo cyclic binders: BoltzGen (`--protocol peptide-anything`), a PepGLAD
  all-atom co-design diversity arm, and our own enrichment-trained cyclic-peptide LLM
  (`cyclic_llm/`, HELM/SMILES).
- **Stage 2 — Verify (the ladder).** L0 cheap gates (`peptide_gate.py`: RDKit validity, SA ≤ 6.5,
  logPapp floor, PAINS/liability, FTO) → designability (BoltzGen 9-filter + refold-RMSD < 2 Å) →
  L1/L2 co-folding (`launch_cofold_v2.sh`) → L2 MM-GBSA ΔG (`peptide_mmgbsa_run.sh`, OpenMM GBn2;
  metal-aware Li-Merz Mn²⁺ for αvβ6) → permeability objective (`permeability_predictor.py`) → L2 FEP
  (GROMACS CaDA-Mn, AWS Batch spot) → L3 wet-lab assay (CRO SPPS → SPR/BLI, PAMPA, cell blockade).
- **Stage 3 — Select.** Pareto-front + deterministic hypervolume over affinity × ΔG × permeability × SA
  with ECFP4/Tanimoto diversity → 12–15-member panel (`peptide_select.py`).
- **Stage 4 — Learn.** Synthetic/real KD → preference pairs (`dpo_pairs.py`, `wetlab_kd_to_pairs.py`)
  → TRL DPO retrain of the generator prior; the physical arm is the self-driving lab harness
  (`/Users/kky/sdl-macrocycle`, software built, hardware pending).

## 3. The verifier ladder (L0 → L3)

| Tier | Verifier | Cost | Gameability | Status |
|---|---|---|---|---|
| **L0** | PAINS/medchem/liability, validity, SA, FTO, ring/acceptance gates | free, instant | deterministic | **live** |
| **L1** | real execution (AWS Batch, terminal + S3 evidence) | minutes, $ | low | **live** (cofold currently bypasses Batch) |
| **L2** | cofold confidence; MM-GBSA (GBn2); relative FEP (CaDA-Mn) | hours, $$ | model-dependent | MM-GBSA **live (ranking-grade)**; **FEP built but masked — unvalidated** |
| **L3** | wet-lab SPR/BLI (Kd), PAMPA (Papp), cell IC50 / expert sign-off | weeks, $$$ | **physical — non-gameable** | **not live** (hybrid, in program) |

Escalation is cost-aware: a proposal must clear L0 for free before it spends L1, and only Pareto-selected
survivors reach L2; L3 is reserved for a single curated panel. The physical L3 rung is what makes the loop
*governed* rather than self-referential — a wet-lab Kd cannot be reward-hacked by the policy that proposed
the peptide — but it is slow and expensive, so the loop today runs L0–L2 only and L3 is the v2 arc.

## 4. The leakage firewall

The one non-negotiable rule (encoded in `evaluation/scorers/rsi_scorer.py`): **a learned change is
promoted only if its gain shows on data it was not derived from, split along a biological axis** —
held-out target (leave-one-target-out), held-out scaffold (Bemis-Murcko, not just new molecules of a
seen series), held-out assay — and scored against a degree/abundance-matched null, never raw gold. Code
self-improvement holds out task instances; here "improved" must mean *generalizes in the biological
dimension that matters*, because our domain's correlations (charge, abundance, source, chemotype) are
treacherous. §5 is what this firewall rejected.

## 5. Results — the governance caught three artifacts (and flagged a fourth as a pending confound)

The evidential contribution. §5.1–5.3 are candidate improvements that passed a naive check and were
refuted by a firewall control; §5.4 is a fourth whose pooled result is a confound and whose within-source
verdict is still pending a pre-registered re-run. Provenance to the committed artifact in each case.

### 5.1 Selector gain that does not clear an abundance null
The enrichment-trained LLM selector ranks held-out PADI4 binders at AUC 0.951 and **beats every
sequence-composition baseline** (2-mer logistic 0.864; +0.077 on the motif-distinct subset), and the gain
is not near-duplicate leakage (3-mer Jaccard < 0.5 inflation −0.011). But the `is_binder` label is
essentially a threshold on display enrichment, so a trivial read-count/enrichment sort scores **AUC ≈ 1.0
on all four targets, and the LM beats it on none** (LM 0.266–0.997; below chance on hPCSK9). *Refuted as a
deployable capability:* within-target "wins" are abundance-circular; a real claim needs a non-circular
affinity label on novel sequences. **The apparent gain is also in part family memorization:** a trivial
k-mer logistic regression matches the LM on random splits (Abeta42 0.986 vs 0.990; hIAPP 0.698 vs 0.689)
and both collapse under family-disjoint splits (hIAPP 0.52, FIKK13 0.42); PADI4 is the exception
(0.865/0.864 vs LM 0.968, and that comparison is not like-for-like). (`docs/20261021_CYCLIC_LLM_PAPER_DRAFT.md`,
`20261021_CYCLIC_LLM_WITHIN_TARGET_SOTA_BENCHMARK.md`, `docs/20261027_SELECTOR_LEAKAGE_AUDIT.md`,
`cyclic_llm/results/leakage_audit_*.json`.)

### 5.2 A renal cross-target signal that was a charge-feature bug
An earlier cross-target renal-clearance transfer was **significantly positive: Spearman ρ = 0.27,
95% CI [0.01, 0.51], p = 0.036.** The firewall traced it to a feature bug: a free N-terminal α-amine
(~+0.8 charge) was counted on peptides whose α-amine is actually amide-conjugated to a chelator — a
**target-class-correlated over-count** that manufactured apparent transfer. After correction:
**ρ = −0.26, CI [−0.55, +0.09], p = 0.11 (null-to-negative)**, and all four pre-registered improvement
analyses null. *Refuted and reported as a methodological cautionary finding.*
(`docs/20261022_RENAL_PREDICTOR_MANUSCRIPT.md`.)

### 5.3 A metal-FEP result invalidated by a frame bug
Relative FEP for the metal-dependent αvβ6 MIDAS pocket appeared to run. The firewall's build-time
coordination check found that `editconf -c` rigidly re-centered the receptor+peptide but the three CaDA-Mn²⁺
ions were appended with un-translated coordinates → **all three Mn were free ions in bulk water 30–37 Å from
the pocket for the entire alchemical leg; the MIDAS site was metal-free.** The prior "equilibration
acceptance" had only checked peptide amide geometry. Independently, the YY→FF control edge computed
**−0.18 ± 0.15 vs a measured −0.95 kcal/mol — sign-correct but ~5× too small, a miss, on a then-metal-free
pocket.** *Refuted: FEP is masked from every reward pending the fix (metals translated with the receptor +
a coordination gate, `validate_mn_coordination.py`, fixed 2026-10-25) and a 10 ns × 3-replica re-run with
re-computed controls.* A 1 ns continuation passed a **structural-stability screen only** — explicitly "screen
≠ metal model validated." (`docs/20261025_CADA_MN_METAL_MODEL_VALIDATION.md`.)

### 5.4 A permeability-loop gain whose pooled outcome is confounded (within-source verdict pending)
A learned permeability retro-loop added +260–347 hits per 500 picks. The **pooled top-decile outcome is
confounded**: 557 of 711 hits (78 %) come from a single source (2013_CHUGAI), and the N-methyl-count
baseline that recovers 70–83 % of the yield draws **98.5 % of its own hits from that same source**. What is
therefore established is a pooled-source confound, **not** a refutation of learning: whether the loop learns
*within* a source is not yet known — the pre-registered within-source re-run (L3, 420 tasks) is still
running. *Reported as a pooled confound with the within-source verdict pending.*
(`research/guangzhou_all_atom/loop_retro/results/`, `loop_retro/PREREG_LOOP.md` L3,
`docs/20261027_PROGRAM_STATUS_VERIFIED.md`.)

### 5.5 Honest measured bounds (what survives)
- **Binding-affinity ML** (28,875 clean cyclic rows, ECFP4+physchem): random-split R² ≈ 0.52 / Spearman 0.71;
  **novel-target (PD-L1+αvβ6, n=327) R² = 0.18–0.26, Spearman 0.42** — "real but modest." (`results/binding_model_metrics_cyclic.json`.)
- **Permeability**: scaffold-R² = **0.231** (leak-free Bemis-Murcko, n=8466) — ranking-grade only, below the
  field's ~0.48–0.55. (`results/permeability_predictor_metrics.json`.)
- **Cross-target generalization: NULL** — our LOTO (v3/v3.1) null in all folds; predictor 0.74 → 0.18 held-out;
  BoltzGen cyclic-FT LOTO smoke Δiptm = −0.16 (worse), full LOTO pending. Matches the field bound (~3.3% honest
  confirmed hit). (`docs/20261006_CYCLIC_LLM_V3_CROSSTARGET_RESULTS.md`, `…V3_1_MULTITARGET_RESULTS.md`.)
- **Closed loop: synthetic only** — DPO ran on simulated KD (`results/SIMULATED_closed_loop_20261003/`,
  `data_origin: simulated`, "no biological or generalization claim").

### 5.6 Additional firewall catches (pre-registered nulls and pipeline integrity)
Four further catches from the companion program, each the firewall or an integrity check refusing a result
rather than publishing it:
- **Pose selector for co-folding — primary claim not supported.** A pre-registered one-shot test on 104
  post-cutoff complexes: the learned selector scores **59.6 %**, which does **not** beat the strongest single
  baseline (`if_plddt` / `ring_strain` at **60.6 %**), and leaves most of the oracle headroom uncaptured
  (oracle **76.9 %**; +19.2 pp over the 57.7 % default unachieved).
  (`multitarget/cyclic_complex_benchmark/PREREG.md`, `results/stageB_eval_S2.json`.)
- **Pipeline integrity — non-canonical residue handling.** `parse_helm` silently dropped / mis-mapped
  non-canonical residues; impact was bounded (no earlier verifier tier changed its verdict) but the bug would
  have corrupted ncAA designs. (`docs/20261027_PARSE_HELM_NCAA_BUG.md`.)
- **Pipeline integrity — empty outputs counted as successes.** The co-folding model wrote zero-byte / atom-less
  sample CIFs while exiting 0; the driver counted files, not *valid* files. Now rejected at source so corrupt
  complexes are never published. (commit `6ee3c1a65`.)
- **KB-rule validation against measured permeability.** The N-methyl-count heuristic holds *within* a laboratory
  in 7 of 8 datasets but with modest effect — a rule admitted as advisory, not as a hard gate.
  (`docs/20261027_KB_RULE_VALIDATION.md`.)
These are the §B additions that extend this companion paper beyond the three headline refutations.

## 6. Pre-registered prospective test (the first honest RSI datapoint — v2)

A single prospective round, pre-registered here, would convert the design into a measured result:
1. **Complete leave-one-target-out** for the generator and the binding/permeability predictors (beyond the
   current smoke scale) and report transfer with CIs on held-out targets/scaffolds.
2. **Re-validate L2 physics**: metal-correct FEP, 10 ns × 3 replicas, re-run the YY→FF (−0.95) and ≥2 further
   measured control edges; admit FEP to the reward only if it recovers measured ΔΔG within stated error.
3. **One prospective closed-loop round** (v2, wet lab): design a 12–15 panel for a held-out target under the
   frozen ladder, synthesize via CRO, assay (SPR/PAMPA/cell), and test the pre-registered hypothesis that the
   *post-feedback* generator proposes binders that beat the *pre-feedback* generator **on a different held-out
   target** — the firewall condition. A positive result there, and only there, is the first RSI datapoint.
Success/failure criteria, panels, and nulls are frozen before synthesis; no metric is chosen post hoc.

## 7. Related work
Self-improving agents (DGM, SICA, Harness2, ScienceBuddy) supply the engine but validate on software
benchmarks with iid held-out; the Darwin–Gödel Drug Discovery Machine (bioRxiv 2025) ports evolutionary
self-improvement to drug discovery. Multi-fidelity molecular generation (MFBind), verifiable-reward molecular
RL, and LLM peptide agents (PepThink-R1) overlap the components. **Novelty is UNVERIFIED** (abstract-level
prior-art check only); the contribution we stand behind is evidential — the governed-loop protocol and the
biology-structured firewall demonstrated by the three refutations of §5 — not architectural priority. A direct
prior-art pass is required before submission.

## 8. Limitations
The structural data wall (low-hundreds of cyclic co-structures, "effectively unbreakable by acquisition");
cross-target generalization unsolved (field-wide and ours); the closed loop is synthetic-only; permeability is
ranking-grade (R² 0.23); FEP is uncalibrated and masked; within-target "wins" are partly confounded; the RSI
claim is a **design, not a measured result** (claiming otherwise would be the exact leakage inflation §4
forbids — the §5.1–5.3 artifacts, the §5.4 pending confound, and the retracted decomposition_v2 0.73→0.016 are the cautionary tales);
targets GRPR and PD-L1 are out-of-scope / de-risking anchors, αvβ6 is the lead.

## 9. Conclusion
In a data-poor science, the value of a self-improving loop is first measured by what it **refuses to believe**.
We built a cyclic-peptide design loop as governed RSI — a cost-ordered verifier ladder with a physical top rung
and a biology-structured leakage firewall — and its demonstrated contribution is that the firewall caught an
abundance-circular selector, a charge-artifact cross-target signal, and a metal-blind FEP result before any of
them could be trained on or published. The pre-registered prospective round that would make the RSI claim
positive is specified; it is future (v2) work.

---

### References (to complete to house style; author/title/year for verifiability)
- Darwin–Gödel Drug Discovery Machine, bioRxiv 2025.08.21.671415; Zhang et al. Darwin Gödel Machine, arXiv:2505.22954; Robeyns et al. SICA, arXiv:2504.15228.
- BoltzGen / BoltzProt-1; RFpeptides; Boltz-2; PepGLAD; CycPeptMPDB; MFBind; PepThink-R1 (direct citations required pre-submission — `docs/20261001_CYCLIC_PEPTIDE_SOTA_LANDSCAPE.md`).
- Quigley et al. 2023 (YY→FF macrocycle, PMID 38099056).

### Internal provenance (not for external version)
Component drafts to MERGE: `docs/20261021_CYCLIC_LLM_PAPER_DRAFT.md`, `docs/20261022_RENAL_PREDICTOR_MANUSCRIPT.md`. Program plan: `docs/20261026_INTEGRATED_PROGRAM_PLAN.md`. RSI spine: `docs/20261027_BIOMATE_NATIVE_RSI_THESIS.md`. Ground-truth status: `docs/20261027_PROGRAM_STATUS_VERIFIED.md`. Physics: `docs/20261025_CADA_MN_METAL_MODEL_VALIDATION.md`. Results: `research/guangzhou_all_atom/results/{binding_model_metrics_cyclic,permeability_predictor_metrics,avb6_metal_mmgbsa_gate,boltzgen_loto_smoke_summary,speed_surrogate_loto}.json`, `SIMULATED_closed_loop_20261003/`. SDL: `/Users/kky/sdl-macrocycle/README.md`.
