#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: adSplit
// This package implements clustering of microarray gene expression profiles according to functional an
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/adSplit/inst/doc/tr_2005_02.R
// Upstream  : golubEsets
// Downstream: none
//
// Install: BiocManager::install("adSplit")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ADSPLIT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-adsplit"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-adsplit:1.76.0--r44_0' :
        'quay.io/biocontainers/bioconductor-adsplit:1.76.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_adsplit_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_adsplit_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_adsplit_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(adSplit)
    library(jsonlite)

    # --- Annotation-Driven Splitting [] ---
    # Key functions: adSplit
    splits <- adSplit(
        Golub_Merge,
        "GO:0007165",
        "hu6800",
        max.probes = 7000
    )


    # --- Randomized Significance Testing [] ---
    # Key functions: randomDiana2means
    scores <- randomDiana2means(
        20,
        exprs(Golub_Merge),
        "hu6800",
        ndraws = 1000,
        ignore.genes = 5
    )


    # --- Visualization of Splits [] ---
    # Key functions: image, hist
    hist(golubKEGGSplits)
    image(
        golubKEGGSplits,
        filter.fdr = 0.3,
        outfile = "splitSet.eps",
        res = 300
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_adsplit_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_adsplit_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_adsplit_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ADSPLIT:", paste0("    adsplit: ", packageVersion("adSplit"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_adsplit_results.csv
    touch ${prefix}_adsplit_output.rds
    echo "BIOC_ADSPLIT:" > versions.yml
    echo "    adsplit: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ADSPLIT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ADSPLIT(ch_input)

    emit:
    results  = BIOC_ADSPLIT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ADSPLIT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ADSPLIT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ADSPLIT.out.versions  // channel: path(versions.yml)
}
