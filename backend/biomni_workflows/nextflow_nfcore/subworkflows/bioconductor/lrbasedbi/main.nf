#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: LRBaseDbi
// Interface to construct LRBase package (LRBase.XXX.eg.db).
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/LRBaseDbi/inst/doc/LRBaseDbi.R
// Upstream  : AnnotationHub, scTensor
// Downstream: none
//
// Install: BiocManager::install("LRBaseDbi")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_LRBASEDBI {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-lrbasedbi"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-lrbasedbi:2.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-lrbasedbi:2.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_lrbasedbi_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_lrbasedbi_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_lrbasedbi_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(AnnotationHub)
    library(LRBaseDb)
    library(jsonlite)

    # --- Annotationhub [] ---
    # Key functions: AnnotationHub, query, LRBaseDb
    library("LRBaseDbi")
    library("AnnotationHub")
    ah <- AnnotationHub()
    dbfile <- query(ah, c("LRBaseDb", "Sus scrofa", "v001"))[[1]]
    # Constructor

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_lrbasedbi_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_lrbasedbi_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_lrbasedbi_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_LRBASEDBI:", paste0("    lrbasedbi: ", packageVersion("LRBaseDbi"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_lrbasedbi_results.csv
    touch ${prefix}_lrbasedbi_output.rds
    echo "BIOC_LRBASEDBI:" > versions.yml
    echo "    lrbasedbi: 0.0.0" >> versions.yml
    """
}


workflow BIOC_LRBASEDBI_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_LRBASEDBI(ch_input)

    emit:
    results  = BIOC_LRBASEDBI.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_LRBASEDBI.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_LRBASEDBI.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_LRBASEDBI.out.versions  // channel: path(versions.yml)
}
