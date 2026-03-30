#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Rsamtools
// This package provides an interface to the 'samtools', 'bcftools', and 'tabix' utilities for manipula
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Rsamtools/inst/doc/Rsamtools-Overview.R
// Upstream  : GenomicAlignments, RCurl
// Downstream: CODEX, CoverageView, esATAC, FRASER, GenomicAlignments
//
// Install: BiocManager::install("Rsamtools")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RSAMTOOLS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rsamtools"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rsamtools:2.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rsamtools:2.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rsamtools_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rsamtools_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rsamtools_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BamViews)
    library(GRanges)
    library(ScanBamParam)
    library(jsonlite)

    # --- Create GenomicRanges object [] ---
    # Key functions: GRanges, ScanBamParam, scanBam, coverage
    which <- GRanges("6:100000-110000")
    param <- ScanBamParam(which=which, what=scanBamWhat())
    na19240bam <- scanBam(na19240url, param=param)
    # --- Transcript annotation retrieval [] ---
    # Key functions: structure, unname, setNames, keggList, enframe, keggLink, left_join, pull
    KEGGREST::keggList("pathway", org)
    tibble::enframe(name = "pathway_id", value = "pathway")
    dplyr::filter(startsWith(.data$pathway, "Caffeine metabolism"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rsamtools_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rsamtools_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rsamtools_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RSAMTOOLS:", paste0("    rsamtools: ", packageVersion("Rsamtools"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rsamtools_results.csv
    touch ${prefix}_rsamtools_output.rds
    echo "BIOC_RSAMTOOLS:" > versions.yml
    echo "    rsamtools: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RSAMTOOLS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RSAMTOOLS(ch_input)

    emit:
    results  = BIOC_RSAMTOOLS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RSAMTOOLS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RSAMTOOLS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RSAMTOOLS.out.versions  // channel: path(versions.yml)
}
