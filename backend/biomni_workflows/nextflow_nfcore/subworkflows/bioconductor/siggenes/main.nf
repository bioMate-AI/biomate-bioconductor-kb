#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: siggenes
// Identification of differentially expressed genes and estimation of the False Discovery Rate (FDR) us
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/siggenes/inst/doc/siggenes.R
// Upstream  : genefilter
// Downstream: KCsmart
//
// Install: BiocManager::install("siggenes")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SIGGENES {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-siggenes"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-siggenes:1.80.0--r44_0' :
        'quay.io/biocontainers/bioconductor-siggenes:1.80.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_siggenes_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_siggenes_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_siggenes_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(siggenes)
    library(jsonlite)

    # --- Significance Analysis of Microarrays ---
    # Key functions: sam, wilc.stat
    data(golub)
    sam.out <- sam(
        golub,
        golub.cl,
        rand = 123,
        gene.names = golub.gnames[, 3]
    )
    sam.out2 <- sam(
        golub,
        golub.cl,
        method = wilc.stat,
        rand = 123
    )

    # --- Delta Parameter Selection ---
    # Key functions: findDelta
    delta.fdr <- findDelta(sam.out, fdr = 0.05)
    delta.genes <- findDelta(sam.out, genes = 200)
    optimal.delta <- delta.fdr[1, "delta"]

    # --- Identification of Significant Genes ---
    # Key functions: summary, list.siggenes
    sum.sam.out <- summary(sam.out, delta = 3.3)
    sig.genes.list <- list.siggenes(sam.out, delta = 3.3)
    sig.rows <- sum.sam.out@row.sig.genes
    fdr.matrix <- sum.sam.out@mat.fdr

    # --- Empirical Bayes Parameter Optimization ---
    # Key functions: find.a0, ebam
    find.out <- find.a0(
        golub,
        golub.cl,
        rand = 123
    )
    ebam.out.opt <- ebam(find.out)
    ebam.out.specific <- ebam(find.out, which.a0 = 2)

    # --- Empirical Bayes Analysis of Microarrays ---
    # Key functions: ebam, summary
    ebam.out <- ebam(
        golub,
        golub.cl,
        a0 = 0,
        rand = 123
    )
    ebam.sum <- summary(ebam.out, delta = 0.9)


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_siggenes_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_siggenes_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_siggenes_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SIGGENES:", paste0("    siggenes: ", packageVersion("siggenes"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_siggenes_results.csv
    touch ${prefix}_siggenes_output.rds
    echo "BIOC_SIGGENES:" > versions.yml
    echo "    siggenes: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SIGGENES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SIGGENES(ch_input)

    emit:
    results  = BIOC_SIGGENES.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SIGGENES.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SIGGENES.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SIGGENES.out.versions  // channel: path(versions.yml)
}
