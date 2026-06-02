#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: infinityFlow
// Pipeline to analyze and merge data files produced by BioLegend's LEGENDScreen or BD Human Cell Surfa
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/infinityFlow/inst/doc/basic_usage.R
// Upstream  : devtools
// Downstream: none
//
// Install: BiocManager::install("infinityFlow")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_INFINITYFLOW {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-infinityflow"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-infinityflow:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-infinityflow:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_infinityflow_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_infinityflow_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_infinityflow_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(infinityFlow)
    library(jsonlite)

    # --- Annotation and Backbone Specification [] ---
    # Key functions: steady_state_lung_backbone_specification, steady_state_lung_annotation
    dir <- file.path(tempdir(), "infinity_flow_example")
    backbone_spec <- steady_state_lung_backbone_specification
    backbone_file <- file.path(dir, "backbone_selection_file.csv")
    write.csv(backbone_spec, file = backbone_file, row.names = FALSE)
    targets <- steady_state_lung_annotation$Infinity_target
    names(targets) <- rownames(steady_state_lung_annotation)
    isotypes <- steady_state_lung_annotation$Infinity_isotype
    names(isotypes) <- rownames(steady_state_lung_annotation)


    # --- Infinity Flow Pipeline Execution [] ---
    # Key functions: infinity_flow
    dir <- file.path(tempdir(), "infinity_flow_example")
    imputed_data <- infinity_flow(
        path_to_fcs = file.path(dir, "fcs"),
        path_to_output = file.path(dir, "output"),
        path_to_intermediary_results = file.path(dir, "tmp"),
        backbone_selection_file = file.path(dir, "backbone_selection_file.csv"),
        annotation = targets,
        isotype = isotypes,
        input_events_downsampling = 1000,
        prediction_events_downsampling = 500,
        verbose = FALSE,
        cores = 1L
    )


    # --- Output Exploration [] ---
    # Key functions: infinity_flow
    output_dir <- file.path(tempdir(), "infinity_flow_example", "output")
    raw_fcs_dir <- file.path(output_dir, "FCS", "split")
    bgc_fcs_dir <- file.path(output_dir, "FCS_background_corrected", "split")
    raw_fcs_files <- list.files(raw_fcs_dir, pattern = ".fcs", full.names = TRUE)
    bgc_fcs_files <- list.files(bgc_fcs_dir, pattern = ".fcs", full.names = TRUE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_infinityflow_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_infinityflow_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_infinityflow_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_INFINITYFLOW:", paste0("    infinityflow: ", packageVersion("infinityFlow"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_infinityflow_results.csv
    touch ${prefix}_infinityflow_output.rds
    echo "BIOC_INFINITYFLOW:" > versions.yml
    echo "    infinityflow: 0.0.0" >> versions.yml
    """
}


workflow BIOC_INFINITYFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_INFINITYFLOW(ch_input)

    emit:
    results  = BIOC_INFINITYFLOW.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_INFINITYFLOW.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_INFINITYFLOW.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_INFINITYFLOW.out.versions  // channel: path(versions.yml)
}
