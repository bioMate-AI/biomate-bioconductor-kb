#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: pmp — signal_drift_and_batch_correction
// Correct signal drift and batch effects across multi-batch mass spectrometry datasets using Quality Control-Robust Spline Correction (QC-RSC).
// Input: MTBLS79
// Container: quay.io/biocontainers/bioconductor-pmp:1.22.1--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, ggplot2, pmp
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter out peaks not reproducibly measured across QC samples using filter_peaks_by_fraction
//  * 2. [Core Analysis] Apply signal drift and batch effect correction using QCRSC
//  * 3. [Core Analysis] Visually compare results before and after correction using sbc_plot

nextflow.enable.dsl = 2

process BIOC_PMP_SIGNAL_DRIFT_AND_BATCH_CORRECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

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
    .bm_deps <- c("pmp", "ggplot2", "SummarizedExperiment")
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
        
        # Load required librari        library(SummarizedExperiment)
es
        library(pmp)
        library(ggplot2)
        
        # Read the input SummarizedExperiment object from the working directory
        if (file.exists("MTBLS79")) {
          MTBLS79 <- readRDS("MTBLS79")
        } else if (file.exists("MTBLS79.rds")) {
          MTBLS79 <- readRDS("MTBLS79.rds")
        } else {
          stop("Required input file 'MTBLS79' or 'MTBLS79.rds' not found in the working directory.")
        }
        
        # Execute the documented workflow steps exactly as specified
        class <- MTBLS79\$Class
        batch <- MTBLS79\$Batch
        sample_order <- c(1:ncol(MTBLS79))
        
        # 1. Filter out peaks not reproducibly measured across QC samples
        data <- filter_peaks_by_fraction(df=MTBLS79, classes=class, method="QC", qc_label="QC", min_frac=0.8)
        
        # 2. Apply signal drift and batch effect correction using QCRSC
        corrected_data <- QCRSC(df=data, order=sample_order, batch=batch, classes=class, spar=0, minQC=4)
        
        # 3. Visually compare results before and after correction
        plots <- sbc_plot (df=data, corrected_df=corrected_data, classes=class, batch=batch, output=NULL, indexes=c(1, 5, 30))
        
        # Save the corrected SummarizedExperiment object
        saveRDS(corrected_data, file = "corrected_data.rds")
        
        # Save the corrected peak matrix as a CSV file
        corrected_matrix <- SummarizedExperiment::assay(corrected_data)
        write.csv(corrected_matrix, file = "corrected_peaks.csv", row.names = TRUE)
        
        # Save the comparison plots to a PDF file
        pdf("sbc_plots.pdf", width = 10, height = 8)
        for (i in seq_along(plots)) {
          grid::grid.newpage()
          grid::grid.draw(plots[[i]])
        }
        dev.off()

    writeLines(c(
        '"BIOC_PMP_SIGNAL_DRIFT_AND_BATCH_CORRECTION":',
        paste0('    pmp: ', as.character(packageVersion('pmp')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_signal_drift_and_batch_correction.csv versions.yml
    """
}

workflow BIOC_PMP_SIGNAL_DRIFT_AND_BATCH_CORRECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ MTBLS79 ] ]

    main:
    BIOC_PMP_SIGNAL_DRIFT_AND_BATCH_CORRECTION(ch_input)

    emit:
    tables   = BIOC_PMP_SIGNAL_DRIFT_AND_BATCH_CORRECTION.out.tables
    plots    = BIOC_PMP_SIGNAL_DRIFT_AND_BATCH_CORRECTION.out.plots
    objects  = BIOC_PMP_SIGNAL_DRIFT_AND_BATCH_CORRECTION.out.objects
    versions = BIOC_PMP_SIGNAL_DRIFT_AND_BATCH_CORRECTION.out.versions
}
