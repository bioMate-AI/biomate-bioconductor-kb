#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SCBN — cross_species_differential_expression
// Normalize cross-species RNA-seq data and identify differentially expressed orthologous genes.
// Input: orthologous_genes_data.csv
// Container: quay.io/biocontainers/bioconductor-scbn:1.28.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SCBN
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Calculate the optimal scaling factor using the SCBN
//  * 2. [Input & Preparation] Extract the scaling factor and prepare vectors for read
//  * 3. [Input & Preparation] Compute p-values for each orthologous gene using the

nextflow.enable.dsl = 2

process BIOC_SCBN_CROSS_SPECIES_DIFFERENTIAL_EXPRESSION {
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
    .bm_deps <- c("SCBN")
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
    
    # Load required library
    library(SCBN)
    
    # Read the user input file from the working directory
    if (!file.exists("orthologous_genes_data.csv")) {
      stop("Error: 'orthologous_genes_data.csv' not found in the working directory.")
    }
    
    orth_gene <- read.csv("orthologous_genes_data.csv", header = TRUE)
    
    # Ensure the input is a data frame
    orth_gene <- as.data.frame(orth_gene)
    
    # Define housekeeping genes index (hkind)
    # We use the first 1000 genes (or fewer if the dataset is smaller) as housekeeping genes
    hkind <- 1:min(1000, nrow(orth_gene))
    
    # --- Calculate the optimal scaling factor using the SCBN ---
    factor <- SCBN(orth_gene=orth_gene, hkind=hkind, a=0.05)
    
    # --- Extract the scaling factor and prepare vectors for read ---
    scale <- factor\$scbn_val
    x <- orth_gene[, 2]
    y <- orth_gene[, 4]
    lengthx <- orth_gene[, 1]
    lengthy <- orth_gene[, 3]
    n1 <- sum(x)
    n2 <- sum(y)
    
    # --- Compute p-values for each orthologous gene using the ---
    p_value <- sageTestNew(x, y, lengthx, lengthy, n1, n2, scale)
    
    # Prepare the final results data frame
    results <- orth_gene
    results\$p_value <- p_value
    results\$significant_05 <- p_value < 0.05
    
    # Write the results to output files
    write.csv(results, "scbn_differential_expression_results.csv", row.names = FALSE)
    saveRDS(list(factor = factor, scale = scale, results = results), "scbn_output.rds")
    
    cat("SCBN pipeline completed successfully. Results saved to 'scbn_differential_expression_results.csv' and 'scbn_output.rds'.\n")

    writeLines(c(
        '"BIOC_SCBN_CROSS_SPECIES_DIFFERENTIAL_EXPRESSION":',
        paste0('    SCBN: ', as.character(packageVersion('SCBN')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cross_species_differential_expression.csv versions.yml
    """
}

workflow BIOC_SCBN_CROSS_SPECIES_DIFFERENTIAL_EXPRESSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ orthologous_genes_data.csv ] ]

    main:
    BIOC_SCBN_CROSS_SPECIES_DIFFERENTIAL_EXPRESSION(ch_input)

    emit:
    tables   = BIOC_SCBN_CROSS_SPECIES_DIFFERENTIAL_EXPRESSION.out.tables
    plots    = BIOC_SCBN_CROSS_SPECIES_DIFFERENTIAL_EXPRESSION.out.plots
    objects  = BIOC_SCBN_CROSS_SPECIES_DIFFERENTIAL_EXPRESSION.out.objects
    versions = BIOC_SCBN_CROSS_SPECIES_DIFFERENTIAL_EXPRESSION.out.versions
}
