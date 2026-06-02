#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: methylInheritance
// Permutation analysis, based on Monte Carlo sampling, for testing the hypothesis that the number of c
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/methylInheritance/inst/doc/methylInheritance.R
// Upstream  : knitr, methylKit
// Downstream: none
//
// Install: BiocManager::install("methylInheritance")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METHYLINHERITANCE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-methylinheritance"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-methylinheritance:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-methylinheritance:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_methylinheritance_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_methylinheritance_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_methylinheritance_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(methylInheritance)
    library(jsonlite)

    # --- Observation Analysis [sites] ---
    # Key functions: runObservation, loadAllRDSResults
    data(demoForTransgenerationalAnalysis)
    runObservation(
        methylKitData = demoForTransgenerationalAnalysis,
        type = "sites",
        outputDir = "demo_01",
        nbrCores = 1,
        minReads = 10,
        minMethDiff = 10,
        qvalue = 0.01,
        vSeed = 2101
    )
    observedResults <- loadAllRDSResults(
        analysisResultsDir = "demo_01/",
        permutationResultsDir = NULL,
        doingSites = TRUE,
        doingTiles = FALSE
    )

    # --- Permutation Analysis [sites] ---
    # Key functions: runPermutation, loadAllRDSResults
    data(demoForTransgenerationalAnalysis)
    runPermutation(
        methylKitData = demoForTransgenerationalAnalysis,
        type = "sites",
        outputDir = "demo_02",
        runObservationAnalysis = FALSE,
        nbrCores = 1,
        nbrPermutations = 2,
        minReads = 10,
        minMethDiff = 10,
        qvalue = 0.01,
        vSeed = 2101
    )
    permutationResults <- loadAllRDSResults(
        analysisResultsDir = NULL,
        permutationResultsDir = "demo_02",
        doingSites = TRUE,
        doingTiles = FALSE
    )

    # --- Merge Results [observation and permutation] ---
    # Key functions: mergePermutationAndObservation
    allResults <- mergePermutationAndObservation(
        permutationResults = permutationResults,
        observationResults = observedResults
    )

    # --- Extract Conserved Sites [multi-generational] ---
    # Key functions: extractInfo
    F1_and_F2 <- extractInfo(
        allResults = allResults,
        type = "sites",
        inter = "i2",
        position = 1
    )
    F2_and_F3 <- extractInfo(
        allResults = allResults,
        type = "sites",
        inter = "i2",
        position = 2
    )
    F1_F2_F3 <- extractInfo(
        allResults = allResults,
        type = "sites",
        inter = "iAll",
        position = 1
    )

    # --- Visualisation [conserved sites] ---
    # Key functions: plotGraph
    output <- plotGraph(F1_and_F2)


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_methylinheritance_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_methylinheritance_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_methylinheritance_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_METHYLINHERITANCE:", paste0("    methylinheritance: ", packageVersion("methylInheritance"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_methylinheritance_results.csv
    touch ${prefix}_methylinheritance_output.rds
    echo "BIOC_METHYLINHERITANCE:" > versions.yml
    echo "    methylinheritance: 0.0.0" >> versions.yml
    """
}


workflow BIOC_METHYLINHERITANCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_METHYLINHERITANCE(ch_input)

    emit:
    results  = BIOC_METHYLINHERITANCE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_METHYLINHERITANCE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_METHYLINHERITANCE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_METHYLINHERITANCE.out.versions  // channel: path(versions.yml)
}
