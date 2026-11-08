# QC attribution review — 2026-11-07

## Observed saved record

The owned completed fixture `cb7a1b63-28a0-41ea-9074-9a3f33fd64f2`
returned HTTP 200 from its QC-events endpoint with six rows. Every row had:

- gate `FASTP`, status `not_evaluated`;
- explanation `No supported QC rule evaluated these metrics.`;
- `execution_control: assessment_only` and a recorded source;
- no measured value or threshold.

These were not six FASTP assessments. Four documents contained single-cell
integration/configuration fields such as `integration_method`, `n_cells_before`
and `n_cells_after`; another contained MultiQC report configuration, and another
contained workflow parameters. Aggregate evidence, without credentials or source
file contents: `/tmp/biomate-hospital-audit/saved-fastp-qc-6bf.json`.

The completed execution status establishes that the workflow finished. It does
not establish that these QC checks passed or failed. `Not evaluated` correctly
avoids inventing an assessment from unsupported measurements.

## Source cause

`NextflowQCGateHandler._S3_REPORT_PATHS` registers FASTP reports with `*.json`.
That wildcard is meaningful when reading a known FASTP process directory.
The retrospective `_reconstruct_qc_from_s3` path reused it across all published
outputs and also used the filename match to infer the producing process.
Consequently unrelated JSON documents were attributed to FASTP. The FASTP checker
expects measurements such as read-survival percentage; those documents contained
none, so assessment returned `not_evaluated`.

The completed-run QC table displayed the gate, measured value, threshold and
status but omitted explanation and source identity. That presentation made six
distinct documents look like six identical failed or unfinished checks.

## Pending backend correction and verification

The reviewed correction is preserved separately under
`/tmp/biomate-hospital-audit/pending-qc-attribution`, including the exact three
files, patch and SHA manifest. The backend worktree was restored to HEAD for the
independent frontend deployment. This document does not claim the backend fix
has been deployed.

The correction scopes process inference to explicit report names or known
producing path components; a bare JSON wildcard cannot identify FASTP. Unrelated
configuration JSON without a declared process is excluded from QC reconstruction.
Dedicated QC documents with unknown producers remain visible as unevaluated, and
unreadable candidate reports remain unavailable. Recorded pass/fail assessment
logic is unchanged.

Local focused verification: **24 tests passed** in
`backend/tests/test_qc_assessment_semantics.py`, using Python 3.14 and isolated
`--noconftest` execution. The tests exercise the real reconstruction function with
mock S3 documents, exclude integration/MultiQC/parameter JSON, retain NCA failure,
OpenFE advisory and unknown dedicated QC, and preserve a genuine FASTP failure
with measured survival 10% against threshold 70%. Log:
`/tmp/qc-attribution-tests.log`. This is not Python 3.9 verification.

Before backend release, the corrected files still require approval and import /
focused verification in the actual Python 3.9 runtime. Deployment alone will not
replace already cached QC sidecars. The affected saved sidecar needs a separately
reviewed reconstruction or invalidation that preserves genuine measured and
failed QC records. No sidecar writes, workflow launches or historical-record
changes were performed in this review.
