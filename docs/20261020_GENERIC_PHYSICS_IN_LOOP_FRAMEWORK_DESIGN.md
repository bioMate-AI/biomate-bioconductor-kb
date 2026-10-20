# Generic physics-in-the-loop design framework — design & refactor plan

**Date:** 2026-10-20 · **Status:** design (no code change) · **Scope:** turn the αvβ6 FEP + closed-loop
work into GENERIC BioMate platform capabilities (any target / modality), with αvβ6 as instance zero.

**Why this doc exists.** The user's product direction: *"we are selling the platform, the platform should
have a generic framework for what we are doing."* The αvβ6 pipeline must not remain a bespoke set of
research scripts; it must become capabilities a customer invokes through BioMate. This doc audits what
BioMate already has, then specifies the generic framework as three platform layers and the concrete
refactor from the current code. It follows the repo principle *"BioMate IS the execution engine"* and
*"audit capabilities first — the gap is usually wiring/selection, not missing primitives."*

Honesty: this is a design, not a claim of a finished framework. Where an αvβ6/Mn/cyclic assumption is
load-bearing, it is marked **[load-bearing]**. "Generic" is used only where the design actually generalizes.

---

## 1. Audit — what already exists (read, not assumed)

### 1.1 Catalog RBFE workflow — `openfe_rbfe` (SMALL-MOLECULE ONLY)
- **File:** `backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/openfe_rbfe/main.nf`
  (entrypoint `bin/run_openfe_rbfe.py`, referenced at `main.nf:258`).
- **DB:** two rows in `backend/database/galaxy_ai_tools.db` — `name="OpenFE Relative Binding Free Energy
  (RBFE)"` and `name="openfe_rbfe"`, both `domain=drug_discovery`, `step_count=5`,
  `docker_image=…/biomni/biomni-tools:x86` (the short row) / ECR `…/biomate/openfe-rbfe:1.0` (in the .nf).
- **What it takes:** `params.receptor` (protein PDB) + `params.ligand_a` + `params.ligand_b` (**SDF**),
  `params.mode ∈ {setup, smoke, production}`, `temperature`, `equilibration_ns`, `production_ns`,
  `lambda_windows`, `protocol_repeats`, `max3d`, `validate`.
- **What it is:** real OpenFE SepTop/RBFE on OpenMM 8 — `SmallMoleculeComponent` + **LOMAP MCS atom-mapping**
  between two **congeneric small molecules**, OpenFF Sage 2.2 ligand FF, PDBFixer/ff14SB protein prep,
  MBAR (Cinnabar) → per-edge ΔΔG ± SEM. Processes `PREP → RBFE_SETUP → OPENFE_ANALYSIS`.
- **Honesty contract** (in `bin/run_openfe_rbfe.py`, not the .nf): no CUDA/OpenCL → `status='requires_gpu'`,
  `ddg_kcal_per_mol=null`, never fabricates a ΔΔG or overlap matrix.
- **QC gate:** `openfe_cycle_closure`, emitted in `qc_metrics.json` and keyed by the QC trace monitor off
  `("OPENFE_ANALYSIS", "*", "qc_metrics.json")`.
- **Cannot do** — the core finding: no **residue-mutation** edges, no **peptide / cyclic-peptide** edges,
  no **metal-bridged** sites. OpenFE's small-molecule component + LOMAP MCS + OpenFF ligand FF have no path
  for "mutate residue 1 Tyr→Phe on a cyclic peptide" or a dummy-cation MIDAS Mn. That is exactly the αvβ6
  control edge, and it is pmx/GROMACS territory, not OpenFE.

### 1.2 How a workflow is invoked generically
- **Entry:** `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py::execute_nextflow(request)`
  (`:5509`). `request` carries `nextflow_path` + a `params: dict`. `_resolve_nextflow_path` (`:1508`)
  resolves the `.nf`; `_choose_container_strategy` (`:3152`) picks the image by path prefix
  (`biomni_nf/`, `nfcore/`). Params are staged/validated (`_validate_input_paths` `:2390`, bare-upload-key
  normalisation `:2423`).
- **Routing:** the composer / chat routes intent → `/api/ai_assistant/generate_workflow` → a `workflow_ga`
  object (`name`, `nextflow_path`, `required_params`, `optional_params`, `steps`) → `execute_nextflow`.
  **Takeaway:** a new catalog capability is reachable by customers as soon as it is (a) a `.nf` at a
  resolvable `nextflow_path`, (b) a DB row with a `params_schema`, (c) routable by the composer. No new
  execution primitive is needed — this is wiring.

### 1.3 Execution-verified reward substrate (ALREADY ~GENERIC)
- `evaluation/local_trial/execution_grader.py`: `CONTRACTS` = a **dict keyed by `workflowName`**
  (`required_outputs`, `json_keys`); `TIERS` ladder (`crashed < no_outputs < empty_outputs <
  missing_required < content_invalid < pass`); `grade_detailed(run, deep) → (verdict, reason, tier)`.
  Objective — terminal success + S3 output facts, no similarity, no LLM. **Adding a workflow = one dict entry.**
- `evaluation/local_trial/graded_run_store.py`: `TIER_REWARD` (monotone), `reward_for_tier`, SQLite
  `graded_runs` store (`record` / `get_reward` / `rewards(campaign)`), and `run_from_outputs(...)` —
  described in-code as *"the generic seam the closed loop uses to hand a finished run to grading."*
- `research/guangzhou_all_atom/cyclic_llm/loop_grade_bridge.py`: `record_scored_run` / `record_round`;
  a `WORKFLOW = {cofold→cyclic_peptide_cofold, mmgbsa→cyclic_peptide_mmgbsa, assay→cyclic_peptide_assay}`
  map — the **mechanism is generic, only this map is cyclic-named**.
- **Existing contracts:** `merfish_spatial_analysis`, `Predict Admet Properties`, and the three
  `cyclic_peptide_*`. These are examples, not hard dependencies.

### 1.4 The αvβ6 pipeline — what is reusable vs target/Mn/cyclic-specific
| Component | File | Reusable mechanism | αvβ6/Mn/cyclic-specific |
|---|---|---|---|
| Closed-loop driver | `cyclic_llm/loop_batch.py::run_round(candidates, target, submit, round_id)` | propose→dispatch→score→select→revise; already takes `target` | `target="avb6"` default; peptide/HELM modality (`fto_score._backbone`); needs a per-target `target_spec`; `loop.revise` is a symbolic stand-in |
| Cofold dispatch | `cyclic_llm/physics_batch.py::dispatch_cofold` | Boltz job-def `boltz-snat2-direct`, spec-derived input, `dry_run` default, metal = `cofactors` | input builder `target_spec.build_cofold_input` is peptide+receptor+cofactor shaped |
| FEP dispatch | `cyclic_llm/fep_batch.py::dispatch_control_edge` | GROMACS job-def `biomate-gromacs-cu12-gpu`; `_fep_command`; `MDRUN_CMD_READY` guard + `in/FEP_INPUTS_READY` sentinel (a clean readiness gate) | `run_id=avb6-fep-ctrl-*`, `tags.target="avb6"`, `PREFIX=cyclic_peptide/fep`; depends on pre-staged receptor/peptide/hybrid |
| Offline FEP prep | `fep/preflight/build_fep_setup.sh` (+ `build_fep_inputs.sh` launcher) | pmx hybrid → gentop → solvate/genion → grompp `em.tpr` per leg; a reusable "stage FEP inputs offline" pattern | Y1F/Y7F peptide mutation + cyclization + CaDA-Mn complex are the αvβ6 edge |
| Metal model | `fep/forcefield/cada_mn.itp` | CaDA octahedral dummy-cation model (Duarte 2014) generalises to other divalent cations | **[load-bearing]** only helps **metalloproteins**; useless for non-metal targets |

---

## 2. The generic framework — three platform layers

### Layer A — Target-agnostic physics-in-the-loop design loop
**What it is.** A closed loop `propose → grade → reward → learn` parameterised by a *design campaign*
config, with a configurable physics grader stack. αvβ6 is one config.

**Config schema (proposed `DesignCampaign`):**
```
target:      { receptor_pdb, binding_site, cofactors[]|metal: {ion, model} }   # metal optional
modality:    peptide | cyclic_peptide | small_molecule
proposer:    { kind: generative|enumerator, ref: <model id | spec | seed set> }
grader_stack: [ cofold?, mmgbsa?, fep? ]        # each optional/ordered; cheap→expensive
reward:      execution_graded                    # Layer C
budget:      { max_candidates, submit: bool, spot: true }
```
**Builds on:** `loop_batch.run_round` (already `target`-parameterised), `physics_batch.dispatch_cofold`,
`fep_batch`, `score`/`physics_dispatch`, and the Layer-C reward.
**Customer invocation:** submit a `DesignCampaign` → the loop driver; later surfaced in the composer as a
"design campaign" capability (one `workflow_ga`-style entry that drives rounds).
**[load-bearing]** Today the loop is generic **over target** (given a `target_spec`) but **peptide/cyclic
modality only** — `propose`, `fto_score._backbone`, `target_spec.build_cofold_input` all assume a peptide.
`small_molecule` modality would need a different proposer + input builder (RDKit/SDF, feeding `openfe_rbfe`).
Do not claim small-molecule support until that proposer exists.
**Refactor from current code:** lift `target="avb6"` and the HELM assumptions out of `run_round` into the
`DesignCampaign` config; make the grader stack a declared list; make the run-kind→contract map a registry
(Layer C).

### Layer B — Generic relative-FEP capability (TWO engines, composer routes by edge type)
**The honest engine split (core finding):**
- **Small-molecule congeneric ligand pair** → `openfe_rbfe` (exists; untouched).
- **Residue-mutation / peptide / cyclic-peptide / metal-bridged edge** → **new `gromacs_pmx_fep`**
  (generalises the αvβ6 `fep_batch` + `build_fep_setup` work).

**Decision & justification.** Do **not** extend `openfe_rbfe` to cover peptide/metal edges: OpenFE's
`SmallMoleculeComponent` + LOMAP MCS + OpenFF ligand FF have no residue-mutation or dummy-metal path, so
forcing it there would be a misuse of a validated tool. Add a **sibling** GROMACS/pmx workflow and present a
**unified "Relative FEP" capability in the composer that routes by edge type**. This reuses `openfe_rbfe`
as-is for its validated domain, puts each edge on the engine built for it, and mirrors proven conventions
(mode `setup|smoke|production`, the no-GPU honesty contract, a `*_cycle_closure` QC gate).

**`gromacs_pmx_fep` param schema (proposed):**
```
receptor          (PDB)
edge              { kind: residue_mutation|peptide_pair, spec: "P:1 TYR->PHE,P:7 TYR->PHE" | {pepA,pepB} }
modality          peptide | cyclic_peptide
metal_model       none | cada:{ion: Mn|Zn|Ca|Mg}        # optional; CaDA only for metalloproteins
legs              [complex, solvent]
lambda_windows, production_ns, protocol_repeats, temperature
mode              setup | smoke | production
```
**Builds on:** `fep_batch.py` (dispatch + `MDRUN_CMD_READY`/`FEP_INPUTS_READY` gating), the validated
offline-prep pattern in `build_fep_setup.sh`, `cada_mn.itp` (optional metal). Lands as a stub `.nf` under the
**safe stub location** (`biomni_workflows/nfcore/…`, per the repo rule — never edit production
`nextflow_nfcore/subworkflows/**`) plus a reviewed `bin/` entrypoint mirroring `run_openfe_rbfe.py`, with the
honesty contract enforced in the entrypoint.
**[load-bearing]** The offline pmx hybrid build is a real constraint (the GROMACS image has no pip; pmx's C
extension needs `-std=gnu11` under conda's C23 gcc), so input prep must stay a staged step, not in-job.
CaDA helps only metalloproteins.

### Layer C — Execution-verified reward as a platform primitive
**What it is.** Any workflow's real run (terminal status + S3 outputs) mints an objective scalar reward via a
registered CONTRACT — already built and CPU-validated; this layer *surfaces and documents* it.
**Refactor from current code:**
1. Relocate `execution_grader.py` + `graded_run_store.py` from `evaluation/local_trial/` to a stable platform
   module (or expose behind an API), keeping behaviour identical.
2. Turn `CONTRACTS` + `loop_grade_bridge.WORKFLOW` into a **registry** with a documented interface,
   e.g. `register_contract(workflow_name, required_outputs=[...], json_keys={...})`, so any workflow (not just
   `cyclic_peptide_*`) plugs in.
3. Wire `graded_run_store.get_reward(run_id)` / `rewards(campaign)` into the RLVR trainer — already the plan.
**Customer/platform invocation:** a workflow author registers a contract; the design loop (Layer A) and any
RLVR training read rewards by `run_id`/`campaign`. **Already generic**: `CONTRACTS` is workflow-keyed,
`TIER_REWARD` is a generic ladder, `run_from_outputs` is the generic seam.

---

## 3. Refactor plan (ordered; reuse vs new)

1. **[reuse]** Leave `openfe_rbfe` untouched — it is the small-molecule engine.
2. **[new]** `gromacs_pmx_fep` catalog workflow: stub `.nf` under `biomni_workflows/nfcore/…` + reviewed
   `bin/run_gromacs_pmx_fep.py` generalising `fep_batch`/`build_fep_setup`; parameterise `run_id`/tags/prefix
   off the target; `metal_model` optional; honesty contract (no GPU → `requires_gpu`/null) + a
   `fep_cycle_closure`/control-edge QC gate mirroring OpenFE's.
3. **[new]** Composer-level **FEP router**: map edge type → engine (small-molecule → `openfe_rbfe`;
   mutation/peptide/metal → `gromacs_pmx_fep`), exposed as one "Relative FEP" intent.
4. **[refactor]** Generalise `loop_batch.run_round` into a `DesignCampaign`-driven driver (target_spec +
   modality + proposer + grader_stack); remove the `avb6` default; make the grader stack declarative.
5. **[refactor]** Promote the reward substrate to a platform module + **contract registry**; wire
   `get_reward` into the trainer.
6. **[reuse]** `execution_grader` / `graded_run_store` logic unchanged behind the registry.

**Instance-zero coupling:** αvβ6 remains the hardest validation case (metal + cyclic + non-standard residues).
Finishing its control-edge FEP ΔΔG validates `gromacs_pmx_fep` end-to-end before it is generalised — so the
instance-zero run is the acceptance test for Layer B, not throwaway work.

---

## 4. The single biggest architectural decision needing the user's call

**Layer B engine strategy: confirm "two engines, composer routes by edge type."**
Recommendation — **yes**: keep `openfe_rbfe` for small-molecule ligand pairs and add a sibling
`gromacs_pmx_fep` for residue-mutation / peptide / cyclic / metal edges, unified under one "Relative FEP"
capability that routes by edge type. The alternative (one engine for everything) is not viable — OpenFE
cannot do residue/metal edges and GROMACS/pmx is heavier than needed for drug-like small molecules. The cost
of the recommendation is maintaining two engines; the benefit is each edge runs on the tool validated for it,
with zero disruption to the shipped `openfe_rbfe`.

---

## 5. Decision log

- **2026-10-20 — Layer B engine strategy CONFIRMED (user):** two engines, composer routes by edge
  type. `openfe_rbfe` kept as-is for small-molecule congeneric pairs; new sibling `gromacs_pmx_fep`
  for residue-mutation / peptide / cyclic / metal edges; one unified "Relative FEP" capability routes
  by edge type. This section records the plan that follows from that decision.

---

## 6. Tracked build sequence (C → B → A)

Build order follows the dependency graph, not the layer letters: the reward substrate (C) and the
grader workflows (B) are prerequisites for the design loop (A). Status tags: **DONE / IN PROGRESS /
HELD (awaiting user go) / PENDING**.

### 6.0 The design loop decomposed (what Layer A actually is)
Six orthogonal parts — ~70% reuse of existing BioMate primitives, not new subsystems:
1. **Config/spec** `DesignCampaign` — *new, small*; declarative `{target, modality, proposer, grader_stack[], reward, budget}`.
2. **Proposer** — *pluggable*; generative model or enumerator behind one interface. Peptide proposer exists; small-molecule needs a new one.
3. **Grader stack** — *reuse*; an ordered list of real BioMate workflows (cofold → MM-GBSA → FEP) invoked via `run_workflow`/`nextflow_executor` on Batch, cheap→expensive.
4. **Reward** — *reuse (Layer C)*; each graded run mints a scalar via the contract registry.
5. **Learn** — *optional, research*; RLVR updates the proposer from `graded_run_store.get_reward(campaign)`. Separable — a campaign can run as pure ranking without it.
6. **Orchestrator** — *refactor*; `loop_batch.run_round` with `target="avb6"`/HELM assumptions lifted into the config.
**Integration surfaces (all reuse):** execution via `run_workflow`→Batch (lineage/billing/SSE free); persistence via the run-state-store/Redis pattern; invocation via a composer intent; UI = the existing auto-loop/QC panel generalized (gate table + was→now diff + candidate leaderboard). DesignCampaign is the existing QC auto-loop (gate→remediate→re-run over one workflow) lifted to propose-new-candidates-and-learn across rounds.

### 6.1 Layer C — execution-verified reward registry
- **[DONE]** `register_contract()` / `get_contract()` + `register_run_kind()` / `workflow_for()`; existing cyclic contracts refactored through the registry; backward-compat confirmed (selftests + `test_execution_grader.py` green). Commit `d4f3023d3`.
- **[PENDING] C1** — relocate `execution_grader.py` + `graded_run_store.py` from `evaluation/local_trial/` to a stable platform module (churns 5 dependent imports; do as one atomic change).
- **[PENDING] C2** — wire `get_reward(run_id)` / `rewards(campaign)` into the RLVR trainer. Blocks Layer A part 5 (learn).

### 6.2 Layer B — unified relative-FEP capability
- **[IN PROGRESS] B0 — αvβ6 instance-zero acceptance test** (the hardest case: metal + cyclic + non-standard residues):
  - **[DONE]** Setup pipeline validated end-to-end — both legs `em.tpr`, `FEP_INPUTS_READY` staged. Bugs cleared en route (each a generic-engine requirement): entrypoint override, offline gemmi prep, `-std=gnu11` for pmx's C ext, pmx console-CLI, `--ref` (not `--keep_resid`) to confine mutations to the peptide, `-ignh` strip, **cyclic origin-rotation so mutation sites stay interior**, `mn_cada.pdb` path, `[molecules]` newline. Commits through `55c384f25`.
  - **[IN PROGRESS]** Cyclic-junction parameterization — add cross-boundary angles/dihedrals/impropers at the head-to-tail junction (production accuracy; the single amide bond only satisfies the `em.tpr` readiness proof).
  - **[HELD — awaiting user go]** Control-edge ΔΔG GPU run (`_fep_command` mdrun-only rewrite → `fep_batch.py --submit`). Spot GPU, ~1 GPU-day/leg (~$15–60). **Acceptance:** control↔control ΔΔG recovers the known Trivehexin-mono↔avebehexin gap within replicate error. This is also the key missing preprint P0 result.
- **[PENDING] B1** — generalize `fep_batch`/`build_fep_setup` into a `gromacs_pmx_fep` catalog workflow: stub `.nf` under `biomni_workflows/nfcore/…` (never production `nextflow_nfcore/**`) + reviewed `bin/run_gromacs_pmx_fep.py`; param schema per §2 Layer B; `metal_model` optional; offline-prep staged step; honesty contract. Starts after B0 validates the engine.
- **[PENDING] B2** — composer FEP router: edge type → engine (small-molecule → `openfe_rbfe`; mutation/peptide/metal → `gromacs_pmx_fep`), one "Relative FEP" intent.
- **[PENDING] B3** — `fep_cycle_closure` / control-edge QC gate (register its contract via Layer C's `validate()` hook).

### 6.3 Layer A — target-agnostic DesignCampaign loop (LAST — depends on B1 + C)
- **[PENDING] A1** — generalize `loop_batch.run_round` into a `DesignCampaign`-driven driver (target_spec + modality + proposer + declarative grader_stack); remove the `avb6`/HELM defaults.
- **[PENDING] A2** — persist a campaign as a first-class object (rounds + candidates + rewards) via the run-state-store/Redis pattern.
- **[PENDING] A3** — composer "design campaign" intent (`workflow_ga`-style entry) that creates + drives the campaign.
- **[PENDING] A4** — campaign UI: generalize the auto-loop panel (gate table, was→now proposer diff, candidate leaderboard by reward).
- **[PENDING] A5** — wire the learn step (RLVR via `get_reward(campaign)`); depends on C2.

### 6.4 Dependency graph
```
C (registry DONE) ──┬─> C2 (trainer wiring) ─────────────────┐
                    │                                         v
B0 (αvβ6 setup DONE; junction IN PROGRESS; ΔΔG HELD) ─> B1 ─> A1 ─> A2 ─> A3 ─> A4 ─> A5
                                                   └─> B2, B3
```
Instance-zero (B0) is the acceptance test for the `gromacs_pmx_fep` engine; it must validate (ΔΔG recovers the control gap) before B1 generalizes it. Nothing in A is throwaway — it is thin orchestration over C + B.
