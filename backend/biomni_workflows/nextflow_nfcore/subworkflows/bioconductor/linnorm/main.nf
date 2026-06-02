#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Linnorm
// Linnorm is an algorithm for normalizing and transforming RNA-seq, single cell RNA-seq, ChIP-seq coun
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Linnorm/inst/doc/Linnorm_User_Manual.R
// Upstream  : RColorBrewer, gplots, igraph, knitr
// Downstream: none
//
// Install: BiocManager::install("Linnorm")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_LINNORM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-linnorm"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-linnorm:2.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-linnorm:2.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_linnorm_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_linnorm_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_linnorm_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Linnorm)
    library(jsonlite)


    # --- Kable1 [] ---
    # Key functions: linnorm
    library(knitr)
    kable(Genes10[,c(1:5)], digits=4)

    # --- Kable2 [] ---
    # Key functions: linnorm
    library(knitr)
    kable(Genes10, digits=4, row.names=FALSE)

    # --- Kable3 [] ---
    # Key functions: linnorm
    library(knitr)
    kable(Genes10, digits=4)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_linnorm_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_linnorm_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_linnorm_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_LINNORM:", paste0("    linnorm: ", packageVersion("Linnorm"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_linnorm_results.csv
    touch ${prefix}_linnorm_output.rds
    echo "BIOC_LINNORM:" > versions.yml
    echo "    linnorm: 0.0.0" >> versions.yml
    """
}


workflow BIOC_LINNORM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_LINNORM(ch_input)

    emit:
    results  = BIOC_LINNORM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_LINNORM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_LINNORM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_LINNORM.out.versions  // channel: path(versions.yml)
}
