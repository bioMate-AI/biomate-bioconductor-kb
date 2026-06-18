#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: arrayMvout — outlier_detection_from_qc_matrix
// Detect outlying microarrays using a pre-computed matrix of quality control metrics.
// Input: qc_matrix.csv
// Container: quay.io/biocontainers/bioconductor-arraymvout:1.68.0--r45hdfd78af_0
// R packages: affyPLM, arrayMvout, maqcsubset, mdqc, mvoutdata
// Bioconductor: 3.20 | R: 4.4
// Requires: arrayMvout
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the pre-computed QC feature data
//  * 2. [Core Analysis] Run outlier detection using ArrayOutliers
//  * 3. [Visualization & Output] Plot the outlier detection results

nextflow.enable.dsl = 2

process BIOC_ARRAYMVOUT_OUTLIER_DETECTION_FROM_QC_MATRIX {
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
    .bm_deps <- c("affyPLM", "arrayMvout", "maqcsubset", "mdqc", "mvoutdata")
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
    library(arrayMvout)
    
    # 1. Load the pre-computed QC feature data
    input_file <- "qc_matrix.csv"
    if (!file.exists(input_file)) {
      stop(paste("Error: Input file", input_file, "not found in the working directory."))
    }
    
    # Read the QC matrix (rows = arrays, columns = metrics)
    qc_data <- read.csv(input_file, row.names = 1, check.names = FALSE)
    qc_matrix <- as.matrix(qc_data)
    
    # 2. Run outlier detection using ArrayOutliers
    # Keeping the exact function call and argument names from the documented code
    ii <- ArrayOutliers(qc_matrix, alpha = 0.01)
    
    # Print the result summary to standard output
    print(ii)
    
    # Save the complete outlier detection object
    saveRDS(ii, file = "outliers_result.rds")
    
    # Safely extract and save the outliers table to a CSV file
    tryCatch({
      if ("outl" %in% names(ii)) {
        write.csv(ii[["outl"]], file = "detected_outliers.csv", row.names = TRUE)
      } else if (is.list(ii) && length(ii) >= 1) {
        write.csv(ii[[1]], file = "detected_outliers.csv", row.names = TRUE)
      } else if (is.object(ii) && .hasSlot(ii, "outl")) {
        write.csv(slot(ii, "outl"), file = "detected_outliers.csv", row.names = TRUE)
      }
    }, error = function(e) {
      warning("Could not write outliers table to CSV: ", e\$message)
    })
    
    # 3. Plot the outlier detection results
    # Keeping the exact plot call and arguments from the documented code
    pdf("outliers_plot.pdf", width = 7, height = 7)
    plot(ii, choices = c(1, 3))
    dev.off()

    writeLines(c(
        '"BIOC_ARRAYMVOUT_OUTLIER_DETECTION_FROM_QC_MATRIX":',
        paste0('    arrayMvout: ', as.character(packageVersion('arrayMvout')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_outlier_detection_from_qc_matrix.csv versions.yml
    """
}

workflow BIOC_ARRAYMVOUT_OUTLIER_DETECTION_FROM_QC_MATRIX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ qc_matrix.csv ] ]

    main:
    BIOC_ARRAYMVOUT_OUTLIER_DETECTION_FROM_QC_MATRIX(ch_input)

    emit:
    tables   = BIOC_ARRAYMVOUT_OUTLIER_DETECTION_FROM_QC_MATRIX.out.tables
    plots    = BIOC_ARRAYMVOUT_OUTLIER_DETECTION_FROM_QC_MATRIX.out.plots
    objects  = BIOC_ARRAYMVOUT_OUTLIER_DETECTION_FROM_QC_MATRIX.out.objects
    versions = BIOC_ARRAYMVOUT_OUTLIER_DETECTION_FROM_QC_MATRIX.out.versions
}
