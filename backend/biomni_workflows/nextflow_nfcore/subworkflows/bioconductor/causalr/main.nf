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

    # --- Createcg [] ---
    # Key functions: CreateCG
    ---------------------------------------------------------------------
    cg <- CreateCG(system.file( "extdata", "testNetwork1.sif",
        package="CausalR"))
    # --- Plotgraphwithnodenames [] ---
    # Key functions: PlotGraphWithNodeNames
    ---------------------------------------------------------------------
    PlotGraphWithNodeNames(cg)  # producing the following graph.
    # --- Createccg [] ---
    # Key functions: CreateCCG
    ---------------------------------------------------------------------
    ccg <- CreateCCG(system.file( "extdata", "testNetwork1.sif",
        package="CausalR"))
    # --- Plotgraphwithnodenames [] ---
    # Key functions: PlotGraphWithNodeNames
    ---------------------------------------------------------------------
    PlotGraphWithNodeNames(ccg) # producing the following graph.
    # --- Readexperimentaldata [] ---
    # Key functions: ReadExperimentalData
    ---------------------------------------------------------------------
    experimentalData <- ReadExperimentalData(system.file( "extdata",
                            "testData1.txt", package="CausalR"),ccg)
    # --- Rankthehypotheses [] ---
    # Key functions: RankTheHypotheses
    -------------------------------------------------------------------------------------------------------------
    options(width=120)
    RankTheHypotheses(ccg, experimentalData, delta=2)
    # --- Makepredictionsfromccg [] ---
    # Key functions: MakePredictionsFromCCG
    -------------------------------------------------------------------------------------------------------------
    predictions <- MakePredictionsFromCCG('Node0',+1,ccg,2)
    predictions
    # --- Scorehypothesis [] ---
    # Key functions: ScoreHypothesis
    -------------------------------------------------------------------------------------------------------------
    ScoreHypothesis(predictions, experimentalData)
    # --- Getnodename [] ---
    # Key functions: GetNodeName, CompareHypothesis
    -------------------------------------------------------------------------------------------------------------
    GetNodeName(ccg,CompareHypothesis(predictions, experimentalData))
    # --- Rankthehypotheses [] ---
    # Key functions: RankTheHypotheses
    -------------------------------------------------------------------------------------------------------------
    options(width=120)
    Rankfor4<-RankTheHypotheses(ccg, experimentalData, 2,
                                correctPredictionsThreshold=4)
    Rankfor4   # For example output only
    # --- Runscanr [] ---
    # Key functions: runSCANR
    -------------------------------------------------------------------------------------------------------------
    runSCANR(ccg, experimentalData, numberOfDeltaToScan=2, topNumGenes=4,
             correctPredictionsThreshold=1,writeResultFiles = TRUE,
             writeNetworkFiles = "none",quiet=TRUE)
    # --- Runscanr [] ---
    # Key functions: runSCANR, WriteAllExplainedNodesToSifFile
    -------------------------------------------------------------------------------------------------------------
    scanResults <- runSCANR(ccg, experimentalData, numberOfDeltaToScan=2,
      topNumGenes=4,correctPredictionsThreshold=1,
      writeResultFiles = FALSE, writeNetworkFiles = "none",quiet=FALSE)

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
