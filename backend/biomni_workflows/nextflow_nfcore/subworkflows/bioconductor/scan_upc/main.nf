#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scan_upc — microarray_scan_upc
// Normalize raw Affymetrix CEL files and estimate universal gene expression probabilities.
// Input: sample.CEL
// Container: quay.io/biocontainers/r-base:4.3.1
// R packages: Biobase, SCAN.UPC, doParallel, GEOquery, scan_upc
// Bioconductor: 3.20 | R: 4.4
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCAN_UPC_MICROARRAY_SCAN_UPC {
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
    .bm_deps <- c("Biobase", "SCAN.UPC", "doParallel", "GEOquery", "scan_upc")
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
    library(SCAN.UPC)
    library(Biobase)
    
    # Define input file
    input_cel <- "sample.CEL"
    
    # Verify that the user-provided input file exists
    if (!file.exists(input_cel)) {
      stop(paste("Error: Required input file '", input_cel, "' not found in the working directory.", sep = ""))
    }
    
    # Stage 1: Normalize raw CEL files individually using the SCAN function
    message("Running SCAN normalization on ", input_cel, "...")
    normalized = SCAN("sample.CEL")
    
    # Stage 2: Calculate universal expression probabilities using the UPC function
    message("Running UPC estimation on ", input_cel, "...")
    upc_values = UPC("sample.CEL")
    
    # Save the raw ExpressionSet objects to RDS
    message("Saving ExpressionSet objects to RDS...")
    saveRDS(normalized, file = "normalized_expression.rds")
    saveRDS(upc_values, file = "upc_values.rds")
    
    # Extract expression matrices
    norm_matrix <- exprs(normalized)
    upc_matrix <- exprs(upc_values)
    
    # Save the expression matrices to CSV
    message("Saving expression matrices to CSV...")
    write.csv(norm_matrix, file = "normalized_expression.csv", row.names = TRUE)
    write.csv(upc_matrix, file = "upc_values.csv", row.names = TRUE)
    
    # Generate diagnostic plots
    message("Generating diagnostic plots...")
    pdf("scan_upc_diagnostics.pdf", width = 10, height = 5)
    par(mfrow = c(1, 2))
    
    # Plot 1: Density of SCAN-normalized values
    plot(density(norm_matrix[, 1]), 
         main = "SCAN Normalized Expression Density", 
         xlab = "Log2 Expression Intensity", 
         col = "blue", 
         lwd = 2)
    
    # Plot 2: Density of UPC values (probabilities)
    plot(density(upc_matrix[, 1]), 
         main = "UPC Expression Probabilities", 
         xlab = "Probability of Active Expression (0 to 1)", 
         col = "red", 
         lwd = 2)
    
    dev.off()
    
    message("Pipeline completed successfully. Outputs written to:")
    message("- normalized_expression.rds")
    message("- upc_values.rds")
    message("- normalized_expression.csv")
    message("- upc_values.csv")
    message("- scan_upc_diagnostics.pdf")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_SCAN_UPC_MICROARRAY_SCAN_UPC":
        scan_upc: \$(Rscript -e 'cat(as.character(packageVersion("scan_upc")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_microarray_scan_upc.csv versions.yml
    """
}

workflow BIOC_SCAN_UPC_MICROARRAY_SCAN_UPC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sample.CEL ] ]

    main:
    BIOC_SCAN_UPC_MICROARRAY_SCAN_UPC(ch_input)

    emit:
    tables   = BIOC_SCAN_UPC_MICROARRAY_SCAN_UPC.out.tables
    plots    = BIOC_SCAN_UPC_MICROARRAY_SCAN_UPC.out.plots
    objects  = BIOC_SCAN_UPC_MICROARRAY_SCAN_UPC.out.objects
    versions = BIOC_SCAN_UPC_MICROARRAY_SCAN_UPC.out.versions
}
