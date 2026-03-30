#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: AnnotationHub
// This package provides a client for the Bioconductor AnnotationHub web resource. The AnnotationHub we
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/AnnotationHub/inst/doc/AnnotationHub-HOWTO.R
// Upstream  : AnnotationDbi, Rsamtools, VariantAnnotation, txdbmaker
// Downstream: adductomicsR, AnnotationHubData, ExperimentHub, hipathia, ipdDb
//
// Install: BiocManager::install("AnnotationHub")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ANNOTATIONHUB {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-annotationhub"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-annotationhub:3.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-annotationhub:3.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_annotationhub_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_annotationhub_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_annotationhub_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(AnnotationHub)
    library(jsonlite)

    # --- Access AnnotationHub resources [] ---
    # Key functions: AnnotationHub, query
    library(AnnotationHub)
    ah <- AnnotationHub()
    query(ah, "OrgDb")
    # --- keytypes [] ---
    # Key functions: keytypes, columns
    library(AnnotationDbi)
    AnnotationDbi::keytypes(orgdb)
    AnnotationDbi::columns(orgdb)
    # --- query [] ---
    # Key functions: query
    query(ah, c("Takifugu", "release-94"))
    # --- make Tx Db From G Ranges [] ---
    # Key functions: makeTxDbFromGRanges
    library(txdbmaker)         # for makeTxDbFromGRanges
    txdb <- makeTxDbFromGRanges(gtf_subset)
    # --- exons [] ---
    # Key functions: exons, getSeq, query
    library(Rsamtools)               # for getSeq,FaFile-method
    exons <- exons(txdb)
    length(exons)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_annotationhub_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_annotationhub_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_annotationhub_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ANNOTATIONHUB:", paste0("    annotationhub: ", packageVersion("AnnotationHub"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_annotationhub_results.csv
    touch ${prefix}_annotationhub_output.rds
    echo "BIOC_ANNOTATIONHUB:" > versions.yml
    echo "    annotationhub: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ANNOTATIONHUB_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ANNOTATIONHUB(ch_input)

    emit:
    results  = BIOC_ANNOTATIONHUB.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ANNOTATIONHUB.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ANNOTATIONHUB.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ANNOTATIONHUB.out.versions  // channel: path(versions.yml)
}
