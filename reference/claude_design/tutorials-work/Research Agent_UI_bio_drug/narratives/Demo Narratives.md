# BioMate Tutorial Narratives

Voiceover scripts for the four primary tutorials. Each beat is tagged `[mm:ss–mm:ss]` cumulative, computed at 150 wpm + 1.5 s pause. Tutorials 1–3 target ~3 min; tutorial 4 ships in two forms — a detailed ~7 min cut and a condensed ~3 min cut.

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

## 3 · Drug screen · auto-loop + comparison (`R02`)

> **Scenario context.** A 10,000-compound library is being screened for blood-brain-barrier penetrants. We follow a pilot that fails QC, BioMate's auto-loop with adjusted parameters, the Run-vs-Run comparison, and the full screen on the winning parameters. Fully automated — about 90 seconds end-to-end.

**[00:00–00:20]** · **[Step 1 — Intro, centered]**
"Drug screens often need a pilot, fail QC, and recover via auto-loop. We'll watch the whole sequence inline — pilot, fail, auto-loop, compare, full, findings — and meet the one scenario that surfaces the Run-vs-Run comparison card by default. About three minutes. The tour drives every decision for you."

**[00:21–00:30]** · **[Step 2 — Plan checklist]**
"BioMate decomposes the request into five sub-tasks: ingest, ADMET, hERG gate, Ames gate, ranking. Watch hERG and Ames — they trip mid-pilot."

**[00:31–00:48]** · **[Step 3 — Pilot prompt]**
"Ten thousand compounds is heavy. The DeepAgent suggests a five-percent pilot first — five hundred compounds, same parameters. The card carries the sampling fraction and strategy side-by-side with the full-run cost — no separate dialog. The decision lives in chat, fully auditable."

**[00:50–00:59]** · **[Step 4 — Pilot running]**
"Pilot running on 500 of 10,000. Plan items tick from circle to dot to checkmark. The pilot validates the QC gates before committing."

**[01:00–01:10]** · **[Step 5 — QC failure]**
"hERG and Ames trip. Plan items flip to amber warn pills in place. The pipeline doesn't crash — the next surface carries the decision."

**[01:12–01:21]** · **[Step 6 — QC speaker pills]**
"Two amber QC pill lines land in chat — one per gate. Pill colours match the plan, never lie, never drift across surfaces."

**[01:22–01:39]** · **[Step 7 — Pilot stopped]**
"The pilot promotion card explains what failed and shows the auto-loop's proposed fix right there — new *logp_max* and *mw_max* values, with a one-click *Apply fixes and re-pilot* action. No silent retry: the user always sees the proposed change before it runs."

**[01:41–01:51]** · **[Step 8 — LOOP speaker]**
"The LOOP speaker — purple pill — takes over. Every auto-loop decision shows here, so the audit trail stays clear. Both gates pass on the second run."

**[01:53–02:12]** · **[Step 9 — Run-vs-Run comparison]**
"Two pilots, side by side. Metrics table with a delta column. Parameter diffs tagged by origin — auto-loop versus user. A trophy badge with the recommendation, confidence, and p-value. QC outcomes coloured red on Run A and green on Run B, so the decision reads at a glance."

**[02:14–02:33]** · **[Step 10 — Ten-second auto-pick]**
"When confidence is high — p less than zero-point-zero-one here — the recommended button shows a ten-second countdown. Hover any button to pause it; click to commit. An auto-fire emits a *No response — using Run B automatically* line so nothing happens silently. Medium or low confidence: no auto-fire."

**[02:35–02:42]** · **[Step 11 — Full run]**
"Decision committed. Ten thousand compounds on the tuned parameters. Faster this time — the pilot already proved the gates."

**[02:44–02:60]** · **[Step 12 — Findings card]**
"The completion summary lands inline. Forty-seven B-B-B-penetrant candidates after all QC gates. Runtime, pass-rate, and a link to the full Report. Hover any *(why?)* anchor on earlier step lines to see the rationale that drove tool choice for that step."

**[03:01–03:11]** · **[Step 13 — Wrap-up, centered]**
"Pilot, fail, auto-loop, compare, full, findings — end to end with a clean audit trail by speaker. The Variant calling tutorial covers nested plans next."

---

## 4a · IND Report — long form, detailed (`IND-01`, ~7 min)

> **Scenario context.** A regulatory scientist opens an in-progress IND program (BM-0042 · CB1 inverse agonist · obesity). We walk the full 5-step pipeline, the live document panel, paragraph feedback, the audit overlay, and the 21 CFR Part 11 sign-and-freeze. About seven minutes end-to-end.

**[00:00–00:16]** · **[Step 1 — Welcome, centered]**
"Welcome to the BioMate IND Report. We'll walk through the five-step pipeline that builds an IND-quality §2.6 nonclinical dossier, the live document panel on the right, and the twenty-one C-F-R Part eleven sign-and-freeze at the end. About seven minutes."

**[00:17–00:31]** · **[Step 2 — Two panels, same project, centered]**
"Two panels, one project. On the left, the five-step pipeline you'll drive — setup, ADMET, P-B-P-K, leads, document. On the right, the IND itself, regenerated in place as each step completes. The tour drives both."

**[00:33–00:50]** · **[Step 3 — Project list]**
"Each program is its own project. The coloured dot on the left of each row is the status — green means signed, blue means in progress, amber means blocked on a gate. Click any project to switch — your work is preserved per project."

**[00:52–01:11]** · **[Step 4 — New project]**
"Two ways to start an IND. *New Project* here in the rail, or — much more common — from the BioMate chat. When you run an ADMET workflow there, a *Generate IND* chip drops under the result and lands you here with steps one and two already filled."

**[01:12–01:32]** · **[Step 5 — Step 1 · Project Setup]**
"Step one is the project header — the card opens as we land on it. Molecule, target, indication, sponsor, and which agencies you're filing with. Each region you add flips on its region-specific paragraphs in the document — N-M-P-A adds a G-L-P declaration, P-M-D-A adds an ethnic bridging block."

**[01:34–01:46]** · **[Step 6 — Multi-region toggle]**
"F-D-A, E-M-A, N-M-P-A, P-M-D-A — any combination. The document panel re-renders region-specific paragraphs inline; the body that applies to every region stays put. One source of truth, four agency outputs."

**[01:47–02:04]** · **[Step 7 — Step 2 · ADMET screening]**
"Step one collapses, step two opens. The ADMET screening step runs the BioMate *predict admet properties* workflow on AWS Batch. Forty-one endpoints across H-erg, D-I-L-I, AYMS, P-P-B-R, Caco-two, B-B-B, the CYPs, and P-g-p. These results feed sections two-point-six-point-one-point-three and two-point-six-point-four of the dossier."

**[02:06–02:25]** · **[Step 8 — Per-compound triage]**
"Click *View ADMET table* for the per-compound view. Every column header tooltips to its guideline citation — H-erg, for example, cites Redfern 2003 and ICH S7B, with the under-ten-micromolar liability threshold. Green check, amber tilde, red cross — the same colour key that travels through the document."

**[02:26–02:42]** · **[Step 9 — Bring in wet-lab data]**
"Computational predictions get you partial coverage. To upgrade to full, upload your wet-lab data — an NTP G-L-P report PDF or an F-D-A N-D-A review. BioMate auto-extracts measured values, and the measured values take precedence over predictions wherever they overlap."

**[02:44–02:57]** · **[Step 10 — Step 3 · PBPK qualification]**
"Step three opens. P-B-P-K qualification against a thirty-drug reference set, per E-M-A's qualification guideline. C-max and A-U-C within two-fold for at least sixty-seven percent of the reference set — that's the regulatory gate."

**[02:58–03:15]** · **[Step 11 — The gateway badge]**
"This badge is the most important pixel in the whole pipeline. If P-B-P-K qualification fails, downstream IND assembly is blocked until you re-qualify. *Re-run with new params* lets you adjust clearance, volume of distribution, or absorption and re-try without leaving the page."

**[03:17–03:28]** · **[Step 12 — Step 4 · Lead selection]**
"Step four opens. Lead ranking with a Gaussian Process model, E-H-V-I acquisition, Morgan fingerprints — every candidate scored on a five-axis surrogate: H-erg, D-I-L-I, AYMS, potency, and applicability domain."

**[03:30–03:45]** · **[Step 13 — Read the ranking]**
"Filled circles encode potency — four out of five filled means strong. *O-O-D* means out of applicability domain — the candidate is still ranked, but flagged in section two-point-six-point-one-point-five with a limitation statement, so reviewers see the caveat."

**[03:46–03:58]** · **[Step 14 — Step 5 · IND document]**
"Step five assembles the dossier — section two-point-six-point-one-point-one through two-point-six-point-six — once steps one through four are complete. The right-hand panel renders the document live as each pipeline step finishes."

**[03:60–04:18]** · **[Step 15 — Section coverage]**
"Section coverage at a glance, inside step five. Filled circle is full — computational plus measured, ready for submission. Half circle is partial — computational only, flagged for wet-lab enrichment. Empty is not yet generated. Sections two-point-six-point-five and two-point-six-point-six always need G-L-P data to reach full."

**[04:20–04:33]** · **[Step 16 — Live document viewer]**
"The document panel is always visible on the right. As each pipeline step completes, the matching section populates in place — no page reload, no separate preview, no copy-paste from a temporary doc."

**[04:34–04:49]** · **[Step 17 — Jump to any section]**
"The tab strip jumps you to any section directly. The dot next to each tab encodes coverage at a glance — green for full, amber for partial — so you can spot the gaps without scrolling."

**[04:50–05:03]** · **[Step 18 — Per-region view]**
"Switch the rendered region right here. N-M-P-A adds the G-L-P declaration paragraph; P-M-D-A adds the ethnic bridging assumption table. The *all regions combined* view is what gets shipped to each agency."

**[05:04–05:23]** · **[Step 19 — Edit any paragraph]**
"Every paragraph is editable. Change one, and a small *edited — saved for model improvement* note appears beside it. Behind the scenes that edit becomes a training pair — your version as chosen, ours as rejected. That's how the BioMate regulatory model improves with every customer's expertise."

**[05:24–05:41]** · **[Step 20 — Suggest a citation]**
"See the plus icon at the end of a paragraph? Click it to suggest a missing guideline — especially useful for N-M-P-A or C-D-E technical guidelines we haven't indexed yet. Approved suggestions roll into the shared corpus on the next refresh."

**[05:42–06:00]** · **[Step 21 — Regulatory audit]**
"The audit bar at the top of section two-point-six is the compliance lens. Zero critical, zero major, two minor, four info — that means the document is signable. Critical blocks signing outright. Major shows an amber warning but lets the regulatory scientist proceed on judgment."

**[06:02–06:19]** · **[Step 22 — Each finding has a fix]**
"The audit drawer opens. Every finding shows what triggered it, the recommended fix, and a *jump to section* link. *Dismiss* with a reason — for example, *not applicable to this topical product* — and that reason refines the checker rule for every customer, automatically."

**[06:21–06:33]** · **[Step 23 — Sign & freeze]**
"Audit drawer closes; the sign button highlights. Twenty-one C-F-R Part eleven, section eleven-point-two-hundred. Reviewer credentials, a six-digit T-O-T-P, and the meaning-of-signature statement are permanently recorded inside the frozen document."

**[06:34–06:47]** · **[Step 24 — Immutable versions]**
"Signed versions are frozen by SHA-two-five-six. Creating version three supersedes version two — but the version-two signature record stays in the audit trail forever. You can always render any prior version, byte-for-byte."

**[06:48–07:10]** · **[Step 25 — Wrap-up, centered]**
"That's the IND Report end to end. Five-step pipeline, live document, audit overlay, signature freeze. Three things worth trying on your own — open the sign overlay to see the full T-O-T-P flow, edit a paragraph and watch the training-pair note appear, and dismiss an audit finding to close the feedback loop. Happy filing."

---

## 4b · IND Report — short form, condensed (`IND-01-short`, ~3 min)

> **Scenario context.** Same product, same scenario as 4a — but condensed to roughly three minutes. Drops the deep technical citations (Redfern, ICH S7B, OSP range), tightens each beat, and merges a few inner-detail steps into their parent step. Use this cut for top-of-funnel demos; use 4a for regulatory-scientist deep dives.

**[00:00–00:16]** · **[Step 1 — Welcome, centered]**
"Welcome to the BioMate IND Report. A five-step pipeline that builds the §2.6 nonclinical dossier for an Investigational New Drug application, with a live document viewer on the right and twenty-one C-F-R Part eleven sign-and-freeze at the end. About three minutes."

**[00:18–00:30]** · **[Step 2 — Two panels, centered]**
"Two panels, one project. The five-step pipeline on the left — setup, ADMET, P-B-P-K, leads, document. The IND itself on the right, regenerated in place as each step completes."

**[00:31–00:46]** · **[Step 3 — Project list]**
"Each program is its own project. The coloured dot on each row is the status — green signed, blue in progress, amber blocked on a gate. Click any project to switch; your work is preserved per project."

**[00:47–01:01]** · **[Step 4 — New project]**
"Two ways to start an IND. *New Project* here in the rail, or — more commonly — hit *Generate IND* on an ADMET result in the BioMate chat. Steps one and two land here pre-filled."

**[01:03–01:13]** · **[Step 5 — Step 1 · Project Setup]**
"Step one. Molecule, target, indication, sponsor, and the agencies you're filing with — F-D-A, E-M-A, N-M-P-A, P-M-D-A in any combination. Region-specific paragraphs flip on automatically."

**[01:14–01:29]** · **[Step 6 — Step 2 · ADMET]**
"Step two. ADMET on AWS Batch — forty-one endpoints including H-erg, D-I-L-I, AYMS, Caco-two, B-B-B, the CYPs, and P-g-p. These feed sections two-point-six-point-one-point-three and two-point-six-point-four. Drop in wet-lab data to upgrade partial sections to full coverage."

**[01:30–01:43]** · **[Step 7 — Step 3 · PBPK qualification]**
"Step three. P-B-P-K qualification against a thirty-drug reference set. C-max and A-U-C within two-fold for at least sixty-seven percent — that's the E-M-A gate. Fail blocks IND assembly until you re-qualify."

**[01:44–01:53]** · **[Step 8 — Step 4 · Lead selection]**
"Step four. Gaussian Process, E-H-V-I, Morgan fingerprints. Every candidate scored on five axes. *O-O-D* candidates are ranked but flagged with a limitation statement."

**[01:55–02:06]** · **[Step 9 — Step 5 · Document]**
"Step five. The dossier assembles in the right panel — section two-point-six-point-one-point-one through two-point-six-point-six. Coverage dots show at a glance: filled full, half partial, empty not yet generated."

**[02:08–02:16]** · **[Step 10 — Live document viewer]**
"The document panel is always live. Tab strip jumps you to any section; region selector renders per agency or all combined."

**[02:17–02:27]** · **[Step 11 — Edits become training data]**
"Every paragraph is editable. Each edit becomes a training pair — yours chosen, ours rejected — so the regulatory model improves with every customer."

**[02:29–02:48]** · **[Step 12 — Regulatory audit]**
"The audit bar at the top of section two-point-six is the compliance lens. Zero critical, zero major, two minor, four info — that's signable. Critical blocks signing; major shows an amber warning you can override on judgment. Every finding has a recommended fix and a *jump to section* link."

**[02:50–03:02]** · **[Step 13 — Sign & freeze]**
"Twenty-one C-F-R Part eleven sign-and-freeze. Reviewer credentials, a six-digit T-O-T-P, and the meaning-of-signature statement are baked into the frozen document. Signed versions are SHA-two-five-six immutable, kept in the audit trail forever."

**[03:04–03:22]** · **[Step 14 — Wrap-up, centered]**
"That's the IND Report end to end. Five-step pipeline, live document, audit overlay, signature freeze. Try the sign overlay to walk through the full T-O-T-P flow, edit a paragraph to see the training-pair note, and dismiss a finding to close the feedback loop. Happy filing."

---

## Recording notes

- **Timings.** Each beat is tagged `[mm:ss–mm:ss]` cumulative. Computed at **150 wpm + 1.5 s pause** between beats, 5 s floor per beat. Target budgets: tutorials 1–3 ≈ 3 min, tutorial 4a ≈ 7 min, tutorial 4b ≈ 3 min. Treat as a target, not a metronome — leave room to breathe.
- **Pace.** ~140–160 words/minute spoken English.
- **Tone.** Calm presenter; scientist talking to a scientist. Not chatty, not stiff.
- **Diction for technical terms.**
  - "CryoSPARC" → cry-o-SPARK
  - "FSC" → spell each letter: F-S-C
  - "GSFSC" → "gold-standard F-S-C" (read the abbreviation as words on first mention)
  - "EMPIAR-10025" → "EM-PIE-AR ten thousand twenty-five"
  - "IMRaD" → "IM-rad" (one word)
  - "DOCX / MD / LaTeX" → "DOCKS / MARK-DOWN / LAY-TEK"
  - "hERG" → "H-erg" (H spelled then ‘erg’)
  - "Ames" → "AYMS"
  - "BBB" → spell letters
  - "logBB" → "log-B-B"
  - "p < 0.01" → "p less than zero-point-zero-one"
  - "21 CFR Part 11" → "twenty-one C-F-R part eleven"
  - "§2.6.1.3" / "§2.6.4" → "section two-point-six-point-one-point-three" / "section two-point-six-point-four" (read § as "section")
  - "PBPK" → "P-B-P-K" (spell)
  - "ADMET" → "AD-met" (one word)
  - "FDA / EMA / NMPA / PMDA / CDE" → spell letters
  - "DILI" → "D-I-L-I" (spell)
  - "P-gp" → "P-g-p"
  - "Caco-2" → "Caco-two"
  - "Cmax / AUC" → "C-max" / "A-U-C"
  - "OOD" → "O-O-D" (spell on first mention; "out of applicability domain" on expansion)
  - "EHVI" → "E-H-V-I"
  - "TOTP" → "T-O-T-P"
  - "SHA-256" → "SHA-two-five-six"
  - "BM-0042" → "B-M zero-zero-four-two"
- **Sync.** The drug screen tutorial auto-advances; the cryo and output tutorials advance on click. For drug screen, match narration to the tour's autoAdvance pacing (≈7s/step). For cryo and output, the operator clicks Next on each beat — narration can breathe a half-second between steps.
- **Cards.** When the screen shows a chat card or modal popping in, leave a beat (~0.5s) before the narration starts. The card's entry animation reads better with audio that follows it, not pre-empts it.
