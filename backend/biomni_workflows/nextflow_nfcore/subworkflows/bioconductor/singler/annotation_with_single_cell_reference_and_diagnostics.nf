#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SingleR — annotation_with_single_cell_reference_and_diagnostics
// Annotate single-cell RNA-seq test data using a custom single-cell reference dataset, employing Wilcoxon-based marker detection and diagnostic visualizations.
// Input: test_dataset.rds, reference_dataset.rds
// Container: quay.io/biocontainers/bioconductor-singler:2.12.0--r45ha27e39d_0
// R packages: SingleCellExperiment, SingleR, scrapper
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, SingleR, scrapper
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load and preprocess the single-cell reference dataset (remove unlabelled cells, normalize, and log-transform)
//  * 2. [Input & Preparation] Load and preprocess the test dataset (remove zero-count libraries, normalize, and log-transform)
//  * 3. [Core Analysis] Run SingleR with Wilcoxon marker detection
//  * 4. [Visualization & Output] Plot score heatmap to inspect assignment confidence
//  * 5. [Visualization & Output] Plot delta distribution to evaluate label ambiguity
//  * 6. [Core Analysis] Check pruned scores to identify low-quality assignments
//  * 7. [Visualization & Output] Plot marker expression heatmap for specific assigned labels

nextflow.enable.dsl = 2

process BIOC_SINGLER_ANNOTATION_WITH_SINGLE_CELL_REFERENCE_AND_DIAGNOSTICS {
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
    .bm_deps <- c("SingleCellExperiment", "SingleR", "scrapper")
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
    library(SingleR)
    library(scrapper)
    library(grDevices)
    library(utils)
    
    # 1. Load and preprocess the single-cell reference dataset
    # Read the user-provided reference dataset
    sceM <- readRDS("reference_dataset.rds")
    
    # Remove unlabelled cells
    sceM <- sceM[, !is.na(sceM\$label)]
    
    # Normalize and log-transform the reference dataset
    sceM <- scrapper::normalizeRnaCounts.se(sceM)
    
    # 2. Load and preprocess the test dataset
    # Read the user-provided test dataset
    sceG <- readRDS("test_dataset.rds")
    
    # Remove libraries with no counts
    sceG <- sceG[, colSums(counts(sceG)) > 0]
    
    # Normalize and log-transform the test dataset
    sceG <- scrapper::normalizeRnaCounts.se(sceG)
    
    # 3. Run SingleR with Wilcoxon marker detection
    pred.grun <- SingleR(test=sceG, ref=sceM, labels=sceM\$label, de.method="wilcox")
    
    # Save the raw SingleR predictions object
    saveRDS(pred.grun, "singler_predictions.rds")
    
    # Summarize and save the distribution of predicted labels
    label_table <- table(pred.grun\$labels)
    write.csv(as.data.frame(label_table), "predicted_labels_frequency.csv", row.names = FALSE)
    
    # 4. Plot score heatmap to inspect assignment confidence
    pdf("score_heatmap.pdf", width = 10, height = 8)
    plotScoreHeatmap(pred.grun)
    dev.off()
    
    # 5. Plot delta distribution to evaluate label ambiguity
    pdf("delta_distribution.pdf", width = 10, height = 8)
    plotDeltaDistribution(pred.grun, ncol = 3)
    dev.off()
    
    # 6. Check pruned scores to identify low-quality assignments
    pruned_summary <- summary(is.na(pred.grun\$pruned.labels))
    write.csv(as.data.frame(as.table(pruned_summary)), "pruned_labels_summary.csv", row.names = FALSE)
    
    # 7. Plot marker expression heatmap for specific assigned labels
    pdf("marker_heatmap.pdf", width = 10, height = 8)
    tryCatch({
      plotMarkerHeatmap(pred.grun, sceG, label="beta")
    }, error = function(e) {
      message("Could not plot marker heatmap for 'beta': ", e\$message)
      # Fallback to the first available label if 'beta' is not present
      available_labels <- unique(pred.grun\$labels)
      if (length(available_labels) > 0) {
        message("Attempting fallback plot with label: ", available_labels[1])
        plotMarkerHeatmap(pred.grun, sceG, label=available_labels[1])
      }
    })
    dev.off()

    writeLines(c(
        '"BIOC_SINGLER_ANNOTATION_WITH_SINGLE_CELL_REFERENCE_AND_DIAGNOSTICS":',
        paste0('    SingleR: ', as.character(packageVersion('SingleR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_annotation_with_single_cell_reference_and_diagnostics.csv versions.yml
    """
}

workflow BIOC_SINGLER_ANNOTATION_WITH_SINGLE_CELL_REFERENCE_AND_DIAGNOSTICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ test_dataset.rds, reference_dataset.rds ] ]

    main:
    BIOC_SINGLER_ANNOTATION_WITH_SINGLE_CELL_REFERENCE_AND_DIAGNOSTICS(ch_input)

    emit:
    tables   = BIOC_SINGLER_ANNOTATION_WITH_SINGLE_CELL_REFERENCE_AND_DIAGNOSTICS.out.tables
    plots    = BIOC_SINGLER_ANNOTATION_WITH_SINGLE_CELL_REFERENCE_AND_DIAGNOSTICS.out.plots
    objects  = BIOC_SINGLER_ANNOTATION_WITH_SINGLE_CELL_REFERENCE_AND_DIAGNOSTICS.out.objects
    versions = BIOC_SINGLER_ANNOTATION_WITH_SINGLE_CELL_REFERENCE_AND_DIAGNOSTICS.out.versions
}
