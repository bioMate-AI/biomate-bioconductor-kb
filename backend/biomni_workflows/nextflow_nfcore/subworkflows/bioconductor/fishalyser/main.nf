#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: FISHalyseR
// FISHalyseR provides functionality to process and analyse digital cell culture images, in particular 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/FISHalyseR/inst/doc/FISHalyseR.R
// Upstream  : knitr
// Downstream: none
//
// Install: BiocManager::install("FISHalyseR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FISHALYSER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-fishalyser"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-fishalyser:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-fishalyser:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_fishalyser_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_fishalyser_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_fishalyser_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(FISHalyseR)
    library(jsonlite)

    # --- analyse Particles [] ---
    # Key functions: analyseParticles
    fProbes1 = paste(TempDir,'/',"exImgMaxEntropyProbes1.jpg",sep='')
    img = readImage(fProbes1)
    anaImg <- analyseParticles(img, 20, 5,0)
    # --- process F I S H [] ---
    # Key functions: processFISH
    illuCorrection = system.file( "extdata", "SampleFISHillu.jpg", package="FISHalyseR")
    combinedImage <- system.file( "extdata", "SampleFISH.jpg", package="FISHalyseR")
    red_Og   <- system.file( "extdata", "SampleFISH_R.jpg", package="FISHalyseR")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_fishalyser_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_fishalyser_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_fishalyser_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FISHALYSER:", paste0("    fishalyser: ", packageVersion("FISHalyseR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fishalyser_results.csv
    touch ${prefix}_fishalyser_output.rds
    echo "BIOC_FISHALYSER:" > versions.yml
    echo "    fishalyser: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FISHALYSER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FISHALYSER(ch_input)

    emit:
    results  = BIOC_FISHALYSER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FISHALYSER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FISHALYSER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FISHALYSER.out.versions  // channel: path(versions.yml)
}
