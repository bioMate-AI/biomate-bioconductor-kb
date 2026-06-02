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

    # --- get Treatment [] ---
    # Key functions: getTreatment
    data(demoForTransgenerationalAnalysis)
    The generations are stored in order (first entry = first generation,
    length(demoForTransgenerationalAnalysis)
    # --- run Observation [] ---
    # Key functions: runObservation, loadAllRDSResults
    runObservation(methylKitData = demoForTransgenerationalAnalysis,
    The results can be retrived using loadAllRDSResults() method
    observedResults <- loadAllRDSResults(
    # --- run Permutation [] ---
    # Key functions: runPermutation, loadAllRDSResults
    runPermutation(methylKitData = demoForTransgenerationalAnalysis, # multi-generational dataset
    The results can be retrived using loadAllRDSResults() method
    permutationResults <- loadAllRDSResults(
    # --- merge Permutation And Observation [] ---
    # Key functions: mergePermutationAndObservation
    allResults <- mergePermutationAndObservation(permutationResults =
    # --- extract Info [] ---
    # Key functions: extractInfo
    F1_and_F2_results <- extractInfo(allResults = allResults, type = "sites",
    head(F1_and_F2_results)
    # --- plot Graph [] ---
    # Key functions: plotGraph
    output <- plotGraph(F1_and_F2)
    # --- run Permutation [] ---
    # Key functions: runPermutation
    permutationResult <- runPermutation(
    permutationResult <- runPermutation(
    # --- meth Read [] ---
    # Key functions: methRead
    library(methylKit)
    generation_01 <- methRead(location = list("demo/F1_control_01.txt", "demo/F1_case_01.txt"),
    sample.id = list("F1_control_01", "F1_case_01"),

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
