# Work & Test Manual — generalization + execution-verification + use-case program (2026-11-04/05)

Purpose: a single, detailed account of everything changed in this workstream, how each piece is
tested, and **what a reviewer should scrutinize** — written so a multi-model review committee can
check it rigorously. Branch `cursor/tutorial-live-recording-and-report-editing-4ea7` → PR #295.
Dev deploys via `scripts/sync_to_dev.sh`; all live runs went through `POST /api/nextflow/execute` on
AWS CPU Batch (a few cents each).

> **Reviewer stance:** treat every claim below as a hypothesis to falsify. Flag correctness bugs,
> statistical errors, unjustified claims, missing edge cases, security/ops risks, and weak tests.
> Cite `file:line` or commit. Rank by severity. It is expected that some findings will be wrong —
> the coordinator will re-verify each against the code/data before acting.

---

## 1. What was built/changed (code artifacts — the review surface)

| # | Change | Key files | Commit | What to scrutinize |
|---|--------|-----------|--------|--------------------|
| A | **QC-gate engine** (declare gates as data; generic pass/advisory/halt) | `backend/lib/galaxy/ai/qc_gate_engine.py` (+`_test`) | (2026-11-04) | operator table, severity parsing, missing-metric → not_evaluated, float coercion, 中文 severity |
| B | **QC declared-gate fallback** in the live QC monitor | `backend/lib/galaxy/jobs/qc_trace_monitor.py` `_check_qc_thresholds` | `a26e61fcd`, fix `3a8adcbe5` | the `_declared_evaluated` guard; does a passing declared-only gate return `(True,[])` not `(None,[])`?; does it ever alter a hardcoded branch? dedup `(metric,threshold)` |
| C | **Model-training: generic tabular** learner + stratified k-fold | `ml_training/{splits.py,datasets.py,tabular_trainer.py,config.py,routing.py}` | (2026-11-04) | stratified k-fold correctness; task inference; no molecular hijack in routing |
| D | **ml_training s3 staging** (loader downloads s3://) | `ml_training/datasets.py` `stage_s3_to_local` | `958ef8134` | AWS-CLI subprocess, idempotency, error paths |
| E | **Tabular loader id-column hygiene** (drop non-numeric cols) | `ml_training/datasets.py` `load_tabular_dataset` | `904bb6b83` | does it drop a real numeric feature? respects `id_cols`; errors when no numeric feature |
| F | **Cross-omics biomarker fusion** (2nd consumer of `fuse_channels`) | `multiomics/biomarker_fusion.py` (+`_test`), `evidence_fusion.py` | `c6c30e20a` | one-way ANOVA F formula; NaN/inf guards; perfect-separation cap 1e6; cross-layer corroboration logic |
| G | **Findings hook** for drivers | `multiomics/biomarker_fusion.py` `drivers_from_run`; endpoint block in `nextflow_executor.py` `analyze_outputs` | `1e8c0eb3f` | CSV/matrix parsers; `_run_lookup` omics recovery; boto3/AWS-CLI fetch; best-effort guard |
| H | **Permutation significance** (max-statistic FWER) for drivers | `multiomics/biomarker_fusion.py` `rank_cross_omics_drivers(n_perm=…)` | `e2c199e53` | is the max-stat null correct? `perm_p` `+1` smoothing; alpha quantile index; FWER claim |
| I | **`logger`→`log`** latent 500 in findings endpoint | `nextflow_executor.py` `analyze_outputs` (6 refs) | `d4b735273` | all 6 refs; any other `logger.` in the file |
| J | **Executor `*_list` file-ref fix** | `nextflow_executor.py` `_looks_like_single_file_ref`; both param-serialization branches | `145c6a75b` (+`_test`) | the URI/ext regex; does it wrongly pass-through a genuine value-list? both branches guarded |
| K | **SNF declared-gate emission** (real multi-omics QC) | `subworkflows/bioconductor/snf_multiomics/main.nf` | `a5927577d` | silhouette on affinity distance; gate thresholds; jsonlite; no new params; Groovy `$`-interpolation safety |
| L | **Dev activation script** (routing flags) | `scripts/enable_generalized_routing_on_dev.sh` | `b1a6cb0e9` | docker-commit snapshot vs reimage; env replay; code-canary check |

## 2. How each is tested (and the gaps)
- **Unit tests** (run on dev/CI; the laptop lacks pulsar/boltons/scipy so galaxy.jobs/galaxy.ai imports fail locally):
  `qc_gate_engine_test.py` (7), `qc_trace_monitor` declared-gate `test_qc_declared_gates.py` (7, validated live 7/7),
  `biomarker_fusion_test.py` (incl. significance), `evidence_fusion_test.py` (4), `test_datasets.py`
  (stage_s3 + id-column), `test_nextflow_executor_list_param_json.py` (file-ref guard).
- **Logic validated in isolation on the laptop** (bypassing the heavy import) for: the QC fallback
  mapping, the F-statistic, the file-ref regex, the parsers. These are *reimplementations* of the
  shipped logic — a reviewer should check they match the shipped code, not drift.
- **Live execution on CPU Batch** (the real proof): see §3.

## 3. Live validation evidence (run IDs, results, known answers)
- **Model-training** run `cd3201a0`: `sklearn_tabular` 5-fold stratified CV, acc 1.0 on separable
  synthetic data; `model.pkl` + metrics.json. Also `27ba372e` on the SYSUCC matrix (CV 0.950, and
  `n_features=2500` confirming the id-column drop).
- **Multi-omics SNF** run `9d889185` (toy) + `ab67ad23` (SYSUCC 150-patient cohort): **ARI 0.978,
  best-match accuracy 0.993** vs known 3 subtypes.
- **Cross-omics drivers**: on the SYSUCC cohort, **24/24 planted drivers recovered**, all permutation-
  significant (perm_p ≤ 0.02); **negative control (random labels) → 0 significant**; **weak-signal
  cohort `9849fe21` (ARI 0.007) → 0 significant** (no false discovery). The raw `corroborated` tier
  over-called in both nulls (42 / 56) — which is why H (significance) exists.
- **QC declared gates**: `_check_qc_thresholds` 7/7 live; the full emit→read→evaluate chain live via
  SNF run `c56bd86d` (monitor logged `[QC-S3] Reading … BIOC_SNF_MULTIOMICS`; silhouette advisory fired).
- **5 use cases** (`20261105_USE_CASE_VALIDATION_LOG.md`): multi-omics (UC-1), ADMET `a4fe422e`
  (terfenadine hERG 0.0124µM flagged), DESeq2 `b8cd8747` (77/100 DE, FDR 0.037), enrichGO `c01c7973`
  (top-8 GO cell-cycle), PKNCA `89766f00` (Cmax≈100, AUCinf≈500, t½≈3.47h). UC-4 passed only after fix J.

## 4. Honest limitations (do not let these pass as "proven")
- The SYSUCC cohort is **synthetic with planted structure** → near-perfect scores are close to an
  **upper bound**; a real cohort will be messier. The weak-signal + random-label controls bound the
  other end.
- The QC-gate **silhouette advisory is not a real-vs-null discriminator** (≈0 even at ARI 0.978). The
  driver-significance count is the trustworthy structure signal, not silhouette.
- `fuse_channels` significance uses a **max-statistic permutation** (FWER) — conservative; it controls
  family-wise error, not FDR. Reviewer: is FWER the right error model for a biomarker shortlist, or
  should it offer BH-FDR too?
- The id-column loader keeps a **numeric** id column unless named in `id_cols` (can't distinguish a
  numeric ID from a feature without the caller). Documented, not fixed.
- Permutation significance re-runs the full fusion `n_perm` times → **O(n_perm) cost**; default
  `n_perm=0` keeps the per-run findings hook fast. Reviewer: is 0 the right default for the hook?
- Fix J (`_looks_like_single_file_ref`): extension/URI heuristic. Could a legitimate `*_list` **value**
  (not a file) ever match the data-file-extension regex and be wrongly passed through unwrapped?
- SNF `.nf` QC emission (K): the silhouette threshold 0.10 is heuristic; on SNF-affinity distance it
  fires advisory even for good clusterings — intentional (advisory, non-blocking) but reviewer should
  judge whether that is noise.

## 5. Review rubric (dimensions for the committee)
1. **Correctness** — does each function do what it claims? trace the gating/branches; find inputs that break it.
2. **Statistical validity** — F-statistic, stratified k-fold, permutation null/FWER, DESeq2/PKNCA
   known-answer checks: are the methods and the pass/fail thresholds sound? any p-hacking / leakage?
3. **Robustness / edge cases** — empty inputs, NaN, single class, missing metric, s3 failure, huge lists.
4. **Test adequacy** — do the tests actually exercise the risk? are the isolation re-implementations
   faithful to the shipped code? what is untested?
5. **Honesty of claims** — does the live evidence support each "✅/validated"? any over-claim vs the
   §4 limitations? is a "known answer" actually known/independent?
6. **Security / ops** — the activation script (docker commit/recreate), subprocess `aws s3 cp`, boto3
   usage, best-effort `except Exception: pass` swallowing real errors, hot-path executor change (J).

## 6. How to run things (for a reviewer who wants to reproduce)
- Unit tests (on dev container): `docker exec biomate-galaxy-dev sh -c 'cd /app && PYTHONPATH=lib python3.9 -m pytest <path>'`
  (laptop can't import the galaxy packages).
- A live use case: `POST /api/nextflow/execute` with `{nextflow_path, parameters, workflow_domain, user_id}`
  (see each UC in the use-case log for the exact params + the bioc named-param gotchas: DESeq2 uses
  `cts`/`coldata` params, PKNCA needs `conc/dose/route` CSV columns, clusterProfiler `gene_list`).
- Scoring scripts (clustering ARI, driver recovery, DE recall/FDR, PK vs computed) are in the session
  scratchpad; the numbers in §3 are reproducible from the committed run outputs on S3.
