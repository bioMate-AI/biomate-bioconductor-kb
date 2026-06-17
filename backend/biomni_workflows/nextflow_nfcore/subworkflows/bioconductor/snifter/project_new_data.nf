#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: snifter — project_new_data
// Project new, unseen test data into an existing t-SNE embedding.
// Input: train_mat, test_mat
// Container: quay.io/biocontainers/bioconductor-snifter:1.20.0--r45hdfd78af_0
// R packages: ggplot2, snifter
// Bioconductor: 3.20 | R: 4.4
// Requires: ggplot2, snifter
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Generate the reference t-SNE embedding on training data using fitsne
//  * 2. [Core Analysis] Project the new test data into the reference embedding using project

nextflow.enable.dsl = 2

process BIOC_SNIFTER_PROJECT_NEW_DATA {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("ggplot2", "snifter")
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
    library(snifter)
    library(ggplot2)
    
    # Helper function to read input matrices robustly
    read_input_matrix <- function(base_name) {
      possible_files <- c(
        base_name,
        paste0(base_name, ".rds"),
        paste0(base_name, ".csv"),
        paste0(base_name, ".tsv"),
        paste0(base_name, ".txt")
      )
      
      found_file <- NULL
      for (f in possible_files) {
        if (file.exists(f)) {
          found_file <- f
          break
        }
      }
      
      if (is.null(found_file)) {
        stop(paste("Error: Input file for", base_name, "not found in the working directory."))
      }
      
      # Read based on file extension or content
      if (grepl("\\\\.rds\$", found_file, ignore.case = TRUE)) {
        mat <- readRDS(found_file)
      } else {
        # Try reading as CSV/TSV
        delim <- if (grepl("\\\\.tsv\$", found_file, ignore.case = TRUE)) "\t" else ","
        df <- read.table(found_file, header = TRUE, sep = delim, row.names = 1, check.names = FALSE)
        mat <- as.matrix(df)
      }
      
      if (!is.matrix(mat)) {
        mat <- as.matrix(mat)
      }
      
      return(mat)
    }
    
    # 1. Read user input files
    message("Reading input matrices...")
    train_mat <- read_input_matrix("train_mat")
    test_mat <- read_input_matrix("test_mat")
    
    # 2. Generate the reference t-SNE embedding on training data
    message("Generating reference t-SNE embedding...")
    embedding <- fitsne(train_mat, random_state = 42L)
    
    # 3. Project the new test data into the reference embedding
    message("Projecting test data into reference embedding...")
    new_coords <- project(embedding, new = test_mat, old = train_mat)
    
    # 4. Save outputs
    message("Saving results...")
    # Save coordinates as CSV
    write.csv(new_coords, "new_coords.csv", row.names = TRUE)
    
    # Save embedding object as RDS
    saveRDS(embedding, "embedding.rds")
    
    # Create and save visualization plot
    df_train <- data.frame(
      tSNE1 = embedding[, 1],
      tSNE2 = embedding[, 2],
      Dataset = "Train"
    )
    df_test <- data.frame(
      tSNE1 = new_coords[, 1],
      tSNE2 = new_coords[, 2],
      Dataset = "Test"
    )
    df_all <- rbind(df_train, df_test)
    
    p <- ggplot(df_all, aes(x = tSNE1, y = tSNE2, color = Dataset, shape = Dataset)) +
      geom_point(alpha = 0.7, size = 1.5) +
      scale_color_manual(values = c("Train" = "#377eb8", "Test" = "#e41a1c")) +
      labs(
        title = "t-SNE Projection of New Data",
        x = "t-SNE 1",
        y = "t-SNE 2"
      ) +
      theme_bw() +
      theme(plot.title = element_text(hjust = 0.5, face = "bold"))
    
    ggsave("projection_plot.pdf", plot = p, width = 7, height = 6)
    
    message("Pipeline completed successfully. Outputs written: 'new_coords.csv', 'embedding.rds', 'projection_plot.pdf'.")

    writeLines(c(
        '"BIOC_SNIFTER_PROJECT_NEW_DATA":',
        paste0('    snifter: ', as.character(packageVersion('snifter')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_project_new_data.csv versions.yml
    """
}

workflow BIOC_SNIFTER_PROJECT_NEW_DATA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ train_mat, test_mat ] ]

    main:
    BIOC_SNIFTER_PROJECT_NEW_DATA(ch_input)

    emit:
    tables   = BIOC_SNIFTER_PROJECT_NEW_DATA.out.tables
    plots    = BIOC_SNIFTER_PROJECT_NEW_DATA.out.plots
    objects  = BIOC_SNIFTER_PROJECT_NEW_DATA.out.objects
    versions = BIOC_SNIFTER_PROJECT_NEW_DATA.out.versions
}
