#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: nullranges
// Modular package for generation of sets of ranges representing the null hypothesis. These can take th
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/nullranges/inst/doc/bootRanges.R
// Upstream  : AnnotationHub, ExperimentHub, GenomeInfoDb, GenomicRanges, InteractionSet
// Downstream: none
//
// Install: BiocManager::install("nullranges")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NULLRANGES {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-nullranges"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-nullranges:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-nullranges:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_nullranges_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_nullranges_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_nullranges_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(AnnotationHub)
    library(DHSA549Hg38)
    library(GRanges)
    library(IRanges)
    library(jsonlite)

    # --- Access AnnotationHub resources [] ---
    # Key functions: AnnotationHub, trim
    suppressPackageStartupMessages(library(AnnotationHub))
    ah <- AnnotationHub()
    # --- segment Density [] ---
    # Key functions: segmentDensity, plotSegment
    set.seed(5)
    plyranges::filter(width(exclude) >= 500)
    # --- segment Density [] ---
    # Key functions: segmentDensity, plotSegment, DHSA549Hg38

    # --- Custom ggplot2 visualization [] ---
    # Key functions: ggplot, geom_histogram, geom_vline
    suppressPackageStartupMessages(library(ggplot2))
    ggplot(boot_stats, aes(sumOverlaps)) +
    geom_histogram(binwidth=5)+
    # --- Create GenomicRanges object [] ---
    # Key functions: GRanges, IRanges, seqlengths
    set.seed(1)
    # --- boot Ranges [] ---
    # Key functions: bootRanges, plotGRanges
    set.seed(1)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_nullranges_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_nullranges_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_nullranges_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_NULLRANGES:", paste0("    nullranges: ", packageVersion("nullranges"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_nullranges_results.csv
    touch ${prefix}_nullranges_output.rds
    echo "BIOC_NULLRANGES:" > versions.yml
    echo "    nullranges: 0.0.0" >> versions.yml
    """
}


workflow BIOC_NULLRANGES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_NULLRANGES(ch_input)

    emit:
    results  = BIOC_NULLRANGES.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_NULLRANGES.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_NULLRANGES.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_NULLRANGES.out.versions  // channel: path(versions.yml)
}
