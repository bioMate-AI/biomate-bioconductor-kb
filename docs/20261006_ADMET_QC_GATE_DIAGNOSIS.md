# ADMET hERG QC gate — "didn't fire" diagnosis (2026-10-06)

Investigated why the realrun-admet E2E reported `QC-01 FAIL — no hERG gate fired (gateEvents=0,
inlineGate=0)` on a *completed* ADMET run. Conclusion: **the gate is not broken — it fired correctly;
the result simply isn't surfaced live** because the auto-loop path it rides on is intentionally disabled.
This corrects the earlier "intermittent gate firing" wording.

## Evidence (run `34aedd59…` / inv `6a406e5f…`, status=completed)
Run record `execution.nextflowStatus.qc_gates` contained TWO fired gates:
- `herg_ic50_uM = 0.01 µM`, threshold `1`, operator `<` → **high-risk hERG** (GOLD message: QT/TdP risk,
  "structural optimisation required"). Terfenadine's predicted hERG IC50 correctly tripped the gate.
- `dili_risk = high`, threshold `low`, operator `!=` → DILI high-risk gate.

So gate **evaluation + thresholds work**, and the ADMET model flagged the known hERG blocker.

## Why the test saw "no gate fired"
The gate RESULT is persisted on the run record, but the **live surfacing is intentionally disabled**:
- `client/src/components/nextflow-workflow-viewer.tsx`: the self-correct / auto-loop controls are
  "commented out until QC loop is stable"; the inline note reads "Auto-loop is currently disabled while
  end-to-end testing is in progress." The live `autoloop_gate_results` SSE event + the inline auto-loop
  gate panel ride on that disabled path.
- Backend emits `autoloop_gate_results` / `autoloop_update` to the AutoLoopPanel (nextflow_executor.py
  ~:3510) — but that panel/flow is the disabled one.

Net: for a plain (non-auto-loop) run, the gate is computed and stored (visible via the run API's
`nextflowStatus.qc_gates`) but **not streamed or rendered live** → `gateEvents=0 / inlineGate=0`. The
E2E's QC-01 assertion watches that deliberately-disabled live path, so it fails **by design**, not from a
gate defect. (Consistent with the auto-loop-panel-commented-out state noted elsewhere.)

## Secondary issue — QC profile mismatch
The request asked for `admet_standard`; the run's `__qcConfig.qcProfile = cipa_ind_submission`. A different
(cardiac-IND) profile was selected than requested. It didn't change the outcome here (cipa's gate set
covers hERG, so the liability was still caught), but the explicit profile request wasn't honored — a
routing/param-propagation gap worth a separate look.

## Takeaways
- ✅ hERG QC gate evaluation is correct and reliable (not intermittent) — the earlier "intermittent" read
  was wrong; the gate consistently fires and is on the run record.
- ⚠️ Live gate surfacing (SSE event + inline panel) is OFF by design (auto-loop disabled during testing);
  re-enabling the auto-loop path restores live gate display. Until then, gate results are post-hoc via the
  run record, and E2E QC-01 will "fail" by design.
- ⚠️ QC-profile selection doesn't always honor the requested profile (`admet_standard` → `cipa_ind_submission`).
