# BioMate Tester Addendum — 2026-03-04
**Addendum to:** `docs/20260303_1914_TESTER_PLAN.md`
**Branch:** `connection_formal`

This document covers only what is **new since the previous tester plan**.
Run the base plan first, then come back here.

---

## 1. Backend Test Lane — Correct Command

The parallel test plan (`20260304_0915_PARALLEL_QC_INTEGRATION_TEST_PLAN.md`) noted
that Lane A (backend QC pytest) was blocked when running from a fresh venv.

**Use the project's own backend venv — it already has everything:**

```bash
cd /home/yzhang/biomate/backend
.venv/bin/python -m pytest \
    tests/test_qc_e2e_domains.py \
    tests/test_qc_edge_cases.py \
    tests/test_gap3_complete_integration.py \
    tests/test_gap3_standalone.py \
    -q --tb=short
```

**Expected:** `577 passed` (no failures).

If count differs, check git branch is `connection_formal` and the backend was restarted
after the latest code pull.

---

## 2. New QC Gates — Manual Verification Checklist

### 2a. CTF Defocus Out-of-Range (direction-aware failure)

Previously: a sample with defocus outside 1,000–100,000 Å was silently ignored.
Now: the gate fires with a directional message.

**To trigger (mock mode):** Run the cryo-EM SPA pipeline.
Inspect the logged QC event in the browser console or SSE stream.

**Expected gate message should include one of:**
- `"near-focus"` + *"Consider collecting at 1.0–3.0 μm underfocus"* (defocus < 1,000 Å)
- `"too far from focus"` + *"Check for stage drift"* (defocus > 100,000 Å)

**Fail:** Modal shows no message, or shows a generic threshold string with no direction.

---

### 2b. Two-Tier Alignment Failure — Critical Severity

RNA-seq alignment failures now have two severity levels:

| Alignment rate | Expected behavior |
|---|---|
| 40–69% | Gate fires with normal `warning` severity |
| < 25% | Gate fires with `critical` severity + message about **species/genome mismatch** |

**How to see the severity:** In the QC gate modal's failed metric, the message for the
critical case explicitly says *"usually indicate a species/genome mismatch, corrupt input,
or heavy contamination — verify input data before adjusting parameters."*

**Test case:** In the SSE developer panel or backend log, trigger the STAR_ALIGN gate
with `alignment_rate = 8` and confirm the message contains the species-mismatch language.

---

### 2c. Near-Threshold Warnings (qc_warning SSE events)

When a metric is approaching but has NOT yet crossed a blocking threshold, the system
now emits a `qc_warning` event (not a modal-triggering `qc_gate_triggered` event).

**Which metrics have near-threshold warnings:**

| Metric | Blocking threshold | Warning fires when |
|---|---|---|
| `alignment_rate` | < 70% | 70–77% |
| `reads_surviving_pct` | < 70% | 70–77% |
| `mapping_rate` | < 50% | 50–55% |
| `classified_pct` | < 30% | 30–33% |
| `coverage_mean` | < 30× | 30–33× |
| `tss_enrichment` | < 7.0 | 7.0–7.7 |
| `nrf_score` | < 0.8 | 0.8–0.88 |
| `ctf_fit_quality` | < 0.70 | 0.70–0.77 |
| `particles_selected` | < 50,000 | 50,000–55,000 |
| `junk_class_fraction` | > 0.50 | 0.45–0.50 |
| `avg_phase_shift_rad` | outside 0.2–1.5 | 0.20–0.22 (depletion) or 1.35–1.50 (over-charge) |

**Expected UI behavior:** A `qc_warning` event should be visible in the step annotation
below the relevant step — a small amber `⚠ Last run: QC warning` label — but NO modal
appears. The workflow continues uninterrupted.

**Fail:** Either a modal blocks the workflow for a near-threshold value, or no annotation
appears at all after a warning event.

---

### 2d. 2D Classification Junk Fraction Gate (NEW routing)

Process names `CLASSIFY_2D_R1`, `CLASSIFY_2D_R2`, `CLASS_2D`, `2D_CLASSIFICATION`
were previously falling through to a null route. They are now routed correctly.

**Expected:** If the cryo-EM pipeline reaches a 2D classification step where
`junk_class_fraction > 0.5` (more than half of classes are junk), an advisory BRONZE gate
fires with the message referencing junk fraction.

---

### 2e. Volta Phase Plate (VPP) CTF Gate (NEW)

Only relevant when `params.phase_plate = true` is passed to the SPA pipeline.

**Two advisory scenarios:**

| Condition | Message |
|---|---|
| `avg_phase_shift_rad < 0.20` | VPP depleted — continue collecting but monitor |
| `avg_phase_shift_rad > 1.50` | VPP over-charged — allow to regenerate |

Both are BRONZE advisory (non-blocking). The workflow continues; the step annotation
shows "Last run: QC warning".

**Named profile** `cryoem_spa_phase_plate` relaxes `fit_quality` threshold to 0.65
(phase plates inherently lower CTF fit quality — this is expected).

---

### 2f. Chemoproteomics Pulldown / ABPP Enrichment Gate (NEW)

Process names: `CHEMOPROTEOMICS_PULLDOWN`, `ABPP_PULLDOWN`, `ABPP`, `PULLDOWN`.

**Gate:** `median_enrichment_ratio < 3×` → SILVER blocking gate fires.

**Workflow:** `proteomics/chemoproteomics_pulldown/main.nf`
- Input: MaxQuant `proteinGroups.txt` or any CSV with intensity columns
- Output: `enrichment_ratios.tsv` + `pulldown_summary.json`

**Test steps:**
1. Ask: *"Run chemoproteomics pulldown QC"* and supply a proteinGroups file
2. If median enrichment < 3×, blocking gate modal should appear with process name
   humanised as **"Chemoproteomics Pulldown"** (not `CHEMOPROTEOMICS_PULLDOWN`)

---

## 3. Parser–Workflow Alignment Fixes (What Was Broken, Now Fixed)

These are invisible to the user but important to verify end-to-end. If a gate
that should fire never fires, it is likely a parser–workflow mismatch regression.

**Full audit report:** `docs/QC/20260303_2215_PARSER_WORKFLOW_AUDIT_REPORT.md`

Summary of the 6 fixes applied:

| Domain | Was broken | Now reads |
|---|---|---|
| Cryo-EM sharpening | `sharpening_results.json` + `bfactor_angstrom_squared` | `sharpening_report.json` + `b_factor_applied` |
| Cryo-EM local resolution | `local_resolution_results.json` + `std_spread_angstrom` | `local_resolution_report.json` + `std_resolution_angstroms` |
| Molecular docking | Scores computed in subprocess, discarded | `docking_autodock_vina_results.json` with `best_score_kcal_mol` at top level |
| QSAR (was phantom) | No workflow existed | `qsar_rf_model/main.nf` writes `qsar_results.json` |
| CryoSPARC CTF | Only read CTFFIND4 `.txt` format | Also reads `micrographs_ctf.cs` (JSON array) + `ctf_report.json` |
| 2D classification | `CLASSIFY_2D_R1/R2` never routed | Now routed to `_parse_2d_classification_metrics()` |

**Smoke check:** After running a cryo-EM SPA workflow in mock mode, confirm:
- A sharpening advisory gate or annotation appears (B-factor gate)
- A 2D classification annotation appears if junk fraction > 50%
- NO "gate would have fired but returned None" message in logs

---

## 4. Run Manager — New Feature

A runs overview panel is now available in the chat UI.

**API endpoint:** `GET /api/workflows/runs/overview`

Query params:
- `scope` — `current_chat` (default) or `all_chats`
- `status` — `running`, `completed`, `failed`, or omit for all
- `search` — free-text search against workflow name
- `sort` — `createdAt_desc`, `updatedAt_desc`, `status_asc`, etc.
- `limit` / `offset` — pagination

**UI panel:** In `chat-with-artifacts.tsx`, there is a run manager scope toggle
(current chat / all chats) with filter and sort controls.

**Test:**
1. Run two workflows in two different chat sessions
2. Switch run manager scope to "all chats"
3. Confirm both runs appear with correct status badges and output readiness hints

---

## 5. Nextflow Entry Auto-Detection

Workflows that define only **named** workflow blocks (no anonymous `workflow { }`)
previously had to be called with an explicit `-entry` flag.

Now the executor auto-detects the right entry point:

```
workflow QSAR_RF_MODEL_WORKFLOW { ... }   → -entry QSAR_RF_MODEL_WORKFLOW
workflow CHEMOPROTEOMICS_PULLDOWN_WORKFLOW { ... }  → -entry CHEMOPROTEOMICS_PULLDOWN_WORKFLOW
```

The frontend also now validates whether a `.nf` file is runnable before showing the
Execute button (checks for at least one workflow block).

**Test:** Run `pharmacology/qsar_rf_model/main.nf` via the UI without setting any
`-entry` override. It should start without a Nextflow "entry not found" error.

---

## 6. QC Profile Selector — Now Wired End-to-End

Previously: `execution-control-panel.tsx` had a dropdown for named QC profiles but it
was never passed to the backend (missing schema field + missing proxy + missing execute body).

**Now fully wired:**
- `ExecutionConfig` schema has `qcProfile` and `qcOverrides` fields
- `GET /api/qc/profiles` is proxied from frontend → backend (returns all 31 profiles live)
- Nextflow execute call includes `qc_profile` and `qc_overrides` when set

**Test:**
1. Open any workflow in the execution panel
2. Expand the QC settings section
3. Select a named profile (e.g. `rnaseq ribodepleted`)
4. Execute the workflow
5. In the backend logs, confirm: `"[QC Profile] Invocation ...: named profile 'rnaseq_ribodepleted' active"`

---

## 7. QC Summary Panel — After Workflow Completes

When a workflow finishes, a **QC Summary** panel now appears in the completion section.

**What it shows:**
- Gate count (red) and warning count (amber)
- Per-event details with the process name and specific failure/warning messages
- Active profile badge if a named profile was used
- Auto-generated **methods text** with a "Copy methods text" button

**Expected behavior:**
- Panel only appears if at least one gate or warning event was recorded during the run
- "Copy methods text" copies a paragraph like:
  > *"Quality control was performed automatically by BioMate using named profile
  > 'rnaseq_ribodepleted'. QC gates were triggered for 1 process(es) (STAR_ALIGN).
  > A total of 2 near-threshold advisory warning(s) were recorded. Gate thresholds
  > and references are described in the BioMate QC governance documentation."*

**API endpoint (if testing directly):**
```
GET /api/invocations/:id/qc-events
```
Returns `{ gates_triggered, warnings_emitted, events[], methods_text }`.

**Fail criteria:** Panel doesn't appear after a workflow that had gate events, OR
"Copy methods text" produces generic/empty text.

---

## 8. Quick Reference — New Thresholds Added Since Last Plan

| Domain | Metric | Gate |
|---|---|---|
| Alignment | < 25% | CRITICAL severity (see §2b) |
| ABPP pulldown | median enrichment < 3× | SILVER blocking |
| QSAR | cv_r2_score < 0.5 | SILVER blocking |
| VPP phase plate | < 0.20 rad | BRONZE advisory (depleted) |
| VPP phase plate | > 1.50 rad | BRONZE advisory (over-charged) |
| 2D classification | junk_class_fraction > 0.50 | BRONZE advisory |
| 2D classification | junk_class_fraction > 0.70 | BRONZE advisory (escalated) |

---

## Known Gaps (Not Yet Implemented)

These are documented to avoid confusion if a tester looks for them:

- **Phase plate CTF gate calibration:** `ctf_cross_correlation` from CryoSPARC (range 0.05–0.20)
  does not map to the CTFFIND4 `fit_quality` gate. The CC metric is stored separately;
  no hard gate threshold yet (needs calibration against real CryoSPARC data).
- **QSAR workflow real validation:** The `qsar_rf_model/main.nf` works in mock/RDKit mode;
  production accuracy with real compound datasets has not been benchmarked yet.

---

## 9. UX — QC Behaviour Changes (2026-03-04 second pass)

### 9a. Skip Pilot — 7-day suppression (US-4.1)

When a user clicks **Skip pilot** (or **Skip** in unified mode), the preference is
now stored in `localStorage` for 7 days keyed by workflow name.

**Expected:** After clicking Skip, refreshing the chat and opening the same workflow
does NOT show the pilot banner again. After 7 days (or clearing localStorage) the
banner reappears.

**Note shown in banner:** *"This workflow won't ask for a pilot again for 7 days."*

---

### 9b. "Pause at QC failures" toggle (US-4.2)

In the **Execution Panel → QC Settings** section, a new toggle appears:

| Toggle state | Behaviour |
|---|---|
| ON (default) | Workflow pauses on QC gate and shows the blocking modal |
| OFF | All suggestions with confidence ≥ 0.7 are auto-applied; workflow continues; step gets an amber QC annotation |

**Test:** Turn toggle OFF, run a cryo-EM SPA workflow in mock mode. When a
CTF gate fires, confirm no modal appears — instead the step shows
"Last run: QC warning" annotation and the workflow continues.

---

## 10. Parameter Suggestions — New Domains

Three new suggester classes now provide actionable suggestions when QC gates fire:

### 10a. Drug discovery (hERG, DILI, Ames, pulldown, QSAR)

| Process | Gate metric | Suggestion |
|---|---|---|
| HERG_PREDICTION | IC50 < 1 μM | Enable BRENK structural alert filter |
| HERG_PREDICTION | IC50 1–10 μM | Enable hERG liability filter |
| DILI_PREDICTION | high/medium | Enable DILI structural alert filter |
| AMES_MUTAGENICITY | prob ≥ 0.7 | reactive_group_filter + PAINS filter |
| CHEMOPROTEOMICS_PULLDOWN | enrichment < 3× | input_protein_ug + beads_ul |
| QSAR_RF_MODEL | CV R² < 0.5 | n_estimators + feature_selection |

### 10b. Proteomics (MaxQuant, DIA-NN)

| Process | Gate metric | Suggestion |
|---|---|---|
| MAXQUANT | PSM/protein FDR > 1% | Tighten mass tolerance + reduce missed cleavages |
| MAXQUANT | Missed cleavage > 20% | Longer digestion + higher enzyme:protein ratio |
| MAXQUANT | Phosphosite localiz. < 0.75 | Switch to ptmRS algorithm |
| DIANN | Protein FDR > 1% | Tighter Q-value + --pg-level 2 |

### 10c. Cryo-EM sharpening and local resolution

| Process | Gate metric | Suggestion |
|---|---|---|
| SHARPENING | B-factor > 0 | Suggest −50 Å² (Rosenthal & Henderson, literature) |
| SHARPENING | B-factor < −300 | Suggest gentler −100 Å² |
| LOCAL_RESOLUTION | std spread > 3.0 Å | local_ctf_refinement + local_motion_correction |

**Test:** Trigger any of the above gates and confirm the modal shows at least one
suggestion card with a specific parameter and suggested value (not just the
troubleshooting steps fallback).

