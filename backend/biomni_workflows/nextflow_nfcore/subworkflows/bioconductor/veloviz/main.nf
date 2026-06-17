#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: veloviz — veloviz_trajectory_embedding
// Build a velocity-informed 2D embedding from current and projected transcriptional states and visualize it.
// Input: curr, proj
// Container: quay.io/biocontainers/bioconductor-veloviz:1.16.0--r45ha27e39d_0
// R packages: veloviz
// Bioconductor: 3.20 | R: 4.4
// Requires: veloviz
// Visualizations: trajectory plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Extract or load current and projected transcriptional states
//  * 2. [Input & Preparation] Build the VeloViz graph using buildVeloviz
//  * 3. [Core Analysis] Extract the 2D embedding coordinates from the VeloViz object
//  * 4. [Visualization & Output] Plot the embedding

nextflow.enable.dsl = 2

process BIOC_VELOVIZ_VELOVIZ_TRAJECTORY_EMBEDDING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("veloviz")
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
    library(veloviz)
    
    # Helper function to read input files robustly
    read_input <- function(base_name) {
      # Check for RDS
      if (file.exists(paste0(base_name, ".rds"))) {
        message(paste("Reading", base_name, "from RDS..."))
        return(as.matrix(readRDS(paste0(base_name, ".rds"))))
      }
      # Check for CSV
      if (file.exists(paste0(base_name, ".csv"))) {
        message(paste("Reading", base_name, "from CSV..."))
        df <- read.csv(paste0(base_name, ".csv"), row.names = 1, check.names = FALSE)
        return(as.matrix(df))
      }
      # Check for TSV
      if (file.exists(paste0(base_name, ".tsv"))) {
        message(paste("Reading", base_name, "from TSV..."))
        df <- read.delim(paste0(base_name, ".tsv"), row.names = 1, check.names = FALSE)
        return(as.matrix(df))
      }
      # Check for exact file name without extension
      if (file.exists(base_name)) {
        message(paste("Reading", base_name, "from direct file path..."))
        res <- tryCatch({
          as.matrix(readRDS(base_name))
        }, error = function(e) {
          df <- read.csv(base_name, row.names = 1, check.names = FALSE)
          as.matrix(df)
        })
        return(res)
      }
      
      stop(paste("Error: Input file for", base_name, "not found in the working directory (expected .rds, .csv, or .tsv)."))
    }
    
    # 1. Extract or load current and projected transcriptional states
    message("Loading input matrices...")
    curr <- read_input("curr")
    proj <- read_input("proj")
    
    # Ensure inputs are matrices
    curr <- as.matrix(curr)
    proj <- as.matrix(proj)
    
    # 2. Build the VeloViz graph using buildVeloviz
    message("Building VeloViz graph...")
    veloviz <- veloviz::buildVeloviz(curr = curr, proj = proj,
                                     normalize.depth = TRUE,
                                     use.ods.genes = FALSE,  
                                     pca = TRUE, nPCs = 3,
                                     center = TRUE, scale = TRUE,
                                     k = 10, similarity.threshold = -1,
                                     distance.weight = 1, distance.threshold = 1,
                                     weighted = TRUE, verbose = FALSE)
    
    # 3. Extract the 2D embedding coordinates from the VeloViz object
    message("Extracting 2D embedding coordinates...")
    emb.veloviz <- veloviz\$fdg_coords
    
    # 4. Plot the embedding and save outputs
    message("Saving outputs...")
    
    # Save the 2D embedding coordinates as a CSV
    write.csv(emb.veloviz, file = "veloviz_embedding_coords.csv", row.names = TRUE)
    
    # Save the full VeloViz object as an RDS file
    saveRDS(veloviz, file = "veloviz_object.rds")
    
    # Save the plot as a PDF
    pdf("veloviz_trajectory_plot.pdf", width = 7, height = 7)
    plot(emb.veloviz, 
         main = "VeloViz 2D Trajectory Embedding", 
         xlab = "VeloViz 1", 
         ylab = "VeloViz 2", 
         pch = 19, 
         col = rgb(0, 0, 0, 0.5), 
         cex = 0.6)
    dev.off()
    
    message("Workflow completed successfully. Outputs saved: 'veloviz_embedding_coords.csv', 'veloviz_object.rds', 'veloviz_trajectory_plot.pdf'.")

    writeLines(c(
        '"BIOC_VELOVIZ_VELOVIZ_TRAJECTORY_EMBEDDING":',
        paste0('    veloviz: ', as.character(packageVersion('veloviz')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_veloviz_trajectory_embedding.csv versions.yml
    """
}

workflow BIOC_VELOVIZ_VELOVIZ_TRAJECTORY_EMBEDDING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ curr, proj ] ]

    main:
    BIOC_VELOVIZ_VELOVIZ_TRAJECTORY_EMBEDDING(ch_input)

    emit:
    tables   = BIOC_VELOVIZ_VELOVIZ_TRAJECTORY_EMBEDDING.out.tables
    plots    = BIOC_VELOVIZ_VELOVIZ_TRAJECTORY_EMBEDDING.out.plots
    objects  = BIOC_VELOVIZ_VELOVIZ_TRAJECTORY_EMBEDDING.out.objects
    versions = BIOC_VELOVIZ_VELOVIZ_TRAJECTORY_EMBEDDING.out.versions
}
