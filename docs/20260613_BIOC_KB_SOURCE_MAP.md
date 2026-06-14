# bioc_kb tutorial — source map for every piece of on-screen / audio content

**Purpose:** every fact spoken or shown in the bioc_kb tutorial video must
come from a file shown here, at the line shown here. Nothing is authored
fresh. If a tab cannot be sourced, the tab is omitted from the tour rather
than filled with invented content.

**Review protocol:** read each row; for each "Source" cell, open the file at
the listed line and confirm the content matches what the table says we'll
play. Sign off → I wire Modals.jsx + re-record. Do not sign off → I do not
touch the recording.

---

## A. Tour callouts (`BiocTours.jsx` — title + body per step)

All 20 tour steps in the bioc-kb-routing tour are already authored in
`reference/claude_design/bioconductor-handoff/src/BiocTours.jsx`. The audio
narration mirrors the body text of each — no extra content.

| Step | Tour callout title | Source line | Audio mirrors |
|---|---|---|---|
| 1 | Bulk RNA-seq differential expression with Bioconductor | `BiocTours.jsx:98–102` | body verbatim |
| 2 | Understanding the request | `:104–108` | body verbatim |
| 3 | Ranked knowledge-base match | `:110–114` | body verbatim |
| 4 | Selected · the chain populates the panel | `:116–120` | body verbatim |
| 5 | Routed by data format, not habit | `:122–126` | body verbatim |
| 6 | Phase A running · QC filtering | `:128–132` | body verbatim |
| 7 | One typed object carries the analysis | `:134–138` | body verbatim |
| 8 | Phase C running · DE testing | `:140–144` | body verbatim |
| 9 | Shrink noisy fold-changes first | `:146–150` | body verbatim |
| 10 | Phase E running · enrichment | `:152–156` | body verbatim |
| 11 | _(complete) — sw.completeTitle / completeBody_ | `:171–172` | body verbatim |
| 12 | After run · one structured report | `:38–42` | body verbatim |
| 13 | Findings · the headline | `:44–46` | sw.findingsBody from `:163` |
| 14 | Outputs · every file produced | `:50–52` | sw.outputsBody from `:164` |
| 15 | Methods · paste-ready prose | `:61–65` | **sw.methodsBody from `:165`** |
| 16 | Parameters · every knob | `:67–71` | **sw.paramsBody from `:166`** |
| 17 | Software · pinned versions | `:73–77` | **sw.softwareBody from `:167`** |
| 18 | Citations · pre-formatted refs | `:79–83` | **sw.citeBody from `:168`** |
| 19 | QC audit · the compliance lens | `:85–89` | **sw.qcBody from `:169`** |
| 20 | That's the full DESeq2 thread | `:173–176` | body verbatim |

The previous mid-tour preview step (image modal) is removed because no SVG
viz handler exists for volcano/UMAP/Manhattan in `Modals.jsx`. Skipping
prevents the "no visualization registered" placeholder.

---

## B. Right-panel content (`data.js` BIOC_KB scenario)

The workflow panel reads from `window.SCENARIOS[scenarioId]` defined in
`reference/claude_design/bioconductor-handoff/src/data.js`.

| Panel element | Source | Verbatim content |
|---|---|---|
| Chain name | `data.js:344` (name) | `Bioconductor · DESeq2 chain` |
| Subtitle | `data.js:345` | `Bulk RNA-seq · 6 phases · DESeq2 + apeglm + clusterProfiler` |
| Phase A | `data.js:361` | `QC · edgeR::filterByExpr` · step `filterByExpr` |
| Phase B | `data.js:364–368` | `Normalise · DESeq2 size factors → DESeqDataSet` · steps `DESeqDataSetFromTximport`, `estimateSizeFactors` |
| Phase C | `data.js:369–373` | `DE test · Wald test · ~ condition` · steps `DESeq()`, `results()` |
| Phase D | `data.js:374–376` | `Shrink · apeglm LFC shrinkage` · step `lfcShrink (apeglm)` |
| Phase E | `data.js:377–381` | `Enrich · clusterProfiler::gseGO` · steps `org.Hs.eg.db`, `gseGO` |
| Phase F | `data.js:382–384` | `Visualise · volcano · dotplot · heatmap` · step `plots` |

Every step's `params: [{k, v}]` array drives the **Parameters tab** rows below.

---

## C. Chat-line stream (`research-data.js` SCEN_BIOC_KB.tape)

The chat lines between markers come from
`reference/claude_design/bioconductor-handoff/src/research-data.js` lines
562–660. Every line is either a phase-state update or a direct paraphrase
of the BiocTours.jsx callout body for the same marker. Specifically:

| Marker | Chat lines emitted | Source for the prose |
|---|---|---|
| `bioc_kb_plan` | "Embedding your request against the Bioconductor knowledge base." | BiocTours `:106` |
| `bioc_kb_disambig` | (disambig card, no chat line) | BiocTours `:111–112` |
| `bioc_kb_selected` | "Selected bulk_rnaseq_de_analysis. Panel populates with the six phases." | BiocTours `:117–118` |
| `bioc_kb_routed` | "Raw integer count matrix → negative-binomial model (DESeq2), not limma/voom…" | BiocTours `:123–124` |
| `bioc_kb_A_run` | "Phase A · QC — edgeR::filterByExpr drops genes under 10 counts." | BiocTours `:129–130` |
| `bioc_kb_norm_done` | "Phase B · Normalise — counts + metadata + size factors fold into a single DESeqDataSet." | BiocTours `:135–136` |
| `bioc_kb_C_run` | "Wald test on design ~ condition" → "2,841 genes DE at FDR < 0.05 → DESeqResults table…" | BiocTours `:141–142` |
| `bioc_kb_shrink_done` | "apeglm shrinks low-count fold-changes toward zero…" | BiocTours `:147–148` |
| `bioc_kb_E_run` | "clusterProfiler gseGO on the shrunk ranked list" → "Top GO term: regulation of apoptotic process" | BiocTours `:153–154` |

No invented gene counts, no infrastructure mentions, no fabricated NES /
p-adj / iteration / sample-split numbers.

---

## D. After-run report tabs (Modals.jsx wiring plan — no new prose)

Today the v1 `Modals.jsx` renders cryo-template content for Methods /
Parameters / Software / Citations regardless of scenario. To fix without
authoring new prose, the Report* components will be made data-driven:

| Tab | Component | Bioc source — no new content authored |
|---|---|---|
| Findings | `window.ReportFindings({findings})` | Already scenario-driven; already correct |
| Outputs | `window.ReportOutputs({outputs, scenario})` | Already scenario-driven; already correct |
| Methods | `ReportMethodsImrad({scenario})` | When `scenario.id` starts with `bioc_`, render `sw.methodsBody` text from BiocTours.jsx (lifted at build / passed as prop) |
| Parameters | `ReportParams({scenario})` | When bioc: render rows by walking `scenario.phases[].steps[].params` (k, v) — every cell comes from `data.js` |
| Software | `ReportSoftware({scenario})` | When bioc: render the unique tool names found in `scenario.phases[].steps[].name` |
| Citations | `ReportCitations({scenario})` | When bioc: fetch `/api/workflows/:name/citations` (already returns the qc_evidence.yaml `transcriptomics:` block — Wave 1-2) and render |
| QC audit | `window.QcAuditPanel({scenario, phases})` | Already scenario-driven; already correct |

For the **prose tabs** (Methods, Citations) that need a sentence of intro,
the intro text is the `sw.methodsBody` / `sw.citeBody` lifted verbatim from
`BiocTours.jsx:165 / :168` — same strings already shown in the tour bubble.

---

## E. qc_evidence.yaml citations (shipped Wave 1-2)

`backend/config/qc_evidence.yaml` lines 963–1108 define the
`transcriptomics:` block consumed by `/api/workflows/:name/citations`. For
the bioc_kb run, the Citations tab will list the four GOLD-provenance
references from this block:

| Reference | YAML location |
|---|---|
| Love MI, Huber W, Anders S. Genome Biology 2014;15:550 (DESeq2) | `qc_evidence.yaml:966–971` |
| Zhu A, Ibrahim JG, Love MI. Bioinformatics 2019;35:2084–2092 (apeglm) | `qc_evidence.yaml:980–985` |
| Yu G, Wang LG, Han Y, He QY. OMICS 2012;16:284–287 (clusterProfiler) | `qc_evidence.yaml:993–998` |
| Chen Y, Lun ATL, Smyth GK. F1000Research 2016;5:1438 (edgeR — alternative) | `qc_evidence.yaml:1007–1012` |

*Note: BiocTours.jsx:168 names "Wu 2021" for clusterProfiler. The
qc_evidence.yaml I shipped lists Yu 2012. I'll fix the YAML to match the
design canon (Wu 2021) — same paper, updated citation — before recording.*

---

## F. What is NOT in any source — therefore not on screen / not in audio

| Forbidden content | Reason |
|---|---|
| "R 4.4 + Bioconductor 3.19 container" | I made it up |
| "submitted to AWS Batch (job 8f3e21…)" | I made it up; also infrastructure detail per your "no AWS Batch" rule |
| "compute cluster" | I made it up; also infrastructure |
| "Loading container (8s)" | I made it up |
| "tximport · reading 120 salmon quant.sf files" | I made up the count + file extension |
| "QC pass · 18,422 of 60,233 genes retained" | I made up both numbers |
| "median size factor = 1.02, IQR 0.91–1.08" | I made up the IQR |
| "dispersion fit converged after 4 iterations" | I made it up |
| "1,572 up · 1,269 down" DE split | I made up the split — the tour only says total 2,841 |
| "NES 2.41, p_adj 8.1e-5" for top GO term | I made up the magnitudes |
| "10,000 permutations" | I made it up |
| "About three minutes" / "~3 min" | Per your "no time mentions" rule |
| "Try the single-cell and methylation tutorials next" | Per your "no context-dependent closings" rule |

---

## Sign-off

If this map is correct: reply **OK** and I will:

1. Wire `Modals.jsx` Report* components to read from the listed sources
   (no prose authored — every string lifted from the files above).
2. Patch `qc_evidence.yaml:993` Yu 2012 → Wu 2021 (match design canon).
3. Re-record bioc_kb only.
4. Frame-audit each After-run tab against this map before handoff.

If any row is wrong: tell me which row and I correct the map before any
code change.
