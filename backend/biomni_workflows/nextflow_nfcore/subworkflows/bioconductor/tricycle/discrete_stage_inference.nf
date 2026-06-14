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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("tricycle", "ggplot2", "scater", "org.Mm.eg.db")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
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
