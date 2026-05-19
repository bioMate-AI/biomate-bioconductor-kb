# ra-drugscreen.en (compressed for 3:00)

## Step 1 — Intro, centered

Drug screens often require preliminary steps, fail QC, and auto-recover. One scenario surfaces the Run-vs-Run comparison card by default.

---

## Step 2 — Plan checklist, five sub-tasks

BioMate orchestrates multi-stage assessments for drug candidates. It first decomposes each request into five distinct sub-tasks. These include Ingest, ADMET prediction, hERG gate, Ames gate, and Ranking.

---

## Step 3 — Pilot prompt

10,000 compounds represent significant workload. DeepAgent suggests a five-percent pilot. The card consolidates sampling fraction, strategy, and full-run cost. Decisions are made in chat.

---

## Step 4 — Pilot running

The pilot is running on 500 of 10,000 compounds. Plan items tick from circle to dot, indicating engine advance. This small pilot validates QC gates before committing the full run.

---

## Step 5 — QC failure mid-pilot

hERG and Ames trip. Plan items turn amber. Pipeline continues; next surface holds the decision. QC gates evaluate per phase. A trip means the auto-loop will propose fixes.

---

## Step 6 — QC speaker pills

Two QC pill lines for hERG and Ames appear in chat. Amber pills match warn pills on the plan. Colors are stable across plan, chat, and Tweaks panel.

---

## Step 7 — Pilot stopped · QC gates triggered

The pilot card explains failures, suggesting new `logp_max` and `mw_max` values. Apply fixes with one click via `Apply fixes and re-pilot`. Users always review changes; no silent retries.

---

## Step 8 — Auto-loop · LOOP speaker

The fix is applied. The LOOP speaker takes over. All lines under LOOP are auto-loop decisions, maintaining a clear audit trail. QC re-evaluates. Both gates pass on the second run.

---

## Step 9 — Run-vs-Run comparison card

Two pilots complete. The comparison card displays metrics with delta, and parameter diffs by origin. A trophy badge shows recommendation, confidence, p-value. QC outcomes are color-coded for instant decision.

---

## Step 10 — Auto-pick

For high confidence (p < 0.01), the recommended option is automatically selected. Manual selection overrides this default. If confidence is medium or low, you must pick an option.

---

## Step 11 — Full run on Run B params

Decision committed. The full screen now processes ten thousand compounds, applying the auto-loop's tuned parameters. Plan items advance; the pilot already proved the gates.

---

## Step 12 — Findings card · 47 candidates

The completion summary appears inline. Forty-seven BBB-penetrant candidates after all QC gates. View QC pass-rate and a link to the full Report. Find tool choice rationale on earlier step lines.

---

## Step 13 — Wrap-up, centered

The end-to-end auto-loop finished. You observed pilot, fail, auto-loop, compare, full, and findings. This included three decision cards, one comparison card, and a clean audit trail.

---
