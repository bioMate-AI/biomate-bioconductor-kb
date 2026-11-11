/**
 * Fixtures for <DataPerception>, shaped exactly like the backend profiler's
 * DataProfile.to_dict() (backend/lib/galaxy/ai/data_perception.py): legacy free
 * text PLUS the structured `findings` the card actually renders.
 */

import type { DataPerceptionProps, DataProfile } from "./data-perception";

/** A clean labelled table — good verdict, no reasons. */
export const GOOD_TABLE_PROFILE: DataProfile = {
  shape: { rows: 24, cols: 18_412 },
  effectiveN: 24,
  effectiveNReason: "dedup",
  duplicateRows: 0,
  classBalance: [
    { label: "control", frac: 0.5 },
    { label: "treated", frac: 0.5 },
  ],
  quality: "good",
  notes: ["24 rows × 18412 columns; no leakage, imbalance, or constant-column issues detected."],
  findings: [
    { section: "note", code: "table_clean", level: "info", params: { rows: 24, cols: 18412 } },
  ],
};

/** The EPAR JSONL file after the D1 fix: one near-constant column → Watch; one duplicate row. */
export const WATCH_JSONL_PROFILE: DataProfile = {
  shape: { rows: 2281, cols: 5 },
  effectiveN: 2280,
  effectiveNReason: "dedup",
  duplicateRows: 1,
  quality: "watch",
  signalSummary: ["1 column(s) are near-constant (>99% single value): source."],
  notes: ["2,281 rows × 5 columns."],
  findings: [
    { section: "signal", code: "near_constant", level: "watch", params: { count: 1, columns: ["source"], pct: 99 } },
    { section: "note", code: "table_summary", level: "info", params: { rows: 2281, cols: 5 } },
  ],
};

/** An imbalanced, leaky dataset — Watch with leakage + imbalance reasons and a plan line. */
export const WATCH_LEAKY_PROFILE: DataProfile = {
  shape: { rows: 300, cols: 54 },
  leakage: { detail: "'batch' (batch/id) is (near-)perfectly correlated with the outcome label." },
  effectiveN: 42,
  effectiveNReason: "imbalance",
  duplicateRows: 0,
  classBalance: [
    { label: "responder", frac: 0.07 },
    { label: "non-responder", frac: 0.93 },
  ],
  quality: "watch",
  notes: [
    "'responder' class is 7% — consider a balanced sampler.",
    "Effective N (42) is far below 300 rows — bounded by the minority class under strong imbalance.",
  ],
  findings: [
    { section: "note", code: "minority_class", level: "watch", params: { label: "responder", pct: 7 } },
    { section: "leakage", code: "batch_confound", level: "watch", params: { column: "batch" } },
    { section: "plan", code: "batch_covariate", level: "info", params: { column: "batch" } },
    { section: "note", code: "effective_n_imbalance", level: "watch", params: { n: 42, rows: 300 } },
  ],
};

/** A malformed upload — blocked verdict, no derived fields. */
export const BLOCKED_PROFILE: DataProfile = {
  shape: { rows: 0, cols: 0 },
  quality: "blocked",
  notes: ["No columns parsed from table."],
  findings: [{ section: "note", code: "no_columns", level: "blocked", params: {} }],
};

/** A profile from an older backend (no findings) — legacy free-text fallback. */
export const LEGACY_PROFILE: DataProfile = {
  shape: { rows: 24, cols: 3 },
  quality: "good",
  notes: ["Single-end reads detected across all 24 samples."],
  signalSummary: ["Top-2 PCs separate control vs treated."],
};

export const LEGACY_PLAN_IMPACT: NonNullable<DataPerceptionProps["planImpact"]> = [
  { observed: "single-end detected", effect: "suggested single-end pipeline" },
];
