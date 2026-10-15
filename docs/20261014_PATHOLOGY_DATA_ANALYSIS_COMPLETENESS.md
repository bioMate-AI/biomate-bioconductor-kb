# Pathology Data-Analysis Completeness (2026-10-14)

Assessment + build/validation of BioMate's ability to **analyze pathology data**
(not instrument connection). Question driving this: how complete, and for the
most common formats/tools, is it actually proven to run?

## Inventory (14 pathology-relevant workflows in `galaxy_ai_tools.db`)

| Capability (common path) | Workflow | Container | Validated (before) |
|---|---|---|---|
| WSI H&E → tiling/QC → nuclei seg → cell table (OpenSlide `.svs`/OME-TIFF + Cellpose) | `wsi_he_nuclei_segmentation` (id 14651) | `bioc-domain-pathology:1.0` ✅ purpose-built | `real_exec_status=None` |
| IHC quantification (protein expr + spatial) | `analyze_immunohistochemistry_image` (id 10695) | `biomni-tools` | None |
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

## Remaining to a "complete" common pathology suite
1. **IHC** (`analyze_immunohistochemistry_image`) — validation in progress (demo
   mock-image path; real-IHC-image run is a stronger follow-up).
2. **Multiplex** (`segment_and_quantify_cells_in_multiplexed_images`) — needs a
   multichannel test image + a Batch run.
3. **`nf-core/mcmicro`** — `docker_image` empty → won't run until a container is pinned.
4. **Stain normalization** (Macenko/Reinhard) as a reusable standalone step
   (currently only `rgb2hed` embedded in the WSI pipeline).
5. **Tissue/tumor-content classification** (tile classifier; the frontier-FM route
   = UNI/CONCH/Virchow2 is the heavier B2 track).

## Infra note
`/api/nextflow/status/<nfRunId>` returns 404 for a direct nextflow run (status not
served at that path for direct runs) — S3 `qc_summary.json` is the terminal signal.
Worth fixing if other tooling polls that route.
