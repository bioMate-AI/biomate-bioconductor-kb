# ra-cryo.en (compressed for 3:00)

## Step 1 — Welcome, centered

We'll perform a complete cryo-EM single-particle analysis using CryoSPARC. This workflow processes raw data to achieve a final reconstruction.

---

## Step 2 — Two views, one run, plan checklist

BioMate presents two synchronized run views. The left chat narrates checklist progress. The right workflow shows phases, steps, and outputs.

---

## Step 3 — Run header

The run header shows workflow name, status badge, and progress bar. Status is idle: workflow loaded, not started.

---

## Step 4 — Five phases, twenty-three steps

CryoSPARC SPA uses five phases. Phase A: motion correction, CTF. B: particle picking. C: 2D classification. D: 3D reconstruction. E: sharpening, validation.

---

## Step 5 — Inside Phase A

The active phase displays live status for every step. View other phases without disturbing the run.

---

## Step 6 — One primary action, Confirm & Run

Parameters pre-filled by BioMate from your chat message. The Confirm and run workflow button submits the job to the cloud.

---

## Step 7 — Phase A is running

Status badge shows running. Phase A motion correction is in progress on cloud GPUs.

---

## Step 9 — CTF gate tripped

CTF estimation shows low CTF fit resolution, likely from a narrow defocus search range. QC gates halt processing, then suggest a fix.

---

## Step 10 — Halt card, accept or edit

BioMate suggests a 0.5 to 4 micrometer defocus range. With auto-loop off, accept, edit, or dismiss. Enabling auto-loop automates fix and rerun three times.

---

## Step 11 — Gate cleared, Phase A done

Phase A completes its CTF rerun. Phase B identifies particles. All accepts, edits, and retries log to the QC audit report.

---

## Step 12 — Step outputs land inline

Completed steps display outputs directly on their row. These include name, type icon, view, and download options.

---

## Step 13 — Phase B, particle picking

Phase B picks particles from micrographs, outputting coordinate files for the next stage.

---

## Step 14 — Phase C, 2D classification

Phase C sorts particles into two-dimensional classes, ensuring only high-quality views advance.

---

## Step 15 — Phase D, 3D reconstruction

Phase D reconstructs the three-dimensional density, keeping the half-map pair for resolution.

---

## Step 16 — Phase E, sharpening and validation

Phase E sharpens the map and validates the overall resolution rigorously. This critical process generates the final, publication-ready density map.

---

## Step 17 — All 23 steps complete

All twenty-three steps are now complete, with status updated to *completed*. The reconstruction converged at 3.1 Å resolution by GSFSC 0.143, a high-quality outcome.

---

## Step 18 — Outputs downloadable

The footer button is now *Run again*. Scroll up to access *View Results*, *Download All*, and auto-generated Findings.

---

## Step 19 — After-run section unlocked

Every completed run creates an *After run* block. It organizes Outputs, Findings, Methods, and Parameters. Plus, Software, Citations, and the QC audit log.

---

## Step 20 — Wrap-up, centered

A complete cryo-EM run. Raw movies yield a sharpened 3D map across nineteen steps.

---
