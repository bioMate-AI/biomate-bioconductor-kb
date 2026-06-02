#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: decoupleR
// Many methods allow us to extract biological activities from omics data using information from prior 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/decoupleR/inst/doc/decoupleR.R
// Upstream  : RefManageR, Seurat, dplyr, ggplot2, ggrepel
// Downstream: none
//
// Install: BiocManager::install("decoupleR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DECOUPLER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-decoupler"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-decoupler:2.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-decoupler:2.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_decoupler_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_decoupler_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_decoupler_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(PrintBibliography)
    library(jsonlite)

    # --- Plot hierarchical clustering heatmap [] ---
    # Key functions: pheatmap, pivot_wider_profile
    filter(statistic=='consensus') %>%
    # --- Toy data analysis [] ---
    # Key functions: get_toy_data, run_fgsea, run_ulm, decouple, PrintBibliography
    res_gsea <- run_fgsea(mat, network, .source='source', .target='target', nproc=1, minsize = 0)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_decoupler_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_decoupler_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_decoupler_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DECOUPLER:", paste0("    decoupler: ", packageVersion("decoupleR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_decoupler_results.csv
    touch ${prefix}_decoupler_output.rds
    echo "BIOC_DECOUPLER:" > versions.yml
    echo "    decoupler: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DECOUPLER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DECOUPLER(ch_input)

    emit:
    results  = BIOC_DECOUPLER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DECOUPLER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DECOUPLER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DECOUPLER.out.versions  // channel: path(versions.yml)
}
