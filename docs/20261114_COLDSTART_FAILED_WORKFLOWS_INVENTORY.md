# Coldstart deep — failed workflows: detailed reasons + fixes

**Timestamp:** 2026-11-14T14:50Z  
**Evidence tip:** mostly `0b63d793` (also `d258bd3227`, `5dd9b6fb67`)  
**Source:** `frontend/e2e/execshots/coldstart-analysis-design-deep/*.json` (committee-regraded)

---

## Summary counts (fail-ish grades)

| Class | N | Fixable now? |
|-------|---|--------------|
| `no_launch` | 12 | Product/routing (no Confirm) — not Batch |
| `nf_generic_fail` | 11 | Per-workflow inputs / sample data |
| `container_exit_other` | 11 | Inputs / structure pointers / R errors |
| `reinvent_cli_missing` | **6** | **YES — root cause fixed in this session** |
| `soft_pass_lie` | 7 | runId/panel plumbing |
| `blocked_required` | 5 | Honest (Cryo Movies Path, etc.) |
| `param_validation` | 4 | Missing required nf-core params |
| `run_failed_generic` | 3 | Script compile / FS |
| `storage_download` | 1 | Sample storage path |
| `empty_nf_session` | 1 | Wrong process selector |
| `missing_input_path` | 1 | ChIP-seq BAM path |

---

## Class details

### 1. REINVENT4 CLI/package not found (6) — FIXED upstream

| Case | Workflow |
|------|----------|
| `design-generate-sm-0/1/2` | REINVENT4 Generative Lead Design |
| `design-optimise-properties-one-pass-sm-0/1/2` | same |

**Observed error:**
```
Process GENERATE_REINVENT4 (reinvent4_sampling) failed: Essential container in task exited —
ERROR: REINVENT4 CLI/package not found in container
```

**Root cause (ground truth from ECR `biomate/reinvent4-nf:x86`, digest `sha256:443e2e6e…`, pushed 2026-11-10):**

Docs/Dockerfile claimed a fix (`pip install reinvent` + staged priors under `/opt/reinvent4/priors`, plus procps). **What is actually in ECR is a different image layout:**

| Expected (repo Dockerfile) | Live ECR `:x86` |
|----------------------------|-----------------|
| `reinvent` on PATH | **Absent** (no `/usr/local/bin/reinvent`) |
| `import reinvent` via pip | **Absent** from site-packages |
| Priors under `/opt/reinvent4/priors` | **Only** `/opt/REINVENT4/priors/README.md` (Zenodo pointer) |
| — | Git tree at `/opt/REINVENT4` + `/opt/biomate/reinvent_runner.py` (runner still calls missing `reinvent` CLI) |

So “fixed in docs / Dockerfile / procps rebuild” never closed the class: Nov-10 rebuild kept the old `/opt/REINVENT4` checkout **without** installing the CLI or downloading priors.

**Fix shipped (needs sync to DEV):**

1. `reinvent4_lead_design/main.nf` — set `PYTHONPATH=/opt/REINVENT4`, invoke via PATH `reinvent` **or** `reinvent.Reinvent.main_script` (not bare `-m` alone — older trees may lack `__main__.py`), fetch `reinvent_pubchem.prior` from Zenodo with a **120s timeout** when staged priors are missing; RDKit scoring soft-fails to unscored SMILES so `FILTER_RANK` (drug-discovery-nf) can re-score.
2. `nextflow_executor.py` — allow-list `reinvent4_lead_design` / `reinvent4_finetune_rl` / `mpo_denovo_optimization` as per-process-container workflows (do not force global drug-discovery image).
3. `backend/docker/reinvent4-nf/Dockerfile` — stage priors from Zenodo (not dead GitHub raw/LFS URLs) for the **next** ECR rebuild; install `rdkit`; install `/opt/biomate/reinvent_runner.py` that uses the same CLI bridge.
4. **Batch E polish:** shared `drug_discovery/reinvent4_runtime.py` (CLI + Zenodo prior) wired into `generators.py` / `reinvent4_trainer.py`; `reinvent4_finetune_rl` seeds `/opt/REINVENT4` on `PYTHONPATH` and its staged `bin/run_reinvent4_training.py` fetches priors before training; `GENERATE_BRICS` uses `RDKIT_CONTAINER` (not reinvent4-nf).

### Sync / rebuild prerequisites (do **not** sync until lease free + PRE_SYNC)

| Step | What | Why |
|------|------|-----|
| A | `docs/PRE_SYNC_CHECKLIST.md` (tsc + vitest; no Galaxy py change required for this class) | Gate before `scripts/sync_to_dev.sh` |
| B | Sync `main.nf` (both reinvent4 workflows) + `nextflow_executor.py` allow-list + `bin/run_reinvent4_training.py` | Unblocks **sampling** / finetune on **current** ECR without rebuild (runtime Zenodo fetch + PYTHONPATH bridge) |
| C | Rebuild/push `biomate/reinvent4-nf:x86` from updated Dockerfile | Removes Batch dependence on runtime Zenodo egress; bakes CLI, priors, `reinvent4_runtime.py`, `reinvent_runner.py`, rdkit |
| D | Re-run only `design-generate-sm-*` / optimise one-pass after B (or C) | Verify class closed |

**Batch egress note:** until C lands, GENERATE/TRAIN need outbound HTTPS to `zenodo.org` from the task role/network. If Zenodo is blocked, fail loud (exit 4) — do not fabricate molecules.

**Container split (intentional):** `GENERATE_REINVENT4` → reinvent4-nf; `VALIDATE_INPUT` / `GENERATE_BRICS` / `FILTER_RANK` → drug-discovery-nf (`RDKIT_CONTAINER`).

---

### 2. Cryo / blocked required (5) — honest, not execution bugs

| Case | Workflow | Reason |
|------|----------|--------|
| `analysis-domain-str-0/2` | CryoSPARC Standard SPA | Confirm disabled — Movies Path required |
| `analysis-domain-fgen-0` | nf-core/crisprseq | Confirm blocked |
| `analysis-try-sample-data-11` | Chemoproteomics Pulldown | Confirm blocked |
| `design-predict-filter-sm-3` | openfe_rbfe | Confirm blocked |

Harness correctly grades `BLOCKED_REQUIRED` (no force-Confirm).

---

### 3. NO_LAUNCH (12)

No Confirm button or instant path skipped — ad-hoc compute, several domain examples without a runnable panel (`clin-0/1`, `str-1`, fold-complex gaps). **Routing / UX**, not Batch.

---

### 4. Param validation (4)

| Case | Workflow | Reason |
|------|----------|--------|
| `analysis-domain-gen-0`, `analysis-validated-workflows-2` | nf-core/sarek | `Validation of pipeline parameters failed` |
| `design-fold-complex-pep-0/2` | nf-core/proteinfold | same |

Cold-start examples do not supply schema-required params.

---

### 5. Container exit — structure / R / data (11)

| Subclass | Cases | Detail |
|----------|-------|--------|
| Structure-set pointer | `design-*-bio-*`, pep optimise | `ValueError: unrecognized structure-set pointer '…_constraints.json'` — JSON passed where PDB/CIF expected |
| Bioconductor R | mageckflute, deqms, multigsea, survival cox | R traceback / missing CSV in cwd |
| openfe | `design-predict-filter-pep-3` | `DEFINE_EDGE` container exit |

---

### 6. Generic Nextflow fail (11) + storage / path / empty session (3)

Bulk RNA-seq DE, seqvartools, Bcell epitope, Docking Vina, prompt-as-name workflows, etc. UI strip often only “Pipeline failed / Nextflow run failed” without step stderr. Notable specifics:

- `analysis-try-sample-data-0`: storage download exception (`differentialabundance.nf`)
- `analysis-try-sample-data-8`: missing ChIP-seq BAM path
- `analysis-try-sample-data-3`: no process matching `PRODUCTION_MD`
- `design-fold-complex-bio-0/1`: script compilation error

---

### 7. FAKE_OR_SOFT_PASS (7)

Completed or clicked Confirm but missing `runId` / empty After Run substance (`cyclic_peptide_design`, WSI, etc.). Measurement / plumbing — not the same as REINVENT.

---

## What “REINVENT was already fixed” referred to (docs)

| Doc claim | What it actually fixed |
|-----------|------------------------|
| `20261006_DRUG_GENERATION_EXECUTION_GATE` bug #1 | Optional null params (receptor/TOML) — **launch gate**, not container |
| `20261022` / procps `82cccf55` | Nextflow needs `ps` — **launch**, not CLI |
| Routing fixes | Generate → reinvent workflow card, not ADMET |
| Repo Dockerfile rewrite | **Never reflected in live ECR `:x86` contents** |

---

## Next steps

1. **Sync** (lease free + PRE_SYNC) reinvent4 `main.nf` files + executor allow-list + finetune `bin/run_reinvent4_training.py` to DEV; re-run `design-generate-sm-*` only.
2. **Rebuild/push** `reinvent4-nf:x86` from the Zenodo-prior Dockerfile so Batch does not depend on runtime Zenodo fetch.
3. Treat remaining classes as separate product tickets (Cryo Movies Path provision, sarek/proteinfold param prefills, structure-set pointer mapping).
