#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Gviz
// Genomic data analyses requires integrated visualization of known genomic information and new experim
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Gviz/inst/doc/Gviz.R
// Upstream  : GenomicFeatures, GenomicRanges, biomaRt, ensembldb, knitr
// Downstream: biomvRCNS, chimeraviz, cicero, cummeRbund, Pviz
//
// Install: BiocManager::install("Gviz")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GVIZ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gviz"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gviz:1.50.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gviz:1.50.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gviz_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gviz_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gviz_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(AnnotationTrack)
    library(GRanges)
    library(GeneRegionTrack)
    library(GenomeAxisTrack)
    library(IdeogramTrack)
    library(SequenceTrack)
    library(jsonlite)

    # --- Create GenomicRanges object [] ---
    # Key functions: GRanges, plotTracks
    introns <- GRanges("chr12", IRanges(start = c(2973662, 2973919),
    end = c(2973848, 2974520)))
    plotTracks(c(bmt, alTrack), from = afrom + 12700, to = afrom + 15200,
    # --- Markdown analysis [] ---
    # Key functions: markdown, latex, biomartCacheClear, genome, AnnotationTrack, GenomeAxisTrack, plotTracks, IdeogramTrack
    types <- data.frame(Value=c("p", "l", "b", "a", "s", "S", "g", "r", "h", "confint", "smooth", "histogram", "mountain", "polygon", "boxplot", "gradient", "heatmap", "horizon"),
    Type=c("dot plot", "lines plot", "dot and lines plot", "lines plot of average (i.e., mean) values", "stair steps (horizontal first)",
    "stair steps (vertical first)", "add grid lines", "add linear regression line", "histogram lines", "confidence intervals for average values", "add loess curve",

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gviz_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gviz_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gviz_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GVIZ:", paste0("    gviz: ", packageVersion("Gviz"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gviz_results.csv
    touch ${prefix}_gviz_output.rds
    echo "BIOC_GVIZ:" > versions.yml
    echo "    gviz: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GVIZ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GVIZ(ch_input)

    emit:
    results  = BIOC_GVIZ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GVIZ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GVIZ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GVIZ.out.versions  // channel: path(versions.yml)
}
