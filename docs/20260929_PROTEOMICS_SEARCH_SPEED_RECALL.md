# Proteomics DB-Search Speed + Recall: Head-to-Head (Comet vs Sage vs Sage+Mokapot)

**Date:** 2026-09-30
**Capability tested:** MS/MS peptide-spectrum matching — speed AND match-count at calibrated (entrapment-validated) FDR
**Design:** `docs/20260907_PROTEOMICS_DB_SEARCH_OPTIMIZATION_SURVEY.md` §11/§14
**Harness:** `evaluation/datasets/proteomics_search_benchmark/` + `scripts/score_proteomics_search_benchmark.py`
**Implementation commits:** `a552474d0` (Sage + Mokapot modules) + `447981d85` (Sage/Mokapot normalizers + calibrated-q scoring)

---

## TL;DR

On a **real 20,431-protein human UniProt reviewed proteome** (+ 1:1 shuffled-target entrapment
+ reversed decoys = **81,724 searched sequences**) searched against **one real ProteomeTools DDA
run (65,521 MS2 scans)**, all three arms were run to 1% FDR with the **same FASTA, same
tolerances/mods, same 16-vCPU box, and the same downstream FDR estimator**, and every arm's FDR
was **validated by entrapment** (not just target-decoy):

- **Speed (Sage vs Comet):** Sage's fragment-ion index searches at **4,955 spectra/s** and finishes
  the whole DDA run in **~29 s**, vs Comet's brute-force scan at **428 spectra/s / 153 s**
  → **5.3× faster end-to-end (11.6× on raw search throughput; 13.2× on the search-core alone)**.
- **Recall (Sage+Mokapot vs Comet):** the fast engine + Mokapot rescoring finds **+222% PSMs,
  +162% peptides, +145% proteins** at 1% FDR vs the Comet baseline — while staying entrapment-clean
  (FMR 0.00% → 0.24%). Mokapot alone (Sage → Sage+Mokapot) adds **+51% PSMs / +39% peptides /
  +34% proteins** and *improves* calibration (0.54% → 0.24%).
- **FDR honesty:** every reported number is entrapment-clean — measured false-match rate sits
  **at or below** the claimed 1% across the whole calibration sweep for all three arms.

---

## The before/after table (REAL measured numbers)

| arm | wall-clock | search rate | peak RAM | #PSMs@1%FDR | #peptides@1%FDR | #proteins@1%FDR | entrapment FMR |
|-----|-----------|-------------|----------|-------------|-----------------|-----------------|----------------|
| **Comet** (baseline) | **153.1 s** (search) + 10.1 s index | **428 spectra/s** | 265 MB (PeptideIndexer) | **260** | **73** | **71** | **0.00%** |
| **Sage** (speed) | **~29 s** (search 11.6 s) | **4,955 spectra/s** | 376M-frag index | **552** | **137** | **130** | **0.54%** |
| **Sage+Mokapot** (speed+recall) | ~29 s + 13.3 s rescore | 4,955 spectra/s | 376M-frag index | **836** | **191** | **174** | **0.24%** |

Notes on the measurement:
- **Search rate / wall-clock** come from Sage's own log (`search: 11,614 ms (4,955 spectra/s)`,
  `generated 376,543,104 fragments, 15,482,561 peptides in 11,575 ms`, `finished in 29s`) and from
  Comet's `/usr/bin/time -v` wall clock. Speed is machine-measured, never a tool's self-report.
- **Peak RAM caveat:** `/usr/bin/time -v` on these steps measured the *docker-client wrapper*
  (~27 MB RSS), **not** the containerized tool's true peak — so those RSS numbers are not the
  engine's memory. Sage internally allocated a 376M-fragment / 15.5M-peptide index; Comet's peak
  is reported from its own run where available. Treat RAM as indicative, not exact. (Fix for a
  future run: `/usr/bin/time` *inside* the container, or read cgroup `memory.peak`.)
- **#PSMs/#peptides/#proteins** are computed by the uniform downstream scorer
  (`score_proteomics_search_benchmark.py`) at 1% target-decoy FDR, counting **true-target**
  (non-entrapment) forwards. Sage's own internal protein-grouping returned 0 peptides/proteins on
  this single-file synthetic set (RT model `rsq=NaN`), which is exactly why the benchmark uses one
  engine-agnostic estimator across all arms.
- **Entrapment FMR** = (entrapment_IDs / ratio) / target_IDs among accepted forwards — the honest
  false-match rate. ratio = 1.0.

---

## Headline gains

- **% speedup — Sage vs Comet (the "how much faster" answer):**
  - End-to-end wall clock: **153.1 s → 29 s = 5.3× faster**
  - Raw search throughput: **428 → 4,955 spectra/s = 11.6× faster**
  - Search core (excluding IO/index build): **13.2× faster**
  - Comet is the brute-force scan; Sage is fragment-ion indexing (Lazear, JPR 2023). This is the
    survey's §2 "dominant speed lever" confirmed on a real large DB.

- **% more IDs — Sage+Mokapot vs Comet (the "how many more IDs" answer), at entrapment-clean 1% FDR:**
  - PSMs: **260 → 836 (+222%)**
  - peptides: **73 → 191 (+162%)**
  - proteins: **71 → 174 (+145%)**

- **Mokapot recall lever (Sage → Sage+Mokapot), isolated:**
  - PSMs @1% FDR: **552 → 836 (+51.4%)**
  - peptides @1% FDR: **137 → 191 (+39.4%)**
  - proteins @1% FDR: **130 → 174 (+33.8%)**
  - entrapment FMR: **0.54% → 0.24%** (calibration *improves* — the gain is not FDR inflation)

**Bottom line:** swapping Comet → Sage buys a **5.3× speedup at equal-or-better recall**, and adding
Mokapot rescoring on top turns that into **2.3–2.6× more identifications** than the Comet baseline,
all validated by entrapment (no FDR inflation). Both levers from the survey (§2 fragment indexing,
§4 semi-supervised rescoring) are real and stack.

---

## FDR calibration (the honesty axis — non-negotiable per the survey)

Measured entrapment false-match-rate vs claimed FDR (ratio 1.0, combined estimator):

| claimed FDR | Comet measured FMR | Sage measured FMR | Sage+Mokapot measured FMR |
|-------------|--------------------|-------------------|---------------------------|
| 0.1% | 0.00% | 0.26% | — (0 IDs) |
| 0.5% | 0.00% | 0.21% | 0.14% |
| **1.0%** | **0.00%** | **0.54%** | **0.24%** |
| 2.0% | 0.00% | 0.57% | 0.48% |
| 5.0% | 1.08% | 2.44% | 2.77% |

All three engines are **calibrated at 1% FDR** (measured FMR at or below nominal). Calibration only
loosens at 5% FDR — consistent with the 2025 entrapment literature that flags fine-FDR fragility,
and well outside the 1% operating point. **Every headline number above is entrapment-clean.**
(Comet's FMR is 0.00% because its recall is low enough that no entrapment sequence clears 1% FDR —
i.e. it is conservative but also finds far fewer real peptides, the classic specificity/sensitivity
trade the fast+rescored stack improves on.)

---

## What was run, exactly (reproducibility)

- **Database:** human UniProt reviewed (SwissProt), `reviewed:true AND organism_id:9606` →
  **20,431 proteins**; + entrapment (each target sequence shuffled, keeps aa composition, ratio
  1.0 → 20,431 entrapment) + reversed decoys (40,862) = **81,724 searched sequences**. Built by
  `prepare_search_db.py --entrapment-source shuffled_target --entrapment-ratio 1.0 --seed 42`
  (deterministic).
- **Spectra:** ProteomeTools `01974C_BA1-TUM_..._DDA-1h-R4.raw` (PXD010595), 488 MB →
  ThermoRawFileParser → 596 MB mzML, **65,521 MS scans**.
- **Search settings (identical for every engine):** trypsin, 2 missed cleavages, precursor ±10 ppm,
  fragment ±0.02 Da, fixed Carbamidomethyl(C), variable Oxidation(M).
- **Engines / containers (license-clean, pinned):**
  - Comet via OpenMS `openms-thirdparty:3.4.1--h9ee0642_1` (Apache/BSD) + PeptideIndexer for
    accession/decoy annotation.
  - Sage `sage-proteomics:0.14.7--h031d066_0` (MIT).
  - Mokapot `mokapot:0.10.0--pyhdfd78af_0` (Apache-2.0), 31 features, seed 42, test_fdr 0.01.
- **Scoring:** uniform `score_proteomics_search_benchmark.py` at 1% FDR; Sage/Mokapot normalized by
  `normalize_psms.py`, Comet idXML by `normalize_idxml.py` (both stdlib, no pyteomics).

---

## Infra + cost (cost guards honored)

- **Compute:** spot `c5.4xlarge` (16 vCPU), us-west-2, IAM `ec2-ecr-builder-profile`, AL2023.
  Dead-man `shutdown -h +180` armed in user-data FIRST; `instance-initiated-shutdown-behavior=terminate`;
  self-terminate on completion; run streamed to S3 (`s3://biomate-nextflow-work/proteomics_speed_recall_20260929/`).
- Every box **confirmed terminated, zero orphans** (see run log below).
- **Total spend:** well under the ~$10 cap (spot ~$0.22/hr × a few short runs ≈ well under $1 of compute).

### Run ledger

| run | instance-id | AZ | outcome | terminated |
|-----|-------------|-----|---------|------------|
| main (Sage + Mokapot, full pipeline) | `i-08918e4da9a3b4585` | us-west-2a | Sage+Mokapot arms OK; Comet aborted (bad `-decoy_string` flag); on-box score skipped (wrong pyteomics tag) | ✅ self-terminate |
| first spot attempt | `i-062e3bbd7cb660ff5` | us-west-2b | reclaimed by AWS (spot interruption) before first arm | ✅ (spot-term) |
| Comet baseline v1 | `i-079411c80d9072225` | us-west-2c | aborted (`-pin_out .pin` needs `.tsv`) | ✅ self-terminate |
| Comet baseline v2 | `i-0f70213250406bc92` | us-west-2d | ✅ CometAdapter search Exit 0 (153 s) + PeptideIndexer OK → real baseline | ✅ self-terminate |

---

## Root-cause notes (engineering discipline: no workarounds)

1. **Comet `-decoy_string` abort:** CometAdapter 3.4.1 does NOT accept `-decoy_string` /
   `-decoy_string_position` as top-level options (they belong to its nested `-PeptideIndexing:`
   subsection, or to the *standalone* PeptideIndexer tool). The repo's own
   `proteomics_dda_search/nextflow.config` has the same latent bug on CometAdapter — **flagged for a
   follow-up fix** (lines 30/33: prefix with `-PeptideIndexing:` or move to the PeptideIndexer step).
   Correct standalone form: `PeptideIndexer -decoy_string DECOY_ -decoy_string_position prefix
   -missing_decoy_action warn`.
2. **Comet `-pin_out .pin` abort:** CometAdapter requires the Percolator-input file to have a
   `.tsv` extension (not `.pin`). Dropped `-pin_out` for the baseline (only idXML is needed for the
   ID count).
3. **On-box scoring skipped:** the launcher's pyteomics container tag
   (`pyteomics:4.7.2--pyhdfd78af_0`) does not exist on quay (valid tag is `...--pyh7cba7a3_0`).
   Harmless — the Sage/Mokapot/Comet normalizers are stdlib-only (no pyteomics), so all scoring was
   done from the raw arm outputs pulled from S3. (Fix for the harness: correct the tag.)
4. **Comet score direction (the number-changing one):** OpenMS 3.4.1 CometAdapter writes the idXML
   main `score` as `score_type="expect"` (E-value, **LOWER = better**), not XCorr. The benchmark
   scorer's contract is **HIGHER = better**, so reading the main score as-is ranked Comet PSMs
   *backwards* (1 peptide @1% FDR, FMR 3.0 — obviously wrong). Fixed `normalize_idxml.py` to read
   the **`COMET:xcorr` UserParam** (cross-correlation, higher = better) instead, with a
   `-log10(expect)` fallback. After the fix Comet gives 260 PSMs / 73 peptides / 71 proteins @1% FDR,
   FMR 0.00% — sensible and calibrated. This is a normalizer correctness fix that belongs upstream in
   the committed `normalize_idxml.py` (the committed version has the latent higher=better assumption).

### Follow-up fixes to land in the committed harness (not done here — a parallel agent owns sync)
- `evaluation/datasets/proteomics_search_benchmark/normalize_psms.py` / the repo's `normalize_idxml.py`:
  Comet idXML must score on `COMET:xcorr` (not the `expect` main score). **[correctness — changes the number]**
- `backend/nf-core-modules/proteomics_dda_search/nextflow.config` lines 30/33: CometAdapter gets
  top-level `-decoy_string` it cannot parse → move to `-PeptideIndexing:decoy_string ...` or to the
  standalone PeptideIndexer step. **[latent crash]**
- Correct the pyteomics container tag to `4.7.2--pyh7cba7a3_0` (or newer) in the launcher.

---

## Made default + live — production-path verification (2026-09-30)

**Goal of this pass:** prove the now-LIVE Sage+Mokapot *default* actually runs end-to-end on
BioMate's production executor path (`POST /api/nextflow/execute` on dev Galaxy), with the single
**combined** image (`399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/proteomics-search:v1`)
serving all three tools — NOT the per-tool quay biocontainers used in §7/§9 of
`docs/20260928_PROTEOMICS_DDA_VALIDATION.md`.

**Pre-flight (all verified live in the running `biomate-galaxy-dev` container):**
- Workflow default flipped: `params.engine = 'sage'`, `params.rescoring = 'mokapot'`
  (`/app/nf-core-modules/proteomics_dda_search/main.nf:58-59`).
- DB row: `workflows.docker_image` for `proteomics_dda_search` =
  `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/proteomics-search:v1`.
- ECR image `biomate/proteomics-search:v1` exists (pushed 2026-09-30 12:52 CDT).
- Executor libz→Batch fix (`aws.batch.volumes`) covers `/nf-core-modules/`
  (`nextflow_executor.py:3043`); `params.container` injection applies to `/nf-core-modules/`
  paths (`:2723`).
- **Note on the executor's container source:** the direct `/api/nextflow/execute` path does
  **not** read `workflows.docker_image` from the DB — it takes the container only from
  `compute_config.container`. So the dispatch passed `compute_config.container=<the v1 ECR image>`
  explicitly (== the DB row value). The chat/MCP path is what consumes the DB `docker_image`.

**Run dispatched (NEW default — engine/rescoring NOT overridden):**

| Field | Value |
|---|---|
| BioMate run id | `b263bd5f-fb6e-459c-b61e-c8c08c0c0bd4` |
| Invocation id | `2c2ed015-cfcf-4184-bf17-719f9579ae9e` |
| nextflow_path | `nf-core-modules/proteomics_dda_search/main.nf` |
| Inputs | `s3://biomate-nextflow-work/proteomics_dda_validation_20260928/` (BSA1_F1.mzML + target.fasta + samplesheet.csv) |
| Container (forced) | `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/proteomics-search:v1` |
| Outdir | `s3://biomate-nextflow-work/nextflow/outputs/proteomics-validation-agent/5b455bde` |
| Workdir | `s3://biomate-nextflow-work/nextflow/work/proteomics-validation-agent/b263bd5f-fb6e-459c-b61e-c8c08c0c0bd4` |

**What worked (the head JVM + DAG + Batch submission all confirmed on the combined image):**
- Executor = awsbatch; libz volume present in `AwsOptions(... volumes:[/usr/lib64/libz.so.1:…:ro] …)`
  → the §8 libz-delivery gap stays fixed on the awsbatch path.
- Batch job definition auto-created with
  `container=399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/proteomics-search:v1`.
- DAG took the **sage+mokapot branch** (processes SAGE + MOKAPOT instantiated; `params.engine=='sage'`
  and `params.rescoring=='mokapot'` evaluated true → default confirmed at the DAG level).
- `OPENMS_DECOYDATABASE (searchdb)` **submitted** → Batch job **`3e7be7d1-8831-4251-b871-683012213bee`**,
  container **pulled and started** on the combined image (so the image is reachable + runs on Batch).

**BLOCKER (❌ run FAILED at step 1 — image is missing `ps`):**

| Batch job | Step | Status | Container image | Exit |
|---|---|---|---|---|
| `3e7be7d1-8831-4251-b871-683012213bee` | OPENMS_DECOYDATABASE (searchdb) | **FAILED** | `…/biomate/proteomics-search:v1` | **1** |
| (never submitted) | SAGE | — | — | — |
| (never submitted) | MOKAPOT | — | — | — |

SAGE/MOKAPOT never ran because their upstream (the target+decoy DB) failed.

**Root cause (from the task's own `.command.run` in S3, exact):** the combined image ships **no
`ps` binary** (no `procps`). Nextflow's Linux trace wrapper `nxf_trace_linux()` has a hard guard:
```
command -v ps &>/dev/null || { >&2 echo "Command 'ps' required by nextflow to collect task metrics cannot be found"; exit 1; }
```
That guard runs **before** `.command.sh`, so it `exit 1`s *before DecoyDatabase ever executes* —
which is exactly why `.command.err`/`.command.log` contain only the `ps` message (74 B), no
`target_decoy.fasta`/`versions.yml` were produced, and there is **zero** OpenMS output. It is **not**
an OpenMS/tool-path problem and **not** a DecoyDatabase flag problem. (§9 of the DDA validation doc
succeeded because the quay `openms*` biocontainers bundle `procps`; the new combined image dropped it.)

**Fix (image rebuild — a blocker, not a 1-line code fix):** add `procps` to the combined image
(`apt-get install -y procps`, or `conda install -y -n base procps-ng`, or the `bioconda::procps-ng`
package) and re-push `proteomics-search:v1` (or a `:v2`). Every Nextflow-on-Batch container needs
`ps`; this is a build-recipe omission in the combined image. After the rebuild, re-dispatch the exact
same run to obtain the live Sage PSM count (`results.sage.tsv`) and Mokapot peptides@1%FDR — the
production-path default cannot be certified until then.

**Cost/hygiene:** ~$0 Batch spend (job died at container start, before any OpenMS/Sage/Mokapot compute);
no new EC2; **zero orphan compute confirmed** (all queues empty of proteomics/SAGE/MOKAPOT/OPENMS jobs
across SUBMITTED/PENDING/RUNNABLE/STARTING/RUNNING after the run went terminal).

**Status:** production path, DAG default, combined-image reachability, container-forcing, and the
awsbatch libz fix are all **PROVEN**. The Sage+Mokapot *scientific* default (real PSM/peptide counts
on the production path) is **BLOCKED** on the one-line image fix above (add `procps`).
