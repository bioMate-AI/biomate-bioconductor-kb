#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: PrInCE
// PrInCE (Predicting Interactomes from Co-Elution) uses a naive Bayes classifier trained on dataset-de
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/PrInCE/inst/doc/intro-to-prince.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("PrInCE")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PRINCE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-prince"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-prince:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-prince:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_prince_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_prince_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_prince_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(PrInCE)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data(gold_standard)
    head(gold_standard)
    # --- Threshold Precision [] ---
    # Key functions: threshold_precision
    ---------------------------------------------------------------------
    network <- threshold_precision(interactions, threshold = 0.5)
    nrow(network)
    # --- Data [] ---
    # Key functions: build_gaussians
    ---------------------------------------------------------------------
    data(scott)
    # set the seed to ensure reproducible output
    set.seed(0)
    # fit Gaussians
    # --- Calculate Features [] ---
    # Key functions: calculate_features
    ---------------------------------------------------------------------
    feat <- calculate_features(scott, gauss, euclidean_distance = FALSE)
    head(feat)
    # --- Data [] ---
    # Key functions: adjacency_matrix_from_list, predict_interactions
    ---------------------------------------------------------------------
    data(gold_standard)
    reference <- adjacency_matrix_from_list(gold_standard)
    # set the seed to ensure reproducible output
    set.seed(0)
    # --- Threshold Precision [] ---
    # Key functions: threshold_precision
    ---------------------------------------------------------------------
    net <- threshold_precision(ppi, threshold = 0.7)
    nrow(net)
    # --- Data [] ---
    # Key functions: filter_profiles, clean_profiles
    ---------------------------------------------------------------------
    # analyze cleaned profiles
    data(scott)
    filtered = filter_profiles(scott)
    chromatograms = clean_profiles(filtered)
    # --- Omit [] ---
    # Key functions: omit
    ---------------------------------------------------------------------
    # remove complexes that could not be analyzed
    z_scores = na.omit(z_scores)
    # how many could be tested?
    length(z_scores)
    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data("kristensen")
    data("kristensen_gaussians")
    dim(kristensen)
    length(kristensen_gaussians)
    # --- Threshold Precision [] ---
    # Key functions: threshold_precision
    ---------------------------------------------------------------------
    network <- threshold_precision(interactions, 0.5)
    nrow(network)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_prince_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_prince_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_prince_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PRINCE:", paste0("    prince: ", packageVersion("PrInCE"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_prince_results.csv
    touch ${prefix}_prince_output.rds
    echo "BIOC_PRINCE:" > versions.yml
    echo "    prince: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PRINCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PRINCE(ch_input)

    emit:
    results  = BIOC_PRINCE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PRINCE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PRINCE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PRINCE.out.versions  // channel: path(versions.yml)
}
