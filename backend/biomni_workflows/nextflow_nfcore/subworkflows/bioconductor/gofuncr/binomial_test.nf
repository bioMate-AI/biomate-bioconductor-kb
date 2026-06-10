#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GOfuncR — binomial_test
// Test for enrichment of genes associated with two counts using the binomial test.
// Input: gene_counts_two.tsv
// Container: quay.io/biocontainers/bioconductor-gofuncr:1.30.0--r45ha27e39d_0
// R packages: GOfuncR
// Bioconductor: 3.20 | R: 4.4
// Requires: GOfuncR
// Visualizations: enrichment plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define genes and two count columns
//  * 2. [Core Analysis] Run enrichment analysis using go_enrich with test='binomial'
//  * 3. [Visualization & Output] Extract results and plot distribution of counts using plot_anno_scores

nextflow.enable.dsl = 2

process BIOC_GOFUNCR_BINOMIAL_TEST {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("GOfuncR")
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
    library(GOfuncR)
    
    # Read user input file
    if (!file.exists("gene_counts_two.tsv")) {
      stop("Error: 'gene_counts_two.tsv' not found in the working directory.")
    }
    
    input_data <- read.delim("gene_counts_two.tsv", header=TRUE, stringsAsFactors=FALSE)
    
    # Format the input dataframe to match the expected columns for go_enrich binomial test
    input_binom <- data.frame(
      gene_ids = input_data[[1]],
      A_counts = input_data[[2]],
      B_counts = input_data[[3]]
    )
    
    # Run enrichment analysis using go_enrich with test='binomial'
    res_binom <- go_enrich(
      input_binom, 
      test='binomial', 
      n_randsets=100,
      silent=TRUE, 
      domains=c('molecular_function', 'cellular_component')
    )
    
    # Extract top GO categories
    top_gos_binom <- res_binom[[1]][1:5, 'node_id']
    
    # Write the enrichment results to a CSV file
    write.csv(res_binom[[1]], file="binomial_enrichment_results.csv", row.names=FALSE)
    
    # Plot distribution of counts and save to PDF
    pdf("binomial_enrichment_plot.pdf", width=10, height=7)
    plot_anno_scores(res_binom, top_gos_binom)
    dev.off()

    writeLines(c(
        '"BIOC_GOFUNCR_BINOMIAL_TEST":',
        paste0('    GOfuncR: ', as.character(packageVersion('GOfuncR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_binomial_test.csv versions.yml
    """
}

workflow BIOC_GOFUNCR_BINOMIAL_TEST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gene_counts_two.tsv ] ]

    main:
    BIOC_GOFUNCR_BINOMIAL_TEST(ch_input)

    emit:
    tables   = BIOC_GOFUNCR_BINOMIAL_TEST.out.tables
    plots    = BIOC_GOFUNCR_BINOMIAL_TEST.out.plots
    objects  = BIOC_GOFUNCR_BINOMIAL_TEST.out.objects
    versions = BIOC_GOFUNCR_BINOMIAL_TEST.out.versions
}
