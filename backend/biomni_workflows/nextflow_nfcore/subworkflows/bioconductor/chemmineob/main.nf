#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ChemmineOB
// ChemmineOB provides an R interface to a subset of cheminformatics functionalities implemented by the
//
// Source : https://bioconductor.org/packages/3.20/bioc/https://bioconductor.org/packages/3.20/bioc/vignettes/ChemmineOB/inst/doc/ChemmineOB.html
// Upstream  : ChemmineR
// Downstream: none
//
// Install: BiocManager::install("ChemmineOB")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CHEMMINEOB {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-chemmineob"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-chemmineob:1.44.0--r44_0' :
        'quay.io/biocontainers/bioconductor-chemmineob:1.44.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_chemmineob_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_chemmineob_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_chemmineob_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(OBDescriptor_GetStringValue)
    library(jsonlite)

    # --- Code Block 1 [] ---
    # Key functions: requireNamespace, packages
    if (!requireNamespace("BiocManager", quietly=TRUE))
        install.packages("BiocManager")
    BiocManager::install(c("ChemmineR", "ChemmineOB"))
    library("ChemmineR")
    library("ChemmineOB")
    # --- Code Block 3 [] ---
    # Key functions: stringp, OBDescriptor_GetStringValue, cast, value
    result = stringp()
    OBDescriptor_GetStringValue(... , result$cast())
    stringValue = result$value()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_chemmineob_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_chemmineob_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_chemmineob_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CHEMMINEOB:", paste0("    chemmineob: ", packageVersion("ChemmineOB"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chemmineob_results.csv
    touch ${prefix}_chemmineob_output.rds
    echo "BIOC_CHEMMINEOB:" > versions.yml
    echo "    chemmineob: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CHEMMINEOB_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CHEMMINEOB(ch_input)

    emit:
    results  = BIOC_CHEMMINEOB.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CHEMMINEOB.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CHEMMINEOB.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CHEMMINEOB.out.versions  // channel: path(versions.yml)
}
