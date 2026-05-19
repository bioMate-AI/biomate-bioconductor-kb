# BioMate Tutorial Narratives

Voiceover scripts for the three primary tutorials in the Research Agent UI demo. Each section is keyed to the on-screen tour callouts; pacing assumes ~5–8 seconds per step. Read at a calm, presenter pace.

---

## 1 · CryoSPARC SPA · 3-minute deep dive (`09d`)

> **Scenario context.** A scientist asks BioMate to run single-particle reconstruction on EMPIAR-10025. We follow the entire pipeline from raw movies to a sharpened 3D map — five phases, twenty-three processes.

**[Step 1 — Welcome, centered]**
"Hi. We're going to run a complete cryo-EM single-particle analysis together. No prior CryoSPARC experience needed — BioMate handles the parameters; just follow along."

**[Step 2 — Two views, one run, plan checklist]**
"BioMate gives you two views of the same run. On the left, the chat narrates progress through a sticky plan checklist and speaker-pilled lines. On the right, the workflow panel is the technical view — phases, steps, parameters, outputs. They stay in sync."

**[Step 3 — Run header]**
"This is the run header. Workflow name, status badge, and a live progress bar. Right now the status is *idle* — the workflow is loaded but nothing has started yet."

**[Step 4 — Five phases, twenty-three steps]**
"CryoSPARC SPA is grouped into five phases. Motion correction and CTF in Phase A. Particle picking in B. Two-dimensional classification in C. Three-dimensional reconstruction in D. And sharpening plus validation in E. Only the active phase auto-expands — the rest collapse to a chip so the panel stays scannable."

**[Step 5 — Inside Phase A]**
"Inside the active phase you get the live status of every step. Phase A runs *MotionCor2* for frame alignment and *CTFFIND4* for defocus estimation. You can peek inside any other phase any time without disturbing the run."

**[Step 6 — One primary action, Confirm & Run]** *(scrolls to footer)*
"Parameters were pre-filled by BioMate from your chat message. When you're ready, the *Confirm and run workflow* button submits the job to AWS Batch. The footer always shows one primary button — never a wall of choices."

**[Step 7 — Phase A is running]** *(scrolls back to header)*
"We're off. The status badge has flipped to *running* and the progress bar is moving. Phase A motion correction is in progress on Batch GPUs. "

**[Step 8 — Live progress per step]**
"Inside Phase A, each step shows a live status chip — queued, running, completed, or failed. As MotionCor2 finishes a movie, the count ticks up. The chat side reads the same SSE stream, so both views stay in sync."

**[Step 9 — CTF gate tripped]**
"Halfway through CTF estimation, BioMate notices the CTF fit resolution is below threshold — probably a too-narrow defocus search range. QC gates are guardrails. Instead of producing a low-quality map, BioMate halts and surfaces a fix."

**[Step 10 — Halt card, accept or edit]**
"Auto-loop is off by default, so the halt card waits for you. BioMate suggests a wider defocus range — zero-point-five to four micrometers. You can *Accept* the suggestion, *Edit* the values yourself, or *Dismiss* and proceed as is. Turning auto-loop on for this phase lets BioMate apply the fix and rerun without asking — capped at three retries."

**[Step 11 — Gate cleared, Phase A done]**
"You accepted the suggestion. Phase A reruns CTF with the new range, the gate passes, and the phase is marked completed. Phase B kicks off automatically. Every accept, edit, and retry is logged in the QC audit report."

**[Step 12 — Step outputs land inline]**
"Notice the small file chips on each completed step row? As soon as a step finishes, its outputs appear right there — name, type icon, *view*, *download*. You don't have to wait for the whole run."

**[Step 13 — Phase B, particle picking]** *(scrolls to current open phase)*
"Phase B. *Topaz* — a neural-network picker — scans every micrograph for particles. The output is one coordinate file per micrograph; these become the input particles for two-dimensional classification."

**[Step 14 — Phase C, 2D classification]**
"Phase C. Particles are sorted into two-dimensional classes. Junk classes — ice, carbon edges, aggregates — are dropped. Only well-defined views advance to 3D."

**[Step 15 — Phase D, 3D reconstruction]**
"Phase D. Cleaned particles go into ab-initio reconstruction, followed by homogeneous refinement. The output is an unsharpened 3D density map plus a half-map pair for resolution estimation. The half-maps are kept separate on purpose — they're the basis for the gold-standard FSC."

**[Step 16 — Phase E, sharpening and validation]**
"Phase E. B-factor sharpening, FSC resolution from the half-maps, and local resolution mapping. The B-factor value is read straight from the manifest — never inferred. The result is the publication-ready map you can deposit at EMDB."

**[Step 17 — All 23 steps complete]** *(scrolls back to header)*
"All twenty-three steps complete. Status flipped to *completed*. The reconstruction converged at three-point-one ångström by GSFSC zero-point-one-four-three — well inside publication-quality territory."

**[Step 18 — Outputs downloadable]** *(scrolls to footer)*
"The footer's primary button has changed to *Run again*. Scroll up to find *View Results*, *Download All*, and the auto-generated Findings."

**[Step 19 — After-run section unlocked]** *(scrolls to After-run header)*
"Every completed run drops a fresh *After run* block at the bottom of the panel. Outputs, Findings, Methods, Parameters, Software, Citations, and the QC audit log — all in one place. There's a dedicated tutorial just for this section."

**[Step 20 — Wrap-up, centered]**
"That's a full cryo-EM run — raw movies to a sharpened 3D map in nineteen steps. "

---

## 2 · After-run report walkthrough (`09f`)

> **Scenario context.** Picks up immediately after a completed cryo-EM run. We tour every tab of the After-run report end to end, with one inline preview detour.

**[Step 1 — Intro, centered]**
"Your run just finished. The *After run* block at the bottom of the panel has seven tabs covering everything BioMate produced. We'll walk each one in order — content switches automatically."

**[Step 2 — After run header + Download report]** *(scrolls panel down to After-run)*
"Every completed run leaves an *After run* section. The *Download report* link on the right bundles every tab below into one structured document — DOCX, Markdown, or LaTeX — manuscript-ready in a single click."

**[Step 3 — Seven tabs overview]**
"Seven tabs cover the whole story. Findings. Outputs. Methods. Parameters. Software. Citations. QC audit. The order matches the natural read order — narrative first, raw artifacts next, then methods and reproducibility, ending with audit."

**[Step 4 — Findings tab]** *(setup clicks Findings)*
"The Findings tab opens with the headline metric — three-point-two-one ångström resolution — plus two or three bullets capturing what to look at, and a numeric table. Every number is read from the run manifest, not generated. If a finding has no citation, BioMate tags it as author judgment."

**[Step 5 — Outputs tab]** *(setup clicks Outputs)*
"The Outputs tab gives you one row per file, grouped by phase and step. *View* opens an inline preview; *download* grabs the single file. The *Download all* button at the top of this tab bundles everything as a ZIP."

**[Step 6 — Outputs land on the step too]** *(scrolls panel back up to phase list)*
"You don't have to wait for the report to grab a file. Look at any completed step row in the panel above — output chips appear inline the moment the step finishes. Same view, same download, just per-step."

**[Step 7 — aligned_sums inline preview]** *(opens preview modal)*
"Let's open one. *Aligned sums* — MotionCor2's motion-corrected micrograph stack — opens right there in a preview modal. Tables get a sortable grid; plots get plotted; 3D maps get a viewer. BioMate picks the right renderer for the file type."

**[Step 8 — Methods tab]** *(closes preview, scrolls down, clicks Methods)*
"The Methods tab. Paragraph-form IMRaD prose you can drop straight into a manuscript. Tool names, versions, exact parameters — written so peers can replicate the run. Italics flag values that were inferred versus read from the manifest."

**[Step 9 — Parameters tab]** *(setup clicks Parameters)*
"The Parameters tab. Phase, step, parameter, value — every knob the run touched, in one table. Defaults are flagged separately from user overrides and auto-loop adjustments. Reviewers want this as a supplementary file."

**[Step 10 — Software tab]** *(setup clicks Software)*
"The Software tab. Every tool that touched the run with its exact version — orchestrator, container runtime, scientific packages. Together with Parameters, this is the reproducibility baseline. Match these and you'll get the same outputs."

**[Step 11 — Citations tab]** *(setup clicks Citations)*
"The Citations tab. Pre-formatted reference list for the tools and methods cited in the Methods prose. PMIDs are click-through to PubMed. Citations and Methods come pre-bundled in the Download report export."

**[Step 12 — QC audit tab]** *(setup clicks QC audit)*
"The QC audit tab — the compliance lens. Every QC gate that fired, with timestamp, threshold, observed value, result, and action. Chain-of-custody included, with the operator e-signature. Twenty-one CFR Part 11 friendly — what regulators and reviewers want to see."

**[Step 13 — Wrap-up, centered]** *(resets to Findings)*
"That's the After-run report. Every tab is generated from the same run manifest. One *Download report* link wraps all seven tabs into a structured document — DOCX for Word, Markdown for Notion or GitHub, LaTeX for journal templates. Share the run URL and a collaborator gets the same view, read-only."

---

## 3 · Drug screen · auto-loop + comparison (`R02`)

> **Scenario context.** A 10,000-compound library is being screened for blood-brain-barrier penetrants. We follow a pilot that fails QC, BioMate's auto-loop with adjusted parameters, the Run-vs-Run comparison, and the full screen on the winning parameters. Fully automated — about 90 seconds end-to-end.

**[Step 1 — Intro, centered]**
"Drug screens often need a pilot, fail QC, and recover via auto-loop. We'll watch the whole sequence inline — and meet the one scenario that surfaces the Run-vs-Run comparison card by default. The tour drives every decision for you."

**[Step 2 — Plan checklist, five sub-tasks]**
"BioMate decomposes the request into five sub-tasks. Ingest. ADMET prediction. hERG gate. Ames gate. Ranking. Each ticks in place. Watch the hERG and Ames rows — they'll trip mid-pilot."

**[Step 3 — Pilot prompt]**
"Ten thousand compounds is heavy. The DeepAgent suggests a five-percent pilot first. The card carries the sampling fraction and strategy side-by-side with the full-run cost — no separate dialog. The decision lives in chat."

**[Step 4 — Pilot running]**
"The pilot is now running on 500 of 10,000 compounds. Plan items tick from circle to dot to checkmark as the engine advances. A small pilot validates the QC gates before committing the full run."

**[Step 5 — QC failure mid-pilot]**
"hERG and Ames trip. The plan items flip to amber warn pills in place. The pipeline doesn't crash — the next surface carries the decision. QC gates evaluate per phase. A trip means the auto-loop will propose fixes."

**[Step 6 — QC speaker pills]**
"Two QC pill lines land in chat — one for hERG, one for Ames. The pills are amber, color-coded to match the warn pills on the plan. Pill colors never lie — they're stable across the plan, the chat, and the Tweaks panel."

**[Step 7 — Pilot stopped · QC gates triggered]**
"The pilot promotion card explains what failed and shows the auto-loop's suggested fix right there — new *logp_max* and *mw_max* values, with a one-click *Apply fixes and re-pilot* action. No silent retry — the user always sees the proposed change before it runs."

**[Step 8 — Auto-loop · LOOP speaker]**
"We just applied the fix. The LOOP speaker — purple pill — takes over. Every line under LOOP is an auto-loop decision, so the audit trail stays clear. QC re-evaluates, and both gates pass on the second run."

**[Step 9 — Run-vs-Run comparison card]**
"Two pilots done. The comparison card lays them side by side. Metrics table with a delta column. Parameter diffs tagged by origin — auto-loop versus user. A trophy badge with the recommendation, confidence, and p-value. QC outcomes are colored red on Run A, green on Run B, so the decision reads at a glance."

**[Step 10 — Auto-pick]**
"When confidence is high — p less than zero-point-zero-one here — the recommended button shows a short countdown. Hover any button to pause it; click to commit. An auto-fire emits a *No response — using Run B automatically* line so nothing happens silently. Medium or low confidence: no auto-fire. The card sits until the user picks."

**[Step 11 — Full run on Run B params]**
"Decision committed. The full screen now runs on ten thousand compounds using the auto-loop's tuned parameters. Plan items tick again — faster this time, since the pilot already proved the gates."

**[Step 12 — Findings card · 47 candidates]**
"The completion summary lands inline. Forty-seven BBB-penetrant candidates after all QC gates. Runtime, QC pass-rate, and a link to the full Report — Findings, Outputs, Methods, Parameters, Software, Citations. Hover any *(why?)* anchor on earlier step lines to see the rationale that drove tool choice."

**[Step 13 — Wrap-up, centered]**
"End-to-end auto-loop, done. You just watched pilot, fail, auto-loop, compare, full, findings. Three decision cards, one comparison card, and a clean audit trail by speaker. The Variant calling tutorial covers nested plans and step retry — try it next."

---

## 4 · IND Report · pipeline → document → sign (`IND-01`)

> **Scenario context.** A regulatory scientist opens an in-progress IND program (BM-0042 · CB1 inverse agonist · obesity). We walk the full 5-step pipeline, the live document panel, paragraph feedback, the audit overlay, and the 21 CFR Part 11 sign-and-freeze. About two minutes end-to-end.

**[Step 1 — Welcome, centered]**
"Welcome to the BioMate IND Report. We'll walk through the five-step pipeline that builds an IND-quality §2.6 nonclinical dossier, the live document panel on the right, and the twenty-one C-F-R Part eleven sign-and-freeze at the end. "

**[Step 2 — Project list]**
"Each program is its own project. The coloured dot on the left of each row is the status — green means signed, blue means in progress, amber means blocked on a gate. Click any project to switch — your work is preserved per project."

**[Step 3 — New project]**
"Two ways to start an IND. *New Project* here in the rail, or — much more common — from the BioMate chat. When you run an ADMET workflow there, a *Generate IND* chip drops under the result and lands you here with steps one and two already filled."

**[Step 4 — Step 1 · Project Setup]**
"Step one is the project header. Molecule, target, indication, sponsor, and which agencies you're filing with. Each region you add flips on its region-specific paragraphs in the document — N-M-P-A adds a G-L-P declaration, P-M-D-A adds an ethnic bridging block."

**[Step 5 — Multi-region toggle]**
"F-D-A, E-M-A, N-M-P-A, P-M-D-A — any combination. The document panel re-renders region-specific paragraphs inline; the body that applies to every region stays put. One source of truth, four agency outputs."

**[Step 6 — Step 2 · ADMET screening]**
"Step two runs the BioMate *predict admet properties* workflow on AWS Batch. Forty-one endpoints across H-erg, D-I-L-I, AYMS, P-P-B-R, Caco-two, B-B-B, the CYPs, and P-g-p. These results feed sections two-point-six-point-one-point-three and two-point-six-point-four of the dossier."

**[Step 7 — Per-compound triage]**
"Click *View ADMET table* for the per-compound view. Every column header tooltips to its guideline citation — H-erg, for example, cites Redfern 2003 and ICH S7B, with the under-ten-micromolar liability threshold. Green check, amber tilde, red cross — the same colour key that travels through the document."

**[Step 8 — Bring in wet-lab data]**
"Computational predictions get you partial coverage. To upgrade to full, upload your wet-lab data — an NTP G-L-P report PDF or an F-D-A N-D-A review. BioMate auto-extracts measured values, and the measured values take precedence over predictions wherever they overlap."

**[Step 9 — Step 3 · PBPK qualification]**
"Step three qualifies the P-B-P-K model against a thirty-drug reference set, per E-M-A's qualification guideline. C-max and A-U-C within two-fold for at least sixty-seven percent of the reference set — that's the regulatory gate."

**[Step 10 — The gateway badge]**
"This badge is the most important pixel in the whole pipeline. If P-B-P-K qualification fails, downstream IND assembly is blocked until you re-qualify. *Re-run with new params* lets you adjust clearance, volume of distribution, or absorption and re-try without leaving the page."

**[Step 11 — Step 4 · Lead selection]**
"Step four ranks the candidate set. A Gaussian Process model with E-H-V-I acquisition over Morgan fingerprints scores every candidate on a five-axis surrogate — H-erg, D-I-L-I, AYMS, potency, and applicability domain."

**[Step 12 — Read the ranking]**
"Filled circles encode potency — four out of five filled means strong. *O-O-D* means out of applicability domain — the candidate is still ranked, but flagged in section two-point-six-point-one-point-five with a limitation statement, so reviewers see the caveat."

**[Step 13 — Step 5 · IND document]**
"Step five assembles the dossier — section two-point-six-point-one-point-one through two-point-six-point-six — once steps one through four are complete. The right-hand panel renders the document live as each pipeline step finishes."

**[Step 14 — Section coverage]**
"Section coverage at a glance. Filled circle is full — computational plus measured, ready for submission. Half circle is partial — computational only, flagged for wet-lab enrichment. Empty is not yet generated. Sections two-point-six-point-five and two-point-six-point-six always need G-L-P data to reach full."

**[Step 15 — Live document viewer]**
"The document panel is always visible on the right. As each pipeline step completes, the matching section populates in place — no page reload, no separate preview, no copy-paste from a temporary doc."

**[Step 16 — Jump to any section]**
"The tab strip jumps you to any section directly. The dot next to each tab encodes coverage at a glance — green for full, amber for partial — so you can spot the gaps without scrolling."

**[Step 17 — Per-region view]**
"Switch the rendered region right here. N-M-P-A adds the G-L-P declaration paragraph; P-M-D-A adds the ethnic bridging assumption table. The *all regions combined* view is what gets shipped to each agency."

**[Step 18 — Edit any paragraph]**
"Every paragraph is editable. Change one, and a small *edited — saved for model improvement* note appears beside it. Behind the scenes that edit becomes a training pair — your version as chosen, ours as rejected. That's how the BioMate regulatory model improves with every customer's expertise."

**[Step 19 — Suggest a citation]**
"See the plus icon at the end of a paragraph? Click it to suggest a missing guideline — especially useful for N-M-P-A or C-D-E technical guidelines we haven't indexed yet. Approved suggestions roll into the shared corpus on the next refresh."

**[Step 20 — Regulatory audit]**
"The audit bar at the top of section two-point-six is the compliance lens. Zero critical, zero major, two minor, four info — that means the document is signable. Critical blocks signing outright. Major shows an amber warning but lets the regulatory scientist proceed on judgment."

**[Step 21 — Each finding has a fix]**
"Open the audit drawer. Every finding shows what triggered it, the recommended fix, and a *jump to section* link. *Dismiss* with a reason — for example, *not applicable to this topical product* — and that reason refines the checker rule for every customer, automatically."

**[Step 22 — Sign & freeze]**
"Sign and freeze. Twenty-one C-F-R Part eleven, section eleven-point-two-hundred. Reviewer credentials, a six-digit T-O-T-P, and the meaning-of-signature statement are permanently recorded inside the frozen document."

**[Step 23 — Immutable versions]**
"Signed versions are frozen by SHA-two-five-six. Creating version three supersedes version two — but the version-two signature record stays in the audit trail forever. You can always render any prior version, byte-for-byte."

**[Step 24 — Wrap-up, centered]**
"That's the IND Report end to end. Five-step pipeline, live document, audit overlay, signature freeze. Three things worth trying on your own — open the sign overlay to see the full T-O-T-P flow, edit a paragraph and watch the training-pair note appear, and dismiss an audit finding to close the feedback loop. Happy filing."

---

## Recording notes

- **Pace.** ~140–160 words/minute spoken English. Each beat lands ~5–8 seconds in the on-screen tour.
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
