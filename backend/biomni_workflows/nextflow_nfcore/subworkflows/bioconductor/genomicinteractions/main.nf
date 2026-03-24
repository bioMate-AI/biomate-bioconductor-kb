#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GenomicInteractions
// Utilities for handling genomic interaction data such as ChIA-PET or Hi-C, annotating genomic feature
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GenomicInteractions/inst/doc/chiapet_vignette.R
// Upstream  : GenomicFeatures, GenomicRanges, Gviz, InteractionSet, knitr
// Downstream: none
//
// Install: BiocManager::install("GenomicInteractions")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENOMICINTERACTIONS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-genomicinteractions"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-genomicinteractions:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-genomicinteractions:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_genomicinteractions_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_genomicinteractions_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_genomicinteractions_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GenomicInteractions)
    library(jsonlite)

    # --- Name analysis [] ---
    # Key functions: name, description, anchorOne, anchorTwo, strand, subsetByFeatures, annotateInteractions, annotationFeatures
    refseq.promoters = promoters(refseq.transcripts, upstream=2500, downstream=2500)
    refseq.transcripts.ul = unlist(refseq.transcripts)
    strand(refseq.transcripts.ul) = ifelse(strand(refseq.transcripts.ul) == "+", "-", "+")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_genomicinteractions_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_genomicinteractions_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_genomicinteractions_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GENOMICINTERACTIONS:", paste0("    genomicinteractions: ", packageVersion("GenomicInteractions"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genomicinteractions_results.csv
    touch ${prefix}_genomicinteractions_output.rds
    echo "BIOC_GENOMICINTERACTIONS:" > versions.yml
    echo "    genomicinteractions: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GENOMICINTERACTIONS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GENOMICINTERACTIONS(ch_input)

    emit:
    results  = BIOC_GENOMICINTERACTIONS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GENOMICINTERACTIONS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GENOMICINTERACTIONS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GENOMICINTERACTIONS.out.versions  // channel: path(versions.yml)
}
