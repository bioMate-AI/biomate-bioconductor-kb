#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: sccomp — model_comparison_loo
// Compare different composition models (e.g., with vs. without a covariate) using leave-one-out (loo) cross-validation.
// Input: user_seurat_obj.rds
// Container: quay.io/biocontainers/bioconductor-sccomp:2.2.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Seurat, loo, sccomp
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Fit the first model with sccomp_estimate() setting inference_method = "hmc" and enable_loo = TRUE
//  * 2. [Core Analysis] Fit the second model with sccomp_estimate() setting inference_method = "hmc" and enable_loo = TRUE
//  * 3. [Core Analysis] Compare models using loo_compare()

nextflow.enable.dsl = 2

process BIOC_SCCOMP_MODEL_COMPARISON_LOO {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(sccomp)
    library(loo)
    library(Seurat)
    
    # 1. Read user input
    if (!file.exists("user_seurat_obj.rds")) {
      stop("Error: 'user_seurat_obj.rds' not found in the working directory.")
    }
    seurat_obj <- readRDS("user_seurat_obj.rds")
    
    # 2. Fit first model (with factor association)
    message("Fitting model with factor association...")
    model_with_factor_association =
      seurat_obj |>
      sccomp_estimate(
        formula_composition = ~ type,
        sample = "sample",
        cell_group = "cell_group",
        inference_method = "hmc",
        enable_loo = TRUE,
        verbose = FALSE
      )
    
    # 3. Fit second model (without association)
    message("Fitting model without association...")
    model_without_association =
      seurat_obj |>
      sccomp_estimate(
        formula_composition = ~ 1,
        sample = "sample",
        cell_group = "cell_group",
        inference_method = "hmc",
        enable_loo = TRUE,
        verbose = FALSE
      )
    
    # 4. Compare models
    message("Comparing models using LOO...")
    comp <- loo_compare(
       attr(model_with_factor_association, "fit")\$loo(),
       attr(model_without_association, "fit")\$loo()
    )
    
    # 5. Save outputs
    message("Saving results...")
    saveRDS(model_with_factor_association, "model_with_factor_association.rds")
    saveRDS(model_without_association, "model_without_association.rds")
    saveRDS(comp, "loo_comparison.rds")
    
    # Write comparison summary to a text file
    sink("loo_comparison_summary.txt")
    print(comp)
    sink()
    
    # Write comparison results as a CSV table
    write.csv(as.data.frame(comp), "loo_comparison_results.csv", row.names = TRUE)
    
    message("Workflow complete. Outputs saved to 'model_with_factor_association.rds', 'model_without_association.rds', 'loo_comparison.rds', 'loo_comparison_summary.txt', and 'loo_comparison_results.csv'.")

    writeLines(c(
        '"BIOC_SCCOMP_MODEL_COMPARISON_LOO":',
        paste0('    sccomp: ', as.character(packageVersion('sccomp')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_model_comparison_loo.csv versions.yml
    """
}

workflow BIOC_SCCOMP_MODEL_COMPARISON_LOO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ user_seurat_obj.rds ] ]

    main:
    BIOC_SCCOMP_MODEL_COMPARISON_LOO(ch_input)

    emit:
    tables   = BIOC_SCCOMP_MODEL_COMPARISON_LOO.out.tables
    plots    = BIOC_SCCOMP_MODEL_COMPARISON_LOO.out.plots
    objects  = BIOC_SCCOMP_MODEL_COMPARISON_LOO.out.objects
    versions = BIOC_SCCOMP_MODEL_COMPARISON_LOO.out.versions
}
