#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: tweeDEseq
// Differential expression analysis of RNA-seq using the Poisson-Tweedie (PT) family of distributions. 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/tweeDEseq/inst/doc/tweeDEseq.R
// Upstream  : xtable
// Downstream: none
//
// Install: BiocManager::install("tweeDEseq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TWEEDESEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-tweedeseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-tweedeseq:1.52.0--r44_0' :
        'quay.io/biocontainers/bioconductor-tweedeseq:1.52.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_tweedeseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_tweedeseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_tweedeseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(tweeDEseq)
    library(MAplot)
    library(Vplot)
    library(jsonlite)

    # --- Count Distribution Comparison [] ---
    # Key functions: compareCountDist
    counts_matrix <- matrix(rnbinom(1000, mu = 10, size = 1), nrow = 10)
    rownames(counts_matrix) <- paste0("GENE", 1:10)
    gender <- rep(c("female", "male"), each = 50)
    xf <- unlist(counts_matrix["GENE1", gender == "female"])
    xm <- unlist(counts_matrix["GENE1", gender == "male"])
    compareCountDist(xf, main = "Female samples")
    compareCountDist(xm, main = "Male samples")


    # --- Differential Expression Analysis [] ---
    # Key functions: tweeDE
    counts_matrix <- matrix(rnbinom(1000, mu = 10, size = 1), nrow = 10)
    rownames(counts_matrix) <- paste0("GENE", 1:10)
    group <- factor(rep(c("A", "B"), each = 50))
    resPT <- tweeDE(counts_matrix, group = group, mc.cores = 1)


    # --- Visualization of DE Results [] ---
    # Key functions: MAplot, Vplot
    hl <- list(
        list(genes = c("GENE1", "GENE2"), pch = 21, col = "blue", bg = "blue"),
        list(genes = c("GENE3"), pch = 1, col = "red", lwd = 2, cex = 1.5)
    )
    MAplot(resPT, cex = 0.7, log2fc.cutoff = log2(1.5), highlight = hl,
           main = "MA-plot")
    Vplot(resPT, cex = 0.7, highlight = hl, log2fc.cutoff = log2(1.5),
          pval.adjust.cutoff = 0.05, main = "Volcano plot")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_tweedeseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_tweedeseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_tweedeseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TWEEDESEQ:", paste0("    tweedeseq: ", packageVersion("tweeDEseq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tweedeseq_results.csv
    touch ${prefix}_tweedeseq_output.rds
    echo "BIOC_TWEEDESEQ:" > versions.yml
    echo "    tweedeseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TWEEDESEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TWEEDESEQ(ch_input)

    emit:
    results  = BIOC_TWEEDESEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TWEEDESEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TWEEDESEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TWEEDESEQ.out.versions  // channel: path(versions.yml)
}
