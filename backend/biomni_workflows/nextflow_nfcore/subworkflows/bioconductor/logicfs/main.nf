#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: logicFS
// Identification of interactions between binary variables using Logic Regression. Can, e.g., be used t
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/logicFS/inst/doc/logicFS.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("logicFS")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_LOGICFS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-logicfs"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-logicfs:2.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-logicfs:2.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_logicfs_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_logicfs_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_logicfs_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(logicFS)
    library(jsonlite)

    # --- Dummy [] ---
    # Key functions: dummy
    bin.snps <- make.snp.dummy(data.logicfs)
    # --- Control [] ---
    # Key functions: control
    my.anneal <- logreg.anneal.control(start = 2, end = -2, iter = 10000)
    # --- Logicfs [] ---
    # Key functions: logicFS
    log.out <- logicFS(bin.snps, cl.logicfs, B = 20, nleaves = 10,
       rand = 1234, anneal.control = my.anneal)
    # --- Bagging [] ---
    # Key functions: bagging
    bag.out <- logic.bagging(bin.snps, cl.logicfs, B = 20, nleaves = 10,
       rand = 1234, anneal.control = my.anneal)
    bag.out
    # --- Predict [] ---
    # Key functions: predict
    cl.preds <- predict(bag.out, bin.snps)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_logicfs_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_logicfs_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_logicfs_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_LOGICFS:", paste0("    logicfs: ", packageVersion("logicFS"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_logicfs_results.csv
    touch ${prefix}_logicfs_output.rds
    echo "BIOC_LOGICFS:" > versions.yml
    echo "    logicfs: 0.0.0" >> versions.yml
    """
}


workflow BIOC_LOGICFS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_LOGICFS(ch_input)

    emit:
    results  = BIOC_LOGICFS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_LOGICFS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_LOGICFS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_LOGICFS.out.versions  // channel: path(versions.yml)
}
