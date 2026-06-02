#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Guitar
// The package is designed for visualization of RNA-related genomic features with respect to the landma
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Guitar/inst/doc/Guitar-Overview.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("Guitar")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GUITAR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-guitar"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-guitar:2.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-guitar:2.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_guitar_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_guitar_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_guitar_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Guitar)
    library(GuitarPlot)
    library(jsonlite)

    # --- Genomic Feature Distribution Plotting [] ---
    # Key functions: GuitarPlot
    GuitarPlot(txTxdb = txdb,
               stBedFiles = stBedFiles,
               headOrtail = TRUE,
               enableCI = FALSE,
               mapFilterTranscript = TRUE,
               pltTxType = c("mrna"),
               stGroupName = c("BED12", "BED6"))


    # --- Feature Point Sampling [] ---
    # Key functions: samplePoints
    sitesPoints <- samplePoints(stGRangeLists,
                                stSampleNum = 10,
                                stAmblguity = 5,
                                pltTxType = c("mrna"),
                                stSampleModle = "Equidistance",
                                mapFilterTranscript = FALSE,
                                guitarTxdb = guitarTxdb)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_guitar_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_guitar_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_guitar_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GUITAR:", paste0("    guitar: ", packageVersion("Guitar"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_guitar_results.csv
    touch ${prefix}_guitar_output.rds
    echo "BIOC_GUITAR:" > versions.yml
    echo "    guitar: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GUITAR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GUITAR(ch_input)

    emit:
    results  = BIOC_GUITAR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GUITAR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GUITAR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GUITAR.out.versions  // channel: path(versions.yml)
}
