#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: hummingbird
// A package for detecting differential methylation. It exploits a Bayesian hidden Markov model that in
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/hummingbird/inst/doc/hummingbird.R
// Upstream  : GenomicRanges, SummarizedExperiment
// Downstream: none
//
// Install: BiocManager::install("hummingbird")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HUMMINGBIRD {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-hummingbird"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-hummingbird:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-hummingbird:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_hummingbird_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_hummingbird_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_hummingbird_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(hummingbird)
    library(SummarizedExperiment)
    library(jsonlite)

    # --- Data Preparation [SummarizedExperiment] ---
    # Key functions: SummarizedExperiment, GPos
    pos_vec <- pos[, 1]
    assaysControl <- list(normM = normM, normUM = normUM)
    assaysCase <- list(abnormM = abnormM, abnormUM = abnormUM)
    exampleSEControl <- SummarizedExperiment(
        assays = assaysControl, 
        rowRanges = GPos("chr29", pos_vec)
    )
    exampleSECase <- SummarizedExperiment(
        assays = assaysCase, 
        rowRanges = GPos("chr29", pos_vec)
    )

    # --- Expectation-Maximization Estimation [EM Algorithm] ---
    # Key functions: hummingbirdEM
    emInfo <- hummingbirdEM(
        experimentInfoControl = exampleSEControl, 
        experimentInfoCase = exampleSECase, 
        binSize = 40
    )

    # --- DMR Detection and Post-Adjustment [Post-processing] ---
    # Key functions: hummingbirdPostAdjustment
    postAdjInfo <- hummingbirdPostAdjustment(
        experimentInfoControl = exampleSEControl, 
        experimentInfoCase = exampleSECase, 
        emInfo = emInfo, 
        minCpGs = 10, 
        minLength = 100, 
        maxGap = 300
    )
    dmrs <- postAdjInfo$DMRs

    # --- Visualization of Methylation Profiles [Visualisation] ---
    # Key functions: hummingbirdGraph
    hummingbirdGraph(
        experimentInfoControl = exampleSEControl, 
        experimentInfoCase = exampleSECase, 
        postAdjInfoDMRs = postAdjInfo$DMRs, 
        coord1 = 107991, 
        coord2 = 108350
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_hummingbird_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_hummingbird_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_hummingbird_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HUMMINGBIRD:", paste0("    hummingbird: ", packageVersion("hummingbird"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hummingbird_results.csv
    touch ${prefix}_hummingbird_output.rds
    echo "BIOC_HUMMINGBIRD:" > versions.yml
    echo "    hummingbird: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HUMMINGBIRD_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HUMMINGBIRD(ch_input)

    emit:
    results  = BIOC_HUMMINGBIRD.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HUMMINGBIRD.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HUMMINGBIRD.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HUMMINGBIRD.out.versions  // channel: path(versions.yml)
}
