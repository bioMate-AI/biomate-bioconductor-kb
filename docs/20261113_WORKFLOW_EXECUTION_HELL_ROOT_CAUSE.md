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

- Generative design may still need search/LLM to land on `reinvent4_lead_design` (we only stop the wrong mega-chain). Chat now clarifies / mentions REINVENT4 rather than ADMET-gated screening; Galaxy `generate_workflow` can still surface `candidate_chain: target_to_lead_full` under a `clarification` response.
- Mega-chain attachment bind still single-wf (`bindAttachmentsToParams`); fold >3 unchanged.
- Optional null “Default” empty fields (`gain_ref`, `dose_per_frame`) — honest empty, not wrong required.
- Cryo license / Tool Credentials prompt: not observed for fixture on DEV (best-effort; may already have a key or prompt is gated elsewhere).

## DEV live verify (2026-11-13, sync `1257a9f36d`, https://dev-public.biomate.ai)

Fixture: `lifeifei163361@163.com`. Harness: `frontend/e2e/hell-clinic-dev-verify.e2e.ts` + API/SSE probes. Shots: `frontend/e2e/execshots/hell-clinic-20261113/`.

| Check | Result | Evidence |
|---|---|---|
| **1. Cryo Movies Path required / run blocked** | **PASS** | Chat: “⚠️ 1 required parameter…”, “Which movies_path?”, “movies_path is required”. Execute empty → `400 missing_required_params` listing `movies_path` only. Shot: `01c-cryo-movies-required.png`. License UI: not seen (best-effort). |
| **2. Generate 500 ≠ ADMET-Gated mega-chain** | **PASS** | `/api/chat/stream`: `workflow_type=clarification`; asks for PDB/sequence; mentions REINVENT4 de novo — **no** “ADMET-Gated Virtual Screening”, **no** pharmacophore→ADMET→dock curated chain in the user-facing text. SSE note: `candidate_chain=target_to_lead_full` still present under clarification (residual). Text: `02-generate500-chat.txt`. |
| **3. DE samplesheet↔input alias** | **PASS** | `buildNextflowLaunchParameters` mirrors `samplesheet`→`input`. Live execute with samplesheet+matrix+contrasts accepted (queued; cancelled). Execute with samplesheet set / matrix empty → `400` missing **`matrix` only** (not “samplesheet was not provided”). |
| **4. cs_image hidden from clinic** | **PASS** | `generate_workflow` for cryosparc_standard_spa: `required=['movies_path']`; param list has **no** `cs_image` (only `cs_helper`). UI body/panel text had no “Cs Image” / ECR URI. |

Residual / notes:
- Accidental DE sandbox launch `b6cb8481-…` from the alias probe was **cancelled** after queue acceptance.
- Direct Galaxy `generate_workflow` for “Generate 500…” can still chain_lookup / clarify toward `target_to_lead_full`; clinic chat path is the authoritative non-ADMET-gated route.

## Canonical Playwright E2E (2026-11-13, `workflow-clinic-hell.e2e.ts`)

Harness: `frontend/e2e/workflow-clinic-hell.e2e.ts` — one login (`lifeifei163361@163.com`), one disposable project, two serial flows, no API mocks. Shots + `results.json`: `frontend/e2e/execshots/workflow-clinic-hell/`.

Run (DEV):
```bash
cd frontend && BIOMATE_URL=https://dev-public.biomate.ai \
  E2E_FIXTURE_PASSWORD=$(cat ~/.config/biomate/e2e_fixture_password) \
  npx playwright test e2e/workflow-clinic-hell.e2e.ts --project=chromium --retries=0 --workers=1
```

Verified against sync `1257a9f36d` at ~2026-11-13T17:37Z — **2/2 tests passed (~4.9m)**:

| Case | Result | Evidence |
|---|---|---|
| **1. Cryo SPA Movies Path / run blocked** | **PASS** | UI: Movies Path required + missing-param alert. Execute empty → `400 missing_required_params` `[movies_path]`. Shot: `01-cryo-full.png`, text: `01-cryo-panel.txt`. |
| **2. Generate 500 ≠ ADMET-Gated mega-chain** | **PASS** | Settled UI asks for PDB/sequence; mentions REINVENT4 generative design — **no** “ADMET-Gated Virtual Screening”, **no** pharmacophore→ADMET→dock curated chain. Stream final: `REINVENT4 Generative Lead Design` (500 candidates). Shots: `02-generate500-full.png`, `02-generate500.txt`, `02-generate500-stream.txt`. |
| **3. DE samplesheet↔input** | **PASS** | Uploaded 3 project CSVs; `buildNextflowLaunchParameters` mirrors `samplesheet`→`input`. Live execute with all three → accepted (queued; **cancelled** `2b7d0fc9-…`). samplesheet set / matrix empty → `400` missing **matrix** only (not “samplesheet was not provided”). Shot: `03-de-panel.png`, `03-de-execute.json`. |
| **4. cs_image hidden** | **PASS** | `generate_workflow` param list has **no** `cs_image` (only `cs_helper`); UI/panel had no “Cs Image” / ECR URI. |

Notes from this run:
- First Generate-500 attempt false-passed on sidebar/user-query text before assistant settled; harness now waits for stop-button gone + non-placeholder assistant text (≥12s stable) and asserts on assistant bubble only, with `/api/chat/stream` `{ message, stream, context }` as supporting probe.
- Accidental DE sandbox launches from the alias probe are cancelled post-assert (`cancelIfQueued` + manual cancel when needed).

## Deep DEV E2E (2026-11-13, live `562908a3e7`)

Harness rewritten as **Flow A (long journey)** + **Flow B (gates + DE→terminal)** with both-panel assertions, attachment names, ADMET SMILES route, license gate, cheap cart→terminal, DE→terminal, findings honesty. Evidence: `frontend/e2e/execshots/workflow-clinic-hell/` (`a1-*`…`a4-*`, `b2-*`, `results.json`, `audit.json`).

### Pass / fail matrix

| Case | Result | Evidence |
|---|---|---|
| **Cryo deep (Movies Path + Confirm blocked + not optional-only)** | **PASS** | Chat: “CryoSPARC Standard SPA”, `movies_path is required`. Execute empty → `400 missing_required_params` `[movies_path]`. Shots: `a1-cryo-prerun.png`, `a1-cryo-panel.txt`. |
| **cs_image hidden** | **PASS** | `generate_workflow` has no `cs_image` (only `cs_helper`); UI no ECR / Cs Image. |
| **Cryo panel open on Confirm and configure** | **FAIL → fix landed locally** | Chat claimed “ready in the panel” but `workflow-right-panel` stayed closed after Clarify “Confirm and configure”. **Root cause (class D):** (1) `setPanelWorkflow` bridge did `if (!prev) return prev` when panel never opened; (2) zero-opt file prompts left pick=`NONE` so Confirm emitted **no** event. **Fix:** `clarify-card.tsx` emits empty fretext for zero-opt NONE; `chat-with-artifacts.tsx` opens panel from message `metadata.workflow` when `prev` is null. Unit: `clarify-card.test.tsx` (12/12). **Pending DEV sync** (`BIOMATE_SYNC_DB=0`). |
| **Cryo license (no GPU)** | **PASS** | Fixture has **no** Cryo license: Tool Credentials UI visible + execute with dummy `movies_path` → `402 cryosparc_license_required`; no run queued. Shots: `a1-cryo-license.png`, `a1-cryo-license-api.json`. |
| **Generate 500 + 4 attachments** | **PASS** | Composer chips show all 4 names; reply REINVENT4 Generative Lead Design (not ADMET-Gated); files considered; panel name `REINVENT4 Generative Lead Design`. Shots: `a2-attach-composer.png`, `a2-generate-reply.png`, `a2-generate-attach.txt`. |
| **ADMET SMILES (separate from Generate)** | **PASS** | Routes to **Predict ADMET Properties (AI)**; name defined; Confirm enabled; not mega-chain. Shot: `a3-admet-prerun.png`. |
| **Cheap Confirm&Run → terminal (cart)** | **PASS** | `cart_construct_design` run `61588932-…` → **`completed`** (~181s, 4 output files). Poller hardened after a 60s status GET timeout aborted the first poll loop. Evidence: `a4-cart-execute.json`, `a4-cart-terminal.json`, `a4-cart-*.png`. |
| **DE samplesheet↔input alias** | **PASS** | Mirror + empty-matrix → 400 matrix only. |
| **DE execute → terminal** | **PASS** | UI Confirm&Run `9bd5d644-…` → **`failed`** (Nextflow; tiny 2×2 CSVs — expected infra/data fail) with **honest** error — **not** “samplesheet was not provided”. Shots: `b2-de-prerun.png`, `b2-de-running.png`, `b2-de-terminal.png`, `b2-de-terminal.json`. |
| **Failure findings honesty** | **PASS** | Failed DE: Findings not “Analysis in progress…” / no spinner (`de_failure_findings_honesty`). Shot: `b2-de-findings.png`. |

### Product bugs found (root cause)

1. **Clarify → panel silent no-op** (Cryo “Confirm and configure”): panel never opened when `panelWorkflow` was null and/or zero-opt NONE emitted nothing. Local fix in `clarify-card.tsx` + `chat-with-artifacts.tsx`; unit test added; **needs sync to DEV** then re-verify `cryo_panel_open_bug`.
2. **DE tiny CSV → Nextflow failed**: terminal reached honestly; failure is data/pipeline (2 samples / 2 genes), not the samplesheet↔input alias class. No test softening.

### Harness notes

- Soft expects inside Flow A so later legs still run; Flow B is a separate describe so it is not skipped when Flow A fails.
- `results.json` merge-on-write so separate workers do not clobber each other.
- `pollWorkflowTerminal` catches per-request timeouts and continues until budget.
