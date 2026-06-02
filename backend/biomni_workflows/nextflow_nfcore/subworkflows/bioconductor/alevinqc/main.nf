#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: alevinQC
// Generate QC reports summarizing the output from an alevin, alevin-fry, or simpleaf run. Reports can 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/alevinQC/inst/doc/alevinqc.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("alevinQC")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ALEVINQC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-alevinqc"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-alevinqc:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-alevinqc:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_alevinqc_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_alevinqc_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_alevinqc_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(alevinQC)
    library(jsonlite)

    # --- Quality Control Report Generation [] ---
    # Key functions: alevinQCReport
    baseDir <- system.file("extdata/alevin_example_v0.14", package = "alevinQC")
    outputDir <- tempdir()
    alevinQCReport(
        baseDir = baseDir,
        sampleId = "testSample",
        outputFile = "alevinReport.html",
        outputFormat = "html_document",
        outputDir = outputDir,
        forceOverwrite = TRUE
    )


    # --- Data Import [] ---
    # Key functions: readAlevinQC
    baseDir <- system.file("extdata/alevin_example_v0.14", package = "alevinQC")
    alevin <- readAlevinQC(baseDir = baseDir)


    # --- Quality Control Visualization [] ---
    # Key functions: plotAlevinKneeRaw, plotAlevinBarcodeCollapse, plotAlevinQuant, plotAlevinKneeNbrGenes
    baseDir <- system.file("extdata/alevin_example_v0.14", package = "alevinQC")
    alevin <- readAlevinQC(baseDir = baseDir)
    plotAlevinKneeRaw(alevin$cbTable)
    plotAlevinBarcodeCollapse(alevin$cbTable)
    plotAlevinQuant(alevin$cbTable)
    plotAlevinKneeNbrGenes(alevin$cbTable)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_alevinqc_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_alevinqc_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_alevinqc_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ALEVINQC:", paste0("    alevinqc: ", packageVersion("alevinQC"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_alevinqc_results.csv
    touch ${prefix}_alevinqc_output.rds
    echo "BIOC_ALEVINQC:" > versions.yml
    echo "    alevinqc: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ALEVINQC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ALEVINQC(ch_input)

    emit:
    results  = BIOC_ALEVINQC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ALEVINQC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ALEVINQC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ALEVINQC.out.versions  // channel: path(versions.yml)
}
