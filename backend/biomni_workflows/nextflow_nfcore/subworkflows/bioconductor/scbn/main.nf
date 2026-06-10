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
//  * 1. [Input & Preparation] Calculate the optimal scaling factor using the SCBN function with housekeeping gene indices. 2. Extract the scaling factor and pre

nextflow.enable.dsl = 2

process BIOC_SCBN_CROSS_SPECIES_DIFFERENTIAL_EXPRESSION {
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
    
    # 1. Calculate the optimal scaling factor using the SCBN function
    factor <- SCBN(orth_gene=orth_gene, hkind=hkind, a=0.05)
    
    # 2. Extract the scaling factor and prepare vectors for read counts, gene lengths, and library sizes
    scale <- factor\$scbn_val
    x <- orth_gene[, 2]
    y <- orth_gene[, 4]
    lengthx <- orth_gene[, 1]
    lengthy <- orth_gene[, 3]
    n1 <- sum(x)
    n2 <- sum(y)
    
    # 3. Compute p-values for each orthologous gene using the sageTestNew function
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
