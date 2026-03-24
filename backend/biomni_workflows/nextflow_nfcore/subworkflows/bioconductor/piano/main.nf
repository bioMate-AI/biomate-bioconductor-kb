#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: piano
// Piano performs gene set analysis using various statistical methods, from different gene level statis
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/piano/inst/doc/Running_gene-set_analysis_with_piano.R
// Upstream  : biomaRt
// Downstream: none
//
// Install: BiocManager::install("piano")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PIANO {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-piano"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-piano:2.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-piano:2.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_piano_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_piano_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_piano_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(piano)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    library(piano)
    data("gsa_input")
    # --- Loadgsc [] ---
    # Key functions: loadGSC
    ---------------------------------------------------------------------
    geneSets <- loadGSC(gsa_input$gsc)
    geneSets

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_piano_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_piano_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_piano_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PIANO:", paste0("    piano: ", packageVersion("piano"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_piano_results.csv
    touch ${prefix}_piano_output.rds
    echo "BIOC_PIANO:" > versions.yml
    echo "    piano: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PIANO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PIANO(ch_input)

    emit:
    results  = BIOC_PIANO.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PIANO.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PIANO.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PIANO.out.versions  // channel: path(versions.yml)
}
