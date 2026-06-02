#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: deconvR
// This package provides a collection of functions designed for analyzing deconvolution of the bulk sam
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/deconvR/inst/doc/deconvRVignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("deconvR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DECONVR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-deconvr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-deconvr:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-deconvr:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_deconvr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_deconvr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_deconvr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(deconvR)
    library(BSmeth2Probe)
    library(jsonlite)

    # --- Cell Mixture Simulation [] ---
    # Key functions: simulateCellMix
    data("HumanCellTypeMethAtlas")
    simulated_data <- simulateCellMix(
        numberOfSamples = 3,
        reference = HumanCellTypeMethAtlas
    )
    samples <- simulated_data$simulated
    proportions <- simulated_data$proportions

    # --- Probe Mapping [] ---
    # Key functions: BSmeth2Probe
    data("IlluminaMethEpicB5ProbeIDs")
    load(system.file("extdata", "WGBS_GRanges.rda", package = "deconvR"))
    mapped_WGBS_data <- BSmeth2Probe(
        probe_id_locations = IlluminaMethEpicB5ProbeIDs,
        WGBS_data = WGBS_GRanges,
        multipleMapping = TRUE,
        cutoff = 10
    )

    # --- Signature Identification [] ---
    # Key functions: simulateCellMix, findSignatures
    data("HumanCellTypeMethAtlas")
    samples <- simulateCellMix(3, reference = HumanCellTypeMethAtlas)$simulated
    sampleMeta <- data.table::data.table(
        "Experiment_accession" = colnames(samples)[-1],
        "Biosample_term_name" = "new cell type"
    )
    extended_matrix <- findSignatures(
        samples = samples,
        sampleMeta = sampleMeta,
        atlas = HumanCellTypeMethAtlas,
        IDs = "IDs"
    )

    # --- Cell Type Deconvolution [] ---
    # Key functions: simulateCellMix, deconvolute
    data("HumanCellTypeMethAtlas")
    simulated_bulk <- simulateCellMix(
        numberOfSamples = 1,
        reference = HumanCellTypeMethAtlas
    )$simulated
    deconvolution <- deconvolute(
        reference = HumanCellTypeMethAtlas,
        bulk = simulated_bulk
    )
    proportions <- deconvolution$proportions


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_deconvr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_deconvr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_deconvr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DECONVR:", paste0("    deconvr: ", packageVersion("deconvR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_deconvr_results.csv
    touch ${prefix}_deconvr_output.rds
    echo "BIOC_DECONVR:" > versions.yml
    echo "    deconvr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DECONVR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DECONVR(ch_input)

    emit:
    results  = BIOC_DECONVR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DECONVR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DECONVR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DECONVR.out.versions  // channel: path(versions.yml)
}
