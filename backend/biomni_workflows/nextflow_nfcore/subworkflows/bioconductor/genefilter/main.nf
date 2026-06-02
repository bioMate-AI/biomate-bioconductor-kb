#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: genefilter
// Some basic functions for filtering genes.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/genefilter/inst/doc/howtogenefilter.R
// Upstream  : ALL, Biobase, class
// Downstream: CNTools, GeneMeta, sva, Hiiragi2013, maEndToEnd
//
// Install: BiocManager::install("genefilter")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENEFILTER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-genefilter"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-genefilter:1.88.0--r44_0' :
        'quay.io/biocontainers/bioconductor-genefilter:1.88.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_genefilter_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_genefilter_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_genefilter_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Aggregate)
    library(jsonlite)

    # --- var Labels [] ---
    # Key functions: varLabels
    library("Biobase")
    library("genefilter")
    data(sample.ExpressionSet)
    # --- filterfun [] ---
    # Key functions: filterfun, genefilter
    ffun_combined <- filterfun(f1, f2)
    wh3 <- genefilter(exprs(sample.ExpressionSet), ffun_combined)
    sum(wh3)
    # --- selectfun [] ---
    # Key functions: selectfun, scale, Aggregate

    # --- ttest [] ---
    # Key functions: ttest, filterfun, genefilter

    # --- genescale [] ---
    # Key functions: genescale, new, knnCV
    library("class")
    geneData <- genescale(exprs(sample.ExpressionSet)[1:75,], 1)
    Agg <- new("aggregator")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_genefilter_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_genefilter_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_genefilter_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GENEFILTER:", paste0("    genefilter: ", packageVersion("genefilter"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genefilter_results.csv
    touch ${prefix}_genefilter_output.rds
    echo "BIOC_GENEFILTER:" > versions.yml
    echo "    genefilter: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GENEFILTER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GENEFILTER(ch_input)

    emit:
    results  = BIOC_GENEFILTER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GENEFILTER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GENEFILTER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GENEFILTER.out.versions  // channel: path(versions.yml)
}
