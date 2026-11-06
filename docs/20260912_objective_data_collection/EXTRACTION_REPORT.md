# Objective label extraction — status after taking over from codex

Continues the collection in `PLAN.md`. Codex downloaded and hash-audited the raw
sources, then stopped (its own usage rate limit) before the label-extraction
phase. This pass turns the downloaded raw data into structured, frozen labels.
Nothing here is promoted to training-eligible.

## What ran

| Script | Output | Verified |
|---|---|---|
| `extract_geo_labels.py` | `geo_sample_labels.json` (269 samples), `geo_label_summary.json` | Every GSE113156 sample resolved to subject + timepoint; GSE35455 112/112 paired |
| `extract_trial_labels.py` | `trial_labels_{disease}.json`, `trial_label_register.json` | Spot-checked NCT04835441 arm denominators, AE counts, withdrawals vs source JSON |
| `make_eval_register.py` | `EVAL_REGISTER.json` (frozen splits) | Deterministic, no RNG; patient/trial units reserved for blind test |

## ⚠ QC correction (supersedes the raw-count framing, incl. codex's PLAN)

Building the actual matrices exposed two errors in the earlier optimistic framing:

- **GSE35455 is NOT a 112-patient paired pre/post durability cohort.** It is a
  two-color **dye-swap** array: `#VALUE = log2(after/before) Tocilizumab`, 112 RA
  patients × 2 arrays that are **dye-swap technical replicates** of one after/before
  contrast (all peripheral blood; no synovium). Worse, those replicates **do not
  reproduce**: median replicate r = **−0.02** across 112 patients (IQR −0.11–0.05),
  only **4%** of patients reach r>0.3 (with ~25k common probes/pair, so not an
  overlap artifact). ⇒ **No reliable per-patient labels.** Demoted to cohort-average
  evidence-only in `EVAL_REGISTER.json`; the 34-patient held-out split is retracted.
- **GSE113156 has no local expression.** Its SOFT carries 0 sample tables; the
  matrix is a separate series-matrix/supplementary file. Labels are ready (6 subjects,
  CD8+CD4, w0/w24) but it's blocked on that download before it can be joined.

Net: after real QC the local GEO side is much thinner than the download counts
implied. This makes the patient-level ImmPort/R4RA sources more important, not less.

## Labels now structured (per objective)

- **Target durability / on-treatment change** — *(downgraded, see QC above)*
  GSE35455 gives only a noisy cohort-average after/before Tocilizumab contrast, not
  per-patient labels. GSE113156 (6 subjects, w0/w24 paired) is the only genuine
  local longitudinal design but its expression matrix still needs downloading. No
  cohort here supports per-patient durability evaluation yet.
- **Treatment response** — GSE15316: 23 whole-blood samples labeled Rituximab
  responder / non-responder (cross-sectional, no pairing). Small; external-test only.
- **Safety (aggregate)** — 337 trials carry arm-level AE counts *with denominators*
  (`ae_group_denoms`, `seriousNumAtRisk`/`otherNumAtRisk`). Usable as randomized
  arm-level safety evidence.
- **Sustained response / withdrawal (aggregate)** — 337 trials carry
  participant-flow withdrawal totals + reasons (e.g. "Physician Decision",
  "Lost to Follow-up"). This is trial-level flow, **NOT** patient time-to-event.

## Frozen evaluation reservations (`EVAL_REGISTER.json`)

- GSE35455 → **demoted to cohort-average evidence-only** (fails per-patient QC); no
  held-out split.
- GSE113156 → whole study reserved, **pending expression-matrix download**.
- GSE15316 → whole study reserved as external test (small, response-labeled).
- Trials → ~20% of usable NCTs per disease frozen as trial-held-out external test
  (39 RA / 21 asthma / 9 lupus). This aggregate-safety/withdrawal evidence is the
  **most solid** labeled asset from this pass.

## Still missing or blocked

- **Patient-level therapy duration** — the one objective codex flagged. Requires
  ImmPort participant tables (SDY1490 iWITH) or the R4RA portal. **ImmPort needs an
  authenticated account — I have no credentials, so I did not and cannot download
  it.** Aggregate trial withdrawal counts do **not** substitute for per-patient
  time-to-event. This is a hard blocker (see decision below).
- **Modality-specific druggability** — not started this pass. BindingDB is already
  in S3 (per PLAN); ChEMBL assay parse still to do.
- **Combination benefit** — DrugComb not yet retrieved.

## Admission gate (unchanged — all still training-ineligible)

Before any of these labels are used for optimization: join the matched expression
matrix / arm-result tables, dedup against existing pretraining+KG+text, and get
human sign-off. `EVAL_REGISTER.json` only freezes the blind-test units so later
steps can't leak them.
