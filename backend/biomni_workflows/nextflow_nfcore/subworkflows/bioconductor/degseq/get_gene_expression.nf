#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DEGseq — get_gene_expression
// Count the number of reads mapped to each gene for a single sample to generate expression values.
// Input: sample.bed, refFlat.txt
// Container: quay.io/biocontainers/bioconductor-degseq:1.64.0--r45ha27e39d_0
// R packages: DEGseq
// Bioconductor: 3.20 | R: 4.4
// Requires: DEGseq
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Define input file paths and output file path
//  * 2. [Visualization & Output] Run getGeneExp to count reads and output raw counts and RPKM values to a text file

nextflow.enable.dsl = 2

process BIOC_DEGSEQ_GET_GENE_EXPRESSION {
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
    .bm_deps <- c("DEGseq")
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
    library(DEGseq)
    
    # Stage 1: Define input file paths and output file path
    # The pipeline reads exactly these files from the working directory
    sample_bed <- "sample.bed"
    refFlat_file <- "refFlat.txt"
    
    # Verify that the required input files exist
    if (!file.exists(sample_bed)) {
      stop("Required input file 'sample.bed' not found in the working directory.")
    }
    if (!file.exists(refFlat_file)) {
      stop("Required input file 'refFlat.txt' not found in the working directory.")
    }
    
    # Prepare the arguments exactly as expected by the documented code
    mapResultBatch <- c(sample_bed)
    refFlat <- refFlat_file
    output <- "gene_expression_counts.txt"
    
    # Stage 2: Run getGeneExp to count reads and output raw counts and RPKM values to a text file
    # This call matches the documented code exactly:
    # exp <- getGeneExp(mapResultBatch, refFlat=refFlat, output=output)
    exp <- getGeneExp(mapResultBatch, refFlat=refFlat, output=output)
    
    # Stage 3: Write additional named output files for downstream analysis
    # Save the returned data frame as an RDS object and a CSV table
    saveRDS(exp, file = "gene_expression_results.rds")
    write.csv(exp, file = "gene_expression_results.csv", row.names = FALSE)
    
    # Print a completion message to standard output
    cat("Workflow completed successfully. Outputs saved to:\n")
    cat("- ", output, " (Raw counts and RPKM text file)\n", sep = "")
    cat("- gene_expression_results.rds (R data object)\n")
    cat("- gene_expression_results.csv (CSV table)\n")

    writeLines(c(
        '"BIOC_DEGSEQ_GET_GENE_EXPRESSION":',
        paste0('    DEGseq: ', as.character(packageVersion('DEGseq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_get_gene_expression.csv versions.yml
    """
}

workflow BIOC_DEGSEQ_GET_GENE_EXPRESSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sample.bed, refFlat.txt ] ]

    main:
    BIOC_DEGSEQ_GET_GENE_EXPRESSION(ch_input)

    emit:
    tables   = BIOC_DEGSEQ_GET_GENE_EXPRESSION.out.tables
    plots    = BIOC_DEGSEQ_GET_GENE_EXPRESSION.out.plots
    objects  = BIOC_DEGSEQ_GET_GENE_EXPRESSION.out.objects
    versions = BIOC_DEGSEQ_GET_GENE_EXPRESSION.out.versions
}
