#!/usr/bin/env python3
"""
Generate ElevenLabs Rachel voiceover for all 4 BioMate tutorial demos.

Outputs per tutorial (in clips/<tutorial>/):
  step_01.mp3 … step_NN.mp3   — one clip per narration beat
  timings.json                 — { steps: [{step, clip_ms, hold_ms}], total_ms }
  combined.mp3                 — steps concatenated with GAP_MS silence between each

Usage:
  python3 generate_vo.py                    # all tutorials
  python3 generate_vo.py --only cryosparc  # one tutorial
"""

import os, sys, subprocess, json, tempfile, shutil, requests

API_KEY  = "sk_f850eae3cd4b254613c81e3b9a7d448a6924f4789e1233a4"
VOICE_ID = "21m00Tcm4TlvDq8ikWAM"   # Rachel
BASE     = os.path.dirname(os.path.abspath(__file__))
CLIPS    = os.path.join(BASE, "clips")

DEFAULT_SPEED   = 1.10
CLOSING_SPEED   = 0.75     # slower for intro/wrap-up centered steps

# Gap between steps in the combined audio (ms).
# Centre steps (modals) get a longer beat; spotlight steps get shorter.
CENTER_GAP_MS   = 1200
SPOT_GAP_MS     = 900


# ── Tutorial definitions ──────────────────────────────────────────────────────
#
# Each entry: (text, is_center_step, speed_override_or_None)
# is_center_step → True for full-screen modal steps; affects gap + speed default.

TUTORIALS = {

  # ── CryoSPARC SPA (cryosparc-main) — 20 steps ──────────────────────────────
  "cryosparc": {
    "label": "CryoSPARC SPA",
    "steps": [
      # 1 — center welcome
      ("We're going to run a complete cryo-EM single-particle analysis. "
       "No CryoSPARC experience needed — BioMate handles the parameters.",
       True, CLOSING_SPEED),

      # 2 — plan-checklist spotlight
      ("Two views, same run. Chat on the left narrates progress with a plan checklist. "
       "The workflow panel on the right shows phases, steps, parameters, and outputs.",
       False, None),

      # 3 — panel-header spotlight
      ("Run header — workflow name, status badge, live progress bar. "
       "Status is idle: the workflow is loaded but nothing has started yet.",
       False, None),

      # 4 — phase-list spotlight
      ("Five phases. A: motion and CTF. B: picking. C: 2D classification. "
       "D: 3D reconstruction. E: sharpening and validation. "
       "Only the active phase auto-expands.",
       False, None),

      # 5 — phase.open spotlight
      ("Phase A is auto-expanded. It runs MotionCor2 for frame alignment "
       "and CTFFIND4 for defocus estimation. Every step shows a live status chip.",
       False, None),

      # 6 — run-footer spotlight
      ("Parameters were pre-filled from your chat message. "
       "Confirm and run submits to AWS Batch. "
       "The footer always shows one primary button.",
       False, None),

      # 7 — panel-header running
      ("We're off. Status is running. "
       "Phase A motion correction is processing on Batch GPUs.",
       False, None),

      # 8 — phase-list live progress
      ("Each step ticks: queued, running, completed, failed. "
       "Chat and panel read the same stream — always in sync.",
       False, None),

      # 9 — CTF gate tripped
      ("CTF fit resolution is below threshold — "
       "likely a too-narrow defocus search range. "
       "QC gates halt before producing a bad map.",
       False, None),

      # 10 — halt card
      ("Auto-loop is off by default, so the halt card waits. "
       "BioMate suggests a wider defocus range — accept, edit, or dismiss. "
       "Turn auto-loop on to rerun without asking, capped at three retries.",
       False, None),

      # 11 — gate cleared
      ("Accepted. CTF reruns, the gate passes, Phase A completes, Phase B starts. "
       "Every retry is logged in the QC audit.",
       False, None),

      # 12 — step outputs inline
      ("File chips appear on each completed step row — "
       "view or download right there. No waiting for the whole run.",
       False, None),

      # 13 — Phase B picking
      ("Phase B. Topaz — a neural-network picker — scans every micrograph. "
       "One coordinate file per micrograph, into 2D classification.",
       False, None),

      # 14 — Phase C 2D
      ("Phase C. 2D classes. Junk classes — ice, carbon, aggregates — are dropped. "
       "Only clean views advance to 3D.",
       False, None),

      # 15 — Phase D 3D
      ("Phase D. Ab-initio reconstruction then homogeneous refinement. "
       "Output: an unsharpened map plus half-maps for gold-standard FSC.",
       False, None),

      # 16 — Phase E sharpening
      ("Phase E. B-factor sharpening, FSC resolution, local resolution. "
       "The B-factor is read from the manifest — never inferred.",
       False, None),

      # 17 — all done
      ("All done. Status completed. Converged at 3.1 angstrom "
       "by gold-standard FSC at 0.143 — publication territory.",
       False, None),

      # 18 — outputs downloadable
      ("Footer primary is now Run again. "
       "Scroll up for View Results, Download All, and the auto-generated Findings.",
       False, None),

      # 19 — after-run block
      ("Every completed run drops an After run block — "
       "outputs, findings, methods, parameters, software, citations, QC audit. "
       "There's a dedicated tutorial just for this section.",
       False, None),

      # 20 — center wrap-up
      ("Raw movies to a sharpened 3D map in twenty-three steps — "
       "motion correction, picking, 2D classification, 3D reconstruction, and sharpening.",
       True, CLOSING_SPEED),
    ],
  },

  # ── After-run report (outputs-findings-report) — 13 steps ──────────────────
  "outputs_report": {
    "label": "After-Run Report",
    "steps": [
      # 1 — center intro
      ("Your run just finished. The After run block has seven tabs covering "
       "everything BioMate produced for this CryoSPARC job. "
       "We'll walk each tab in order — content switches automatically.",
       True, CLOSING_SPEED),

      # 2 — after-run-header
      ("Every completed run leaves an After run section. "
       "Download report on the right bundles every tab into one structured document — "
       "DOCX, Markdown, or LaTeX — manuscript-ready in a click.",
       False, None),

      # 3 — results-links tabs
      ("Seven tabs cover the whole story: Findings, Outputs, Methods, Parameters, "
       "Software, Citations, and the QC audit. "
       "Narrative first, raw artifacts next, then reproducibility, ending with audit.",
       False, None),

      # 4 — Findings tab
      ("Findings opens with the headline metric — 3.21 angstrom resolution — "
       "plus two or three bullets, and a numeric table. "
       "Every number is read from the run manifest, not generated.",
       False, None),

      # 5 — Outputs tab
      ("One row per file, grouped by phase and step. "
       "View opens an inline preview; download grabs the single file. "
       "Download all bundles every output across all five phases as one ZIP.",
       False, None),

      # 6 — outputs on step
      ("You don't have to wait for the report. "
       "Each completed step shows its output chips inline the moment it finishes.",
       False, None),

      # 7 — inline preview modal
      ("The aligned sums folder opens in a preview modal. "
       "Tables get a sortable grid, plots get plotted, 3D maps get a viewer. "
       "BioMate picks the right renderer.",
       False, None),

      # 8 — Methods tab
      ("Methods. Paragraph-form prose you can drop straight into a manuscript. "
       "Tool names, versions, exact parameters — written so peers can replicate the run. "
       "Italics flag values that were inferred versus read from the manifest.",
       False, None),

      # 9 — Parameters tab
      ("Parameters. Phase, step, parameter, value — every knob the run touched. "
       "Defaults are flagged separately from user overrides and auto-loop adjustments.",
       False, None),

      # 10 — Software tab
      ("Every tool with its exact version. "
       "Together with Parameters, this is the reproducibility baseline.",
       False, None),

      # 11 — Citations tab
      ("Pre-formatted references for tools and methods cited in the prose. "
       "Click any PMID to open PubMed. "
       "Pre-bundled in the Download report.",
       False, None),

      # 12 — QC audit tab
      ("The QC audit tab. Every QC gate that fired: "
       "timestamp, threshold, observed value, result, and the action taken. "
       "21 CFR Part 11 friendly — chain-of-custody and operator e-signature included.",
       False, None),

      # 13 — center wrap-up
      ("That's the After run report. Seven tabs, one manifest, no copy-paste. "
       "Download report wraps everything into DOCX for Word, Markdown for Notion, "
       "or LaTeX for journal templates. Share the run URL and a collaborator gets "
       "the same view, read-only.",
       True, CLOSING_SPEED),
    ],
  },

  # ── Drug screen auto-loop (drugscreen-compare) — 13 steps ──────────────────
  "drug_screen": {
    "label": "Drug Screen Auto-Loop",
    "steps": [
      # 1 — center intro
      ("Drug screens often need a pilot, fail QC, and recover via auto-loop. "
       "We'll watch the whole sequence inline — pilot, fail, auto-loop, compare, full, findings. "
       "The tour drives every decision for you.",
       True, CLOSING_SPEED),

      # 2 — plan checklist
      ("BioMate decomposes the request into five sub-tasks: "
       "ingest, ADMET, hERG gate, Ames gate, ranking. "
       "Watch hERG and Ames — they trip mid-pilot.",
       False, None),

      # 3 — pilot prompt
      ("Ten thousand compounds is heavy. The DeepAgent suggests a five-percent pilot first — "
       "five hundred compounds, same parameters. "
       "The card carries the sampling fraction and strategy, plus the full-run cost. "
       "No separate dialog. The decision lives in chat, fully auditable.",
       False, None),

      # 4 — pilot running
      ("Pilot running on 500 of 10,000. "
       "Plan items tick from circle to dot to checkmark. "
       "The pilot validates the QC gates before committing.",
       False, None),

      # 5 — QC failure
      ("hERG and Ames trip. Plan items flip to amber warn pills in place. "
       "The pipeline doesn't crash — the next surface carries the decision.",
       False, None),

      # 6 — QC speaker pills
      ("Two amber QC pill lines land in chat — one for hERG, one for Ames. "
       "Pill colours match the plan, never lie, never drift across surfaces.",
       False, None),

      # 7 — pilot promotion card
      ("The pilot promotion card explains what failed and shows the auto-loop's "
       "proposed fix right there — new logp-max and mw-max values, "
       "with a one-click Apply fixes and re-pilot action. "
       "No silent retry: the user always sees the proposed change before it runs.",
       False, None),

      # 8 — LOOP speaker
      ("The LOOP speaker — purple pill — takes over. "
       "Every auto-loop decision shows here, so the audit trail stays clear. "
       "Both gates pass on the second run.",
       False, None),

      # 9 — comparison card
      ("Two pilots, side by side. Metrics table with a delta column. "
       "Parameter diffs tagged by origin — auto-loop versus user. "
       "A trophy badge with the recommendation, confidence, and p-value. "
       "QC outcomes coloured red on Run A and green on Run B.",
       False, None),

      # 10 — auto-pick countdown
      ("When confidence is high — p less than 0.01 here — "
       "the recommended button shows a ten-second countdown. "
       "Hover any button to pause it; click to commit. "
       "An auto-fire emits a 'No response — using Run B automatically' line "
       "so nothing happens silently.",
       False, None),

      # 11 — full run
      ("Decision committed. Ten thousand compounds on the tuned parameters. "
       "Faster this time — the pilot already proved the gates.",
       False, None),

      # 12 — findings card
      ("The completion summary lands inline. "
       "Forty-seven BBB-penetrant candidates after all QC gates, "
       "with a link to the full Report.",
       False, None),

      # 13 — center wrap-up
      ("Pilot, fail, auto-loop, compare, full, findings — "
       "end to end with a clean audit trail by speaker. "
       "The Variant calling tutorial covers nested plans next.",
       True, CLOSING_SPEED),
    ],
  },

  # ── IND Report long form (IND Tour) — 25 steps ─────────────────────────────
  "ind_report": {
    "label": "IND Report",
    "steps": [
      # 1 — center welcome
      ("Welcome to the BioMate IND Report. "
       "We'll walk through the five-step pipeline that builds an IND-quality "
       "section 2.6 nonclinical dossier, the live document panel on the right, "
       "and the 21 CFR Part 11 sign-and-freeze at the end.",
       True, CLOSING_SPEED),

      # 2 — center two panels
      ("Two panels, one project. On the left, the five-step pipeline you'll drive — "
       "setup, ADMET, PBPK, leads, document. "
       "On the right, the IND itself, regenerated in place as each step completes. "
       "The tour drives both.",
       True, CLOSING_SPEED),

      # 3 — project list
      ("Each program is its own project. "
       "The coloured dot on the left of each row is the status — "
       "green means signed, blue means in progress, amber means blocked on a gate. "
       "Click any project to switch — your work is preserved per project.",
       False, None),

      # 4 — new project
      ("Two ways to start an IND. New Project here in the rail, "
       "or — much more common — from the BioMate chat. "
       "When you run an ADMET workflow there, a Generate IND chip drops under "
       "the result and lands you here with steps one and two already filled.",
       False, None),

      # 5 — step 1 setup
      ("Step one is the project header. "
       "Molecule, target, indication, sponsor, and which agencies you're filing with. "
       "Each region you add flips on its region-specific paragraphs in the document — "
       "NMPA adds a GLP declaration, PMDA adds an ethnic bridging block.",
       False, None),

      # 6 — multi-region toggle
      ("FDA, EMA, NMPA, PMDA — any combination. "
       "The document panel re-renders region-specific paragraphs inline; "
       "the body that applies to every region stays put. "
       "One source of truth, four agency outputs.",
       False, None),

      # 7 — step 2 ADMET
      ("Step two. The ADMET screening step runs the BioMate predict ADMET properties "
       "workflow on AWS Batch. Forty-one endpoints across hERG, DILI, Ames, PPBR, "
       "Caco-2, BBB, the CYPs, and P-gp. "
       "These results feed sections 2.6.1.3 and 2.6.4 of the dossier.",
       False, None),

      # 8 — per-compound triage
      ("Click View ADMET table for the per-compound view. "
       "Every column header tooltips to its guideline citation — "
       "hERG cites Redfern 2003 and ICH S7B, with the under-ten-micromolar liability threshold. "
       "Green check, amber tilde, red cross — the same colour key that travels through the document.",
       False, None),

      # 9 — wet-lab data
      ("Computational predictions give you partial coverage. "
       "To upgrade to full, upload your wet-lab data — "
       "an NTP GLP report PDF or an FDA NDA review. "
       "BioMate auto-extracts measured values, and measured values take precedence "
       "over predictions wherever they overlap.",
       False, None),

      # 10 — step 3 PBPK
      ("Step three opens. PBPK qualification against a thirty-drug reference set, "
       "per EMA's qualification guideline. "
       "Cmax and AUC within two-fold for at least sixty-seven percent "
       "of the reference set — that's the regulatory gate.",
       False, None),

      # 11 — gateway badge
      ("This badge is the most important pixel in the whole pipeline. "
       "If PBPK qualification fails, downstream IND assembly is blocked "
       "until you re-qualify. "
       "Re-run with new params lets you adjust clearance, "
       "volume of distribution, or absorption and retry without leaving the page.",
       False, None),

      # 12 — step 4 lead selection
      ("Step four opens. Lead ranking with a Gaussian Process model, "
       "EHVI acquisition, Morgan fingerprints — "
       "every candidate scored on a five-axis surrogate: "
       "hERG, DILI, Ames, potency, and applicability domain.",
       False, None),

      # 13 — read the ranking
      ("Filled circles encode potency — four out of five filled means strong. "
       "OOD means out of applicability domain — the candidate is still ranked, "
       "but flagged in section 2.6.1.5 with a limitation statement, "
       "so reviewers see the caveat.",
       False, None),

      # 14 — step 5 document
      ("Step five assembles the dossier — "
       "section 2.6.1.1 through 2.6.6 — "
       "once steps one through four are complete. "
       "The right-hand panel renders the document live as each pipeline step finishes.",
       False, None),

      # 15 — section coverage
      ("Section coverage at a glance, inside step five. "
       "Filled circle is full — computational plus measured, ready for submission. "
       "Half circle is partial — computational only, flagged for wet-lab enrichment. "
       "Empty is not yet generated.",
       False, None),

      # 16 — live document viewer
      ("The document panel is always visible on the right. "
       "As each pipeline step completes, the matching section populates in place — "
       "no page reload, no separate preview, no copy-paste from a temporary doc.",
       False, None),

      # 17 — jump to any section
      ("The tab strip jumps you to any section directly. "
       "The dot next to each tab encodes coverage at a glance — "
       "green for full, amber for partial — so you can spot the gaps without scrolling.",
       False, None),

      # 18 — per-region view
      ("Switch the rendered region right here. "
       "NMPA adds the GLP declaration paragraph; "
       "PMDA adds the ethnic bridging assumption table. "
       "The all-regions-combined view is what gets shipped to each agency.",
       False, None),

      # 19 — edit paragraph
      ("Every paragraph is editable. Change one, and a small 'edited — saved for model improvement' "
       "note appears beside it. Behind the scenes that edit becomes a training pair — "
       "your version as chosen, ours as rejected. "
       "That's how the BioMate regulatory model improves with every customer's expertise.",
       False, None),

      # 20 — suggest a citation
      ("See the plus icon at the end of a paragraph? "
       "Click it to suggest a missing guideline — especially useful for NMPA or CDE technical guidelines "
       "we haven't indexed yet. "
       "Approved suggestions roll into the shared corpus on the next refresh.",
       False, None),

      # 21 — regulatory audit bar
      ("The audit bar at the top of section 2.6 is the compliance lens. "
       "Zero critical, zero major, two minor, four info — that means the document is signable. "
       "Critical blocks signing outright. "
       "Major shows an amber warning but lets the regulatory scientist proceed on judgment.",
       False, None),

      # 22 — audit drawer
      ("The audit drawer opens. Every finding shows what triggered it, "
       "the recommended fix, and a jump-to-section link. "
       "Dismiss with a reason — for example, 'not applicable to this topical product' — "
       "and that reason refines the checker rule for every customer, automatically.",
       False, None),

      # 23 — sign and freeze
      ("Audit drawer closes; the sign button highlights. "
       "21 CFR Part 11, section 11.200. "
       "Reviewer credentials, a six-digit TOTP, and the meaning-of-signature statement "
       "are permanently recorded inside the frozen document.",
       False, None),

      # 24 — immutable versions
      ("Signed versions are frozen by SHA-256. "
       "Creating version three supersedes version two — "
       "but the version-two signature record stays in the audit trail forever. "
       "You can always render any prior version, byte-for-byte.",
       False, None),

      # 25 — center wrap-up
      ("That's the IND Report end to end. "
       "Five-step pipeline, live document, audit overlay, signature freeze. "
       "Three things worth trying on your own: "
       "open the sign overlay to walk the full TOTP flow, "
       "edit a paragraph and watch the training-pair note appear, "
       "and dismiss an audit finding to close the feedback loop. "
       "Happy filing.",
       True, CLOSING_SPEED),
    ],
  },

  # ── Bioconductor · DESeq2 chain (bioc-kb-routing) — 30 steps ────────────────
  # Sourced from Research Agent_UI_bio_drug/narratives/Bioconductor Narratives.md
  # full-cut. Step order matches BiocTours.jsx exactly:
  #   6 opening beats + 5 controlSteps + 4 analysis beats + 11 afterRunSteps + 1 wrap-up
  # HTML: Research Agent_UI_bio_drug/Research Agent UI.html
  # Tour label: "BIO — Bioconductor · KB routing & execution"
  "bioc_kb": {
    "label": "Bioconductor · DESeq2 chain",
    "steps": [
      # 1 — center welcome
      ("We're running a differential-expression analysis, end to end. "
       "No R needed — BioMate matches your request to a curated Bioconductor "
       "workflow and drives every step.",
       True, CLOSING_SPEED),

      # 2 — understanding the request
      ("First it embeds your request against the Bioconductor knowledge base. "
       "The panel stays empty — no pipeline is chosen until the match resolves.",
       False, None),

      # 3 — ranked KB match
      ("Two curated chains score close — a count-matrix DESeq2 path, and a "
       "fuller FASTQ pipeline. BioMate shows both with scores and pre-selects "
       "the top one.",
       False, None),

      # 4 — chain populates the panel
      ("With the DESeq2 chain committed, the panel fills with six phases: "
       "QC, normalise, DE test, shrink, enrich, visualise.",
       False, None),

      # 5 — routed by data format, not habit
      ("Why DESeq2? A raw integer count matrix needs a negative-binomial model "
       "— not limma-voom, which is for continuous intensities. "
       "Routed by data format, not habit.",
       False, None),

      # 6 — Phase A running, QC filtering
      ("Execution starts; the active phase auto-expands. "
       "edgeR's filterByExpr drops genes under ten counts. "
       "Parameters and outputs appear inline as each step finishes.",
       False, None),

      # 7 — QC gate: genes retained — passed
      ("Phase A's gate reads fourteen-thousand two-hundred and three genes retained "
       "— seventy-seven percent of the original count, well above the ten-thousand threshold. "
       "A green gate here means the library isn't dominated by noise. "
       "Had it failed, auto-loop would have tightened the filter and re-run automatically.",
       False, None),

      # 8 — control: params prefilled and editable
      ("Every step opens with the workflow's defaults already filled in. "
       "Click the gear to adjust a value inline — change only what you need.",
       False, None),

      # 8 — control: QC gates editable with auto-loop
      ("Each phase has an editable QC gate, prefilled with its default threshold. "
       "The auto-loop switch lets a failed gate fix its own params and re-run.",
       False, None),

      # 9 — control: halt box, 10s auto-proceed
      ("When auto-loop is on, a failed gate posts a halt box — "
       "the failing metric, the proposed fix, and a ten-second countdown. "
       "Apply, pause, or dismiss.",
       False, None),

      # 10 — control: outputs render inline in real time
      ("As each step finishes, its files drop into the panel — "
       "view opens them inline, download grabs the file. "
       "No waiting for the full chain.",
       False, None),

      # 11 — control: stop and resume any phase
      ("Any running phase can be stopped — finished steps and outputs are kept "
       "— then resumed exactly where you left off.",
       False, None),

      # 12 — one typed object carries the analysis
      ("After normalisation, counts, metadata and size factors fold into one "
       "DESeqDataSet — the typed object every downstream step reads from.",
       False, None),

      # 13 — Phase C running, DE testing
      ("Phase C runs the Wald test on design tilde-condition — "
       "two thousand eight hundred and forty-one genes at five-percent FDR — "
       "producing a results table of fold-change and adjusted-p per gene.",
       False, None),

      # 14 — QC gate: replicate count — critical guard
      ("Phase C checks twelve replicates per group against a minimum of two — "
       "a critical guard. DESeq2 needs at least two replicates to estimate dispersion; "
       "fewer means the model cannot converge. "
       "A fail here halts the chain immediately, before any computation is wasted.",
       False, None),

      # 16 — shrink noisy fold-changes
      ("Before ranking, apeglm shrinks noisy low-count fold-changes toward zero, "
       "so enrichment isn't dominated by extremes.",
       False, None),

      # 17 — Phase E running, enrichment
      ("clusterProfiler's gseGO runs on the ranked list — "
       "top term, regulation of apoptotic process. "
       "Next, Phase F renders the figures and queries STRING for an interaction network.",
       False, None),

      # 18 — Phase F · STRINGdb gene interaction network
      ("BioMate queries STRING version twelve for all twenty-eight hundred and forty-one DE genes. "
       "The result is an interactive protein-protein interaction network — "
       "nodes coloured by log-two fold-change, edges weighted by STRING confidence. "
       "Top hub: TP53, with eighty-seven first-degree interactions.",
       False, None),

      # 19 — chain complete (findings-chat spotlight)
      ("All six phases done — DESeq2, apeglm, clusterProfiler, EnhancedVolcano, and the STRINGdb interaction network. "
       "Chat drops a findings card; the panel flips to the After-run report.",
       False, None),

      # 20 — after run, one structured report (results-links spotlight)
      ("The report has seven tabs in reading order — results first, methods and "
       "reproducibility next, audit last. The whole thing exports to one document.",
       False, None),

      # 21 — Findings tab
      ("Findings: the headline metric, a few bullets, and figures read straight "
       "from the manifest — including the STRINGdb hub gene. "
       "Nothing is invented — uncited claims are tagged author judgment.",
       False, None),

      # 22 — Outputs tab
      ("Outputs lists every file by phase — the results object, volcano, "
       "GO dot plot, top-fifty heatmap, and the interactive STRINGdb network. "
       "View previews inline; download grabs one or all.",
       False, None),

      # 23 — Open in RStudio (interactive-launcher spotlight)
      ("Download isn't the end. Every results object has an Open-in-RStudio button "
       "— a live R four-point-three session with DESeq2 loaded and your "
       "dataset pre-mounted.",
       False, None),

      # 24 — STRINGdb network preview (preview-modal spotlight)
      ("Clicking view on the STRINGdb network renders it inline — "
       "twenty-eight hundred genes as nodes, coloured by fold-change, "
       "edges weighted by STRING confidence. "
       "Hub genes like TP53 sit at the centre; export as SVG anytime.",
       False, None),

      # 25 — Methods tab
      ("Methods is paragraph-form prose — tools, versions, exact parameters — "
       "written so a peer can replicate the run, including the STRINGdb network construction. "
       "Paste it straight into a manuscript.",
       False, None),

      # 26 — Parameters tab
      ("Parameters lists phase, step and value for everything the run touched "
       "— a ready supplementary table. "
       "Defaults, overrides and auto-loop tweaks are distinguished.",
       False, None),

      # 27 — Software tab
      ("Software pins every package version — DESeq2, apeglm, edgeR, "
       "clusterProfiler, STRINGdb. With Parameters, it's the reproducibility baseline.",
       False, None),

      # 28 — Citations tab
      ("Citations auto-generates the reference list — Love twenty-fourteen, "
       "Zhu twenty-nineteen, Wu twenty-twenty-one, Szklarczyk twenty-twenty-three, and more. "
       "Methods and Citations export together.",
       False, None),

      # 29 — QC audit tab
      ("QC audit logs every gate that fired — gene retention, size-factor range, "
       "replicate count — with threshold, observed value and action. "
       "Twenty-one CFR Part Eleven friendly.",
       False, None),

      # 30 — center wrap-up
      ("That's the full DESeq2 thread — match, route, run six phases, "
       "a seven-tab report with an interactive gene network, all from one request. "
       "Download wraps it into a single document.",
       True, CLOSING_SPEED),
    ],
  },

  # ── Bioconductor · scRNA-seq → pseudobulk DE (bioc-sc-routing) — 25 steps ──
  # Sourced from Research Agent_UI_bio_drug/narratives/Bioconductor Narratives.md
  # full-cut. Step order matches BiocTours.jsx:
  #   4 opening + 5 controlSteps + 4 analysis + 11 afterRunSteps + 1 wrap-up
  # Tour label: "BIO2 — Bioconductor · scRNA-seq → pseudobulk DE"
  "bioc_sc": {
    "label": "Bioconductor · scRNA-seq chain",
    "steps": [
      # 1 — center welcome
      ("Same agent, a single-cell request. BioMate routes to the OSCA stack, "
       "clusters and annotates in parallel, then runs condition DE "
       "the statistically correct way — pseudobulk.",
       True, CLOSING_SPEED),

      # 2 — seven phases, a parallel branch
      ("Seven phases: QC, normalise, feature selection and PCA, cluster, "
       "then markers and annotation in parallel, then pseudobulk DE.",
       False, None),

      # 3 — routed to the OSCA stack
      ("The agent works backward from the goal. Condition DE with DESeq2 means "
       "a SingleCellExperiment plus scran and scater — not Seurat — "
       "so the final step hands off cleanly.",
       False, None),

      # 4 — Phase A running, cell QC
      ("Phase A: emptyDrops separates real cells from ambient barcodes, "
       "then per-cell QC flags high-mito, low-count cells — "
       "nine thousand eight hundred and fourteen of twelve thousand four hundred and two kept.",
       False, None),

      # 5 — control: params prefilled and editable
      ("Each step opens with defaults filled in. "
       "Click the gear to adjust a value inline — change only what you need.",
       False, None),

      # 6 — control: QC gates editable with auto-loop
      ("Every phase has an editable QC gate, prefilled with its default. "
       "The auto-loop switch lets a failed gate fix its params and re-run.",
       False, None),

      # 7 — control: halt box, 10s auto-proceed
      ("With auto-loop on, a failed gate posts a halt box — "
       "failing metric, proposed fix, ten-second countdown. Apply, pause, or dismiss.",
       False, None),

      # 8 — control: outputs render inline
      ("Files drop into the panel as each step finishes — "
       "view opens them inline, download grabs the file.",
       False, None),

      # 9 — control: stop and resume
      ("Any phase can be stopped — finished steps are kept — "
       "then resumed where you left off, nothing recomputed.",
       False, None),

      # 10 — one SingleCellExperiment throughout
      ("QC and normalisation fold into a single SingleCellExperiment carrying "
       "counts, log-counts and metadata. Every step below reads from this one object.",
       False, None),

      # 11 — phases B–D done, 11 clusters
      ("Normalisation, HVG selection with PCA, and graph-based clustering are done "
       "— eleven clusters. "
       "The UMAP is for visualisation only; clusters come from the SNN graph.",
       False, None),

      # 12 — parallel branch, markers and annotation
      ("Phases E and F open together — scoreMarkers and SingleR both read the "
       "clustered object, so the engine fans them out and tracks the join.",
       False, None),

      # 13 — pseudobulk, not naive per-cell DE
      ("The key beat: testing thousands of cells as replicates is pseudoreplication. "
       "The fix — aggregate to pseudobulk, so the six samples are the real replicates, "
       "then DESeq2 per cell type.",
       False, None),

      # 14 — chain complete (findings-chat spotlight)
      ("Seven phases done — routed to OSCA, clustered, annotated, then pseudobulk DE. "
       "CD8 T cells are the strongest responder, "
       "two hundred and fourteen DE genes on true replicates.",
       False, None),

      # 15 — after run, one structured report
      ("The After-run report — seven tabs in reading order, results first, audit last, "
       "and a one-click export of the whole document.",
       False, None),

      # 16 — Findings tab
      ("Findings: headline plus figures from the manifest — "
       "DE genes per cell type, composition, QC retention. "
       "Significance rests on the six biological replicates.",
       False, None),

      # 17 — Outputs tab
      ("Outputs by phase — the UMAP, marker heatmap, per-cell-type DE tables, "
       "and the cell-type calls. View previews; download grabs one or all.",
       False, None),

      # 18 — Open in CellxGene (interactive-launcher spotlight)
      ("The natural next move for single-cell: the h5ad export has an "
       "Open-in-CellxGene button — browse the annotated UMAP and expression live, "
       "or switch to RStudio.",
       False, None),

      # 19 — visualised, annotated UMAP (preview-modal spotlight)
      ("Clicking view on the UMAP renders it inline — "
       "nine thousand eight hundred and fourteen cells coloured by "
       "eight SingleR cell types, with a legend.",
       False, None),

      # 20 — Methods tab
      ("Methods, paste-ready — emptyDrops QC, scran normalisation, "
       "SNN-Louvain clustering, SingleR annotation, "
       "and aggregate-then-DESeq2, with versions and parameters.",
       False, None),

      # 21 — Parameters tab
      ("Parameters: phase, step, value — emptyDrops FDR, HVG count, SNN k, "
       "the SingleR reference, the pseudobulk design. A ready supplementary table.",
       False, None),

      # 22 — Software tab
      ("Software pins exact versions — DropletUtils, scran, scater, SingleR, DESeq2 "
       "— the reproducibility baseline alongside Parameters.",
       False, None),

      # 23 — Citations tab
      ("Citations: Amezquita twenty-twenty for OSCA, Lun twenty-nineteen for emptyDrops, "
       "Aran twenty-nineteen for SingleR, Love twenty-fourteen for DESeq2.",
       False, None),

      # 24 — QC audit tab
      ("QC audit logs every gate — cells retained, cluster count, "
       "and the replicate-unit gate that enforces pseudobulk over per-cell DE.",
       False, None),

      # 25 — center wrap-up
      ("That's the single-cell thread — route to OSCA, cluster, annotate in parallel, "
       "pseudobulk DE, a seven-tab report. One object, statistically honest DE.",
       True, CLOSING_SPEED),
    ],
  },

  # ── Bioconductor · 450k methylation → DMRs (bioc-methyl-routing) — 25 steps ─
  # Sourced from Research Agent_UI_bio_drug/narratives/Bioconductor Narratives.md
  # full-cut. Step order matches BiocTours.jsx:
  #   4 opening + 5 controlSteps + 4 analysis + 11 afterRunSteps + 1 wrap-up
  # Tour label: "BIO3 — Bioconductor · 450k methylation → DMRs"
  "bioc_methyl": {
    "label": "Bioconductor · 450k methylation chain",
    "steps": [
      # 1 — center welcome
      ("A methylation-array request. This chain rides a genomic backbone object "
       "instead of a count matrix — probe coordinates travel with the data, "
       "so region-level analysis is possible.",
       True, CLOSING_SPEED),

      # 2 — five phases, mirrored in the panel
      ("Five phases: read IDAT, QC and normalise, DMP calling, DMR calling, "
       "then CpG-corrected enrichment. The panel mirrors the chat.",
       False, None),

      # 3 — routed to minfi
      ("The agent explains it — raw IDAT plus a 450k manifest routes to minfi, "
       "because the DMR step needs a genomic object, not a plain matrix.",
       False, None),

      # 4 — Phase A running, read IDAT
      ("Phase A: read.metharray.exp reads the IDAT pairs into a MethylSet — "
       "raw methylated and unmethylated intensities, "
       "four hundred and fifty thousand probes across twenty-four samples.",
       False, None),

      # 5 — control: params prefilled and editable
      ("Each step opens with defaults filled in. "
       "Click the gear to adjust a value inline — change only what you need.",
       False, None),

      # 6 — control: QC gates editable with auto-loop
      ("Every phase has an editable QC gate, prefilled with its default. "
       "The auto-loop switch lets a failed gate fix its params and re-run.",
       False, None),

      # 7 — control: halt box, 10s auto-proceed
      ("With auto-loop on, a failed gate posts a halt box — "
       "failing metric, proposed fix, ten-second countdown. Apply, pause, or dismiss.",
       False, None),

      # 8 — control: outputs render inline
      ("Files drop into the panel as each step finishes — "
       "view opens them inline, download grabs the file.",
       False, None),

      # 9 — control: stop and resume
      ("Any phase can be stopped — finished steps are kept — "
       "then resumed where you left off.",
       False, None),

      # 10 — GenomicRatioSet, coordinates attached
      ("After QC and normalisation the object is a GenomicRatioSet — "
       "beta-values with each probe's coordinate. "
       "That backbone is what lets the next step collapse CpGs into regions.",
       False, None),

      # 11 — Phase C running, DMP calling
      ("Phase C: per-CpG differential methylation with limma eBayes on M-values "
       "— twelve thousand four hundred and three significant CpGs at "
       "five-percent FDR, passed to bumphunter.",
       False, None),

      # 12 — Phase D done, 847 DMRs
      ("bumphunter, a thousand bootstraps, collapses adjacent significant CpGs "
       "into eight hundred and forty-seven regions — "
       "a GRanges object of DMRs, ready for enrichment.",
       False, None),

      # 13 — CpG-density bias correction (teaching beat)
      ("The teaching beat: a normal GO over-represents CpG-rich promoters on the array. "
       "The fix — gometh weights genes by CpG count "
       "so enrichment p-values stay calibrated.",
       False, None),

      # 14 — chain complete (findings-chat spotlight)
      ("Five phases done — minfi read, normalised, DMPs, bumphunter DMRs, "
       "CpG-corrected GO. Eight hundred and forty-seven DMRs "
       "from twelve thousand four hundred and three significant CpGs.",
       False, None),

      # 15 — after run, one structured report
      ("The After-run report — seven tabs, results first, audit last, "
       "exportable as one document.",
       False, None),

      # 16 — Findings tab
      ("Findings: headline plus figures from the manifest — "
       "DMR direction, top CpG-corrected GO terms, probe-QC retention. "
       "Numbers read from the run, not generated.",
       False, None),

      # 17 — Outputs tab
      ("Outputs by phase — the DMP table, the DMRs as GRanges, "
       "and the CpG-corrected enrichment. View previews; download grabs one or all.",
       False, None),

      # 18 — Open in RStudio (interactive-launcher spotlight)
      ("Every results object has an Open-in-RStudio button — "
       "a live R four-point-three session with minfi and bumphunter loaded "
       "and your GenomicRatioSet mounted.",
       False, None),

      # 19 — visualised, DMR manhattan (preview-modal spotlight)
      ("Clicking view on the DMR track renders it inline — "
       "significance across chromosomes, with the eight hundred and forty-seven "
       "DMRs above threshold highlighted.",
       False, None),

      # 20 — Methods tab
      ("Methods, paste-ready — read.metharray, detection-p QC, "
       "SNP and cross-reactive filtering, quantile normalisation, "
       "limma DMPs, bumphunter DMRs, gometh enrichment.",
       False, None),

      # 21 — Parameters tab
      ("Parameters: detection-p cutoff, the M-value design, "
       "bumphunter bootstraps and cutoff, the gometh array type. "
       "A ready supplementary table.",
       False, None),

      # 22 — Software tab
      ("Software pins exact versions — minfi, limma, bumphunter, missMethyl "
       "— the reproducibility baseline alongside Parameters.",
       False, None),

      # 23 — Citations tab
      ("Citations: Aryee twenty-fourteen for minfi, Jaffe twenty-twelve for bumphunter, "
       "Phipson twenty-sixteen for missMethyl, Ritchie twenty-fifteen for limma.",
       False, None),

      # 24 — QC audit tab
      ("QC audit logs every gate — samples read, probes retained, "
       "significant-CpG and DMR counts, and the CpG-bias-corrected flag.",
       False, None),

      # 25 — center wrap-up
      ("That's the epigenomics thread — a GRanges backbone, DMPs, DMRs, "
       "CpG-corrected enrichment, a seven-tab report. "
       "A different object lineage, same orchestration.",
       True, CLOSING_SPEED),
    ],
  },

  # ── Tier-0 Therapeutic Design Tutorials ─────────────────────────────────────
  # Source: design_handoff_tier0_design_pipelines/narratives/Drug Development Narratives.md
  # All five tours are 19 steps each (intro + route/special + phaseARun + panelSteps(5)
  #   + chat beat + afterRun(9) + closing).
  # HTML: design_handoff_tier0_design_pipelines/Research Agent UI.html
  # Tour labels registered in that folder's Tour.jsx under "Therapeutic design" group.

  # ── T01 · Bispecific format triage — PD-1 × VEGF for NSCLC ────────────────
  "design_bispecific": {
    "label": "T01 · Bispecific format triage",
    "steps": [
      # 1 — center welcome
      ("We'll design a PD-1-by-VEGF bispecific antibody for lung cancer "
       "— end to end, from one sentence.",
       True, CLOSING_SPEED),

      # 2 — routing the intent
      ("BioMate reads two targets, an indication, and a requested format, "
       "and routes to the bispecific format-triage workflow.",
       False, None),

      # 3 — Phase A, mechanism
      ("Phase A infers the mechanism: PD-1 and VEGF efficacy is driven by "
       "cooperative avidity on dimeric VEGF.",
       False, None),

      # 4 — parameters, prefilled
      ("Each step opened with its parameters already filled from your message "
       "— change only what you need.",
       False, None),

      # 5 — provenance badges
      ("Open Workflow settings: every value wears a badge — from your message, "
       "normalized, or inferred. Prefill is never a black box.",
       False, None),

      # 6 — QC gates
      ("Each phase carries an editable QC gate, with an optional auto-loop "
       "that re-runs a failed phase with adjusted parameters.",
       False, None),

      # 7 — outputs inline
      ("As each step finishes, its files drop straight into the panel "
       "— the scoring matrix and the ranked table appear as they're produced.",
       False, None),

      # 8 — stop and resume
      ("Any running phase can be stopped and resumed "
       "— finished steps and their outputs are kept.",
       False, None),

      # 9 — composite ranking
      ("Phase C weights mechanism and format together. "
       "The tetravalent cooperative format leads — ivonescimab's architecture "
       "— ahead of the requested CrossMab.",
       False, None),

      # 10 — chain complete
      ("All four phases done. "
       "The chat drops a findings card and the panel flips to the After-run report.",
       False, None),

      # 11 — after-run report
      ("Every completed run opens a tabbed After-run report "
       "— results first, methods next, audit last. We'll walk each tab.",
       False, None),

      # 12 — Findings tab
      ("Findings leads with the headline and figures read straight from the run manifest "
       "— the composite scores and the axis weighting.",
       False, None),

      # 13 — Outputs tab
      ("Outputs lists every file — the format report and the ranked CSV "
       "— grouped by phase. View inline, or download all.",
       False, None),

      # 14 — Methods tab
      ("Methods is paste-ready prose — the six axes, the cooperative-avidity call, "
       "and the composite weighting, written for a reviewer.",
       False, None),

      # 15 — Parameters tab
      ("Parameters lists every knob the run touched "
       "— the five formats, the six axes, the weighting — supplementary-ready.",
       False, None),

      # 16 — Software tab
      ("Software pins each component and version "
       "— the reproducibility baseline alongside Parameters.",
       False, None),

      # 17 — Citations tab
      ("Citations are pre-formatted — the ivonescimab tetravalent mechanism papers "
       "and the HARMONi-two readout.",
       False, None),

      # 18 — QC audit tab
      ("The QC audit — every gate that fired, with threshold, observed value, and result. "
       "An auditable trail of how the recommendation was reached.",
       False, None),

      # 19 — center wrap-up
      ("From one sentence: five formats scored and the tetravalent winner recovered "
       "— the architecture the field landed on for ivonescimab.",
       True, CLOSING_SPEED),
    ],
  },

  # ── T02 · In-vivo CAR-T co-design — CD19 + LNP for DLBCL ─────────────────
  "design_cart": {
    "label": "T02 · In-vivo CAR-T co-design",
    "steps": [
      # 1 — center welcome
      ("We'll co-design an in-vivo CD19 CAR-T for lymphoma "
       "— both the construct and the delivery, in one pass.",
       True, CLOSING_SPEED),

      # 2 — free text to schema enum
      ("Here's the teaching moment: your 'T cells' became the schema value "
       "T-underscore-cell automatically, so delivery is unambiguous before any compute.",
       False, None),

      # 3 — Phase A, atlas safety
      ("Phase A scans CD19 across tissues "
       "— it's B-cell-restricted, no critical-tissue hits, safe to proceed.",
       False, None),

      # 4 — parameters, prefilled
      ("Each step opened with its parameters pre-filled from your message "
       "— adjust only what you need.",
       False, None),

      # 5 — provenance badges
      ("In Workflow settings, every value is badged "
       "— and the delivery cell reads normalized from your 'T cells'.",
       False, None),

      # 6 — QC gates
      ("Each phase has an editable QC gate; "
       "the atlas-safety gate is what cleared the target here.",
       False, None),

      # 7 — outputs inline
      ("Outputs land as they're produced "
       "— the expression map, the LNP tropism scores, the fratricide check.",
       False, None),

      # 8 — stop and resume
      ("A running phase can be stopped and resumed "
       "— finished steps and their outputs are preserved.",
       False, None),

      # 9 — the fratricide check
      ("The phase that earns its keep: the anti-CD8 LNP hits CD8-positive T cells, "
       "CD19 sits on B cells — no overlap, so the design is green.",
       False, None),

      # 10 — chain complete
      ("All five phases done. "
       "The findings card lands and the panel flips to the After-run report.",
       False, None),

      # 11 — after-run report
      ("The After-run report opens — results, methods, then audit. "
       "We'll walk each tab in order.",
       False, None),

      # 12 — Findings tab
      ("Findings reads from the manifest — LNP delivery efficiency by candidate, "
       "the construct domains, and the atlas-safety bar.",
       False, None),

      # 13 — Outputs tab
      ("Outputs lists the construct FASTA, the fratricide JSON, "
       "the LNP recommendation, and the CMC flag. View or download all.",
       False, None),

      # 14 — Methods tab
      ("Methods is paste-ready "
       "— the atlas call, LNP tropism, the fratricide logic, and the construct domains.",
       False, None),

      # 15 — Parameters tab
      ("Parameters lists the LNP candidates, the fratricide cell-type comparison, "
       "and the FMC63 four-one-BB construct choices.",
       False, None),

      # 16 — Software tab
      ("Software pins each component and version — the reproducibility baseline.",
       False, None),

      # 17 — Citations tab
      ("Citations: the CPTX twenty-three-oh-nine CD8-targeted LNP, "
       "the anti-CD5 in-vivo-CAR proof of concept, and the Kymriah construct.",
       False, None),

      # 18 — QC audit tab
      ("The QC audit — atlas safety, delivery efficiency, and the fratricide overlap gate. "
       "The fratricide gate is the one that protects the design.",
       False, None),

      # 19 — center wrap-up
      ("The anti-CD8 LNP plus CD19 CAR — Capstan's CPTX twenty-three-oh-nine. "
       "Switch the target to CD7 and the fratricide gate trips automatically.",
       True, CLOSING_SPEED),
    ],
  },

  # ── T03 · In-vivo base-edit knockout — PCSK9 for hypercholesterolemia ──────
  "design_baseedit": {
    "label": "T03 · In-vivo base-edit knockout",
    "steps": [
      # 1 — center welcome
      ("We'll design an in-vivo base-edit knockout of PCSK9 to lower cholesterol "
       "— from a single sentence.",
       True, CLOSING_SPEED),

      # 2 — tissue picks the delivery
      ("A knockout means a base editor, not a nuclease. "
       "PCSK9 is liver-expressed, so intravenous LNP is the natural route.",
       False, None),

      # 3 — Phase A, tissue restriction
      ("Phase A confirms PCSK9 is hepatocyte-restricted "
       "— an ideal target, because the liver natively absorbs LNPs.",
       False, None),

      # 4 — parameters, prefilled
      ("Each step opened with parameters pre-filled from your message "
       "— edit-goal was derived from the word 'knockout'.",
       False, None),

      # 5 — provenance badges
      ("In Workflow settings, every value is badged "
       "— from your message, derived, or inferred.",
       False, None),

      # 6 — QC gates
      ("Each phase has an editable QC gate; "
       "here the tissue-restriction gate cleared the IV-LNP route.",
       False, None),

      # 7 — outputs inline
      ("Outputs land as they're produced "
       "— the editor choice, the guide CSV, the CMC flag.",
       False, None),

      # 8 — stop and resume
      ("A running phase can be stopped and resumed, "
       "with finished steps and outputs kept.",
       False, None),

      # 9 — editor and clinical precedent
      ("Phase B picks an adenine base editor making an A-to-G edit at the splice donor; "
       "the CMC flag surfaces VERVE-101's liver-enzyme signal "
       "and the reformulation Verve used for VERVE-102.",
       False, None),

      # 10 — chain complete
      ("All five phases done. "
       "The findings card lands and the panel flips to the After-run report.",
       False, None),

      # 11 — after-run report
      ("The After-run report opens "
       "— results first, methods next, audit last. We'll walk each tab.",
       False, None),

      # 12 — Findings tab
      ("Findings reads from the manifest "
       "— editor-class fit, top-guide specificity, and the off-target scan.",
       False, None),

      # 13 — Outputs tab
      ("Outputs lists the editor choice, the guide RNA CSV, "
       "the CMC flag, and the IND-readiness checklist.",
       False, None),

      # 14 — Methods tab
      ("Methods is paste-ready "
       "— the tissue rationale, the adenine-base-editor selection, "
       "the splice-donor edit, and the CMC note.",
       False, None),

      # 15 — Parameters tab
      ("Parameters lists the editor class, the splice-donor edit, "
       "the genome used for off-target scanning, and the precedent referenced.",
       False, None),

      # 16 — Software tab
      ("Software pins each component and version — the reproducibility baseline.",
       False, None),

      # 17 — Citations tab
      ("Citations: the primate PCSK9 base-editing paper "
       "and the VERVE-101 adenine-base-editor splice-donor mechanism.",
       False, None),

      # 18 — QC audit tab
      ("The QC audit — tissue restriction, splice-donor disruption, "
       "and guide specificity above ninety-five percent, "
       "each with threshold and result.",
       False, None),

      # 19 — center wrap-up
      ("An adenine base editor disrupting the PCSK9 splice donor "
       "— VERVE-one-oh-one and one-oh-two's exact mechanism, "
       "recovered from one sentence.",
       True, CLOSING_SPEED),
    ],
  },

  # ── T04 · GLP-1 modality bake-off — MASH ─────────────────────────────────
  "design_glp1": {
    "label": "T04 · GLP-1 modality bake-off",
    "steps": [
      # 1 — center welcome
      ("The next GLP-1 question for fatty-liver disease isn't dosing "
       "— it's modality. We'll score four of them.",
       True, CLOSING_SPEED),

      # 2 — when BioMate isn't sure
      ("'Compare' is ambiguous — run a design workflow, or just search for tools? "
       "Rather than guess, BioMate asks. We pick 'run a design workflow'.",
       False, None),

      # 3 — routed, indication normalized
      ("Routed to the GLP-1 modality bake-off, "
       "with the indication lowercased to the enum value mash.",
       False, None),

      # 4 — Phase A, scoring
      ("Phase A scores each modality across six axes "
       "— half-life, oral bioavailability, cardiovascular outcomes, "
       "liver evidence, manufacturing, and dosing burden.",
       False, None),

      # 5 — parameters and provenance
      ("In Workflow settings, the modality list is badged from your message; "
       "every value shows where it came from.",
       False, None),

      # 6 — QC gates
      ("Each phase carries an editable QC gate "
       "— here, that all four modalities were scored.",
       False, None),

      # 7 — outputs inline
      ("Outputs land as they're produced "
       "— the scoring matrix and the ranked recommendation.",
       False, None),

      # 8 — stop and resume
      ("A running phase can be stopped and resumed, with finished work preserved.",
       False, None),

      # 9 — ranking
      ("Peptide injection leads on safety and cardiovascular outcomes; "
       "messenger-RNA is still preclinical; "
       "gene therapy is single-dose but unproven for durability.",
       False, None),

      # 10 — chain complete
      ("All three phases done. "
       "The findings card lands and the panel flips to the After-run report.",
       False, None),

      # 11 — after-run report
      ("The After-run report opens — results, methods, then audit. "
       "We'll walk each tab.",
       False, None),

      # 12 — Findings tab
      ("Findings reads from the manifest "
       "— the composite modality scores and the six scoring axes.",
       False, None),

      # 13 — Outputs tab
      ("Outputs lists the scoring CSV and the bake-off recommendation. "
       "View inline or download all.",
       False, None),

      # 14 — Methods tab
      ("Methods is paste-ready "
       "— the six axes with their named agents, and the indication-fit weighting.",
       False, None),

      # 15 — Parameters tab
      ("Parameters lists the modality list, the six axes, "
       "and the indication-fit weighting.",
       False, None),

      # 16 — Software tab
      ("Software pins the bake-off scorer and its version.",
       False, None),

      # 17 — Citations tab
      ("Citations: the semaglutide and survodutide MASH readouts behind the scoring.",
       False, None),

      # 18 — QC audit tab
      ("The QC audit — modalities scored and the top-modality check, "
       "each with threshold and result.",
       False, None),

      # 19 — center wrap-up
      ("Peptide injection first — the same ranking the field converged on. "
       "And the ambiguity card doubles as a 'what if BioMate isn't sure' lesson.",
       True, CLOSING_SPEED),
    ],
  },

  # ── T05 · Oncology modality triage — BCMA ────────────────────────────────
  "design_modtriage": {
    "label": "T05 · Oncology modality triage",
    "steps": [
      # 1 — center welcome
      ("You picked BCMA for oncology — now which modality? "
       "We'll score CAR-T, bispecific, ADC, and messenger-RNA.",
       True, CLOSING_SPEED),

      # 2 — expression drives the ranking
      ("BioMate profiles where BCMA is expressed first, "
       "because that weights everything after it "
       "— a restricted target favours cell therapies.",
       False, None),

      # 3 — Phase A, atlas profile
      ("Phase A: BCMA is restricted to plasma cells and some mature B cells, "
       "no critical-tissue hits — pointing at multiple myeloma.",
       False, None),

      # 4 — parameters, prefilled
      ("Each step opened pre-filled from your message "
       "— modalities set to 'all', from 'try all options'.",
       False, None),

      # 5 — provenance badges
      ("In Workflow settings, every value is badged "
       "— from your message, or computed in a phase.",
       False, None),

      # 6 — QC gates
      ("Each phase has an editable QC gate; "
       "the atlas-safety gate cleared the off-tumor risk here.",
       False, None),

      # 7 — outputs inline
      ("Outputs land as they're produced "
       "— the expression profile, the modality scores, the ranking.",
       False, None),

      # 8 — stop and resume
      ("A running phase can be stopped and resumed, "
       "with finished steps and outputs kept.",
       False, None),

      # 9 — ADC versus bispecific
      ("Teclistamab, a T-cell engager, is approved; "
       "belantamab mafodotin, an ADC, was withdrawn for eye toxicity "
       "— so bispecific scores second, ADC third with a payload caveat.",
       False, None),

      # 10 — chain complete
      ("All four phases done. "
       "The findings card lands and the panel flips to the After-run report.",
       False, None),

      # 11 — after-run report
      ("The After-run report opens — results first, methods next, audit last. "
       "We'll walk each tab.",
       False, None),

      # 12 — Findings tab
      ("Findings reads from the manifest "
       "— the modality ranking, BCMA's expression composition, and the atlas-safety bar.",
       False, None),

      # 13 — Outputs tab
      ("Outputs lists the modality ranking, the IHC follow-up panel, "
       "and the composite ranking. View or download all.",
       False, None),

      # 14 — Methods tab
      ("Methods is paste-ready "
       "— the atlas profile, the CAR-T rationale, "
       "and the ADC-versus-engager evaluation.",
       False, None),

      # 15 — Parameters tab
      ("Parameters lists the atlas source, the precedents per modality, "
       "and the indication-fit weighting.",
       False, None),

      # 16 — Software tab
      ("Software pins the pan-modality scorer and its version.",
       False, None),

      # 17 — Citations tab
      ("Citations: the ide-cel and teclistamab readouts behind the ranking.",
       False, None),

      # 18 — QC audit tab
      ("The QC audit — atlas safety, off-tumor risk, and the top-modality check, "
       "each with threshold and result.",
       False, None),

      # 19 — center wrap-up
      ("CAR-T first — the place ide-cel and cilta-cel landed "
       "— and the whole BCMA landscape scored from a single sentence.",
       True, CLOSING_SPEED),
    ],
  },

  # ── Seven-Domain Tutorial Package — T1–T7 ────────────────────────────────────
  # manualStream tours: Beat 1 = welcome (center), Beats 2–7 = tape sections,
  # Beat 8 = wrap (center). 8 steps per tutorial.

  "tut_rnaseq": {
    "label": "T1 — Bulk RNA-seq DE + GSEA (ERCC truth)",
    "steps": [
      # 1 — Beat 1 · Welcome, centered
      ("This is the bulk RNA-seq tutorial. One plain-English request becomes a real three-step pipeline "
       "— alignment, differential expression, gene-set enrichment — and we score the result against a "
       "spike-in truth set at the end. Fully driven for you.",
       True, CLOSING_SPEED),

      # 2 — Beat 2 · Section 1 · Understanding the request
      ("BioMate routes the request to the bulk RNA-seq differential-expression chain — alignment and "
       "quantification, then differential abundance, then clusterProfiler. Inputs land prefilled from "
       "the gold dataset — GSE49712, GRCh38, contrast B-versus-A.",
       False, None),

      # 3 — Beat 3 · Section 2 · Choosing the approach
      ("Here's why this dataset. GSE49712 is the SEQC benchmark: samples A and B carry ERCC spike-ins "
       "at four known ratios, so the spike-in transcripts are a built-in ground truth. DESeq2 is the "
       "right model — raw integer counts — and those spike-ins let us measure truth recovery at the end, "
       "not just render a volcano plot.",
       False, None),

      # 4 — Beat 4 · Section 3 · Phase B + QC
      ("The chain runs phase by phase. Phase B aligns and quantifies — STAR alignment, Salmon "
       "quantification. MultiQC enforces two gates across all ten samples: uniquely-mapped at or above "
       "seventy percent, and Salmon mapping at or above seventy percent. Mean uniquely-mapped comes in "
       "at eighty-seven percent — green.",
       False, None),

      # 5 — Beat 5 · Phase C + Phase D
      ("Phase C runs DESeq2 on the B-versus-A contrast. The sample-distance heatmap splits cleanly into "
       "two clusters — A and B are separable. Eighty-four-hundred-and-twenty-seven differentially-expressed "
       "genes at five-percent FDR. Phase D is the gene-set enrichment — GO, KEGG and Reactome — and the "
       "top hit is cell cycle, adjusted-p of one-point-two times ten-to-the-minus-twelve.",
       False, None),

      # 6 — Beat 6 · Phase E · validate
      ("Phase E is the part that makes this a benchmark, not a demo. The validator joins the DE table to "
       "the ERCC ground-truth ratios and checks the sign of every spike-in's fold-change. "
       "Ninety-two-point-one percent of ERCC transcripts recover the correct direction — above the "
       "ninety-percent target — with an AUC of zero-point-nine-seven.",
       False, None),

      # 7 — Beat 7 · Section 4 · Findings card
      ("The Findings card lands inline. Eighty-four-hundred DE genes; ERCC truth recovery "
       "ninety-two-point-one percent; AUC zero-point-nine-seven; top pathway cell cycle. This reproduces "
       "the SEQC/MAQC-III result published in Nature Biotechnology — the screen states the validated "
       "number out loud.",
       False, None),

      # 8 — Beat 8 · Wrap, centered
      ("Request to validated result, end to end. Hover any why anchor on the earlier lines to see the "
       "rationale behind each step. Next up — the single-cell tutorial.",
       True, CLOSING_SPEED),
    ],
  },

  "tut_scrna": {
    "label": "T2 — scRNA-seq PBMC → annotate (Azimuth)",
    "steps": [
      # 1 — Beat 1 · Welcome, centered
      ("The single-cell tutorial. QC, normalize, integrate, cluster, annotate — and then score the "
       "annotations against an independent reference. Watch how BioMate handles the two steps that have "
       "nothing to do on a single-batch dataset.",
       True, CLOSING_SPEED),

      # 2 — Beat 2 · Section 1 · Understanding the request
      ("BioMate routes to the single-cell multimodal chain: QC and normalize, Harmony integration, "
       "then cluster and annotate. The input is the 10x PBMC ten-thousand v3 filtered matrix — "
       "one donor, one condition. Single batch.",
       False, None),

      # 3 — Beat 3 · Section 2 · Choosing the approach
      ("That single batch matters. Harmony integration has one batch to integrate, so it runs as an "
       "identity pass-through. And the Milo differential-abundance step has no condition to contrast. "
       "BioMate keeps Milo in the plan but surfaces it as an advisory skip — not silently dropped, not "
       "faked on a degenerate design. The demo stays honest about which steps did real work.",
       False, None),

      # 4 — Beat 4 · Section 3 · Phase A + B + QC
      ("Phase A loads the matrix — ten-thousand-one-hundred-ninety-four cells by thirty-six-thousand "
       "genes. Phase B runs Scrublet for doublets and scran normalization. Three QC gates pass: doublet "
       "rate one-point-six percent, median eighteen-hundred-ninety-two genes per cell, median "
       "mitochondrial eight-point-four percent. A hundred-and-fifty-nine doublets removed.",
       False, None),

      # 5 — Beat 5 · Phase C + D + Milo advisory
      ("Phase C — Harmony, the identity pass-through, as promised. Phase D clusters with Leiden at "
       "resolution zero-point-six — eleven clusters — then reference-maps them with Azimuth to seven "
       "PBMC lineages. And there's the Milo line: an amber advisory, skipped on a single condition, "
       "not a failure.",
       False, None),

      # 6 — Beat 6 · Phase E · validate
      ("Phase E scores the labels. The validator re-maps the final object with Azimuth and computes "
       "macro-F1 across the seven lineages: zero-point-eight-nine, above the zero-point-eight-five "
       "target. The labels match an independent reference — not just internal cluster structure.",
       False, None),

      # 7 — Beat 7 · Section 4 · Findings card
      ("Findings: ninety-eight-hundred-forty-one cells across seven cell types; macro-F1 "
       "zero-point-eight-nine versus Azimuth; Milo skipped, single condition. The annotation "
       "reproduces the PBMC reference from Hao and colleagues in Cell.",
       False, None),

      # 8 — Beat 8 · Wrap, centered
      ("A clean single-cell workup that's honest about its degenerate steps. "
       "Next, germline variant calling against a gold-standard genome.",
       True, CLOSING_SPEED),
    ],
  },

  "tut_variant": {
    "label": "T3 — Germline variants · GIAB HG002 chr20",
    "steps": [
      # 1 — Beat 1 · Welcome, centered
      ("Germline variant calling. We call, annotate and filter variants — then benchmark the call set "
       "against a community gold-standard truth genome with hap.py. "
       "This is the most rigorous validation of the seven.",
       True, CLOSING_SPEED),

      # 2 — Beat 2 · Section 1 · Understanding the request
      ("BioMate routes to the variant-annotation chain: call, then annotate, then filter. The dataset "
       "is GIAB HG002 — the Genome-in-a-Bottle reference sample — restricted to chromosome twenty "
       "for the demo.",
       False, None),

      # 3 — Beat 3 · Section 2 · Choosing the approach
      ("Why HG002? It ships a version-four-point-two-point-one high-confidence VCF and BED — a "
       "community gold standard. Calling with both DeepVariant and GATK HaplotypeCaller and taking "
       "the consensus lets hap.py score SNV and indel F1 against that truth, restricted to the "
       "high-confidence regions where the answer is actually known.",
       False, None),

      # 4 — Beat 4 · Section 3 · Phase B + QC
      ("Phase B calls germline variants — DeepVariant plus GATK HaplotypeCaller on chromosome twenty. "
       "Three QC gates confirm the call set is well-behaved before we trust it: mean coverage "
       "thirty-four-X, Ti-over-Tv two-point-zero-four, het-over-hom one-point-six-two. "
       "A hundred-and-nine-thousand-eight-hundred-seventy-three variants pass.",
       False, None),

      # 5 — Beat 5 · Phase C + D
      ("Phase C annotates consequences against the human transcript database. Phase D filters to coding "
       "consequences with a gnomAD allele-frequency at or below one percent — trimming common population "
       "variants down to the set worth reporting.",
       False, None),

      # 6 — Beat 6 · Phase E · validate
      ("Phase E runs hap.py against the GIAB truth VCF, inside the high-confidence BED. SNV F1 "
       "zero-point-nine-nine-four, against a target of zero-point-nine-nine. Indel F1 "
       "zero-point-nine-six-two, against zero-point-nine-five. Both above target.",
       False, None),

      # 7 — Beat 7 · Section 4 · Findings card
      ("Findings: chromosome twenty, SNV F1 zero-point-nine-nine-four, indel F1 "
       "zero-point-nine-six-two versus GIAB. A hundred-and-nine-thousand pass variants; Ti-over-Tv "
       "and het-over-hom both in range. The chain reproduces the GIAB benchmark.",
       False, None),

      # 8 — Beat 8 · Wrap, centered
      ("A benchmarked variant call set with every QC gate green. "
       "Next — ChIP-seq peaks, validated against ENCODE.",
       True, CLOSING_SPEED),
    ],
  },

  "tut_chipseq": {
    "label": "T4 — ChIP-seq K562 H3K27ac → enrichment",
    "steps": [
      # 1 — Beat 1 · Welcome, centered
      ("The ChIP-seq tutorial. Call peaks, annotate them, run pathway enrichment — and then check "
       "whether the call set reproduces the ENCODE consensus for the same biosample. "
       "Validation as reproducibility, not just a peak count.",
       True, CLOSING_SPEED),

      # 2 — Beat 2 · Section 1 · Understanding the request
      ("BioMate routes to the ChIP-seq annotation chain: MACS2 peaks, then ChIPseeker, then "
       "clusterProfiler. The dataset is ENCODE K562 H3K27-acetyl — signal track ENCFF "
       "three-oh-one-T-V-L, input ENCFF zero-three-eight-F-K-Y.",
       False, None),

      # 3 — Beat 3 · Section 2 · Choosing the approach
      ("K562 H3K27-acetyl is an active histone mark with an ENCODE consensus narrowPeak for this exact "
       "biosample. So we call peaks with MACS2, then validate by overlapping our called set against "
       "that consensus. The question becomes: did we recover the published call set — a far stronger "
       "test than just finding a plausible number of peaks.",
       False, None),

      # 4 — Beat 4 · Section 3 · Phase B + QC
      ("Phase B — MACS2 narrow peak calling at q-value zero-point-zero-one, against the matched input. "
       "Three quality gates pass: FRIP zero-point-two-seven, NSC one-point-one-eight, and "
       "forty-seven-thousand-three-hundred-thirty-one peaks — inside the expected "
       "twenty-five-to-eighty-thousand window for this mark.",
       False, None),

      # 5 — Beat 5 · Phase C + D
      ("Phase C annotates with ChIPseeker, TSS window minus-three-thousand to three-thousand on "
       "hg-thirty-eight — about forty percent of peaks are promoter-proximal. Phase D runs GO "
       "Biological Process enrichment; the top term is regulation of transcription by RNA Pol Two, "
       "adjusted-p two-point-eight times ten-to-the-minus-thirty.",
       False, None),

      # 6 — Beat 6 · Phase E · validate
      ("Phase E intersects the called peaks with the ENCODE consensus narrowPeak. Eighty-three-point-four "
       "percent of our peaks overlap the consensus — above the eighty-percent target. "
       "The call set reproduces ENCODE.",
       False, None),

      # 7 — Beat 7 · Section 4 · Findings card
      ("Findings: forty-seven-thousand-three-hundred-thirty-one H3K27-acetyl peaks; "
       "eighty-three-point-four percent overlap the ENCODE consensus; FRIP and NSC green; "
       "top GO term transcription by RNA Pol Two.",
       False, None),

      # 8 — Beat 8 · Wrap, centered
      ("Peaks called, annotated, enriched — and reproduced against ENCODE. "
       "Next, label-free proteomics with a spike-in truth set.",
       True, CLOSING_SPEED),
    ],
  },

  "tut_proteomics": {
    "label": "T5 — Proteomics LFQ · UPS1 spike-in",
    "steps": [
      # 1 — Beat 1 · Welcome, centered
      ("The proteomics tutorial. Label-free quantification, then differential expression — on a "
       "spike-in design that gives us both known positives and known negatives, so we can score "
       "recall and the false-positive rate.",
       True, CLOSING_SPEED),

      # 2 — Beat 2 · Section 1 · Understanding the request
      ("BioMate routes to the proteomics DE chain: MSnBase for label-free quantification, then limma "
       "for the differential test. The dataset is ProteomeXchange P-X-D-zero-zero-two-nine-five-two "
       "— UPS1 standards spiked into yeast lysate at known ratios.",
       False, None),

      # 3 — Beat 3 · Section 2 · Choosing the approach
      ("The spike-in is the whole point. The forty-eight UPS1 proteins are known to be differentially "
       "expressed; the yeast background is known not to be. So I can measure recall — how many UPS1 "
       "we recover — and the false-positive rate on the yeast background. limma with eBayes and "
       "Benjamini-Hochberg adjustment is the standard moderated test for label-free quant.",
       False, None),

      # 4 — Beat 4 · Section 3 · Phase A–C + QC
      ("Phase A loads the mzML files. Phase B does feature detection and retention-time alignment "
       "— identification rate seventy-one percent, above the sixty-percent gate. Phase C rolls "
       "peptides up to protein quantities; median replicate C-V eleven percent, missingness "
       "fourteen percent. Both gates green.",
       False, None),

      # 5 — Beat 5 · Phase D
      ("Phase D is the limma test — eBayes moderation on the high-versus-low concentration contrast, "
       "Benjamini-Hochberg adjusted, with a log-fold-change threshold of one. This is where the UPS1 "
       "proteins should separate from the yeast background.",
       False, None),

      # 6 — Beat 6 · Phase E · validate
      ("Phase E scores against the truth. Forty-two of the forty-eight UPS1 proteins recovered at "
       "five-percent FDR — eighty-seven-point-five percent, above the eighty-percent target. And the "
       "yeast false-positive rate is three-point-one percent, under the five-percent ceiling.",
       False, None),

      # 7 — Beat 7 · Section 4 · Findings card
      ("Findings: forty-two of forty-eight UPS1 recovered, eighty-seven-point-five percent; yeast "
       "F-P-R three-point-one percent; identification rate seventy-one, median C-V eleven. "
       "This reproduces the MaxLFQ benchmark from Cox and colleagues.",
       False, None),

      # 8 — Beat 8 · Wrap, centered
      ("Recall on the spike-in, false positives on the background — both inside target. "
       "Next, recovering genomes from a metagenome.",
       True, CLOSING_SPEED),
    ],
  },

  "tut_metagenome": {
    "label": "T6 — Metagenomics → MAGs (CAMI II)",
    "steps": [
      # 1 — Beat 1 · Welcome, centered
      ("The metagenomics tutorial. We recover metagenome-assembled genomes — MAGs — from a shotgun "
       "community: bin the contigs, quality-screen the bins, assign taxonomy. And because this is "
       "a simulated community, we can score recovery against the known answer.",
       True, CLOSING_SPEED),

      # 2 — Beat 2 · Section 1 · Understanding the request
      ("BioMate routes to the shotgun-metagenomics-to-MAG chain: CONCOCT binning, MMseqs2 taxonomy, "
       "PathoStat. The dataset is the CAMI Two low-complexity gut subset — five samples — "
       "starting from assembled contigs.",
       False, None),

      # 3 — Beat 3 · Section 2 · Choosing the approach
      ("CAMI Two ships gold-standard binning and per-genome taxonomy for every source genome, so MAG "
       "recovery is a measurable number. CONCOCT bins the contigs by coverage and composition, "
       "CheckM2 keeps only high-quality MAGs — at least eighty percent complete, at most five percent "
       "contaminated — and AMBER scores recovery against the gold mapping.",
       False, None),

      # 4 — Beat 4 · Section 3 · Phase B + C + QC
      ("Phase B — CONCOCT bins the contigs, minimum length two-thousand: thirty-eight bins. Phase C "
       "is the quality screen. CheckM2 estimates completeness and contamination, and keeps twenty-seven "
       "of the thirty-eight bins as high-quality MAGs that clear the thresholds.",
       False, None),

      # 5 — Beat 5 · Phase D
      ("Phase D assigns taxonomy with MMseqs2 — genus rank for eighty-nine percent of bins, above "
       "the seventy-percent gate. Phase E summarizes differential abundance across the five samples "
       "with PathoStat.",
       False, None),

      # 6 — Beat 6 · Phase E · validate
      ("Then AMBER scores recovery against the CAMI gold binning. Seventy-one percent of the reference "
       "genomes are recovered as high-quality MAGs — above the seventy-percent target — with an AMBER "
       "bin-level F1 of zero-point-seven-four.",
       False, None),

      # 7 — Beat 7 · Section 4 · Findings card
      ("Findings: thirty-eight MAGs, twenty-seven high-quality; seventy-one percent CAMI Two recovery; "
       "taxonomy on eighty-nine percent of bins. This reproduces the CAMI Two benchmark from Meyer "
       "and colleagues in Nature Methods.",
       False, None),

      # 8 — Beat 8 · Wrap, centered
      ("Genomes recovered and scored against a known community. One left — untargeted metabolomics.",
       True, CLOSING_SPEED),
    ],
  },

  "tut_metabolomics": {
    "label": "T7 — Metabolomics consensus (MTBLS136)",
    "steps": [
      # 1 — Beat 1 · Welcome, centered
      ("The metabolomics tutorial, and the last of the seven. Untargeted LC-MS: pick peaks, annotate "
       "them, then take a consensus signature across three classifiers — and score it against a "
       "published biomarker list.",
       True, CLOSING_SPEED),

      # 2 — Beat 2 · Section 1 · Understanding the request
      ("BioMate routes to the LC-MS consensus chain: X-C-M-S for peak picking, CAMERA for annotation, "
       "biosigner for consensus feature selection. The dataset is MetaboLights M-T-B-L-S-one-thirty-six "
       "— the Thévenot twenty-fifteen urine study — with gender as the phenotype.",
       False, None),

      # 3 — Beat 3 · Section 2 · Choosing the approach
      ("biosigner runs three classifiers — PLS-DA, random forest and SVM — and keeps only the features "
       "all three agree on. That's a more robust signature than any single model. And MTBLS136 has a "
       "published list of gender-discriminating steroid metabolites, so we can score recall of that "
       "signature at the end.",
       False, None),

      # 4 — Beat 4 · Section 3 · Phase B + QC
      ("Phase B — X-C-M-S centWave peak picking and retention-time alignment. Two gates pass: median "
       "QC-sample C-V fourteen percent, under thirty; and eighty-nine-hundred-forty peaks, inside the "
       "three-to-fifteen-thousand window for urine LC-MS.",
       False, None),

      # 5 — Beat 5 · Phase C + D
      ("Phase C — CAMERA groups isotopes and adducts down to fifty-four-hundred-twelve features. "
       "Phase D is the biosigner consensus across PLS-DA, random forest and SVM: twenty-three features "
       "survive in all three, at a cross-validated accuracy of zero-point-eight-three — above the "
       "zero-point-seven-zero gate.",
       False, None),

      # 6 — Beat 6 · Phase E · validate
      ("Phase E matches the consensus features to the published gender biomarkers by mass-to-charge "
       "and retention time. Nine of the twelve published features are recovered — seventy-five percent, "
       "above the seventy-percent target.",
       False, None),

      # 7 — Beat 7 · Section 4 · Findings card
      ("Findings: nine of twelve published gender biomarkers recovered, seventy-five percent; "
       "twenty-three consensus features; C-V accuracy zero-point-eight-three. This reproduces the "
       "Thévenot twenty-fifteen signature — steroid metabolites like testosterone glucuronide and "
       "androsterone sulfate.",
       False, None),

      # 8 — Beat 8 · Wrap, centered
      ("That's all seven domains — each one a real chain, a gold-standard dataset, and a validated "
       "number on screen. Pick any tutorial from the Tutorial menu to replay it.",
       True, CLOSING_SPEED),
    ],
  },

  # ── Method-integration pilots — Z01, Z02, ZZ01, ZZ02, L01 ───────────────────
  # Same manualStream pattern as T1–T7: 1 centered loading step in Tour.jsx,
  # tape auto-plays. 3-minute condensed cuts from Integration Tutorial Narratives.md.

  "int_torchgwas": {
    "label": "Z01 — TorchGWAS · UDIP brain phenotypes",
    "steps": [
      # 1 — Welcome, centered
      ("Image-genetics G-W-A-S used to mean weeks of Slurm scripts. Here it's 256 brain-image "
       "phenotypes against nine million variants on one G-P-U node — a published method, run on new data.",
       True, CLOSING_SPEED),

      # 2 — Routed to the image-genetics chain
      ("BioMate reads UDIP, Torch G-W-A-S and UK Biobank, and routes to the image-genetics chain — "
       "four phases: phenotype QC, kernel and ancestry, the G-P-U scan, and the loci report.",
       False, None),

      # 3 — A published method, wired as a chain
      ("The 256 features come from an unsupervised vision transformer on UK Biobank brain scans. "
       "Parameters prefill — ancestry European, genome-wide threshold, twelve covariates — and only "
       "the phenotype path needs confirming.",
       False, None),

      # 4 — Phase A running, phenotype QC
      ("Execution starts and the active phase auto-expands. The 256 features are rank-normalised "
       "and provenance-checked before any model runs.",
       False, None),

      # 5 — Phase C, 256 LMMs on the GPU
      ("Kernel and ancestry kept 41,200 European-ancestry samples. Phase C then fits one linear "
       "mixed model per phenotype — 256 by nine million variants, about 87 G-P-U minutes on a single A100.",
       False, None),

      # 6 — Chain complete
      ("All four phases done. The chat drops a findings card and the panel flips to the After-run report.",
       False, None),

      # 7 — Findings
      ("Findings: 1,142 genome-wide loci, eighteen novel against the G-W-A-S Catalog. The top locus "
       "sits on the H-F-E H-L-A region — the paper's headline. Every number reads from the run manifest.",
       False, None),

      # 8 — Outputs
      ("Outputs lists every file — the loci report, the summary-statistics parquet, the Manhattan plot. "
       "View previews inline; download grabs one or all.",
       False, None),

      # 9 — Open in a live kernel
      ("The outputs don't have to end in a download — BioMate spins up a live Jupyter or RStudio "
       "session with the loci report and summary statistics mounted, ready for a custom locus zoom.",
       False, None),

      # 10 — Methods
      ("Methods is paste-ready prose — the vision-transformer phenotypes, the ancestry restriction, "
       "the per-phenotype mixed model, clumping, and the novel-versus-Catalog comparison, with versions "
       "and parameters.",
       False, None),

      # 11 — Wrap-up, centered
      ("A published image-genetics method, run from one chat prompt to 1,142 loci — "
       "with the published H-F-E H-L-A hit recovered.",
       True, CLOSING_SPEED),
    ],
  },

  "int_fda_screen": {
    "label": "Z02 — Folding-Docking-Affinity · EGFR T790M",
    "steps": [
      # 1 — Welcome, centered
      ("Lead-prioritisation usually means three teams and a month. Here we fold a target, "
       "dock a thousand-compound library, and rank with calibrated uncertainty — using one published model.",
       True, CLOSING_SPEED),

      # 2 — Routed to the FDA chain
      ("BioMate parses EGFR T790M, a thousand compounds, and an uncertainty requirement, and routes "
       "to the Folding-Docking-Affinity chain — fold, dock, affinity, rank.",
       False, None),

      # 3 — One published model, end to end
      ("Parameters prefill from the request — the target sequence, Vina as the docking engine, "
       "top twenty-five, uncertainty on. A docking-only pipeline couldn't return calibrated affinity; "
       "that's the value this chain adds.",
       False, None),

      # 4 — Phase A running, target fold
      ("Phase A: E-S-M fold returns the kinase domain at a confidence of eighty-seven — above the "
       "eighty gate for docking. The gate passes and the run continues.",
       False, None),

      # 5 — Phase C, affinity with an error bar
      ("Phase C gives each docked complex a predicted affinity and a calibrated error bar. The model "
       "was trained on the DAVIS kinase benchmark, so the uncertainty is meaningful — and the ranking "
       "flags advance or hold by the lower band.",
       False, None),

      # 6 — Chain complete
      ("Fold, dock 1,024 ligands, calibrated affinity, ranked top twenty-five. The lead compound sits "
       "at a predicted p-K-d of seven-point-eight, flagged to advance.",
       False, None),

      # 7 — Findings
      ("Findings: the top twenty-five with uncertainty, the lead at p-K-d seven-point-eight. Median "
       "docking score minus six-point-seven across the library; the calibration error is reported as "
       "a finding.",
       False, None),

      # 8 — Outputs
      ("Outputs by phase — the folded structure, the docked poses, the affinity table, the ranked "
       "top twenty-five, and the ranking plot.",
       False, None),

      # 9 — Open in a live kernel
      ("Spin up a live Jupyter session with the affinity predictions and the ranked hits mounted — "
       "re-rank by a custom score or pull poses for the top hits, without leaving BioMate.",
       False, None),

      # 10 — QC audit
      ("QC audit shows the real gate — E-S-M fold confidence above eighty, observed eighty-seven. "
       "The affinity calibration is a finding, not a pass-fail gate, so it lives in Findings.",
       False, None),

      # 11 — Methods
      ("Methods, paste-ready — E-S-M fold target prep, Vina docking, the affinity head and its DAVIS "
       "calibration, and the advance-flag rule, with versions and parameters.",
       False, None),

      # 12 — Wrap-up, centered
      ("A published model, calibrated on a published benchmark, runnable from chat — and it pairs with "
       "the tumor-immunology chain for parallel small-molecule and immunotherapy rails.",
       True, CLOSING_SPEED),
    ],
  },

  "int_tumor_tcell": {
    "label": "ZZ01 — Tumor-reactive T-cell chain (3 tools)",
    "steps": [
      # 1 — Welcome, centered
      ("Three integrated tools, one prompt: find tumor-reactive T cells, annotate their state, "
       "and rank candidate neoantigens. This is BioMate's multi-tool chain composer running three "
       "tools in sequence.",
       True, CLOSING_SPEED),

      # 2 — Routed to the multi-tool chain
      ("Single-cell RNA, tumor-reactive, neoantigen and an H-L-A allele route to the multi-tool "
       "chain — three tools, nine phases: turep, then Scupa, then ImmuneApp.",
       False, None),

      # 3 — The composer wires three tools as one run
      ("The first tool's parameters land; the second and third auto-wire from upstream outputs, "
       "so you confirm once and the composer dispatches each tool in turn. Multi-tool integration "
       "is the headline here.",
       False, None),

      # 4 — Step 1 / Phase B, turep inference
      ("Step one, turep inference: forty-eight thousand cells scanned, 612 flagged tumor-reactive "
       "at a calibrated error of point-oh-three-eight. Its output auto-wires straight into Scupa.",
       False, None),

      # 5 — Step 2 / Phase B, Scupa polarization
      ("Step two, Scupa polarisation: 598 cells scored across exhausted, effector-memory and "
       "resident-memory states. The majority are exhausted — consistent with tumor-infiltrating "
       "lymphocytes in melanoma.",
       False, None),

      # 6 — Step 3 / Phase B, ImmuneApp MHC-I
      ("Step three, ImmuneApp: 1,840 candidate peptides narrowed to 147 binders, at a "
       "rank-percentile of two percent or better for the patient's H-L-A allele.",
       False, None),

      # 7 — Top neoantigen
      ("The top hit ranks at point-one-two percent — a known RAS-derived neoantigen, exactly the "
       "validated driver epitope this chain is built to surface.",
       False, None),

      # 8 — Chain complete
      ("612 tumor-reactive cells, 147 binders, one top neoantigen — from one prompt across three tools.",
       False, None),

      # 9 — Findings
      ("Findings read the funnel from the manifest — 612 tumor-reactive, 598 polarised, 147 binders, "
       "one top neoantigen. Per-tool calibration is reported here as findings.",
       False, None),

      # 10 — Outputs
      ("Outputs grouped by tool and phase — the tumor-reactive cells, the polarisation scores, "
       "the binders, the neoantigen ranking, and the binding heatmap.",
       False, None),

      # 11 — Open in CellxGene
      ("The H5AD export has an Open-in-CellxGene button — browse the 612 tumor-reactive cells and "
       "their expression live, or switch the tile to RStudio for the ranking tables.",
       False, None),

      # 12 — Methods
      ("Methods names all three tools — turep detection, Scupa polarisation, ImmuneApp prediction "
       "and ranking — with the cell counts, the calibration, and the H-L-A allele.",
       False, None),

      # 13 — Wrap-up, centered
      ("Three integrated tools, nine phases, one prompt — find, annotate, rank. "
       "Multi-tool integration is BioMate's specialty.",
       True, CLOSING_SPEED),
    ],
  },

  "int_scgwas": {
    "label": "ZZ02 — scGWAS · immune cell types",
    "steps": [
      # 1 — Welcome, centered
      ("Standard G-W-A-S tells you which variants matter. Single-cell G-W-A-S tells you which cell "
       "types they matter in. Here we light up Crohn's-disease variants in regulatory T cells — "
       "from one prompt.",
       True, CLOSING_SPEED),

      # 2 — Routed to the single-cell GWAS chain
      ("BioMate reads single-cell G-W-A-S, Crohn's and a gut atlas, and routes to the single-cell "
       "G-W-A-S chain — twelve traits, twenty-seven cell types, ten-thousand permutations prefilled.",
       False, None),

      # 3 — Which cell types, not just which variants
      ("Standard G-W-A-S returns risk variants; single-cell G-W-A-S integrates those summary statistics "
       "with the single-cell atlas to score per-cell-type enrichment. One prompt launches it on the "
       "G-P-U queue.",
       False, None),

      # 4 — Phase A, join + completeness gates
      ("Phase A joins the summary statistics to the atlas — the harmonised format is auto-detected. "
       "18,787 G-W-A-S genes loaded, 8,529 shared with the atlas, both real tool-emitted gates.",
       False, None),

      # 5 — Phase B, cell-type enrichment
      ("Phase B scores enrichment across twenty-five cell types with ten-thousand permutations — "
       "five pass a five-percent F-D-R. Crohn's lands most strongly on regulatory T cells.",
       False, None),

      # 6 — Chain complete
      ("Join, enrichment, report. The top hit is Crohn's disease in regulatory T cells — "
       "the published headline, from one prompt.",
       False, None),

      # 7 — Findings
      ("Findings: a trait-by-cell-type heatmap, five of twenty-five cell types passing F-D-R, "
       "Crohn's most enriched in regulatory T cells.",
       False, None),

      # 8 — Outputs
      ("Outputs — the gene scores, the enrichment table, the report, and the trait-by-cell-type "
       "heatmap. View previews; download grabs one or all.",
       False, None),

      # 9 — Open in a live kernel
      ("BioMate spins up a live RStudio or Jupyter session with the enrichment and gene-score "
       "tables mounted — re-plot the heatmap or test another trait, without leaving BioMate.",
       False, None),

      # 10 — QC audit
      ("QC audit shows the real tool-emitted gates — G-W-A-S genes loaded, cell types identified, "
       "and shared genes — each with threshold and observed value, parsed from the tool's output.",
       False, None),

      # 11 — Methods
      ("Methods, paste-ready — summary-statistics harmonisation and the atlas join, the "
       "permutation-based enrichment, and F-D-R thresholding, with gene counts and parameters.",
       False, None),

      # 12 — Wrap-up, centered
      ("Cell-type G-W-A-S resolution from one prompt — Crohn's in regulatory T cells, "
       "the published result.",
       True, CLOSING_SPEED),
    ],
  },

  "int_rare_disease": {
    "label": "L01 — Rare-disease multi-modal workup",
    "steps": [
      # 1 — Welcome, centered
      ("The rare-disease multi-modal pipeline — variant calls, expression outliers, splicing outliers "
       "— usually means three separate Nextflow runs you stitch yourself. Here it's one chat prompt.",
       True, CLOSING_SPEED),

      # 2 — Already a 5-step curated chain
      ("Rare-disease, whole-genome, OUTRIDER and FRASER route to the curated multi-modal workup — "
       "a five-step chain. Genome, the variant caller and both RNA-outlier tools prefill; only the "
       "sample sheet needs confirming.",
       False, None),

      # 3 — A curated multi-modal upstream, as one chain
      ("This is the established multi-modal upstream — sarek for variants, then RNA-seq and DROP "
       "for outliers — composed into one dispatch. The composer runs sarek first; the RNA steps "
       "wait for inputs.",
       False, None),

      # 4 — Phase A, sarek germline calling
      ("Phase A: sarek calls germline variants with HaplotypeCaller — transition-to-transversion "
       "two-oh-three, depth thirty-four-fold, d-b S-N-P overlap ninety-seven percent, all real "
       "tool-emitted gates.",
       False, None),

      # 5 — Phase D, OUTRIDER + FRASER
      ("Phase D: DROP runs OUTRIDER for aberrant expression and FRASER for aberrant splicing — "
       "the standard RNA-outlier pair. Eight expression outliers, five splicing outliers join the "
       "case report.",
       False, None),

      # 6 — Chain complete
      ("All five phases done — variants, annotation, RNA quant, RNA outliers, aggregation. "
       "One table: top variants, outlier genes, splicing events.",
       False, None),

      # 7 — Findings
      ("Findings, per case from the manifest — germline metrics, eight expression outliers, five "
       "splicing outliers, three ClinVar pathogenic variants — folded into one table.",
       False, None),

      # 8 — Outputs
      ("Outputs by phase — the annotated VCF, the gene counts, the OUTRIDER and FRASER results, "
       "and the unified case report. View previews; download grabs one or all.",
       False, None),

      # 9 — Open in a live kernel
      ("BioMate spins up a live RStudio session with the OUTRIDER and FRASER results mounted — "
       "cross-reference the outliers against the variant calls, or open the case report, without "
       "leaving BioMate.",
       False, None),

      # 10 — QC audit
      ("QC audit is the richest of any pilot — eight to ten tool-emitted gates across the chain: "
       "sarek's transition-to-transversion, depth and d-b S-N-P overlap, the annotation rate, the "
       "alignment and RNA metrics, and the DROP convergence checks.",
       False, None),

      # 11 — Methods
      ("Methods, paste-ready — sarek HaplotypeCaller, Ensembl V-E-P, RNA-seq with STAR-Salmon, "
       "DROP's OUTRIDER and FRASER, and case-report aggregation, with versions and parameters.",
       False, None),

      # 12 — Wrap-up, centered
      ("A curated multi-modal upstream, in one prompt, runnable on day one — same tools, "
       "with downstream variant ranking available next phase.",
       True, CLOSING_SPEED),
    ],
  },

  # ── DD01: MG stratification 3-turn conversational (tut_mg_stratification) — 21 steps ─
  # Updated content: QC gate checks run quality (not biology), ADMET auto-resolves from ChEMBL
  # Target ~185 s: shorter scripts to cut 37s from previous 222s run
  "tut_mg_stratification": {
    "label": "DD01 — MG stratification → complement enrichment → ADMET",
    "steps": [

      # 1 — Hook, centered (~17w)
      ("One question. BioMate reads the result and suggests the next step. "
       "Each message follows the science.",
       True, CLOSING_SPEED),

      # 2 — DESeq2: biology question → CFD (~14w)
      ("She asks what's dysregulated in M-G patients. "
       "Complement genes surface together — C-F-D strongest.",
       False, None),

      # 3 — Phase A params & outputs (~14w)
      ("The workflow panel shows parameters prefilled — design tilde condition, apeglm shrinkage. "
       "Output files appear inline.",
       False, None),

      # 4 — Phase A QC gate — run quality, not biology (~15w)
      ("QC gate: enough samples per group, dispersion converged. "
       "C-F-D is a biological finding, not the gate.",
       False, None),

      # 5 — BioMate suggests enrichGO (~14w)
      ("Complement genes appeared together, not as isolated hits. "
       "BioMate proposes enrichment testing. She agrees.",
       False, None),

      # 6 — enrichGO result: complement activation rank 1 (~14w)
      ("enrichGO runs on the DE gene list. The top-ranked term: complement activation — "
       "emerging from the data, not asserted.",
       False, None),

      # 7 — Phase B enrichment outputs (~13w)
      ("The enrichment table tops with complement activation — "
       "reproducing the published M-G signature from Tuzun and Christadoss.",
       False, None),

      # 8 — Phase B QC gate (~12w)
      ("Pathway QC gate: was anything enriched at all? "
       "Twenty-seven terms significant. Pass.",
       False, None),

      # 9 — BioMate suggests iptacopan via CFB (~15w)
      ("Factor B surfaces from the run itself — up-regulated, inside the enriched pathway. "
       "BioMate names iptacopan.",
       False, None),

      # 10 — ADMET auto-resolved from ChEMBL (~13w)
      ("BioMate resolves iptacopan from ChEMBL — no structure to paste. "
       "ADMET-AI screens fifteen endpoints.",
       False, None),

      # 11 — Phase C three ADMET safety gates (~15w)
      ("Three ADMET safety gates evaluated — hERG, Caco-two permeability, CYP3A4 inhibition. "
       "All pass their thresholds. All green.",
       False, None),

      # 12 — Findings card lands (~15w)
      ("A findings card appears in chat and the After run report panel opens automatically — both in sync.",
       False, None),

      # 13 — Seven-tab report (~13w)
      ("Seven tabs — Findings, Outputs, Methods, Parameters, Software, Citations, QC audit. "
       "Every number from the run.",
       False, None),

      # 14 — Findings headline (~15w)
      ("The Findings tab shows a headline verdict, grounded bullets, and key figures straight from the run.",
       False, None),

      # 15 — Outputs tab (~13w)
      ("Every output file, grouped by phase. "
       "View previews inline; download pulls the artifact.",
       False, None),

      # 16 — Interactive panel (~12w)
      ("Open any output live — DE results in R-Studio, AnnData in CellxGene.",
       False, None),

      # 17 — Methods tab (~12w)
      ("Paste-ready methods prose — DESeq2, apeglm, enrichGO, ADMET-AI — "
       "with inline citations.",
       False, None),

      # 18 — Parameters tab (~12w)
      ("Every parameter used per phase — design formula, FDR cutoff, shrinkage. "
       "Fully reproducible.",
       False, None),

      # 19 — Software tab (~11w)
      ("Each package pinned to a version — DESeq2, clusterProfiler, R, ggplot2.",
       False, None),

      # 20 — Citations tab (~15w)
      ("References auto-generated for every tool and publication cited in the run. Ready to drop into a manuscript.",
       False, None),

      # 21 — QC audit, closing (~17w)
      ("All gates in one table — threshold, observed, result. "
       "From one question to a drug candidate, three turns. This is BioMate.",
       True, CLOSING_SPEED),
    ],
  },

  # ── DD02: MG full pipeline one long query (tut_mg_oneshot) — 8 steps ─────────
  # Target ~180 s: 8 steps × ~33 words @ 1.10 speed ≈ 21 s/clip × 8 = 168 s + ~10 s gaps
  "tut_mg_oneshot": {
    "label": "DD02 — MG full pipeline (one long query)",
    "steps": [

      # 1 — Hook, centered (~30w)
      ("Same science — asked all at once. "
       "Rather than following each result turn by turn, the scientist puts the full task in one message. "
       "BioMate plans the entire pipeline and runs it end to end.",
       True, CLOSING_SPEED),

      # 2 — Plan committed up front (~35w)
      ("One request covers the full chain — DESeq2 on the GEO dataset, "
       "pathway enrichment on the DE list, ChEMBL lookup for the drug candidate, and ADMET screening. "
       "BioMate commits the whole plan at once, before any results are seen. "
       "Contrast the conversational run, where each phase only emerged after reviewing the last.",
       False, None),

      # 3 — All phase cards visible immediately (~35w)
      ("All three phase cards appear from the start, with parameters already filled — "
       "Differential Expression with the design formula and apeglm shrinkage, "
       "Pathway Enrichment targeting GO Biological Process, "
       "and ADMET Screening ready for the resolved drug. "
       "Nothing is revealed turn by turn; the user committed everything up front.",
       False, None),

      # 4 — Phase A DE result (~34w)
      ("Phase A: DESeq2 runs first. Three hundred and twelve genes reach significance at FDR 0.05. "
       "Complement genes dominate the top of the up-regulated list — "
       "C-F-D at log-two fold change 2.84, with C3, CFB, and C5AR1 close behind. "
       "The QC gate scores six of six complement targets.",
       False, None),

      # 5 — Auto-continues, enrichGO result (~33w)
      ("No user turn between phases. BioMate narrates 'continuing as planned' "
       "and moves directly into enrichGO. "
       "Complement activation ranks first — the same pathway targeted by the three approved M-G drugs. "
       "Twenty-seven terms reach significance in the biological process ontology.",
       False, None),

      # 6 — Phase C: target from run, drug from ChEMBL (~34w)
      ("Factor B surfaces from the run's own results — it is up-regulated in the DE table "
       "and sits inside the enriched complement activation pathway. "
       "BioMate resolves iptacopan from ChEMBL, no structure to paste. "
       "ADMET-AI screens fifteen endpoints; three safety gates — hERG, Caco-two, CYP3A4 — all pass.",
       False, None),

      # 7 — Single findings card, complete (~33w)
      ("Because it ran as a batch, the findings card lands once and is complete from the start — "
       "C-F-D as the top driver, complement activation as the pathway, "
       "Factor B as the target, iptacopan as the candidate. "
       "ADMET pass on all three safety gates, on GSE227835 with ten M-G and ten healthy controls.",
       False, None),

      # 8 — Full report, closing — LaTeX removed per product spec (~26w)
      ("Seven tabs, all present at once — Findings, Outputs, Methods, Parameters, "
       "Software, Citations, and QC audit. "
       "Download the full report as DOCX or Markdown. "
       "One query. One complete pipeline. This is BioMate.",
       True, CLOSING_SPEED),
    ],
  },

}


# ── ElevenLabs helpers ────────────────────────────────────────────────────────

def audio_duration_ms(path):
    r = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "json", path],
        capture_output=True, text=True)
    return int(float(json.loads(r.stdout)["format"]["duration"]) * 1000)

def generate_clip(text, speed, outpath):
    url = f"https://api.elevenlabs.io/v1/text-to-speech/{VOICE_ID}"
    payload = {
        "text": text,
        "model_id": "eleven_multilingual_v2",
        "voice_settings": {
            "stability": 0.45,
            "similarity_boost": 0.80,
            "style": 0.20,
            "use_speaker_boost": True,
        },
        "speed": speed,
    }
    resp = requests.post(url,
        headers={"xi-api-key": API_KEY, "Content-Type": "application/json"},
        json=payload)
    resp.raise_for_status()
    with open(outpath, "wb") as f:
        f.write(resp.content)
    return outpath

def make_silence(ms, outpath):
    subprocess.run([
        "ffmpeg", "-y", "-f", "lavfi",
        "-i", "anullsrc=r=44100:cl=mono",
        "-t", str(ms / 1000), "-q:a", "2", outpath,
    ], capture_output=True, check=True)
    return outpath


# ── Per-tutorial generation ───────────────────────────────────────────────────

def generate_tutorial(key, tutorial):
    label = tutorial["label"]
    steps = tutorial["steps"]
    out_dir = os.path.join(CLIPS, key)
    os.makedirs(out_dir, exist_ok=True)

    print(f"\n{'='*60}")
    print(f"  Tutorial: {label}  ({len(steps)} steps)")
    print(f"{'='*60}")

    timings = []
    segments = []

    for i, (text, is_center, spd_override) in enumerate(steps, start=1):
        speed = spd_override if spd_override is not None else DEFAULT_SPEED
        clip_path = os.path.join(out_dir, f"step_{i:02d}.mp3")

        short = text[:60].replace("\n","") + ("…" if len(text) > 60 else "")
        print(f"  Step {i:2d}/{len(steps)}: {short!r}")

        generate_clip(text, speed, clip_path)
        clip_ms = audio_duration_ms(clip_path)

        gap_ms = CENTER_GAP_MS if is_center else SPOT_GAP_MS
        hold_ms = clip_ms + gap_ms

        print(f"           clip={clip_ms}ms  hold={hold_ms}ms  speed={speed}")
        timings.append({"step": i, "clip_ms": clip_ms, "hold_ms": hold_ms,
                        "gap_ms": gap_ms, "is_center": is_center})
        segments.append(clip_path)

        # Silence between steps
        sil = os.path.join(out_dir, f"sil_{i:02d}.mp3")
        make_silence(gap_ms, sil)
        segments.append(sil)

    # Save timings JSON
    total_ms = sum(t["hold_ms"] for t in timings)
    timings_data = {"steps": timings, "total_ms": total_ms}
    json_path = os.path.join(out_dir, "timings.json")
    with open(json_path, "w") as f:
        json.dump(timings_data, f, indent=2)

    # Build combined MP3 (remove trailing silence segment)
    concat_path = os.path.join(out_dir, "concat.txt")
    with open(concat_path, "w") as f:
        for s in segments[:-1]:   # drop the last silence
            f.write(f"file '{s}'\n")

    combined = os.path.join(out_dir, "combined.mp3")
    subprocess.run([
        "ffmpeg", "-y", "-f", "concat", "-safe", "0",
        "-i", concat_path,
        "-c:a", "libmp3lame", "-q:a", "2", combined,
    ], check=True, capture_output=True)

    dur_s = audio_duration_ms(combined) / 1000
    print(f"\n  → {combined}")
    print(f"  Total: {dur_s:.1f}s  ({len(steps)} steps)")
    return timings_data


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    only = None
    if "--only" in sys.argv:
        idx = sys.argv.index("--only")
        only = sys.argv[idx + 1] if idx + 1 < len(sys.argv) else None

    keys = [only] if only else list(TUTORIALS.keys())

    for key in keys:
        if key not in TUTORIALS:
            print(f"Unknown tutorial: {key}. Options: {list(TUTORIALS.keys())}")
            sys.exit(1)
        generate_tutorial(key, TUTORIALS[key])

    print("\nAll tutorials done!")

if __name__ == "__main__":
    main()
