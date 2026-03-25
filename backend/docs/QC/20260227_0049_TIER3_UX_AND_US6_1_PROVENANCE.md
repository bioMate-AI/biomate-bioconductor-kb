# QC Governance UX — Tier 3 Implementation + US-6.1 Suggestion Provenance
**Date:** 2026-02-27 00:49
**Session scope:** Completing all remaining Tier 1/2/3 UX user stories; Paper 1 supplementary S1–S4; WES somatic tests

---

## 1. WES Somatic 150X Coverage Auto-Detect — Tests Added

`TestWESSomaticCoverageAutoDetect` class (8 tests) added to `tests/test_qc_edge_cases.py`.

| Test | What it verifies |
|---|---|
| `test_wes_somatic_domain_fires_gate_below_150x` | `wes_somatic` domain: 130X → gate fires at 150X |
| `test_wes_somatic_domain_passes_above_150x` | `wes_somatic` domain: 155X → pass |
| `test_wes_tumor_normal_alias_fires_gate_below_150x` | `wes_tumor_normal` alias also maps to 150X |
| `test_standard_wes_passes_at_90x` | Standard WES 90X → pass (80X threshold unaffected) |
| `test_standard_wes_fires_gate_below_80x` | Standard WES 60X → gate fires at 80X not 150X |
| `test_wes_somatic_near_threshold_emits_warning` | 152X (within 10% above 150X) → `qc_warning` SSE, not gate |
| `test_wes_somatic_tumor_normal_profile_sets_150x` | Named profile `wes_somatic_tumor_normal` → 150X threshold |
| `test_wes_somatic_tumor_only_profile_sets_200x_and_relaxed_dup` | Named profile `wes_somatic_tumor_only` → 200X + dup tolerance 50% |

**Test count after addition:** 325 passing (core QC suite).

---

## 2. Paper 1 Supplementary Materials (S1–S4)

All four supplementary files written to `research_repos/biomate_qc_governance_paper/supplementary/`:

| File | Contents |
|---|---|
| `qc_thresholds_evidence.md` (S1) | Complete citation table for all QC thresholds across 6 domains (281 lines) — sourced from `docs/QC/20260224_QC_THRESHOLDS_EVIDENCE.md` |
| `named_profiles_full.md` (S2) | All 28 named profiles with full override tables and provenance (500 lines) |
| `test_suite_documentation.md` (S3) | 470 tests organised by class, domain, and governance layer (147 lines) |
| `api_reference.md` (S4) | QC gate API contract, SSE event schema, audit log format, `/api/qc/profiles` endpoint (296 lines) |

**Paper 1 overview status updated:** `20260225_1545_PAPER1_OVERVIEW.md` — status line now reads:
> "Backend complete (470 tests); all P0 fixes done; all Tier 1+2 UX done; supplementary S1–S4 written; benchmark datasets needed (AWS)"

---

## 3. Tier 3 UX — US-4.3: Custom QC Thresholds UI

Enables users to select a named QC profile and add per-metric overrides directly in the Execution Control Panel.

### Files changed

**`frontend/shared/schema.ts`** — extended `executionConfigSchema`:
```typescript
qcProfile: z.string().optional(),
qcOverrides: z.record(z.number()).optional(),
```

**`frontend/server/routes.ts`** — forwards QC fields to backend execute call:
```typescript
...(request.executionConfig?.qcProfile && { qc_profile: request.executionConfig.qcProfile }),
...(request.executionConfig?.qcOverrides && ... && { qc_overrides: request.executionConfig.qcOverrides }),
```

**`frontend/client/src/components/execution-control-panel.tsx`** — added collapsible "QC Governance" section:
- `GET /api/qc/profiles` fetched on mount; 28 hardcoded profile IDs as fallback
- Profile selector dropdown (all 28 named profiles)
- Per-metric override editor: key/value pairs, Add / Delete
- `buildConfig()` includes `qcProfile` and `qcOverrides` when non-empty

---

## 4. Tier 3 UX — US-1.2: Phase 0 / Phase 1 Visual Distinction

`frontend/client/src/components/workflow-artifact.tsx` — added two visual elements when `pilotRunSuggested`:

**Phase 0 header** (above step list):
- Coloured badge: amber (idle) → blue (running) → green (completed)
- Label: "Phase 0 · Pilot" + status text "Running on sample subset…" / "Complete" / "Ready to run"

**Phase 1 locked indicator** (below step list, hidden after pilot completes):
- Dashed border, Lock icon
- Text: "Phase 1 · Full Dataset — Full dataset run starts after pilot QC passes"

---

## 5. US-6.1: Suggestion Provenance Badges

Surfaces the evidential basis for each parameter suggestion in the QC gate modal.

### Backend — `backend/lib/galaxy/jobs/parameter_suggester.py`

Added `source: str = "rule"` to `ParameterSuggestion` dataclass:
```python
@dataclass
class ParameterSuggestion:
    parameter: str
    current_value: Any
    suggested_value: Any
    reason: str
    confidence: float
    source: str = "rule"  # "rule" = empirical heuristic; "literature" = cites a paper/standard
```

Tagged 5 suggestions as `source="literature"`:

| Suggester | Parameter | Citation |
|---|---|---|
| `ChIPSeqParameterSuggester` | `shift=-100` | ENCODE4; Corces et al. (2017) Nat Methods |
| `ChIPSeqParameterSuggester` | `extsize=200` | ENCODE4 ATAC-seq standards |
| `ChIPSeqParameterSuggester` | `pcr_cycles` | ENCODE4 library complexity standards |
| `RNASeqParameterSuggester` | `twopass_mode` | Dobin et al. (2013) Bioinformatics; nf-core/rnaseq |
| `RNASeqParameterSuggester` | `decoy_aware` | Srivastava et al. (2020) Bioinformatics |

All other suggestions default to `source="rule"` (empirical heuristic).

### Backend — `backend/lib/galaxy/jobs/qc_trace_monitor.py`

Added `"source": s.source` to the SSE serialization dict (line ~2811):
```python
suggestions = [
    {
        "parameter": s.parameter,
        "currentValue": s.current_value,
        "suggestedValue": s.suggested_value,
        "reason": s.reason,
        "confidence": s.confidence,
        "source": s.source,  # US-6.1
    }
    for s in suggestion_objects
]
```

### Frontend — `frontend/client/src/components/qc-gate-modal.tsx`

- `ParameterSuggestion` interface extended: `source?: string`
- `BookOpen` icon imported from lucide-react
- Source badge rendered inline with confidence badge, **only when `source === "literature"`**:

```tsx
{suggestion.source === "literature" && (
  <span className="inline-flex items-center gap-1 text-xs text-sky-600 dark:text-sky-400 font-normal">
    <BookOpen className="h-3 w-3" />
    Literature
  </span>
)}
```

Rule-based suggestions show no badge (default, keeps UI uncluttered).

---

## Remaining Tier 3 Items (not yet implemented)

| Story | Description |
|---|---|
| US-4.2 | "Pause at QC failures" toggle — auto-apply high-confidence suggestions without showing modal |
| US-5.1 | Multi-job QC triage dashboard |
| US-5.2 | Automated mode + email escalation |

---

## Verification

```bash
# Backend: 325/325 passing
cd /home/yzhang/biomate/backend
.venv/bin/python -m pytest tests/test_qc_edge_cases.py -q --tb=short

# Frontend: no new TypeScript errors introduced
cd /home/yzhang/biomate/frontend
npx tsc --noEmit 2>&1 | grep "qc-gate-modal\|parameter_suggester"  # should be empty
```
