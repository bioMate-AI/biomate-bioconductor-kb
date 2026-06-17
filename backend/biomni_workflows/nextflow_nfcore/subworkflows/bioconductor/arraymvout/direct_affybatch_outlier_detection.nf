#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: arrayMvout — direct_affybatch_outlier_detection
// Detect outliers directly from an AffyBatch object without manually pre-computing intermediate QA objects.
// Input: raw_arrays.CEL
// Container: quay.io/biocontainers/bioconductor-arraymvout:1.68.0--r45hdfd78af_0
// R packages: affy, arrayMvout
// Bioconductor: 3.20 | R: 4.4
// Requires: affy, arrayMvout
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the AffyBatch object
//  * 2. [Core Analysis] Run outlier detection using ArrayOutliers directly on the AffyBatch object

nextflow.enable.dsl = 2

process BIOC_ARRAYMVOUT_DIRECT_AFFYBATCH_OUTLIER_DETECTION {
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
    .bm_deps <- c("affy", "arrayMvout")
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
    library(arrayMvout)
    library(affy)
    
    # 1. Load the AffyBatch object from the user-specified directory
    input_dir <- "raw_arrays.CEL"
    if (!dir.exists(input_dir)) {
      stop(paste("Required input directory '", input_dir, "' does not exist in the working directory.", sep = ""))
    }
    
    # Read the CEL files into an AffyBatch object named 's12c' to match documented code
    s12c <- affy::ReadAffy(celfile.path = input_dir)
    
    # 2. Run outlier detection using ArrayOutliers directly on the AffyBatch object
    aos12c = ArrayOutliers(s12c, alpha=0.05)
    
    # 3. Display documented outputs
    print(aos12c[[1]])
    print(aos12c[[4]])
    
    # 4. Save meaningful results to output files
    # Save the detected outliers table
    write.csv(aos12c[[1]], file = "detected_outliers.csv", row.names = FALSE)
    
    # Save the full QC features matrix
    if (length(aos12c) >= 3) {
      write.csv(aos12c[[3]], file = "qc_features.csv", row.names = TRUE)
    }
    
    # Save the detailed outlier list at different alpha levels
    sink("outlier_details_by_alpha.txt")
    print(aos12c[[4]])
    sink()
    
    # Save the complete ArrayOutliers result object
    saveRDS(aos12c, file = "array_outliers_result.rds")
    
    # Generate diagnostic plot
    pdf("outliers_biplot.pdf")
    tryCatch({
      plot(aos12c, choices = c(1, 3))
    }, error = function(e) {
      message("Plotting skipped or failed: ", e\$message)
    })
    dev.off()

    writeLines(c(
        '"BIOC_ARRAYMVOUT_DIRECT_AFFYBATCH_OUTLIER_DETECTION":',
        paste0('    arrayMvout: ', as.character(packageVersion('arrayMvout')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_direct_affybatch_outlier_detection.csv versions.yml
    """
}

workflow BIOC_ARRAYMVOUT_DIRECT_AFFYBATCH_OUTLIER_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ raw_arrays.CEL ] ]

    main:
    BIOC_ARRAYMVOUT_DIRECT_AFFYBATCH_OUTLIER_DETECTION(ch_input)

    emit:
    tables   = BIOC_ARRAYMVOUT_DIRECT_AFFYBATCH_OUTLIER_DETECTION.out.tables
    plots    = BIOC_ARRAYMVOUT_DIRECT_AFFYBATCH_OUTLIER_DETECTION.out.plots
    objects  = BIOC_ARRAYMVOUT_DIRECT_AFFYBATCH_OUTLIER_DETECTION.out.objects
    versions = BIOC_ARRAYMVOUT_DIRECT_AFFYBATCH_OUTLIER_DETECTION.out.versions
}
