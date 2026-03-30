#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: fgsea
// The package implements an algorithm for fast gene set enrichment analysis. Using the fast algorithm 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/fgsea/inst/doc/fgsea-tutorial.R
// Upstream  : BiocParallel, GEOquery, Seurat, ggplot2, limma
// Downstream: gsean, metapone, PPInfer
//
// Install: BiocManager::install("fgsea")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FGSEA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-fgsea"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-fgsea:1.32.4--r44_0' :
        'quay.io/biocontainers/bioconductor-fgsea:1.32.4--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_fgsea_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_fgsea_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_fgsea_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(fgsea)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data, seed
    ---------------------------------------------------------------------
    data(examplePathways)
    data(exampleRanks)
    set.seed(42)
    # --- Fgsea [] ---
    # Key functions: fgsea
    ---------------------------------------------------------------------
    fgseaRes <- fgsea(pathways = examplePathways,
                      stats    = exampleRanks,
                      minSize  = 15,
                      maxSize  = 500)
    # --- Table [] ---
    # Key functions: setNames
    ---------------------------------------------------------------------
    ranks <- read.table(rnk.file,
                        header=TRUE, colClasses = c("character", "numeric"))
    ranks <- setNames(ranks$t, ranks$ID)
    str(ranks)
    # --- Gmtpathways [] ---
    # Key functions: gmtPathways
    ---------------------------------------------------------------------
    pathways <- gmtPathways(gmt.file)
    str(head(pathways))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_fgsea_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_fgsea_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_fgsea_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FGSEA:", paste0("    fgsea: ", packageVersion("fgsea"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fgsea_results.csv
    touch ${prefix}_fgsea_output.rds
    echo "BIOC_FGSEA:" > versions.yml
    echo "    fgsea: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FGSEA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FGSEA(ch_input)

    emit:
    results  = BIOC_FGSEA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FGSEA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FGSEA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FGSEA.out.versions  // channel: path(versions.yml)
}
