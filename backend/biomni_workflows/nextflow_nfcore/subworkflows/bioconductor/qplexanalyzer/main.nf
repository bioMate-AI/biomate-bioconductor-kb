#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: qPLEXanalyzer
// Tools for TMT based quantitative proteomics data analysis.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/qPLEXanalyzer/inst/doc/qPLEXanalyzer.R
// Upstream  : dplyr, patchwork
// Downstream: qPLEXdata
//
// Install: BiocManager::install("qPLEXanalyzer")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_QPLEXANALYZER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-qplexanalyzer"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-qplexanalyzer:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-qplexanalyzer:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_qplexanalyzer_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_qplexanalyzer_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_qplexanalyzer_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(qPLEXanalyzer)
    library(jsonlite)


    # --- Import [] ---
    # Key functions: convertToMSnset, exprs, intensityPlot
    MSnset_data <- convertToMSnset(exp2_Xlink$intensities,
                                   metadata = exp2_Xlink$metadata,
                                   indExpData = c(7:16), 
                                   Sequences = 2, 
                                   Accessions = 6)
    exprs(MSnset_data) <- exprs(MSnset_data)+1.1
    MSnset_data
    intensityPlot(MSnset_data, title = "Peptide intensity distribution")

    # --- Boxplot [] ---
    # Key functions: intensityBoxplot, rliPlot
    intensityBoxplot(MSnset_data, title = "Peptide intensity distribution")
    rliPlot(MSnset_data, title = "Relative Peptide intensity")

    # --- Corrplot [] ---
    # Key functions: corrPlot, exprs, hierarchicalPlot
    corrPlot(MSnset_data)
    exprs(MSnset_data) <- exprs(MSnset_data) + 0.01
    hierarchicalPlot(MSnset_data)

    # --- Pcaplot [] ---
    # Key functions: pcaPlot, coveragePlot, extdata, qPLEXanalyzer
    pcaPlot(MSnset_data, labelColumn = "BioRep", pointsize = 3)
    mySequenceFile <- system.file("extdata", "P03372.fasta", package = "qPLEXanalyzer")
    coveragePlot(MSnset_data,
                 ProteinID = "P03372", 
                 ProteinName = "ESR1",
                 fastaFile = mySequenceFile)

    # --- Norm [] ---
    # Key functions: intensityPlot, normalizeQuantiles, normalizeScaling, groupScaling, fData, filter, as_tibble, arrange
    MSnset_data <- MSnset_data[, -5]
    p1 <- intensityPlot(MSnset_data, title = "No normalization")

    MSnset_norm_q <- normalizeQuantiles(MSnset_data)
    p2 <- intensityPlot(MSnset_norm_q, title = "Quantile")

    MSnset_norm_ns <- normalizeScaling(MSnset_data, scalingFunction = median)
    p3 <- intensityPlot(MSnset_norm_ns, title = "Scaling")

    # --- Summarize [] ---
    # Key functions: summarizeIntensities, peptideIntensityPlot
    MSnset_Pnorm <- summarizeIntensities(MSnset_norm_gs, 
                                         summarizationFunction = sum, 
                                         annotation = human_anno)
    peptideIntensityPlot(MSnset_data,
                         combinedIntensities = MSnset_Pnorm,
                         ProteinID = "P03372", 
                         ProteinName = "ESR1")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_qplexanalyzer_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_qplexanalyzer_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_qplexanalyzer_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_QPLEXANALYZER:", paste0("    qplexanalyzer: ", packageVersion("qPLEXanalyzer"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_qplexanalyzer_results.csv
    touch ${prefix}_qplexanalyzer_output.rds
    echo "BIOC_QPLEXANALYZER:" > versions.yml
    echo "    qplexanalyzer: 0.0.0" >> versions.yml
    """
}


workflow BIOC_QPLEXANALYZER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_QPLEXANALYZER(ch_input)

    emit:
    results  = BIOC_QPLEXANALYZER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_QPLEXANALYZER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_QPLEXANALYZER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_QPLEXANALYZER.out.versions  // channel: path(versions.yml)
}
