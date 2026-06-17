# Bioconductor Visualization Coverage Audit

Date: 2026-06-14
Scope: Do BioMate's recognition vocab + frontend renderer cover EVERY visualization
that the Bioconductor workflow corpus actually produces?

Method: cross-checked three layers against the live files/DB — no production `.nf` or
DB edits (read-only audit).

- Corpus: `backend/biomni_workflows/nextflow_nfcore/subworkflows/bioconductor/**/*.nf`
  — 3,353 `.nf` total; 3,220 are enrichment-eligible (contain `Document-derived` /
  `real input-consuming`).
- DB: `backend/database/galaxy_ai_tools.db`, table `workflows` (source=`bioconductor`,
  3,310 rows). Viz lives in columns `visualization_tools`, `qc_steps`, `step_metadata`.

## TL;DR

- **Layer 1 vocab (`VIZ_FUNCS`)** recognizes **57 named plotting functions** + a generic
  catch-all + 24 figure-filename hints.
- **Layer 2 ground truth**: the corpus calls **96 distinct *named* plotting functions**
  (plus the base/ggplot generic family). Only **48 / 96 = 50%** of distinct named
  plotting functions are in the vocab. By call-volume the named coverage is **68%**.
- **The real surfacing gap is the generic catch-all**: **1,487 / 3,220 workflows (46%)**
  emit figures but get only the unhelpful label `"plot (ggplot/base)"` — no specific
  plot type — because they use base `plot()` / `hist()` / `ggplot()` saving to filenames
  that match none of the 24 `FIG_HINTS` patterns. Only 338 workflows (10%) get a *named*
  viz label; 489 (15%) are rescued by a filename hint; 906 (28%) get no viz label at all.
- **RENDER GAP (the worst, highest-impact bug)**: **PDF is the dominant figure output
  (4,671 occurrences vs PNG 55)** yet the per-step viewer routes `.pdf` into an `<img>`
  tag (`IMAGE_EXTS` in `step-output-preview.tsx` includes `pdf`). Browsers cannot render
  a PDF in `<img>` → broken-image icon. So for ~the entire Bioconductor corpus, the
  primary figure output is effectively **un-previewable inline**.

---

## Layer 1 — What BioMate RECOGNIZES (the vocabulary)

Source: `backend/scripts/enrich_bioc_viz_qc.py` (`VIZ_FUNCS`, `GENERIC_VIZ`, `FIG_HINTS`,
`QC_PATTERNS`); per-step attribution in `enrich_bioc_step_metadata.py`.

### `VIZ_FUNCS` (57 named function → label entries)

clusterProfiler/enrichplot: `dotplot, cnetplot, emapplot, goplot, ridgeplot, upsetplot,
heatplot, gseaplot, gseaplot2, treeplot`
DESeq2/edgeR/limma: `plotMA, plotPCA, plotDispEsts, plotCounts, plotMDS, plotBCV,
plotSmear, volcanoplot, plotMD, glMDPlot, glimmaMDS`
heatmaps/general: `pheatmap, Heatmap, heatmap.2, EnhancedVolcano, barplot, boxplot`
mia/miaViz/microbiome: `plotAbundance, plotColData, plotReducedDim, plotRDA, plotDMN,
plotPrevalence, plot_richness, plot_ordination, plot_bar`
fgsea/GSVA/methyl/flow/imaging: `plotEnrichment, plotGseaTable, densityplot, autoplot,
image, fviz_, vizDiagnostics`
single-cell: `plotUMAP, plotTSNE, plotExpression, plotHighestExprs, plotScater, plotDots,
DimPlot, FeaturePlot, VlnPlot, RidgePlot, DoHeatmap, ElbowPlot, plot_cells,
plot_genes_in_pseudotime`

Generic catch-all (`GENERIC_VIZ`): `ggplot, ggsave, pdf(, png(, tiff(, svg(, jpeg(, bmp(,
dev.print` → label `"plot (ggplot/base)"` when no named fn or fig-hint matches.

`FIG_HINTS` (24 filename → label regexes): umap, tsne, pca, mds, volcano, heatmap, ma_plot,
dispersion/bcv, dotplot, boxplot, barplot, violin/vln, density, ridge, ordination/nmds/rda/cca,
richness/diversity, cnet/network, enrich/emap/gsea, cluster, pseudotime/trajectory, qc,
scatter, elbow, survival/kaplan.

`QC_PATTERNS`: 25 regex → QC-step labels (filterByExpr, calcNormFactors, estimateDisp,
perCellQCMetrics, isOutlier, removeBatchEffect/ComBat/sva/harmony, scDblFinder/doublet,
voom, vsn, normalizeBetweenArrays, etc.).

### DB coverage (how many rows actually carry viz)

| field | non-empty bioc rows | of 3,310 |
|---|---|---|
| `visualization_tools` | 2,124 | 64% |
| `qc_steps` | 354 | 11% |
| `step_metadata` | 3,148 | 95% |

`step_metadata`: 11,603 total steps, **2,811 steps (24%)** carry a non-empty
`visualizations` array.

### Distinct viz labels present in the DB (`visualization_tools`, top of 50 labels)

`plot (ggplot/base)` **1,360** · heatmap 192 · bar plot 117 · box plot 100 · cluster plot 76 ·
PCA plot 70 · enrichment plot 68 · network plot 50 · volcano plot 48 · density plot 47 ·
image plot 32 · scatter plot 26 · UMAP 24 · MA plot 23 · ComplexHeatmap 23 · t-SNE 20 ·
ordination 19 · dot plot 18 · survival 15 · violin 11 · … (long tail of 1–7 each).

**The single label `"plot (ggplot/base)"` dominates (1,360 workflows / 64% of viz-bearing
rows)** — i.e. for most workflows we know "a figure is produced" but not *what* figure.

---

## Layer 2 — What the WORKFLOWS ACTUALLY PRODUCE (ground truth)

Scanned the R script body (`#!/usr/bin/env Rscript … """`) of all 3,220 eligible `.nf`.
Function-call frequency = number of workflows that invoke it.

### Named plotting functions actually called (distinct = 96; 48 covered, 48 uncovered)

**Covered by `VIZ_FUNCS` (48 distinct, top):** barplot 113, Heatmap 96, boxplot 93,
image 41, pheatmap 19, plotPCA 18, plotReducedDim 13, plotMA 12, dotplot 10, DimPlot 7,
FeaturePlot 7, autoplot 7, plotMD 7, plotTSNE 7, plotCounts 7, volcanoplot 6,
plotDispEsts 5, heatmap.2 4, cnetplot 4, emapplot 4, … (rest 1–3 each).

**NOT in `VIZ_FUNCS` — produced but never given a specific label unless a filename hint
happens to fire (48 distinct, by frequency):**

| count | function | what it draws |
|---|---|---|
| **97** | `heatmap` (base R) | heatmap — base `heatmap()` is NOT a key (only `Heatmap`/`heatmap.2`/`pheatmap` are) |
| 11 | `plotTracks` (Gviz) | genome browser track plot |
| 9 | `plotVolcano` | volcano plot (custom/Glimma) |
| 8 | `plotHeatmap` (deepTools/scater) | heatmap |
| 8 | `plotRegion` (methylation) | DMR region plot |
| 7 | `plotProfile` (deepTools) | metagene profile |
| 6 | `ggtree` | phylogenetic tree |
| 6 | `xyplot` (lattice) | scatter |
| 5 | `plotQC` | QC plot |
| 5 | `MAplot` (affy) | MA plot |
| 5 | `meanSdPlot` (vsn) | mean-SD diagnostic |
| 5 | `plotCorrelation` (deepTools) | sample-correlation heatmap |
| 4 | `plotRLE` | relative-log-expression |
| 4 | `circos` / `chordDiagram` (circlize) | circos plot |
| 4 | `cloud` (lattice) | 3D scatter |
| 4 | `qcReport` (minfi) | array QC report |
| 4 | `pathview` | KEGG pathway map |
| 4 | `plotROC` | ROC curve |
| 4 | `plotKaryotype` (karyoploteR) | karyotype/ideogram |
| 4 | `plotDensities` (limma) | density diagnostic |
| 3 | `venn` / `upset` | set-overlap (vennDiagram present too) |
| 3 | `plotManhattan` | Manhattan plot |
| 3 | `qq` | QQ plot |
| 2 | `mdsPlot` (minfi) | MDS |
| 2 | `levelplot` / `splom` (lattice) | level/scatter-matrix |
| 2 | `plotMatrix`, `plotDiagnostics`, `Gviz`, `plotDMRs`, `corrplot`, `densityPlot`, `plotPosterior` | various |
| 1 | `image.plot`, `plotChromosome`, `plotMarkerHeatmap`, `ideogram`, `plotGenes`, `forestplot`, `fviz_nbclust`, `beeswarm`, `plotSA`, `anno_barplot`, `ComplexHeatmap`, `plotCoverage`, `ggbio` | various |

**Generic base/ggplot family (32 distinct) → only ever the catch-all `"plot"` label:**
`plot` 1,124, `ggsave` 199, `hist` 145, `ggplot` 140, `plot.new` 114, `geom_point` 86,
`facet_wrap` 26, `plot_grid` 24, `geom_boxplot` 20, `geom_bar` 20, `geom_line` 19,
`pairs` 18, `grid.arrange` 16, `geom_histogram` 15, `facet_grid` 14, `geom_density` 11,
`ggarrange` 7, `biplot` 6, `matplot` 6, `dendrogram` 5, `geom_violin` 5, `stripchart` 4,
`geom_tile` 4, `plotly` 3, `geom_col` 3, `qplot` 3, `screeplot` 3, `smoothScatter` 2,
`ggplotly` 2, `mosaicplot` 1, `ggdraw` 1, `plotDendrogram` 1.

### Figure output file types emitted (occurrences across R bodies / output decls)

| ext | occurrences |
|---|---|
| **pdf** | **4,671** |
| html | 137 |
| png | 55 |
| tif | 21 |
| jpg | 18 |
| svg | 10 |
| tiff | 8 |
| ps | 4 |
| eps | 4 |
| jpeg | 3 |

**PDF is ~85× more common than PNG.** The corpus is overwhelmingly PDF-figure-based
(R's default `pdf()` device + `ggsave(... .pdf)`).

---

## Layer 3 — What BioMate can RENDER (frontend output preview)

Per-step viewer: `frontend/client/src/components/step-output-preview.tsx`
(`resolveViewer(ext)`); chat-level: `frontend/client/src/components/chat-output-attachments.tsx`
(driven by server `fileType`). Step-file serving: `frontend/server/routes.ts`
`/api/workflows/runs/:id/step-file` (line 10188); classifiers `getFileType` (line 98) and
`classifyFileType` (line 13857). Backend step→viz serving:
`backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` `_steps_from_db_metadata`
(line 4319) / `get_nextflow_steps` (line 4357) — passes the DB `visualizations`/`qc`/
`outputs` arrays straight through to the UI.

Renderer extension map (`step-output-preview.tsx`):
- `IMAGE_EXTS = {png, jpg, jpeg, gif, svg, **pdf**}` → `<img>` lightbox
- `TABLE_EXTS = {csv, tsv, json, tabular, star}` → inline table
- `SEQ_EXTS {fasta,fa,fastq,fq}` / `VCF_EXTS {vcf,bcf}` / `ANNOT_EXTS {bed,gff,gtf,gff3}`
- `STRUCT_EXTS {pdb,mmcif,cif}` → 3Dmol · `DENSITY_EXTS {mrc,map,mrcs,rec}` → DensityMapViewer
- `HTML_EXTS {html,htm}` → sandboxed iframe · `TEXT_EXTS {log,txt,sh,py,out,err}` → `<pre>`
- `R_EXTS {rds,rdata}` → "open in RStudio" · everything else → download link

### RENDER GAPS

1. **PDF rendered as `<img>` → broken image (CRITICAL).** `pdf` is in `IMAGE_EXTS`, so a
   `.pdf` figure becomes `<img src=blob:…pdf>`. Browsers do not render PDF in `<img>`;
   the user sees a broken-image icon. This affects the **dominant** figure output of the
   entire Bioconductor corpus (4,671 PDF occurrences). `chat-output-attachments` has the
   same bug: server `classifyFileType` (routes.ts:13860) maps `pdf → image` → `ImageOutput`
   → `<img>`. There is **no PDF→PNG conversion anywhere in the backend** (grep for
   pdftoppm / pdf2image / ghostscript = 0 hits). Note an internal inconsistency: the
   legacy `getFileType` (routes.ts:102) maps `pdf → interactive` (iframe, which *would*
   render via the browser PDF plugin) — the two classifiers disagree, and the per-step
   viewer path uses the broken `image` route.
2. **`tif` / `tiff` not rendered.** Not in `IMAGE_EXTS` (only png/jpg/jpeg/gif/svg/pdf) →
   falls through to download link. 21+8 occurrences. Browsers can't natively show TIFF
   anyway, so this needs server-side conversion, but today it is silently a download.
3. **`eps` / `ps` (PostScript) not rendered** → download only (minor, 4+4).
4. **Interactive `.html` plots (plotly/Glimma/ggiraph) DO render** via sandboxed iframe —
   good. 137 html occurrences are covered. (`getFileType` path also routes html→iframe.)

---

## COVERAGE GAP — quantified answer

### Layer 1 vs Layer 2 (vocabulary)
- Distinct *named* plotting functions in corpus: **96**
- In `VIZ_FUNCS`: **48** → **50% of distinct named functions covered**
- Weighted by #workflows that call them: covered 522 vs uncovered 250 →
  **68% of named-call volume covered**
- Top uncovered by volume: base `heatmap()` (97), `plotTracks` (11), `plotVolcano` (9),
  `plotHeatmap` (8), `plotRegion` (8), `plotProfile` (7), `ggtree` (6), `MAplot` (5),
  `meanSdPlot` (5), `plotCorrelation` (5), `plotKaryotype`/`circos` (4 each),
  `pathview` (4), `plotROC` (4), `qcReport` (4).

### Specificity gap (the bigger problem) — per-workflow label quality

| outcome | workflows | % |
|---|---|---|
| named viz label (specific) | 338 | 10% |
| rescued by filename hint | 489 | 15% |
| **generic `"plot (ggplot/base)"` only** | **1,487** | **46%** |
| no viz label at all | 906 | 28% |

So **74% of viz-producing workflows surface either a vague "plot" label or nothing
specific.** The vocabulary is fine for the headline tools (DESeq2/edgeR/clusterProfiler);
it collapses for the long tail that draws figures with base `plot()`/`ggplot()` + generic
filenames, and for the 48 uncovered named functions.

### Layer 3 render gap
- **PDF** (dominant, 4,671) → **broken `<img>`** — the single highest-impact defect.
- `tif/tiff` (29) → download only. `eps/ps` (8) → download only.
- png/jpg/svg/gif/html/csv/tsv/json/fasta/vcf/bed/gff/pdb/mrc all render. PDF is the
  glaring exception precisely because it is the most common.

---

## WHAT NEEDS TO BE DONE (prioritized)

### P0 — Render PDF figures (highest impact, smallest change)
The corpus is ~85% PDF figures and they currently show a broken image. Two options:
- **(a) Quick:** in `step-output-preview.tsx` move `pdf` out of `IMAGE_EXTS` into a new
  `pdf` viewer that renders `<iframe src=blob:…pdf>` or `<embed type=application/pdf>`
  (browser plugin), mirroring what `getFileType` already intends. Same one-line fix in
  `classifyFileType` (routes.ts:13860) so `chat-output-attachments` routes pdf →
  `InteractiveOutput` (iframe), not `ImageOutput`. **Effort: ~1h. Impact: unblocks inline
  preview for the dominant output of the whole bioc corpus.**
- **(b) Robust:** server-side rasterize PDF → PNG (pdftoppm/ghostscript, first page) at the
  `step-file` endpoint when `?as=png`, and keep the `<img>` path. Better thumbnails, works
  everywhere, but adds a system dep + a conversion route. **Effort: ~half day.**
  Recommend (a) now, (b) later for thumbnails. Also add `tif/tiff` → server PNG conversion
  (browsers can't show TIFF) — fold into (b).

### P1 — Add the high-frequency uncovered named functions to `VIZ_FUNCS`
Add these 14 (covers the bulk of the uncovered call-volume), then re-run enrichment:
```
heatmap → "heatmap"                 # base R heatmap(), 97 calls — biggest single miss
plotTracks → "genome track plot"    # Gviz, 11
plotVolcano → "volcano plot"        # 9
plotHeatmap → "heatmap"             # scater/deepTools, 8
plotRegion → "methylation region plot" # 8
plotProfile → "profile plot"        # deepTools, 7
ggtree → "phylogenetic tree"        # 6
MAplot → "MA plot"                  # affy, 5
meanSdPlot → "mean-SD plot"         # vsn, 5
plotCorrelation → "correlation heatmap" # deepTools, 5
plotKaryotype → "karyotype plot"    # karyoploteR, 4
pathview → "KEGG pathway map"       # 4
plotROC → "ROC curve"               # 4
chordDiagram/circos → "circos plot" # circlize, 4
```
Plus the long tail (qcReport, plotDensities, plotRLE, mdsPlot, vennDiagram/venn, qq,
plotManhattan, ggbio, forestplot) for completeness. **Effort: ~1–2h to add + re-enrich.
Impact: lifts named distinct coverage 50% → ~75%, and reclassifies a chunk of the
"plot (ggplot/base)" rows into specific labels.**

### P1 — Broaden `FIG_HINTS` to shrink the 1,487 generic-only bucket
The catch-all dominates because filenames like `figure1.pdf`, `output.pdf`, `result_plot.pdf`
match no hint. Add hints for: `\btrack`, `\bprofile`, `\bcorrelation\b|corr`, `karyotype|ideogram`,
`pathway|kegg`, `\broc\b`, `manhattan`, `\bqq\b`, `tree|phylo`, `mean[_.-]?sd`, `rle`,
`forest`, `circos|chord`. Each new hint converts some generic-only workflows to a specific
label without touching `.nf`. **Effort: ~1h. Impact: meaningfully reduces the 46% generic
bucket.**

### P2 — Re-enrichment pass (required after P1 vocab/hint changes)
Re-run `python3 backend/scripts/enrich_bioc_viz_qc.py` then
`python3 backend/scripts/enrich_bioc_step_metadata.py` (both write `.nf` headers + DB cols,
make a timestamped `.db.bak`). The serving path (`_steps_from_db_metadata` →
`/api/nextflow/steps`) needs no change — it passes the DB `visualizations` array straight
through, so new labels surface automatically once the DB is re-enriched.
**Effort: ~15 min run + spot-check. Impact: applies P1 across all 3,220 workflows.**

### P3 — Reconcile the two server classifiers
`getFileType` (routes.ts:98) and `classifyFileType` (routes.ts:13857) disagree on `pdf`
(interactive vs image) and on `html`/`bed`/`gff`. Collapse to one classifier to prevent
the per-path render divergence that caused the PDF bug. **Effort: ~1h. Impact: correctness
+ maintainability.**

---

## Key files
- Vocab: `backend/scripts/enrich_bioc_viz_qc.py` (VIZ_FUNCS L26, GENERIC_VIZ L57, FIG_HINTS L61, QC_PATTERNS L86)
- Per-step attribution: `backend/scripts/enrich_bioc_step_metadata.py`
- DB: `backend/database/galaxy_ai_tools.db` table `workflows` cols `visualization_tools`/`qc_steps`/`step_metadata`
- Serving: `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` `_steps_from_db_metadata` (L4319), `get_nextflow_steps` (L4357)
- Renderer: `frontend/client/src/components/step-output-preview.tsx` (IMAGE_EXTS L51, resolveViewer L69)
- Chat renderer: `frontend/client/src/components/chat-output-attachments.tsx`
- Classifiers + step-file endpoint: `frontend/server/routes.ts` (getFileType L98, step-file L10188, classifyFileType L13857)
