# `qc-events.measured` field — single-token value contract

**Date:** 2026-06-11
**Surface:** `GET /api/invocations/:id/qc-events` response, `events[].measured`
**Audited:** v2 visual-audit pass, defect A2 in `docs/20260610_V2_BIOC_HANDOFF_PROGRESS.md`

---

## Contract

Each event in the `events[]` array carries a `measured` field. **The
rendered table column ("Observed") expects a single-token value** — not a
value plus a parenthetical breakdown.

```ts
// frontend/client/src/v2/AfterRunReport.tsx — QcAuditTab
interface QcEvent {
  ts?: string;
  gate?: string;
  status?: string;
  message?: string;
  measured?: string | number;   // ← single token
  threshold?: string | number;  // ← single token (e.g. "≥ 0.70", "0.5 – 2.0")
}
```

The component renders `e.measured` verbatim into the table cell. Whatever
the backend ships is what the user sees, with no client-side parsing or
trimming. If backend packs `"0.771 (14,203 / 18,421)"` into one field, the
cell becomes visually dense and inconsistent with the rest of the row.

## ✅ Good — single-token values

| Gate | Measured | Threshold |
|---|---|---|
| `gene_retention` | `"0.771"` | `"≥ 0.70"` |
| `size_factor_range` | `"0.42"` | `"0.5 – 2.0"` |
| `replicate_count` | `"6"` | `"≥ 3"` |
| `de_count` | `"2,841"` | `"≥ 100"` |
| `fsc_resolution_a` | `"3.21 Å"` | `"≤ 3.5 Å"` |
| `ctf_quality` | `"0.143"` | `"≥ 0.30"` |

## ❌ Bad — packed values

| Backend ships | Problem |
|---|---|
| `"0.771 (14,203 / 18,421)"` | Numerator/denominator should be Findings-tab retention figure, not duplicated in QC log |
| `"0.42 (below)"` | "below" is already the Result column |
| `"6 per group"` | "per group" is implied by the gate name; column gets wide |
| `"2,841 genes"` | "genes" is implied by `gate=de_count`; column gets wide |

## Why this matters

The QC audit table is the **21 CFR Part 11 compliance lens** (handoff §5.7).
Reviewers scan it row-by-row to confirm each gate fired, what it observed,
and how the system responded. A single-token Observed value:

1. **Aligns vertically** across rows so a regulator's eye can sweep the
   column without parsing prose
2. **Mirrors the audit-log format** in `qc_evidence.yaml` and the Galaxy
   backend's `qc_metrics.json` emit (both store value + unit, not packed
   strings)
3. **Composes with the auto-loop remediation card** — the remediation
   card already shows the was→now diff with proper units; duplicating
   that detail in Observed is redundant

## Where to enforce

| Layer | What to do |
|---|---|
| **Galaxy backend** | When emitting QC events from `qc_gate_reader.py` / `qc_trace_monitor.py`, set `event.measured` to the bare value (with unit if scientifically required, e.g. `"3.21 Å"`). Push ratios and breakdowns into Findings-tab figures or the methods report. |
| **biomate Node bridge** | `/api/invocations/:id/qc-events` proxy — pass through unmodified; do not concatenate fields. |
| **v2 QcAuditTab** | Render `e.measured` verbatim. No formatting. (Current behavior — confirmed in `frontend/client/src/v2/AfterRunReport.tsx` line ~875.) |

## How A2 surfaced

During the 2026-06-11 v2 visual-audit pass, I authored a mock `qcEvents`
payload for the audit harness that packed value + ratio. The screenshot
(`frontend/e2e/screenshots/v2-audit/qc_audit_tab.png` — first version)
showed the Observed column visibly busier than the rest of the row.

The **component was correct** — it renders backend-provided data — but
my mock revealed that without a backend contract, an inattentive
backend developer could ship the dense format and the table would
quietly degrade. Hence this note.

Documented as part of commit `<sha>` on the `bioc/v2-qc-audit-panel` branch.
