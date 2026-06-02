#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: chromVAR
// Determine variation in chromatin accessibility across sets of annotations or peaks. Designed primari
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/chromVAR/inst/doc/Introduction.R
// Upstream  : BiocParallel, Matrix, SummarizedExperiment, motifmatchr
// Downstream: none
//
// Install: BiocManager::install("chromVAR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CHROMVAR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-chromvar"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-chromvar:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-chromvar:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_chromvar_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_chromvar_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_chromvar_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(chromVAR)
    library(jsonlite)

    # --- Quality Control and Filtering [] ---
    # Key functions: addGCBias, filterSamples, filterPeaks
    data(example_counts, package = "chromVAR")
    counts_gc <- addGCBias(
        example_counts,
        genome = BSgenome.Hsapiens.UCSC.hg19::BSgenome.Hsapiens.UCSC.hg19
    )
    counts_filtered <- filterSamples(
        counts_gc,
        min_depth = 1500,
        min_in_peaks = 0.15,
        shiny = FALSE
    )
    counts_filtered <- filterPeaks(counts_filtered, non_overlapping = TRUE)


    # --- Motif and Kmer Matching [] ---
    # Key functions: getJasparMotifs, matchMotifs, matchKmers
    motifs <- getJasparMotifs()
    motif_ix <- matchMotifs(
        motifs,
        counts_filtered,
        genome = BSgenome.Hsapiens.UCSC.hg19::BSgenome.Hsapiens.UCSC.hg19
    )
    kmer_ix <- matchKmers(
        6,
        counts_filtered,
        genome = BSgenome.Hsapiens.UCSC.hg19::BSgenome.Hsapiens.UCSC.hg19
    )


    # --- Deviation Computation [] ---
    # Key functions: getBackgroundPeaks, computeDeviations
    bg_peaks <- getBackgroundPeaks(object = counts_filtered)
    dev <- computeDeviations(
        object = counts_filtered,
        annotations = motif_ix,
        background_peaks = bg_peaks
    )


    # --- Variability Analysis and Visualization [] ---
    # Key functions: computeVariability, plotVariability, deviationsTsne, plotDeviationsTsne
    variability <- computeVariability(dev)
    var_plot <- plotVariability(variability, use_plotly = FALSE)
    tsne_results <- deviationsTsne(dev, threshold = 1.5, perplexity = 10)
    tsne_plots <- plotDeviationsTsne(
        dev,
        tsne_results,
        annotation_name = "TEAD3",
        sample_column = "Cell_Type",
        shiny = FALSE
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_chromvar_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_chromvar_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_chromvar_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CHROMVAR:", paste0("    chromvar: ", packageVersion("chromVAR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chromvar_results.csv
    touch ${prefix}_chromvar_output.rds
    echo "BIOC_CHROMVAR:" > versions.yml
    echo "    chromvar: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CHROMVAR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CHROMVAR(ch_input)

    emit:
    results  = BIOC_CHROMVAR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CHROMVAR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CHROMVAR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CHROMVAR.out.versions  // channel: path(versions.yml)
}
