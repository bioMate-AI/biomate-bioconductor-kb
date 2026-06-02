#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CNORfeeder
// This package integrates literature-constrained and data-driven methods to infer signalling networks 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CNORfeeder/inst/doc/CNORfeeder-vignette.R
// Upstream  : CNORode, CellNOptR, MEIGOR, OmnipathR, doParallel
// Downstream: none
//
// Install: BiocManager::install("CNORfeeder")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CNORFEEDER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cnorfeeder"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cnorfeeder:1.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cnorfeeder:1.46.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cnorfeeder_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cnorfeeder_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cnorfeeder_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CNORfeeder)
    library(jsonlite)

    # --- Feeder Path Identification [] ---
    # Key functions: feederRetrofitting
    feeder_res <- feederRetrofitting(
        CNOlist = CNOlistToy,
        model = ToyModel,
        database = retrofitted_links
    )


    # --- Integrated Model Generation [] ---
    # Key functions: mapBack
    integrated_model <- mapBack(
        model = ToyModel,
        addedLinks = feeder_res
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cnorfeeder_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cnorfeeder_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cnorfeeder_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CNORFEEDER:", paste0("    cnorfeeder: ", packageVersion("CNORfeeder"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cnorfeeder_results.csv
    touch ${prefix}_cnorfeeder_output.rds
    echo "BIOC_CNORFEEDER:" > versions.yml
    echo "    cnorfeeder: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CNORFEEDER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CNORFEEDER(ch_input)

    emit:
    results  = BIOC_CNORFEEDER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CNORFEEDER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CNORFEEDER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CNORFEEDER.out.versions  // channel: path(versions.yml)
}
