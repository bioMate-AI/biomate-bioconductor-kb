#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: baySeq
// This package identifies differential expression in high-throughput 'count' data, such as that derive
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/baySeq/inst/doc/baySeq.R
// Upstream  : parallel
// Downstream: clusterSeq, segmentSeq
//
// Install: BiocManager::install("baySeq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BAYSEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-bayseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-bayseq:2.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-bayseq:2.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_bayseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_bayseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_bayseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CD)
    library(NB)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    data(simData)
    simData[1:10,]
    # --- Libsizes [] ---
    # Key functions: libsizes, getLibsizes
    libsizes(CD) <- getLibsizes(CD)
    libsizes(CD)
    # --- Plotma [] ---
    # Key functions: CD
    plotMA.CD(CD, samplesA = "simA", samplesB = "simB",
              col = c(rep("red", 100), rep("black", 900)))
    # --- Figplotma [] ---
    # Key functions: CD
    plotMA.CD(CD, samplesA = "simA", samplesB = "simB",
              col = c(rep("red", 100), rep("black", 900)))
    # --- Frame [] ---
    # Key functions: frame
    CD@annotation <- data.frame(name = paste("count", 1:1000, sep = "_"))
    # --- Nb [] ---
    # Key functions: NB
    CD <- getPriors.NB(CD, samplesize = 1000, estimation = "QL", cl = cl)
    # --- Getlikelihoods [] ---
    # Key functions: getLikelihoods
    CD <- getLikelihoods(CD, cl = cl, bootStraps = 3, verbose = FALSE)
    CD@estProps
    CD@posteriors[1:10,]
    CD@posteriors[101:110,]
    # --- Topcounts [] ---
    # Key functions: topCounts
    topCounts(CD, group = "DE")
    # --- Plotposteriors [] ---
    # Key functions: plotPosteriors
    plotPosteriors(CD, group = "DE", col = c(rep("red", 100), rep("black", 900)))
    # --- Figplotposteriors [] ---
    # Key functions: plotPosteriors
    plotPosteriors(CD, group = "DE", col = c(rep("red", 100), rep("black", 900)))
    # --- Data [] ---
    # Key functions: data
    data(mobData)
    data(mobAnnotation)
    # --- Libsizes [] ---
    # Key functions: libsizes, getLibsizes
    libsizes(cD) <- getLibsizes(cD, estimationType = "quantile")
    # --- Replicates [] ---
    # Key functions: replicates, factor
    replicates(cDPair) <- as.factor(c("D3/D3", "D3/D3", "WT/D3", "WT/D3"))
    # --- Groups [] ---
    # Key functions: groups
    groups(cDPair) <- list(NDE = NDE, mobile = mobile)
    # --- Nb [] ---
    # Key functions: NB
    cDPair <- getPriors.NB(cDPair, samplesize = 1e4, cl = cl)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_bayseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_bayseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_bayseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BAYSEQ:", paste0("    bayseq: ", packageVersion("baySeq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bayseq_results.csv
    touch ${prefix}_bayseq_output.rds
    echo "BIOC_BAYSEQ:" > versions.yml
    echo "    bayseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BAYSEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BAYSEQ(ch_input)

    emit:
    results  = BIOC_BAYSEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BAYSEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BAYSEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BAYSEQ.out.versions  // channel: path(versions.yml)
}
