#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: vsn — affymetrix_genechip_normalization
// Preprocess Affymetrix genechip data using the RMA method with VSN background correction, normalization, and transformation.
// Input: Dilution
// Container: quay.io/biocontainers/bioconductor-vsn:3.78.1--r45h01b2380_0
// R packages: Biobase, affy, vsn
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, affy, vsn
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Save the normalized ExpressionSet object as an RDS file
//  * 2. [Visualization & Output] Save the normalized expression matrix as a CSV table
//  * 3. [Visualization & Output] Generate and save diagnostic plots (mean-sd plot) to a PDF

nextflow.enable.dsl = 2

process BIOC_VSN_AFFYMETRIX_GENECHIP_NORMALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20-slim"

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
    .bm_deps <- c("Biobase", "affy", "vsn")
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
    library(vsn)
    library(affy)
    library(Biobase)
    
    # Define input file path
    input_file <- "Dilution.rds"
    
    # Verify the input file exists
    if (!file.exists(input_file)) {
      stop(paste("Error: Input file", input_file, "not found in the working directory."))
    }
    
    # Read the user input AffyBatch object
    Dilution <- readRDS(input_file)
    
    # Verify the object class
    if (!inherits(Dilution, "AffyBatch")) {
      stop("Error: The input object must be of class 'AffyBatch'.")
    }
    
    # Run the documented workflow: vsnrma to perform background correction,
    # between-array normalization, transformation, and summarization.
    d_vsn = vsnrma(Dilution)
    
    # Write named output files for the meaningful results
    
    # --- Save the normalized ExpressionSet object as an RDS file ---
    saveRDS(d_vsn, file = "d_vsn.rds")
    
    # --- Save the normalized expression matrix as a CSV table ---
    normalized_exprs <- exprs(d_vsn)
    write.csv(normalized_exprs, file = "normalized_intensities.csv", row.names = TRUE)
    
    # --- Generate and save diagnostic plots (mean-sd plot) to a PDF ---
    pdf("vsn_diagnostic_plots.pdf", width = 7, height = 7)
    tryCatch({
      meanSdPlot(d_vsn)
    }, error = function(e) {
      warning("Could not generate meanSdPlot: ", e\$message)
    })
    dev.off()
    
    cat("Pipeline completed successfully. Outputs written to 'd_vsn.rds', 'normalized_intensities.csv', and 'vsn_diagnostic_plots.pdf'.\n")

    writeLines(c(
        '"BIOC_VSN_AFFYMETRIX_GENECHIP_NORMALIZATION":',
        paste0('    vsn: ', as.character(packageVersion('vsn')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_affymetrix_genechip_normalization.csv versions.yml
    """
}

workflow BIOC_VSN_AFFYMETRIX_GENECHIP_NORMALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Dilution ] ]

    main:
    BIOC_VSN_AFFYMETRIX_GENECHIP_NORMALIZATION(ch_input)

    emit:
    tables   = BIOC_VSN_AFFYMETRIX_GENECHIP_NORMALIZATION.out.tables
    plots    = BIOC_VSN_AFFYMETRIX_GENECHIP_NORMALIZATION.out.plots
    objects  = BIOC_VSN_AFFYMETRIX_GENECHIP_NORMALIZATION.out.objects
    versions = BIOC_VSN_AFFYMETRIX_GENECHIP_NORMALIZATION.out.versions
}
