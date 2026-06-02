#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SigCheck
// While gene signatures are frequently used to predict phenotypes (e.g. predict prognosis of cancer pa
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SigCheck/inst/doc/SigCheck.R
// Upstream  : BiocParallel, breastCancerNKI
// Downstream: none
//
// Install: BiocManager::install("SigCheck")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SIGCHECK {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-sigcheck"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-sigcheck:2.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-sigcheck:2.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_sigcheck_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_sigcheck_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_sigcheck_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SigCheck)
    library(MulticoreParam)
    library(jsonlite)

    # --- Background Comparison and Permutation Tests [] ---
    # Key functions: sigCheckRandom, sigCheckKnown, sigCheckPermutedSurvival, sigCheckPermutedFeatures
    check_random <- sigCheckRandom(check, N = 100)
    check_known <- sigCheckKnown(check, knownSignatures$cancer)
    check_perm_surv <- sigCheckPermutedSurvival(check, N = 100)
    check_perm_feat <- sigCheckPermutedFeatures(check, N = 100)
    random_pval <- check_random@survivalPval


    # --- Classifier-Based Evaluation [] ---
    # Key functions: sigCheck
    check_classifier <- sigCheck(
        nki,
        classes = "e.dmfs",
        signature = knownSignatures$cancer$VANTVEER,
        annotation = "HUGO.gene.symbol",
        validationSamples = which(nki$series == "NKI2"),
        scoreMethod = "classifier"
    )
    sig_perf <- check_classifier@sigPerformance
    mode_perf <- check_classifier@modePerformance
    confusion_mat <- check_classifier@confusion


    # --- Visualization of Signature Performance [] ---
    # Key functions: sigCheckPlot
    sigCheckPlot(nkiResults)
    sigCheckPlot(classifyRandom, classifier = TRUE)
    sigCheckPlot(classifyKnown, classifier = TRUE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_sigcheck_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_sigcheck_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_sigcheck_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SIGCHECK:", paste0("    sigcheck: ", packageVersion("SigCheck"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sigcheck_results.csv
    touch ${prefix}_sigcheck_output.rds
    echo "BIOC_SIGCHECK:" > versions.yml
    echo "    sigcheck: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SIGCHECK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SIGCHECK(ch_input)

    emit:
    results  = BIOC_SIGCHECK.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SIGCHECK.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SIGCHECK.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SIGCHECK.out.versions  // channel: path(versions.yml)
}
