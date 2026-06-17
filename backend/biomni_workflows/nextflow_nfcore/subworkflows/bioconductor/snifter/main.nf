#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: snifter — run_fitsne
// Run fast interpolated t-SNE (FI-tSNE) on a high-dimensional matrix to generate 2D coordinates.
// Input: counts
// Container: quay.io/biocontainers/bioconductor-snifter:1.20.0--r45hdfd78af_0
// R packages: BiocStyle, ggplot2, snifter
// Bioconductor: 3.20 | R: 4.4
// Requires: ggplot2, snifter
// Visualizations: t-SNE plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run FI-tSNE using the fitsne function
//  * 2. [Visualization & Output] Visualize the resulting 2D coordinates

nextflow.enable.dsl = 2

process BIOC_SNIFTER_RUN_FITSNE {
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
    .bm_deps <- c("BiocStyle", "ggplot2", "snifter")
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
        library("snifter")
        library("ggplot2")
        
        # Set theme for plotting
        theme_set(theme_bw())
        
        # -----------------------------------------------------------------------------
        # 1. Read User Input
        # -----------------------------------------------------------------------------
        # The pipeline expects a file named 'counts' (CSV, TSV, or RDS format)
        # representing a high-dimensional matrix where rows are samples and columns are features.
        
        counts <- NULL
        
        if (file.exists("counts.csv")) {
          counts_df <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
          counts <- as.matrix(counts_df)
        } else if (file.exists("counts.tsv")) {
          counts_df <- read.delim("counts.tsv", row.names = 1, check.names = FALSE)
          counts <- as.matrix(counts_df)
        } else if (file.exists("counts.rds")) {
          counts <- readRDS("counts.rds")
          if (!is.matrix(counts)) {
            counts <- as.matrix(counts)
          }
        } else {
          stop("Error: Input 'counts' file (counts.csv, counts.tsv, or counts.rds) not found in the working directory.")
        }
        
        # Optional: Read labels for visualization if available.
        # If not available, we will use a default dummy label.
        label <- NULL
        if (file.exists("labels.csv")) {
          labels_df <- read.csv("labels.csv", header = TRUE)
          if ("label" %in% colnames(labels_df)) {
            label <- labels_df\$label
          } else {
            label <- labels_df[, 1]
          }
        } else if (file.exists("labels.txt")) {
          label <- readLines("labels.txt")
        } else {
          label <- rep("Sample", nrow(counts))
        }
        
        # -----------------------------------------------------------------------------
        # 2. Run FI-tSNE (Documented Code)
        # -----------------------------------------------------------------------------
        fit <- fitsne(counts, random_state = 42L)
        
        # -----------------------------------------------------------------------------
        # 3. Visualize and Save Results
        # -----------------------------------------------------------------------------
        # Generate the t-SNE plot
        p <- ggplot() +
            aes(fit[, 1], fit[, 2], colour = label) +
            geom_point(pch = 19) +
            scale_colour_discrete(name = "Cluster") +
            labs(x = "t-SNE 1", y = "t-SNE 2")
        
        # Save the plot to a PDF file
        ggsave("tsne_plot.pdf", plot = p, width = 8, height = 6)
        
        # Prepare coordinates data frame for export
        sample_names <- rownames(counts)
        if (is.null(sample_names)) {
          sample_names <- paste0("Sample_", seq_len(nrow(counts)))
        }
        
        coords_df <- data.frame(
          Sample = sample_names,
          tSNE_1 = fit[, 1],
          tSNE_2 = fit[, 2]
        )
        
        # Save coordinates to CSV
        write.csv(coords_df, "tsne_coordinates.csv", row.names = FALSE)
        
        # Save the fit object as RDS
        saveRDS(fit, "snifter_fit.rds")

    writeLines(c(
        '"BIOC_SNIFTER_RUN_FITSNE":',
        paste0('    snifter: ', as.character(packageVersion('snifter')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_run_fitsne.csv versions.yml
    """
}

workflow BIOC_SNIFTER_RUN_FITSNE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ counts ] ]

    main:
    BIOC_SNIFTER_RUN_FITSNE(ch_input)

    emit:
    tables   = BIOC_SNIFTER_RUN_FITSNE.out.tables
    plots    = BIOC_SNIFTER_RUN_FITSNE.out.plots
    objects  = BIOC_SNIFTER_RUN_FITSNE.out.objects
    versions = BIOC_SNIFTER_RUN_FITSNE.out.versions
}
