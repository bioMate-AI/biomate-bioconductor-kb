# ra-drugscreen narration (EN)

## Step 1 — Intro, centered

Drug screens often need a pilot, fail QC, and recover via auto-loop. We'll watch the whole sequence inline — and meet the one scenario that surfaces the Run-vs-Run comparison card by default. The tour drives every decision for you.

---

## Step 2 — Plan checklist, five sub-tasks

BioMate decomposes the request into five sub-tasks. Ingest. ADMET prediction. hERG gate. Ames gate. Ranking. Each ticks in place. Watch the hERG and Ames rows — they'll trip mid-pilot.

---

## Step 3 — Pilot prompt

Ten thousand compounds is heavy. The DeepAgent suggests a five-percent pilot first. The card carries the sampling fraction and strategy side-by-side with the full-run cost — no separate dialog. The decision lives in chat.

---

## Step 4 — Pilot running

The pilot is now running on 500 of 10,000 compounds. Plan items tick from circle to dot to checkmark as the engine advances. A small pilot validates the QC gates before committing the full run.

---

## Step 5 — QC failure mid-pilot

hERG and Ames trip. The plan items flip to amber warn pills in place. The pipeline doesn't crash — the next surface carries the decision. QC gates evaluate per phase. A trip means the auto-loop will propose fixes.

---

## Step 6 — QC speaker pills

Two QC pill lines land in chat — one for hERG, one for Ames. The pills are amber, color-coded to match the warn pills on the plan. Pill colors never lie — they're stable across the plan, the chat, and the Tweaks panel.

---

## Step 7 — Pilot stopped · QC gates triggered

The pilot promotion card explains what failed and shows the auto-loop's suggested fix right there — new *logp_max* and *mw_max* values, with a one-click *Apply fixes and re-pilot* action. No silent retry — the user always sees the proposed change before it runs.

---

## Step 8 — Auto-loop · LOOP speaker

We just applied the fix. The LOOP speaker — purple pill — takes over. Every line under LOOP is an auto-loop decision, so the audit trail stays clear. QC re-evaluates, and both gates pass on the second run.

---

## Step 9 — Run-vs-Run comparison card

Two pilots done. The comparison card lays them side by side. Metrics table with a delta column. Parameter diffs tagged by origin — auto-loop versus user. A trophy badge with the recommendation, confidence, and p-value. QC outcomes are colored red on Run A, green on Run B, so the decision reads at a glance.

---

## Step 10 — Auto-pick

When confidence is high — p less than zero-point-zero-one here — the recommended button shows a short countdown. Hover any button to pause it; click to commit. An auto-fire emits a *No response — using Run B automatically* line so nothing happens silently. Medium or low confidence: no auto-fire. The card sits until the user picks.

---

## Step 11 — Full run on Run B params

Decision committed. The full screen now runs on ten thousand compounds using the auto-loop's tuned parameters. Plan items tick again — faster this time, since the pilot already proved the gates.

---

## Step 12 — Findings card · 47 candidates

The completion summary lands inline. Forty-seven BBB-penetrant candidates after all QC gates. Runtime, QC pass-rate, and a link to the full Report — Findings, Outputs, Methods, Parameters, Software, Citations. Hover any *(why?)* anchor on earlier step lines to see the rationale that drove tool choice.

---

## Step 13 — Wrap-up, centered

End-to-end auto-loop, done. You just watched pilot, fail, auto-loop, compare, full, findings. Three decision cards, one comparison card, and a clean audit trail by speaker. The Variant calling tutorial covers nested plans and step retry — try it next.

---
