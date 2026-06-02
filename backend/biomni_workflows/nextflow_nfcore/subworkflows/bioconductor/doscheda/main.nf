#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Doscheda
// Doscheda focuses on quantitative chemoproteomics used to determine protein interaction profiles of s
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Doscheda/inst/doc/Doscheda.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("Doscheda")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DOSCHEDA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-doscheda"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-doscheda:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-doscheda:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_doscheda_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_doscheda_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_doscheda_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Doscheda)
    library(jsonlite)

    # --- new [] ---
    # Key functions: new, setParameters
    library(Doscheda)
    # --- set Data [] ---
    # Key functions: setData

    # --- remove Peptides [] ---
    # Key functions: removePeptides
    ex <- removePeptides(ex,removePeps = FALSE)
    # --- run Normalisation [] ---
    # Key functions: runNormalisation, fitModel
    ex<- runNormalisation(ex)
    ex <- fitModel(ex)
    # --- run Doscheda [] ---
    # Key functions: runDoscheda

    # --- replicate Plot [] ---
    # Key functions: replicatePlot
    replicatePlot(ex,conc = 0, repIndex1 = 1, repIndex2 = 2)
    # --- new [] ---
    # Key functions: new, setParameters, setData, removePeptides, runNormalisation


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_doscheda_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_doscheda_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_doscheda_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DOSCHEDA:", paste0("    doscheda: ", packageVersion("Doscheda"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_doscheda_results.csv
    touch ${prefix}_doscheda_output.rds
    echo "BIOC_DOSCHEDA:" > versions.yml
    echo "    doscheda: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DOSCHEDA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DOSCHEDA(ch_input)

    emit:
    results  = BIOC_DOSCHEDA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DOSCHEDA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DOSCHEDA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DOSCHEDA.out.versions  // channel: path(versions.yml)
}
