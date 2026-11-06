# Generalization-stack committee triage (multi-omics / ml_training / executor / QC)

2026-11-05. Companion to `20261105_GENERALIZATION_WORK_AND_TEST_MANUAL.md`,
`20261105_CROSS_OMICS_BIOMARKER_FUSION_METHOD.md`, and
`20261105_SYSUCC_SIM_MULTIOMICS_VALIDATION.md`.

A multi-model LLM committee (Opus / Sonnet / Fable reviewers, read-only) reviewed the generalized
multi-omics + model-training + executor work in three passes. Per the standing instruction —
*"be careful regarding the expert suggestions, they may be correct or wrong"* — every finding was
verified against the code before acting; some were applied, some rejected with reasons, some
documented as known trade-offs. This records the full triage so a human (or the next committee
round) can audit each decision.

Scope of files reviewed:
- `backend/lib/galaxy/ai/multiomics/biomarker_fusion.py` (+ test)
- `backend/lib/galaxy/ai/ml_training/datasets.py` (+ tests)
- `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` (driver-fusion hook + `*_list` serialization)
- `backend/lib/galaxy/jobs/qc_trace_monitor.py` (declared-gate fallback, S3/Batch passthrough)
- `backend/biomni_workflows/nextflow_nfcore/subworkflows/bioconductor/snf_multiomics/main.nf`

---

## Pass 1 — the unit-test that never ran (my error, caught by the committee)
**Finding (CONFIRMED, my fault):** `biomarker_fusion_test.py` could not even import (`drivers_from_run`
missing from the import line) and its fixtures were degenerate zero-variance matrices — so my earlier
claim "unit-tested" was false; the tests had never executed.
**Fix:** added the missing import; rebuilt fixtures with real within-group noise (`random.gauss`),
60 samples, unique-per-layer noise features, `n_perm=100`. **12/12 now pass.** The method doc's
"unit-tested" claim is now accurate.

**Rejected-with-reason (the reviewer was wrong):** a reviewer proposed tying the F-statistic
within-group variance floor to `ss_between` (or feature variance). I rejected it: for a
perfectly-separable feature `ss_within=0 ⇒ ss_total=ss_between`, so any `floor ∝ scale^2` makes
`F` a constant independent of effect size — it **collapses the ordering of all perfectly-separable
features to one value**, strictly worse than the current magnitude-scaled floor. Documented in the
function docstring instead of changing the code.

---

## Pass 2/3 — Reviewer B (integration) + Reviewer A (correctness + triage audit)

### CONFIRMED and FIXED

| ID | Severity | Finding | Fix (commit) |
|---|---|---|---|
| H1 | HIGH | `_report_json_to_metrics` passed through only scalars, so a workflow's declared **`gates` list was stripped before `_check_qc_thresholds`** on the S3/Batch path — declared gates were read-as-file but **never evaluated** on Batch (corrects my earlier "evaluated live on Batch" over-claim). | Preserve `gates`/`declared_gates` lists through the passthrough (`bd3aafbd3`). **Verified live on dev** — see §Verification. |
| A1 / L1 | MEDIUM (reproduced crash) | `load_tabular_dataset` + `_load_csv` row-skip checked only `None`/`""`, not the broad `_MISSING_TOKENS`. A textual `"NA"`/`"."` label reached `float()` → an auto-inferred **regression crashes** on `float("NA")`; classification minted a spurious `"NA"` class. | Row-skip uses `_is_missing`; `_val` maps non-finite (`inf`/`nan` text) to missing so it can't poison a column mean or reach sklearn. +2 tests, 18/18 (`3cb929682`). |
| M1 | MEDIUM | `biomarker_fusion._default_fetch` used bare `boto3.client("s3")` (AWS us-east-1 only → 301/NoSuchBucket on on-prem MinIO) and **swallowed the real boto3 error** into the staging fallback's generic "AWS CLI not available". | Use `galaxy.ai.s3_utils.make_s3_client` (honours `S3_ENDPOINT_URL` + region); on total failure raise naming **both** real causes (`863a8d356`). |
| H2 | (defensive) | Reviewer B: driver hook silently skips if `omics` is a JSON-string. Reviewer A **ruled it out** for real runs (the run record keeps the ORIGINAL request params, so `omics` stays a Python list — confirmed by `test_integration_planner`). | Added a defensive JSON-string parse anyway to close the edge; no known live case (`eea051da2`). |

### CONFIRMED verdicts on my earlier triage (Reviewer A audit)
- **B1 (F-floor rejection): my rejection STANDS.** Reviewer A confirmed the collapse math and the
  general result that scale-invariance ⟺ ordering-collapse are mutually exclusive. It added a
  genuine sub-point: the `(|grand|+1)²` factor sacrifices *offset*-invariance (two equal-separation
  features of different mean score differently). I did **not** swap to a constant floor — that trades
  offset-invariance for scale-awareness (tiny-magnitude features rank low), and the point is
  **practically moot**: the downstream EvidenceGate robust-z **clips to `Z_CAP`**, so all
  perfectly-separable features saturate and tie regardless of the floor. Documented in the docstring
  (`863a8d356`); the principled fix remains per-layer standardization upstream.
- **B2 (drop all-missing columns): CORRECT, confirmed.** Dropping an all-missing column is right (it
  would otherwise `KeyError` at X-build or become a junk constant-0 feature); partially-missing
  columns are still kept + mean-imputed.

### Reviewer-A fresh findings held as known-minor (LOW / edge / cosmetic — not fixed)
- **A2 (LOW):** a generic `*_list` param carrying a bare comma string would wrap to a single-element
  array. `smiles_list` is **safe** (`_normalize_smiles_list_param` splits first); no other value-list
  param carries commas today. The two serialization branches are byte-for-byte consistent.
- **A3 (LOW):** SNF `.nf` re-publishes the staged input CSVs alongside its outputs
  (`path("*.csv")` glob). Its one real risk — the analyze-outputs driver hook's loose
  `clusters?.csv` match could pick a re-published input named e.g. `clusters.csv` — is **FIXED on
  the consumer side** (`cce960c6d`), testably and with no Batch run: the picker is now a pure
  `biomarker_fusion.select_cluster_output` that prefers the exact `snf_clusters.csv` /
  `patient_stratification.csv` names and excludes any file whose basename matches an input omics
  layer (+4 unit tests). The cosmetic `outdir` pollution (the `.nf` glob itself) is left as-is —
  tightening it would need a Batch re-run for a purely-cosmetic gain.
- **A4 (edge):** a layer with many *exactly*-separable features would have its robust-z null dominated
  by their ~1e9 F values. Such a layer usually signals a label leak; the docstring already notes
  continuous omics with real noise never hit this path.
- **A5 (INFO):** dead `n_total` local; `standardNormalization` on a constant feature yields NaN
  (rare after common-sample alignment). Trivial.

### Reviewer-A ruled-OUT concerns (checked, not bugs)
Permutation test is a correct Westfall-Young maxT (`p=(ge+1)/(n_perm+1)`, identity permutation
included, deterministic); the F-stat one-way ANOVA (NaN-aware, df guards) is correct;
`_looks_like_single_file_ref` correctly prevents wrapping `gene_list=s3://…/x.txt`;
`stage_s3_to_local`'s URI-hash prefix prevents the cross-URI basename collision; the driver hook's
`isinstance(list)` guard fires for real runs.

---

## Verification (live on dev, deployed `84577b8e1`)

**H1 — in-container test of the deployed `qc_trace_monitor`** (`scratchpad/verify_h1.sh`):
- H1a: `_report_json_to_metrics("BIOC_SNF_MULTIOMICS", {…,"gates":[…]})` → returned metrics **include
  `gates`** (not stripped).
- H1b: `_check_qc_thresholds(…)` on a balanced 3-cluster result → `passed=True` (not `None`) ⇒ the
  declared gates were **actually evaluated** on the S3 path.
- H1c (negative control): `n_clusters_found=1` → `passed=False`, 1 blocking failure ⇒ the halt gate
  genuinely fires on a degenerate clustering.

**A1/L1 + M1:** 18/18 `test_datasets.py`, 12/12 `biomarker_fusion_test.py` (local, python3.14);
`py_compile` clean under python3.9; in-container module-load check of all three modules (pending
`863a8d356` landing on dev — `scratchpad/verify_deploy.sh`).

---

## Pass 4 — adversarial re-review of the pass-2/3 FIXES (did the fixes introduce regressions?)
Two reviewers (Opus correctness + Sonnet integration) attacked ONLY the four new fix commits
(`3cb929682`, `863a8d356`, `eea051da2`). Both ran the suites locally: **30/30** pass.

**CONFIRMED regression (BOTH reviewers independently; Opus reproduced) → FIXED (`cb70c6772`):**
my A1 fix applied the broad `_is_missing` token set to the **label** column unconditionally, so a
**classification** class literally named `none`/`-`/`.`/`NA` (e.g. a treatment arm `none`, mutation
status `none`) was **silently dropped** — Opus reproduced `arm=[drugA,none,drugA,none]` collapsing to a
single class. Root-cause fix (task-aware, strictly better than the reviewers' token-narrowing
suggestion — it keeps *any* non-blank label as a valid class):
- label row-skip uses a new `_is_blank` (None/empty/whitespace only), never a semantic token;
- the **regression** path explicitly drops missing/non-numeric-label rows (where `float("NA")` would
  crash), keeping X/y aligned and logging the count;
- classification keeps every non-blank label as a class; `_load_csv` (molecule, regression-only) skips
  non-numeric/non-finite labels. +2 tests (categorical `none` kept; blank still skipped), 20/20.

**CONFIRMED clean by both reviewers** (ruled-out, with evidence): M1 (`make_s3_client` import-safe,
signature-compatible, won't throw at construction, new `RuntimeError` still caught by the per-layer
handler → findings path not sunk); H2 (purely additive, fires only for a `[`-prefixed str, double-
wrapped in try/except, `_json.loads` once per request — not a hot path/DoS); `_val` non-finite guard
(rejects only inf/overflow, no legit finite value lost, no existing test's numbers change); X/y stay
aligned; `csv.DictReader` yields only str/None so `_is_missing`'s `isinstance` guard is safe; the
driver hook's `isinstance(list)` path is unchanged for real runs. One LOW note left as-is: the per-layer
M1 `RuntimeError` text is surfaced in the **logs** (where a developer debugging a missing-drivers
finding looks), not to end users — intentional for a best-effort supplementary finding.

## Net
Four committee passes: pass 1 caught a unit-test that never ran (my false "unit-tested" claim) + I
rejected a floor suggestion with math; passes 2/3 caught one HIGH plumbing bug (H1, correcting a false
"evaluated live" claim of mine, now live-verified), one reproduced MEDIUM crash (A1), one MEDIUM
on-prem/error-masking bug (M1); pass 4 caught a MEDIUM silent-data-loss **regression that my A1 fix
introduced** (classification labels named `none`/`-`/`.`), now fixed with a task-aware root-cause fix.
Reviewer suggestions were taken when right (A1 regression, M1, H1), rejected with math when wrong (the
F-floor variants), and a reviewer disagreement (H2) was resolved by reading the code. The LOW/cosmetic
remainder is documented as known-minor rather than churned. "No one does it perfect once" — borne out
at every pass, including on my own fixes; the corrections are the point.
