#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: scDD
// This package implements a method to analyze single-cell RNA- seq Data utilizing flexible Dirichlet P
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/scDD/inst/doc/scDD.R
// Upstream  : SingleCellExperiment, gridExtra
// Downstream: none
//
// Install: BiocManager::install("scDD")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCDD {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-scdd"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-scdd:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-scdd:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_scdd_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_scdd_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_scdd_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SingleCellExperiment)
    library(jsonlite)

    # --- curve [] ---
    # Key functions: curve, polygon
    interesting DD patterns (illustration purposes only)
    par(mfrow=c(2,2), tcl=-0.5, mai=c(0.4,0.4,0.5,0.3))
    x <- seq(0, 6, by=0.05)
    # --- sc D D [] ---
    # Key functions: scDD
    scDatExSim <- scDD(scDatExSim, prior_param=prior_param, testZeroes=FALSE)
    # --- Extract differential expression results [] ---
    # Key functions: results
    RES <- results(scDatExSim)
    head(RES)
    # --- main engine perm [] ---
    # Key functions: scDD
    scDatExSim <- scDD(scDatExSim, prior_param=prior_param,
    # --- simulate Set [] ---
    # Key functions: simulateSet
    SD <- simulateSet(scDatEx, numSamples=numSamples,
    nEE=nEE, nEP=nEP, sd.range=c(2,2), modeFC=4, plots=FALSE,
    library(SingleCellExperiment)
    # --- Create SingleCellExperiment object [] ---
    # Key functions: SingleCellExperiment, show
    sce <- SingleCellExperiment(assays=list(normcounts=cbind(scDatExList$C1,
    colData=data.frame(condition))
    show(sce)
    # --- load exdat3e [] ---
    # Key functions: show
    data(scDatEx)
    show(scDatEx)
    # --- preprocess [] ---
    # Key functions: preprocess, show
    scDatEx <- preprocess(scDatEx, zero.thresh=0.9)
    show(scDatEx)
    # --- show [] ---
    # Key functions: show
    scDatEx.scran <- preprocess(scDatEx, zero.thresh=0.5, scran_norm=TRUE)
    show(scDatEx.scran)
    # --- plot DE [] ---
    # Key functions: sideViolin
    de <- sideViolin(normcounts(scDatExSim)[1,], scDatExSim$condition,
    title.gene=rownames(scDatExSim)[1])
    # --- plot DP [] ---
    # Key functions: sideViolin
    dp <- sideViolin(normcounts(scDatExSim)[6,], scDatExSim$condition,
    title.gene=rownames(scDatExSim)[6])
    # --- plot DM [] ---
    # Key functions: sideViolin
    dm <- sideViolin(normcounts(scDatExSim)[11,], scDatExSim$condition,
    title.gene=rownames(scDatExSim)[11])
    # --- plot DB [] ---
    # Key functions: sideViolin
    db <- sideViolin(normcounts(scDatExSim)[16,], scDatExSim$condition,
    title.gene=rownames(scDatExSim)[16])
    # --- plot EP [] ---
    # Key functions: sideViolin
    ep <- sideViolin(normcounts(scDatExSim)[21,], scDatExSim$condition,
    title.gene=rownames(scDatExSim)[21])
    # --- plot EE [] ---
    # Key functions: sideViolin
    ee <- sideViolin(normcounts(scDatExSim)[26,], scDatExSim$condition,
    title.gene=rownames(scDatExSim)[26])

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_scdd_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_scdd_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_scdd_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCDD:", paste0("    scdd: ", packageVersion("scDD"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scdd_results.csv
    touch ${prefix}_scdd_output.rds
    echo "BIOC_SCDD:" > versions.yml
    echo "    scdd: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCDD_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SCDD(ch_input)

    emit:
    results  = BIOC_SCDD.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCDD.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCDD.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCDD.out.versions  // channel: path(versions.yml)
}
