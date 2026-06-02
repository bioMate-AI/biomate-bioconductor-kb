#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MOGAMUN
// MOGAMUN is a multi-objective genetic algorithm that identifies active modules in a multiplex biologi
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MOGAMUN/inst/doc/MOGAMUN_Vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("MOGAMUN")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MOGAMUN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mogamun"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mogamun:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mogamun:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mogamun_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mogamun_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mogamun_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MOGAMUN)
    library(jsonlite)

    # --- mogamun_init [] ---
    # Key functions: mogamun_init
    parameters <- mogamun_init(Generations = 1, PopSize = 10)
    # --- mogamun_load_data [] ---
    # Key functions: mogamun_load_data
    dePath <- system.file("extdata/DE/Sample_DE.csv", package = "MOGAMUN")
    system.file("extdata/DE/Sample_NodesScore.csv", package = "MOGAMUN")
    paste0(system.file("extdata/LayersMultiplex", package = "MOGAMUN"), "/")
    # --- mogamun_run [] ---
    # Key functions: mogamun_run
    mogamun_run(LoadedData = loadedData, ResultsDir = '.')
    # --- mogamun_postprocess [] ---
    # Key functions: mogamun_postprocess


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mogamun_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mogamun_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mogamun_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MOGAMUN:", paste0("    mogamun: ", packageVersion("MOGAMUN"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mogamun_results.csv
    touch ${prefix}_mogamun_output.rds
    echo "BIOC_MOGAMUN:" > versions.yml
    echo "    mogamun: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MOGAMUN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MOGAMUN(ch_input)

    emit:
    results  = BIOC_MOGAMUN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MOGAMUN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MOGAMUN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MOGAMUN.out.versions  // channel: path(versions.yml)
}
