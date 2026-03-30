#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ternarynet
// Gene-regulatory network (GRN) modeling seeks to infer dependencies between genes and thereby provide
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ternarynet/inst/doc/ternarynet.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("ternarynet")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TERNARYNET {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ternarynet"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ternarynet:1.50.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ternarynet:1.50.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ternarynet_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ternarynet_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ternarynet_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ternarynet)
    library(jsonlite)

    # --- Integer [] ---
    # Key functions: frame, parallelFit
    library(ternarynet)
    i_exp <- as.integer(c(0,0,0, 0,0,0, 0,0,0, 0,0,0,
                            1,1,1, 1,1,1, 1,1,1, 1,1,1,
                            2,2,2, 2,2,2, 2,2,2, 2,2,2,
                            3,3,3, 3,3,3, 3,3,3, 3,3,3,
    # --- Parallelfit [] ---
    # Key functions: parallelFit
    results <- parallelFit(indata,
                            max_parents=1,
                            n_cycles=10,
                            n_write=10,
                            T_lo=0.001,

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ternarynet_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ternarynet_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ternarynet_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TERNARYNET:", paste0("    ternarynet: ", packageVersion("ternarynet"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ternarynet_results.csv
    touch ${prefix}_ternarynet_output.rds
    echo "BIOC_TERNARYNET:" > versions.yml
    echo "    ternarynet: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TERNARYNET_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TERNARYNET(ch_input)

    emit:
    results  = BIOC_TERNARYNET.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TERNARYNET.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TERNARYNET.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TERNARYNET.out.versions  // channel: path(versions.yml)
}
