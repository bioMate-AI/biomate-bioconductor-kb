#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GOfuncR — contingency_test
// Test for enrichment of genes associated with four counts using the 2x2 contingency table test.
// Input: gene_counts_four.tsv
// Container: quay.io/biocontainers/bioconductor-gofuncr:1.30.0--r45ha27e39d_0
// R packages: GOfuncR
// Bioconductor: 3.20 | R: 4.4
// Requires: GOfuncR
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define genes and four count columns
//  * 2. [Core Analysis] Run enrichment analysis using go_enrich with test='contingency'
//  * 3. [Visualization & Output] Extract results and plot distribution of counts using plot_anno_scores

nextflow.enable.dsl = 2

process BIOC_GOFUNCR_CONTINGENCY_TEST {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    
    # Read the user input file
    # The file must be a tab-separated values file with gene symbols and four columns of counts
    input_conti <- read.delim("gene_counts_four.tsv", header = TRUE, stringsAsFactors = FALSE)
    
    # Ensure the columns are named appropriately for the workflow
    colnames(input_conti) <- c("gene_ids", "subs_non_syn", "subs_syn", "vari_non_syn", "vari_syn")
    
    # Run enrichment analysis using go_enrich with test='contingency'
    # Reproducing the exact argument names from the documented code (n_randset=100)
    res_conti <- go_enrich(input_conti, test = 'contingency', n_randset = 100)
    
    # Save the full enrichment results list as an RDS object
    saveRDS(res_conti, file = "contingency_enrichment_results.rds")
    
    # Write the main stats table to a CSV file
    write.csv(res_conti[[1]], file = "contingency_enrichment_stats.csv", row.names = FALSE)
    
    # Extract top GO categories and plot distribution of counts
    top_gos_conti <- res_conti[[1]][1:5, 'node_id']
    
    # Save the plot to a PDF file
    pdf("contingency_anno_scores_plot.pdf", width = 10, height = 7)
    plot_anno_scores(res_conti, top_gos_conti)
    dev.off()

    writeLines(c(
        '"BIOC_GOFUNCR_CONTINGENCY_TEST":',
        paste0('    GOfuncR: ', as.character(packageVersion('GOfuncR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_contingency_test.csv versions.yml
    """
}

workflow BIOC_GOFUNCR_CONTINGENCY_TEST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gene_counts_four.tsv ] ]

    main:
    BIOC_GOFUNCR_CONTINGENCY_TEST(ch_input)

    emit:
    tables   = BIOC_GOFUNCR_CONTINGENCY_TEST.out.tables
    plots    = BIOC_GOFUNCR_CONTINGENCY_TEST.out.plots
    objects  = BIOC_GOFUNCR_CONTINGENCY_TEST.out.objects
    versions = BIOC_GOFUNCR_CONTINGENCY_TEST.out.versions
}
