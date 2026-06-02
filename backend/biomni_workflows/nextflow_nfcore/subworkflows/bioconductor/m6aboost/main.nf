#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: m6Aboost
// This package can help user to run the m6Aboost model on their own miCLIP2 data. The package includes
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/m6Aboost/inst/doc/m6AboosVignettes.R
// Upstream  : ExperimentHub
// Downstream: none
//
// Install: BiocManager::install("m6Aboost")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_M6ABOOST {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-m6aboost"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-m6aboost:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-m6aboost:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_m6aboost_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_m6aboost_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_m6aboost_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(m6Aboost)
    library(jsonlite)


    # --- Eval=true [] ---
    # Key functions: events, truncationAssignment, CtoTAssignment, truncation_positive.bw, truncation_negative.bw, C2T_positive.bw, C2T_negative.bw
    ## truncationAssignment allows to assign the number of truncation events
    ## The input should be a GRanges object with the peaks and bigWig files
    ## with the truncation events (separated per strand)
    truncationBw_p <- file.path(testpath, "truncation_positive.bw")
    truncationBw_n <- file.path(testpath, "truncation_negative.bw")

    test <- truncationAssignment(test, 
        bw_positive=truncationBw_p,
        bw_negative=truncationBw_n,
        sampleName = "WT1")

    ## CtoTAssignment allows to assign the number of C-to-T transitions
    ctotBw_p <- file.path(testpath, "C2T_positive.bw")
    ctotBw_n <- file.path(testpath, "C2T_negative.bw")
    # --- Eval=false [] ---
    # Key functions: preparingData
    #  ## E.g. for two replicates, this can be calculated as
    #  peak$WTmean <- (peak$WT1 + peak$WT2)/2

    ## -----------------------------------------------------------------------------
    ## Extract the features for the m6Aboost prediction
    test <- preparingData(test, test_gff3, colname_reads="WTmean", 
        colname_C2T="CtoTmean")
    test

    # --- Warning=false [] ---
    # Key functions: m6Aboost
    ## Note that since the test data set contains only a tiny fraction of the real 
    ## data, and a part of the test data belongs to the training set. Here for 
    ## preventing the unnecessary value change, we set the normalization to FALSE. 
    out <- m6Aboost(test, "BSgenome.Mmusculus.UCSC.mm10", normalization = FALSE)
    out

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_m6aboost_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_m6aboost_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_m6aboost_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_M6ABOOST:", paste0("    m6aboost: ", packageVersion("m6Aboost"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_m6aboost_results.csv
    touch ${prefix}_m6aboost_output.rds
    echo "BIOC_M6ABOOST:" > versions.yml
    echo "    m6aboost: 0.0.0" >> versions.yml
    """
}


workflow BIOC_M6ABOOST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_M6ABOOST(ch_input)

    emit:
    results  = BIOC_M6ABOOST.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_M6ABOOST.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_M6ABOOST.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_M6ABOOST.out.versions  // channel: path(versions.yml)
}
