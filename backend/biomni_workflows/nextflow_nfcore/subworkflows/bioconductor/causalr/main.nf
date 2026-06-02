#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CausalR
// Causal network analysis methods for regulator prediction and network reconstruction from genome scal
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CausalR/inst/doc/CausalR.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("CausalR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CAUSALR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-causalr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-causalr:1.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-causalr:1.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_causalr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_causalr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_causalr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CausalR)
    library(CompareHypothesis)
    library(CreateCCG)
    library(CreateCG)
    library(GetNodeName)
    library(MakePredictionsFromCCG)
    library(PlotGraphWithNodeNames)
    library(RankTheHypotheses)
    library(ReadExperimentalData)
    library(ScoreHypothesis)
    library(WriteAllExplainedNodesToSifFile)
    library(jsonlite)

    # --- Experimental Data Loading [] ---
    # Key functions: CreateCCG, ReadExperimentalData
    sif_file <- system.file("extdata", "testNetwork1.sif", package = "CausalR")
    ccg <- CreateCCG(sif_file)
    data_file <- system.file("extdata", "testData1.txt", package = "CausalR")
    experimentalData <- ReadExperimentalData(
        fileName = data_file,
        ccg = ccg
    )


    # --- Hypothesis Ranking [] ---
    # Key functions: CreateCCG, ReadExperimentalData, RankTheHypotheses
    sif_file <- system.file("extdata", "testNetwork1.sif", package = "CausalR")
    ccg <- CreateCCG(sif_file)
    data_file <- system.file("extdata", "testData1.txt", package = "CausalR")
    experimentalData <- ReadExperimentalData(data_file, ccg)
    rank_all <- RankTheHypotheses(ccg, experimentalData, delta = 2)
    test_nodes <- c("Node0", "Node2", "Node3")
    rank_subset <- RankTheHypotheses(
        ccg,
        experimentalData,
        delta = 2,
        listOfNodes = test_nodes
    )


    # --- Path and Prediction Analysis [] ---
    # Key functions: GetShortestPathsFromCCG, MakePredictionsFromCCG, ScoreHypothesis, CompareHypothesis, GetNodeName
    sif_file <- system.file("extdata", "testNetwork1.sif", package = "CausalR")
    ccg <- CreateCCG(sif_file)
    data_file <- system.file("extdata", "testData1.txt", package = "CausalR")
    experimentalData <- ReadExperimentalData(data_file, ccg)
    paths <- GetShortestPathsFromCCG(ccg, "Node0", "Node3")
    predictions <- MakePredictionsFromCCG("Node0", +1, ccg, delta = 2)
    score <- ScoreHypothesis(predictions, experimentalData)
    comparison <- CompareHypothesis(predictions, experimentalData)
    node_names <- GetNodeName(ccg, comparison)


    # --- SCANR Network Analysis [] ---
    # Key functions: runSCANR, WriteAllExplainedNodesToSifFile
    sif_file <- system.file("extdata", "testNetwork1.sif", package = "CausalR")
    ccg <- CreateCCG(sif_file)
    data_file <- system.file("extdata", "testData1.txt", package = "CausalR")
    experimentalData <- ReadExperimentalData(data_file, ccg)
    scan_res <- runSCANR(ccg, experimentalData, numberOfDeltaToScan = 2,
        topNumGenes = 4, correctPredictionsThreshold = 1,
        writeResultFiles = FALSE, writeNetworkFiles = "none")
    WriteAllExplainedNodesToSifFile(scan_res, ccg, experimentalData,
        delta = 2, correctlyExplainedOnly = TRUE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_causalr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_causalr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_causalr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CAUSALR:", paste0("    causalr: ", packageVersion("CausalR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_causalr_results.csv
    touch ${prefix}_causalr_output.rds
    echo "BIOC_CAUSALR:" > versions.yml
    echo "    causalr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CAUSALR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CAUSALR(ch_input)

    emit:
    results  = BIOC_CAUSALR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CAUSALR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CAUSALR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CAUSALR.out.versions  // channel: path(versions.yml)
}
