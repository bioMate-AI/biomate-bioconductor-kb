# Models ownership and registration review — 2026-11-07

## Confirmed source defects

The legacy `/api/models`, `/api/model-tracks/*` and `/api/inference/*` Node passthroughs used optional authentication. Their Python endpoints did not independently require an authenticated owner. The legacy model catalogue scanned all campaign databases; Adapt read customer chosen/rejected text without owner filtering; an unmatched project in Optimise fell back to all campaigns; feedback toggles could change another record. This was verified by source and synthetic fixtures, without reading real users' model/edit records.

The registration review also found that generated TrainingConfig workflow rows omitted selected model_name/metric/gate fields (and LLM task type), despite the new registration manifest requiring an exact launch snapshot. Root delegated that builder repair separately. The new central registry's default persistent path was separately reconciled by root.

## Repairs

- Models/tracks/inference Node routes require login. A dedicated privileged bridge supplies its own configured Galaxy credential and authenticated BioMate owner header, replacing caller headers. Project queries are checked against authorized projects before proxying.
- Python Models endpoints require the Galaxy administrator dependency before trusting that bridge header. Ordinary user Galaxy keys cannot forge owner context by supplying a header. Missing trusted owner is denied.
- Legacy custom models use durable campaign registry `campaigns.user_id` bindings. Blank, foreign and unbound campaigns are never globally enumerated or inferred. Predefined BioNeMo catalogue entries remain available to authenticated platform users.
- An unmatched project never falls back to every campaign. Ownership database errors are 503, not successful empty results.
- Adapt reads/toggles require exact recorded owner; project matching uses the recorder's existing normalized organization key. The worker receives a temporary exact-owner/project JSONL subset, excludes unbound/foreign/disabled rows, and leaves the shared source untouched. Owner-scoped submission counts use the same input. Empty active input fails before overwriting an adaptation artifact; other owners' rows do not permanently block a valid job.
- Retrain errors return before creating a first-class execution. A successful response must contain a real job ID and recognized backend status; no fake queued record is generated from a denied/empty response.
- Inference results retain and enforce their owner. Historical unowned inference results are denied. Unavailable/stub inference is failed, not completed science.
- Legacy catalogue version labels use the registry's recorded active version. Missing version evidence says `Not recorded`; version 1 is not invented.

The new owner/project-scoped central training registration remains separate and does not gain an inference or promotion permission through this repair.

## Verification

- Node owner bridge/registration tests: **15 passed**, `/tmp/model-privacy-node.log`.
- Python Models shape/owner fixtures plus worker isolation: **30 passed**, `/tmp/model-privacy-python.log`.
- Python tests use an isolated `/tmp/biomate-model-review-venv`, with test-only FastAPI/pytest/httpx/PyYAML dependencies and available system scientific packages. `--noconftest` is used because this existing shape suite deliberately stubs the Router rather than booting the full Galaxy webapp; the local full-webapp conftest lacks boltons. This is not a substitute for the exact deployed Python 3.9 import/route smoke check owned by root.
- Fixtures cover anonymous/missing owner, foreign projects, forged forwarded headers, global fallback, custom models with two owners plus unbound history, customer edit isolation, blocked foreign toggle, inference result ownership, truthful failed inference, real active version 7, and worker source isolation.

No production data was inspected or rewritten. No GPU/Batch training was started. No commit or deployment was performed by this worker. Root owns full regression/build, exact runtime overlay, synchronization and deployed acceptance.
