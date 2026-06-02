#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: gemma.R
// Low- and high-level wrappers for Gemma's RESTful API. They enable access to curated expression and d
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/gemma.R/inst/doc/gemma.R.R
// Upstream  : parallel
// Downstream: none
//
// Install: BiocManager::install("gemma.R")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GEMMA_R {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gemma_r"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gemma.r:3.2.1--r44_0' :
        'quay.io/biocontainers/bioconductor-gemma.r:3.2.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gemma_r_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gemma_r_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gemma_r_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(gemma.R)
    library(jsonlite)

    # --- get_datasets_by_ids [] ---
    # Key functions: get_datasets_by_ids
    get_datasets_by_ids("GSE46416") %>%
    # --- get_dataset_object [] ---
    # Key functions: get_dataset_object

    # --- Plot hierarchical clustering heatmap [] ---
    # Key functions: assay, pheatmap, get_dataset_samples, gemma_kable, get_genes
    manicExpr <- assay(manic, "counts")
    pheatmap(col =viridis(10),border_color = NA,angle_col = 45,fontsize = 7)
    get_dataset_samples('GSE46416') %>% make_design('text') %>% select(-factorValues) %>%  head %>%
    # --- Custom ggplot2 visualization [] ---
    # Key functions: arrange, ggplot, aes, geom_point, geom_hline
    de <- get_differential_expression_values("GSE46416",readableContrasts = TRUE)[[1]]
    filter(de, diffexpr == "Up") %>%
    arrange(`contrast_bipolar disorder has_modifier manic phase_pvalue`) %>%
    # --- get_dataset_annotations [] ---
    # Key functions: get_dataset_annotations

    # --- get_dataset_annotations [] ---
    # Key functions: get_dataset_annotations, get_gene_locations


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gemma_r_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gemma_r_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gemma_r_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GEMMA_R:", paste0("    gemma_r: ", packageVersion("gemma.R"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gemma_r_results.csv
    touch ${prefix}_gemma_r_output.rds
    echo "BIOC_GEMMA_R:" > versions.yml
    echo "    gemma_r: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GEMMA_R_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GEMMA_R(ch_input)

    emit:
    results  = BIOC_GEMMA_R.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GEMMA_R.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GEMMA_R.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GEMMA_R.out.versions  // channel: path(versions.yml)
}
