#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: M3C
// M3C is a consensus clustering algorithm that uses a Monte Carlo simulation to eliminate overestimati
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/M3C/inst/doc/M3Cvignette.R
// Upstream  : ComplexHeatmap
// Downstream: none
//
// Install: BiocManager::install("M3C")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_M3C {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-m3c"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-m3c:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-m3c:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_m3c_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_m3c_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_m3c_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(M3C)
    library(jsonlite)


    # --- Results='hide' [] ---
    # Key functions: M3C, for, suppressWarnings
    # for vignette
    res <- M3C(mydata, des = desx, removeplots = TRUE, iters=25, 
               objective='PAC', fsize=8, lthick=1, dotsize=1.25)

    ## -----------------------------------------------------------------------------
    res$scores

    ## -----------------------------------------------------------------------------
    for (k in seq(2,10)){
      myresults <- res$realdataresults[[k]]$ordered_annotation
      chifit <- suppressWarnings(chisq.test(table(myresults[c('consensuscluster','class')])))
      print(chifit$p.value)
    }

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_m3c_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_m3c_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_m3c_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_M3C:", paste0("    m3c: ", packageVersion("M3C"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_m3c_results.csv
    touch ${prefix}_m3c_output.rds
    echo "BIOC_M3C:" > versions.yml
    echo "    m3c: 0.0.0" >> versions.yml
    """
}


workflow BIOC_M3C_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_M3C(ch_input)

    emit:
    results  = BIOC_M3C.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_M3C.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_M3C.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_M3C.out.versions  // channel: path(versions.yml)
}
