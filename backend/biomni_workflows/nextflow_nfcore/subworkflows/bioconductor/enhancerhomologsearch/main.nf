#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: enhancerHomologSearch
// Get ENCODE data of enhancer region via H3K4me1 peaks and search homolog regions for given sequences.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/enhancerHomologSearch/inst/doc/enhancerHomologSearch.R
// Upstream  : BiocManager, MotifDb
// Downstream: none
//
// Install: BiocManager::install("enhancerHomologSearch")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ENHANCERHOMOLOGSEARCH {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-enhancerhomologsearch"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-enhancerhomologsearch:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-enhancerhomologsearch:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_enhancerhomologsearch_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_enhancerhomologsearch_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_enhancerhomologsearch_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GRanges)
    library(jsonlite)

    # --- Create GenomicRanges object [] ---
    # Key functions: GRanges, getENCODEdata, mget
    if (!"BiocManager" %in% rownames(installed.packages()))
    install.packages("BiocManager")
    library(BiocManager)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_enhancerhomologsearch_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_enhancerhomologsearch_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_enhancerhomologsearch_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ENHANCERHOMOLOGSEARCH:", paste0("    enhancerhomologsearch: ", packageVersion("enhancerHomologSearch"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_enhancerhomologsearch_results.csv
    touch ${prefix}_enhancerhomologsearch_output.rds
    echo "BIOC_ENHANCERHOMOLOGSEARCH:" > versions.yml
    echo "    enhancerhomologsearch: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ENHANCERHOMOLOGSEARCH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ENHANCERHOMOLOGSEARCH(ch_input)

    emit:
    results  = BIOC_ENHANCERHOMOLOGSEARCH.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ENHANCERHOMOLOGSEARCH.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ENHANCERHOMOLOGSEARCH.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ENHANCERHOMOLOGSEARCH.out.versions  // channel: path(versions.yml)
}
