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

  # ── Bioconductor · DESeq2 chain (bioc-kb-routing) — 21 steps ────────────────
  # Voiceover sourced from src/BiocTours.jsx step bodies + the shared
  # afterRunSteps generator. JSX markup stripped, package / class names
  # spelled out for clarity (DESeqDataSet → "DeSeq Data Set", etc).
  # Audit notes from docs/20260610_BIOC_TUTORIAL_NARRATIVE_AUDIT.md:
  # D1 (step 3 disambig) needs a longer dwell — handled at the playwright
  # tour layer, not here, since this is just voiceover length.
  "bioc_kb": {
    "label": "Bioconductor · DESeq2 chain",
    "steps": [
      # 1 — center welcome
      ("We're going to run a Bioconductor differential expression analysis, "
       "end to end. BioMate matches your request to a curated workflow, "
       "routes each step to the right package, runs the six-phase chain, "
       "then hands you a full report. "
       "About three minutes — match, route, run, report.",
       True, CLOSING_SPEED),

      # 2 — spotlight: empty workflow panel
      ("BioMate embeds your request against the Bioconductor knowledge base. "
       "The panel stays empty for now — BioMate won't commit to a pipeline "
       "before the match is resolved.",
       False, None),

      # 3 — spotlight: disambiguation card (D1 — content-dense)
      ("Two curated chains scored close — a count-matrix DeSeq2 path at "
       "zero point seven one, and a fuller F-A-S-T-Q pipeline at zero point "
       "six six. Rather than guess, BioMate surfaces both with their scores. "
       "The top match is pre-selected, with a commit countdown.",
       False, None),

      # 4 — spotlight: phase list populates
      ("With bulk RNA-seq DeSeq2 chosen, the panel fills with its six phases. "
       "Q-C, normalise, D-E test, shrink, enrich, visualise. "
       "Only now does a pipeline exist; chat and panel track the same run.",
       False, None),

      # 5 — spotlight: reason block (routing)
      ("BioMate explains the choice. A raw integer count matrix calls for "
       "a negative-binomial model — DeSeq2 — not limma-voom, which expects "
       "continuous log-two intensities. "
       "The reasoning is grounded in the Love twenty-fourteen citation.",
       False, None),

      # 6 — spotlight: Phase A running
      ("Execution starts. The active phase auto-expands. "
       "edgeR's filterByExpr drops genes under ten counts. "
       "As each step finishes, its parameters and output files appear inline.",
       False, None),

      # 7 — spotlight: object handoff
      ("After normalisation, counts, metadata and size factors fold into one "
       "DeSeq Data Set. That object class is the contract every downstream "
       "DeSeq2 step reads from — typed handoffs all the way through.",
       False, None),

      # 8 — spotlight: Phase C running, DE testing
      ("The Wald test runs on design tilde condition. "
       "Two thousand eight hundred and forty-one genes pass at "
       "false discovery rate under zero point zero five. "
       "The result is a DeSeq Results table.",
       False, None),

      # 9 — spotlight: shrinkage explanation
      ("Before ranking, apeglm shrinks low-count fold-changes toward zero. "
       "The gene list feeding enrichment isn't dominated by noisy extremes. "
       "apeglm isn't a blind default; the reasoning block says why.",
       False, None),

      # 10 — spotlight: Phase E enrichment
      ("clusterProfiler's gseGO runs on the shrunk ranked list. "
       "Top GO term — regulation of apoptotic process. "
       "Phase F then renders the volcano plot, dot plot and heatmap.",
       False, None),

      # ── shared afterRunSteps (10 steps) ─────────────────────────────────────
      # 11 — center: chain complete card
      ("All six phases done — DeSeq2, apeglm, clusterProfiler, "
       "EnhancedVolcano. The chat drops a findings card and the panel "
       "flips to the after-run report. Next, we walk every tab.",
       True, None),

      # 12 — spotlight: after-run tabs overview
      ("Every completed run produces a structured report. "
       "Seven tabs — findings, outputs, methods, parameters, software, "
       "citations, and the Q-C audit. Findings first, raw artifacts next, "
       "then reproducibility, ending with audit.",
       False, None),

      # 13 — spotlight: Findings tab
      ("The findings tab. Headline metric, a few bullets, and figures read "
       "straight from the run manifest. "
       "Figures are data-driven — bars for top G-O terms, a stacked bar for "
       "D-E direction, a retention ring for gene filtering. "
       "No numbers are invented.",
       False, None),

      # 14 — spotlight: Outputs tab
      ("Outputs. One row per file, grouped by phase and step. "
       "DeSeq results, the volcano P-N-G, the G-O dot plot, the top fifty "
       "heatmap. View previews each file inline; download grabs one or all.",
       False, None),

      # 15 — spotlight: inline preview detour
      ("Clicking view on the volcano P-N-G renders it inline — "
       "log-two fold change versus negative log-ten adjusted p, "
       "up genes in red, down in blue, cutoff lines drawn. "
       "BioMate picks the volcano viewer from the file type.",
       False, None),

      # 16 — spotlight: Methods tab
      ("The methods tab. Paragraph-form prose you can paste straight into "
       "a manuscript — tools, versions, exact parameters, written so peers "
       "can replicate the DeSeq2 run.",
       False, None),

      # 17 — spotlight: Parameters tab
      ("Parameters. Phase, step, parameter, value — for everything the run "
       "touched, from filterByExpr thresholds to apeglm's shrinkage type. "
       "A ready supplementary table.",
       False, None),

      # 18 — spotlight: Software tab
      ("Software. Every package with its exact version — DeSeq2, apeglm, "
       "edgeR, clusterProfiler, EnhancedVolcano. Match these with the "
       "parameters tab and you reproduce the run.",
       False, None),

      # 19 — spotlight: Citations tab
      ("Citations. An auto-generated reference list — "
       "Love twenty-fourteen for DeSeq2, Zhu twenty-nineteen for apeglm, "
       "Wu twenty twenty-one for clusterProfiler. "
       "Methods and citations ship together in the download report export.",
       False, None),

      # 20 — spotlight: QC audit tab (D2 — strong claim now backed by the
      # rich panel shipped in commit 8050e6c3d on the BioMate side)
      ("The Q-C audit tab. Every gate that fired, with threshold, observed "
       "value, result, and action. A four-stat header summarises pass, "
       "auto-corrected, and manual interventions. "
       "Twenty-one C-F-R Part Eleven friendly, with chain of custody.",
       False, None),

      # 21 — center: wrap-up
      ("That's the full DeSeq2 thread. Match, route, run six phases, "
       "and a seven-tab report — all from one request. "
       "Try the scRNA-seq and methylation tutorials next: "
       "same agent, different science.",
       True, CLOSING_SPEED),
    ],
  },

  # ── Bioconductor · scRNA-seq → pseudobulk DE (bioc-sc-routing) — 19 steps ──
  # Sourced from src/BiocTours.jsx 'bioc-sc-routing'. Strips JSX markup,
  # spells package names phonetically (SingleCellExperiment → "single cell
  # experiment"). Centerpiece (step 8): the pseudobulk trap-and-fix beat
  # — extended dwell handled at the playwright tour layer.
  "bioc_sc": {
    "label": "Bioconductor · scRNA-seq chain",
    "steps": [
      # 1 — center welcome
      ("Same agent, a single-cell request. BioMate routes to the O-S-C-A "
       "stack, clusters and annotates in parallel, then runs condition "
       "differential expression the statistically correct way — pseudobulk. "
       "About three minutes — route, cluster, annotate, pseudobulk D-E, report.",
       True, CLOSING_SPEED),

      # 2 — spotlight: phase list with parallel branch
      ("Seven phases. Q-C, normalise, feature and P-C-A, cluster, "
       "markers and annotation in parallel, then pseudobulk D-E. "
       "Marker detection and annotation both read the clustered object, "
       "so they're grouped to run concurrently.",
       False, None),

      # 3 — spotlight: routed to OSCA
      ("BioMate works backward from the goal. Condition D-E with DeSeq2 "
       "means a single cell experiment with scran and scater — not Seurat — "
       "so the final pseudobulk step hands off with no lossy conversion. "
       "Routing is the whole object ecosystem, not just one tool.",
       False, None),

      # 4 — spotlight: Phase A cell QC
      ("Phase A. emptyDrops separates real cells from ambient barcodes. "
       "perCellQCMetrics flags high-mitochondrial and low-count cells. "
       "Nine thousand eight hundred and fourteen of twelve thousand four "
       "hundred and two cells retained.",
       False, None),

      # 5 — spotlight: one SCE throughout
      ("Q-C and normalisation fold into a single cell experiment carrying "
       "counts, log-counts, metadata, and size factors. Every step below — "
       "including the pseudobulk DeSeq2 — reads from this one object. "
       "Staying S-C-E-native avoids a lossy conversion at the end.",
       False, None),

      # 6 — spotlight: Phases B–D done, 11 clusters
      ("Normalisation, highly-variable-gene selection plus P-C-A, and "
       "graph-based clustering with buildSNNGraph plus Louvain are complete. "
       "Eleven clusters. The U-MAP is a picture, not the clustering — "
       "clusters come from the S-N-N graph.",
       False, None),

      # 7 — spotlight: parallel markers + annotation
      ("Phases E and F open together. scoreMarkers and SingleR — against "
       "the Human Primary Cell Atlas — both read the clustered object, "
       "so the engine fans them out and tracks the join. "
       "Independent steps run concurrently; dependent ones wait.",
       False, None),

      # 8 — spotlight: pseudobulk centerpiece (densest beat in the series)
      ("The key teaching beat. The Q-C block flags the trap — testing "
       "thousands of cells as replicates is pseudoreplication. The agent "
       "block gives the fix — aggregate to pseudobulk, so the six samples "
       "are the real replicates. Then DeSeq2 per cell type. "
       "The agent corrects the stats trap before running the test.",
       False, None),

      # ── shared afterRunSteps (10) ──────────────────────────────────────────
      # 9 — center: chain complete
      ("All seven phases done. Routed to O-S-C-A, clustered, annotated in "
       "parallel, then pseudobulk D-E. C-D-eight T cells are the strongest "
       "responder — two hundred and fourteen D-E genes on true replicates. "
       "Next, we walk every tab of the report.",
       True, None),

      # 10 — spotlight: tabs overview
      ("Every completed run produces a structured report. Seven tabs — "
       "findings, outputs, methods, parameters, software, citations, and "
       "the Q-C audit. Same order as the bulk tutorial.",
       False, None),

      # 11 — spotlight: Findings tab
      ("The findings tab. Headline metric and figures from the manifest — "
       "D-E genes per cell type, cell-type composition, and Q-C retention. "
       "Pseudobulk means significance rests on the six biological replicates.",
       False, None),

      # 12 — spotlight: Outputs tab
      ("Outputs. Files grouped by phase and step — the U-MAP, the marker "
       "heatmap, per-cell-type D-E tables, and the cell-type calls. "
       "View previews inline; download grabs one or all.",
       False, None),

      # 13 — spotlight: inline preview (annotated UMAP)
      ("Clicking view on the U-MAP renders it inline. "
       "Nine thousand eight hundred and fourteen cells coloured by the "
       "eight SingleR cell types, with a legend. "
       "The U-MAP is for visualisation; clusters come from the S-N-N graph.",
       False, None),

      # 14 — spotlight: Methods tab
      ("Methods. Paste-ready prose — emptyDrops Q-C, scran normalisation, "
       "S-N-N and Louvain clustering, SingleR annotation, and "
       "aggregateAcrossCells into DeSeq2. With versions and parameters.",
       False, None),

      # 15 — spotlight: Parameters tab
      ("Parameters. Phase, step, parameter, value — emptyDrops F-D-R, "
       "highly-variable-gene count, S-N-N k, the SingleR reference, "
       "and the pseudobulk design. A ready supplementary table.",
       False, None),

      # 16 — spotlight: Software tab
      ("Software. Exact versions — DropletUtils, scran, scater, SingleR, "
       "DeSeq2. Match these with the parameters tab and you reproduce the run.",
       False, None),

      # 17 — spotlight: Citations tab
      ("Citations. Amezquita twenty-twenty for O-S-C-A, Lun twenty-nineteen "
       "for emptyDrops, Aran twenty-nineteen for SingleR, "
       "Love twenty-fourteen for DeSeq2. Pre-bundled in the download report.",
       False, None),

      # 18 — spotlight: QC audit tab (includes the pseudoreplication gate)
      ("The Q-C audit tab. Cells retained, size-factor range, cluster count, "
       "pruned clusters, and the replicate-unit gate — sample, not cell. "
       "The replicate-unit gate is what enforces pseudobulk over naive "
       "per-cell D-E.",
       False, None),

      # 19 — center: wrap-up
      ("That's the single-cell thread. Route to O-S-C-A, cluster, "
       "annotate in parallel, pseudobulk D-E, and a seven-tab report. "
       "One object, one request, statistically honest D-E. "
       "Compare with the bulk and methylation tutorials — "
       "same agent, different data.",
       True, CLOSING_SPEED),
    ],
  },

  # ── Bioconductor · 450k methylation → DMRs (bioc-methyl-routing) — 19 steps
  # Sourced from src/BiocTours.jsx 'bioc-methyl-routing'. Centerpiece
  # (step 8): the CpG-density bias correction trap-and-fix beat — extended
  # dwell handled at the playwright tour layer.
  "bioc_methyl": {
    "label": "Bioconductor · 450k methylation chain",
    "steps": [
      # 1 — center welcome
      ("A methylation-array request. This chain rides a genomic backbone "
       "object instead of a count matrix — probe coordinates travel with "
       "the data, so region-level analysis is possible. "
       "About three minutes — I-DAT, genomic ratio set, D-M-Rs, "
       "C-p-G-corrected G-O, report.",
       True, CLOSING_SPEED),

      # 2 — spotlight: five phases
      ("Five phases. Read I-DAT, Q-C and normalise, D-M-P calling, "
       "D-M-R calling, and C-p-G-corrected enrichment. "
       "The panel shows the same five phases the chat narrates. "
       "Each phase lists its real minfi steps, parameters, and outputs.",
       False, None),

      # 3 — spotlight: routed to minfi
      ("Raw I-DAT plus a four-fifty-k manifest routes to minfi, "
       "because the downstream D-M-R step needs a genomic object, "
       "not a plain matrix. The input format picks the whole ecosystem, "
       "not just one tool.",
       False, None),

      # 4 — spotlight: Phase A read IDAT
      ("Phase A. minfi's read-meth-array-exp reads the I-DAT pairs into a "
       "methyl set — raw methylated and unmethylated intensities, "
       "four hundred and fifty thousand probes by twenty-four samples. "
       "The running phase auto-expands.",
       False, None),

      # 5 — spotlight: GenomicRatioSet handoff
      ("After Q-C and normalisation the object is a genomic ratio set. "
       "Beta values with each probe's genomic coordinate. "
       "That genomic ranges backbone is what lets the next step collapse "
       "C-p-Gs into regions. Methyl set, genomic ratio set, data frame, "
       "genomic ranges — each typed.",
       False, None),

      # 6 — spotlight: Phase C DMP calling
      ("Phase C. Per-C-p-G differential methylation with limma e-Bayes "
       "on M-values, design tilde group. "
       "Twelve thousand four hundred and three significant C-p-Gs at "
       "false discovery rate under zero point zero five, passed on to "
       "bumphunter. M-values for testing; beta values for reporting.",
       False, None),

      # 7 — spotlight: Phase D DMRs done
      ("Phase D. bumphunter with one thousand bootstraps collapses "
       "adjacent significant C-p-Gs into eight hundred and forty-seven "
       "regions — a genomic ranges object of D-M-Rs, ready for enrichment. "
       "Region-level analysis is only possible because coordinates rode along.",
       False, None),

      # 8 — spotlight: CpG-density bias centerpiece
      ("The teaching beat. The Q-C block flags the trap — a normal G-O "
       "over-represents C-p-G-rich promoters on the array. "
       "The agent block gives the fix — missMethyl gometh weights genes by "
       "C-p-G count, so enrichment p-values stay calibrated. "
       "The agent reaches for the array-aware tool, not the generic one.",
       False, None),

      # ── shared afterRunSteps (10) ──────────────────────────────────────────
      # 9 — center: chain complete
      ("All five phases done. minfi read, normalised, D-M-Ps, bumphunter "
       "D-M-Rs, and C-p-G-corrected G-O. Eight hundred and forty-seven "
       "D-M-Rs from twelve thousand four hundred and three significant "
       "C-p-Gs. Next, we walk every tab of the report.",
       True, None),

      # 10 — spotlight: tabs overview
      ("Seven tabs — findings, outputs, methods, parameters, software, "
       "citations, and the Q-C audit. Same structure as the other two "
       "Bioconductor tutorials.",
       False, None),

      # 11 — spotlight: Findings tab
      ("The findings tab. Headline plus figures from the manifest — "
       "D-M-R direction, hyper or hypo, top C-p-G-corrected G-O terms, "
       "and probe-Q-C retention. Numbers read from the run.",
       False, None),

      # 12 — spotlight: Outputs tab
      ("Outputs. Files by phase and step — the D-M-P table with twelve "
       "thousand four hundred and three C-p-Gs, the D-M-R object with "
       "eight hundred and forty-seven regions as genomic ranges, and the "
       "C-p-G-corrected G-O enrichment. View previews; download grabs one "
       "or all.",
       False, None),

      # 13 — spotlight: inline preview (DMR manhattan)
      ("Clicking view on the D-M-R tracks P-N-G renders it inline — "
       "negative log-ten p across chromosomes, with the eight hundred and "
       "forty-seven significant D-M-Rs above the region-wide threshold "
       "highlighted.",
       False, None),

      # 14 — spotlight: Methods tab
      ("Methods. Paste-ready — read-meth-array, detection-p Q-C, "
       "S-N-P and cross-reactive filtering, preprocessQuantile, "
       "limma D-M-Ps, bumphunter D-M-Rs, gometh enrichment — "
       "with versions and parameters.",
       False, None),

      # 15 — spotlight: Parameters tab
      ("Parameters. Phase, step, parameter, value — detection-p cutoff, "
       "the M-value design, bumphunter bootstraps and cutoff, the gometh "
       "array type. A ready supplementary table.",
       False, None),

      # 16 — spotlight: Software tab
      ("Software. Exact versions — minfi, limma, bumphunter, missMethyl. "
       "Match these with the parameters tab and you reproduce the run.",
       False, None),

      # 17 — spotlight: Citations tab
      ("Citations. Aryee twenty-fourteen for minfi, Jaffe twenty-twelve "
       "for bumphunter, Phipson twenty-sixteen for missMethyl, "
       "Ritchie twenty-fifteen for limma. Pre-bundled in the download report.",
       False, None),

      # 18 — spotlight: QC audit tab (includes the bias-corrected gate)
      ("The Q-C audit tab. Samples read, probes retained, significant-C-p-G "
       "count, D-M-R count, and the C-p-G-bias-corrected flag. "
       "The bias-corrected gate is what enforces gometh over a generic G-O test.",
       False, None),

      # 19 — center: wrap-up
      ("That's the epigenomics thread. A genomic ranges backbone, D-M-Ps, "
       "D-M-Rs, C-p-G-corrected enrichment, and a seven-tab report. "
       "A different object lineage from the other two tutorials, "
       "the same orchestration. That completes the three Bioconductor demos.",
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
