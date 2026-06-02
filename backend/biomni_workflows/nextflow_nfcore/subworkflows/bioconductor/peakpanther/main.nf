#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: peakPantheR
// An automated pipeline for the detection, integration and reporting of predefined features across a l
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/peakPantheR/inst/doc/getting-started.R
// Upstream  : BiocStyle, devtools, doParallel, faahKO, foreach
// Downstream: none
//
// Install: BiocManager::install("peakPantheR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PEAKPANTHER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-peakpanther"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-peakpanther:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-peakpanther:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_peakpanther_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_peakpanther_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_peakpanther_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(peakPantheR)
    library(jsonlite)


    # --- Biocstyle [] ---
    # Key functions: markdown
    BiocStyle::markdown()

    # --- Eval = False [] ---
    # Key functions: requireNamespace, install, faahKO
    #  if (!requireNamespace("BiocManager", quietly = TRUE))
    #      install.packages("BiocManager")
    #  
    #  BiocManager::install("faahKO")

    ## -----------------------------------------------------------------------------
    library(faahKO)
    ## file paths
    input_spectraPaths  <- c(system.file('cdf/KO/ko15.CDF', package = "faahKO"),
                            system.file('cdf/KO/ko16.CDF', package = "faahKO"),
                            system.file('cdf/KO/ko18.CDF', package = "faahKO"))
    input_spectraPaths

    # --- Results = "asis" [] ---
    # Key functions: vector, pandoc.table, cpdID, cpdName, rtMin, rtMax, mzMin, mzMax
    # use pandoc for improved readability
    input_targetFeatTable <- data.frame(matrix(vector(), 2, 8, dimnames=list(c(), 
                            c("cpdID", "cpdName", "rtMin", "rt", "rtMax", "mzMin", 
                            "mz", "mzMax"))), stringsAsFactors=FALSE)
    input_targetFeatTable[1,] <- c("ID-1", "Cpd 1", 3310., 3344.888, 3390., 522.194778, 
                                    522.2, 522.205222)
    input_targetFeatTable[2,] <- c("ID-2", "Cpd 2", 3280., 3385.577, 3440., 496.195038,
                                    496.2, 496.204962)
    input_targetFeatTable[,c(1,3:8)] <- sapply(input_targetFeatTable[,c(1,3:8)], 
                                                as.numeric)
    rownames(input_targetFeatTable) <- NULL
    pander::pandoc.table(input_targetFeatTable, digits = 9)

    # --- Results = "asis" [] ---
    # Key functions: vector, pandoc.table, cpdID, cpdName, rtMin, rtMax, mzMin, mzMax
    # use pandoc for improved readability
    input_targetFeatTable <- data.frame(matrix(vector(), 2, 8, dimnames=list(c(),
                            c("cpdID", "cpdName", "rtMin", "rt", "rtMax", "mzMin",
                            "mz", "mzMax"))), stringsAsFactors=FALSE)
    input_targetFeatTable[1,] <- c("ID-1", "Cpd 1", 3310., 3344.888, 3390.,
                                    522.194778, 522.2, 522.205222)
    input_targetFeatTable[2,] <- c("ID-2", "Cpd 2", 3280., 3385.577, 3440.,
                                    496.195038, 496.2, 496.204962)
    input_targetFeatTable[,3:8] <- sapply(input_targetFeatTable[,3:8], as.numeric)
    rownames(input_targetFeatTable) <- NULL
    pander::pandoc.table(input_targetFeatTable, digits = 9)

    # --- Results = "asis" [] ---
    # Key functions: vector, pandoc.table, filepath, testcol1, testcol2, faahKO
    # use pandoc for improved readability
    input_spectraMeta <- data.frame(matrix(vector(), 3, 3,
                            dimnames=list(c(),c("filepath","testcol1","testcol2"))),
                            stringsAsFactors=FALSE)
    input_spectraMeta[1,] <- c(system.file('cdf/KO/ko15.CDF', package = "faahKO"),
                                "c", 3)
    input_spectraMeta[2,] <- c(system.file('cdf/KO/ko16.CDF', package = "faahKO"),
                                "d", 4)
    input_spectraMeta[3,] <- c(system.file('cdf/KO/ko18.CDF', package = "faahKO"),
                                "e", 5)
    rownames(input_spectraMeta) <- NULL
    pander::pandoc.table(input_spectraMeta, digits = 0)

    # --- Results = "asis" [] ---
    # Key functions: vector, pandoc.table, testcol1, testcol2
    # use pandoc for improved readability
    input_featMeta <- data.frame(matrix(vector(), 2, 2,
                        dimnames=list(c(),c("testcol1","testcol2"))),
                        stringsAsFactors=FALSE)
    input_featMeta[1,] <- c("a", 1)
    input_featMeta[2,] <- c("b", 2)
    rownames(input_featMeta) <- NULL
    pander::pandoc.table(input_featMeta, digits = 0)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_peakpanther_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_peakpanther_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_peakpanther_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PEAKPANTHER:", paste0("    peakpanther: ", packageVersion("peakPantheR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_peakpanther_results.csv
    touch ${prefix}_peakpanther_output.rds
    echo "BIOC_PEAKPANTHER:" > versions.yml
    echo "    peakpanther: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PEAKPANTHER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PEAKPANTHER(ch_input)

    emit:
    results  = BIOC_PEAKPANTHER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PEAKPANTHER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PEAKPANTHER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PEAKPANTHER.out.versions  // channel: path(versions.yml)
}
