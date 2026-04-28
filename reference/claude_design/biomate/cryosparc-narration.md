## Step 1 — Hi! Let's run cryo-EM together

BioMate takes raw cryo-EM movies and returns a sharpened 3D map — fully automated, zero configuration required.

---

## Step 2 — This is the run header

The run header shows the workflow name, a live status badge, and a progress bar that fills as phases complete.

---

## Step 3 — 5 phases, 23 steps total

CryoSPARC SPA runs five phases: motion correction, particle picking, 2D classification, 3D reconstruction, and sharpening.

---

## Step 4 — What's inside Phase A?

Phase A auto-expands to show its steps. MotionCor2 aligns movie frames; CTFFIND4 estimates defocus for each micrograph.

---

## Step 5 — One primary action — Confirm & Run

BioMate pre-filled every parameter from your chat message. One button — Confirm and run — submits the pipeline to AWS Batch.

---

## Step 6 — We're off! Phase A is running

Status badge flips to running. Phase A motion correction is processing on Batch GPU instances. The progress bar is moving.

---

## Step 7 — Live progress per step

Each step shows a live status chip — queued, running, completed — updated in real time as MotionCor2 works through the stack.

---

## Step 8 — CTF fit quality gate just tripped

A QC gate fired mid-phase: CTF fit resolution is below threshold. BioMate paused before wasting compute on bad data.

---

## Step 9 — Auto-loop: try again with better parameters

BioMate proposes widening the defocus range to 0.5–4 µm. Accept and Phase A reruns automatically with the new parameters.

---

## Step 10 — Gate cleared — Phase A done

Retry succeeded. CTF quality now passes. Phase A is complete and Phase B starts automatically — no button press needed.

---

## Step 11 — Phase B: particle picking

Topaz, a neural-network picker, scans every micrograph and outputs particle coordinates for the next stage.

---

## Step 12 — Phase C: 2D classification

Particles sort into 2D classes. Junk classes — ice, carbon edges, aggregates — are dropped. Clean views advance to 3D.

---

## Step 13 — Phase D: 3D reconstruction

Ab-initio reconstruction builds the 3D model from scratch — no reference bias. Homogeneous refinement then iterates to convergence.

---

## Step 14 — Phase E: sharpening & validation

B-factor sharpening, FSC 0.143 resolution estimation, and local resolution mapping complete the publication-ready map.

---

## Step 15 — You can detach the watcher anytime

The watcher is a live SSE stream from AWS Batch. Close your browser anytime — the job keeps running and reattaches when you return.

---

## Step 16 — All 23 steps complete!

Status flips to completed. Your dataset went from raw movies to a sharpened 3D map at 3.1 ångström resolution.

---

## Step 17 — Outputs are downloadable now

Footer switches to Run again. Scroll up for View Results, Download All, and the AI Findings card.

---

## Step 18 — After-run section unlocked

Every completed run adds an After-run block: output file links, an AI summary, and a one-click Methods Report.

---

## Step 19 — That's a full cryo-EM run!

Nineteen steps, one pipeline. Real runs take 30 to 90 minutes on AWS. Next: try the Outputs and Findings tour.

---
