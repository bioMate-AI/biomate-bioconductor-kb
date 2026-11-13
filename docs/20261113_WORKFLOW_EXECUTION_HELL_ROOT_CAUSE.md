# 2026-11-13 — Workflow analysis + execution hell (systemic root cause)

User report: “the entire workflow analysis and execution is in hell” with 9
screenshots (Generate→ADMET misroute, Cryo Running with Movies Path unset,
DE “mapped but samplesheet not provided”, ECR `cs_image` leak, no license
prompt, empty Default fields, step modal with no params).

## Upstream classes (not 9 instance bugs)

| Class | Symptoms | Single funnel |
|---|---|---|
| **A. Primary-data truth** | 3–7 (Cryo), DE gate holes | Schema/`null_param_is_required` treated demo elvis (`?: test_data`) and `required: []` stubs as optional → UI + execute allowed Running with Movies Path / samplesheet empty |
| **B. Display-bound ≠ launch-bound** | 9 (DE), 1 (attachments on wrong card) | Inputs card showed `required_params[].value` / filename; launch map omitted alias (`samplesheet`↔`input`) or row values |
| **C. Generate stolen by screening** | 1–2 | `msg.includes("drug")` matched **drug-like**; classifier `chain_hint` + Tier-2 kept `drug_discovery_admet_gated_screening` |
| **D. License scan miss** | 3 | `\bcryosparc\b` does not match `cryosparc_standard_spa` (`_` is a word char); content scan missed `container params.cs_image` |

Secondary / deferred: attachment fold >3 (intentional UX); step modal empty params (global params, not per-step); empty “Default” optional nulls (`gain_ref`) — cosmetic; generate→reinvent **card** still depends on search/LLM after chain drop.

## Fixes shipped (this branch)

1. **Clinic hard-required primary data** — `movies_path` / `samplesheet` / `matrix` / reads… forced required in schema + `.nf` parse; demo elvis still required (`nf_param_requirement.py`); shared `CLINIC_HARD_REQUIRED_DATA_NAMES` + `unboundClinicHardDataFromParams` used by panel Confirm & Run **and** `/api/workflows/execute`.
2. **Launch alias** — `buildNextflowLaunchParameters` mirrors `samplesheet`↔`input`; execute merges structured row values into the payload.
3. **Generate routing** — whole-word hint tokens; `isMoleculeGenerateRequest` returns null from library dual-path (no ADMET-gated steal); Tier-2 drops generate intents; domain prompt no longer maps “drug-like” alone → ADMET when generate/design.
4. **Hide infra** — `cs_image` (+ other `*_container` / `container_image`) in `_NEXTFLOW_INTERNAL_PARAMS`.
5. **Cryo license** — path scan treats `_`/`-` as separators; also detects image URI on `params.*image`.

## Tests

- `backend/tests/test_nf_param_requirement.py` — demo elvis + real cryo `movies_path`
- `backend/tests/test_license_scan_cryosparc_path.py` — path underscore match
- `frontend/shared/workflow-data-inputs.test.ts` — clinic hard unbound
- `frontend/server/nextflow-launch-params.test.ts` — samplesheet↔input
- `frontend/server/library-triage-sequential.test.ts` — Generate-500 / drug-like

## Still open

- Generative design may still need search/LLM to land on `reinvent4_lead_design` (we only stop the wrong mega-chain).
- Mega-chain attachment bind still single-wf (`bindAttachmentsToParams`); fold >3 unchanged.
- Optional null “Default” empty fields (`gain_ref`, `dose_per_frame`) — honest empty, not wrong required.
- Full DEV verify + sync deferred until PRE_SYNC green.

## Suggested DEV verify

1. CryoSPARC SPA idle: Movies Path required; Confirm & Run blocked; Tool Credentials shows CryoSPARC when no user key.
2. DE with 3 CSVs: Inputs mapped → launch payload has `samplesheet` **and** `input`; no “samplesheet was not provided”.
3. “Generate 500 candidates… drug-like” + attachments → **not** ADMET-Gated Virtual Screening chain.
4. Cryo panel: no `Cs Image` / ECR URI in settings.
