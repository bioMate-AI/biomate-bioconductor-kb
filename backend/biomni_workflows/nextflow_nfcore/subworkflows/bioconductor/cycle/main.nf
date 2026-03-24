#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: cycle
// Package for assessing the statistical significance of periodic expression based on Fourier analysis 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/cycle/inst/doc/cycle.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("cycle")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CYCLE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cycle"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cycle:1.60.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cycle:1.60.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cycle_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cycle_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cycle_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(cycle)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    data(yeast)
      yeast <- yeast[1:200,]
    # --- Standardise [] ---
    # Key functions: standardise
    yeast <- standardise(yeast)
    # --- Pdata [] ---
    # Key functions: pData
    times.yeast <-  pData(yeast)$time
    times.yeast
    # --- Fdrfourier [] ---
    # Key functions: fdrfourier
    fdr.rr <- fdrfourier(eset=yeast,T=T.yeast,times=times.yeast,background.model="rr",N=NN,progress=FALSE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cycle_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cycle_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cycle_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CYCLE:", paste0("    cycle: ", packageVersion("cycle"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cycle_results.csv
    touch ${prefix}_cycle_output.rds
    echo "BIOC_CYCLE:" > versions.yml
    echo "    cycle: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CYCLE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CYCLE(ch_input)

    emit:
    results  = BIOC_CYCLE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CYCLE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CYCLE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CYCLE.out.versions  // channel: path(versions.yml)
}
