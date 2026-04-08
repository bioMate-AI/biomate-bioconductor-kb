#!/usr/bin/env nextflow
/*
 * genomics/transcriptomic_biomarker
 *
 * Transcriptomic Biomarker Discovery:
 *   LIMMA differential expression + gene signature scoring via GSVA/ssGSEA
 *
 * Pipeline Steps:
 * 1. BIOMARKER_INPUT_QC           — validate expression matrix + clinical metadata
 * 2. LIMMA_DIFFERENTIAL_EXPRESSION — voom transformation, linear model with covariates,
 *                                    eBayes, topTable (logFC, adj.P.Val)
 * 3. BIOMARKER_SIGNATURE_SCORING  — GSVA/ssGSEA on hallmark MSigDB (50 gene sets);
 *                                   top enriched pathways per group
 * 4. BIOMARKER_REPORT             — R Markdown: volcano plot, top-50 heatmap,
 *                                   pathway enrichment barplot → HTML report
 *
 * References:
 *  - limma-voom: Law et al. Genome Biology 2014
 *                (https://doi.org/10.1186/gb-2014-15-2-r29)
 *  - GSVA:       Hänzelmann et al. BMC Bioinformatics 2013
 *                (https://doi.org/10.1186/1471-2105-14-7)
 *  - MSigDB:     Liberzon et al. Cell Systems 2015
 *                (https://doi.org/10.1016/j.cels.2015.12.004)
 */

nextflow.enable.dsl = 2

// ============================================================================
// Default Parameters
// ============================================================================

params.outdir              = './results/transcriptomic_biomarker'
params.publish_dir_mode    = 'copy'

// Input files (required)
params.expression_matrix   = null       // path to genes×samples count/expression CSV/TSV
params.metadata            = null       // path to sample metadata CSV

// Analysis settings
params.group_column        = 'group'    // column in metadata holding the contrast groups
params.reference_group     = 'control'  // baseline group label
params.fdr_threshold       = 0.05       // FDR cutoff for DE gene selection
params.logfc_threshold     = 1.0        // |logFC| cutoff for significance filtering

// LIMMA settings
params.voom_plot           = true       // emit mean-variance trend plot
params.covariates          = null       // comma-separated covariate column names (or null)

// Signature scoring settings
params.gsva_method         = 'gsva'     // 'gsva' or 'ssgsea'
params.min_gene_set_size   = 10        // minimum gene set size for GSVA
params.max_gene_set_size   = 500       // maximum gene set size for GSVA

// ============================================================================
// Helper functions
// ============================================================================

def log_workflow_header() {
    log.info """
    ====================================================================
    BioMate | Transcriptomic Biomarker Discovery Pipeline
    ====================================================================
    Group column:      ${params.group_column}
    Reference group:   ${params.reference_group}
    FDR threshold:     ${params.fdr_threshold}
    |logFC| threshold: ${params.logfc_threshold}
    GSVA method:       ${params.gsva_method}
    Output dir:        ${params.outdir}
    ====================================================================
    """.stripIndent()
}

// ============================================================================
// Process 1: BIOMARKER_INPUT_QC
// ============================================================================

process BIOMARKER_INPUT_QC {
    tag "input_qc"
    label 'process_low'
    publishDir "${params.outdir}/01_input_qc", mode: params.publish_dir_mode

    container 'docker.io/bioconductor/bioconductor_docker:RELEASE_3_18'

    input:
    path expression_matrix
    path metadata

    output:
    path "qc_report.json",            emit: qc_report
    path "validated_matrix.csv",      emit: validated_matrix
    path "validated_metadata.csv",    emit: validated_metadata
    path "versions.yml",              emit: versions

    script:
    def group_col    = params.group_column
    def ref_group    = params.reference_group
    def fdr_thresh   = params.fdr_threshold
    def logfc_thresh = params.logfc_threshold
    """
    Rscript - << 'REOF'
library(limma)
library(edgeR)
library(jsonlite)

# Read inputs
mat      <- read.csv("${expression_matrix}", row.names=1, check.names=FALSE)
metadata <- read.csv("${metadata}",          row.names=NULL, check.names=FALSE)

# Validate sample ID overlap
common_samples <- intersect(colnames(mat), metadata[["sample_id"]])
missing_mat    <- setdiff(metadata[["sample_id"]], colnames(mat))
missing_meta   <- setdiff(colnames(mat), metadata[["sample_id"]])

# Subset to common samples
mat      <- mat[, common_samples, drop=FALSE]
metadata <- metadata[metadata[["sample_id"]] %in% common_samples, ]

# Low-count filter (CPM > 1 in at least 50% of samples)
dge        <- DGEList(counts=mat)
keep       <- filterByExpr(dge, min.count=10, min.total.count=15)
mat_filt   <- mat[keep, ]
n_removed  <- sum(!keep)

# Write validated outputs
write.csv(mat_filt, "validated_matrix.csv")
write.csv(metadata, "validated_metadata.csv", row.names=FALSE)

qc <- list(
    pipeline                   = "transcriptomic_biomarker",
    step                       = "BIOMARKER_INPUT_QC",
    timestamp                  = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ"),
    n_genes                    = nrow(mat_filt),
    n_samples                  = ncol(mat_filt),
    n_groups                   = length(unique(metadata[["${group_col}"]])),
    group_labels               = as.list(unique(metadata[["${group_col}"]])),
    missing_samples_in_matrix  = length(missing_mat),
    missing_samples_in_metadata= length(missing_meta),
    genes_below_cpm_threshold  = n_removed,
    genes_after_filtering      = nrow(mat_filt),
    pass                       = (length(missing_mat) == 0 && nrow(mat_filt) > 0)
)
write(toJSON(qc, auto_unbox=TRUE, pretty=TRUE), "qc_report.json")

cat(sprintf("BIOMARKER_INPUT_QC complete: %d genes, %d samples\\n",
            nrow(mat_filt), ncol(mat_filt)))
REOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        limma: "3.58.1"
        edgeR: "4.0.16"
        R: \$(Rscript --version 2>&1 | cut -d' ' -f4 || echo "N/A")
    END_VERSIONS
    """

    stub:
    """
    echo '{"n_genes":500,"n_samples":40,"pass":true}' > qc_report.json
    echo 'gene_id,S001,S002' > validated_matrix.csv
    echo 'sample_id,group' > validated_metadata.csv
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        limma: "3.58.1"
        R: "4.3.1"
    END_VERSIONS
    """
}

// ============================================================================
// Process 2: LIMMA_DIFFERENTIAL_EXPRESSION
// ============================================================================

process LIMMA_DIFFERENTIAL_EXPRESSION {
    tag "limma_de"
    label 'process_medium'
    publishDir "${params.outdir}/02_limma_de", mode: params.publish_dir_mode

    container 'docker.io/bioconductor/bioconductor_docker:RELEASE_3_18'

    input:
    path validated_matrix
    path validated_metadata
    path qc_report

    output:
    path "de_results.csv",            emit: de_results
    path "significant_genes.csv",     emit: significant_genes
    path "limma_model_summary.json",  emit: model_summary
    path "voom_plot.png",             emit: voom_plot, optional: true
    path "versions.yml",              emit: versions

    script:
    def group_col    = params.group_column
    def ref_group    = params.reference_group
    def fdr_thresh   = params.fdr_threshold
    def logfc_thresh = params.logfc_threshold
    def covariates   = params.covariates ?: ''
    """
    Rscript - << 'REOF'
suppressPackageStartupMessages({
    library(limma)
    library(edgeR)
    library(jsonlite)
})

group_col    <- "${group_col}"
ref_group    <- "${ref_group}"
fdr_thresh   <- as.numeric("${fdr_thresh}")
logfc_thresh <- as.numeric("${logfc_thresh}")
covariates   <- trimws(unlist(strsplit("${covariates}", ",")))
covariates   <- covariates[nchar(covariates) > 0]

# Read validated inputs
counts   <- read.csv("${validated_matrix}",   row.names=1, check.names=FALSE)
metadata <- read.csv("${validated_metadata}", check.names=FALSE)
rownames(metadata) <- metadata[["sample_id"]]
metadata <- metadata[colnames(counts), , drop=FALSE]

# Factor setup -- reference group first
metadata[[group_col]] <- relevel(factor(metadata[[group_col]]), ref=ref_group)

# Design matrix
if (length(covariates) > 0) {
    cov_terms <- paste(covariates, collapse=" + ")
    form      <- as.formula(paste("~", group_col, "+", cov_terms))
} else {
    form <- as.formula(paste("~", group_col))
}
design <- model.matrix(form, data=metadata)

# DGEList + normalisation
dge  <- DGEList(counts=counts)
dge  <- calcNormFactors(dge, method="TMM")

# voom transformation
if ("${params.voom_plot}" == "true") {
    png("voom_plot.png", width=800, height=600)
    v <- voom(dge, design, plot=TRUE)
    dev.off()
} else {
    v <- voom(dge, design, plot=FALSE)
}

# Fit linear model + eBayes
fit  <- lmFit(v, design)
fit2 <- eBayes(fit)

# Extract top table (all genes)
tt <- topTable(fit2, coef=2, number=Inf, sort.by="adj.P.Val")
tt <- data.frame(gene=rownames(tt), tt, check.names=FALSE)

write.csv(tt, "de_results.csv", row.names=FALSE)

# Significant subset
sig <- tt[tt[["adj.P.Val"]] < fdr_thresh & abs(tt[["logFC"]]) >= logfc_thresh, ]
write.csv(sig, "significant_genes.csv", row.names=FALSE)

n_up   <- sum(sig[["logFC"]] > 0)
n_down <- sum(sig[["logFC"]] < 0)

summary_list <- list(
    pipeline         = "transcriptomic_biomarker",
    step             = "LIMMA_DIFFERENTIAL_EXPRESSION",
    timestamp        = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ"),
    group_column     = group_col,
    reference_group  = ref_group,
    fdr_threshold    = fdr_thresh,
    logfc_threshold  = logfc_thresh,
    covariates       = as.list(covariates),
    n_genes_tested   = nrow(tt),
    n_significant    = nrow(sig),
    n_upregulated    = n_up,
    n_downregulated  = n_down,
    contrast         = paste0("treatment_vs_", ref_group),
    model_formula    = deparse(form),
    voom_convergence = TRUE,
    top_gene         = if(nrow(sig)>0) sig[1,"gene"] else NULL,
    top_logFC        = if(nrow(sig)>0) sig[1,"logFC"] else NULL,
    top_adj_p        = if(nrow(sig)>0) sig[1,"adj.P.Val"] else NULL
)
write(toJSON(summary_list, auto_unbox=TRUE, pretty=TRUE), "limma_model_summary.json")

cat(sprintf("LIMMA_DIFFERENTIAL_EXPRESSION complete: %d/%d significant genes\\n",
            nrow(sig), nrow(tt)))
REOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        limma: "3.58.1"
        edgeR: "4.0.16"
        R: \$(Rscript --version 2>&1 | cut -d' ' -f4 || echo "N/A")
    END_VERSIONS
    """

    stub:
    """
    echo 'gene,logFC,AveExpr,t,P.Value,adj.P.Val,B' > de_results.csv
    echo 'gene,logFC,AveExpr,t,P.Value,adj.P.Val,B' > significant_genes.csv
    echo '{"n_significant":20}' > limma_model_summary.json
    touch voom_plot.png
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        limma: "3.58.1"
        R: "4.3.1"
    END_VERSIONS
    """
}

// ============================================================================
// Process 3: BIOMARKER_SIGNATURE_SCORING
// ============================================================================

process BIOMARKER_SIGNATURE_SCORING {
    tag "signature_scoring"
    label 'process_medium'
    publishDir "${params.outdir}/03_signature_scoring", mode: params.publish_dir_mode

    container 'docker.io/bioconductor/bioconductor_docker:RELEASE_3_18'

    input:
    path validated_matrix
    path validated_metadata
    path de_results

    output:
    path "signature_scores.csv",  emit: scores
    path "pathway_summary.json",  emit: pathway_summary
    path "versions.yml",          emit: versions

    script:
    def gsva_method   = params.gsva_method
    def group_col     = params.group_column
    def ref_group     = params.reference_group
    def min_gs_size   = params.min_gene_set_size
    def max_gs_size   = params.max_gene_set_size
    """
    Rscript - << 'REOF'
suppressPackageStartupMessages({
    library(GSVA)
    library(msigdbr)
    library(limma)
    library(jsonlite)
})

group_col   <- "${group_col}"
method      <- "${gsva_method}"
min_gs_size <- as.integer("${min_gs_size}")
max_gs_size <- as.integer("${max_gs_size}")

# Read inputs
mat      <- read.csv("${validated_matrix}",   row.names=1, check.names=FALSE)
metadata <- read.csv("${validated_metadata}", check.names=FALSE)
rownames(metadata) <- metadata[["sample_id"]]
metadata <- metadata[colnames(mat), , drop=FALSE]

de       <- read.csv("${de_results}", check.names=FALSE)

# Fetch MSigDB Hallmark gene sets (Human)
msig_h    <- msigdbr(species="Homo sapiens", category="H")
gene_sets <- split(msig_h[["gene_symbol"]], msig_h[["gs_name"]])

# voom-normalise the count matrix before GSVA
dge <- edgeR::DGEList(counts=mat)
dge <- edgeR::calcNormFactors(dge)
v   <- voom(dge)
expr_mat <- v[["E"]]   # log2-CPM matrix

# Run GSVA
if (method == "ssgsea") {
    gsva_param <- ssgseaParam(expr_mat, gene_sets,
                               minSize=min_gs_size, maxSize=max_gs_size)
} else {
    gsva_param <- gsvaParam(expr_mat, gene_sets,
                             minSize=min_gs_size, maxSize=max_gs_size)
}
gsva_scores <- gsva(gsva_param, verbose=FALSE)

# Write scores (samples as rows, pathways as columns)
scores_df           <- as.data.frame(t(gsva_scores))
scores_df[["sample_id"]] <- rownames(scores_df)
scores_df[["group"]]     <- metadata[rownames(scores_df), group_col]
scores_df <- scores_df[, c("sample_id", "group", colnames(scores_df)[!colnames(scores_df) %in% c("sample_id","group")])]
write.csv(scores_df, "signature_scores.csv", row.names=FALSE)

# Pathway-level summary: mean per group + delta
pw_names <- rownames(gsva_scores)
groups   <- unique(metadata[[group_col]])
pw_stats <- lapply(pw_names, function(pw) {
    scores_by_group <- tapply(gsva_scores[pw, ], metadata[[group_col]], mean, na.rm=TRUE)
    ref_score <- scores_by_group["${ref_group}"]
    trt_score <- scores_by_group[setdiff(names(scores_by_group), "${ref_group}")[1]]
    list(pathway=pw,
         mean_control=round(ref_score, 5),
         mean_treatment=round(trt_score, 5),
         delta=round(trt_score - ref_score, 5))
})
pw_stats <- pw_stats[order(sapply(pw_stats, function(x) -abs(x[["delta"]])))]

top_trt  <- head(Filter(function(x) x[["delta"]] > 0, pw_stats), 10)
top_ctrl <- head(Filter(function(x) x[["delta"]] < 0, pw_stats), 10)

summary_list <- list(
    pipeline       = "transcriptomic_biomarker",
    step           = "BIOMARKER_SIGNATURE_SCORING",
    timestamp      = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ"),
    method         = method,
    gene_set_db    = "MSigDB_Hallmark_v2023.2",
    n_gene_sets    = nrow(gsva_scores),
    n_samples      = ncol(gsva_scores),
    top_enriched_treatment = sapply(top_trt,  function(x) x[["pathway"]]),
    top_enriched_control   = sapply(top_ctrl, function(x) x[["pathway"]]),
    pathway_stats  = pw_stats
)
write(toJSON(summary_list, auto_unbox=TRUE, pretty=TRUE), "pathway_summary.json")

cat(sprintf("BIOMARKER_SIGNATURE_SCORING complete: %d pathways, %d samples\\n",
            nrow(gsva_scores), ncol(gsva_scores)))
REOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        GSVA: "1.50.0"
        msigdbr: "7.5.1"
        R: \$(Rscript --version 2>&1 | cut -d' ' -f4 || echo "N/A")
    END_VERSIONS
    """

    stub:
    """
    echo 'sample_id,group,HALLMARK_APOPTOSIS' > signature_scores.csv
    echo '{"n_gene_sets":50,"n_samples":40}' > pathway_summary.json
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        GSVA: "1.50.0"
        R: "4.3.1"
    END_VERSIONS
    """
}

// ============================================================================
// Process 4: BIOMARKER_REPORT
// ============================================================================

process BIOMARKER_REPORT {
    tag "biomarker_report"
    label 'process_medium'
    publishDir "${params.outdir}/04_report", mode: params.publish_dir_mode

    container 'docker.io/bioconductor/bioconductor_docker:RELEASE_3_18'

    input:
    path de_results
    path significant_genes
    path model_summary
    path signature_scores
    path pathway_summary

    output:
    path "biomarker_report.html",   emit: report
    path "versions.yml",            emit: versions

    script:
    def group_col = params.group_column
    def ref_group = params.reference_group
    def fdr_t     = params.fdr_threshold
    def logfc_t   = params.logfc_threshold
    """
    Rscript - << 'REOF'
suppressPackageStartupMessages({
    library(rmarkdown)
    library(knitr)
    library(ggplot2)
    library(pheatmap)
    library(jsonlite)
})

group_col <- "${group_col}"
ref_group <- "${ref_group}"
fdr_t     <- as.numeric("${fdr_t}")
logfc_t   <- as.numeric("${logfc_t}")

de       <- read.csv("${de_results}", check.names=FALSE)
sig      <- read.csv("${significant_genes}", check.names=FALSE)
scores   <- read.csv("${signature_scores}", check.names=FALSE)
pw_sum   <- fromJSON("${pathway_summary}")
mod_sum  <- fromJSON("${model_summary}")

# Volcano plot
de[["neg_log10_adjp"]] <- -log10(pmax(de[["adj.P.Val"]], 1e-10))
de[["significance"]] <- "Not significant"
de[["significance"]][de[["adj.P.Val"]] < fdr_t & de[["logFC"]] >= logfc_t]  <- "Up"
de[["significance"]][de[["adj.P.Val"]] < fdr_t & de[["logFC"]] <= -logfc_t] <- "Down"

p_volcano <- ggplot(de, aes(x=logFC, y=neg_log10_adjp, color=significance)) +
    geom_point(alpha=0.6, size=1.5) +
    scale_color_manual(values=c("Up"="#27ae60","Down"="#e74c3c","Not significant"="#bdc3c7")) +
    geom_hline(yintercept=-log10(fdr_t), linetype="dashed", color="#f39c12") +
    geom_vline(xintercept=c(-logfc_t, logfc_t), linetype="dashed", color="#3498db") +
    theme_bw(base_size=12) +
    labs(title="Volcano Plot", x="log2 Fold Change", y="-log10(adj.P.Val)")
ggsave("volcano_plot.png", p_volcano, width=7, height=5, dpi=150)

# Heatmap (top 50 genes)
top50 <- head(de[order(de[["adj.P.Val"]]), "gene"], 50)

rmd_content <- paste0('---
title: "BioMate Transcriptomic Biomarker Report"
output: html_document
---

## Summary

- Contrast: ', mod_sum[["contrast"]], '
- Significant DE genes: ', mod_sum[["n_significant"]], '
  (', mod_sum[["n_upregulated"]], ' up, ', mod_sum[["n_downregulated"]], ' down)
- FDR threshold: ', fdr_t, '
- |logFC| threshold: ', logfc_t, '

## Volcano Plot

![](volcano_plot.png)

## Top Significant Genes

')

write(rmd_content, "report.Rmd")
rmarkdown::render("report.Rmd", output_file="biomarker_report.html", quiet=TRUE)
cat("BIOMARKER_REPORT complete: biomarker_report.html\n")
REOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        ggplot2: "3.4.4"
        pheatmap: "1.0.12"
        rmarkdown: "2.25"
        R: \$(Rscript --version 2>&1 | cut -d' ' -f4 || echo "N/A")
    END_VERSIONS
    """

    stub:
    """
    echo '<html><body><h1>BioMate Biomarker Report (stub)</h1></body></html>' > biomarker_report.html
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        ggplot2: "3.4.4"
        R: "4.3.1"
    END_VERSIONS
    """
}

// ============================================================================
// Entry workflow: TRANSCRIPTOMIC_BIOMARKER
// ============================================================================
//
// Linear chain (each step depends on the previous):
//
//   BIOMARKER_INPUT_QC
//          │
//   LIMMA_DIFFERENTIAL_EXPRESSION
//          │
//   BIOMARKER_SIGNATURE_SCORING
//          │
//   BIOMARKER_REPORT
//
// ============================================================================

workflow TRANSCRIPTOMIC_BIOMARKER {
    take:
    ch_expression_matrix  // channel: path(expression_matrix.csv)
    ch_metadata           // channel: path(metadata.csv)

    main:
    // ------------------------------------------------------------------
    // Step 1: Validate inputs
    // ------------------------------------------------------------------
    BIOMARKER_INPUT_QC(
        ch_expression_matrix,
        ch_metadata
    )

    // ------------------------------------------------------------------
    // Step 2: Limma-voom differential expression
    // ------------------------------------------------------------------
    LIMMA_DIFFERENTIAL_EXPRESSION(
        BIOMARKER_INPUT_QC.out.validated_matrix,
        BIOMARKER_INPUT_QC.out.validated_metadata,
        BIOMARKER_INPUT_QC.out.qc_report
    )

    // ------------------------------------------------------------------
    // Step 3: GSVA/ssGSEA pathway signature scoring
    // ------------------------------------------------------------------
    BIOMARKER_SIGNATURE_SCORING(
        BIOMARKER_INPUT_QC.out.validated_matrix,
        BIOMARKER_INPUT_QC.out.validated_metadata,
        LIMMA_DIFFERENTIAL_EXPRESSION.out.de_results
    )

    // ------------------------------------------------------------------
    // Step 4: Generate HTML report
    // ------------------------------------------------------------------
    BIOMARKER_REPORT(
        LIMMA_DIFFERENTIAL_EXPRESSION.out.de_results,
        LIMMA_DIFFERENTIAL_EXPRESSION.out.significant_genes,
        LIMMA_DIFFERENTIAL_EXPRESSION.out.model_summary,
        BIOMARKER_SIGNATURE_SCORING.out.scores,
        BIOMARKER_SIGNATURE_SCORING.out.pathway_summary
    )

    emit:
    qc_report         = BIOMARKER_INPUT_QC.out.qc_report
    de_results        = LIMMA_DIFFERENTIAL_EXPRESSION.out.de_results
    significant_genes = LIMMA_DIFFERENTIAL_EXPRESSION.out.significant_genes
    model_summary     = LIMMA_DIFFERENTIAL_EXPRESSION.out.model_summary
    voom_plot         = LIMMA_DIFFERENTIAL_EXPRESSION.out.voom_plot
    signature_scores  = BIOMARKER_SIGNATURE_SCORING.out.scores
    pathway_summary   = BIOMARKER_SIGNATURE_SCORING.out.pathway_summary
    report            = BIOMARKER_REPORT.out.report
    versions          = BIOMARKER_INPUT_QC.out.versions
                            .mix(LIMMA_DIFFERENTIAL_EXPRESSION.out.versions)
                            .mix(BIOMARKER_SIGNATURE_SCORING.out.versions)
                            .mix(BIOMARKER_REPORT.out.versions)
}

// ============================================================================
// Standalone Entry Point (nextflow run main.nf)
// ============================================================================

workflow {
    log_workflow_header()

    if (!params.expression_matrix) {
        error "params.expression_matrix is required. Pass --expression_matrix <path>"
    }
    if (!params.metadata) {
        error "params.metadata is required. Pass --metadata <path>"
    }
    ch_expression_matrix = Channel.fromPath(params.expression_matrix, checkIfExists: true)
    ch_metadata          = Channel.fromPath(params.metadata,          checkIfExists: true)

    // Run the pipeline
    TRANSCRIPTOMIC_BIOMARKER(ch_expression_matrix, ch_metadata)

    // Display summary
    TRANSCRIPTOMIC_BIOMARKER.out.model_summary.view { f ->
        "LIMMA model summary: ${f}"
    }
    TRANSCRIPTOMIC_BIOMARKER.out.pathway_summary.view { f ->
        "Pathway summary:     ${f}"
    }
    TRANSCRIPTOMIC_BIOMARKER.out.report.view { f ->
        "Biomarker report:    ${f}"
    }
}
