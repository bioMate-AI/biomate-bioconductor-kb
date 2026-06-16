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

DEFAULT_SPEED   = 0.80
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

  # ── Bioconductor · DESeq2 chain (bioc-kb-routing) — 27 steps ────────────────
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

      # 7 — control: params prefilled and editable
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

      # 14 — shrink noisy fold-changes
      ("Before ranking, apeglm shrinks noisy low-count fold-changes toward zero, "
       "so enrichment isn't dominated by extremes.",
       False, None),

      # 15 — Phase E running, enrichment
      ("clusterProfiler's gseGO runs on the ranked list — "
       "top term, regulation of apoptotic process. "
       "Phase F renders the volcano, dot plot, and heatmap.",
       False, None),

      # 16 — chain complete (findings-chat spotlight)
      ("All six phases done — DESeq2, apeglm, clusterProfiler, EnhancedVolcano. "
       "Chat drops a findings card; the panel flips to the After-run report.",
       False, None),

      # 17 — after run, one structured report (results-links spotlight)
      ("The report has seven tabs in reading order — results first, methods and "
       "reproducibility next, audit last. The whole thing exports to one document.",
       False, None),

      # 18 — Findings tab
      ("Findings: the headline metric, a few bullets, and figures read straight "
       "from the manifest. Nothing is invented — uncited claims are tagged "
       "author judgment.",
       False, None),

      # 19 — Outputs tab
      ("Outputs lists every file by phase — the results object, volcano, "
       "GO dot plot, top-fifty heatmap. View previews inline; download grabs one or all.",
       False, None),

      # 20 — Open in RStudio (interactive-launcher spotlight)
      ("Download isn't the end. Every results object has an Open-in-RStudio button "
       "— a live R four-point-three session with DESeq2 loaded and your "
       "dataset pre-mounted.",
       False, None),

      # 21 — visualised, volcano plot (preview-modal spotlight)
      ("Clicking view on the volcano renders it inline — fold-change versus "
       "significance, up genes red, down blue. "
       "BioMate picks the viewer from the file type.",
       False, None),

      # 22 — Methods tab
      ("Methods is paragraph-form prose — tools, versions, exact parameters — "
       "written so a peer can replicate the run. "
       "Paste it straight into a manuscript.",
       False, None),

      # 23 — Parameters tab
      ("Parameters lists phase, step and value for everything the run touched "
       "— a ready supplementary table. "
       "Defaults, overrides and auto-loop tweaks are distinguished.",
       False, None),

      # 24 — Software tab
      ("Software pins every package version — DESeq2, apeglm, edgeR, "
       "clusterProfiler. With Parameters, it's the reproducibility baseline.",
       False, None),

      # 25 — Citations tab
      ("Citations auto-generates the reference list — Love twenty-fourteen, "
       "Zhu twenty-nineteen, Wu twenty-twenty-one, and more. "
       "Methods and Citations export together.",
       False, None),

      # 26 — QC audit tab
      ("QC audit logs every gate that fired — gene retention, size-factor range, "
       "replicate count — with threshold, observed value and action. "
       "Twenty-one CFR Part Eleven friendly.",
       False, None),

      # 27 — center wrap-up
      ("That's the full DESeq2 thread — match, route, run six phases, "
       "a seven-tab report, all from one request. "
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
