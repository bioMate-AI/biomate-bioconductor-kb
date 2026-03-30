#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: segmentSeq
// High-throughput sequencing technologies allow the production of large volumes of short sequences, wh
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/segmentSeq/inst/doc/methylationAnalysis.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("segmentSeq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SEGMENTSEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-segmentseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-segmentseq:2.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-segmentseq:2.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_segmentseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_segmentseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_segmentseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(segmentSeq)
    library(jsonlite)

    # --- Methdist [] ---
    # Key functions: plotMethDistribution, rowMeans
    par(mfrow = c(2,1))
    dists <- plotMethDistribution(mD, main = "Distributions of methylation", chr = "Chr1")
    plotMethDistribution(mD,
                         subtract = rowMeans(sapply(dists, function(x) x[,2])),
                         main = "Differences between distributions", chr = "Chr1")
    # --- Figmethdist [] ---
    # Key functions: plotMethDistribution, rowMeans
    par(mfrow = c(2,1))
    dists <- plotMethDistribution(mD, main = "Distributions of methylation", chr = "Chr1")
    plotMethDistribution(mD,
                         subtract = rowMeans(sapply(dists, function(x) x[,2])),
                         main = "Differences between distributions", chr = "Chr1")
    # --- Processad [] ---
    # Key functions: processAD
    sD <- processAD(mD, cl = cl)
    # --- Heuristicseg [] ---
    # Key functions: heuristicSeg
    thresh = 0.2
    hS <- heuristicSeg(sD = sD, aD = mD, prop = thresh, cl = cl, gap = 100, getLikes = FALSE)
    hS
    # --- Mergemethsegs [] ---
    # Key functions: mergeMethSegs
    hS <- mergeMethSegs(hS, mD, gap = 5000, cl = cl)
    # --- Locilikelihoods [] ---
    # Key functions: lociLikelihoods
    ## hSL <- lociLikelihoods(hS, mD, cl = cl)
    # --- Plotmeth [] ---
    # Key functions: plotMeth
    plotMeth(mD, hSL, chr = "Chr1", limits = c(1, 50000), cap = 10)
    # --- Figplotmeth [] ---
    # Key functions: plotMeth
    plotMeth(mD, hSL, chr = "Chr1", limits = c(1, 50000), cap = 10)
    # --- Groups [] ---
    # Key functions: groups
    groups(hSL) <- list(NDE = c(1,1,1,1), DE = c("A", "A", "B", "B"))
    # --- Methobservables [] ---
    # Key functions: methObservables
    hSL <- methObservables(hSL)
    # --- Densityfunction [] ---
    # Key functions: densityFunction
    densityFunction(hSL) <- bbNCDist
    # --- Getpriors [] ---
    # Key functions: getPriors
    hSL <- getPriors(hSL, cl = cl)
    # --- Getlikelihoods [] ---
    # Key functions: getLikelihoods
    hSL <- getLikelihoods(hSL, cl = cl)
    # --- Topcounts [] ---
    # Key functions: topCounts
    topCounts(hSL, "DE")
    # --- <Stopcluster [] ---
    # Key functions: null, stopCluster
    if(!is.null(cl))
        stopCluster(cl)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_segmentseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_segmentseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_segmentseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SEGMENTSEQ:", paste0("    segmentseq: ", packageVersion("segmentSeq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_segmentseq_results.csv
    touch ${prefix}_segmentseq_output.rds
    echo "BIOC_SEGMENTSEQ:" > versions.yml
    echo "    segmentseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SEGMENTSEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SEGMENTSEQ(ch_input)

    emit:
    results  = BIOC_SEGMENTSEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SEGMENTSEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SEGMENTSEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SEGMENTSEQ.out.versions  // channel: path(versions.yml)
}
