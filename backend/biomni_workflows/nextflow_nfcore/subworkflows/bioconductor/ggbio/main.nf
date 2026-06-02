#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ggbio
// The ggbio package extends and specializes the grammar of graphics for biological data. The graphics 
//
// Source : https://raw.githubusercontent.com/tengfei/ggbio/master/vignettes/realvignettes/ggbio.Rnw
// Upstream  : none
// Downstream: CAFE, intansv
//
// Install: BiocManager::install("ggbio")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GGBIO {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ggbio"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ggbio:1.54.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ggbio:1.54.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ggbio_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ggbio_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ggbio_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ggbio)
    library(GRanges)
    library(GRangesFilter)
    library(GeneIdFilter)
    library(GeneNameFilter)
    library(IRanges)
    library(Ideogram)
    library(jsonlite)

    # --- Ideogram Generation [Ideogram] ---
    # Key functions: Ideogram
    p.ideo <- Ideogram(
        genome = "hg19",
        subchr = "chr2"
    )
    target_region <- GenomicRanges::GRanges(
        "chr2",
        IRanges::IRanges(1e8, 1e8 + 10000000)
    )
    p.ideo_zoomed <- p.ideo + ggplot2::xlim(target_region)

    # --- Gene Model Visualization [autoplot] ---
    # Key functions: autoplot
    wh <- GenomicRanges::GRanges(
        "chr17",
        IRanges::IRanges(41196312, 41277500)
    )
    p.txdb <- autoplot(
        Homo.sapiens::Homo.sapiens,
        which = wh,
        gap.geom = "chevron",
        label.color = "black",
        color = "brown",
        fill = "brown"
    )
    p.txdb_reduced <- autoplot(
        Homo.sapiens::Homo.sapiens,
        which = wh,
        stat = "reduce"
    )

    # --- Multi-track Alignment [tracks, Ideogram, autoplot] ---
    # Key functions: tracks, Ideogram, autoplot
    wh <- GenomicRanges::GRanges(
        "chr17",
        IRanges::IRanges(41196312, 41277500)
    )
    p.ideo <- Ideogram(
        genome = "hg19",
        subchr = "chr17"
    )
    p.txdb <- autoplot(
        Homo.sapiens::Homo.sapiens,
        which = wh
    )
    track_plot <- tracks(
        ideogram = p.ideo,
        gene_model = p.txdb,
        heights = c(1, 4)
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ggbio_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ggbio_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ggbio_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GGBIO:", paste0("    ggbio: ", packageVersion("ggbio"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ggbio_results.csv
    touch ${prefix}_ggbio_output.rds
    echo "BIOC_GGBIO:" > versions.yml
    echo "    ggbio: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GGBIO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GGBIO(ch_input)

    emit:
    results  = BIOC_GGBIO.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GGBIO.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GGBIO.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GGBIO.out.versions  // channel: path(versions.yml)
}
