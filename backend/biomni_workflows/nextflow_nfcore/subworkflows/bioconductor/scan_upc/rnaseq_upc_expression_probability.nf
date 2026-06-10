#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scan_upc — rnaseq_upc_expression_probability
// Estimate universal gene expression probabilities from RNA-Seq abundance data.
// Input: rna_seq_rpkm.txt
// Container: quay.io/biocontainers/r-base:4.3.1
// R packages: Biobase, SCAN.UPC
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, scan_upc
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the SCAN.UPC library
//  * 2. [Core Analysis] Run UPC_RNASeq on the abundance file to calculate standardized expression probabilities

nextflow.enable.dsl = 2

process BIOC_SCAN_UPC_RNASEQ_UPC_EXPRESSION_PROBABILITY {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    
    # Load the required libraries
    library(SCAN.UPC)
    library(Biobase)
    
    # Define input and output file paths
    input_file <- "rna_seq_rpkm.txt"
    output_csv <- "upc_expression_probabilities.csv"
    output_rds <- "upc_rnaseq_results.rds"
    output_pdf <- "upc_probabilities_histogram.pdf"
    
    # Verify that the user input file exists
    if (!file.exists(input_file)) {
      stop(paste("Error: Input file", input_file, "not found in the working directory."))
    }
    
    # Run UPC_RNASeq on the abundance file to calculate standardized expression probabilities
    message("Estimating universal gene expression probabilities using UPC_RNASeq...")
    upc_rnaseq_results <- UPC_RNASeq(input_file)
    
    # Save the complete ExpressionSet object as an RDS file
    message("Saving ExpressionSet object...")
    saveRDS(upc_rnaseq_results, file = output_rds)
    
    # Extract the expression probability matrix
    prob_matrix <- Biobase::exprs(upc_rnaseq_results)
    
    # Save the probability matrix to a CSV file
    message("Saving expression probabilities to CSV...")
    write.csv(prob_matrix, file = output_csv, row.names = TRUE)
    
    # Generate a diagnostic histogram of the estimated probabilities
    message("Generating diagnostic plot...")
    pdf(output_pdf, width = 8, height = 6)
    hist(prob_matrix, 
         breaks = 50, 
         col = "skyblue", 
         border = "white",
         main = "Distribution of UPC Expression Probabilities",
         xlab = "UPC Probability (0 = Inactive, 1 = Active)",
         ylab = "Frequency")
    dev.off()
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_SCAN_UPC_RNASEQ_UPC_EXPRESSION_PROBABILITY":',
        paste0('    scan_upc: ', as.character(packageVersion('scan_upc')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rnaseq_upc_expression_probability.csv versions.yml
    """
}

workflow BIOC_SCAN_UPC_RNASEQ_UPC_EXPRESSION_PROBABILITY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ rna_seq_rpkm.txt ] ]

    main:
    BIOC_SCAN_UPC_RNASEQ_UPC_EXPRESSION_PROBABILITY(ch_input)

    emit:
    tables   = BIOC_SCAN_UPC_RNASEQ_UPC_EXPRESSION_PROBABILITY.out.tables
    plots    = BIOC_SCAN_UPC_RNASEQ_UPC_EXPRESSION_PROBABILITY.out.plots
    objects  = BIOC_SCAN_UPC_RNASEQ_UPC_EXPRESSION_PROBABILITY.out.objects
    versions = BIOC_SCAN_UPC_RNASEQ_UPC_EXPRESSION_PROBABILITY.out.versions
}
