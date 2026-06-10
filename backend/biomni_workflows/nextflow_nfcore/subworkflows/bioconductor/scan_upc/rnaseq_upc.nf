#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scan_upc — rnaseq_upc
// Estimate universal gene expression probabilities from RNA-Seq expression values.
// Input: expression_matrix.txt
// Container: quay.io/biocontainers/r-base:4.3.1
// R packages: Biobase, SCAN.UPC
// Bioconductor: 3.20 | R: 4.4
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCAN_UPC_RNASEQ_UPC {
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
    .bm_deps <- c("Biobase", "SCAN.UPC")
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
    
    # Define input file path
    input_file <- "expression_matrix.txt"
    
    # Check if input file exists
    if (!file.exists(input_file)) {
      stop(paste("Error: Input file", input_file, "not found in the working directory."))
    }
    
    # Estimate universal gene expression probabilities using UPC_Generic
    message("Estimating universal gene expression probabilities...")
    upc_values = UPC_Generic("expression_matrix.txt")
    
    # Save the resulting ExpressionSet object
    message("Saving results...")
    saveRDS(upc_values, "upc_values.rds")
    
    # Extract the probability matrix and save as CSV
    upc_matrix <- exprs(upc_values)
    write.csv(upc_matrix, "upc_probabilities.csv", row.names = TRUE)
    
    message("Pipeline completed successfully. Outputs saved to 'upc_values.rds' and 'upc_probabilities.csv'.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_SCAN_UPC_RNASEQ_UPC":
        scan_upc: \$(Rscript -e 'cat(as.character(packageVersion("scan_upc")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rnaseq_upc.csv versions.yml
    """
}

workflow BIOC_SCAN_UPC_RNASEQ_UPC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.txt ] ]

    main:
    BIOC_SCAN_UPC_RNASEQ_UPC(ch_input)

    emit:
    tables   = BIOC_SCAN_UPC_RNASEQ_UPC.out.tables
    plots    = BIOC_SCAN_UPC_RNASEQ_UPC.out.plots
    objects  = BIOC_SCAN_UPC_RNASEQ_UPC.out.objects
    versions = BIOC_SCAN_UPC_RNASEQ_UPC.out.versions
}
