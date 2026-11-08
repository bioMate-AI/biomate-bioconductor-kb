/**
 * Fixtures for <DataPerception>. These stand in for what the BACKEND
 * perception profiler will emit at ingest; no values are computed here.
 */

import type { DataPerceptionProps, DataProfile } from "./data-perception";

/** A clean bulk RNA-seq count matrix — good verdict, single-end note. */
export const GOOD_RNASEQ_PROFILE: DataProfile = {
  shape: { rows: 24, cols: 18_412 },
  effectiveN: 24,
  classBalance: [
    { label: "control", frac: 0.5 },
    { label: "treated", frac: 0.5 },
  ],
  signalSummary: [
    "Library sizes span 12M–31M reads; no obvious low-depth outlier.",
    "Top-2 PCs separate control vs treated (PC1 42% variance).",
  ],
  quality: "good",
  notes: ["Single-end reads detected across all 24 samples."],
};

export const GOOD_RNASEQ_PLAN_IMPACT: NonNullable<DataPerceptionProps["planImpact"]> = [
  { observed: "single-end detected", effect: "suggested single-end pipeline" },
  { observed: "balanced 12/12 design", effect: "kept default two-group contrast" },
];

/** An imbalanced, leaky dataset — watch verdict with call-outs. */
export const WATCH_LEAKY_PROFILE: DataProfile = {
  shape: { rows: 300, cols: 54 },
  leakage: { detail: "processing batch is perfectly correlated with the outcome label." },
  effectiveN: 41,
  classBalance: [
    { label: "responder", frac: 0.07 },
    { label: "non-responder", frac: 0.93 },
  ],
  signalSummary: ["3 columns are near-constant (>99% single value)."],
  quality: "watch",
  notes: [
    "Effective N (41) is far below 300 rows — strong within-batch correlation.",
    "Responder class is 7% — consider a balanced sampler.",
  ],
};

export const WATCH_LEAKY_PLAN_IMPACT: NonNullable<DataPerceptionProps["planImpact"]> = [
  { observed: "batch–label leakage", effect: "added batch as a covariate before modelling" },
];

/** A malformed upload — blocked verdict, no derived fields. */
export const BLOCKED_PROFILE: DataProfile = {
  shape: { rows: 0, cols: 0 },
  quality: "blocked",
  notes: ["File parsed to 0 rows — header present but no data records."],
};
