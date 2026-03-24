#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BUS
// This package can be used to compute associations among genes (gene-networks) or between genes and so
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BUS/inst/doc/bus.R
// Upstream  : minet
// Downstream: none
//
// Install: BiocManager::install("BUS")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BUS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-bus"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-bus:1.62.0--r44_0' :
        'quay.io/biocontainers/bioconductor-bus:1.62.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_bus_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_bus_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_bus_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BUS)
    library(jsonlite)

    # --- Bus [] ---
    # Key functions: packageDescription
    options(keep.source = TRUE, width = 60)
    bus <- packageDescription("BUS")
    # --- B U S [] ---
    # Key functions: BUS
    library(BUS)
    library(minet)
    data(copasi)
    mat=as.matrix(copasi)[1:5,]
    rownames(mat)<-paste("G",1:nrow(mat), sep="")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_bus_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_bus_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_bus_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BUS:", paste0("    bus: ", packageVersion("BUS"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bus_results.csv
    touch ${prefix}_bus_output.rds
    echo "BIOC_BUS:" > versions.yml
    echo "    bus: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BUS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BUS(ch_input)

    emit:
    results  = BIOC_BUS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BUS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BUS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BUS.out.versions  // channel: path(versions.yml)
}
