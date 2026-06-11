#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: celaref — scrnaseq_to_scrnaseq_comparison
// Compare a query single-cell RNA-seq dataset to a single-cell RNA-seq reference dataset to annotate query clusters.
// Input: sim_query_counts.tab, sim_query_cell_info.tab, sim_ref_counts.tab, sim_ref_cell_info.tab
// Container: quay.io/biocontainers/bioconductor-celaref:1.28.0--r45hdfd78af_0
// R packages: celaref, ExperimentHub, ggplot2, Matrix, tidyverse
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CELAREF_SCRNASEQ_TO_SCRNASEQ_COMPARISON {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-celaref:1.28.0--r45hdfd78af_0"

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
    .bm_deps <- c("celaref", "ExperimentHub", "ggplot2", "Matrix", "tidyverse")
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
    library(celaref)
    library(ggplot2)
    
    # Define input file paths as specified by the user
    counts_filepath.query <- "sim_query_counts.tab"
    cell_info_filepath.query <- "sim_query_cell_info.tab"
    counts_filepath.ref <- "sim_ref_counts.tab"
    cell_info_filepath.ref <- "sim_ref_cell_info.tab"
    
    # 1. Load query and reference datasets into SummarizedExperiment objects
    toy_ref_se   <- load_se_from_files(counts_file=counts_filepath.ref, cell_info_file=cell_info_filepath.ref)
    toy_query_se <- load_se_from_files(counts_file=counts_filepath.query, cell_info_file=cell_info_filepath.query)
    
    # 2. Filter out low-expression genes and small cell groups
    toy_ref_se     <- trim_small_groups_and_low_expression_genes(toy_ref_se)
    toy_query_se   <- trim_small_groups_and_low_expression_genes(toy_query_se)
    
    # Save filtered SummarizedExperiment objects for downstream reproducibility
    saveRDS(toy_ref_se, "toy_ref_se.rds")
    saveRDS(toy_query_se, "toy_query_se.rds")
    
    # 3. Run within-experiment differential expression
    de_table.toy_ref   <- contrast_each_group_to_the_rest(toy_ref_se,    dataset_name="ref")
    de_table.toy_query <- contrast_each_group_to_the_rest(toy_query_se,  dataset_name="query")
    
    # Save differential expression tables
    write.csv(de_table.toy_ref, "de_table_ref.csv", row.names = FALSE)
    write.csv(de_table.toy_query, "de_table_query.csv", row.names = FALSE)
    
    # 4. Generate rank distribution violin plots
    pdf("ranking_violin_plot.pdf", width = 10, height = 8)
    plot_out <- make_ranking_violin_plot(de_table.test=de_table.toy_query, de_table.ref=de_table.toy_ref)
    if (inherits(plot_out, "ggplot")) {
        print(plot_out)
    }
    dev.off()
    
    # 5. Suggest cluster labels based on reference similarity
    similarity_labels <- make_ref_similarity_names(de_table.toy_query, de_table.toy_ref)
    
    # Save suggested cluster labels
    write.csv(similarity_labels, "similarity_labels.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_CELAREF_SCRNASEQ_TO_SCRNASEQ_COMPARISON":',
        paste0('        celaref: ', as.character(packageVersion("celaref")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scrnaseq_to_scrnaseq_comparison.csv versions.yml
    """
}

workflow BIOC_CELAREF_SCRNASEQ_TO_SCRNASEQ_COMPARISON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sim_query_counts.tab, sim_query_cell_info.tab, sim_ref_counts.tab, sim_ref_cell_info.tab ] ]

    main:
    BIOC_CELAREF_SCRNASEQ_TO_SCRNASEQ_COMPARISON(ch_input)

    emit:
    tables   = BIOC_CELAREF_SCRNASEQ_TO_SCRNASEQ_COMPARISON.out.tables
    plots    = BIOC_CELAREF_SCRNASEQ_TO_SCRNASEQ_COMPARISON.out.plots
    objects  = BIOC_CELAREF_SCRNASEQ_TO_SCRNASEQ_COMPARISON.out.objects
    versions = BIOC_CELAREF_SCRNASEQ_TO_SCRNASEQ_COMPARISON.out.versions
}
