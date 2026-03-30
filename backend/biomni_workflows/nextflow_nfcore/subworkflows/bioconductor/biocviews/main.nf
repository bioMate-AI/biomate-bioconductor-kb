#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: biocViews
// Infrastructure to support 'views' used to classify Bioconductor packages. 'biocViews' are directed a
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/biocViews/inst/doc/HOWTO-BCV.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("biocViews")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIOCVIEWS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-biocviews"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-biocviews:1.74.0--r44_0' :
        'quay.io/biocontainers/bioconductor-biocviews:1.74.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_biocviews_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_biocviews_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_biocviews_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(biocViews)
    library(jsonlite)

    # --- Querying a repository [] ---
    # Key functions: getBiocSubViews
    data(biocViewsVocab)
    reposPath <- system.file("doc", package="biocViews")
    reposUrl <- paste("file://", reposPath, sep="")
    # --- get Sub Terms [] ---
    # Key functions: getSubTerms
    getSubTerms(biocViewsVocab, term="Technology")
    # --- Generating HTML [] ---
    # Key functions: writeBiocViews
    viewsDir <- file.path(tempdir(), "biocViews")
    dir.create(viewsDir)
    writeBiocViews(biocViews, dir=viewsDir)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_biocviews_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_biocviews_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_biocviews_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BIOCVIEWS:", paste0("    biocviews: ", packageVersion("biocViews"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biocviews_results.csv
    touch ${prefix}_biocviews_output.rds
    echo "BIOC_BIOCVIEWS:" > versions.yml
    echo "    biocviews: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BIOCVIEWS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BIOCVIEWS(ch_input)

    emit:
    results  = BIOC_BIOCVIEWS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BIOCVIEWS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BIOCVIEWS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BIOCVIEWS.out.versions  // channel: path(versions.yml)
}
