#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RITAN — term_enrichment_analysis
// Run hypergeometric enrichment analysis on a list of genes of interest across selected annotation resources or a custom GMT file.
// Input: my_genes.txt, curated_gene_disease_associations.gmt.gz
// Container: quay.io/biocontainers/bioconductor-ritan:1.34.0--r45hdfd78af_0
// R packages: knitr, RITAN, RITANdata
// Bioconductor: 3.20 | R: 4.4
// Requires: RITAN, RITANdata
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load the input gene list and define the target resources
//  * 2. [Visualization & Output] Run hypergeometric enrichment testing using
//  * 3. [Visualization & Output] Summarize and inspect the top enriched terms using

nextflow.enable.dsl = 2

process BIOC_RITAN_TERM_ENRICHMENT_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("knitr", "RITAN", "RITANdata")
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
        library(RITANdata)
        library(RITAN)
        
        # --- Load the input gene list and define the target resources ---
        if (!file.exists("my_genes.txt")) {
          stop("Required input file 'my_genes.txt' not found in the working directory.")
        }
        
        # Read the user-provided gene list
        my_genes <- readLines("my_genes.txt")
        my_genes <- unique(trimws(my_genes[my_genes != ""]))
        
        # Define resources and background genes
        resources <- c("ReactomePathways", "MSigDB_Hallmarks")
        
        # Define the optional custom GMT file path
        gmt <- "curated_gene_disease_associations.gmt.gz"
        
        # Use the input genes as the query set 'gs' for the custom GMT enrichment
        gs <- my_genes
        
        # --- Run hypergeometric enrichment testing using ---
        e <- term_enrichment (my_genes, resources = resources, all_symbols = cached_coding_genes)
        
        # --- Summarize and inspect the top enriched terms using ---
        summary (e)
        
        # Save standard enrichment results
        write.csv(e, "term_enrichment_results.csv", row.names = FALSE)
        saveRDS(e, "term_enrichment_results.rds")
        
        # Run enrichment against the custom GMT file if it exists
        e2 <- NULL
        if (file.exists(gmt)) {
          e2 <- term_enrichment ( gs, resources = gmt, all_symbols = cached_coding_genes )
          print ( e2[ 1 : 3 , - 5 ] )
          
          # Save custom GMT enrichment results
          write.csv(e2, "term_enrichment_gmt_results.csv", row.names = FALSE)
          saveRDS(e2, "term_enrichment_gmt_results.rds")
        } else {
          message("Optional custom GMT file 'curated_gene_disease_associations.gmt.gz' not found. Skipping custom GMT enrichment.")
        }

    writeLines(c(
        '"BIOC_RITAN_TERM_ENRICHMENT_ANALYSIS":',
        paste0('    RITAN: ', as.character(packageVersion('RITAN')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_term_enrichment_analysis.csv versions.yml
    """
}

workflow BIOC_RITAN_TERM_ENRICHMENT_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ my_genes.txt, curated_gene_disease_associations.gmt.gz ] ]

    main:
    BIOC_RITAN_TERM_ENRICHMENT_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_RITAN_TERM_ENRICHMENT_ANALYSIS.out.tables
    plots    = BIOC_RITAN_TERM_ENRICHMENT_ANALYSIS.out.plots
    objects  = BIOC_RITAN_TERM_ENRICHMENT_ANALYSIS.out.objects
    versions = BIOC_RITAN_TERM_ENRICHMENT_ANALYSIS.out.versions
}
