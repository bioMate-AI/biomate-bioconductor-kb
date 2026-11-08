# Cyclic-Peptide Design — End-to-End Process: Target → Candidate → Wet-Lab → Closed Loop

**Date:** 2026-09-30 · **Scope:** the complete dry→wet closed-loop (DBTL/DMTA) for target-conditioned
cyclic-peptide therapeutics, as run for the ACT Round-1 PD-L1 program. All stages, data artifacts, formats,
information flow, compute, and the learning loop.
**Companions:** `20260930_ACT_APPLICATION_WORKING_PROTOCOL.md` (strategy/§3 pipeline),
`20260930_PEPTIDE_GEN_IN_BIOMATE_AND_ACT_HARNESS_PLAN.md` (BioMate vs harness),
`20260721_MACROCYCLE_CLOSEDLOOP_MASTER.md` + `20260730_DRY_WET_CLOSED_LOOP_PROTOCOL.md` (loop mechanics).
**Honesty contract:** demonstrated (run, measured) vs reasoned vs forward-capability are kept distinct;
provenance is tagged on every artifact (experimental vs predicted vs computed).

---

## 0 · The loop at a glance

```
                    ┌─────────────────────── LEARN (D→ model update) ───────────────────────┐
                    │                                                                        │
   ┌──────────┐   ┌─┴────────────┐   ┌───────────────┐   ┌──────────────┐   ┌────────────┐  │
   │ STAGE 0  │──▶│  STAGE 1     │──▶│  STAGE 2       │──▶│  STAGE 3     │──▶│  STAGE 4   │──┘
   │ TARGET   │   │  GENERATE    │   │  SELECT (dry)  │   │  WET-LAB     │   │  LEARN     │
   │ prep     │   │  (Design)    │   │  gate→ΔG→perm  │   │  (Make+Test) │   │  DPO/retrain│
   │          │   │              │   │  →Pareto→12-15 │   │  synth+assay │   │            │
   └──────────┘   └──────────────┘   └───────────────┘   └──────────────┘   └────────────┘
     pocket          design pool        order sheet         measured           preference
     (structure)     (seq+struct)       (12-15 panel)       (Kd, Papp, %)       pairs → model
       │                 │                    │                   │                  │
   DESIGN ───────────── BUILD ────────────── (order) ────────── TEST ───────────── LEARN   (DBTL)
```

One turn of this loop = one **round**. Round-1 proves the loop on a de-risked target (PD-L1); each round's
wet-lab data updates the model (Stage 4), so round N+1 designs are better than round N. **The loop + the
accumulating proprietary assay data is the moat — not any single model.**

---

## 1 · STAGE 0 — Target selection & preparation

**Goal:** turn a chosen target into a machine-conditionable **pocket**.

| Item | Detail |
|---|---|
| **Input** | A target protein with a druggable PPI interface + ideally a co-crystal with a bound ligand |
| **Round-1 target** | **PD-L1** (Direction 1, de-risking anchor). Structure: **PDB 5O45** — PD-L1 IgV (chain A, 129 res) + macrocyclic peptide-71 (chain B, 14-mer), 0.99 Å |
| **Pocket definition** | receptor residues with any heavy atom **< 5 Å** of the native ligand (ncAA-inclusive), indexed 1-based over *resolved* residues (matches the generator's build order) |
| **Round-1 pocket (measured)** | 19 PD-L1 residues at the PD-1-binding face; design length range 10–16 (anchored near the native 14-mer) |
| **Producer** | `boltzgen_ourtarget.sh::build_spec` (gemmi) |
| **Data out** | target mmCIF (`<pdb>.cif`), pocket residue-index list, BoltzGen spec YAML (`entities: protein X sequence 10..16 cyclic:true + file(chain A, binding: <pocket>)`) |
| **Format** | mmCIF (structure), YAML (spec) |
| **Where** | RCSB download → instance `/specs/`, `/cifs/` → S3 `runs/<RUNID>/` |

**Information flow:** target PDB id → RCSB mmCIF → pocket residues (5 Å contacts) → generator spec.
**Gate:** non-empty pocket; resolved-residue indexing (unresolved-gap safe).

---

## 2 · STAGE 1 — GENERATE (Design)

**Goal:** sample many de-novo cyclic-peptide binders conditioned on the pocket.

Two generators run in parallel and their pools are **combined** (diversity hedge):

| Generator | Role | Method | Output |
|---|---|---|---|
| **BoltzGen** (lead, IP-clean) | primary de-novo cyclic binder + fold + 9 developability filters | AF-family folding-based design, `--protocol peptide-anything --num_designs 200–500 --budget 2` | per-design metrics + structures |
| **PepGLAD-M2c** (ours, diversity arm) | all-atom co-design latent diffusion, pocket-conditioned | frozen v1 AE + warm-started diffusion, `generate.py` sample N | orthogonal chemotypes |

| Item | Detail |
|---|---|
| **Input** | pocket spec (Stage 0) + generator checkpoint |
| **Data out (per design)** | `designed_sequence`, generated 3D structure (PDB/cif), `iptm` (interface confidence), `ptm`, `filter_rmsd`/refold-RMSD, `bb_designability_rmsd_2` (bool), BoltzGen 9-filter flags |
| **Format** | `all_designs_metrics.csv` (one row/design) + per-design `.pdb`/`.cif` |
| **Where** | S3 `runs/<RUNID>/boltzgen_targets/<pdb>/final_ranked_designs/` (metrics) + `intermediate_designs/` (structures) |
| **Round-1 measured** | BoltzGen 199-design pool: **iptm max 0.626, median 0.454, 3 ≥0.6, 176/199 designable** — PD-L1 is a hard *flat* interface (iptm ceiling ~0.63); enriched to 500 + M2c diversity arm |
| **Thresholds** | prioritize iptm ≥ 0.6 (strong ≥ 0.79); consistency ≥ 0.8; diversity ≥ 0.75 (no mode collapse) |

**Information flow:** pocket → generator → design pool (sequence + 3D structure + confidence metrics) → CSV+structures on S3.
**Provenance:** `BoltzGen_generated` / `PepGLAD_M2c_generated` (predicted, computational).

---

## 3 · STAGE 2 — SELECT (in-silico triage; the "D" of DMTA)

**Goal:** reduce the pool (hundreds) → an orderable **12–15-candidate panel**, ranked by *therapy-relevant*
objectives, cheap filters before expensive ones.

| Step | Script | What it does | Data in → out |
|---|---|---|---|
| [2] **A3 gate** (cheap) | `peptide_gate.py::gate_candidates` | RDKit-valid; SA ≤ 6.5; logPapp ≥ −7.0 floor; fail-open on missing | pool → survivors |
| [3] **designability** | (BoltzGen filters) | refold-RMSD < 2 Å; 9-filter pass | survivors → designable set |
| [4] **MM-GBSA ΔG** (expensive) | `peptide_mmgbsa_run.sh` | headless head-to-tail build + OpenMM GBn2 physics ΔG re-rank on ~50 survivors (non-circular: iptm ⟂ ΔG, ρ = −0.04); rank *within-target* (size-bias aware) | designable → ΔG-ranked |
| [5] **permeability** | `permeability_predictor.py` | logPapp (EnsembleCycPerm ΔPSA3D GBM, R²~0.45 ranking-grade) as an **objective** (not a hard reject at this maturity) | + logPapp |
| [6] **synthesizability** | (SA + cyclization feasibility) | SA ceiling + macrocyclization feasibility | + SA |
| [7] **SELECT** | `peptide_select.py::select_batch(pool, n_select=12–15)` | **Pareto-front + deterministic HVI** over affinity × ΔG × permeability × SA; **diversity preserved** (Tanimoto/ECFP4) | → **12–15 panel** |

| Item | Detail |
|---|---|
| **Property vector (per candidate)** | `{affinity_dG, permeability(logPapp), SA, safety, uncertainty}` each provenance-tagged measured-vs-predicted (the A1 verify layer's `PeptideProperties`) |
| **Output** | ranked 12–15 order sheet: id, sequence, cyclization, ΔG, logPapp, SA, iptm, diversity cluster |
| **Format** | `order_sheet.csv` / `SelectionResult` JSON + the 12–15 structures |
| **Where** | S3 `runs/<RUNID>/select/` |
| **Compute** | gate/perm/select = CPU (minutes, ~$0.10); MM-GBSA = GPU (~10 GPU-h, ~$50) |

**Information flow:** design pool + metrics → gate (drop invalid) → MM-GBSA (physics ΔG, the real discriminator
on a flat target) → permeability → **Pareto+HVI select** → 12–15 panel. **The panel is the dry-loop deliverable
(the ACT in-silico traction artifact).**

---

## 4 · STAGE 3 — WET-LAB (Make + Test)

**Goal:** synthesize the 12–15 and measure ground truth — converts predictions into the *demonstrated* loop.

| Assay | Measures | Reads out |
|---|---|---|
| **Solid-phase peptide synthesis** (IP-clean CRO, fee-for-service → IP assigns to us) | make the macrocycles | synthesized panel + yield |
| **SPR / BLI** | binding affinity to the target | **Kd / kon / koff** |
| **PAMPA** (+ Caco-2 if needed) | passive permeability | **Papp** (validates the perm model) |
| **Cell-based blockade reporter** (PD-1/PD-L1 e.g. Promega) | functional IO activity | **% blockade / IC50** |

| Item | Detail |
|---|---|
| **Input** | the 12–15 order sheet (sequences + cyclization) |
| **Data out** | measured `{Kd, Papp, %blockade, synth_yield}` per candidate + failure reasons (synthesis-failed vs no-bind vs tox) |
| **Format** | assay CSV/plate data → ingested to the property store |
| **Cost / time** | **~$15–25k, 4–8 weeks** (the parallel session's quota/cost line) |
| **Provenance** | `experimental` — this is the *only* eval-anchor-grade data (predicted structures never enter eval) |

**Information flow:** order sheet → CRO synthesis → assays → measured property vectors (with failure taxonomy)
→ ingested back to the loop. **The wet-lab-confirmed hit is the winning ACT artifact** (the in-silico panel is
the pre-application artifact).

---

## 5 · STAGE 4 — LEARN (the loop closes)

**Goal:** turn measured outcomes into a model update, so round N+1 > round N.

| Step | Script | What it does |
|---|---|---|
| **Ingest** | assay → property store | measured Kd/Papp/%blockade attached to each candidate, provenance=experimental |
| **Emit preference pairs** | `dpo_pairs.py::emit_pairs` → `to_trl_records()` | `(chosen ≻ rejected)` pairs from: verify-select verdicts, activity (binder ≻ non-binder), permeability (permeable ≻ not), expert (advanced ≻ abandoned). Output: `[{prompt, chosen, rejected}]` |
| **Retrain** | **A4 DPO trainer — TO BUILD** (emitter ready) | DPO fine-tune the generator prior on the pairs (TRL DPOTrainer recipe; algorithm not novel — **moat = the accumulating proprietary wet-lab pairs**) |
| **Also** | permeability model recalibration | measured Papp calibrates the perm GBM (ranking→calibrated) |

| Item | Detail |
|---|---|
| **Data out** | DPO pair set (versioned, provenance-tagged) → updated generator checkpoint |
| **Format** | TRL records JSON (`prompt/chosen/rejected`) → new LDM checkpoint |
| **Where** | S3 `runs/<RUNID>/dpo_pairs/` → new `ckpts/` |
| **Status** | pair-emitter ✅ ready; **DPO trainer = the one loop seam still TO BUILD** |

**Information flow:** measured outcomes → preference pairs → DPO retrain → better generator → feeds Stage 1 of
the next round. **This is the compounding step; unproven until a prospective round shows predicted→measured lift.**

---

## 6 · Data & information flow (consolidated)

| Artifact | Format | Producer (stage) | Consumer | S3 location |
|---|---|---|---|---|
| target mmCIF | mmCIF | 0 (RCSB) | generators | `runs/<RUNID>/cifs/` |
| pocket spec | YAML | 0 | BoltzGen/M2c | `runs/<RUNID>/specs/` |
| design pool metrics | CSV | 1 | gate/select | `runs/<RUNID>/boltzgen_targets/<pdb>/final_ranked_designs/all_designs_metrics.csv` |
| design structures | PDB/cif | 1 | MM-GBSA | `runs/<RUNID>/…/intermediate_designs/` |
| property vectors | JSON | 2 (A1 verify) | select | `runs/<RUNID>/verify/` |
| **12–15 order sheet** | CSV/JSON | 2 (select) | wet-lab | `runs/<RUNID>/select/` |
| assay results | CSV | 3 (CRO) | learn | ingested to property store |
| DPO pairs | TRL JSON | 4 (emit) | DPO trainer | `runs/<RUNID>/dpo_pairs/` |
| updated model | ckpt | 4 (retrain) | next-round gen | `runs/<newRUNID>/ckpts/` |

**Provenance discipline (load-bearing):** every structure carries `conformer_provenance ∈ {PDB_experimental,
NMR_experimental, xTB_CREMP, ETKDG, BoltzGen_generated, PepGLAD_M2c_generated, Boltz_predicted}`. **Predicted /
computed data is train-only; only experimental (crystal/NMR/cryoEM + wet-lab) anchors evaluation.**

---

## 7 · Compute & cost (per target / round)

| Step | Instance | Wall | ~Cost (spot) |
|---|---|---|---|
| Generate BoltzGen 200–500 | g5/g6 (A10G/L4) | 1–3 h | $5–15 |
| PepGLAD-M2c diversity arm | g5/g6 | 1–2 h | $5–10 |
| MM-GBSA verify ~50 survivors | GPU (parallel spots) | ~10 GPU-h | ~$50 |
| gate + perm + Pareto select | CPU | minutes | ~$0.10 |
| **dry compute / target / round** | | | **~$65–90** |
| **wet lab (12–15: synth + PAMPA + SPR + blockade)** | CRO | 4–8 wk | **~$15–25k** |

Infra: **spot always**, self-terminating (dead-man's-switch + instance-terminate), 60 s S3 heartbeat, AZ/instance
fallback (g5→g6→g4dn across us-west-2; multi-region on capacity crunch). All artifacts stream to S3.

---

## 8 · Execution home: research harness vs BioMate production

| | Research harness (now) | BioMate production (target state) |
|---|---|---|
| Where | `research/guangzhou_all_atom/`, standalone spot | `cyclic_peptide_design` + `bionemo_structure_design` workflows, AWS Batch |
| Invocation | bash launchers (this program) | chat/MCP → engine |
| Round-1 | **runs here (harness-first, per protocol §3)** | — |
| Productization (later) | — | reconcile BoltzGen/PepGLAD stack into the workflow + IO targeting + DMTA loop as a first-class feature + end-to-end engine validation |

**Decision (2026-09-30): harness-first for ACT traction; productize into BioMate as a separate workstream.**

---

## 9 · Go/no-go gates (per stage)

- **Stage 0:** non-empty pocket; sane design-length range.
- **Stage 1:** ≥ some designs with iptm ≥ 0.6 *or* ≥ N designable (176/199 on PD-L1) — else oversample/diversify.
- **Stage 2:** MM-GBSA ΔG separates candidates; Pareto front non-degenerate; diversity preserved.
- **Stage 3:** ≥1 measured binder (validates the loop); perm model directionally correct vs PAMPA.
- **Stage 4:** DPO retrain shows **predicted→measured lift** over the prior (the loop's proof — unproven until a prospective round).

---

## 10 · Honest limits & the moat

- **Generators are commodities/leverage** — BoltzGen (open), PepGLAD (MIT); the permeability model is ~R²0.45
  (field SOTA ~0.55). Our own generator (M2c) is DockQ 0.437, data-bound (~235 bound complexes), a diversity
  arm — not pitched as SOTA-beating.
- **PD-L1 is a hard flat target** — iptm ceiling ~0.63; the physics/developability re-rank does the selection work.
- **The moat is the closed loop + proprietary wet-lab/assay data + the resolved challenges** — no published
  end-to-end macrocycle DBTL loop exists. The compounding asset is Stage-4 data, not any single model.
- **The loop is unproven until a prospective wet-lab round shows predicted→measured lift** — that is the honest
  limiter and the ACT round-1 milestone.

---

## 11 · Round-1 status (2026-09-30)

Stage 0 ✅ (PD-L1/5O45, 19-res pocket) · Stage 1 🔄 (BoltzGen-500 + PepGLAD-M2c arm running) · Stage 2 ⏳ (gate→
MM-GBSA→perm→select, runs when pools land → 12–15 panel) · Stage 3 ⏳ (CRO, parallel-session quota) · Stage 4 ⏳
(pair-emitter ready; DPO trainer to build).
