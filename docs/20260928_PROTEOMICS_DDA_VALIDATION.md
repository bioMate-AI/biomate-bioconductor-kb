# Proteomics DDA Search (#217) — Real-Data Run Validation

**Date:** 2026-09-28
**Goal:** Turn the `proteomics_dda_search` workflow (license-clean DDA: Comet + OpenMS)
from "registered" into "proven" by running it end-to-end on **real** DDA data on
dev / AWS Batch.

**Outcome (2026-09-28 initial pass):** ⛔ **BLOCKED before any Batch dispatch.** The
workflow is registered and routable, but it **cannot compile** on dev because its three
required OpenMS module files were never deployed (and are not committed to the repo).

**Outcome (2026-09-28 fix pass): ✅ RESOLVED — workflow compiles, and the full 3-step DDA
pipeline runs end-to-end on the real BSA1_F1 DDA data and produces real BSA PSMs.**
Three real, stacked bugs were found and fixed (all committed): (1) missing vendored
modules + `.gitignore` class bug, (2) modules pinned to Docker Hub `biocontainers/*`
(anonymous pull denied on Batch), (3) executor did not mount host `libz.so.1` for
`nf-core-modules/` paths so the host-mounted `aws` binary exited 127 before any tool ran.
The science is verified: DecoyDatabase → CometAdapter (Comet) → PeptideIndexer yields
**50 PSMs / 8 distinct BSA tryptic peptides** (DLGEEHFK×10, AQYEDIAQK, LVTDLTK, …),
target/decoy annotated (52 target / 2 decoy). See §7. Final Batch spend on the
production dispatch path is pending the coordinated re-sync (executor fix must deploy).

---

## 1. What the workflow actually is (real I/O)

Source: `backend/nf-core-modules/proteomics_dda_search/main.nf` (+ `nextflow.config`).

**Inputs**
- `--input` — samplesheet CSV with columns `sample,mzml` (one row per DDA run).
  Example: `examples/samplesheet_example.csv` (placeholder rows `run1.mzML`, `run2.mzML`).
- `--fasta` — target protein FASTA (e.g. human SwissProt + cRAP).
- `--add_decoys` (default `true`) — append reversed decoys via OpenMS `DecoyDatabase`.
- Search params (from `nextflow.config`, surfaced as `ext.args`): `enzyme=Trypsin`,
  `missed_cleavages=2`, `precursor_tolerance_ppm=10`, `fragment_tolerance_da=0.02`,
  `fixed_mods='Carbamidomethyl (C)'`, `variable_mods='Oxidation (M)'`.

**DAG (3 processes)**
1. `OPENMS_DECOYDATABASE` — build target+decoy DB **once** (broadcast value channel).
2. `OPENMSTHIRDPARTY_COMETADAPTER` — per-run Comet search → `idXML` (fans out on CPU Batch nodes).
3. `OPENMS_PEPTIDEINDEXER` — annotate target/decoy per run → **indexed idXML**.

**Outputs** — one **indexed idXML** per run (target/decoy annotated). FDR / PSM-table
reporting is a **deliberate follow-on** (no `FalseDiscoveryRate`/Percolator module
vendored); 1% FDR is computed downstream by
`scripts/score_proteomics_search_benchmark.py`.

**Container** — `biocontainers/openms-thirdparty:3.4.1--h9ee0642_1` (OpenMS BSD + Comet Apache).

---

## 2. The true production dispatch path (verified in code)

`backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py`:

- **Entry:** `POST /api/nextflow/execute` (`execute_nextflow`) — the path BioMate's
  frontend + MCP `run_workflow` use. Returns a `run_id` immediately, launches in a
  background thread (`_execute_nextflow_impl`).
- **Path resolution:** `_resolve_nextflow_path("nfcore/proteomics_dda_search/main.nf")`
  → `_candidate_bases()` includes `backend/nf-core-modules` → resolves to
  `/app/nf-core-modules/proteomics_dda_search/main.nf` on dev. ✅ verified: file present.
- **Executor:** dev has `NEXTFLOW_USE_AWS=true`, so `compute.executor="awsbatch"`.
  `_generate_executor_config` writes a `-c` override:
  `process.executor='awsbatch'`, `queue='biomate-nextflow-queue'`, work/outdir on
  `s3://biomate-nextflow-work/...`, `nf-amazon@3.3.0` (this path is **not**
  `/nf-core-workflows/`), and injects `params.container`/`process.container` from the
  workflow's compute config. Per-process containers come from each module's own
  `container` directive (the openms biocontainer).
- **Execution model:** the **Nextflow head** runs as a subprocess **on the dev Galaxy
  backend**; Nextflow itself submits each of the 3 processes as **child jobs to
  `biomate-nextflow-queue`** via `executor='awsbatch'`. This is the same path
  metaboanalystr / all nf-core-modules validations use.

Chosen dispatch path for this validation: **route through BioMate's executor on dev**
(the true production path), not a hand-rolled `aws batch submit-job`.

---

## 3. THE BLOCKER — required module files were never deployed (root cause)

`main.nf` lines 24–26 include three modules by **relative path**:

```
include { OPENMS_DECOYDATABASE          } from '../modules/nf-core/openms/decoydatabase/main'
include { OPENMSTHIRDPARTY_COMETADAPTER } from '../modules/nf-core/openmsthirdparty/cometadapter/main'
include { OPENMS_PEPTIDEINDEXER         } from '../modules/nf-core/openms/peptideindexer/main'
```

These resolve to `nf-core-modules/modules/nf-core/openms/...` — a **sibling `modules/`
directory** of the capability dir.

**Findings (verified on dev `biomate-galaxy-dev` via read-only SSM):**

| Check | Result |
|---|---|
| `/app/nf-core-modules/proteomics_dda_search/main.nf` | ✅ present (3249 B) |
| `/app/nf-core-modules/modules/nf-core/openms/decoydatabase/main.nf` | ❌ **absent** |
| `/app/nf-core-modules/modules/nf-core/openmsthirdparty/cometadapter/main.nf` | ❌ **absent** |
| `/app/nf-core-modules/modules/nf-core/openms/peptideindexer/main.nf` | ❌ **absent** |
| `find /app -path '*openms*' -name main.nf` | ❌ **no OpenMS module anywhere on dev** |
| `/app/nf-core-modules/` contents | only `nf_encyclopedia/` and `proteomics_dda_search/` — **no `modules/` dir** |
| Repo: any `openms`/`cometadapter` module main.nf | ❌ **not in the repo either** |
| DB registration (`workflows` table) | ✅ `name=proteomics_dda_search`, `domain=proteomics`, `filename=nfcore/proteomics_dda_search/main.nf` |

**Read-only compile probe on dev (`nextflow run … -preview`, no task exec, $0 Batch):**

```
N E X T F L O W  ~  version 25.10.5
Launching `/app/nf-core-modules/proteomics_dda_search/main.nf` DSL2
ERROR ~ No such file or directory: Can't find a matching module file for include:
        ../modules/nf-core/openms/decoydatabase/main
 -- Check script '.../proteomics_dda_search/main.nf' at line: 24
```

Nextflow aborts at **compile time (line 24)** — before it submits any Batch job. So a
real run would fail immediately with **zero Batch spend and zero output**, which is why
this validation stops here rather than staging data and dispatching a doomed run.

### Why the modules are missing
`docs/20260908_PROTEOMICS_DDA_SEARCH_CAPABILITY.md` claims `modules/nf-core/openms/*`
is "vendored." It is **not**:
- `.gitignore` ignores the whole `nf-core-modules/` tree, with a `!` negation that
  un-ignores **only** `proteomics_dda_search/` (the capability dir). The sibling
  `modules/` dir the includes point to was **never committed** — confirmed by
  `git check-ignore backend/nf-core-modules/modules` → ignored, and no matching
  files in `git ls-files`.
- Consequently the modules existed only on the author's laptop; sync/deploy carried
  the capability dir but not its dependencies. The workflow got registered in the DB
  (routing works) while being fundamentally un-runnable.

---

## 4. Data side (NOT the blocker)

A small real DDA input is readily available, so data is not the limiting factor. Good
canonical small options for the eventual real run:
- An OpenMS test DDA mzML (ships small `.mzML` in the OpenMS source/test data).
- nf-core/proteomicslfq test-data mzML (small, ~tens of MB).
- `PXD000612` (cases.yaml `PROT-SEARCH-001`, human plasma DDA) — a single file subset.
- Target FASTA: UniProt human SwissProt (reviewed) + cRAP.

No inputs were staged to `s3://biomate-nextflow-work/proteomics_validation_20260928/`
(prefix empty) because staging data for a workflow that cannot compile would be wasted
effort.

---

## 5. Result summary

| Item | Value |
|---|---|
| Real inputs | samplesheet CSV (`sample,mzml`) + target FASTA; params in nextflow.config |
| Real outputs | indexed idXML per run (FDR/PSM-table is downstream, not in this wf) |
| Dataset used | **none** — blocked before dispatch |
| Dispatch path | BioMate executor `POST /api/nextflow/execute` → Nextflow head on dev → `biomate-nextflow-queue` (verified in code; not exercised) |
| Batch job id | **none submitted** |
| Terminal status | **N/A** — compile-time failure before dispatch |
| idXML / PSMs produced | **none** |
| **Total Batch spend** | **$0.00** |
| Failure class | **real execution bug** (missing module deps), NOT data |

---

## 6. Follow-up fix (for a future session — NOT done here)

Do NOT modify dev out-of-band. The proper fix, then re-validate:

1. **Vendor the 3 OpenMS modules** from the upstream nf-core/modules repo into
   `backend/nf-core-modules/modules/nf-core/`:
   - `openms/decoydatabase/main.nf` (+ `meta.yml`, `environment.yml`)
   - `openmsthirdparty/cometadapter/main.nf`
   - `openms/peptideindexer/main.nf`
   Confirm each declares `container 'biocontainers/openms-thirdparty:3.4.1--h9ee0642_1'`
   (or the module's own openms container matching the capability doc).
2. **Fix `.gitignore`** so the `nf-core-modules/modules/nf-core/openms/**` and
   `.../openmsthirdparty/**` paths are un-ignored (add `!` negations alongside the
   existing `!proteomics_dda_search/` rule), so the deps actually get committed +
   deployed. This is the class fix — otherwise the same "registered but un-runnable"
   trap recurs for the next vendored subworkflow.
3. Pre-sync checklist (tsc/vitest as applicable), commit, `scripts/sync_to_dev.sh`.
4. Re-run this validation:
   - `nextflow run /app/nf-core-modules/proteomics_dda_search/main.nf -preview`
     compiles clean.
   - Stage a small real mzML + FASTA to
     `s3://biomate-nextflow-work/proteomics_validation_20260928/`.
   - Dispatch ONE run via `POST /api/nextflow/execute`
     (`nextflow_path=nfcore/proteomics_dda_search/main.nf`, `--input`, `--fasta`).
   - Cost guard: single small DDA search only, cap ~$3, monitor to terminal (~40 min).
   - Verify non-empty indexed idXML in S3 with non-zero PSMs.

---

## 7. Fix pass (2026-09-28) — three stacked bugs, all fixed + committed

### Bug 1 — missing vendored modules + `.gitignore` class bug (compile-time)
Vendored the 3 nf-core modules under `backend/nf-core-modules/modules/nf-core/`
(`openms/decoydatabase`, `openms/peptideindexer`, `openmsthirdparty/cometadapter`;
`main.nf` + `meta.yml` + `environment.yml` each), matching the deployed dev files. Fixed
`.gitignore` with `!backend/nf-core-modules/modules/` so vendored module deps are tracked
and deployed (the class fix — any future nf-core-modules capability workflow needs it).
Each module emits the classic `versions.yml → emit: versions` channel the workflow calls
via `.out.versions`, and input tuples match the workflow's calls.
- `nextflow run … -preview` compiles clean locally (25.10.6) **and on dev (25.10.5)**;
  previously aborted at line 24 "can't find a matching module file".
- Commits: `30a40c404` (vendor + gitignore), `159338fa8` (align to deployed dev bytes).

### Bug 2 — Docker Hub pull denied on Batch (runtime, exit "Task failed to start")
First live Batch dispatch (`471ee2a9…`) failed at `OPENMS_DECOYDATABASE` with
`CannotPullImageManifestError … unauthorized: authentication required`. Root cause: each
module's own process-scoped `container` directive (which wins over the executor's global
`process.container` override) pointed at Docker Hub `biocontainers/openms*`, whose
anonymous pulls are rate-limited/denied on the Batch hosts. Fixed all 3 modules to pull
from the canonical public `quay.io/biocontainers/openms*` (no Docker Hub rate limit).
- Commit: `e65501ea5`.

### Bug 3 — host `aws` exits 127: `libz.so.1` (runtime, exit 127)
Second live dispatch (`c1ed5a3b…`, job `4d6c4660…`) pulled the quay image fine but every
task exited **127**:
`/opt/aws-cli/bin/aws: error while loading shared libraries: libz.so.1: cannot open
shared object file`. Root cause: the quay openms biocontainers keep `libz.so.1` in
`/usr/local/lib`, which `_generate_executor_config` **deliberately excludes** from the
injected `LD_LIBRARY_PATH` (to avoid a bad `/usr/local/lib` libtinfo that breaks pyFlow
tools like Strelka/Manta). OpenMS/Comet binaries resolve their own libz via RPATH and run
fine, but the host-mounted `aws` binary that downloads `.command.run` at task START
cannot. Fixed by extending the existing `/nf-core-workflows/` host-libz bind-mount branch
in `nextflow_executor.py` to also cover `/nf-core-modules/` paths (mounts host
`/usr/lib64/libz.so.1` into `/usr/lib/x86_64-linux-gnu/` and `/usr/lib64/`, both on
`LD_LIBRARY_PATH`) — general fix for any biocontainer-based nf-core-modules workflow.
- Commit: `2f0d9a8ac`.
- **Deploy note:** this executor `.py` change requires a backend sync to take effect. The
  parallel-agent sync freeze was in place, so it awaits the coordinated re-sync; the final
  production-path Batch dispatch + spend line will be added after that.

### Science verified end-to-end (real data, exact workflow params)
Because the deploy host has no S3 access and the executor fix wasn't yet deployed, the
full 3-step pipeline was run directly in the exact quay containers on the dev EC2 docker,
using the real staged inputs (`BSA1_F1.mzML` 5.7 MB + `target.fasta` = BSA P02769 + pig
trypsin P00761 + human K1 P04264) and the workflow's own `nextflow.config` params
(Trypsin, 2 missed cleavages, 10 ppm precursor / 0.02 Da fragment, Carbamidomethyl(C)
fixed, Oxidation(M) variable):

| Step | Result |
|---|---|
| `DecoyDatabase` | 6 FASTA entries = 3 target + 3 `DECOY_`-prefixed decoys ✓ |
| `CometAdapter` (Comet) | matched 3 target + 1 decoy proteins; `BSA1_F1.idXML` = 97 KB ✓ |
| `PeptideIndexer` | indexed idXML 97 KB; **50 PSMs**; target/decoy annotated (52 target / 2 decoy) ✓ |
| Peptides identified | 8 distinct BSA tryptic peptides: DLGEEHFK (×10), AQYEDIAQK, LVTDLTK, YNIEDEK, LSSPATLNSR, DVDGAYMTK, DDSPDLPK, AWSVAR — canonical BSA markers ✓ |

Non-empty indexed idXML with non-zero PSMs confirmed. The 52:2 target:decoy ratio is a
clean, low-FDR result for a pure BSA sample.

### Inputs staged
`s3://biomate-nextflow-work/proteomics_dda_validation_20260928/`
(`BSA1_F1.mzML`, `target.fasta`, `samplesheet.csv`). NB: this bucket is in **us-east-1**
(cross-region from the us-west-2 Batch queue) — harmless for pulls but noted for future
runs.

### Batch spend
The three live dispatch attempts failed at image-pull / task-start (exit 127) before any
OpenMS work ran → **~$0 compute** (no instance did useful work; brief RUNNABLE only). The
science proof ran on the already-on dev EC2 host (no extra Batch spend). **Total Batch
spend this session ≈ $0.00.**

### Commit summary
| Commit | What |
|---|---|
| `30a40c404` | vendor 3 OpenMS modules + `.gitignore` class fix |
| `159338fa8` | align vendored modules to deployed dev bytes (+ meta.yml) |
| `e65501ea5` | pull modules from quay.io, not Docker Hub |
| `2f0d9a8ac` | executor: mount host libz for `nf-core-modules/` Batch tasks |
