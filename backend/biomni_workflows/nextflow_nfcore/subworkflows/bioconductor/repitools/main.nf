#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Repitools
// Tools for the analysis of enrichment-based epigenomic data.  Features include summarization and visu
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Repitools/inst/doc/Repitools_vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("Repitools")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_REPITOOLS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-repitools"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-repitools:1.52.0--r44_0' :
        'quay.io/biocontainers/bioconductor-repitools:1.52.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_repitools_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_repitools_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_repitools_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Repitools)
    library(jsonlite)

    # --- Findclusters [] ---
    # Key functions: frame, rnorm, findClusters
    stats.table <- data.frame(chr = "chr1", pos = 1:500, t.stat = rnorm(500))
    stats.table[100:104, "t.stat"] <- rnorm(5, 5)
    stats.table[200:204, "t.stat"] <- rnorm(5, -5)
    stats.clustered <- findClusters(stats.table, score.col = 3, w.size = 5, n.med = 2, n.consec = 3, cut.samps = seq(-2, -10, -2), maxFDR = 0.05, trend = "down", n.perm = 10)
    cluster.1 <- which(stats.clustered$cluster == 1)
    # --- Genomeblocks [] ---
    # Key functions: genomeBlocks
    chrs <- c(50000, 10000)
    names(chrs) <- c("chr1", "chr2")
    genomeBlocks(chrs, width = 5000)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_repitools_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_repitools_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_repitools_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_REPITOOLS:", paste0("    repitools: ", packageVersion("Repitools"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_repitools_results.csv
    touch ${prefix}_repitools_output.rds
    echo "BIOC_REPITOOLS:" > versions.yml
    echo "    repitools: 0.0.0" >> versions.yml
    """
}


workflow BIOC_REPITOOLS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_REPITOOLS(ch_input)

    emit:
    results  = BIOC_REPITOOLS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_REPITOOLS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_REPITOOLS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_REPITOOLS.out.versions  // channel: path(versions.yml)
}
