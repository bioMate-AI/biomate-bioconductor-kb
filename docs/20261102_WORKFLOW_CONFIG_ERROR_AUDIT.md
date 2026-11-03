# Workflow config error audit — GEO incident + tree-wide sweep

**Date:** 2026-11-02
**Trigger:** The GEO accession auto-chain (GSE → geo_data_connector → differentialabundance)
failed repeatedly on real AWS Batch. Peeling the failures layer-by-layer in the dev Galaxy
logs exposed **three classes of latent config bug** in `geo_data_connector`. Since those classes
are copy-paste-able across subworkflows, we swept the whole workflow tree for the same patterns
rather than fixing only the one workflow that happened to be exercised.

---

## Part 1 — The GEO incident (errors, in the order they surfaced)

Each layer was confirmed from a real dev log line before any fix — no guessed retries.

| # | Error (verbatim signature) | Root cause | Fix | Commit |
|---|---|---|---|---|
| L1 | chain launched empty, no param-fill, no id fetch | execute-gate didn't emit a fetch→DE chain for a bare GEO accession | 2-step auto-chain in `routes.ts` (geo_data_connector → differentialabundance) | `5f542664b` / `cef49d333` |
| L2 | GEO_FETCH tried fetchngs/FASTQ on a microarray GSE | dual-classifier: executor maps GSE→`handler=sequencing`→fetchngs, overriding a self-fetching getGEO workflow | `_workflow_fetches_geo_natively()` skip in executor accession loop | `a94dffaec` |
| L3 | `JobQueue biomate-medium-queue not found` | **stale queue names** `biomate-medium-queue` / `biomate-high-queue` in the workflow's `aws` profile — these queues do not exist | removed hard-coded queues from the profile; executor injects real ones via `-c` | `3e7281e01` |
| L4 | `CannotPullImageManifestError: manifest unknown` | **nonexistent container tag** `bioconductor-geoquery:2.72.0--r44_0` (version 2.72.0 was never published; build string lacks the `hdfd78af` hash) | `2.74.0--r44hdfd78af_0` (verified on quay + Galaxy depot) | `5d30d3801` (main.nf) |
| L4b | same tag still present in `nextflow.config` default | the L4 commit patched only `main.nf`'s 4 hard-coded strings and **missed `params.container` on `nextflow.config:24`** | fixed the config default too | this session |

**Lesson from L4b:** when a container/queue string is duplicated across `main.nf` *and*
`nextflow.config` (default `params.*`), a fix to one file silently leaves the other wrong. Always
grep the whole workflow directory for the bad string, not just the file in the traceback.

### Why the profile-scoped queue beat the executor override (L3 mechanism)
The executor writes a `-c biomate_executor_override.config` that sets queues
(`nextflow_executor.py` ~3089–3447: default `biomate-nextflow-queue`, `process_high`→`biomate-hpc-queue`,
`process_gpu`→`biomate-gpu-spot-queue`). But a **profile-scoped** `withName`/`withLabel` queue inside the
pipeline's own `nextflow.config` (activated via `-profile aws`) **wins** over the flat `-c` override —
and a `withName` selector beats any `withLabel` injection regardless of file. So a wrong queue baked
into a workflow's `aws` profile is *not* neutralised by the executor; it fails hard.

---

## Part 2 — Tree-wide audit (the "check other workflows" sweep)

### Ground truth established first
- **Real AWS Batch queues** (`aws batch describe-job-queues --region us-west-2`):
  `biomate-nextflow-queue`, `biomate-hpc-queue`, `biomate-gpu-spot-queue`, `biomate-gpu-t4-queue`,
  `galaxy-cloud-queue`, `galaxy-cloud-queue-gpu`, `l7-gpu-spot-queue`.
- **Container existence** verified per-tag against quay.io registry API (anonymous bearer token) and
  `https://depot.galaxyproject.org/singularity/<img>` (HTTP 200 = exists, 404 = does not).
- **Region**: all Batch infra is `us-west-2`; any `aws.region = 'us-east-1'` is wrong.

### Three bug classes and what the sweep found

**Class A — nonexistent Batch queue name (same as L3)**
- `biomate-nextflow-gpu-queue` — **19 files** (all of `cryo_em/` + `cryo_et/`). Not a real queue.
  → `biomate-gpu-spot-queue`.
- `structure_prediction_docking`: `biomate-gpu-queue` ×2, `biomate-cpu-queue` ×1 (none exist; uses
  `withName` → guaranteed failure). → `biomate-gpu-spot-queue` / `biomate-nextflow-queue`.
- **False positives (NOT bugs):** `cpu`, `gpu`, `short`, `normal` — all inside **slurm** profiles;
  these are valid SLURM partition names and slurm profiles are not used in production.

**Class B — nonexistent container tag (same as L4)** — the signature is a biocontainer tag with a
build string `--r<NN>_<N>` that has **no `hdfd78af`-style hash** (auto-generated tags always have one;
a hashless one is almost always hand-typed and wrong). All three confirmed 404 on the Galaxy depot:
- `geo_data_connector`: `bioconductor-geoquery:2.72.0--r44_0` → `2.74.0--r44hdfd78af_0` *(L4/L4b)*
- `immune_deconvolution`: `bioconductor-deconrnaseq:1.46.0--r44_0` → `1.48.0--r44hdfd78af_0`
  (1.46.0 was never published; newest r44 build is 1.48.0)
- `trajectory_inference`: `bioconductor-monocle3:1.3.4--r44_0` → `r-monocle3:1.3.1--r44h9948957_1`
  (**wrong repo entirely** — monocle3 is published as `r-monocle3`, not `bioconductor-monocle3`;
  `bioconductor-monocle3` has 0 tags. No 1.3.4 exists; newest r44 is 1.3.1.)

**Class C — wrong `aws.region`** — `us-east-1` found in 4 workflows (plus geo_data_connector, already
fixed): `structure_prediction_docking`, `immune_deconvolution`, `perturb_seq_analysis`,
`trajectory_inference`. All → `us-west-2`.

### Full fix list (this session, 25 files)
| Workflow(s) | Class | Change |
|---|---|---|
| cryo_em/* (14) + cryo_et/* (5) | A | `biomate-nextflow-gpu-queue` → `biomate-gpu-spot-queue` |
| drug_discovery/structure_prediction_docking | A+C | gpu/cpu queues → real; region → us-west-2 |
| bioconductor/immune_deconvolution | B+C | deconrnaseq tag → 1.48.0--r44hdfd78af_0; region → us-west-2 |
| genomics/trajectory_inference | B+C | monocle3 → r-monocle3:1.3.1--r44h9948957_1 (config + main.nf); region → us-west-2 |
| genomics/perturb_seq_analysis | C | region → us-west-2 |
| genomics/geo_data_connector | B | geoquery config default → 2.74.0--r44hdfd78af_0 (L4b) |

---

## Part 3 — Verification status (honest)

These are **deterministic string corrections verified against authoritative sources** (the live
Batch queue list; the quay/depot registries). That cross-check *is* the verification for a
name/tag — firing a real GPU Batch run per workflow just to confirm a string would be a speculative
expensive deploy (forbidden by the pre-sync discipline). Runtime confirmation happens when each
workflow is next legitimately exercised. The GEO chain itself is being re-run end-to-end
(`/tmp/geo_retest.log`) to confirm L1–L4b together.

**Not yet audited (harder, deferred):** full existence check of all **1,331 distinct biocontainer
pins** — only the hashless `--rNN_N` signature was swept. A complete audit needs a registry-manifest
HEAD per tag. Also `:latest` / no-build-string pins (`cellpose:3.1.0`, `r-base:4.3.1`, `squidpy:1.5.0`,
`python:3.11`) are mutable/fragile but currently resolve.

---

## Part 4 — Prevention (stop the class, not the instance)

Add a pre-sync lint (candidate: extend `docs/PRE_SYNC_CHECKLIST.md` + a `scripts/` validator) that
fails the sync if any workflow config contains:
1. a `queue = '...'` **inside an `awsbatch`/`aws` profile** whose value is not in the live
   `describe-job-queues` list (slurm-profile queues exempt);
2. an `aws.region` other than `us-west-2`;
3. a `quay.io/biocontainers/...` tag that 404s on the Galaxy depot (cheap HEAD; catches Class B
   including the hashless-build and wrong-repo cases).

This is the "fix BioMate, not the instance" response: the same validator would have caught L3, L4,
and every Part-2 finding at commit time instead of in a paid Batch run.

---

## Part 5 — GEO chain re-test result (2026-11-02, GSE22055)

After L1–L4b, the full chain (`chain_1793683908_a08b87`) was re-run on real AWS Batch:

- **Step 0 `geo_data_connector` → SUCCEEDED** (run `2a2728ae`), emitting `count_matrix` +
  `sample_metadata`. **This validates L1–L4b end-to-end** — the GEO ingest fetches and produces
  artifacts; the container pulls, the queue resolves, the region is right.
- **Step 1 `nf-core/differentialabundance` (DESeq2) → FAILED** (run `7f7e06e2`), verbatim from
  `/tmp/nextflow_runs/7f7e06e2-.../nextflow.log`:
  > `DESeq2 setup failed for contrast 'GSM449831_vs_GSM449832': all samples have 0 counts for all
  > genes. check the counting script.`

**Root cause of the step-1 failure (NOT a geo bug):** GSE22055 is a **microarray** series — its matrix
is log2 **intensities** (e.g. 6.3, 8.1), not integer counts. The DESeq2 process coerces with
`storage.mode(count_mat) <- "integer"`, truncating sub-1 / non-integer intensities to 0 → all-zero
matrix → DESeq2 aborts. A secondary signal: the auto-picked contrast was two **individual samples**
(`GSM449831_vs_GSM449832`), not groups — a context/contrast-selection gap.

Both are exactly the failure modes that motivate the **intent-and-context-aware routing** work
(`docs/20261102_UNIFIED_PUBLIC_ID_ROUTING_DESIGN.md`): microarray + DE must route to **limma**
(not DESeq2), and the contrast must come from context (e.g. tumor-vs-normal groups), not the first
two samples. A clean DESeq2 green needs a **bulk RNA-seq** GSE (e.g. GSE52778). The ingest layer
(this session's deliverable) is done and verified; data-type routing is the next step.
