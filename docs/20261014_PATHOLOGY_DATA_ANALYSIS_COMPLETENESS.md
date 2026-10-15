# Pathology Data-Analysis Completeness (2026-10-14)

Assessment + build/validation of BioMate's ability to **analyze pathology data**
(not instrument connection). Question driving this: how complete, and for the
most common formats/tools, is it actually proven to run?

## Inventory (14 pathology-relevant workflows in `galaxy_ai_tools.db`)

| Capability (common path) | Workflow | Container | Validated (before) |
|---|---|---|---|
| WSI H&E → tiling/QC → nuclei seg → cell table (OpenSlide `.svs`/OME-TIFF + Cellpose) | `wsi_he_nuclei_segmentation` (id 14651) | `bioc-domain-pathology:1.0` ✅ purpose-built | `real_exec_status=None` |
| IHC quantification (protein expr + spatial) | `analyze_immunohistochemistry_image` (id 10695) | `biomni-tools` | None → **fixed + `ok`** (run 22ae9a78) |
| H&E histology (thrombus, CNS-lesion) | 2 biomni workflows | biomni-tools | None |
| Multiplex IF (segment + quantify) | `segment_and_quantify_cells_in_multiplexed_images` (10760); `nf-core/mcmicro` (12729) | biomni-tools / **mcmicro: empty** 🛑 | None |
| IF / morphometry (corneal nerve, Rhod2, bone µCT, aortic) | 5 biomni workflows | biomni-tools | None |

**Key finding:** the surface was broad but **unproven** — every pathology row had
`real_exec_status=None` (claimed `executable=1`, never a recorded green run). The
real completeness gap was proof + the input contract, not missing workflows.

## What was done this session

### 1. WSI H&E pipeline — VALIDATED end-to-end (the common core) ✅
Two real AWS Batch runs via `POST /api/workflows/execute`, graded on terminal
success + S3 outputs (BioMate's execution-grading standard):
- **Demo `.svs`** (run `72fbd99c`): OpenSlide opened CMU-1-Small-Region.svs
  (2220×2967, mpp 0.499) → 17 tissue tiles → **441 Cellpose nuclei** → full S3
  outputs (`cell_table.csv`, `qc_overlay.png`, `qc_summary.json`, 17 tile masks,
  manifest, RUO report). `bioc-domain-pathology:1.0` stack (openslide-python
  1.4.6 + scikit-image 0.25.2 + torch) imported — the combo no off-the-shelf
  biocontainer provides.
- **s3 user slide** (run `08ce958f`): same pipeline on
  `s3://biomate-nextflow-work/test-wsi/CMU-1-Small-Region.svs`; `qc_summary.json`
  confirms `is_demo:false`, `source:"user_supplied (fetched from s3://…)"`, 441
  nuclei. Proves the real user-upload path.

### 2. Input-contract fix — WSI now accepts http/s3 URIs (commits `276f6728`, `7464e23e`)
The pipeline was demo-only: `input_wsi` required a LOCAL path (`os.path.exists`),
so a user slide staged as an `s3://` URI failed. Added `_fetch_remote_wsi`:
- `http(s)://` → `urllib.urlretrieve` (same mechanism the demo already used).
- `s3://` → boto3, falling back to the executor's **bind-mounted aws CLI**
  (`/opt/aws-cli`, per `Dockerfile.pathology`), resolved via `shutil.which` +
  explicit paths. Honest-fail with a clear message if neither is available.
- Local paths + the param-less demo quick-run unchanged. Embedded python
  `py_compile`s; both branches validated on Batch (demo=http mechanism, s3=run 08ce958f).

### 3. Recorded validation
`wsi_he_nuclei_segmentation` → `real_exec_status='ok'` + `real_exec_at` +
`real_exec_produced` (run IDs + outputs) written to the **local** canonical DB
(row-count guard passed, 4210 rows). NOT yet DB-synced to dev: the 322 MB
workflow DB is gitignored, so a DB sync re-uploads the whole file and could revert
a concurrent session's dev-side DB change not present locally — so this flag
propagates on a deliberate DB sync once local==dev is confirmed. The authoritative
proof meanwhile is the two green runs + S3 outputs.

### 4. IHC pipeline — was BROKEN, now FIXED + VALIDATED ✅ (commit `7a025b5f`)
First validation (run `6f645eea`) exposed three real defects behind
`executable=1`: (a) **phantom demo** — the comment promised a mock image but no
code generated it, so the default `image_path` didn't exist and `io.imread`
failed; (b) **dishonest success** — the load error was returned as a string, so
the run recorded `success:true` and exited 0 (a failed analysis logged as
successful); (c) no http/s3 input fetch. Fixes: `_resolve_image_path` uses the
REAL scikit-image reference IHC image (`data.immunohistochemistry()`) for the
demo + fetches http/s3 URIs; load failure now raises → `success:false` → exit 1.
Re-validated (run `22ae9a78`, param-less): genuine `success:true`, real metrics —
**27 tissue regions**, protein-expression quantification (total intensity
91380.05, avg 0.73), spatial distribution (avg 235.47 px) — loaded from the real
reference image. `real_exec_status='ok'` recorded (row 10695, local DB).

### 5. Systemic integrity remediation across the biomni stubs (2026-10-15)
Execution-grading the biomni image/assay workflows exposed a **class defect**:
(a) **dishonest success** — a failure returned as an error STRING so the caller
recorded `success:true`/exit 0; (b) **fabrication** — stubs inventing metrics
(cns_lesion hardcoded 1250/7.5 + clinical interpretation; quantify_cell_cycle RNG
counts). Scope: 2 fabrication + 15 dishonest-success out of 2,239 (the broad
bioconductor/nf-core catalog is genuine; "simulate" hits like SimBu are real
simulation packages). All 17 fixed + re-validated param-less on Batch:
- **Dishonest-success ELIMINATED 17/17** — failures now raise → honest non-zero
  exit, no `results.json`; legitimate empty results ("no FDA match", "no BLAST
  hits", image-only PDF) kept as valid successes.
- **Both fabrication stubs honest-fail** — no invented numbers.
- **8 genuinely validated** (`real_exec_status='ok'`, local DB): WSI + IHC +
  corneal_nerve, multiplex, calcium_imaging, blast_sequence (real NCBI BLAST),
  protease_kinetics, panhumanpy.
- **7 honest-fail, follow-up:** 3 image (`aortic`, `mitochondrial`, `cell_morphology`)
  — root cause **cv2/opencv missing from biomni-tools** (opencv-python-headless added,
  commit 603722965; needs a biomni-tools:x86 rebuild+push); 4 external-API (`fda_*`,
  `pdf`) — suspected Batch worker egress to api.fda.gov / PDF host (BLAST reached
  NCBI, so egress is partial), pending triage.

## Remaining to a "complete" common pathology suite
1. **Multiplex** (`segment_and_quantify_cells_in_multiplexed_images`) — no demo
   path; needs a multichannel test image + a Batch run.
2. **`nf-core/mcmicro`** — full nf-core pipeline; `docker_image` empty (nf-core
   self-resolves per-module containers, so this may not be the real blocker) but
   validating it needs real CODEX/CyCIF data + a sample sheet + heavy compute.
3. **Stain normalization** (Macenko/Reinhard) as a reusable standalone step
   (currently only `rgb2hed` embedded in the WSI pipeline).
4. **Tissue/tumor-content classification** (tile classifier; the frontier-FM route
   = UNI/CONCH/Virchow2 is the heavier B2 track).

## Infra note
`/api/nextflow/status/<nfRunId>` returns 404 for a direct nextflow run (status not
served at that path for direct runs) — S3 `qc_summary.json` is the terminal signal.
Worth fixing if other tooling polls that route.
