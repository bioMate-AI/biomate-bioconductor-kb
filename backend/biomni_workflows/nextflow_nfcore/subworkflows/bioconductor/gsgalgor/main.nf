#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GSgalgoR
// A multi-objective optimization algorithm for disease sub-type discovery based on a non-dominated sor
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GSgalgoR/inst/doc/GSgalgoR.R
// Upstream  : Biobase, breastCancerTRANSBIG, breastCancerUPP, genefu, ggplot2
// Downstream: none
//
// Install: BiocManager::install("GSgalgoR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GSGALGOR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gsgalgor"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gsgalgor:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gsgalgor:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(ggplot_object)

    output:
    tuple val(meta), path("${meta.id}_gsgalgor_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gsgalgor_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gsgalgor_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Surv)
    library(jsonlite)

    # --- Expression matrix extraction [] ---
    # Key functions: install_github, exprs, fData, pData, featureNames, unlist, Surv, sample
    expandProbesets <- function (eset, sep = "///", map="Gene.symbol"){
    x <- lapply(featureNames(eset), function(x) strsplit(x, sep)[[1]])
    y<- lapply(as.character(fData(eset)[,map]), function(x) strsplit(x,sep))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gsgalgor_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gsgalgor_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gsgalgor_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GSGALGOR:", paste0("    gsgalgor: ", packageVersion("GSgalgoR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gsgalgor_results.csv
    touch ${prefix}_gsgalgor_output.rds
    echo "BIOC_GSGALGOR:" > versions.yml
    echo "    gsgalgor: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GSGALGOR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(ggplot_object) ]

    main:
    BIOC_GSGALGOR(ch_input)

    emit:
    results  = BIOC_GSGALGOR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GSGALGOR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GSGALGOR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GSGALGOR.out.versions  // channel: path(versions.yml)
}
