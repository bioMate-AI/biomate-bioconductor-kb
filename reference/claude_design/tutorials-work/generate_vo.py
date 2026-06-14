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
      ("In this tutorial we compare gene expression between a control and a "
       "treated group, using the standard Bioconductor toolkit: DESeq2, "
       "apeglm, and clusterProfiler. No R experience needed — BioMate picks "
       "the right workflow, runs it, and hands back a paste-ready report.",
       True, CLOSING_SPEED),

      # 2 — empty panel · understanding the request
      ("BioMate embeds your request against the Bioconductor knowledge base. "
       "The panel stays empty until a pipeline is committed.",
       False, None),

      # 3 — disambig card
      ("Two curated chains scored close: a count-matrix DESeq2 path at "
       "seventy-one percent, and a fuller FASTQ pipeline at sixty-six "
       "percent. BioMate surfaces both with their scores and pre-selects the "
       "top match.",
       False, None),

      # 4 — phase list populates
      ("The panel now shows the six phases that will run: QC, normalise, "
       "differential expression, shrinkage, enrichment, and visualisation. "
       "The chat on the left and the panel on the right are now tracking "
       "the same run.",
       False, None),

      # 5 — routing reasoning
      ("Why DESeq2 and not limma-voom? An integer count matrix calls for a "
       "negative-binomial model, which is what DESeq2 fits. Limma-voom is "
       "for continuous log-two intensities, which is a different kind of "
       "input.",
       False, None),

      # 6 — Phase A · QC filtering
      ("Phase A starts and the active phase expands automatically. edgeR's "
       "filterByExpr drops genes under ten counts. Parameters and output "
       "files appear inline as each step finishes.",
       False, None),

      # 7 — DESeqDataSet handoff
      ("After normalisation, the counts, sample metadata, and size factors "
       "fold into a single DESeqDataSet object. Every downstream DESeq2 step "
       "reads from that one object.",
       False, None),

      # 8 — Phase C · DE testing
      ("Phase C runs the Wald test, using condition as the design. The "
       "result is two thousand eight hundred and forty-one differentially "
       "expressed genes at false discovery rate under five percent.",
       False, None),

      # 9 — apeglm shrinkage
      ("Before ranking, apeglm pulls low-count fold changes toward zero. "
       "That keeps noisy extremes from dominating the enrichment that "
       "follows.",
       False, None),

      # 10 — Phase E · enrichment
      ("Phase E runs clusterProfiler's gseGO on the shrunk ranked list. The "
       "top biological-process term is regulation of apoptotic process. "
       "Phase F then renders the volcano plot, dot plot, and heatmap.",
       False, None),

      # 11 — center: chain complete · transition
      ("All six phases are done. A findings card lands in the chat, and the "
       "After-run report opens in the panel.",
       True, None),

      # 12 — tabs overview
      ("The After-run report has seven tabs: results first, methods and "
       "reproducibility next, audit last.",
       False, None),

      # 13 — Findings tab
      ("Findings: the headline numbers and figures, read straight from the "
       "run.",
       False, None),

      # 14 — Outputs tab
      ("Outputs: one row per file. View opens a file in place; Download all "
       "packages everything as a single ZIP.",
       False, None),

      # 15 — Methods tab
      ("Methods: paste-ready prose for a manuscript, with every tool and the "
       "parameters used.",
       False, None),

      # 16 — Parameters tab
      ("Parameters: a table of every value the run touched, by phase and "
       "step.",
       False, None),

      # 17 — Software tab
      ("Software: every package with its pinned version, so the run is "
       "reproducible.",
       False, None),

      # 18 — Citations tab
      ("Citations: an auto-generated reference list for the methods used.",
       False, None),

      # 19 — QC audit tab
      ("QC audit: every quality gate that fired, with the threshold, the "
       "observed value, the result, and the action taken. The audit trail "
       "is compatible with twenty-one CFR Part Eleven.",
       False, None),

      # 20 — center wrap-up
      ("And that's the full Bioconductor DESeq2 thread — from a "
       "natural-language request, through six analysis phases, to a "
       "complete, paste-ready report.",
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
      # 1 — center welcome (~3min target)
      ("Single-cell request. Route to OSCA, cluster, annotate in parallel, "
       "then condition DE the right way — pseudobulk.",
       True, CLOSING_SPEED),

      # 2 — phase list
      ("Seven phases. QC, normalise, feature, cluster, "
       "markers and annotation in parallel, pseudobulk DE.",
       False, None),

      # 3 — routed to OSCA
      ("Routed to OSCA. A single cell experiment hands off to pseudobulk "
       "DeSeq2 with no lossy conversion.",
       False, None),

      # 4 — Phase A cell QC
      ("Phase A. emptyDrops and perCellQCMetrics. "
       "Nine thousand eight hundred fourteen of twelve thousand cells retained.",
       False, None),

      # 5 — one SCE throughout
      ("One single cell experiment carries counts, log-counts, metadata, "
       "and size factors through every step.",
       False, None),

      # 6 — Phases B–D, 11 clusters
      ("Normalised. PCA. SNN graph plus Louvain. "
       "Eleven clusters. UMAP is for visualisation.",
       False, None),

      # 7 — parallel branch
      ("scoreMarkers and SingleR open in parallel — "
       "both read the clustered object.",
       False, None),

      # 8 — pseudobulk centerpiece
      ("Trap and fix. Thousands of cells aren't replicates — "
       "aggregate to pseudobulk so six samples are. Then DeSeq2 per cell type.",
       False, None),

      # 9 — center: chain complete
      ("Seven phases done. CD-eight T cells lead with two hundred fourteen DE genes.",
       True, None),

      # 10 — tabs overview
      ("Seven tabs — Findings, Outputs, Methods, Parameters, Software, "
       "Citations, QC audit.",
       False, None),

      # 11 — Findings tab
      ("Findings. DE genes per cell type, composition, QC retention — from the manifest.",
       False, None),

      # 12 — Outputs tab
      ("Outputs. UMAP, marker heatmap, per-cell-type DE tables, cell-type calls.",
       False, None),

      # 13 — UMAP preview
      ("Clicking view on the UMAP renders it inline — "
       "cells coloured by the eight SingleR types.",
       False, None),

      # 14 — Methods tab
      ("Methods. emptyDrops, scran, SNN/Louvain, SingleR, "
       "aggregateAcrossCells into DeSeq2.",
       False, None),

      # 15 — Parameters tab
      ("Parameters. emptyDrops FDR, HVG count, SNN k, "
       "SingleR reference, pseudobulk design.",
       False, None),

      # 16 — Software tab
      ("Software. DropletUtils, scran, scater, SingleR, DeSeq2 — exact versions.",
       False, None),

      # 17 — Citations tab
      ("Citations. Amezquita twenty-twenty, Lun twenty-nineteen, "
       "Aran twenty-nineteen, Love twenty-fourteen.",
       False, None),

      # 18 — QC audit
      ("QC audit. Cells retained, cluster count, "
       "and the replicate-unit gate — sample, not cell.",
       False, None),

      # 19 — center wrap-up
      ("One object, one request, statistically honest DE. "
       "Try the methylation tutorial next.",
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
      # 1 — center welcome (~3min target)
      ("Methylation array. Genomic backbone, not a count matrix — "
       "probe coordinates travel with the data.",
       True, CLOSING_SPEED),

      # 2 — five phases
      ("Five phases. Read IDAT, QC, DMP calling, DMR calling, "
       "and CpG-corrected enrichment.",
       False, None),

      # 3 — routed to minfi
      ("IDAT plus the 450k manifest routes to minfi — "
       "DMRs need a genomic object, not a plain matrix.",
       False, None),

      # 4 — Phase A read IDAT
      ("Phase A. read-meth-array-exp returns a methyl set: "
       "four hundred fifty thousand probes, twenty-four samples.",
       False, None),

      # 5 — GenomicRatioSet handoff
      ("After QC, a genomic ratio set. Beta values with probe coordinates. "
       "Lets the next step collapse CpGs into regions.",
       False, None),

      # 6 — Phase C DMP
      ("Phase C. limma eBayes on M-values. "
       "Twelve thousand four hundred CpGs significant.",
       False, None),

      # 7 — Phase D DMRs
      ("Phase D. bumphunter, one thousand bootstraps. "
       "Eight hundred forty-seven DMRs as genomic ranges.",
       False, None),

      # 8 — CpG-bias centerpiece
      ("Trap and fix. Normal GO over-represents CpG-rich promoters. "
       "missMethyl gometh weights by CpG count and keeps p-values calibrated.",
       False, None),

      # 9 — center: chain complete
      ("Five phases done. Eight hundred forty-seven DMRs.",
       True, None),

      # 10 — tabs overview
      ("Seven tabs — Findings, Outputs, Methods, Parameters, Software, "
       "Citations, QC audit.",
       False, None),

      # 11 — Findings tab
      ("Findings. DMR direction, top CpG-corrected GO terms, probe-QC retention.",
       False, None),

      # 12 — Outputs tab
      ("Outputs. DMP table, DMR object as genomic ranges, "
       "CpG-corrected GO enrichment.",
       False, None),

      # 13 — DMR manhattan preview
      ("Clicking view on the DMR tracks renders it inline — "
       "negative log-ten p across chromosomes.",
       False, None),

      # 14 — Methods tab
      ("Methods. read-meth-array, detection-p QC, preprocessQuantile, "
       "limma DMPs, bumphunter DMRs, gometh.",
       False, None),

      # 15 — Parameters tab
      ("Parameters. Detection-p cutoff, M-value design, "
       "bumphunter bootstraps, gometh array type.",
       False, None),

      # 16 — Software tab
      ("Software. minfi, limma, bumphunter, missMethyl — exact versions.",
       False, None),

      # 17 — Citations tab
      ("Citations. Aryee twenty-fourteen, Jaffe twenty-twelve, "
       "Phipson twenty-sixteen, Ritchie twenty-fifteen.",
       False, None),

      # 18 — QC audit
      ("QC audit. Samples, probes, significant CpGs, DMRs, "
       "and the CpG-bias-corrected flag.",
       False, None),

      # 19 — center wrap-up
      ("Genomic backbone, DMRs, CpG-corrected GO — different lineage, "
       "same orchestration. That's the three Bioconductor demos.",
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
