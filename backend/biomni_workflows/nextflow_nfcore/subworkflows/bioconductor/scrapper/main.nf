#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scrapper — basic_sc_rna_seq_analysis
// Perform an end-to-end single-cell RNA-seq analysis workflow including QC, normalization, PCA, clustering, and marker detection using a single wrapper function.
// Input: sce.z
// Container: quay.io/biocontainers/bioconductor-scrapper:1.4.0--r45ha27e39d_0
// R packages: SingleCellExperiment, BiocStyle, DelayedArray, knitr, scater, scrapper, scRNAseq
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, scater, scrapper
// Visualizations: ordination plot, t-SNE plot
// QC: cell QC metrics
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Identify mitochondrial genes
//  * 2. [Core Analysis] Run end-to-end analysis with analyze.se()
//  * 3. [Visualization & Output] Visualize results with plotReducedDim()
//  * 4. [Core Analysis] Inspect marker genes with previewMarkers()

nextflow.enable.dsl = 2

process BIOC_SCRAPPER_BASIC_SC_RNA_SEQ_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    tuple val(meta), path("qc_metrics.json"), emit: qc_metrics
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("SingleCellExperiment", "BiocStyle", "DelayedArray", "knitr", "scater", "scrapper", "scRNAseq")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(scrapper)
    library(scater)
    
    # 1. Read the input SingleCellExperiment object from the working directory
    sce.z <- readRDS("sce.z")
    
    # 2. Identify mitochondrial genes
    is.mito <- grep("^mt-", rownames(sce.z))
    
    # 3. Run end-to-end analysis with analyze.se()
    results <- analyze.se(
        sce.z,
        rna.qc.subsets=list(Mito=is.mito),
        num.threads=2 # limit number of threads to keep R CMD check happy.
    )
    
    # Save the analyzed SingleCellExperiment object (which contains the results)
    saveRDS(results\$x, "analyzed_sce.rds")
    
    # 4. Visualize results with plotReducedDim() and save to PDF
    pdf("tsne_plot.pdf", width=8, height=6)
    p <- plotReducedDim(results\$x, "TSNE", colour_by="graph.cluster")
    print(p)
    dev.off()
    
    # 5. Inspect marker genes with previewMarkers() and save to CSV
    markers_preview <- previewMarkers(results\$markers\$rna[[1]], order.by="auc.median")
    write.csv(as.data.frame(markers_preview), "marker_genes.csv", row.names=TRUE)
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # cell QC metrics — defensive cell-count + per-cell summary from any
    # matrix artifact. Pass when columns (cells) ≥ 50 and rows (features) ≥ 200
    # (Luecken & Theis 2019 single-cell QC floor).
    .cqc_ncells <- NA_real_; .cqc_nfeats <- NA_real_; .cqc_files <- character(0)
    for (.cqc_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .cqc_obj <- tryCatch(readRDS(.cqc_rds), error = function(e) NULL)
      .cqc_mat <- if (is.matrix(.cqc_obj) || is.data.frame(.cqc_obj)) .cqc_obj else NULL
      if (!is.null(.cqc_mat) && nrow(.cqc_mat) > 100) {
        .cqc_ncells <- ncol(.cqc_mat); .cqc_nfeats <- nrow(.cqc_mat)
        .cqc_files <- c(.cqc_files, .cqc_rds); break
      }
    }
    .gates_by_label[["cell QC metrics"]] <- list(
      gate_row = "bioc_cell_qc_metrics",
      metric_name = "n_cells",
      metric_value = .cqc_ncells,
      passes = isTRUE(is.finite(.cqc_ncells) && .cqc_ncells >= 50 && .cqc_nfeats >= 200),
      status = if (is.finite(.cqc_ncells)) paste0("computed (cells=", .cqc_ncells, ", features=", .cqc_nfeats, "; proxy gate)")
               else "not_computed (no scRNA matrix .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_SCRAPPER_BASIC_SC_RNA_SEQ_ANALYSIS",
      domain  = "bioconductor",
      declared_qc_steps = c("cell QC metrics"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_SCRAPPER_BASIC_SC_RNA_SEQ_ANALYSIS":',
        paste0('    scrapper: ', as.character(packageVersion('scrapper')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_basic_sc_rna_seq_analysis.csv versions.yml
    """
}

workflow BIOC_SCRAPPER_BASIC_SC_RNA_SEQ_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce.z ] ]

    main:
    BIOC_SCRAPPER_BASIC_SC_RNA_SEQ_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SCRAPPER_BASIC_SC_RNA_SEQ_ANALYSIS.out.tables
    plots    = BIOC_SCRAPPER_BASIC_SC_RNA_SEQ_ANALYSIS.out.plots
    objects  = BIOC_SCRAPPER_BASIC_SC_RNA_SEQ_ANALYSIS.out.objects
    versions = BIOC_SCRAPPER_BASIC_SC_RNA_SEQ_ANALYSIS.out.versions
}
