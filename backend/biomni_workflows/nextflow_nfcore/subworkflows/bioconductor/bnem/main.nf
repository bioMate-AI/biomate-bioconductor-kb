#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: bnem
// bnem combines the use of indirect measurements of Nested Effects Models (package mnem) with the Bool
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/bnem/inst/doc/bnem.R
// Upstream  : CellNOptR, mnem
// Downstream: none
//
// Install: BiocManager::install("bnem")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BNEM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-bnem"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-bnem:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-bnem:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_bnem_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_bnem_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_bnem_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(bnem)
    library(jsonlite)

    # --- Network Inference [] ---
    # Key functions: bnem
    greedy <- bnem(
        search = "greedy",
        fc = fc,
        expression = sim$expression,
        CNOlist = sim$CNOlist,
        model = sim$model,
        parallel = NULL,
        initBstring = NULL,
        draw = FALSE,
        verbose = FALSE,
        maxSteps = Inf,
        method = "s"
    )


    # --- Validation and Visualisation [] ---
    # Key functions: validateGraph
    fitinfo <- validateGraph(
        sim$CNOlist,
        fc = fc,
        expression = sim$expression,
        model = sim$model,
        bString = greedy$bString,
        Sgene = 4,
        Egenes = 1000,
        cexRow = 0.8,
        cexCol = 0.7,
        xrot = 45,
        Colv = TRUE,
        Rowv = TRUE,
        dendrogram = "both"
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_bnem_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_bnem_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_bnem_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BNEM:", paste0("    bnem: ", packageVersion("bnem"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bnem_results.csv
    touch ${prefix}_bnem_output.rds
    echo "BIOC_BNEM:" > versions.yml
    echo "    bnem: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BNEM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BNEM(ch_input)

    emit:
    results  = BIOC_BNEM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BNEM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BNEM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BNEM.out.versions  // channel: path(versions.yml)
}
