# Drug-Development Pipeline — Definitive Per-Stage Readiness Map

**Date:** 2026-10-04 · **Purpose:** decide, per stage, what the tutorial may SHOW as working (real
output) vs. what we omit. **Rule:** we only film a stage running with real, non-stub, non-fabricated
output, or we leave it out entirely. No "gap/roadmap/not-yet" labels in the tutorial — those live
here (internal).

**Status vocabulary**
- **RUNS-LIVE-REAL-OUTPUT** — a committed, verifiable run on record (Batch or local) produced real,
  non-stub output; safe to film.
- **RUNNABLE-WITH-SETUP** — the code path is real and will produce real output, but requires a setup
  step (user input data, a container build, or a deliberate GPU-Batch run) before it can be filmed.
- **NOT-READY** — cannot produce real demonstrable output today (stub-only, unbuilt container,
  fabrication history unresolved, UI hidden, or fail-open integrity bug). Omit from tutorial.

Evidence is quoted from the sources, not inferred. Primary ground truth: the 2026-10-04 committee
reports, `20261004_AUTOLOOP_LIVE_PROOF.md`, the 2026-09-22 honesty audit, and the actual `main.nf`
code. Where the optimistic planning doc `20260417_DRUG_DEVELOPMENT_COVERAGE_ANALYSIS.md` (which marks
nearly everything "✅ internal") conflicts with the committee/honesty evidence, the later
committee/honesty evidence wins — see §Contradictions.

---

## The map

### Stage 1 — Molecule generation / design (seed → candidates)

| Field | Value |
|---|---|
| **Workflow / path** | `drug_discovery/reinvent4_lead_design/main.nf` (also `scaffold_hopping/`, `mpo_denovo_optimization/`) |
| **Status** | **RUNNABLE-WITH-SETUP** (BRICS path real & cheap; REINVENT4 path NOT-READY) |
| **Evidence** | Code: `main.nf:33-34` "GENERATE_BRICS — RDKit BRICS + medchem enumeration (SWAP-POINT…). **NOT REINVENT4 RL.**"; `main.nf:71` "'brics' — deterministic RDKit BRICS enumeration baseline (NOT learned)". Honesty audit `20260922…:18` "REINVENT4 now wired (43 tests); **no real gen run yet (x86 container unbuilt)**". Committee drug-discovery `A1 [HIGH]`: flagship over-credits REINVENT4; "in any live demo the molecules are produced by **BRICS, not a trained REINVENT4 policy**." |
| **What runs today** | Deterministic **BRICS enumeration** (seed SMILES → analogue variants scored by cheap RDKit descriptors). This is real, non-stub output. A *trained generative model* does NOT run (REINVENT4 container unbuilt, zero real gen runs). |
| **Tutorial-ready?** | Yes **if framed as rule-based BRICS enumeration** (never "REINVENT4 / trained generator"). Show seed → enumerated candidates + descriptor scores. |
| **Cost/risk** | Cheap CPU (local/Batch). |

### Stage 2 — Property / ADMET prediction (hERG, DILI, …)

| Field | Value |
|---|---|
| **Workflow / path** | `drug_discovery/predict_admet_properties/main.nf` (a.k.a. `pharmacology/predict_admet_properties`) |
| **Status** | **RUNS-LIVE-REAL-OUTPUT** ✅ (the one fully proven stage) |
| **Evidence** | `20261004_AUTOLOOP_LIVE_PROOF.md`: run `d0ff684b-…`, AWS Batch, **succeeded, rc 0, 292 s**; per-compound real numbers (terfenadine hERG IC50 **0.0124 µM**, aspirin DILI prob **0.855**). Committee drug-discovery coverage map: Stage 3a ADMET = "**LIVE** (real run `c40459b2`…; pre-run→running→completed→outputs)… Execution + downloads verified". Honesty audit `20260922…:40` "ADMET … ✅ already live + verified on dev". |
| **What runs today** | Full ADMET panel (hERG, DILI, logP, MW, oral bioavailability, AMES etc.) via Chemprop/MPNN GNNs → real per-compound values + `qc_metrics.json`/`toxicity_report.json` + downloadable report. |
| **Tutorial-ready?** | Yes — this is the anchor demo. **Caveat to honor on-screen:** predictive accuracy is not quantified ("no blanket accuracy"); the terfenadine-anchored "estimated IC50" is a heuristic, lead with the native blocker-class score; and the featured aspirin run reports **DILI = high (0.855)** — state it, don't hide it (committee H2/H3). |
| **Cost/risk** | Cheap–moderate (CPU Batch, ~5 min). Already on record. |

### Stage 3 — Molecular docking (pose + score)

| Field | Value |
|---|---|
| **Workflow / path** | `pharmacology/docking_autodock_vina/main.nf` (+ `drug_discovery/schrodinger_glide_docking`, `moe_covalent_docking`, `structure_prediction_docking`) |
| **Status** | **RUNNABLE-WITH-SETUP** (real code + honesty contract; no verified run on record) |
| **Evidence** | Code is real AutoDock-Vina with an honesty contract (`main.nf:413` "…so the gate row stays in the audit ledger **without fabricating a verdict**"). Honesty audit `20260922…:42` "a correct workflow exists (`docking_autodock_vina`); **needs one verification Batch run (blocked now on GPU spot capacity)**". Committee drug-discovery `A2`: docking is "**CODED/UNVERIFIED**", flagship's "runs on cloud & GPU" is "stronger than 'coded but unverified.'" |
| **What's missing** | One deliberate verification Batch run (receptor + ligand → pose + Vina score). Blocker is GPU/CPU spot capacity, not code. |
| **Tutorial-ready?** | Not yet. Film **only after** one real run produces a pose + score. Then it becomes showable (pose viewer + score). Do **not** narrate "runs on cloud & GPU" until that run exists. |
| **Cost/risk** | CPU-Batch (Vina is CPU); one verification run needed. |

### Stage 4 — RBFE / FEP (relative binding free energy)

| Field | Value |
|---|---|
| **Workflow / path** | `drug_discovery/openfe_rbfe/main.nf` |
| **Status** | **NOT-READY** (stub-only without GPU; recent fabrication history) |
| **Evidence** | Code: `main.nf:22-24` "A real RBFE edge needs a GPU and hours of sampling. Without a CUDA/OpenCL [device] … ddg_kcal_per_mol=null. It **NEVER fabricates a ΔΔG**"; multiple `stub:` blocks emit `ddg_kcal_per_mol: null, status: "stub"`. Honesty audit `20260922…:56-62`: the **prior** `openfe_rbfe` **fabricated ΔΔG = −1.23 kcal/mol + synthetic `np.random` convergence** until 2026-09-22; replaced with a genuine OpenFE v1.2 path but "**Real ΔΔG needs the openfe container on GPU Batch**" (never run). Committee `A2`: "OpenFE RBFE is newly real but … not run; and the prior … workflow fabricated ΔΔG." |
| **What's missing** | GPU-Batch run of the openfe container producing a real MBAR ΔΔG ± SEM. Until then every output is an explicit `null`/stub. |
| **Tutorial-ready?** | No. Omit. (A stub output showing `ΔΔG = null` is honest but is not "a stage running with real output.") |
| **Cost/risk** | GPU-Batch, hours/edge — expensive; blocked. |

### Stage 5 — Molecular dynamics (MD)

| Field | Value |
|---|---|
| **Workflow / path** | `drug_discovery/gromacs_protein_md`, `drug_discovery/amber_pmemd_md`, `drug_discovery/amber_peptide_mmgbsa`, `molecular_dynamics/mlip_md_simulation/main.nf` |
| **Status** | **NOT-READY** (no clean container; placeholder trajectory; no E2E run on record) |
| **Evidence** | `mlip_md_simulation/main.nf:45` "**No clean public biocontainer** bundles OpenMM 8 + openmm-ml + a CUDA build…"; `:109` "Emit an empty **placeholder trajectory** so the optional output channel exists." Committee drug-discovery `A2`: "MD/MM-GBSA have **no end-to-end evidence cited**." `20260920_BIOMATE_WHATS_LEFT.md:44` lists GROMACS-MD among "E2E-unverified tools (wired, never run to completion)". |
| **What's missing** | A buildable GPU MD container + one real trajectory/energy run. |
| **Tutorial-ready?** | No. Omit. |
| **Cost/risk** | GPU-Batch, long wall-clock — expensive; blocked on container. |

### Stage 6 — Multi-objective optimization / Pareto ranking (GP / MPO)

| Field | Value |
|---|---|
| **Workflow / path** | `drug_discovery/mpo_denovo_optimization/main.nf` (GP-Pareto); ranking also surfaced in the results view |
| **Status** | **RUNNABLE-WITH-SETUP** (Pareto *ranking* of a given candidate set is real; the *generative closed-loop optimizer* is a GAP) |
| **Evidence** | Code `mpo_denovo_optimization/main.nf:29` "Objectives are **REAL RDKit-computable models** … NOT stubs"; `:22-27` generator is a SWAP-POINT and "step exits 3 (honesty contract) rather than fabricating a run." Honesty audit `20260922…:46` "MPO / closed loop … ✅ **built — GP-Pareto Batch workflow, green locally**". Committee coverage map Stage 5: "**Ranking real; auto-optimizer = GAP (honestly 'written, not wired')**." |
| **What runs today** | Given a candidate set with real objective scores (e.g. from Stage 1 BRICS + Stage 2 ADMET), BioMate computes real RDKit objectives and a Pareto front/ranking. The **autonomous generative GP-MPO loop** (propose→score→re-propose) is not demonstrated. |
| **Tutorial-ready?** | Partial-yes: show **Pareto ranking of an existing candidate set** (cheap, real). Do **not** depict an autonomous multi-round optimizer improving molecules — that is unproven. |
| **Cost/risk** | Cheap CPU for ranking; GP-Pareto workflow green locally (confirm one run before filming). |

### Stage 7 — PK / PBPK modeling (NCA, allometry, PBPK)

| Field | Value |
|---|---|
| **Workflow / path** | `drug_discovery/pbpk_simulation/main.nf`, `drug_discovery/nca_pknca/main.nf`, allometric scaling; (`pk_sim_pbpk`, `simcyp_pbpk` are wrappers) |
| **Status** | **RUNNABLE-WITH-SETUP** (PBPK runs & returns real numbers but accuracy is weak; NCA needs user PK data) |
| **Evidence** | **Contradiction resolved toward "runs":** `20260723_E2E_USECASE_AUDIT_CLINICAL_PBPK.md:19` run `36f26f0c-…` "**succeeded on Batch**"; `20260827_BIOMATE_PBPK_SAME_ITEM_RESULT.md` produces real `nca_parameters.json`→`Cmax` but "**systematically over-predicts Cmax (13/15 too high)**"; `20260829_PBPK_CMAX_FIX…` same-item score **0.20→0.53**, "authoritative number pending the dev Batch same-item rerun." Committee `A4` (video-scope): written T11 says "execution … still needs a dedicated demonstration before this stage can be filmed." NCA PKNCA is marked "🔌🔌 needs in vivo PK data" (`20260417…` Stage-4 chain). `nca_pknca/main.nf` has real PKNCA R + `stub:` fallback. |
| **What runs today** | PBPK ODE simulation executes on Batch and emits real Cmax/AUC numbers (poor absolute accuracy, ~0.53 within-2-fold). NCA requires the user's concentration-time CSV to produce real output. |
| **Tutorial-ready?** | Conditional. PBPK can be shown **running with real output** if we (a) re-capture a clean succeeded run and (b) frame it as "projected exposure, accuracy not validated — not a safe-dose claim" (never "validated"). NCA: only with a real PK-data input. Safest: show PBPK exposure projection with the accuracy caveat, or omit. |
| **Cost/risk** | Cheap–moderate CPU Batch. Run exists; re-verify before filming. |

### Stage 8 — IND / regulatory report authoring (§2.6.1 narrative / DOCX)

| Field | Value |
|---|---|
| **Workflow / path** | `backend/lib/galaxy/ai/drug_discovery/feedback_router.py` (`/api/ind-report/...`); ICH M4 §2.6 DOCX assembler |
| **Status** | **NOT-READY** (UI nav hidden intentionally; integrity fail-open) |
| **Evidence** | Backend endpoints exist (`20261002_BIOMATE_LOOP_INFOFLOW_READINESS.md:48` `POST /api/ind-report/projects/{id}/edit`, `/sections/{id}/regenerate`, etc.). But `20260908_BIOMATE_THREE_PARTS…:84` flags the §2.6 DOCX assembler has **fail-opens — `ich_corpus` returns grounded=true when its PDFs are missing** (🟡). Memory [Billing hidden]: "**IND Report + CRO Library commented out** intentionally (crash); do NOT restore." Committee drug-discovery coverage map: IND/§2.6.1 = "**NOT COVERED** … absent from this [video] set." |
| **What's missing** | (1) Un-hide the UI without re-triggering the crash; (2) close the grounded=true-when-corpus-missing fail-open (risk of a plausibly-fabricated narrative) before any demo. |
| **Tutorial-ready?** | No. Omit — hidden UI + unresolved integrity fail-open make a live demo unsafe. |
| **Cost/risk** | Blocked (UI + integrity bug), not a compute cost. |

### Stage 9 — Closed-loop QC gate + auto-remediation

| Field | Value |
|---|---|
| **Workflow / path** | `experiments/autoloop_bridge` → `nextflow_executor.py` (`evaluate_and_emit`); `experiments/admet_autoloop/param_tuner.py` |
| **Status** | **RUNS-LIVE-REAL-OUTPUT** for the gate-fire; remediation is **advisory, not autonomous** |
| **Evidence** | `20261004_AUTOLOOP_LIVE_PROOF.md`: on run `d0ff684b` the gate fired live — `qc_gates` recorded `herg_ic50_uM=0.012 < 1` (halt) and `dili_risk=high` with GOLD-tier cited messages; the control run `46953d98` (safe compounds) had `qc_gates: []` ("stays silent on safe compounds and fires only on the real liability"). **Honesty limit (same doc):** "the auto-loop bridge is **reactive/advisory** … the actual re-run is a **separate deliberate call, not a fully autonomous restart**"; the live was→now param-diff payload "was not retrievable post-hoc" (served per-worker, not proxied by Node → 404). This also **supersedes the stale "gate firing UNPROVEN on dev"** caveat (committee H4). |
| **What runs today** | A real ADMET run whose GOLD hERG/DILI QC gate fires with cited thresholds and stays silent on safe compounds; `param_tuner.remediate()` deterministically proposes was→now param tightening (logp_max 5.0→4.0, mw_max 500→400). |
| **Tutorial-ready?** | Yes — film the **gate firing + silent-control contrast** + the advisory remediation suggestion. Must say remediation is an **advisory suggestion, the re-run is a deliberate user action**, not an autonomous closed loop. |
| **Cost/risk** | Cheap (piggybacks on the Stage-2 ADMET run already on record). |

---

## (A) READY TO SHOW WORKING NOW — cheapest first

1. **Stage 2 — ADMET panel (hERG/DILI/logP/oral)** — real run `d0ff684b` on record; the anchor demo. Cheap CPU. *(Carry the no-accuracy + DILI-high caveats.)*
2. **Stage 9 — QC gate fire + silent-control + advisory remediation** — same run; free. *(Say "advisory, not autonomous.")*
3. **Stage 1 — BRICS enumeration (seed → candidates)** — cheap CPU. *(Call it rule-based enumeration, never REINVENT4/trained generator.)*
4. **Stage 6 — Pareto ranking of an existing candidate set** — cheap CPU; chains naturally off Stages 1+2. *(Ranking only — not an autonomous optimizer.)*

These four chain into a single honest journey: BRICS seeds → ADMET scores → Pareto ranking → QC gate fires → advisory remediation. All real, all cheap, all on CPU.

## (B) SHORT EFFORT FROM READY (effort named)

1. **Stage 3 — Docking (Vina)** — effort: **one verification CPU/GPU-Batch run** (receptor+ligand → pose+score). Code real with a no-fabrication contract; blocker is spot capacity, not code. Film after that run.
2. **Stage 7 — PBPK exposure projection** — effort: **re-capture one clean succeeded Batch run** (a succeeded run already exists, `36f26f0c`) and frame as "projected, accuracy-not-validated." NCA sub-stage needs the user's PK-data CSV. Showable with that framing; omit if we won't carry the accuracy caveat.

## (C) CANNOT BE SHOWN YET — omit from tutorial, track internally

1. **Stage 4 — RBFE/FEP** — stub-only without GPU (`ddg = null`); recent fabrication history (−1.23 kcal/mol synthetic ΔΔG, fixed 2026-09-22 but never re-run). Needs a real GPU-Batch openfe run.
2. **Stage 5 — MD (GROMACS/AMBER/MLIP)** — no clean container, emits placeholder trajectory; no E2E run on record. Needs a buildable GPU container + one real trajectory.
3. **Stage 8 — IND/§2.6.1 DOCX** — UI nav intentionally commented out (crash) AND a `grounded=true`-when-corpus-missing fail-open (fabrication risk). Needs both fixed before any demo.
4. **Stage 1 (REINVENT4 branch only)** — trained generator; x86 container unbuilt, zero real gen runs. The BRICS branch covers Stage 1 for the tutorial; do not invoke REINVENT4.
5. **Stage 6 (autonomous generative GP-MPO loop only)** — "written, not wired"; the ranking sub-capability is in list (A).

---

## Contradictions flagged & reconciled

1. **"docking/RBFE/GP-Pareto are real tested" (memory/`20260417` coverage doc) vs committee "not demonstrated."**
   - *Reconciliation:* the `20260417_DRUG_DEVELOPMENT_COVERAGE_ANALYSIS.md` diagram marks almost everything "✅ internal" — it is an **architecture/intent map, not an execution record**, and predates the fabrication discovery. The code + 2026-09/10 evidence show: **docking** = real code, *no verified run* (RUNNABLE-WITH-SETUP); **RBFE/FEP** = stub-without-GPU + **fabrication history** (NOT-READY); **GP-Pareto** = ranking real/green-locally, generative loop not wired. The committee "not demonstrated" wins for the *video claim*; "real tested" was over-stated. Only **ADMET** and the **QC gate-fire** have committed real-run evidence.
2. **Generator identity: flagship "REINVENT4 (4 learned modes)" vs T1/code "BRICS, rule-based."** Code is decisive: `GENERATE_BRICS … NOT REINVENT4 RL`; REINVENT4 is an unrun SWAP-POINT. **BRICS is what runs.** (Committee H1/A1 BLOCKER.)
3. **FEP "newly real" (honesty audit) vs "stub/null" (code).** Both true: the code was *rewritten* to be genuine **and** honest (returns `null`, never fabricates) — but it still **cannot produce a real ΔΔG without a GPU run that has never happened**. So: real code, NOT-READY output.
4. **PBPK "demonstration pending" (committee/T11) vs "succeeded on Batch" (`20260723`).** Reconciled: PBPK **does execute and returns real Cmax/AUC** (so it is RUNNABLE, not stub) — the "pending" refers to a *film-ready* user-journey + the **weak accuracy** (~0.53 within-2-fold, systematic over-prediction). Showable only with an explicit accuracy caveat.
5. **"QC gate firing UNPROVEN on dev" (flagship caveat) is STALE.** `20261004_AUTOLOOP_LIVE_PROOF.md` proves it fired live (`d0ff684b`). Upgrade to "fires live; remediation advisory" (committee H4).

---

## Change log
- 2026-10-04 — created from committee reports, AUTOLOOP_LIVE_PROOF, 2026-09-22 honesty audit, the
  `main.nf` source, and PBPK/NCA run docs. Read-only evidence pass; no workflow or tutorial files
  edited.
