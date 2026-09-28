# Peptide Program — Parallel Work Plan (Data/Knowledge ∥ Model Building)

**Date:** 2026-09-27
**Goal:** run **missing-data/knowledge collection** and **model building** as two concurrent lanes that
converge, so neither blocks the other. Grounded in the adjudicated verdicts:
`20260927_CYCLIC_CORPUS_AND_TRAINING_STRATEGY.md` (component-split: AE=B, generator=D),
`20260925_PEPTIDE_EXECUTION_PLAN.md` (loop A1–A5), `20260926_NEGATIVE_AND_EXPERT_DATA_SOURCING.md` (3 pillars).

**Design principle:** the model lane starts *immediately* (the Tier-0 gate + AE mid-train + non-canonical
rep need only data we already have). The data lane runs in parallel, mostly **CPU/ETL (no GPU contention)**,
and its outputs feed the model lane at three defined convergence points. **The long-pole is bound cyclic
complexes (D2)** — it gates the generator's target-SFT stage, so it starts on day 1.

---

## The two lanes at a glance

```
        WEEK 1 ───────────► WEEK 2-3 ──────────► WEEK 3-5 ──────────► WEEK 5+
LANE M  M0 gate ─┬─► M1 AE mid-train ─┬─────────► M2 generator curriculum ─► M5 loop wiring
(model, GPU)     └─► M3 non-canon rep ─┴─► M4 closure ┘                        (A1+A4 on peptides)
                                                        ▲            ▲              ▲
LANE D  D0 corpus+freeze ─► D1 CREMP ────────────────┘  D2 bound cx ┘  D3/D4/D5 ───┘
(data, CPU/ETL)  D2 bound complexes (START DAY 1, long-pole) ─────────────────────►
                 D3 negatives · D4 expert · D5 physchem (parallel, feed the loop) ─►
```

Convergence points: **①** D0 (frozen eval + clean corpus) gates all training · **②** D1→M1, D2→M2-SFT ·
**③** D3/D4/D5→M5 loop.

---

## LANE M — Model building (GPU)

> **LEVERAGE THE OFFICIAL HARNESS — do NOT reinvent (CLAUDE.md rule; the M0 stochastic-recon bug was a
> reinvention symptom).** All model-lane steps call the vendored PepGLAD code in
> `research/guangzhou_all_atom/runtime/PepGLAD/`:
> - **Eval / 7-metric panel** → `cal_metrics.py` (emits DockQ, DockQ≥0.23/0.49/0.80, RMSD(CA), RMSD(full-atom),
>   Slide AAR, Sequence/Struct/Codesign Diversity, Consistency) + `evaluation/{dockq,diversity,seq_metric,rmsd,dG}`.
>   **Do not reimplement the panel.**
> - **AE mid-train (M1)** → `train.py` + `AutoEncoderTrainer` (config-driven), not a custom training loop.
> - **Generation (M2)** → `generate.py`. **Featurization** → `CoDesignDataset` + `scripts/data_process/process.py`
>   (route CREMP/bound complexes through the real processor, don't hand-build batches).
> - M0's reconstruction RMSD already equals the official `evaluation/rmsd.compute_rmsd` (un-aligned per-atom) —
>   consistent with the panel; the fix there was determinism only.

### M0 — Tier-0 go/no-go gate  ·  ✅ DONE (2026-09-28) → **GO: AE = Option B (linear-epoch221 init)**
**Result (deterministic run, 300 held-out CREMP mols):** linear-init AE reconstructs valid cyclic geometry —
**ring-closure 0.32 vs random 0.00**, **RMSD-Cα 1.05 vs 1.34 Å**; random's lower *all-atom* RMSD (2.08 vs 2.64)
was a collapsed 0-ring blob, not a better prior (decision rule corrected to key on structure validity, not
collapse-gameable all-atom RMSD). **Two findings carried forward:** (1) even the linear AE holds only **32%
ring closure** on CREMP → epoch-221 (trained on linear PepBench complexes) is **out-of-distribution on
macrocycles**, which is exactly the M1 mid-training thesis; (2) low closure → **M4 (hard cyclic-closure
constraint) must be co-developed with M1, not deferred to week 4** (see M1/M4). Cost: 2 spot runs (~30 min
each), both self-terminated cleanly. Small-mol arm skipped (no checkpoint).

<details><summary>original M0 spec</summary>

*week 1, ~1 GPU afternoon, NO new data*
Frozen-encoder linear-probe transfer matrix (committee's decisive experiment). 3 AE inits —
small-mol / linear-epoch221 / random — frozen; measure all-atom reconstruction + ring-closure validity on
held-out CREMP **and** the experimental cyclic-complex subset. Add Gemini's latent-interpolation ring-break
test. **Decides AE init** (expected: linear-epoch221 ≫ random ≫ small-mol). **Blocks M1.** Uses
`cremp_partial` (have) + epoch-221 (have) — can run before D0/D1 finish.

</details>

### M1 — Geometry AE mid-train (Option B)  ·  *week 2–3, GPU*  ·  **UNBLOCKED by M0 → GO(B)**
Mid-train the all-atom geometry AE on cyclic conformers, **init from the linear-epoch221 AE (M0 verdict)**.
**M0 finding — bring M4 forward:** the linear AE holds only 32% ring closure on held-out CREMP, so the hard
cyclic-closure constraint (M4) is **co-developed with M1**, not deferred to week 4 — M1's acceptance includes
ring-closure recovery, not just reconstruction RMSD. Use the official trainer (`train.py`/`AutoEncoderTrainer`). Sample **per molecule** (not per
conformer) to avoid CREMP correlation bias. Metrics: reconstruction, ring-closure, stereochemistry, clashes
on the **frozen** family-disjoint split. **Depends on:** M0 (init), D0 (frozen eval), D1 (full CREMP —
can start on partial). This is the not-data-starved component; highest-confidence win.
- **STRENGTH GATE (vs RINGER):** the AE latent must reconstruct/generate cyclic geometry at **≥ RINGER
  coverage-recall (79.7%)** and **ring-closure validity**, on the same CREMP held-out, *without* a separate
  SLSQP post-processing crutch if possible. A therapy-grade latent that is weaker than the public conformer
  SOTA is not acceptable — fix before M2 builds on it.

### M2 — Co-design generator curriculum (Option D)  ·  *week 3–5, GPU*
Three stages: **(2a)** keep the epoch-221 linear-complex **binding prior** as warm start (have it) →
**(2b)** cyclic mid-train in the M1 latent (penalize non-cyclic topologies; LoRA/DoRA or linear-complex
replay to avoid forgetting) → **(2c) target-conditioned SFT** on the scarce bound cyclic subset. **(2c)
depends on D2** (bound complexes) — the critical path. Report the 7-metric panel + a **modification-recovery /
chemical-validity metric** (guards against silent canonical collapse); never DockQ-only.
- **STRENGTH GATE (vs APCyc — the head-to-head):** on the **shared full-atom cyclic co-design panel** (DockQ,
  RMSD, consistency, diversity + APCyc's multi-property axes: affinity/permeability/protease/solubility),
  **match or beat APCyc** — *and* deliver the **native sidechain-ncAA (N-Me/D-AA/staple)** generation APCyc
  can't. Match-or-beat is the acceptance bar (strength check), not a novelty gate.
- **Developability tie-in (the RFpeptides caveat):** since RFpeptides reaches nM with all-canonical chemistry,
  the ncAA output must show a **developability distribution shift** (permeability/ΔPSA3D) canonical designs
  can't reach — the ncAA machinery is justified by drug properties, not a DockQ delta.

### M3 — Non-canonical representation (#1, the crown IP)  ·  *week 2–4, parallel to M1, GPU*
Chemistry-native encoding decoupling residue identity ⊥ atom template, with **modification as an explicit
conditioning channel** (N-Me flag, chirality, staple/closure bonds). Order: N-Me (`nme_v1`, have) → D-AA →
staples. **Depends on:** `nme_v1` (have) + D0 monomer canonicalization (for D-AA/staple vocab). Runs
alongside M1 — same chemistry, different objective.

### M4 — Hard cyclic-manifold closure (#3)  ·  *week 4, GPU*
Enforce hard ring-closure + valence/chirality over the non-canonical rings during sampling (PH-guidance
gradient-scale lessons already encoded). **Depends on:** M3.

### M5 — Wire the loop on peptides (A1 verify + A4 DPO)  ·  *week 5+, GPU+CPU*
Turn the built model into a closed loop: A1 verify heads (calibrated by D5 physchem + D3 negatives), A4 DPO
on the generator (D3 activity pairs + D4 expert pairs + peptide taste scorer). **Depends on:** M2 + D3/D4/D5.
This is where the pharma pains actually get solved (per the cross-reference in the execution plan).
- **STRENGTH GATE (vs HELM-BERT):** the A1 permeability/developability head must reach **≥ HELM-BERT
  scaffold-split R² (0.483)** on CycPeptMPDB (honest ceiling ~0.48–0.50) — a verify layer weaker than the
  public developability SOTA can't gate a therapy loop credibly.
- **LOOP GATE (vs no-loop + GALILEO framing):** show **developable-candidate yield lift** (7-metric panel, no
  diversity collapse) over the no-loop baseline; differentiate from GALILEO (general agent) / PEGASUS
  (HT-assay) as *a learned generator compounding on proprietary pharma data*. Prospective wet-lab lift is the
  final proof (execution-plan honest limiter).

---

## LANE D — Missing data / knowledge collection (CPU/ETL, parallel)

### D0 — Corpus assembly v1 + freeze eval  ·  *week 1, CPU — GATES ALL TRAINING*
Aggregate existing cyclic DBs into one schema **with the 4 blocking fixes**: (1) HELM2 monomer
canonicalization, (2) SMILES standardization + priority-merge dedup (exp > NMR > xTB > ETKDG), (3) conformer
provenance tags, (4) cyclic-aware split (seq-identity ≤40% + Tanimoto-MaxMin, validate median train/test
Tanimoto < 0.35 — **not** Bemis-Murcko). **Freeze the eval set first**, then assemble training from the
remainder. Output: `cyclic_corpus_v1` on S3. **This is convergence point ①.**

### D1 — Complete CREMP  ·  *week 1–2, CPU/download*
Finish `cremp_partial` → full 36,198 macrocycles / ~31.3M conformers. **Feeds M1.** Biggest structure-rich
win, no experiments.

### D2 — Bound cyclic complexes (THE long-pole — start day 1)  ·  *week 1–5, CPU+GPU-inference*
The generator's true ceiling. Two sub-streams in parallel: **(2i)** mine PDB / BioLip / Q-BioLip for
experimental bound cyclic complexes (SS-bond / head-to-tail); **(2ii)** generate bound-relevant poses via
**HighFold3 / HighFold-MeD** (native N-Me/D-AA cyclic) or Boltz/Chai-1/AF3 for CycPeptMPDB + BindingDB
peptide ligands. **Feeds M2c** (target SFT). Prioritize anything with a real receptor over more solution
conformers. **Convergence point ②.**

### D3 — Measured negatives  ·  *week 1–3, CPU/ETL, commercial-safe*
PubChem `Inactive` + Tox21/ToxCast `hitc==0` (public domain) → property/safety heads; ChEMBL/BindingDB
censored `>` + null-pchembl → activity-DPO pairs. Peptide-relevant subset where available. **Feeds M5**
(A1 heads + A4 activity-DPO). Note the peptide gap: most negatives are small-molecule — use for the shared
property heads; peptide activity pairs come from the loop over time.

### D4 — Expert signal  ·  *week 2–4, CPU/ETL*
**Peptide adaptation of the small-molecule recipe:** cyclic-peptide patents / clinical-stage macrocycles →
advanced-vs-abandoned DPO pairs (join to development phase); data for a **peptide taste scorer** (MolSkill
has no peptide analog). Within-patent hard negatives held target/era/assignee constant. **Feeds M5** (A4
expert-DPO). Internal-train only (CC-BY-SA copyleft).

### D5 — Physicochemical calibration  ·  *week 1–3, CPU/ETL*
TDC-ADME suite + AqSolDB/ESOL + Caco-2/PAMPA/MDCK + CycPeptMPDB (peptide permeability) → calibrate the
permeability/solubility/logD heads (ranking-grade → calibrated). **Best target-agnostic lever for Pain 2.**
**Feeds M5** (A1 calibrated heads) + M3/DCG-P1 (bake physchem into generation). Peptide analog of mmpdb =
residue-/monomer-level MMP over HELM.

---

## Critical path & dependencies (what gates what)

1. **M0 (gate)** — runs first, blocks M1. Cheap; do it week 1.
2. **D0 (corpus + frozen eval)** — blocks *all* training (leakage discipline). Do it week 1, in parallel with M0.
3. **D1 → M1** — full CREMP for the full AE mid-train (M1 can start on partial).
4. **D2 → M2c** — bound complexes for target-SFT. **Longest lead time → start day 1.** If D2 is thin at
   M2 time, ship M2a+M2b (binding prior + cyclic mid-train) and hold M2c until bound data lands.
5. **D3/D4/D5 → M5** — the loop needs negatives + expert + physchem; these run through the whole window and
   the loop compounds as they (and the customer's own data) accrue.

**No-GPU-contention guarantee:** Lane D is CPU/ETL + inference-only pose generation (D2ii can use a separate
spot GPU). Lane M owns the training GPUs. They don't fight for the same resource.

---

## Strength checkpoints (therapy-grade acceptance gates)

Each model milestone is judged by **therapy-grade strength vs the best public component on that axis**.
**Parity is the FLOOR, not the goal — the product has to be both strong AND genuinely innovative, or there's
no reason to build it.** Matching SOTA per axis is the entry ticket; the win is **out-resolving the hard
challenges** so we *exceed* SOTA where it counts. The innovation vectors (the resolved-challenge IP) are
expected to *beat*, not just tie: **#1 chemistry-agnostic sidechain-ncAA representation**, **#3 hard
non-canonical ring closure**, **joint co-design consistency**, **developability-conditioned generation**, and
**#4 the closed loop compounding on proprietary data**. The differentiation is the composite system *plus*
these advances — not being first in a niche, and not settling for parity.

| Milestone | Axis | Strength bar (match or beat) | Beyond-parity (the added capability) |
|---|---|---|---|
| **M1** | cyclic geometry (AE) | **RINGER** coverage-recall 79.7% + ring-closure validity | closure without SLSQP crutch; ncAA-ready latent |
| **M2** | cyclic co-design | **APCyc** full-atom panel + multi-property axes | **native sidechain ncAA** (N-Me/D-AA/staple) APCyc lacks |
| **M2** | affinity (experimental, T4) | **RFpeptides** 6–9.4 nM, canonical | ncAA → **developability shift** canonical can't reach |
| **M5** | developability head | **HELM-BERT** scaffold R² 0.483 | integrated into the live verify/loop |
| **M5** | closed loop | no-loop baseline; **GALILEO/PEGASUS** framing | learned generator compounding on **proprietary pharma data** |

## Honest gates (carried from the source docs)
- Every training step: 7-metric panel, leakage-filtered/family-disjoint splits, vs physics + simple baseline.
- **No step presents reconstruction/denoising as evidence of binding** — bound data are too limited to claim that.
- The closed loop (M5) is unproven until a **prospective wet-lab round** shows predicted→measured lift.
- Spot GPUs only (self-terminate + stream to S3); D2ii pose generation on its own spot instance.

## Immediate next actions (week 1, all parallel)
- **M0**: launch the frozen-probe transfer matrix on a spot GPU (cremp_partial + epoch-221).
- **D0**: launch corpus-assembly v1 (4 fixes + freeze eval) on CPU → `cyclic_corpus_v1`.
- **D1**: kick off CREMP completion download.
- **D2**: start PDB/BioLip bound-cyclic mining (the long-pole) + stand up HighFold3 pose generation.
- **D5**: pull TDC-ADME + CycPeptMPDB permeability for head calibration (fastest ROI).
