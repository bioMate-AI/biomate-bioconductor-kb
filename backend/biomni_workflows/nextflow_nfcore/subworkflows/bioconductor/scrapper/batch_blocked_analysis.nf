#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scrapper — batch_blocked_analysis
// Combine multiple single-cell datasets and perform batch-corrected analysis using MNN correction and block-aware calculations.
// Input: sce.t, sce.z
// Container: quay.io/biocontainers/bioconductor-scrapper:1.4.0--r45ha27e39d_0
// R packages: SingleCellExperiment, scater, scrapper, scuttle
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, scater, scrapper, scuttle
// Visualizations: ordination plot, t-SNE plot
// QC: cell QC metrics
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Find common genes and combine columns
//  * 2. [Input & Preparation] Define batch blocking vector
//  * 3. [Core Analysis] Run batch-aware end-to-end analysis with analyze.se()
//  * 4. [Visualization & Output] Visualize batch correction
//  * 5. [Core Analysis] Aggregate cells across clusters and batches with aggregateAcrossCells.se()

nextflow.enable.dsl = 2

process BIOC_SCRAPPER_BATCH_BLOCKED_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("SingleCellExperiment", "scater", "scrapper", "scuttle")
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
    library(scuttle)
    
    # Read user input files from the working directory
    file_t <- if (file.exists("sce.t")) "sce.t" else "sce.t.rds"
    file_z <- if (file.exists("sce.z")) "sce.z" else "sce.z.rds"
    
    if (!file.exists(file_t) || !file.exists(file_z)) {
        stop("Required input files (sce.t and sce.z) not found in the working directory.")
    }
    
    sce.t <- readRDS(file_t)
    sce.z <- readRDS(file_z)
    
    # Only using the common genes in both datasets.
    common <- intersect(rownames(sce.z), rownames(sce.t))
    combined <- combineCols(sce.t[common,], sce.z[common,])
    block <- rep(c("tasic", "zeisel"), c(ncol(sce.t), ncol(sce.z)))
    
    # No mitochondrial genes in the combined set, so we'll just skip it.
    blocked_res <- analyze.se(combined, block=block, num.threads=2)
    
    # Save the full analysis results object
    saveRDS(blocked_res, "blocked_res.rds")
    
    # Visualize batch correction and save to PDF
    pdf("blocked_tsne_plot.pdf")
    p <- plotReducedDim(blocked_res\$x, "TSNE", colour_by="block")
    print(p)
    dev.off()
    
    # Table of clusters across batches
    tab <- table(blocked_res\$x\$graph.cluster, blocked_res\$x\$block)
    write.csv(as.data.frame.matrix(tab), "cluster_block_table.csv")
    
    # Preview markers and save to CSV
    markers_preview <- previewMarkers(blocked_res\$markers\$rna[[1]])
    write.csv(as.data.frame(markers_preview), "preview_markers.csv")
    
    # Aggregate cells across clusters and batches
    aggregates <- aggregateAcrossCells.se(
        blocked_res\$x,
        list(cluster=blocked_res\$x\$graph.cluster, dataset=blocked_res\$x\$block)
    )
    
    # Save aggregated profiles
    saveRDS(aggregates, "aggregated_profiles.rds")

    writeLines(c(
        '"BIOC_SCRAPPER_BATCH_BLOCKED_ANALYSIS":',
        paste0('    scrapper: ', as.character(packageVersion('scrapper')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_batch_blocked_analysis.csv versions.yml
    """
}

workflow BIOC_SCRAPPER_BATCH_BLOCKED_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce.t, sce.z ] ]

    main:
    BIOC_SCRAPPER_BATCH_BLOCKED_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SCRAPPER_BATCH_BLOCKED_ANALYSIS.out.tables
    plots    = BIOC_SCRAPPER_BATCH_BLOCKED_ANALYSIS.out.plots
    objects  = BIOC_SCRAPPER_BATCH_BLOCKED_ANALYSIS.out.objects
    versions = BIOC_SCRAPPER_BATCH_BLOCKED_ANALYSIS.out.versions
}
