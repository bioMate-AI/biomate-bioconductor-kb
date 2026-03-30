#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MassSpecWavelet
// Peak Detection in Mass Spectrometry data is one of the important preprocessing steps. The performanc
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MassSpecWavelet/inst/doc/FindingLocalMaxima.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("MassSpecWavelet")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MASSSPECWAVELET {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-massspecwavelet"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-massspecwavelet:1.72.1--r44_0' :
        'quay.io/biocontainers/bioconductor-massspecwavelet:1.72.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_massspecwavelet_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_massspecwavelet_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_massspecwavelet_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MassSpecWavelet)
    library(jsonlite)

    # --- mark [] ---
    # Key functions: mark, localMaximum
    set.seed(5413L)
    winSizes <- c(5, 31, 301)
    xlengths <- c(20, 200, 2000, 20000, 200000)
    # --- plot Local Max [] ---
    # Key functions: plotLocalMax
    par(mfrow = c(2,1))
    plotLocalMax(localMax_classic, NULL, range=c(plotRange[1], plotRange[2]), main = "classic")
    plotLocalMax(localMax_new, NULL, range=c(plotRange[1], plotRange[2]), main = "new")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_massspecwavelet_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_massspecwavelet_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_massspecwavelet_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MASSSPECWAVELET:", paste0("    massspecwavelet: ", packageVersion("MassSpecWavelet"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_massspecwavelet_results.csv
    touch ${prefix}_massspecwavelet_output.rds
    echo "BIOC_MASSSPECWAVELET:" > versions.yml
    echo "    massspecwavelet: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MASSSPECWAVELET_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MASSSPECWAVELET(ch_input)

    emit:
    results  = BIOC_MASSSPECWAVELET.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MASSSPECWAVELET.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MASSSPECWAVELET.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MASSSPECWAVELET.out.versions  // channel: path(versions.yml)
}
