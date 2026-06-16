# BioMate — CryoSPARC Tutorial Narration

Voiceover scripts for the cryo-EM tutorials. Each beat is tagged `[mm:ss–mm:ss]` cumulative, computed at 150 wpm + 1.5 s pause. Both cuts target ~3 min.

---

## 1 · CryoSPARC SPA · 3-minute deep dive (`09d`)

> **Scenario context.** A scientist asks BioMate to run single-particle reconstruction on EMPIAR-10025. We follow the entire pipeline from raw movies to a sharpened 3D map — five phases, twenty-three processes.

**[00:00–00:07]** · **[Step 1 — Welcome, centered]**
"We're going to run a complete cryo-EM single-particle analysis. No CryoSPARC experience needed — BioMate handles the parameters."

**[00:09–00:17]** · **[Step 2 — Two views, one run]**
"Two views, same run. Chat on the left narrates progress; the workflow panel on the right shows phases, steps, parameters, outputs."

**[00:19–00:25]** · **[Step 3 — Run header]**
"Run header — workflow name, status badge, live progress bar. Status *idle*: loaded but not started."

**[00:27–00:36]** · **[Step 4 — Five phases]**
"Five phases. A: motion plus CTF. B: picking. C: 2D classification. D: 3D reconstruction. E: sharpening and validation. Only the active phase auto-expands."

**[00:37–00:44]** · **[Step 5 — Inside Phase A]**
"Phase A runs MotionCor2 for frame alignment and CTFFIND4 for defocus. Every step shows a live status chip."

**[00:46–00:54]** · **[Step 6 — Confirm & Run]**
"Parameters were pre-filled from your chat message. *Confirm and run* submits to AWS Batch. The footer always shows one primary button."

**[00:56–01:01]** · **[Step 7 — Phase A is running]**
"We're off. Status is *running*. A small dataset takes three to six minutes."

**[01:03–01:10]** · **[Step 8 — Live progress per step]**
"Each step ticks: queued, running, completed, failed. Chat and panel read the same SSE stream — always in sync."

**[01:12–01:20]** · **[Step 9 — CTF gate tripped]**
"CTF fit resolution is below threshold — likely a too-narrow defocus search range. QC gates halt before producing a bad map."

**[01:22–01:34]** · **[Step 10 — Halt card]**
"Auto-loop is off, so the halt card waits. BioMate suggests a wider defocus range — accept, edit, or dismiss. Turn auto-loop on to apply and rerun without asking, capped at three retries."

**[01:36–01:44]** · **[Step 11 — Gate cleared]**
"Accepted. CTF reruns, the gate passes, Phase A completes, Phase B starts. Every retry is logged in the QC audit."

**[01:45–01:53]** · **[Step 12 — Outputs land inline]**
"File chips appear on each completed step row — view or download right there. No waiting for the whole run."

**[01:55–02:02]** · **[Step 13 — Phase B, picking]**
"Phase B. Topaz — a neural-network picker — scans every micrograph. One coordinate file per micrograph, into 2D."

**[02:04–02:10]** · **[Step 14 — Phase C, 2D]**
"Phase C. 2D classes. Junk classes — ice, carbon, aggregates — are dropped. Only clean views advance."

**[02:12–02:18]** · **[Step 15 — Phase D, 3D]**
"Phase D. Ab-initio then homogeneous refinement. Output: an unsharpened map plus half-maps for gold-standard FSC."

**[02:19–02:27]** · **[Step 16 — Phase E, sharpening]**
"Phase E. B-factor sharpening, FSC resolution, local resolution. The B-factor is read straight from the manifest — never inferred."

**[02:28–02:34]** · **[Step 17 — All 23 steps complete]**
"All done. Status *completed*. Converged at 3.1 ångström by GSFSC 0.143 — publication territory."

**[02:36–02:42]** · **[Step 18 — Outputs downloadable]**
"Footer primary is now *Run again*. Scroll up for View Results, Download All, and the auto-generated Findings."

**[02:44–02:51]** · **[Step 19 — After-run section unlocked]**
"Every completed run drops an *After run* block — outputs, findings, methods, parameters, software, citations, QC audit. Separate tutorial."

**[02:53–03:02]** · **[Step 20 — Wrap-up, centered]**
"Raw movies to a sharpened 3D map in nineteen steps. Real runs take thirty to ninety minutes — we fast-forwarded the cloud time."

---

## 2 · After-run report walkthrough (`09f`)

> **Scenario context.** Picks up immediately after a completed cryo-EM run. We tour every tab of the After-run report end to end, with one inline preview detour.

**[00:00–00:18]** · **[Step 1 — Intro, centered]**
"Your run just finished. The *After run* block has seven tabs covering everything BioMate produced for this CryoSPARC job — findings, raw outputs, methods, parameters, software, citations, and the QC audit. We'll walk each one in order, with one inline preview detour along the way."

**[00:20–00:31]** · **[Step 2 — After-run header]**
"Every completed run leaves an *After run* section. *Download report* on the right bundles every tab below into one DOCX, Markdown, or LaTeX document — manuscript-ready in a click."

**[00:33–00:49]** · **[Step 3 — Seven tabs]**
"Seven tabs cover the whole story. Findings, Outputs, Methods, Parameters, Software, Citations, and the QC audit. The order matches the natural read order — narrative first, raw artifacts next, then reproducibility, ending with audit. Content switches automatically as we move through them."

**[00:51–01:11]** · **[Step 4 — Findings tab]**
"Findings opens with the headline metric — three-point-two-one ångström resolution — plus two or three bullets capturing what to look at, and a numeric table beneath. Every number is read from the run manifest, not generated. If a finding has no citation, BioMate tags it as author judgment so reviewers know."

**[01:13–01:32]** · **[Step 5 — Outputs tab]**
"One row per file, grouped by phase and step. *View* opens an inline preview right in the panel; *download* grabs the single file. The *Download all* button bundles every output across all five phases as a single ZIP — same files you'd pull individually, one click instead of dozens."

**[01:34–01:42]** · **[Step 6 — Outputs on the step too]**
"You don't have to wait for the report. Each completed step shows its output chips inline the moment it finishes."

**[01:43–01:53]** · **[Step 7 — Inline preview]**
"*Aligned sums* opens in a preview modal. Tables get a grid; plots get plotted; 3D maps get a viewer. BioMate picks the renderer."

**[01:54–02:13]** · **[Step 8 — Methods tab]**
"The Methods tab. IMRaD prose you can drop straight into a manuscript — tool names, versions, exact parameters, written so peers can replicate the run. Italics flag values that were inferred from defaults versus values read directly from the manifest, so you know what to double-check."

**[02:14–02:30]** · **[Step 9 — Parameters tab]**
"The Parameters tab. Phase, step, parameter, value — every knob the run touched, in one sortable table. Defaults are flagged separately from user overrides and auto-loop adjustments, so reviewers can see exactly where each value came from. Supplementary-file ready."

**[02:31–02:37]** · **[Step 10 — Software tab]**
"Every tool with its exact version. Together with Parameters, this is the reproducibility baseline."

**[02:38–02:46]** · **[Step 11 — Citations tab]**
"Pre-formatted references for tools and methods cited in the prose. PMIDs click through to PubMed. Pre-bundled in the Download report."

**[02:48–03:05]** · **[Step 12 — QC audit tab]**
"The QC audit tab — the compliance lens. Every QC gate that fired with timestamp, threshold, observed value, result, and the action taken. Chain-of-custody included, with the operator e-signature attached. Twenty-one C-F-R Part eleven friendly — what regulators and reviewers want to see."

**[03:06–03:24]** · **[Step 13 — Wrap-up, centered]**
"That's the After-run report. Seven tabs, one manifest, no copy-paste. The *Download report* link wraps everything into a DOCX for Word, Markdown for Notion or GitHub, or LaTeX for journal templates. Share the run URL and a collaborator gets the same view, read-only."

---

## Recording notes

- **Timings.** Each beat is tagged `[mm:ss–mm:ss]` cumulative. Computed at **150 wpm + 1.5 s pause** between beats, 5 s floor per beat. Target ≈ 3 min each. Treat as a target, not a metronome.
- **Pace.** ~140–160 words/minute spoken English.
- **Tone.** Calm presenter; scientist talking to a scientist. Not chatty, not stiff.
- **Diction for technical terms.**
  - "CryoSPARC" → cry-o-SPARK
  - "FSC" → spell each letter: F-S-C
  - "GSFSC" → "gold-standard F-S-C" (read the abbreviation as words on first mention)
  - "EMPIAR-10025" → "EM-PIE-AR ten thousand twenty-five"
  - "IMRaD" → "IM-rad" (one word)
  - "DOCX / MD / LaTeX" → "DOCKS / MARK-DOWN / LAY-TEK"
  - "21 CFR Part 11" → "twenty-one C-F-R part eleven"
- **Sync.** The cryo and after-run tutorials advance on click — the operator clicks Next on each beat, so narration can breathe a half-second between steps.
- **Cards.** When the screen shows a chat card or modal popping in, leave a beat (~0.5s) before the narration starts. The card's entry animation reads better with audio that follows it, not pre-empts it.

---

## How to run the tutorial

Open `Cryo Tutorial (Research Agent UI)/Research Agent UI.html` in a browser. The cryo deep-dive tour (`09d`) and the after-run report walkthrough (`09f`) are the two cryo-EM guided tours. Requires an internet connection (loads React + fonts from CDN).
