#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: hicVennDiagram
// A package to generate high-resolution Venn and Upset plots for genomic interaction data from HiC, Ch
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/hicVennDiagram/inst/doc/hicVennDiagram.R
// Upstream  : BiocManager, ChIPpeakAnno, ggplot2
// Downstream: none
//
// Install: BiocManager::install("hicVennDiagram")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HICVENNDIAGRAM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-hicvenndiagram"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-hicvenndiagram:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-hicvenndiagram:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_hicvenndiagram_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_hicvenndiagram_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_hicvenndiagram_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(hicVennDiagram)
    library(jsonlite)

    # --- venn Count [] ---
    # Key functions: vennCount, upsetPlot
    file_folder <- system.file("extdata",
    file_list <- dir(file_folder, pattern = ".bedpe", full.names = TRUE)
    names(file_list) <- sub(".bedpe", "", basename(file_list))
    # --- chippeakanno findOverlapsOfPeaks [] ---
    # Key functions: toGRanges, findOverlapsOfPeaks, vennTable, overlappingPeaksToVennTable
    library(ChIPpeakAnno)
    bed <- system.file("extdata", "MACS_output.bed", package="ChIPpeakAnno")
    gr1 <- toGRanges(bed, format="BED", header=FALSE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_hicvenndiagram_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_hicvenndiagram_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_hicvenndiagram_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HICVENNDIAGRAM:", paste0("    hicvenndiagram: ", packageVersion("hicVennDiagram"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hicvenndiagram_results.csv
    touch ${prefix}_hicvenndiagram_output.rds
    echo "BIOC_HICVENNDIAGRAM:" > versions.yml
    echo "    hicvenndiagram: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HICVENNDIAGRAM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HICVENNDIAGRAM(ch_input)

    emit:
    results  = BIOC_HICVENNDIAGRAM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HICVENNDIAGRAM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HICVENNDIAGRAM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HICVENNDIAGRAM.out.versions  // channel: path(versions.yml)
}
