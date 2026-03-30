#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GenomicRanges
// The ability to efficiently represent and manipulate genomic annotations and alignments is playing a 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GenomicRanges/inst/doc/ExtendingGenomicRanges.R
// Upstream  : AnnotationHub, DESeq2, GenomicAlignments, GenomicFeatures, IRanges
// Downstream: alabaster.ranges, AllelicImbalance, AneuFinder, annmap, AnnotationHubData
//
// Install: BiocManager::install("GenomicRanges")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENOMICRANGES {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-genomicranges"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-genomicranges:1.58.0--r44_0' :
        'quay.io/biocontainers/bioconductor-genomicranges:1.58.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_genomicranges_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_genomicranges_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_genomicranges_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(VRanges)
    library(jsonlite)

    # --- Granges Ranges [] ---
    # Key functions: selectMethod
    library(GenomicRanges)
    selectMethod(ranges, "GRanges")
    # --- Delegating Granges Ranges [] ---
    # Key functions: selectMethod
    selectMethod(ranges, "DelegatingGenomicRanges")
    # --- Gnclist Granges [] ---
    # Key functions: getSlots
    getSlots("GNCList")["granges"]
    # --- Vranges [] ---
    # Key functions: extraColumnSlotNames, VRanges
    GenomicRanges:::extraColumnSlotNames(VariantAnnotation:::VRanges())

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_genomicranges_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_genomicranges_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_genomicranges_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GENOMICRANGES:", paste0("    genomicranges: ", packageVersion("GenomicRanges"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genomicranges_results.csv
    touch ${prefix}_genomicranges_output.rds
    echo "BIOC_GENOMICRANGES:" > versions.yml
    echo "    genomicranges: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GENOMICRANGES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GENOMICRANGES(ch_input)

    emit:
    results  = BIOC_GENOMICRANGES.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GENOMICRANGES.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GENOMICRANGES.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GENOMICRANGES.out.versions  // channel: path(versions.yml)
}
