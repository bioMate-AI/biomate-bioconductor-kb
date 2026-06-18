#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: tricycle — discrete_stage_inference
// Infer discrete cell cycle stages (G1/S, S, G2, G2/M, M/G1) using the Schwabe et al. (2020) method.
// Input: sce_normalized.rds
// Container: quay.io/biocontainers/bioconductor-tricycle:1.18.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, ggplot2, org.Mm.eg.db, scater, tricycle
// Visualizations: ordination plot
// QC: cell QC metrics
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Estimate discrete cell cycle stages using estimate_Schwabe_stage()
//  * 2. [Visualization & Output] Plot the projected cell cycle space colored by the predicted stages

nextflow.enable.dsl = 2

process BIOC_TRICYCLE_DISCRETE_STAGE_INFERENCE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    tuple val(meta), path("qc_metrics.json"), emit: qc_metrics
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("tricycle", "ggplot2", "scater", "org.Mm.eg.db")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(tricycle)
    library(ggplot2)
    library(scater)
    library(org.Mm.eg.db) # Required for mouse ENSEMBL to SYMBOL mapping in estimate_Schwabe_stage
    
    # Define input and output file paths
    input_file <- "sce_normalized.rds"
    output_rds <- "sce_with_stages.rds"
    output_csv <- "predicted_stages.csv"
    output_pdf <- "projected_cell_cycle_space_stages.pdf"
    
    # Check if input file exists
    if (!file.exists(input_file)) {
      stop(paste("Error: Input file", input_file, "not found in the working directory."))
    }
    
    # Read the SingleCellExperiment object
    message("Reading input SingleCellExperiment object...")
    neurosphere_example <- readRDS(input_file)
    
    # Ensure the data is projected to tricycleEmbedding space for plotting
    # If the embedding is not present, project it first
    if (!"tricycleEmbedding" %in% reducedDimNames(neurosphere_example)) {
      message("tricycleEmbedding not found. Projecting cell cycle space first...")
      neurosphere_example <- project_cycle_space(neurosphere_example, 
                                                 gname.type = 'ENSEMBL', 
                                                 species = 'mouse')
    }
    
    # 1. Estimate discrete cell cycle stages using estimate_Schwabe_stage()
    message("Estimating discrete cell cycle stages...")
    neurosphere_example <- estimate_Schwabe_stage(neurosphere_example,
                                                gname.type = 'ENSEMBL',
                                                species = 'mouse')
    
    # 2. Plot the projected cell cycle space colored by the predicted stages
    message("Generating projection plot...")
    p <- scater::plotReducedDim(neurosphere_example, dimred = "tricycleEmbedding",
                           colour_by = "CCStage") +
      labs(x = "Projected PC1", y = "Projected PC2",
           title = paste0("Projected cell cycle space (n=", ncol(neurosphere_example), ")")) +
      theme_bw(base_size = 14)
    
    # Save the plot as a PDF
    message(paste("Saving plot to", output_pdf, "..."))
    ggsave(output_pdf, plot = p, width = 7, height = 6)
    
    # Save the updated SingleCellExperiment object
    message(paste("Saving updated SingleCellExperiment object to", output_rds, "..."))
    saveRDS(neurosphere_example, output_rds)
    
    # Save the predicted stages as a CSV table
    message(paste("Saving predicted stages to", output_csv, "..."))
    stages_df <- data.frame(
      CellID = colnames(neurosphere_example),
      CCStage = neurosphere_example\$CCStage,
      stringsAsFactors = FALSE
    )
    write.csv(stages_df, file = output_csv, row.names = FALSE)
    
    message("Pipeline completed successfully!")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # cell QC metrics — defensive cell-count + per-cell summary from any
    # matrix artifact. Pass when columns (cells) ≥ 50 and rows (features) ≥ 200
    # (Luecken & Theis 2019 single-cell QC floor).
    .cqc_ncells <- NA_real_; .cqc_nfeats <- NA_real_; .cqc_files <- character(0)
    for (.cqc_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .cqc_obj <- tryCatch(readRDS(.cqc_rds), error = function(e) NULL)
      .cqc_mat <- if (is.matrix(.cqc_obj) || is.data.frame(.cqc_obj)) .cqc_obj else NULL
      if (!is.null(.cqc_mat) && nrow(.cqc_mat) > 100) {
        .cqc_ncells <- ncol(.cqc_mat); .cqc_nfeats <- nrow(.cqc_mat)
        .cqc_files <- c(.cqc_files, .cqc_rds); break
      }
    }
    .gates_by_label[["cell QC metrics"]] <- list(
      gate_row = "bioc_cell_qc_metrics",
      metric_name = "n_cells",
      metric_value = .cqc_ncells,
      passes = isTRUE(is.finite(.cqc_ncells) && .cqc_ncells >= 50 && .cqc_nfeats >= 200),
      status = if (is.finite(.cqc_ncells)) paste0("computed (cells=", .cqc_ncells, ", features=", .cqc_nfeats, "; proxy gate)")
               else "not_computed (no scRNA matrix .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_TRICYCLE_DISCRETE_STAGE_INFERENCE",
      domain  = "bioconductor",
      declared_qc_steps = c("cell QC metrics"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_TRICYCLE_DISCRETE_STAGE_INFERENCE":',
        paste0('    tricycle: ', as.character(packageVersion('tricycle')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_discrete_stage_inference.csv versions.yml
    """
}

workflow BIOC_TRICYCLE_DISCRETE_STAGE_INFERENCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce_normalized.rds ] ]

    main:
    BIOC_TRICYCLE_DISCRETE_STAGE_INFERENCE(ch_input)

    emit:
    tables   = BIOC_TRICYCLE_DISCRETE_STAGE_INFERENCE.out.tables
    plots    = BIOC_TRICYCLE_DISCRETE_STAGE_INFERENCE.out.plots
    objects  = BIOC_TRICYCLE_DISCRETE_STAGE_INFERENCE.out.objects
    versions = BIOC_TRICYCLE_DISCRETE_STAGE_INFERENCE.out.versions
}
