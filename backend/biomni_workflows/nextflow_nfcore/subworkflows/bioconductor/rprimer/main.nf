#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: rprimer
// Functions, workflow, and a Shiny application for visualizing sequence conservation and designing deg
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/rprimer/inst/doc/getting-started-with-rprimer.R
// Upstream  : kableExtra
// Downstream: none
//
// Install: BiocManager::install("rprimer")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RPRIMER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rprimer"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rprimer:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rprimer:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rprimer_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rprimer_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rprimer_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(rprimer)
    library(jsonlite)


    # --- Include = False [] ---
    # Key functions: set
    knitr::opts_chunk$set(
      collapse = TRUE,
      comment = "#>"
    )

    # --- Warning=false [] ---
    # Key functions: readDNAMultipleAlignment, colmask, extdata, example_alignment.txt, rprimer, fasta
    library(rprimer)
    library(Biostrings)

    ## -----------------------------------------------------------------------------
    filepath <- system.file("extdata", "example_alignment.txt", package = "rprimer")

    myAlignment <- readDNAMultipleAlignment(filepath, format = "fasta")

    ## -----------------------------------------------------------------------------
    ## Mask everything but position 3000 to 4000 and 5000 to 6000
    myMaskedAlignment <- myAlignment

    colmask(myMaskedAlignment, invert = TRUE) <- c(3000:4000, 5000:6000)

    ## -----------------------------------------------------------------------------

    # --- Fig 3 [] ---
    # Key functions: plotData
    plotData(myConsensusProfile, highlight = c(from, to))

    ## -----------------------------------------------------------------------------
    myAssayRegion <- myConsensusProfile[
      myConsensusProfile$position >= from & 
        myConsensusProfile$position <= to, 
    ]

    # --- Warning=false [] ---
    # Key functions: sessionInfo, exampleRprimerProfile, exampleRprimerOligo, exampleRprimerAssay, exampleRprimerMatchOligo, exampleRprimerMatchAssay
    data("exampleRprimerProfile")
    data("exampleRprimerOligo")
    data("exampleRprimerAssay")
    data("exampleRprimerMatchOligo")
    data("exampleRprimerMatchAssay")

    ## -----------------------------------------------------------------------------
    sessionInfo()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rprimer_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rprimer_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rprimer_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RPRIMER:", paste0("    rprimer: ", packageVersion("rprimer"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rprimer_results.csv
    touch ${prefix}_rprimer_output.rds
    echo "BIOC_RPRIMER:" > versions.yml
    echo "    rprimer: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RPRIMER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RPRIMER(ch_input)

    emit:
    results  = BIOC_RPRIMER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RPRIMER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RPRIMER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RPRIMER.out.versions  // channel: path(versions.yml)
}
