# ra-cryo narration (EN)

## Step 1 — Welcome, centered

Hi. We're going to run a complete cryo-EM single-particle analysis together. No prior CryoSPARC experience needed — BioMate handles the parameters; just follow along.

---

## Step 2 — Two views, one run, plan checklist

BioMate gives you two views of the same run. On the left, the chat narrates progress through a sticky plan checklist and speaker-pilled lines. On the right, the workflow panel is the technical view — phases, steps, parameters, outputs. They stay in sync.

---

## Step 3 — Run header

This is the run header. Workflow name, status badge, and a live progress bar. Right now the status is *idle* — the workflow is loaded but nothing has started yet.

---

## Step 4 — Five phases, twenty-three steps

CryoSPARC SPA is grouped into five phases. Motion correction and CTF in Phase A. Particle picking in B. Two-dimensional classification in C. Three-dimensional reconstruction in D. And sharpening plus validation in E. Only the active phase auto-expands — the rest collapse to a chip so the panel stays scannable.

---

## Step 5 — Inside Phase A

Inside the active phase you get the live status of every step. Phase A runs *MotionCor2* for frame alignment and *CTFFIND4* for defocus estimation. You can peek inside any other phase any time without disturbing the run.

---

## Step 6 — One primary action, Confirm & Run

Parameters were pre-filled by BioMate from your chat message. When you're ready, the *Confirm and run workflow* button submits the job to the cloud. The footer always shows one primary button — never a wall of choices.

---

## Step 7 — Phase A is running

We're off. The status badge has flipped to *running* and the progress bar is moving. Phase A motion correction is in progress on Batch GPUs. A small dataset typically takes three to six minutes.

---

## Step 8 — Live progress per step

Inside Phase A, each step shows a live status chip — queued, running, completed, or failed. As MotionCor2 finishes a movie, the count ticks up. The chat side reads the same SSE stream, so both views stay in sync.

---

## Step 9 — CTF gate tripped

Halfway through CTF estimation, BioMate notices the CTF fit resolution is below threshold — probably a too-narrow defocus search range. QC gates are guardrails. Instead of producing a low-quality map, BioMate halts and surfaces a fix.

---

## Step 10 — Halt card, accept or edit

Auto-loop is off by default, so the halt card waits for you. BioMate suggests a wider defocus range — zero-point-five to four micrometers. You can *Accept* the suggestion, *Edit* the values yourself, or *Dismiss* and proceed as is. Turning auto-loop on for this phase lets BioMate apply the fix and rerun without asking — capped at three retries.

---

## Step 11 — Gate cleared, Phase A done

You accepted the suggestion. Phase A reruns CTF with the new range, the gate passes, and the phase is marked completed. Phase B kicks off automatically. Every accept, edit, and retry is logged in the QC audit report.

---

## Step 12 — Step outputs land inline

Notice the small file chips on each completed step row? As soon as a step finishes, its outputs appear right there — name, type icon, *view*, *download*. You don't have to wait for the whole run.

---

## Step 13 — Phase B, particle picking

Phase B. *Topaz* — a neural-network picker — scans every micrograph for particles. The output is one coordinate file per micrograph; these become the input particles for two-dimensional classification.

---

## Step 14 — Phase C, 2D classification

Phase C. Particles are sorted into two-dimensional classes. Junk classes — ice, carbon edges, aggregates — are dropped. Only well-defined views advance to 3D.

---

## Step 15 — Phase D, 3D reconstruction

Phase D. Cleaned particles go into ab-initio reconstruction, followed by homogeneous refinement. The output is an unsharpened 3D density map plus a half-map pair for resolution estimation. The half-maps are kept separate on purpose — they're the basis for the gold-standard FSC.

---

## Step 16 — Phase E, sharpening and validation

Phase E. B-factor sharpening, FSC resolution from the half-maps, and local resolution mapping. The B-factor value is read straight from the manifest — never inferred. The result is the publication-ready map you can deposit at EMDB.

---

## Step 17 — All 23 steps complete

All twenty-three steps complete. Status flipped to *completed*. The reconstruction converged at three-point-one ångström by GSFSC zero-point-one-four-three — well inside publication-quality territory.

---

## Step 18 — Outputs downloadable

The footer's primary button has changed to *Run again*. Scroll up to find *View Results*, *Download All*, and the auto-generated Findings.

---

## Step 19 — After-run section unlocked

Every completed run drops a fresh *After run* block at the bottom of the panel. Outputs, Findings, Methods, Parameters, Software, Citations, and the QC audit log — all in one place. There's a dedicated tutorial just for this section.

---

## Step 20 — Wrap-up, centered

That's a full cryo-EM run — raw movies to a sharpened 3D map in nineteen steps. Real runs take thirty to ninety minutes; this tutorial fast-forwarded the cloud time so you could see every milestone.

---
