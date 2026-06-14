#!/usr/bin/env python3
"""
First-class VISUALIZATION + QC metadata for each Bioconductor workflow.

Packages ship rich built-in visualization (clusterProfiler: dotplot/cnetplot;
DESeq2: plotMA/plotPCA; miaViz; edgeR/limma: plotMDS/volcanoplot) and QC operations
(filtering, normalization diagnostics, outlier detection). The workflows already
*call* these, but they were only buried in the R + step text. This extracts them
into dedicated, searchable fields:
  - `// Visualizations:` header + DB column `visualization_tools`
  - `// QC:` header + DB column `qc_steps`
so the UI can show "what plots you get" and "what QC is done" per workflow.

Usage: python3 backend/scripts/enrich_bioc_viz_qc.py [--dry-run] [--no-db]
"""
from __future__ import annotations
import argparse, json, re, shutil, sqlite3, time
from pathlib import Path

BIOC = Path(__file__).resolve().parents[1] / \
    "biomni_workflows/nextflow_nfcore/subworkflows/bioconductor"
DB = Path("/home/yzhang/biomate/backend/database/galaxy_ai_tools.db")
REL = "nextflow_nfcore/subworkflows/bioconductor"

# Known Bioconductor + base/ggplot visualization functions (call -> human label)
VIZ_FUNCS = {
    # clusterProfiler / enrichplot
    "dotplot": "dot plot", "cnetplot": "gene-concept network", "emapplot": "enrichment map",
    "goplot": "GO DAG plot", "ridgeplot": "ridge plot", "upsetplot": "UpSet plot",
    "heatplot": "heat plot", "gseaplot": "GSEA plot", "gseaplot2": "GSEA plot", "treeplot": "tree plot",
    # DESeq2 / edgeR / limma
    "plotMA": "MA plot", "plotPCA": "PCA plot", "plotDispEsts": "dispersion plot",
    "plotCounts": "gene count plot", "plotMDS": "MDS plot", "plotBCV": "BCV plot",
    "plotSmear": "smear plot", "volcanoplot": "volcano plot", "plotMD": "mean-difference plot",
    "glMDPlot": "interactive MD plot", "glimmaMDS": "interactive MDS",
    # heatmaps / general
    "pheatmap": "heatmap", "Heatmap": "heatmap (ComplexHeatmap)", "heatmap.2": "heatmap",
    "EnhancedVolcano": "volcano plot", "barplot": "bar plot", "boxplot": "box plot",
    # mia / miaViz / microbiome
    "plotAbundance": "abundance plot", "plotColData": "sample metadata plot",
    "plotReducedDim": "ordination plot", "plotRDA": "RDA plot", "plotDMN": "DMN fit plot",
    "plotPrevalence": "prevalence plot", "plot_richness": "alpha diversity plot",
    "plot_ordination": "ordination plot", "plot_bar": "taxa bar plot",
    # fgsea / GSVA / methylation / flow / imaging
    "plotEnrichment": "enrichment plot", "plotGseaTable": "GSEA table plot",
    "densityplot": "density plot", "autoplot": "autoplot", "image": "image plot",
    "fviz_": "factoextra plot", "vizDiagnostics": "diagnostics plot",
    # single-cell (scater / scran / Seurat / monocle)
    "plotUMAP": "UMAP plot", "plotTSNE": "t-SNE plot", "plotExpression": "expression plot",
    "plotHighestExprs": "highest-expression plot", "plotScater": "QC scatter plot",
    "plotDots": "dot plot", "DimPlot": "UMAP/t-SNE plot", "FeaturePlot": "feature plot",
    "VlnPlot": "violin plot", "RidgePlot": "ridge plot", "DoHeatmap": "heatmap",
    "ElbowPlot": "elbow plot", "plot_cells": "trajectory plot",
    "plot_genes_in_pseudotime": "pseudotime plot",
    # high-frequency gaps surfaced by docs/20260614_BIOC_VIZ_COVERAGE_AUDIT.md
    "heatmap": "heatmap",                    # base graphics heatmap() — the single biggest miss (97 calls)
    "plotHeatmap": "heatmap", "meanSdPlot": "mean-SD plot",
    "plotVolcano": "volcano plot", "MAplot": "MA plot",
    "plotTracks": "genomic tracks (Gviz)", "plotRegion": "genomic region plot",
    "plotProfile": "profile plot", "plotCorrelation": "correlation plot",
    "ggtree": "phylogenetic tree", "plotKaryotype": "karyotype plot",
    "chordDiagram": "circos plot", "circlize": "circos plot",
    "pathview": "pathway diagram", "plotROC": "ROC curve", "plotPCA3D": "3D PCA plot",
    # long-tail uncovered functions from the same audit
    "qcReport": "array QC report", "plotDensities": "density plot",
    "plotRLE": "RLE plot", "mdsPlot": "MDS plot",
    "vennDiagram": "Venn diagram", "venn": "Venn diagram", "upset": "UpSet plot",
    "qq": "QQ plot", "plotManhattan": "Manhattan plot",
    "ggbio": "genomic plot (ggbio)", "forestplot": "forest plot",
    "corrplot": "correlation plot", "densityPlot": "density plot",
    "plotDiagnostics": "diagnostic plot", "plotDMRs": "DMR plot",
    "ideogram": "ideogram", "plotChromosome": "chromosome plot",
    "plotGenes": "gene track plot", "fviz_nbclust": "elbow plot",
    "beeswarm": "beeswarm plot", "plotSA": "SA diagnostic",
    "plotCoverage": "coverage plot", "screeplot": "scree plot",
    "biplot": "biplot", "plotPosterior": "posterior plot",
    "xyplot": "scatter plot", "levelplot": "level plot", "splom": "scatter matrix",
    "cloud": "3D scatter", "smoothScatter": "smooth scatter",
    "plotDendrogram": "dendrogram", "dendrogram": "dendrogram",
    "stripchart": "strip chart", "matplot": "matrix plot",
    "mosaicplot": "mosaic plot",
}
# generic plotting devices / ggplot indicate a figure is produced
GENERIC_VIZ = ("ggplot", "ggsave", "pdf(", "png(", "tiff(", "svg(", "jpeg(", "bmp(", "dev.print")

# figure-output filename hints -> specific plot label (used when a step writes a figure
# but no *named* viz function matched, e.g. a ggplot saved to "pca_plot.pdf").
FIG_HINTS = [
    (r'umap', "UMAP plot"), (r'tsne|t[-_.]?sne', "t-SNE plot"), (r'\bpca\b|pca[_.-]', "PCA plot"),
    (r'\bmds\b', "MDS plot"), (r'volcano', "volcano plot"), (r'heatmap', "heatmap"),
    (r'\bma[_.-]?plot', "MA plot"), (r'dispersion|\bbcv\b', "dispersion plot"),
    (r'dot[_.-]?plot', "dot plot"), (r'box[_.-]?plot', "box plot"), (r'bar[_.-]?plot', "bar plot"),
    (r'violin|\bvln\b', "violin plot"), (r'density', "density plot"), (r'ridge', "ridge plot"),
    (r'ordination|nmds|\brda\b|\bcca\b', "ordination plot"),
    (r'richness|alpha[_.-]?div|diversity', "diversity plot"), (r'cnet|network', "network plot"),
    (r'enrich|emap|gsea', "enrichment plot"), (r'cluster', "cluster plot"),
    (r'pseudotime|trajectory', "trajectory plot"), (r'\bqc\b', "QC plot"),
    (r'scatter', "scatter plot"), (r'elbow', "elbow plot"), (r'survival|kaplan', "survival plot"),
    # broader hints to shrink the 1,487 generic-only bucket from the 06-14 audit
    (r'\btrack', "genomic tracks"), (r'\bprofile\b', "profile plot"),
    (r'\bcorrelation\b|\bcorr\b', "correlation plot"),
    (r'karyotype|ideogram', "karyotype plot"),
    (r'pathway|\bkegg\b', "pathway diagram"),
    (r'\broc\b', "ROC curve"), (r'manhattan', "Manhattan plot"),
    (r'\bqq\b', "QQ plot"), (r'tree|phylo', "phylogenetic tree"),
    (r'mean[_.-]?sd', "mean-SD plot"), (r'\brle\b', "RLE plot"),
    (r'forest', "forest plot"), (r'circos|chord', "circos plot"),
    (r'venn', "Venn diagram"), (r'upset', "UpSet plot"),
    (r'mds[_.-]', "MDS plot"), (r'biplot', "biplot"),
    (r'beeswarm', "beeswarm plot"), (r'coverage', "coverage plot"),
    (r'screeplot|\bscree\b', "scree plot"),
    (r'mosaic', "mosaic plot"), (r'strip[_.-]?chart', "strip chart"),
]


def viz_from_figure_files(figure_files: list[str]) -> list[str]:
    """Derive specific plot labels from figure output filenames (PCA plot, UMAP plot...)."""
    out: list[str] = []
    for fn in figure_files:
        low = fn.lower()
        for pat, label in FIG_HINTS:
            if re.search(pat, low) and label not in out:
                out.append(label)
    return out

# QC operation patterns (function/keyword -> label)
QC_PATTERNS = [
    (r'\bfilterByExpr\b', "filter low-expression genes"),
    (r'\bcalcNormFactors\b', "TMM normalization"),
    (r'\bestimateDisp\b|\bestimateSizeFactors\b', "dispersion/size-factor estimation"),
    (r'\bplotDispEsts\b|\bplotBCV\b', "dispersion QC plot"),
    (r'\bperCellQCMetrics\b|\baddPerCellQC\b|\bquickPerCellQC\b', "per-cell QC metrics"),
    (r'\bisOutlier\b|\bperFeatureQCMetrics\b', "outlier detection"),
    (r'\bplotMA\b|\bplotPCA\b', "diagnostic MA/PCA QC"),
    (r'\b(prevalence|abundance)[ _]?filter|filterTaxa|prune_taxa\b', "prevalence/abundance filtering"),
    (r'\bvalidObject\b|\bstopifnot\b|\bcheckmate\b', "input validation"),
    (r'\blow[ _-]?count|removeLowCount|rowSums\([^)]*\)\s*[<>]', "low-count filtering"),
    (r'\bremoveBatchEffect\b|\bComBat\b|\bsva\b|\bfastMNN\b|\bharmony\b', "batch-effect correction"),
    (r'\bcomplete\.cases\b|\bna\.omit\b|\bimpute', "missing-value handling"),
    (r'\bscDblFinder\b|\bfindDoubletClusters\b|\bdoublet', "doublet detection QC"),
    (r'\bcalculateQCMetrics\b|\baddQCPerCell\b|\bscater\b|\bemptyDrops\b', "cell QC metrics"),
    (r'\blogNormCounts\b|\bnormalizeCounts\b|\bSCTransform\b|\bvst\b|\brlog\b|\bcpm\b', "count normalization"),
    (r'\bmodelGeneVar\b|\bgetTopHVGs\b|\bFindVariableFeatures\b', "highly-variable feature selection"),
    (r'\bquickCluster\b|\bclusterCells\b|\bFindClusters\b|\bbuildSNNGraph\b', "clustering QC"),
    (r'\bmapQuality\b|\bsummarizeOverlaps\b|\bmappingStats\b', "alignment/mapping QC"),
    (r'\bdetectionPVal\b|\bdetectionP\b|\bqcReport\b|\bbeadcount\b', "array detection QC"),
    (r'\bvoom\b|\bvoomWithQualityWeights\b', "voom mean-variance modelling"),
    (r'\bnormalizeBetweenArrays\b|\bnormalizeQuantiles\b', "between-array normalization"),
    (r'\bvsn\b|\bjustvsn\b|\bnormalizeVSN\b', "variance-stabilizing normalization"),
    (r'\bplotDensities\b|\bmeanSdPlot\b|\bplotSA\b|\bplotMeanVar\b', "normalization diagnostic plot"),
    (r'\bcooks\.distance\b|\boutlierDetection\b|\breplaceOutliers\b', "outlier diagnostics"),
    (r'\baveLogCPM\b|\bgoodTuringProportions\b', "expression-level QC"),
]


def extract_r(content: str) -> str:
    # Current corpus: R lives inside the nextflow `script: """ ... """` block and the
    # versions footer is R writeLines (no more `cat <<-END_VERSIONS`). Grab from the
    # Rscript shebang to the closing triple-quote of the script block.
    m = re.search(r'#!/usr/bin/env Rscript(.*?)\n[ \t]*"""', content, re.DOTALL)
    if m:
        return m.group(1).replace('\\$', '$')
    # legacy fallback (older corpus used a cat <<-END_VERSIONS terminator)
    m = re.search(r'(#!/usr/bin/env Rscript.*?)\n\s*cat <<-END_VERSIONS', content, re.DOTALL)
    return (m.group(1) if m else "").replace('\\$', '$')


def viz_of(r: str) -> list[str]:
    found = []
    for fn, label in VIZ_FUNCS.items():
        if re.search(r'\b' + re.escape(fn) + r'\s*\(', r) or (fn.endswith("_") and fn in r):
            if label not in found:
                found.append(label)
    if any(g in r for g in GENERIC_VIZ):
        # generic plotting present — try to name it from the saved figure filenames in the R
        figs = re.findall(r'["\']([A-Za-z0-9_./-]+\.(?:pdf|png|tiff|svg|jpe?g))["\']', r)
        for label in viz_from_figure_files(figs):
            if label not in found:
                found.append(label)
        if not found:
            found.append("plot (ggplot/base)")
    return found


def qc_of(r: str) -> list[str]:
    found = []
    for pat, label in QC_PATTERNS:
        if re.search(pat, r) and label not in found:
            found.append(label)
    return found


def hdr_block(tag: str, items: list[str]) -> str:
    return f"// {tag}: {', '.join(items)}\n" if items else ""


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--no-db", action="store_true")
    args = ap.parse_args()
    rows = {}
    n = 0
    for nf in BIOC.rglob("*.nf"):
        c = nf.read_text(errors="replace")
        if "Document-derived" not in c and "real input-consuming" not in c:
            continue
        r = extract_r(c)
        viz, qc = viz_of(r), qc_of(r)
        rows[f"{REL}/{nf.parent.name}/{nf.name}"] = (viz, qc)
        # write headers (idempotent) after // Requires: (or before nextflow.enable.dsl)
        new = re.sub(r'// Visualizations:.*\n', '', c)
        new = re.sub(r'// QC:.*\n', '', new)
        block = hdr_block("Visualizations", viz) + hdr_block("QC", qc)
        if block:
            if "// Requires:" in new:
                new = re.sub(r'(// Requires:.*\n)', r'\1' + block, new, count=1)
            else:
                new = new.replace("nextflow.enable.dsl", block + "\nnextflow.enable.dsl", 1)
        if new != c and not args.dry_run:
            nf.write_text(new)
        n += 1
    nv = sum(1 for v, q in rows.values() if v)
    nq = sum(1 for v, q in rows.values() if q)
    print(f"[viz-qc] {n} workflows: {nv} with visualizations, {nq} with QC steps (dry_run={args.dry_run})")
    if args.dry_run or args.no_db:
        return 0
    bak = DB.with_suffix(f".db.bak.{int(time.time())}")
    shutil.copy(DB, bak)
    con = sqlite3.connect(str(DB)); cur = con.cursor()
    cols = {r[1] for r in cur.execute("PRAGMA table_info(workflows)")}
    for col in ("visualization_tools", "qc_steps"):
        if col not in cols:
            cur.execute(f"ALTER TABLE workflows ADD COLUMN {col} TEXT")
    u = 0
    for fn, (viz, qc) in rows.items():
        res = cur.execute("UPDATE workflows SET visualization_tools=?, qc_steps=? "
                          "WHERE source='bioconductor' AND filename=?",
                          (json.dumps(viz), json.dumps(qc), fn))
        u += res.rowcount
    con.commit(); con.close()
    print(f"[viz-qc] DB: added columns + updated {u} rows (backup {bak.name})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
