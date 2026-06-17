#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: chipexoqual — subsampling_qc_pipeline
// Assess quality of deeply sequenced ChIP-exo/nexus experiments by subsampling reads to controlled depths.
// Input: file.bam
// Container: quay.io/biocontainers/bioconductor-chipexoqual:1.34.0--r45hdfd78af_0
// R packages: BiocParallel, BiocStyle, ChIPexoQual, chipexoqualexample, ggplot2, gridExtra, knitr
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CHIPEXOQUAL_SUBSAMPLING_QC_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-chipexoqual:1.34.0--r45hdfd78af_0"

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
    .bm_deps <- c("BiocParallel", "BiocStyle", "ChIPexoQual", "chipexoqualexample", "ggplot2", "gridExtra", "knitr")
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
    library(ChIPexoQual)
    library(gridExtra)
    library(ggplot2)
    
    # Define input file
    input_bam <- "file.bam"
    
    # Check if input file exists
    if (!file.exists(input_bam)) {
      stop(paste("Required input file '", input_bam, "' not found in the working directory.", sep = ""))
    }
    
    # --- Subsample reads at specified depths using ---
    message("Running ExoDataSubsampling on ", input_bam, "...")
    sample.depth = seq(1e5,2e5,5e4)
    exoList = ExoDataSubsampling(file = input_bam, sample.depth = sample.depth, verbose=FALSE)
    
    # Save the subsampled ExoData list object
    saveRDS(exoList, "exoList_subsampled.rds")
    message("Saved subsampled ExoData list to 'exoList_subsampled.rds'")
    
    # --- Plot parameter distributions across subsampled depths ---
    message("Generating parameter distribution plots...")
    p1 = paramDistBoxplot(exoList,which.param = "beta1")
    p2 = paramDistBoxplot(exoList,which.param = "beta2")
    
    # Save plots to PDF
    pdf("subsampling_qc_plots.pdf", width = 10, height = 5)
    gridExtra::grid.arrange(p1,p2,nrow = 1)
    dev.off()
    message("Saved QC plots to 'subsampling_qc_plots.pdf'")
    
    # Extract and save summary statistics
    message("Extracting summary statistics...")
    tryCatch({
      beta1_medians = sapply(exoList, function(x) median(beta1(x)))
      beta2_medians = sapply(exoList, function(x) median(-beta2(x)))
      summary_df = data.frame(
        Subsample_Depth = names(exoList),
        Median_Beta1 = beta1_medians,
        Median_Beta2 = beta2_medians
      )
      write.csv(summary_df, "subsampling_qc_summary.csv", row.names = FALSE)
      message("Saved summary statistics to 'subsampling_qc_summary.csv'")
    }, error = function(e) {
      warning("Could not extract summary statistics: ", e\$message)
    })
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_CHIPEXOQUAL_SUBSAMPLING_QC_PIPELINE":',
        paste0('        chipexoqual: ', as.character(packageVersion("chipexoqual")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_subsampling_qc_pipeline.csv versions.yml
    """
}

workflow BIOC_CHIPEXOQUAL_SUBSAMPLING_QC_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ file.bam ] ]

    main:
    BIOC_CHIPEXOQUAL_SUBSAMPLING_QC_PIPELINE(ch_input)

    emit:
    tables   = BIOC_CHIPEXOQUAL_SUBSAMPLING_QC_PIPELINE.out.tables
    plots    = BIOC_CHIPEXOQUAL_SUBSAMPLING_QC_PIPELINE.out.plots
    objects  = BIOC_CHIPEXOQUAL_SUBSAMPLING_QC_PIPELINE.out.objects
    versions = BIOC_CHIPEXOQUAL_SUBSAMPLING_QC_PIPELINE.out.versions
}
