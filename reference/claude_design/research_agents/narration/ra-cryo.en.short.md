# ra-cryo.en (compressed for 3:00)

## Step 1 — Welcome, centered

Perform a complete cryo-EM single-particle analysis. BioMate manages CryoSPARC parameters, so you can easily follow along.

---

## Step 2 — Two views, one run, plan checklist

BioMate has two run views. Left chat tracks progress. Right workflow panel details phases, steps, parameters, outputs. Both stay in sync.

---

## Step 3 — Run header

Run header displays workflow name, status badge, and live progress bar. Status is idle: loaded but not started.

---

## Step 4 — Five phases, twenty-three steps

CryoSPARC SPA has five phases. Phase A: Motion correction, CTF. B: Particle picking. C: 2D classification. D: 3D reconstruction. E: Sharpening, validation.

---

## Step 5 — Inside Phase A

Active phase shows live step status. Phase A runs MotionCor2 for frame alignment. CTFFIND4 estimates defocus. View any phase anytime without disturbing run.

---

## Step 6 — One primary action, Confirm & Run

BioMate pre-filled parameters from your chat message. The Confirm and run workflow button submits the job to the cloud.

---

## Step 7 — Phase A is running

Status: running; progress moving. Phase A motion correction on Batch GPUs. Small datasets take three to six minutes.

---

## Step 8 — Live progress per step

Each step displays live status: queued, running, completed, failed. MotionCor2 completion updates the count. Chat and main view sync via SSE stream.

---

## Step 9 — CTF gate tripped

During CTF estimation, low CTF fit resolution halts the process. This indicates a narrow defocus search range. A fix is offered.

---

## Step 10 — Halt card, accept or edit

Auto-loop is off. BioMate suggests zero-point-five to four micrometers defocus range. Accept, edit, or dismiss. Auto-loop enables three retries.

---

## Step 11 — Gate cleared, Phase A done

Suggestion accepted. Phase A reruns CTF with new range, gate passes, completes. Phase B auto-starts. Actions log to QC audit.

---

## Step 12 — Step outputs land inline

Completed steps display file chips. Outputs appear: name, type, view, download. No need to await the entire run.

---

## Step 13 — Phase B, particle picking

Topaz scans every micrograph for particles. Each yields one coordinate file. These become input for two-dimensional classification.

---

## Step 14 — Phase C, 2D classification

Particles sort into 2D classes. Drop junk like ice, carbon edges, aggregates. Well-defined views advance to 3D.

---

## Step 15 — Phase D, 3D reconstruction

Phase D. Particles undergo ab-initio reconstruction, then homogeneous refinement. Output: 3D density map and half-map pair for gold-standard FSC resolution estimation.

---

## Step 16 — Phase E, sharpening and validation

Phase E: B-factor sharpening, FSC from half-maps, and local resolution. B-factor reads from the manifest. Result: EMDB-ready map.

---

## Step 17 — All 23 steps complete

Twenty-three steps completed. Status: completed. Reconstruction converged at 3.1 Å by GSFSC 0.143.

---

## Step 18 — Outputs downloadable

The primary footer button is now *Run again*. Locate *View Results*, *Download All*, and Findings above.

---

## Step 19 — After-run section unlocked

Each completed run adds a new *After run* block. It holds all outputs, findings, methods, citations, and QC logs.

---

## Step 20 — Wrap-up, centered

Raw movies sharpened to a 3D map in nineteen steps. Real runs take thirty to ninety minutes.

---
