#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: benchdamic
// Starting from a microbiome dataset (16S or WMS with absolute count values) it is possible to perform
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/benchdamic/inst/doc/intro.R
// Upstream  : BiocParallel, SPsimSeq, SummarizedExperiment, cowplot, ggplot2
// Downstream: none
//
// Install: BiocManager::install("benchdamic")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BENCHDAMIC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-benchdamic"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-benchdamic:1.12.2--r44_0' :
        'quay.io/biocontainers/bioconductor-benchdamic:1.12.2--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_benchdamic_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_benchdamic_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_benchdamic_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SerialParam)
    library(TreeSummarizedExperiment)
    library(jsonlite)

    # --- Data import and loading [] ---
    # Key functions: sample_data, createSplits, SerialParam, runSplits, tax_table
    genera <- tax_table(ps_plaque_16S)[, "GENUS"]
    rownames(microbial_metabolism) <- microbial_metabolism$Genus
    priorInfo <- data.frame(genera, "Type" =  microbial_metabolism[genera, "Type"])
    # --- Quality control and filtering [] ---
    # Key functions: TreeSummarizedExperiment, colData
    sim_obj <- TreeSummarizedExperiment::TreeSummarizedExperiment(
    assays = list("counts" = sim_list[[1]][["counts"]]),
    SummarizedExperiment::colData(sim_obj)[, "colData.Group"] <- as.factor(
    # --- HURDLE analysis [] ---
    # Key functions: fitHURDLE, prepareObserved, fitModels, plotRMSE, ldply, plot_grid, plotMD, kable_styling
    available_methods <- read.csv(file = "./benchdamic_methods.csv", sep = ";")
    kable(x = available_methods,
    col.names = c("Method (package)", "Short description", "Test",
    # --- Visualization and reporting [] ---
    # Key functions: plotPositives, facet_wrap, theme, geom_hline, ylim
    plotPositives(positives = positives_nodir) +
    facet_wrap( ~ method) +
    theme(legend.position = "none") +

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_benchdamic_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_benchdamic_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_benchdamic_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BENCHDAMIC:", paste0("    benchdamic: ", packageVersion("benchdamic"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_benchdamic_results.csv
    touch ${prefix}_benchdamic_output.rds
    echo "BIOC_BENCHDAMIC:" > versions.yml
    echo "    benchdamic: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BENCHDAMIC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BENCHDAMIC(ch_input)

    emit:
    results  = BIOC_BENCHDAMIC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BENCHDAMIC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BENCHDAMIC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BENCHDAMIC.out.versions  // channel: path(versions.yml)
}
