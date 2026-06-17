# BioMate Tutorial Narratives — Bioconductor

Voiceover scripts for the three **Bioconductor** tutorials (`bioc_kb`, `bioc_sc`, `bioc_methyl`). Same conventions as `Demo Narratives.md`: each beat is tagged `[mm:ss–mm:ss]` cumulative, computed at ~150 wpm + ~2 s pause between beats, 5 s floor per beat. Step labels match the in-app guided tour in `src/BiocTours.jsx`.

> **Length note.** These are the *comprehensive* walkthroughs the in-app tours drive — match → route → run every phase → walk all seven report tabs. They run **~4½ min** at narration pace (the in-app "~3 min" estimate assumes the viewer reads bubbles silently while the tour fast-forwards). For a 3-minute cut, drop the five shared "you're in control" beats (params / QC gate / halt box / inline outputs / stop-resume) and the Parameters + Software + Citations report tabs — they repeat across all three tutorials.

---

## 1 · Bioconductor · DESeq2 chain — bulk RNA-seq (`bioc-kb-routing`)

> **Scenario context.** A scientist asks for differential expression on a bulk RNA-seq count matrix. We follow knowledge-base routing, the six-phase DESeq2 chain, and the full After-run report.

**[00:00–00:09]** · **[Step 1 — Welcome, centered]**
"We're running a differential-expression analysis, end to end. No R needed — BioMate matches your request to a curated Bioconductor workflow and drives every step."

**[00:11–00:19]** · **[Step 2 — Understanding the request]**
"First it embeds your request against the Bioconductor knowledge base. The panel stays empty — no pipeline is chosen until the match resolves."

**[00:21–00:31]** · **[Step 3 — Ranked knowledge-base match]**
"Two curated chains score close — a count-matrix DESeq2 path, and a fuller FASTQ pipeline. BioMate shows both with scores and pre-selects the top one."

**[00:33–00:40]** · **[Step 4 — Selected, the chain populates]**
"With the DESeq2 chain committed, the panel fills with six phases: QC, normalise, DE test, shrink, enrich, visualise."

**[00:42–00:52]** · **[Step 5 — Routed by data format, not habit]**
"Why DESeq2? A raw integer count matrix needs a negative-binomial model — not limma-voom, which is for continuous intensities. Routed by data format, not habit."

**[00:54–01:03]** · **[Step 6 — Phase A running, QC filtering]**
"Execution starts; the active phase auto-expands. edgeR's filterByExpr drops genes under ten counts. Parameters and outputs appear inline as each step finishes."

**[01:05–01:13]** · **[Step 7 — Parameters, prefilled and editable]**
"Every step opens with the workflow's defaults already filled in. Click the gear to adjust a value inline — change only what you need."

**[01:15–01:24]** · **[Step 8 — QC gates, editable with auto-loop]**
"Each phase has an editable QC gate, prefilled with its default threshold. The auto-loop switch lets a failed gate fix its own params and re-run."

**[01:26–01:36]** · **[Step 9 — On a failed gate, auto-proceed]**
"When auto-loop is on, a failed gate posts a halt box — the failing metric, the proposed fix, and a ten-second countdown. Apply, pause, or dismiss."

**[01:38–01:47]** · **[Step 10 — Outputs render inline]**
"As each step finishes, its files drop into the panel — view opens them inline, download grabs the file. No waiting for the full chain."

**[01:49–01:56]** · **[Step 11 — Stop and resume]**
"Any running phase can be stopped — finished steps and outputs are kept — then resumed exactly where you left off."

**[01:58–02:06]** · **[Step 12 — One typed object carries the analysis]**
"After normalisation, counts, metadata and size factors fold into one DESeqDataSet — the typed object every downstream step reads from."

**[02:08–02:19]** · **[Step 13 — Phase C running, DE testing]**
"Phase C runs the Wald test on design tilde-condition — 2,841 genes at five-percent FDR — producing a results table of fold-change and adjusted-p per gene."

**[02:21–02:27]** · **[Step 14 — Shrink noisy fold-changes]**
"Before ranking, apeglm shrinks noisy low-count fold-changes toward zero, so enrichment isn't dominated by extremes."

**[02:29–02:38]** · **[Step 15 — Phase E running, enrichment]**
"clusterProfiler's gseGO runs on the ranked list — top term, regulation of apoptotic process. Phase F renders the volcano, dotplot and heatmap."

**[02:40–02:48]** · **[Step 16 — Chain complete, 2,841 DE genes]**
"All six phases done — DESeq2, apeglm, clusterProfiler, EnhancedVolcano. Chat drops a findings card; the panel flips to the After-run report."

**[02:50–02:59]** · **[Step 17 — After run, one structured report]**
"The report has seven tabs in reading order — results first, methods and reproducibility next, audit last. The whole thing exports to one document."

**[03:01–03:10]** · **[Step 18 — Findings, the headline]**
"Findings: the headline metric, a few bullets, and figures read straight from the manifest. Nothing is invented — uncited claims are tagged author judgment."

**[03:12–03:21]** · **[Step 19 — Outputs, every file]**
"Outputs lists every file by phase — the results object, volcano, GO dotplot, top-50 heatmap. View previews inline; download grabs one or all."

**[03:23–03:33]** · **[Step 20 — Open in RStudio]**
"Download isn't the end. Every results object has an Open-in-RStudio button — a live R 4.3 session with DESeq2 loaded and your dataset pre-mounted."

**[03:35–03:44]** · **[Step 21 — Visualised, volcano plot]**
"Clicking view on the volcano renders it inline — fold-change versus significance, up genes red, down blue. BioMate picks the viewer from the file type."

**[03:46–03:55]** · **[Step 22 — Methods, paste-ready prose]**
"Methods is paragraph-form prose — tools, versions, exact parameters — written so a peer can replicate the run. Paste it straight into a manuscript."

**[03:57–04:05]** · **[Step 23 — Parameters, every knob]**
"Parameters lists phase, step and value for everything the run touched — a ready supplementary table. Defaults, overrides and auto-loop tweaks are distinguished."

**[04:07–04:14]** · **[Step 24 — Software, pinned versions]**
"Software pins every package version — DESeq2, apeglm, edgeR, clusterProfiler. With Parameters, it's the reproducibility baseline."

**[04:16–04:24]** · **[Step 25 — Citations, pre-formatted refs]**
"Citations auto-generates the reference list — Love 2014, Zhu 2019, Wu 2021, and more. Methods and Citations export together."

**[04:26–04:36]** · **[Step 26 — QC audit, the compliance lens]**
"QC audit logs every gate that fired — gene retention, size-factor range, replicate count — with threshold, observed value and action. Part 11 friendly."

**[04:38–04:48]** · **[Step 27 — Wrap-up, centered]**
"That's the full DESeq2 thread — match, route, run six phases, a seven-tab report, all from one request. Download wraps it into a single document."

---

## 2 · Bioconductor · scRNA-seq → pseudobulk DE (`bioc-sc-routing`)

> **Scenario context.** A single-cell request. We follow routing to the OSCA stack, parallel marker-detection and annotation, and the statistically correct condition DE — pseudobulk, not per-cell.

**[00:00–00:10]** · **[Step 1 — Welcome, centered]**
"Same agent, a single-cell request. BioMate routes to the OSCA stack, clusters and annotates in parallel, then runs condition DE the statistically correct way — pseudobulk."

**[00:12–00:20]** · **[Step 2 — Seven phases, a parallel branch]**
"Seven phases: QC, normalise, feature selection and PCA, cluster, then markers and annotation in parallel, then pseudobulk DE."

**[00:22–00:33]** · **[Step 3 — Routed to the OSCA stack]**
"The agent works backward from the goal. Condition DE with DESeq2 means a SingleCellExperiment plus scran and scater — not Seurat — so the final step hands off cleanly."

**[00:35–00:44]** · **[Step 4 — Phase A running, cell QC]**
"Phase A: emptyDrops separates real cells from ambient barcodes, then per-cell QC flags high-mito, low-count cells — 9,814 of 12,402 kept."

**[00:46–00:52]** · **[Step 5 — Parameters, prefilled and editable]**
"Each step opens with defaults filled in. Click the gear to adjust a value inline — change only what you need."

**[00:54–01:03]** · **[Step 6 — QC gates, editable with auto-loop]**
"Every phase has an editable QC gate, prefilled with its default. The auto-loop switch lets a failed gate fix its params and re-run."

**[01:05–01:13]** · **[Step 7 — On a failed gate, auto-proceed]**
"With auto-loop on, a failed gate posts a halt box — failing metric, proposed fix, ten-second countdown. Apply, pause, or dismiss."

**[01:15–01:21]** · **[Step 8 — Outputs render inline]**
"Files drop into the panel as each step finishes — view opens them inline, download grabs the file."

**[01:23–01:30]** · **[Step 9 — Stop and resume]**
"Any phase can be stopped — finished steps are kept — then resumed where you left off, nothing recomputed."

**[01:32–01:41]** · **[Step 10 — One SingleCellExperiment throughout]**
"QC and normalisation fold into a single SingleCellExperiment carrying counts, logcounts and metadata. Every step below reads from this one object."

**[01:43–01:53]** · **[Step 11 — Phases B–D done, 11 clusters]**
"Normalisation, HVG selection with PCA, and graph-based clustering are done — eleven clusters. The UMAP is for visualisation only; clusters come from the SNN graph."

**[01:55–02:04]** · **[Step 12 — Parallel branch, markers ∥ annotation]**
"Phases E and F open together — scoreMarkers and SingleR both read the clustered object, so the engine fans them out and tracks the join."

**[02:06–02:18]** · **[Step 13 — Pseudobulk, not naive per-cell DE]**
"The key beat: testing thousands of cells as replicates is pseudoreplication. The fix — aggregate to pseudobulk, so the six samples are the real replicates, then DESeq2 per cell type."

**[02:20–02:30]** · **[Step 14 — Chain complete, 8 cell types]**
"Seven phases done — routed to OSCA, clustered, annotated, then pseudobulk DE. CD8 T cells are the strongest responder, 214 DE genes on true replicates."

**[02:32–02:39]** · **[Step 15 — After run, one structured report]**
"The After-run report — seven tabs in reading order, results first, audit last, and a one-click export of the whole document."

**[02:41–02:51]** · **[Step 16 — Findings, the headline]**
"Findings: headline plus figures from the manifest — DE genes per cell type, composition, QC retention. Significance rests on the six biological replicates."

**[02:53–03:02]** · **[Step 17 — Outputs, every file]**
"Outputs by phase — the UMAP, marker heatmap, per-cell-type DE tables, and the cell-type calls. View previews; download grabs one or all."

**[03:04–03:14]** · **[Step 18 — Open in CellxGene]**
"The natural next move for single-cell: the h5ad export has an Open-in-CellxGene button — browse the annotated UMAP and expression live, or switch to RStudio."

**[03:16–03:23]** · **[Step 19 — Visualised, annotated UMAP]**
"Clicking view on the UMAP renders it inline — 9,814 cells coloured by eight SingleR cell types, with a legend."

**[03:25–03:35]** · **[Step 20 — Methods, paste-ready prose]**
"Methods, paste-ready — emptyDrops QC, scran normalisation, SNN-Louvain clustering, SingleR annotation, and aggregate-then-DESeq2, with versions and parameters."

**[03:37–03:46]** · **[Step 21 — Parameters, every knob]**
"Parameters: phase, step, value — emptyDrops FDR, HVG count, SNN k, the SingleR reference, the pseudobulk design. A ready supplementary table."

**[03:48–03:56]** · **[Step 22 — Software, pinned versions]**
"Software pins exact versions — DropletUtils, scran, scater, SingleR, DESeq2 — the reproducibility baseline alongside Parameters."

**[03:58–04:05]** · **[Step 23 — Citations, pre-formatted refs]**
"Citations: Amezquita 2020 for OSCA, Lun 2019 for emptyDrops, Aran 2019 for SingleR, Love 2014 for DESeq2."

**[04:07–04:16]** · **[Step 24 — QC audit, the compliance lens]**
"QC audit logs every gate — cells retained, cluster count, and the replicate-unit gate that enforces pseudobulk over per-cell DE."

**[04:18–04:28]** · **[Step 25 — Wrap-up, centered]**
"That's the single-cell thread — route to OSCA, cluster, annotate in parallel, pseudobulk DE, a seven-tab report. One object, statistically honest DE."

---

## 3 · Bioconductor · 450k methylation → DMRs (`bioc-methyl-routing`)

> **Scenario context.** A methylation-array request. The chain rides a genomic-coordinate backbone so region-level analysis is possible — IDAT to DMRs to CpG-density-corrected enrichment.

**[00:00–00:10]** · **[Step 1 — Welcome, centered]**
"A methylation-array request. This chain rides a genomic backbone object instead of a count matrix — probe coordinates travel with the data, so region-level analysis is possible."

**[00:12–00:20]** · **[Step 2 — Five phases, mirrored in the panel]**
"Five phases: read IDAT, QC and normalise, DMP calling, DMR calling, then CpG-corrected enrichment. The panel mirrors the chat."

**[00:22–00:31]** · **[Step 3 — Routed to minfi]**
"The agent explains it — raw IDAT plus a 450k manifest routes to minfi, because the DMR step needs a genomic object, not a plain matrix."

**[00:33–00:43]** · **[Step 4 — Phase A running, read IDAT]**
"Phase A: read.metharray.exp reads the IDAT pairs into a MethylSet — raw methylated and unmethylated intensities, 450k probes across 24 samples."

**[00:45–00:51]** · **[Step 5 — Parameters, prefilled and editable]**
"Each step opens with defaults filled in. Click the gear to adjust a value inline — change only what you need."

**[00:53–01:02]** · **[Step 6 — QC gates, editable with auto-loop]**
"Every phase has an editable QC gate, prefilled with its default. The auto-loop switch lets a failed gate fix its params and re-run."

**[01:04–01:12]** · **[Step 7 — On a failed gate, auto-proceed]**
"With auto-loop on, a failed gate posts a halt box — failing metric, proposed fix, ten-second countdown. Apply, pause, or dismiss."

**[01:14–01:20]** · **[Step 8 — Outputs render inline]**
"Files drop into the panel as each step finishes — view opens them inline, download grabs the file."

**[01:22–01:28]** · **[Step 9 — Stop and resume]**
"Any phase can be stopped — finished steps are kept — then resumed where you left off."

**[01:30–01:41]** · **[Step 10 — GenomicRatioSet, coordinates attached]**
"After QC and normalisation the object is a GenomicRatioSet — beta-values with each probe's coordinate. That backbone is what lets the next step collapse CpGs into regions."

**[01:43–01:53]** · **[Step 11 — Phase C running, DMP calling]**
"Phase C: per-CpG differential methylation with limma eBayes on M-values — 12,403 significant CpGs at five-percent FDR, passed to bumphunter."

**[01:55–02:04]** · **[Step 12 — Phase D done, 847 DMRs]**
"bumphunter, a thousand bootstraps, collapses adjacent significant CpGs into 847 regions — a GRanges object of DMRs, ready for enrichment."

**[02:06–02:17]** · **[Step 13 — CpG-density bias correction]**
"The teaching beat: a normal GO over-represents CpG-rich promoters on the array. The fix — gometh weights genes by CpG count so enrichment p-values stay calibrated."

**[02:19–02:28]** · **[Step 14 — Chain complete, 847 DMRs]**
"Five phases done — minfi read, normalised, DMPs, bumphunter DMRs, CpG-corrected GO. 847 DMRs from 12,403 significant CpGs."

**[02:30–02:36]** · **[Step 15 — After run, one structured report]**
"The After-run report — seven tabs, results first, audit last, exportable as one document."

**[02:38–02:48]** · **[Step 16 — Findings, the headline]**
"Findings: headline plus figures from the manifest — DMR direction, top CpG-corrected GO terms, probe-QC retention. Numbers read from the run, not generated."

**[02:50–02:59]** · **[Step 17 — Outputs, every file]**
"Outputs by phase — the DMP table, the DMRs as GRanges, and the CpG-corrected enrichment. View previews; download grabs one or all."

**[03:01–03:10]** · **[Step 18 — Open in RStudio]**
"Every results object has an Open-in-RStudio button — a live R 4.3 session with minfi and bumphunter loaded and your GenomicRatioSet mounted."

**[03:12–03:20]** · **[Step 19 — Visualised, DMR manhattan]**
"Clicking view on the DMR track renders it inline — significance across chromosomes, with the 847 DMRs above threshold highlighted."

**[03:22–03:32]** · **[Step 20 — Methods, paste-ready prose]**
"Methods, paste-ready — read.metharray, detection-p QC, SNP and cross-reactive filtering, quantile normalisation, limma DMPs, bumphunter DMRs, gometh enrichment."

**[03:34–03:42]** · **[Step 21 — Parameters, every knob]**
"Parameters: detection-p cutoff, the M-value design, bumphunter bootstraps and cutoff, the gometh array type. A ready supplementary table."

**[03:44–03:52]** · **[Step 22 — Software, pinned versions]**
"Software pins exact versions — minfi, limma, bumphunter, missMethyl — the reproducibility baseline alongside Parameters."

**[03:54–04:01]** · **[Step 23 — Citations, pre-formatted refs]**
"Citations: Aryee 2014 for minfi, Jaffe 2012 for bumphunter, Phipson 2016 for missMethyl, Ritchie 2015 for limma."

**[04:03–04:12]** · **[Step 24 — QC audit, the compliance lens]**
"QC audit logs every gate — samples read, probes retained, significant-CpG and DMR counts, and the CpG-bias-corrected flag."

**[04:14–04:24]** · **[Step 25 — Wrap-up, centered]**
"That's the epigenomics thread — a GRanges backbone, DMPs, DMRs, CpG-corrected enrichment, a seven-tab report. A different object lineage, same orchestration."

---

## Recording notes

- **Timings.** Each beat is tagged `[mm:ss–mm:ss]` cumulative at ~150 wpm + ~2 s pause between beats, 5 s floor per beat. Full comprehensive cuts run ~4:30–4:50 each.
- **Source of truth.** Lines are condensed from the in-app guided-tour copy in `src/BiocTours.jsx`. The headline numbers (2,841 DE genes; 9,814 cells / 8 cell types / 214 CD8 DE genes; 12,403 CpGs / 847 DMRs) are drawn from each scenario's run manifest — keep them in sync with `src/data.js` and `src/research-data.js` if either changes.
- **Pronunciation.** "DESeq2" → *dee-seek two*; "apeglm" → *ape-G-L-M*; "minfi" → *min-fye*; "OSCA" → *os-kah*; "gometh" → *go-meth*; "IDAT" → *eye-dat*; "GRanges" → *G-ranges*.
- **3-minute cut.** Drop Steps 7–11 (the shared params / QC-gate / halt / inline-outputs / stop-resume control beats) and the Parameters, Software and Citations report tabs — they recur across all three tutorials, so cover them once in tutorial 1 and trim from 2 and 3. The condensed scripts below apply exactly that trim.

---
---

# 3-minute cuts

Condensed versions of the three scripts above — the five shared control beats and the Parameters / Software / Citations report tabs removed, retimed from zero. Each runs ~3–3½ min. The wording is unchanged from the full cut, so a narrator can record once and lift either length.

---

## 1 · DESeq2 chain — 3-min cut (`bioc-kb-routing`)

**[00:00–00:09]** · **[Welcome, centered]**
"We're running a differential-expression analysis, end to end. No R needed — BioMate matches your request to a curated Bioconductor workflow and drives every step."

**[00:11–00:19]** · **[Understanding the request]**
"First it embeds your request against the Bioconductor knowledge base. The panel stays empty — no pipeline is chosen until the match resolves."

**[00:21–00:31]** · **[Ranked knowledge-base match]**
"Two curated chains score close — a count-matrix DESeq2 path, and a fuller FASTQ pipeline. BioMate shows both with scores and pre-selects the top one."

**[00:33–00:40]** · **[Selected, the chain populates]**
"With the DESeq2 chain committed, the panel fills with six phases: QC, normalise, DE test, shrink, enrich, visualise."

**[00:42–00:52]** · **[Routed by data format, not habit]**
"Why DESeq2? A raw integer count matrix needs a negative-binomial model — not limma-voom, which is for continuous intensities. Routed by data format, not habit."

**[00:54–01:03]** · **[Phase A running, QC filtering]**
"Execution starts; the active phase auto-expands. edgeR's filterByExpr drops genes under ten counts. Parameters and outputs appear inline as each step finishes."

**[01:05–01:13]** · **[One typed object carries the analysis]**
"After normalisation, counts, metadata and size factors fold into one DESeqDataSet — the typed object every downstream step reads from."

**[01:15–01:25]** · **[Phase C running, DE testing]**
"Phase C runs the Wald test on design tilde-condition — 2,841 genes at five-percent FDR — producing a results table of fold-change and adjusted-p per gene."

**[01:27–01:33]** · **[Shrink noisy fold-changes]**
"Before ranking, apeglm shrinks noisy low-count fold-changes toward zero, so enrichment isn't dominated by extremes."

**[01:35–01:44]** · **[Phase E running, enrichment]**
"clusterProfiler's gseGO runs on the ranked list — top term, regulation of apoptotic process. Phase F renders the volcano, dotplot and heatmap."

**[01:46–01:54]** · **[Chain complete, 2,841 DE genes]**
"All six phases done — DESeq2, apeglm, clusterProfiler, EnhancedVolcano. Chat drops a findings card; the panel flips to the After-run report."

**[01:56–02:05]** · **[After run, one structured report]**
"The report has seven tabs in reading order — results first, methods and reproducibility next, audit last. The whole thing exports to one document."

**[02:07–02:16]** · **[Findings, the headline]**
"Findings: the headline metric, a few bullets, and figures read straight from the manifest. Nothing is invented — uncited claims are tagged author judgment."

**[02:18–02:27]** · **[Outputs, every file]**
"Outputs lists every file by phase — the results object, volcano, GO dotplot, top-50 heatmap. View previews inline; download grabs one or all."

**[02:29–02:39]** · **[Open in RStudio]**
"Download isn't the end. Every results object has an Open-in-RStudio button — a live R 4.3 session with DESeq2 loaded and your dataset pre-mounted."

**[02:41–02:50]** · **[Visualised, volcano plot]**
"Clicking view on the volcano renders it inline — fold-change versus significance, up genes red, down blue. BioMate picks the viewer from the file type."

**[02:52–03:01]** · **[Methods, paste-ready prose]**
"Methods is paragraph-form prose — tools, versions, exact parameters — written so a peer can replicate the run. Paste it straight into a manuscript."

**[03:03–03:13]** · **[QC audit, the compliance lens]**
"QC audit logs every gate that fired — gene retention, size-factor range, replicate count — with threshold, observed value and action. Part 11 friendly."

**[03:15–03:25]** · **[Wrap-up, centered]**
"That's the full DESeq2 thread — match, route, run six phases, a seven-tab report, all from one request. Download wraps it into a single document."

---

## 2 · scRNA-seq → pseudobulk DE — 3-min cut (`bioc-sc-routing`)

**[00:00–00:10]** · **[Welcome, centered]**
"Same agent, a single-cell request. BioMate routes to the OSCA stack, clusters and annotates in parallel, then runs condition DE the statistically correct way — pseudobulk."

**[00:12–00:20]** · **[Seven phases, a parallel branch]**
"Seven phases: QC, normalise, feature selection and PCA, cluster, then markers and annotation in parallel, then pseudobulk DE."

**[00:22–00:33]** · **[Routed to the OSCA stack]**
"The agent works backward from the goal. Condition DE with DESeq2 means a SingleCellExperiment plus scran and scater — not Seurat — so the final step hands off cleanly."

**[00:35–00:44]** · **[Phase A running, cell QC]**
"Phase A: emptyDrops separates real cells from ambient barcodes, then per-cell QC flags high-mito, low-count cells — 9,814 of 12,402 kept."

**[00:46–00:55]** · **[One SingleCellExperiment throughout]**
"QC and normalisation fold into a single SingleCellExperiment carrying counts, logcounts and metadata. Every step below reads from this one object."

**[00:57–01:07]** · **[Phases B–D done, 11 clusters]**
"Normalisation, HVG selection with PCA, and graph-based clustering are done — eleven clusters. The UMAP is for visualisation only; clusters come from the SNN graph."

**[01:09–01:18]** · **[Parallel branch, markers ∥ annotation]**
"Phases E and F open together — scoreMarkers and SingleR both read the clustered object, so the engine fans them out and tracks the join."

**[01:20–01:32]** · **[Pseudobulk, not naive per-cell DE]**
"The key beat: testing thousands of cells as replicates is pseudoreplication. The fix — aggregate to pseudobulk, so the six samples are the real replicates, then DESeq2 per cell type."

**[01:34–01:44]** · **[Chain complete, 8 cell types]**
"Seven phases done — routed to OSCA, clustered, annotated, then pseudobulk DE. CD8 T cells are the strongest responder, 214 DE genes on true replicates."

**[01:46–01:53]** · **[After run, one structured report]**
"The After-run report — seven tabs in reading order, results first, audit last, and a one-click export of the whole document."

**[01:55–02:05]** · **[Findings, the headline]**
"Findings: headline plus figures from the manifest — DE genes per cell type, composition, QC retention. Significance rests on the six biological replicates."

**[02:07–02:16]** · **[Outputs, every file]**
"Outputs by phase — the UMAP, marker heatmap, per-cell-type DE tables, and the cell-type calls. View previews; download grabs one or all."

**[02:18–02:28]** · **[Open in CellxGene]**
"The natural next move for single-cell: the h5ad export has an Open-in-CellxGene button — browse the annotated UMAP and expression live, or switch to RStudio."

**[02:30–02:37]** · **[Visualised, annotated UMAP]**
"Clicking view on the UMAP renders it inline — 9,814 cells coloured by eight SingleR cell types, with a legend."

**[02:39–02:49]** · **[Methods, paste-ready prose]**
"Methods, paste-ready — emptyDrops QC, scran normalisation, SNN-Louvain clustering, SingleR annotation, and aggregate-then-DESeq2, with versions and parameters."

**[02:51–03:00]** · **[QC audit, the compliance lens]**
"QC audit logs every gate — cells retained, cluster count, and the replicate-unit gate that enforces pseudobulk over per-cell DE."

**[03:02–03:12]** · **[Wrap-up, centered]**
"That's the single-cell thread — route to OSCA, cluster, annotate in parallel, pseudobulk DE, a seven-tab report. One object, statistically honest DE."

---

## 3 · 450k methylation → DMRs — 3-min cut (`bioc-methyl-routing`)

**[00:00–00:10]** · **[Welcome, centered]**
"A methylation-array request. This chain rides a genomic backbone object instead of a count matrix — probe coordinates travel with the data, so region-level analysis is possible."

**[00:12–00:20]** · **[Five phases, mirrored in the panel]**
"Five phases: read IDAT, QC and normalise, DMP calling, DMR calling, then CpG-corrected enrichment. The panel mirrors the chat."

**[00:22–00:31]** · **[Routed to minfi]**
"The agent explains it — raw IDAT plus a 450k manifest routes to minfi, because the DMR step needs a genomic object, not a plain matrix."

**[00:33–00:43]** · **[Phase A running, read IDAT]**
"Phase A: read.metharray.exp reads the IDAT pairs into a MethylSet — raw methylated and unmethylated intensities, 450k probes across 24 samples."

**[00:45–00:56]** · **[GenomicRatioSet, coordinates attached]**
"After QC and normalisation the object is a GenomicRatioSet — beta-values with each probe's coordinate. That backbone is what lets the next step collapse CpGs into regions."

**[00:58–01:08]** · **[Phase C running, DMP calling]**
"Phase C: per-CpG differential methylation with limma eBayes on M-values — 12,403 significant CpGs at five-percent FDR, passed to bumphunter."

**[01:10–01:19]** · **[Phase D done, 847 DMRs]**
"bumphunter, a thousand bootstraps, collapses adjacent significant CpGs into 847 regions — a GRanges object of DMRs, ready for enrichment."

**[01:21–01:32]** · **[CpG-density bias correction]**
"The teaching beat: a normal GO over-represents CpG-rich promoters on the array. The fix — gometh weights genes by CpG count so enrichment p-values stay calibrated."

**[01:34–01:43]** · **[Chain complete, 847 DMRs]**
"Five phases done — minfi read, normalised, DMPs, bumphunter DMRs, CpG-corrected GO. 847 DMRs from 12,403 significant CpGs."

**[01:45–01:51]** · **[After run, one structured report]**
"The After-run report — seven tabs, results first, audit last, exportable as one document."

**[01:53–02:03]** · **[Findings, the headline]**
"Findings: headline plus figures from the manifest — DMR direction, top CpG-corrected GO terms, probe-QC retention. Numbers read from the run, not generated."

**[02:05–02:14]** · **[Outputs, every file]**
"Outputs by phase — the DMP table, the DMRs as GRanges, and the CpG-corrected enrichment. View previews; download grabs one or all."

**[02:16–02:25]** · **[Open in RStudio]**
"Every results object has an Open-in-RStudio button — a live R 4.3 session with minfi and bumphunter loaded and your GenomicRatioSet mounted."

**[02:27–02:34]** · **[Visualised, DMR manhattan]**
"Clicking view on the DMR track renders it inline — significance across chromosomes, with the 847 DMRs above threshold highlighted."

**[02:36–02:46]** · **[Methods, paste-ready prose]**
"Methods, paste-ready — read.metharray, detection-p QC, SNP and cross-reactive filtering, quantile normalisation, limma DMPs, bumphunter DMRs, gometh enrichment."

**[02:48–02:57]** · **[QC audit, the compliance lens]**
"QC audit logs every gate — samples read, probes retained, significant-CpG and DMR counts, and the CpG-bias-corrected flag."

**[02:59–03:09]** · **[Wrap-up, centered]**
"That's the epigenomics thread — a GRanges backbone, DMPs, DMRs, CpG-corrected enrichment, a seven-tab report. A different object lineage, same orchestration."
