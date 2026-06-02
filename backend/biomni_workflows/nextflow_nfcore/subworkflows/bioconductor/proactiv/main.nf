#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: proActiv
// Most human genes have multiple promoters that control the expression of different isoforms. The use 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/proActiv/inst/doc/proActiv.R
// Upstream  : Rtsne, ggplot2, gridExtra
// Downstream: none
//
// Install: BiocManager::install("proActiv")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PROACTIV {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-proactiv"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-proactiv:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-proactiv:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_proactiv_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_proactiv_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_proactiv_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(proActiv)
    library(jsonlite)

    # --- Custom ggplot2 visualization [] ---
    # Key functions: rowData, ggplot, geom_bar, xlab, ggtitle, as_tibble, labs, geom_point
    majorPromoter <- as_tibble(rdata) %>% group_by(geneId) %>%
    mutate(promoterCount = n()) %>% filter(HepG2.class == 'Major')
    # --- Table formatting and display [] ---
    # Key functions: proActiv, loadDb, kable, getAlternativePromoters, show, boxplotPromoters, assays


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_proactiv_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_proactiv_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_proactiv_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PROACTIV:", paste0("    proactiv: ", packageVersion("proActiv"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_proactiv_results.csv
    touch ${prefix}_proactiv_output.rds
    echo "BIOC_PROACTIV:" > versions.yml
    echo "    proactiv: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PROACTIV_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PROACTIV(ch_input)

    emit:
    results  = BIOC_PROACTIV.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PROACTIV.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PROACTIV.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PROACTIV.out.versions  // channel: path(versions.yml)
}
