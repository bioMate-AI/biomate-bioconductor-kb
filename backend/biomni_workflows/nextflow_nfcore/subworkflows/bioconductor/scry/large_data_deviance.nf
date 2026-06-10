#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scry — large_data_deviance
// Calculate deviance feature selection and null residuals on large, disk-backed (HDF5/DelayedArray) or sparse in-memory matrices.
// Input: h5counts, sce
// Container: quay.io/biocontainers/bioconductor-scry:1.22.0--r45hdfd78af_0
// R packages: DelayedArray, HDF5Array, SingleCellExperiment, scry
// Bioconductor: 3.20 | R: 4.4
// Requires: DelayedArray, HDF5Array, SingleCellExperiment, scry
// Visualizations: plot (ggplot/base)
// QC: low-count filtering
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter out unexpressed genes from the HDF5/DelayedArray counts
//  * 2. [Core Analysis] Run devianceFeatureSelection directly on the HDF5/DelayedArray counts
//  * 3. [Core Analysis] Run nullResiduals on the HDF5-backed SingleCellExperiment

nextflow.enable.dsl = 2

process BIOC_SCRY_LARGE_DATA_DEVIANCE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("DelayedArray", "HDF5Array", "SingleCellExperiment", "scry")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
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
        library(scry)
        library(DelayedArray)
        library(HDF5Array)
        
        # Read user input files from the working directory
        h5counts_file <- if (file.exists("h5counts.rds")) "h5counts.rds" else "h5counts"
        sce_file <- if (file.exists("sce.rds")) "sce.rds" else "sce"
        
        if (!file.exists(h5counts_file) || !file.exists(sce_file)) {
          stop("Required input files (h5counts/h5counts.rds and sce/sce.rds) not found in the working directory.")
        }
        
        h5counts <- readRDS(h5counts_file)
        sce <- readRDS(sce_file)
        
        # 1. Filter out unexpressed genes from the HDF5/DelayedArray counts
        h5counts<-h5counts[rowSums(h5counts)>0,]
        
        # 2. Run devianceFeatureSelection directly on the HDF5/DelayedArray counts
        system.time(h5devs<-devianceFeatureSelection(h5counts))
        
        # 3. Run nullResiduals on the HDF5-backed SingleCellExperiment
        sce <- nullResiduals(sce, assay="counts", type="deviance")
        
        # Write meaningful output files
        # Save deviance statistics
        saveRDS(h5devs, "h5devs.rds")
        
        # Export deviance statistics as a CSV table
        h5devs_df <- data.frame(
          gene = if (is.null(names(h5devs))) seq_along(h5devs) else names(h5devs),
          binomial_deviance = as.numeric(h5devs)
        )
        write.csv(h5devs_df, "deviance_feature_selection.csv", row.names = FALSE)
        
        # Save the updated SingleCellExperiment object containing null residuals
        saveRDS(sce, "sce_null_residuals.rds")
        
        # Generate and save a diagnostic plot of the sorted deviances
        pdf("deviance_plot.pdf", width = 6, height = 4)
        plot(sort(h5devs, decreasing = TRUE), type = "l", 
             xlab = "ranked genes", ylab = "binomial deviance", 
             main = "Feature Selection with Deviance (HDF5)")
        dev.off()

    writeLines(c(
        '"BIOC_SCRY_LARGE_DATA_DEVIANCE":',
        paste0('    scry: ', as.character(packageVersion('scry')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_large_data_deviance.csv versions.yml
    """
}

workflow BIOC_SCRY_LARGE_DATA_DEVIANCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ h5counts, sce ] ]

    main:
    BIOC_SCRY_LARGE_DATA_DEVIANCE(ch_input)

    emit:
    tables   = BIOC_SCRY_LARGE_DATA_DEVIANCE.out.tables
    plots    = BIOC_SCRY_LARGE_DATA_DEVIANCE.out.plots
    objects  = BIOC_SCRY_LARGE_DATA_DEVIANCE.out.objects
    versions = BIOC_SCRY_LARGE_DATA_DEVIANCE.out.versions
}
