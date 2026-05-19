# ra-drugscreen.en (compressed for 3:00)

## Step 1 — Intro, centered

Drug screens often require a pilot, fail QC, then recover via auto-loop. A specific scenario surfaces the Run-vs-Run comparison card by default.

---

## Step 2 — Plan checklist, five sub-tasks

BioMate decomposes the request into five sub-tasks. Ingest, ADMET prediction, hERG gate, Ames gate, and Ranking. Each proceeds.

---

## Step 3 — Pilot prompt

For ten thousand compounds, DeepAgent suggests a five-percent pilot. The card shows sampling fraction, strategy, and full-run cost. Make your decision directly in chat.

---

## Step 4 — Pilot running

Pilot run processing 500 of 10,000 compounds. Plan items tick to checkmark. This validates QC gates before the full run.

---

## Step 5 — QC failure mid-pilot

hERG and Ames trip. Plan items show amber warnings. The pipeline continues; next surface holds decision. QC gates evaluate per phase. Trips trigger auto-loop proposed fixes.

---

## Step 6 — QC speaker pills

Two amber QC pills for hERG and Ames appear in chat. Their color matches warn pills, stable across plan, chat, Tweaks.

---

## Step 7 — Pilot stopped · QC gates triggered

The pilot card explains failure, showing the auto-loop's suggested fix. New `logp_max` and `mw_max` values are offered. One-click Apply fixes and re-pilot applies them. Users always see changes; no silent retry occurs.

---

## Step 8 — Auto-loop · LOOP speaker

LOOP (purple pill) takes over. LOOP logs auto-loop decisions, keeping audit trail clear. QC re-evaluates; both gates pass second run.

---

## Step 9 — Run-vs-Run comparison card

Comparison card shows two pilots, side-by-side metrics, delta column. Parameter diffs are origin-tagged. Trophy badge displays recommendation, confidence, p-value. QC outcomes are red (Run A), green (Run B). Quick decisions.

---

## Step 10 — Ten-second auto-pick

High confidence (p < 0.01) starts a 10-second countdown. Hover pauses; click commits. An auto-fire confirms automatic selection. Otherwise, the user must pick.

---

## Step 11 — Full run on Run B params

Decision committed. Ten thousand compounds now run using auto-loop's tuned parameters. Plan items fast-track; the pilot proved gates.

---

## Step 12 — Findings card · 47 candidates

The completion summary lands inline. Forty-seven BBB-penetrant candidates passed QC. See runtime, QC pass-rate, and full Report link. Hover anchors for tool choice rationale.

---

## Step 13 — Wrap-up, centered

Pilot, fail, auto-loop, compare, full, findings ran. Generated three decision cards, one comparison card, plus a clean audit trail.

---
