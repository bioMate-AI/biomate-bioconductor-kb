# Cryo-EM Real E2E Test — Plan & Implementation
*2026-03-11 21:00*

## What was planned

Design a real end-to-end test demonstrating a cryo-EM researcher running EMPIAR-10028
(β-galactosidase, 7028 movies) through BioMate, with:
1. Pilot run suggestion banner
2. QC Settings panel interaction
3. Full workflow execution with progress tracking
4. QC gate demonstration

---

## Gaps found during planning

| Gap | Found | Resolution |
|---|---|---|
| Pilot trigger never fires for cryo-EM | `ai_assistant.py` only checks `len(uploaded_datasets) > 20`; cryo-EM uses S3 paths, not Galaxy uploads | Added `num_movies > 1000` trigger (Reason 6) |
| No pilot banner in NextflowWorkflowViewer | Banner existed in `WorkflowArtifact` only | Added banner to `nextflow-workflow-viewer.tsx` |
| QC motion gate never fires in mock mode | QC parser reads `.log` / `*_motion.txt` (MotionCor2 text); mock writes JSON only | No change; documented as production-only behaviour |
| `total_drift_angstrom` field mismatch | Mock writes `total_motion_angstroms`; QC reads `total_drift_angstrom` | **Not fixed** — user confirmed "no more mock changes" |

---

## Code changes made

### 1. `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py`
**Lines ~1057–1085** (after Reason 5 "from_scratch"):

Added Reason 6 — large cryo-EM dataset pilot trigger:
```python
# Reason 6: Large cryo-EM dataset (num_movies > 1000)
_num_movies = None
for _pd in result.get('generated_parameters', []):
    for _key in ('num_movies', 'num_micrographs', 'movie_count'):
        if _key in _pd.get('parameters', {}):
            try:
                _num_movies = int(_pd['parameters'][_key])
            except (ValueError, TypeError):
                pass
if _num_movies is None and request.message:
    import re as _re
    _m = _re.search(r'\bnum_movies\s*=\s*(\d+)', request.message, _re.IGNORECASE)
    if _m:
        try:
            _num_movies = int(_m.group(1))
        except (ValueError, TypeError):
            pass
if _num_movies and _num_movies > 1000:
    pilot_reasons.append(
        f"Large cryo-EM dataset ({_num_movies:,} movies) — "
        f"pilot run on ~200 movies recommended before full processing"
    )
```

### 2. `frontend/client/src/components/nextflow-workflow-viewer.tsx`
**Between `<ParameterGroup />` and `<div data-testid="workflow-run-controls">`**

Added pilot run banner:
```tsx
{workflowDefinition?.pilot_run_suggested && !isExecuting && (
  <div className="rounded-lg border border-amber-300 bg-amber-50 ..."
       data-testid="pilot-run-banner">
    <AlertTriangle ... />
    <span className="font-semibold">Pilot run recommended</span>
    {workflowDefinition.pilot_message && (
      <span> — {workflowDefinition.pilot_message}</span>
    )}
  </div>
)}
```

**Wiring confirmed**: `workflowDefinition` prop = `message.metadata?.workflow` from
`chat-message.tsx:332`, which is the full backend response object including
`pilot_run_suggested` and `pilot_message` fields.

---

## New files created

| File | Purpose |
|---|---|
| `frontend/e2e/cryoem-real-e2e.e2e.ts` | Playwright E2E test (8 steps, no API mocking) |
| `docs/CRYOEM_E2E_USER_GUIDE.md` | Researcher step-by-step guide with QC parameter reference |

---

## Dataset

**EMPIAR-10028** — E. coli β-galactosidase
7028 EER movies, 0.885 Å/px, 300 kV Krios, D2, 180 Å diameter, target 2.2 Å

User does not download movies; parameters are specified in query to drive mock pipeline outputs.

---

## QC gate behaviour (important context)

The QC monitor parses motion correction from **text log files** (MotionCor2 `.log`, `*_motion.txt`),
looking for patterns like "Total motion: 15.3 Å".

The mock pipeline writes **JSON** (`motion_correction_report.json`). The parser never reads this,
so the motion gate (`total_drift_angstrom > threshold`) cannot fire in mock mode regardless of
the threshold override setting.

**In production** (real CryoSPARC + real RELION/MotionCor2):
- MOTION_CORRECTION logs are text files → QC gate fires automatically
- Setting `total_drift_angstrom=10` via QC overrides will flag most micrographs
- QC modal appears with GOLD/SILVER classification and remediation advice

---

## Verification

```bash
# Backend: cryo-EM QC tests still pass
cd backend && PYTHONPATH=lib python -m pytest tests/test_qc_e2e_domains.py -k cryoem -v

# Frontend: new E2E test (requires BioMate running on localhost:5173)
cd frontend && npx playwright test e2e/cryoem-real-e2e.e2e.ts --reporter=html

# Smoke test only (no browser, fast):
cd frontend && npx playwright test e2e/cryoem-real-e2e.e2e.ts -g "T0 cryoem profiles"
```
