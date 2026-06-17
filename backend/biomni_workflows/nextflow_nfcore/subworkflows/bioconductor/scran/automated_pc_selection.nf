#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scran — automated_pc_selection
// Determine the optimal number of principal components (PCs) to retain based on technical variance estimates.
// Input: sce.ready
// Container: quay.io/biocontainers/bioconductor-scran:1.38.0--r45ha27e39d_0
// R packages: SingleCellExperiment, scran
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, scran
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Extract variance explained and technical/total variance statistics
//  * 2. [Core Analysis] Determine the number of PCs to retain using denoisePCANumber()
//  * 3. [Core Analysis] Subset the PCA coordinates to the chosen number of PCs

nextflow.enable.dsl = 2

process BIOC_SCRAN_AUTOMATED_PC_SELECTION {
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
    .bm_deps <- c("SingleCellExperiment", "scran", "SummarizedExperiment")
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
    library(SummarizedExperiment)
    library(scran)
    
    # Read the input SingleCellExperiment object from the working directory
    sce.ready <- readRDS("sce.ready")
    
    # Extract variance explained and technical/total variance statistics
    var.explained <- metadata(sce.ready)\$PCA\$variance.explained
    stats <- rowData(sce.ready)
    total.tech.var.in.hvgs <- sum(stats[stats\$hvg,"fitted"])
    total.var.in.hvgs <- sum(stats[stats\$hvg,"variances"])
    
    # Determine the optimal number of PCs to retain using denoisePCANumber()
    chosen <- denoisePCANumber(var.explained, total.tech.var.in.hvgs, total.var.in.hvgs)
    
    # Subset the PCA coordinates to the chosen number of PCs
    reducedDim(sce.ready, "PCA.denoised") <- reducedDim(sce.ready, "PCA")[,1:chosen]
    
    # Save the modified SingleCellExperiment object
    saveRDS(sce.ready, "sce_denoised.rds")
    
    # Save the chosen number of PCs to a CSV file
    write.csv(data.frame(chosen_pcs = chosen), "chosen_pc.csv", row.names = FALSE)
    
    # Generate a diagnostic plot showing the variance explained and the selection threshold
    pdf("variance_explained_pcs.pdf")
    plot(var.explained, type = "b", pch = 16, col = "blue",
         xlab = "Principal Component", ylab = "Variance Explained",
         main = paste("Denoised PC Selection (Chosen PCs:", chosen, ")"))
    abline(v = chosen, col = "red", lty = 2, lwd = 2)
    legend("topright", legend = c("Variance Explained", paste("Cutoff (PC ", chosen, ")", sep="")),
           col = c("blue", "red"), lty = c(1, 2), pch = c(16, NA))
    dev.off()

    writeLines(c(
        '"BIOC_SCRAN_AUTOMATED_PC_SELECTION":',
        paste0('    scran: ', as.character(packageVersion('scran')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_automated_pc_selection.csv versions.yml
    """
}

workflow BIOC_SCRAN_AUTOMATED_PC_SELECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce.ready ] ]

    main:
    BIOC_SCRAN_AUTOMATED_PC_SELECTION(ch_input)

    emit:
    tables   = BIOC_SCRAN_AUTOMATED_PC_SELECTION.out.tables
    plots    = BIOC_SCRAN_AUTOMATED_PC_SELECTION.out.plots
    objects  = BIOC_SCRAN_AUTOMATED_PC_SELECTION.out.objects
    versions = BIOC_SCRAN_AUTOMATED_PC_SELECTION.out.versions
}
