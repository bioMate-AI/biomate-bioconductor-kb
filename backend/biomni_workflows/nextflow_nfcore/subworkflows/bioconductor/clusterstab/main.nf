#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: clusterStab
// This package can be used to estimate the number of clusters in a set of microarray data, as well as 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/clusterStab/inst/doc/clusterStab.R
// Upstream  : fibroEset, genefilter
// Downstream: none
//
// Install: BiocManager::install("clusterStab")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CLUSTERSTAB {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-clusterstab"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-clusterstab:1.78.0--r44_0' :
        'quay.io/biocontainers/bioconductor-clusterstab:1.78.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_clusterstab_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_clusterstab_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_clusterstab_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(clusterStab)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: exprs, cv, genefilter, benhur
    library(clusterStab)
    library(genefilter)
    library(fibroEset)
    data(fibroEset)
    exprs(fibroEset) <- log2(exprs(fibroEset))
    # --- Plot [] ---
    # Key functions: hclust, dist, exprs, pData
    plot(hclust(dist(t(exprs(fibroEset[index,])))), labels = pData(fibroEset)[,2], sub="", xlab="")
    # --- Plot [] ---
    # Key functions: hclust, dist, exprs, pData, ecdf
    plot(hclust(dist(t(exprs(fibroEset[index,])))), labels = pData(fibroEset)[,2], sub="", xlab="")
    ecdf(bh)
    # --- Clustercomp [] ---
    # Key functions: clusterComp
    cmp <- clusterComp(fb, 2)
    cmp

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_clusterstab_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_clusterstab_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_clusterstab_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CLUSTERSTAB:", paste0("    clusterstab: ", packageVersion("clusterStab"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_clusterstab_results.csv
    touch ${prefix}_clusterstab_output.rds
    echo "BIOC_CLUSTERSTAB:" > versions.yml
    echo "    clusterstab: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CLUSTERSTAB_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CLUSTERSTAB(ch_input)

    emit:
    results  = BIOC_CLUSTERSTAB.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CLUSTERSTAB.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CLUSTERSTAB.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CLUSTERSTAB.out.versions  // channel: path(versions.yml)
}
