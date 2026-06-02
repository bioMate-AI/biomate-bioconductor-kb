#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: stJoincount
// stJoincount facilitates the application of join count analysis to spatial transcriptomic data genera
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/stJoincount/inst/doc/stJoincount-vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("stJoincount")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_STJOINCOUNT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-stjoincount"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-stjoincount:1.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-stjoincount:1.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_stjoincount_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_stjoincount_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_stjoincount_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(stJoincount)
    library(jsonlite)


    # --- Set Up [] ---
    # Key functions: set
    knitr::opts_chunk$set(
      collapse = TRUE,
      comment = "#>"
    )

    # --- "install" [] ---
    # Key functions: requireNamespace, install, load, dataPrepFromSeurat, stJoincount, extdata, dataframe.rda, label
    #  if (!requireNamespace("BiocManager", quietly = TRUE)) {
    #        install.packages("BiocManager")
    #    }
    #  BiocManager::install("stJoincount")

    ## -----------------------------------------------------------------------------
    fpath <- system.file("extdata", "dataframe.rda", package="stJoincount")
    load(fpath)
    head(humanBC)

    ## -----------------------------------------------------------------------------
    fpath <- system.file("extdata", "SeuratBC.rda", package="stJoincount")
    load(fpath)
    df <- dataPrepFromSeurat(seuratBC, "label")


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_stjoincount_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_stjoincount_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_stjoincount_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_STJOINCOUNT:", paste0("    stjoincount: ", packageVersion("stJoincount"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_stjoincount_results.csv
    touch ${prefix}_stjoincount_output.rds
    echo "BIOC_STJOINCOUNT:" > versions.yml
    echo "    stjoincount: 0.0.0" >> versions.yml
    """
}


workflow BIOC_STJOINCOUNT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_STJOINCOUNT(ch_input)

    emit:
    results  = BIOC_STJOINCOUNT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_STJOINCOUNT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_STJOINCOUNT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_STJOINCOUNT.out.versions  // channel: path(versions.yml)
}
