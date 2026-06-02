#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: tomoseqr
// `tomoseqr` is an R package for analyzing Tomo-seq data. Tomo-seq is a genome-wide RNA tomography met
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/tomoseqr/inst/doc/tomoseqr.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("tomoseqr")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TOMOSEQR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-tomoseqr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-tomoseqr:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-tomoseqr:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_tomoseqr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_tomoseqr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_tomoseqr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(tomoseqr)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data(testx, testy, testz)
    head(testx)
    # --- estimate3d Expressions [] ---
    # Key functions: estimate3dExpressions
    ---------------------------------------------------------------------
    # --- Findaxialgenes [] ---
    # Key functions: findAxialGenes
    ---------------------------------------------------------------------
    axialGeneTable <- findAxialGenes(testx)
    print(axialGeneTable)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_tomoseqr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_tomoseqr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_tomoseqr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TOMOSEQR:", paste0("    tomoseqr: ", packageVersion("tomoseqr"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tomoseqr_results.csv
    touch ${prefix}_tomoseqr_output.rds
    echo "BIOC_TOMOSEQR:" > versions.yml
    echo "    tomoseqr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TOMOSEQR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TOMOSEQR(ch_input)

    emit:
    results  = BIOC_TOMOSEQR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TOMOSEQR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TOMOSEQR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TOMOSEQR.out.versions  // channel: path(versions.yml)
}
