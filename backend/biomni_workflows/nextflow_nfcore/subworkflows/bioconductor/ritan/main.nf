#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RITAN
// Tools for comprehensive gene set enrichment and extraction of multi-resource high confidence subnetw
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RITAN/inst/doc/choosing_resources.R
// Upstream  : RITANdata, knitr
// Downstream: none
//
// Install: BiocManager::install("RITAN")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RITAN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ritan"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ritan:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ritan:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ritan_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ritan_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ritan_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RITAN)
    library(jsonlite)

    # --- kable [] ---
    # Key functions: kable
    library(RITANdata)
    library(RITAN)
    library(knitr)
    # --- geneset overlap P [] ---
    # Key functions: network_overlap
    e <- network_overlap( genes, resources = c('CCSB','STRING'), minStringScore = 700 )
    # --- geneset overlap M [] ---
    # Key functions: network_overlap
    e2 <- network_overlap( genes, resources = c('PID','HumanNet') )
    # --- geneset overlap E [] ---
    # Key functions: network_overlap
    e2 <- network_overlap( genes, resources = c('ChEA','HumanNet') )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ritan_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ritan_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ritan_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RITAN:", paste0("    ritan: ", packageVersion("RITAN"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ritan_results.csv
    touch ${prefix}_ritan_output.rds
    echo "BIOC_RITAN:" > versions.yml
    echo "    ritan: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RITAN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RITAN(ch_input)

    emit:
    results  = BIOC_RITAN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RITAN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RITAN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RITAN.out.versions  // channel: path(versions.yml)
}
