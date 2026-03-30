#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MEIGOR
// MEIGOR provides a comprehensive environment for performing global optimization tasks in bioinformati
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MEIGOR/inst/doc/MEIGOR-vignette.R
// Upstream  : CNORode, CellNOptR
// Downstream: none
//
// Install: BiocManager::install("MEIGOR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MEIGOR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-meigor"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-meigor:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-meigor:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_meigor_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_meigor_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_meigor_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MEIGO)
    library(jsonlite)

    # --- Ex3 analysis [] ---
    # Key functions: ex3, MEIGO, plotCNOlist, plotModel, getLBodeContObjFunction, preprocessing
    problem<-list(f="ex3",x_L=rep(0,6),x_U=c(rep(1,4),16,16),
    opts<-list(ndiverse=10, local_solver='SOLNP', local_tol=3)
    Results<-MEIGO(problem,opts,algorithm="multistart",k1,k2,k3,k4)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_meigor_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_meigor_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_meigor_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MEIGOR:", paste0("    meigor: ", packageVersion("MEIGOR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_meigor_results.csv
    touch ${prefix}_meigor_output.rds
    echo "BIOC_MEIGOR:" > versions.yml
    echo "    meigor: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MEIGOR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MEIGOR(ch_input)

    emit:
    results  = BIOC_MEIGOR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MEIGOR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MEIGOR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MEIGOR.out.versions  // channel: path(versions.yml)
}
