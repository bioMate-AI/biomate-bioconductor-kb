#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: FEAST — model_selection_and_visualization
// Run consensus clustering, evaluate multiple feature sizes using a short model selection function, and visualize the validation results.
// Input: Y, k, trueclass
// Container: quay.io/biocontainers/bioconductor-feast:1.18.0--r45h01b2380_0
// R packages: FEAST, ggplot2, ggpubr
// Bioconductor: 3.20 | R: 4.4
// Requires: FEAST, ggplot2, ggpubr
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Preprocess the count matrix using process_Y
//  * 2. [Visualization & Output] Perform consensus clustering using Consensus
//  * 3. [Visualization & Output] Run model selection using Select_Model_short_TSCAN
//  * 4. [Visualization & Output] Visualize the results using Visual_Rslt

nextflow.enable.dsl = 2

process BIOC_FEAST_MODEL_SELECTION_AND_VISUALIZATION {
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
    .bm_deps <- c("FEAST", "ggplot2", "ggpubr")
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
    library(FEAST)
    library(ggpubr)
    library(ggplot2)
    
    # Robustly read inputs from the working directory
    message("Reading input files...")
    
    if (file.exists("Y.rds")) {
      Y <- readRDS("Y.rds")
    } else if (file.exists("Y.csv")) {
      Y <- as.matrix(read.csv("Y.csv", row.names = 1, check.names = FALSE))
    } else if (file.exists("Y.tsv")) {
      Y <- as.matrix(read.delim("Y.tsv", row.names = 1, check.names = FALSE))
    } else {
      stop("Error: Count matrix Y not found. Please provide Y.rds, Y.csv, or Y.tsv in the working directory.")
    }
    
    if (file.exists("k.rds")) {
      k <- readRDS("k.rds")
    } else if (file.exists("k.txt")) {
      k <- as.integer(readLines("k.txt", n = 1))
    } else {
      stop("Error: Number of clusters k not found. Please provide k.rds or k.txt in the working directory.")
    }
    
    if (file.exists("trueclass.rds")) {
      trueclass <- readRDS("trueclass.rds")
    } else if (file.exists("trueclass.txt")) {
      trueclass <- readLines("trueclass.txt")
    } else if (file.exists("trueclass.csv")) {
      trueclass <- read.csv("trueclass.csv", header = FALSE)[[1]]
    } else {
      stop("Error: True class labels not found. Please provide trueclass.rds, trueclass.txt, or trueclass.csv in the working directory.")
    }
    
    # Ensure Y is a matrix
    Y <- as.matrix(Y)
    
    # --- Preprocess the count matrix using process_Y ---
    message("Preprocessing count matrix...")
    Y = process_Y(Y, thre = 2)
    
    # --- Perform consensus clustering using Consensus ---
    message("Performing consensus clustering...")
    con_res = Consensus(Y, k=k)
    
    # Save consensus clustering results
    saveRDS(con_res, "consensus_results.rds")
    if (!is.null(con_res\$cluster)) {
      write.csv(data.frame(Cell = names(con_res\$cluster), Cluster = con_res\$cluster), 
                "consensus_clusters.csv", row.names = FALSE)
    }
    
    # --- Run model selection using Select_Model_short_TSCAN ---
    message("Running model selection...")
    mod_res = Select_Model_short_TSCAN(Y, cluster = con_res\$cluster, top = c(200, 500, 1000, 2000))
    
    # Save model selection results
    saveRDS(mod_res, "model_selection_results.rds")
    if (is.data.frame(mod_res)) {
      write.csv(mod_res, "model_selection_metrics.csv", row.names = TRUE)
    } else if (is.list(mod_res)) {
      tryCatch({
        write.csv(as.data.frame(mod_res), "model_selection_metrics.csv", row.names = TRUE)
      }, error = function(e) {
        sink("model_selection_summary.txt")
        print(mod_res)
        sink()
      })
    }
    
    # --- Visualize the results using Visual_Rslt ---
    message("Visualizing results...")
    PP = Visual_Rslt(model_cv_res = mod_res, trueclass = trueclass)
    
    # Print the plot to the current device
    print(PP\$ggobj)
    
    # Save the visualization plot to files
    message("Saving plots...")
    ggsave("validation_plot.pdf", plot = PP\$ggobj, width = 8, height = 6)
    ggsave("validation_plot.png", plot = PP\$ggobj, width = 8, height = 6, dpi = 300)
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_FEAST_MODEL_SELECTION_AND_VISUALIZATION":',
        paste0('    FEAST: ', as.character(packageVersion('FEAST')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_model_selection_and_visualization.csv versions.yml
    """
}

workflow BIOC_FEAST_MODEL_SELECTION_AND_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Y, k, trueclass ] ]

    main:
    BIOC_FEAST_MODEL_SELECTION_AND_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_FEAST_MODEL_SELECTION_AND_VISUALIZATION.out.tables
    plots    = BIOC_FEAST_MODEL_SELECTION_AND_VISUALIZATION.out.plots
    objects  = BIOC_FEAST_MODEL_SELECTION_AND_VISUALIZATION.out.objects
    versions = BIOC_FEAST_MODEL_SELECTION_AND_VISUALIZATION.out.versions
}
