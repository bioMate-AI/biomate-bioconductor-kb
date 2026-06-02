#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DriverNet
// DriverNet is a package to predict functional important driver genes in cancer by integrating genome 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DriverNet/inst/doc/DriverNet-Overview.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("DriverNet")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DRIVERNET {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-drivernet"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-drivernet:1.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-drivernet:1.46.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_drivernet_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_drivernet_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_drivernet_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DriverNet)
    library(jsonlite)

    # --- Significance Testing [] ---
    # Key functions: computeRandomizedResult
    randomDriversResult <- computeRandomizedResult(
        patMutMatrix = samplePatientMutationMatrix,
        patOutMatrix = samplePatientOutlierMatrix,
        influenceGraph = sampleInfluenceGraph,
        geneNameList = sampleGeneNames,
        outputFolder = NULL,
        printToConsole = FALSE,
        numberOfRandomTests = 20,
        weight = FALSE,
        purturbGraph = FALSE,
        purturbData = TRUE
    )


    # --- Result Summarization [] ---
    # Key functions: resultSummary
    res <- resultSummary(
        driversList,
        randomDriversResult,
        samplePatientMutationMatrix,
        sampleInfluenceGraph,
        outputFolder = NULL,
        printToConsole = FALSE
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_drivernet_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_drivernet_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_drivernet_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DRIVERNET:", paste0("    drivernet: ", packageVersion("DriverNet"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_drivernet_results.csv
    touch ${prefix}_drivernet_output.rds
    echo "BIOC_DRIVERNET:" > versions.yml
    echo "    drivernet: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DRIVERNET_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DRIVERNET(ch_input)

    emit:
    results  = BIOC_DRIVERNET.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DRIVERNET.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DRIVERNET.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DRIVERNET.out.versions  // channel: path(versions.yml)
}
