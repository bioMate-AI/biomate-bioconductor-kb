#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: corral — multi_batch_integration
// Align and integrate single-cell datasets from different batches or platforms using corralm.
// Input: scmix_sce, scmix_matlist
// Container: quay.io/biocontainers/bioconductor-corral:1.20.0--r45h575d39b_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, corral, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run corralm on the SingleCellExperiment specifying the batch covariate in splitby
//  * 2. [Visualization & Output] Visualize the integrated embedding using plot_embedding_sce
//  * 3. [Core Analysis] Convert to a list of matrices using sce2matlist and run corralm on the list
//  * 4. [Core Analysis] Evaluate batch integration using the scaled variance metric with scal_var

nextflow.enable.dsl = 2

process BIOC_CORRAL_MULTI_BATCH_INTEGRATION {
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
    .bm_deps <- c("corral", "ggplot2", "SummarizedExperiment")
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
    library(corral)
    library(SummarizedExperiment)
    library(ggplot2)
    
    # 1. Read user input files from the working directory
    scmix_sce <- readRDS("scmix_sce.rds")
    
    # Extract generic covariates for batch and cell type to avoid hardcoding
    batch_attr <- colnames(colData(scmix_sce))[1]
    cell_attr <- if (ncol(colData(scmix_sce)) > 1) colnames(colData(scmix_sce))[2] else batch_attr
    
    # 2. Run corralm on the SingleCellExperiment specifying the batch covariate in splitby
    scmix_sce <- corralm(scmix_sce, splitby = batch_attr)
    
    # 3. Visualize the integrated embedding using plot_embedding_sce and save to PDF
    pdf("plot_corralm_sce.pdf", width = 8, height = 6)
    p1 <- plot_embedding_sce(sce = scmix_sce, 
                             which_embedding = 'corralm', 
                             color_attr = batch_attr, 
                             color_title = 'platform', 
                             ellipse_attr = cell_attr, 
                             plot_title = 'corralm on scmix', 
                             saveplot = FALSE)
    if (inherits(p1, "ggplot")) {
      print(p1)
    }
    dev.off()
    
    # Convert the SingleCellExperiment to a list of matrices
    scmix_matlist <- sce2matlist(sce = scmix_sce, splitby = batch_attr, whichmat = 'counts')
    
    # 4. Run corralm on the list of matrices
    scmix_corralm <- corralm(scmix_matlist)
    
    # Extract covariates for plotting
    platforms <- colData(scmix_sce)[[batch_attr]]
    cell_lines <- colData(scmix_sce)[[cell_attr]]
    
    # Visualize the list-based integrated embedding using plot_embedding and save to PDF
    pdf("plot_corralm_matlist.pdf", width = 8, height = 6)
    p2 <- plot_embedding(embedding = scmix_corralm\$v, 
                         plot_title = 'corralm on scmix', 
                         color_vec = platforms, 
                         color_title = 'platform', 
                         ellipse_vec = cell_lines, 
                         saveplot = FALSE)
    if (inherits(p2, "ggplot")) {
      print(p2)
    }
    dev.off()
    
    # 5. Evaluate batch integration using the scaled variance metric with scal_var
    sv_metrics <- scal_var(scmix_corralm)
    
    # 6. Save outputs to the working directory
    saveRDS(scmix_sce, "scmix_sce_integrated.rds")
    saveRDS(scmix_corralm, "scmix_corralm.rds")
    write.csv(as.data.frame(sv_metrics), "scaled_variance.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_CORRAL_MULTI_BATCH_INTEGRATION":',
        paste0('    corral: ', as.character(packageVersion('corral')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_batch_integration.csv versions.yml
    """
}

workflow BIOC_CORRAL_MULTI_BATCH_INTEGRATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ scmix_sce, scmix_matlist ] ]

    main:
    BIOC_CORRAL_MULTI_BATCH_INTEGRATION(ch_input)

    emit:
    tables   = BIOC_CORRAL_MULTI_BATCH_INTEGRATION.out.tables
    plots    = BIOC_CORRAL_MULTI_BATCH_INTEGRATION.out.plots
    objects  = BIOC_CORRAL_MULTI_BATCH_INTEGRATION.out.objects
    versions = BIOC_CORRAL_MULTI_BATCH_INTEGRATION.out.versions
}
