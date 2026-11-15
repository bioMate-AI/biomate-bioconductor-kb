# Coldstart remaining four HONEST_FAIL classes (post `aaaf2a6b` sync)

**Date:** 2026-11-15  
**Context:** Remasure evidence under `frontend/e2e/execshots/coldstart-analysis-design-deep/` was captured against DEV tip **`25a03a72c7`**. Local tip then landed compile / TRAIN-routing / pep-3 fixes in **`2bfb77f29d`**, binding coverage in **`0faa6dff24`**, and merge **`aaaf2a6b`** (absorb live tip `104915eedd` before coldstart compile sync).

**Honesty rule:** These four classes are still **HONEST_FAIL** until a post-`aaaf2a6b` remasure rewrites the execshot JSON with a newer `buildInfo.commit` and a non-fail terminal. This note does **not** invent soft passes. Pre-fix remasure grades remain the ground truth below.

**Cross-links**

| Doc | Role |
|-----|------|
| [`docs/20261115_COLDSTART_COMPILE_TRAIN_ROUTING_FIX.md`](20261115_COLDSTART_COMPILE_TRAIN_ROUTING_FIX.md) | What `2bfb77f29d` claimed to fix (GString `$`, TRAIN hijack, pep-3 containers) |
| [`docs/20261114_BATCH_F_STRUCTURE_SET.md`](20261114_BATCH_F_STRUCTURE_SET.md) | `*_constraints.json` → PDB rebind; residual “wrong product = TRAIN” |
| [`docs/20261114_BATCH_G_BIOCONDUCTOR.md`](20261114_BATCH_G_BIOCONDUCTOR.md) | Cox / deqms R-schema staging (preceded compile class) |
| [`docs/20261114_BATCH_H_GENERIC_NF.md`](20261114_BATCH_H_GENERIC_NF.md) | seqvartools VCF/ped discovery; pep-3 seed; flow deferred to D |
| [`docs/20261114_BATCH_D_PATH_STORAGE.md`](20261114_BATCH_D_PATH_STORAGE.md) | Flow `PRODUCTION_MD` gate + Accuri path residual risk |
| [`docs/20261114_COLDSTART_REMAINING_FIXES.md`](20261114_COLDSTART_REMAINING_FIXES.md) | Earlier “closed in tree” inventory (needs remasure to close on DEV) |
| [`docs/20261115_PEP3_GROMACS_RECEPTOR_STAGING.md`](20261115_PEP3_GROMACS_RECEPTOR_STAGING.md) | Verified pep-3 root cause: bare `1BXL.pdb` + sample_data outside staged WF; in-tree assets/`_resolveReceptor` |
| [`docs/20261115_FLOW_CYTOMETRY_CONTAINER_EXIT_FIX.md`](20261115_FLOW_CYTOMETRY_CONTAINER_EXIT_FIX.md) | Verified flow-cyto RCs + in-tree fix (`path` stage FCS, bake/bootstrap `flowio`); **not closed** until DEV remasure |
| [`docs/20261115_PROTEIN_DIFFUSION_TRAIN_EXECUTABLE.md`](20261115_PROTEIN_DIFFUSION_TRAIN_EXECUTABLE.md) | Executable TRAIN path: warm-start inference + `resolve_ml_training_container` + baked ckpts |

---

## Snapshot: remasure tip `25a03a72c7`

| Class | Cases (execshot id) | `runId` | Fail signature (sanitized) |
|-------|---------------------|---------|----------------------------|
| **TRAIN NotImplementedError** | `design-generate-bio-1`, `design-generate-bio-2`, `design-fold-complex-bio-2`, `design-optimise-properties-one-pass-pep-1` (+ related bio/pep TRAIN routes) | `4fd7d4be-…`, `acdc0255-…`, `121110b9-…`, `c084672d-…` | `Process TRAIN failed: … NotImplementedError: … diffusion-training GPU image` |
| **Module compilation** | `analysis-try-sample-data-7` (cox), `analysis-domain-prot-0` (deqms), `analysis-domain-gen-2` (seqvartools) | `cbb020bd-…`, `42eec0e5-…`, `17d0a2bc-…` | `Module compilation error — - file : [path]` |
| **pep-3 path missing** | `design-predict-filter-pep-3` (`gromacs_pmx_fep`) | `6f7de6e2-…` | `No such file or directory: [path] — -- Check '.nextflow.log'` |
| **Flow cytometry container exit** | `analysis-try-sample-data-3` | `e7aa117b-…` | `Process ANALYZE_FLOW_CYTOMETRY_IMMUNOPHENOTYPING (run) failed: Essential container in task exited` |

All listed JSON files have `"grade": "HONEST_FAIL"`, `"useCasePass": false`, and `buildInfo.commit = 25a03a72c7…`. After-run strips show honest `RUN FAILED` (not spinner soft-pass).

---

## 1. TRAIN NotImplementedError

**Status (2026-11-15 follow-up):** **Both** tracks are in-tree and must stay together — do not ship routing without the executable image path (or vice versa).

| Track | In-tree? | Remasure / ops still required |
|-------|----------|-------------------------------|
| **Design intent gate** (bare design/fold → catalog, not TRAIN) | **Yes** — `detect_training_intent` verb gate + scaffold strip (`2bfb77f29d` / `8493c1d891` / `2435bab3d2`); unit matrix green | Post-sync deep remasure of `design-generate-bio-*` / fold / pep design → catalog WF, not TRAIN |
| **Executable fine-tune TRAIN** (explicit “fine-tune / train protein diffusion”) | **Yes (uncommitted)** — trainer warm-start inference, `compute_config` on TRAIN cards, executor `resolve_ml_training_container`, baked ckpts in Dockerfile | **`git tag diffusion-training-v3 && push`** (or next free `diffusion-training-v*`) → GH image workflow; then sync Galaxy; remasure fine-tune + real PDB |

Design prompts must stay `detect_training_intent=False`. Fine-tune prompts stay `True` and must land on `biomate/diffusion-training`, not Ludwig.

### Prior remasure evidence

| Case | Prompt (abbrev) | Workflow card | `runId` | `after.failSnippet` / `terminal.error` |
|------|-----------------|---------------|---------|----------------------------------------|
| `design-generate-bio-1` | Graft CDRs onto human framework | (empty `workflowNames`; ran TRAIN) | `4fd7d4be-b25d-4a6c-8fd2-c6d0d0fe1410` | `Process TRAIN failed: Essential container in task exited — raise NotImplementedError( \| NotImplementedError: The concrete RFdiffusion fine-tune/sample loop runs on the diffusion-training GPU image…` |
| `design-generate-bio-2` | Enzyme active-site redesign | `protein backbone design` | `acdc0255-e110-468f-8094-d1b9d1e74fb3` | same NotImplementedError |
| `design-fold-complex-bio-2` | Predict fold of designed binder | (empty `workflowNames`; TRAIN) | `121110b9-f812-406f-90a6-b4ddf02f447c` | same |
| `design-optimise-properties-one-pass-pep-1` | Reduce charge / keep permeability | `peptide structure design` | `c084672d-a0ad-4cde-b3d3-f9e26e4d1c0b` | same NotImplementedError |

**Same class, different fail shape (Batch F residual on tip `25a03a72c7`):**  
`design-optimise-properties-one-pass-pep-0` still hit `ValueError: unrecognized structure-set pointer '…_peptide_constraints.json'` — binding kind mismatch, not NotImplemented. Covered by Batch F + `0faa6dff24` test; do not conflate with GPU-image NotImplemented.

Screens: `design-generate-bio-{1,2}-after-run.png`, `design-fold-complex-bio-2-after-run.png`, `design-optimise-properties-one-pass-pep-1-after-run.png`.

### Root-cause hypothesis vs what landed

| Layer | Hypothesis (remeasure) | Landed in `2bfb77f29d` / related |
|-------|------------------------|----------------------------------|
| **Routing hijack** | `_DIFFUSION_HINTS` alone made bare “design a binder / peptide structure / graft CDRs” → `detect_training_intent=True` → `ml_training` / `diffusion_train.nf` TRAIN process | **Yes:** `detect_training_intent` now requires a train/fine-tune verb co-occurring with diffusion hints; bare design falls through to catalog (`routing.py`). Unit matrix in `test_diffusion.py`. |
| **Binding unblocked TRAIN** | Batch F rebound `*_constraints.json` → PDB so TRAIN got a real structure set — then failed loudly on missing GPU image (honest) | Batch F + spec-less rebind (`attachment-binding.ts`) + `0faa6dff24` test. Binding fix does **not** make TRAIN product-correct. |
| **Infra / executable TRAIN** | Trainer raised `NotImplementedError` even with rfdiffusion import; Confirm & Run omitted `compute_config.container` → Ludwig `ml-training`; weights not baked | **In tree (uncommitted):** warm-start `run_inference.py` driver + honest metrics; `resolve_ml_training_container` + executor fallback; routing attaches `compute_config`; Dockerfile bakes Base/Complex ckpts. **Still required:** ECR tag `diffusion-training-v*` rebuild/push + DEV remasure of true fine-tune prompts. |

### Verification plan

```bash
# Unit (already part of PRE_SYNC for this class)
cd backend && PYTHONPATH=lib python3.9 -m pytest \
  lib/galaxy/ai/ml_training/tests/test_diffusion.py \
  lib/galaxy/ai/ml_training/tests/test_routing.py -q

# Post-sync remasure — expect catalog design/fold WF, NOT Process TRAIN
BIOMATE_DEEP_FILTER='design-generate-bio-1|design-generate-bio-2|design-fold-complex-bio-2|design-optimise-properties-one-pass-pep-1' \
  ./e2e/run_coldstart_deep.sh
```

**Pass criteria (honest):** card is an indexed design/fold/optimise workflow (antibody, ProteinMPNN, cyclic peptide, ADMET, …), not `protein backbone design` / `peptide structure design` TRAIN; no `NotImplementedError` from diffusion harness.  
**Still HONEST_FAIL if:** prompt still routes to TRAIN, or TRAIN runs and exits NotImplemented (infra gap).

### Open risks

- Verb-gated diffusion may still fire on prompts that say “train / fine-tune a binder diffusion model” without the GPU image → honest NotImplemented remains correct.
- Empty `workflowNames` on some TRAIN runs complicates harness diagnosis; panel name / session metadata lag is orthogonal.
- Closing Batch F pointer errors can **unmask** NotImplemented (seen: pep-1 progressed from constraints JSON → NotImplemented on tip `25a03a72c7`).

---

## 2. Module compilation (bare `$` in Style-A `script: """`)

### Prior remasure evidence

| Case | Workflow | `runId` | Fail |
|------|----------|---------|------|
| `analysis-try-sample-data-7` | `survival_cox_proportional_hazards_regression` | `cbb020bd-40d9-4a10-aee8-9db990da546d` | `Module compilation error — - file : [path]` |
| `analysis-domain-prot-0` | `deqms_maxquant_lfq` | `42eec0e5-545c-43d5-8065-bd168188ff1b` | same |
| `analysis-domain-gen-2` | `seqvartools` | `17d0a2bc-dc6f-40ff-bce3-474119f9764f` | same |

UI AI diagnosis often: “No error log was captured” / “run stopped before completing” — consistent with **compile-time** abort before process stderr.

### Root-cause hypothesis vs what landed

| Prior batch | What it fixed | What remasure still showed |
|-------------|---------------|----------------------------|
| **Batch G** | Cox column aliases; deqms contaminant/LFQ robustness | Never reached R — Module compilation first |
| **Batch H** | seqvartools VCF/ped discovery + freestyle staging | Same — compile before discovery runs |

**Hypothesis (confirmed in tree by `2bfb77f29d`):** Bioconductor Style-A `.nf` files are `include`d via `biomate_entry.nf`. Inside `script: """` … `"""` GStrings, bare `$` (R regex end-anchors, shell `$(…)`, etc.) is Groovy interpolation → **Module compilation error**. Standalone `nextflow run main.nf` can mask this; the entry wrapper surfaces it.

**Landed:** Escape `$` → `\$` in `script:` / `shell:` / `stub:` for cox, deqms, seqvartools, antibody `$(find)`, atacseq stub, nonmem_poppk, wsi_he_nuclei_segmentation, plus several immunology/genomics siblings (see `2bfb77f29d` stat).

### Verification plan

```bash
# Local static: no bare end-anchor /$()/ patterns left unescaped in touched script blocks
# (spot-check cox / deqms / seqvartools after sync)

BIOMATE_DEEP_FILTER='analysis-try-sample-data-7|analysis-domain-prot-0|analysis-domain-gen-2' \
  ./e2e/run_coldstart_deep.sh
```

**Pass criteria:** no `Module compilation error`. Subsequent fails (R schema, missing VCF columns, Batch egress) are **new** HONEST_FAIL classes — record them; do not call compile closed if R then crashes.

### Open risks

- Other Style-A / biomni workflows with bare `$` in GStrings not in the `2bfb77f29d` file list can still compile-fail under `biomate_entry.nf`.
- UI redacts the real `.nf` path to `[path]` — Galaxy `.nextflow.log` on the run workdir is required for any residual compile miss.
- Batch G R-logic fixes are still unverified until compile clears.

---

## 3. pep-3 path missing (`gromacs_pmx_fep`)

**Status:** in-tree fix present (assets/`_resolveReceptor`) — **not closed** until post-sync remasure. Detail: [`docs/20261115_PEP3_GROMACS_RECEPTOR_STAGING.md`](20261115_PEP3_GROMACS_RECEPTOR_STAGING.md).

### Prior remasure evidence

| Field | Value |
|-------|-------|
| Case | `design-predict-filter-pep-3` |
| Prompt | Relative binding free energy for single-residue change in peptide binder |
| Workflow | `gromacs_pmx_fep` |
| `runId` | `6f7de6e2-a3ba-42bd-9ccf-61ccae81c15d` |
| `terminal.error` | `No such file or directory: [path] — -- Check '.nextflow.log' file for details` |
| `after.failSnippet` | `RUN FAILED No such file…` + AI diagnosis “input the pipeline needs could not be found” |

Screens: `design-predict-filter-pep-3-{seeded,launched,terminal,after-run}.png`.

**Note on symptom drift:** Inventory / Batch H originally labelled pep-3 as **`DEFINE_EDGE` Essential container exited** (python3 missing on `gromacs-cuda`). Remasure tip `25a03a72c7` instead shows **path missing** — consistent with null `params.receptor` / unresolved demo path on the head **before** 1BXL defaults + vendored PDB landed. Do not soft-pass either shape.

### Root-cause hypothesis vs what landed

| Cause | Status in `2bfb77f29d` |
|-------|------------------------|
| `DEFINE_EDGE` / `PREPARE` / `ANALYZE` used `GMX_CONTAINER` (CUDA image often without `python3`) | **Fixed:** `PY_CONTAINER` = `biomate/workflow-tools` for those steps; GMX reserved for MD legs |
| `params.receptor` / `edge_spec` null → launch/path abort | **Fixed:** default receptor `${projectDir}/../../sample_data/peptides/1BXL.pdb`, `edge_kind=peptide_pair`, BAK vs G1A `edge_spec` |
| Vendored `sample_data/peptides/1BXL.pdb` missing on DEV tree | **Added** in same commit (3342-line PDB) |
| Generative prompts hijacked to FEP | **Partial:** generative routing hint excludes `gromacs_pmx_fep` / `openfe_rbfe` — pep-3 **is** an FEP ask, so routing to gromacs is intentional |

Batch H also seeded Prepared inputs (`receptor=1BXL.pdb edge_kind=peptide_pair …`) in the coldstart catalog — complementary to NF defaults.

### Verification plan

```bash
# Tree must include receptor on synced Galaxy image
test -f backend/biomni_workflows/sample_data/peptides/1BXL.pdb

BIOMATE_DEEP_FILTER='design-predict-filter-pep-3' \
  ./e2e/run_coldstart_deep.sh
```

**Pass criteria:** past DEFINE_EDGE / path resolve into MD or a later **honest** gate (equilibration time, QC cycle_closure, GPU quota) — not `No such file` and not python-missing container exit on DEFINE_EDGE.  
**Do not** call REAL_PASS on a later MD/QC fail.

### Open risks

- Relative `${projectDir}/../../sample_data/peptides/1BXL.pdb` must resolve on the **Batch/Galaxy head** layout after sync; wrong relative depth → same `No such file` with a new tip.
- `workflow-tools` image must ship on ECR for AWS mode; otherwise PY_CONTAINER pull fails (different HONEST_FAIL).
- Full FEP smoke/production modes are expensive; coldstart may only clear setup/DEFINE_EDGE.

---

## 4. Flow cytometry container exit

**Status (2026-11-15):** RCs **verified**. Fix is **in-tree** — see [`docs/20261115_FLOW_CYTOMETRY_CONTAINER_EXIT_FIX.md`](20261115_FLOW_CYTOMETRY_CONTAINER_EXIT_FIX.md). **Not closed** until DEV remasure.

### Prior remasure evidence

| Field | Value |
|-------|-------|
| Case | `analysis-try-sample-data-3` |
| Workflow | `Analyze Flow Cytometry Immunophenotyping` |
| Prompt | Gate FSC/SSC; Accuri blank for format |
| `runId` | `e7aa117b-48ab-46fd-9bd0-e63ea6360983` |
| Fail | `Process ANALYZE_FLOW_CYTOMETRY_IMMUNOPHENOTYPING (run) failed: Essential container in task exited` |

`2bfb77f29d` / `aaaf2a6b` **did not** touch this workflow. Batch D closed the **previous** abort (`There's no process matching config selector: PRODUCTION_MD`). Remasure tip `25a03a72c7` shows the **next** failure class: container exit after PRODUCTION_MD was gated.

### Root-cause hypothesis vs what landed

| Layer | Hypothesis | Landed? |
|-------|------------|---------|
| **Batch D** | Executor always emitted `withName: 'PRODUCTION_MD'` → Nextflow 24+ strict exit | **Yes (earlier):** gate on process declaration; Accuri default path verified on disk |
| **Residual (Batch D Gaps)** | `params.fcs_file_path` is a **host `projectDir` string** exported into the task; Accuri file may be absent **inside** the container if the workflow tree is not mounted | **Not fixed.** `main.nf` still uses `val(meta)` only — FCS is not a `path` input staged into the work dir |
| **Runtime** | `flowio.FlowData(fcs_file_path)` / missing dep / bad FCS → process non-zero → “Essential container exited” | Needs `.command.err` from the failed task — not in UI strip |

Vendored file exists locally: `backend/biomni_workflows/sample_data/flow_cytometry/Accuri_C6_A01_H2O.fcs` (13 603 bytes). Path alone ≠ Batch staging.

### Verification plan

```bash
# Confirm Accuri still on tree after sync
python3 -c "
from pathlib import Path
p=Path('backend/biomni_workflows/nextflow_nfcore/subworkflows/cell_biology/analyze_flow_cytometry_immunophenotyping')
f=(p/'../../../../sample_data/flow_cytometry/Accuri_C6_A01_H2O.fcs').resolve()
print(f.exists(), f.stat().st_size)
"

BIOMATE_DEEP_FILTER='^analysis-try-sample-data-3$' \
  ./e2e/run_coldstart_deep.sh
```

On fail: pull run workdir `.command.err` / `.command.log` for `ANALYZE_FLOW_CYTOMETRY_IMMUNOPHENOTYPING` (FileNotFound vs `flowio` vs gating JSON). Prefer root fix: stage FCS as `path` input (or localize via executor) rather than string `projectDir` into an unmounted container.

**Pass criteria:** process completes with results JSON / population table; still HONEST_FAIL if container exits for any reason.

### Open risks

- Treating container-exit as “flaky Batch” without stderr is forbidden — get the task log.
- Synthetic fallback in the Python body (`fcs_file_path is None`) does **not** help when a non-null host path points at a missing in-container file.
- Not in scope of `2bfb77f29d`; tracking here so it is not lost after PRODUCTION_MD looks “done” in Batch D docs.

---

## Post-`aaaf2a6b` remasure checklist (all four)

Do **not** mark any class closed until execshots show a tip ≥ `aaaf2a6b` / `2bfb77f29d` and grades move off these fail signatures.

```bash
# PRE_SYNC (docs/PRE_SYNC_CHECKLIST.md) then one-writer sync
# Then:
BIOMATE_DEEP_FILTER='design-generate-bio-1|design-generate-bio-2|design-fold-complex-bio-2|design-optimise-properties-one-pass-pep-1|analysis-try-sample-data-7|analysis-domain-prot-0|analysis-domain-gen-2|design-predict-filter-pep-3|analysis-try-sample-data-3' \
  ./e2e/run_coldstart_deep.sh
```

| Class | Expect after good sync | Still HONEST_FAIL if… |
|-------|------------------------|-------------------------|
| TRAIN NotImplemented | Design → catalog (not TRAIN); explicit fine-tune → diffusion-training image with real designs (no fabricated `train_loss`) | Design still routes to TRAIN; fine-tune still Ludwig / NotImplemented; image tag not rebuilt |
| Module compilation | Past compile into R/process | Any `Module compilation error` |
| pep-3 path | Past path/DEFINE_EDGE python (needs **assets/** staging fix, not only `2bfb77f29d` sample_data default) | `No such file` or DEFINE_EDGE container exit |
| Flow cytometry | Completes gating outputs (in-tree fix; image rebuild optional — bootstrap covers `flowio`) | Essential container exited (any cause) — **not closed** until remasure |

---

## Commit map

| Commit | Relevance |
|--------|-----------|
| `2bfb77f29d` | Escape NF GString `$`; stop TRAIN hijack; gromacs PY_CONTAINER + 1BXL defaults; Batch F residual rebind; generative≠FEP hint |
| `0faa6dff24` | Test: spec-less `constraints.json` → PDB rebind |
| `aaaf2a6b` | Merge absorb `104915eedd` before coldstart compile sync (Wave 4 landings + leverage — not a substitute for remasure of the four classes) |

**Evidence tip for this note:** remasure JSON `buildInfo.commit = 25a03a72c7` (pre-fix). Post-sync remasure must overwrite those files before any class is called closed.

### Uncommitted sibling set (ready after clean tree)

| Bundle | Key paths | Shared-file risk |
|--------|-----------|------------------|
| **diffusion-train** | `diffusion_trainer.py`, `executor_payload.py`, `routing.py`, `nextflow_executor.py`, Dockerfile, GH workflow, `test_diffusion.py`, `docs/20261115_PROTEIN_DIFFUSION_TRAIN_EXECUTABLE.md` | `routing.py`, `nextflow_executor.py` |
| **pep-3 assets** | `gromacs_pmx_fep/{main.nf,nextflow_schema.json,assets/1BXL.pdb,tests}`, `backend/.gitignore` un-ignore, catalog peptides note, PEP3 doc | `cold-start-demo-catalog.ts` |
| **flow-cyto** | flow `main.nf`, `workflow-tools` Dockerfiles/smoke, `test_coldstart_batch_d_fixes.py`, FLOW doc | none with TRAIN/pep-3 code |
| **Module `$`** | already in `2bfb77f29d` — **no new uncommitted** | — |

Do **not** commit auto_update/research disk-free deletes (parked in stash). Restore any such deletes before sync gate.
