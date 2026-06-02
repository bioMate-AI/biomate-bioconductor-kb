#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: fishpond
// Fishpond contains methods for differential transcript and gene expression analysis of RNA-seq data u
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/fishpond/inst/doc/allelic.R
// Upstream  : SummarizedExperiment, ensembldb, limma, macrophage, tximeta
// Downstream: none
//
// Install: BiocManager::install("fishpond")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FISHPOND {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-fishpond"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-fishpond:2.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-fishpond:2.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_fishpond_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_fishpond_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_fishpond_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(fishpond)
    library(jsonlite)

    # --- Two-Group Differential Analysis [] ---
    # Key functions: swish
    y <- swish(y, x = "allele", pair = "sample", fast = 1)
    res_stats <- mcols(y)[, c("stat", "pvalue", "qvalue")]
    sig_results <- res_stats[which(res_stats$qvalue < 0.05), ]


    # --- Visualization of Inferential Replicates [] ---
    # Key functions: plotInfReps, plotAllelicHeatmap
    idx <- 1:2
    plotInfReps(y, idx = idx[1], x = "allele", cov = "sample")
    dat <- data.frame(
        minusLogQ = -log10(mcols(y)$qvalue[idx]),
        row.names = rownames(y)[idx]
    )
    plotAllelicHeatmap(y, idx = idx, annotation_row = dat)


    # --- Interaction and Covariate Analysis [] ---
    # Key functions: makeSimSwishData, labelKeep, swish
    y_int <- makeSimSwishData(diffAI = TRUE, n = 12)
    y_int <- labelKeep(y_int)
    y_int <- swish(
        y_int, x = "allele", pair = "sample",
        cov = "condition", interaction = TRUE
    )


    # --- Dynamic Time-Course Analysis [] ---
    # Key functions: makeSimSwishData, labelKeep, swish, computeInfRV
    y_dyn <- makeSimSwishData(dynamicAI = TRUE)
    y_dyn <- labelKeep(y_dyn)
    y_dyn <- swish(
        y_dyn, x = "allele", pair = "sample",
        cov = "time", cor = "pearson"
    )
    y_dyn <- computeInfRV(y_dyn)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_fishpond_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_fishpond_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_fishpond_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FISHPOND:", paste0("    fishpond: ", packageVersion("fishpond"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fishpond_results.csv
    touch ${prefix}_fishpond_output.rds
    echo "BIOC_FISHPOND:" > versions.yml
    echo "    fishpond: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FISHPOND_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FISHPOND(ch_input)

    emit:
    results  = BIOC_FISHPOND.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FISHPOND.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FISHPOND.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FISHPOND.out.versions  // channel: path(versions.yml)
}
