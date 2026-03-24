#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: sarks
// Suffix Array Kernel Smoothing (see https://academic.oup.com/bioinformatics/article-abstract/35/20/39
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/sarks/inst/doc/sarks-vignette.R
// Upstream  : ggplot2, rJava
// Downstream: none
//
// Install: BiocManager::install("sarks")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SARKS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-sarks"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-sarks:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-sarks:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_sarks_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_sarks_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_sarks_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Sarks)
    library(jsonlite)

    # --- Java Initialization [] ---
    # Key functions: jinit
    options(java.parameters = '-Xmx8G')  ## sets to 8 gigabytes: modify as needed
    library(rJava)
    .jinit()
    ## ---------------------------------------------------------------------
    ## once you've set the java.parameters and then called .jinit from rJava
    # --- Check Scores [] ---
    # Key functions: data
    data(simulatedScores)
    simulatedScores
    # --- Minimal 1 [] ---
    # Key functions: Sarks, sarksFilters, permutationDistribution, permutationThresholds, kmerPeaks
    sarks <- Sarks(simulatedSeqs, simulatedScores, halfWindow=4)
    filters <- sarksFilters(halfWindow=4, spatialLength=0, minGini=1.1)
    permDist <- permutationDistribution(sarks, reps=250, filters, seed=123)
    thresholds <- permutationThresholds(filters, permDist, nSigma=2.0)
    peaks <- kmerPeaks(sarks, filters, thresholds)
    # --- Kmer Counts [] ---
    # Key functions: kmerCounts
    kmerCounts(unique(peaks$kmer), simulatedSeqs)
    # --- Merging Simplification [] ---
    # Key functions: mergedKmerSubPeaks
    nonRedundantPeaks <- mergedKmerSubPeaks(sarks, filters, thresholds)
    nonRedundantPeaks[ , c('i', 's', 'block', 'wi', 'kmer', 'windowed')]
    # --- Extending [] ---
    # Key functions: extendKmers
    extendedPeaks <- extendKmers(sarks, nonRedundantPeaks)
    extendedPeaks[ , c('i', 's', 'block', 'wi', 'kmer', 'windowed')]
    # --- Catseq [] ---
    # Key functions: getCatSeq
    concatenated <- sarks$getCatSeq()
    nchar(concatenated)
    # --- Source Block [] ---
    # Key functions: sourceBlock
    iCenteredWindow0Based <- iCenteredWindow - 1
    sourceBlock(sarks, i=iCenteredWindow0Based)
    # --- Yhat Plot [] ---
    # Key functions: getYhat
    yhat <- sarks$getYhat()
    i0based <- seq(0, length(yhat)-1)
    plot(i0based, yhat, type='l', xlab='i')
    # --- Perm Example [] ---
    # Key functions: sample, Sarks
    set.seed(12345)
    scoresPerm <- sample(simulatedScores)
    names(scoresPerm) <- names(simulatedScores)
    sarksPerm <- Sarks(simulatedSeqs, scoresPerm, halfWindow=4)
    # --- Perm Thresholds [] ---
    # Key functions: permutationDistribution, permutationThresholds, kmerPeaks
    permDistNull <- permutationDistribution(
            sarksPerm, reps=250, filters, seed=123)
    thresholdsNull <- permutationThresholds(
            filters, permDistNull, nSigma=2.0)
    peaksNull <- kmerPeaks(sarksPerm, filters, thresholdsNull)
    # --- Fpr Estimation [] ---
    # Key functions: estimateFalsePositiveRate
    fpr = estimateFalsePositiveRate(
            sarks, reps=250, filters, thresholds, seed=321)
    fpr$ci
    # --- Gini Testing [] ---
    # Key functions: estimateFalsePositiveRate, sarksFilters
    estimateFalsePositiveRate(
            sarks, reps=250, filters, thresholds, seed=321)$ci
    filtersNoGini <- sarksFilters(halfWindow=4, spatialLength=0, minGini=0)
    estimateFalsePositiveRate(
            sarks, reps=250, filtersNoGini, thresholds, seed=321)$ci
    # --- No Gini Thresholds [] ---
    # Key functions: permutationDistribution, permutationThresholds, kmerPeaks
    permDistNoGini <-
            permutationDistribution(sarks, reps=250, filtersNoGini, seed=123)
    thresholdsNoGini <-
            permutationThresholds(filtersNoGini, permDistNoGini, nSigma=2.0)
    peaksNoGini <- kmerPeaks(sarks, filtersNoGini, thresholdsNoGini)
    # --- Spatial [] ---
    # Key functions: Sarks, sarksFilters, permutationDistribution, permutationThresholds, kmerPeaks
    sarks <- Sarks(
        simulatedSeqs, simulatedScores, halfWindow=4, spatialLength=3
    )
    filters <- sarksFilters(halfWindow=4, spatialLength=3, minGini=1.1)
    permDist <- permutationDistribution(sarks, reps=250, filters, seed=123)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_sarks_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_sarks_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_sarks_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SARKS:", paste0("    sarks: ", packageVersion("sarks"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sarks_results.csv
    touch ${prefix}_sarks_output.rds
    echo "BIOC_SARKS:" > versions.yml
    echo "    sarks: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SARKS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SARKS(ch_input)

    emit:
    results  = BIOC_SARKS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SARKS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SARKS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SARKS.out.versions  // channel: path(versions.yml)
}
