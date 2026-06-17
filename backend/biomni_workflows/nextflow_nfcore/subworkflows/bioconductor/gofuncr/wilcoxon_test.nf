#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GOfuncR — wilcoxon_test
// Test for enrichment of high (or low) scored genes using the Wilcoxon rank-sum test.
// Input: gene_scores.tsv
// Container: quay.io/biocontainers/bioconductor-gofuncr:1.30.0--r45ha27e39d_0
// R packages: GOfuncR
// Bioconductor: 3.20 | R: 4.4
// Requires: GOfuncR
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define genes and their continuous scores
//  * 2. [Core Analysis] Run enrichment analysis using go_enrich with test='wilcoxon'
//  * 3. [Visualization & Output] Extract results and plot distribution of scores using plot_anno_scores

nextflow.enable.dsl = 2

process BIOC_GOFUNCR_WILCOXON_TEST {
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
    library(GOfuncR)
    
    # 1. Define genes and their continuous scores by reading the user input file
    input_data = read.delim("gene_scores.tsv", sep="\t", header=TRUE, stringsAsFactors=FALSE)
    input_willi = data.frame(
      gene_ids = input_data[, 1],
      gene_scores = as.numeric(input_data[, 2])
    )
    
    # 2. Run enrichment analysis using go_enrich with test='wilcoxon'
    res_willi = go_enrich(input_willi, test='wilcoxon', n_randsets=100)
    
    # 3. Extract results and plot distribution of scores using plot_anno_scores
    # Save the text results and RDS object
    write.csv(res_willi[[1]], "wilcoxon_enrichment_results.csv", row.names=FALSE)
    saveRDS(res_willi, "res_willi.rds")
    
    # Extract top GOs and plot
    top_gos_willi = res_willi[[1]][1:5, 'node_id']
    
    # Save plot to PDF
    pdf("wilcoxon_anno_scores_plot.pdf", width=10, height=7)
    plot_anno_scores(res_willi, top_gos_willi)
    dev.off()

    writeLines(c(
        '"BIOC_GOFUNCR_WILCOXON_TEST":',
        paste0('    GOfuncR: ', as.character(packageVersion('GOfuncR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_wilcoxon_test.csv versions.yml
    """
}

workflow BIOC_GOFUNCR_WILCOXON_TEST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gene_scores.tsv ] ]

    main:
    BIOC_GOFUNCR_WILCOXON_TEST(ch_input)

    emit:
    tables   = BIOC_GOFUNCR_WILCOXON_TEST.out.tables
    plots    = BIOC_GOFUNCR_WILCOXON_TEST.out.plots
    objects  = BIOC_GOFUNCR_WILCOXON_TEST.out.objects
    versions = BIOC_GOFUNCR_WILCOXON_TEST.out.versions
}
