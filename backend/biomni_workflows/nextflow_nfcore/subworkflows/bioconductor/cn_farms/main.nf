#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cn_farms — cn_farms_pipeline
// Estimate copy numbers from raw Affymetrix CEL files using the FARMS algorithm.
// Input: cel_files.CEL
// Container: quay.io/biocontainers/r-base:4.3.1
// R packages: cn.farms, cn_farms
// Bioconductor: 3.20 | R: 4.4
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: box plot

nextflow.enable.dsl = 2

process BIOC_CN_FARMS_CN_FARMS_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/r-base:4.3.1"

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
    .bm_deps <- c("cn.farms", "cn_farms")
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
    
    # Load the required Bioconductor package
    library(cn.farms)
    
    # --- Locate CEL files ---
    # The pipeline reads the declared user input 'cel_files.CEL' from the working directory.
    # If not found under that exact name, it falls back to any CEL files in the directory.
    filenames <- "cel_files.CEL"
    if (!file.exists(filenames)) {
      filenames <- list.files(pattern = "cel_files\\\\.CEL\$", ignore.case = TRUE, full.names = TRUE)
    }
    if (length(filenames) == 0 || !file.exists(filenames[1])) {
      filenames <- list.files(pattern = "\\\\.CEL\$", ignore.case = TRUE, full.names = TRUE)
    }
    
    if (length(filenames) == 0) {
      stop("Error: No CEL files found. Please ensure 'cel_files.CEL' is in the working directory.")
    }
    
    # --- Run the cn.farms pipeline to normalize, correct for ---
    # Keeping the exact function call and argument names from the documented code
    cn.data <- cn.farms(filenames)
    
    # --- Extract copy number estimates and save outputs ---
    # Save the complete ExpressionSet object as an RDS file
    saveRDS(cn.data, file = "cn_farms_output.rds")
    
    # Extract copy number estimates and write to a CSV table
    if (inherits(cn.data, "ExpressionSet")) {
      cn_estimates <- exprs(cn.data)
      write.csv(cn_estimates, file = "copy_number_estimates.csv", row.names = TRUE)
    } else {
      tryCatch({
        cn_estimates <- assayDataElement(cn.data, "exprs")
        write.csv(cn_estimates, file = "copy_number_estimates.csv", row.names = TRUE)
      }, error = function(e) {
        warning("Could not extract copy number estimates using standard ExpressionSet methods.")
      })
    }
    
    # Generate a diagnostic PDF plot of the copy number distribution
    pdf("copy_number_distribution.pdf")
    tryCatch({
      boxplot(exprs(cn.data), main = "Distribution of Copy Number Estimates", 
              xlab = "Samples", ylab = "Intensity (log2 scale)", col = "lightblue")
    }, error = function(e) {
      plot(1, type = "n", main = "Plotting failed", xlab = "", ylab = "")
      text(1, 1, "Could not generate boxplot of estimates")
    })
    dev.off()

    writeLines(c(
        '"BIOC_CN_FARMS_CN_FARMS_PIPELINE":',
        paste0('        cn_farms: ', as.character(packageVersion("cn_farms")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cn_farms_pipeline.csv versions.yml
    """
}

workflow BIOC_CN_FARMS_CN_FARMS_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ cel_files.CEL ] ]

    main:
    BIOC_CN_FARMS_CN_FARMS_PIPELINE(ch_input)

    emit:
    tables   = BIOC_CN_FARMS_CN_FARMS_PIPELINE.out.tables
    plots    = BIOC_CN_FARMS_CN_FARMS_PIPELINE.out.plots
    objects  = BIOC_CN_FARMS_CN_FARMS_PIPELINE.out.objects
    versions = BIOC_CN_FARMS_CN_FARMS_PIPELINE.out.versions
}
