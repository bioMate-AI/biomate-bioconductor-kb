#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: gg4way — gg4way_with_limma
// Compare two contrasts from a limma-voom analysis using a 4-way plot and extract shared significant genes.
// Input: efit
// Container: quay.io/biocontainers/bioconductor-gg4way:1.8.0--r45hdfd78af_0
// R packages: airway, DESeq2, edgeR, gg4way, ggplot2, limma, purrr
// Bioconductor: 3.20 | R: 4.4
// Requires: gg4way, ggplot2, limma
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Generate the 4-way plot using gg4way()
//  * 2. [Core Analysis] Extract shared significant genes using getShared()
//  * 3. [Core Analysis] Extract the Pearson correlation coefficient using getCor()
//  * 4. [Visualization & Output] Plot with specific gene labels

nextflow.enable.dsl = 2

process BIOC_GG4WAY_GG4WAY_WITH_LIMMA {
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
    .bm_deps <- c("airway", "DESeq2", "edgeR", "gg4way", "ggplot2", "limma", "purrr")
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
        library(limma)
        library(gg4way)
        library(ggplot2)
        
        # -----------------------------------------------------------------------------
        # Stage 0: Read User Input
        # -----------------------------------------------------------------------------
        # The pipeline expects an MArrayLM object named 'efit' in the working directory.
        # We will check for both 'efit' and 'efit.rds'.
        input_file <- NULL
        if (file.exists("efit")) {
            input_file <- "efit"
        } else if (file.exists("efit.rds")) {
            input_file <- "efit.rds"
        } else {
            stop("Error: Required input file 'efit' or 'efit.rds' not found in the working directory.")
        }
        
        message("Reading input file: ", input_file)
        efit <- readRDS(input_file)
        
        # Extract contrast names dynamically
        contrasts <- colnames(efit)
        if (length(contrasts) < 2) {
            stop("Error: efit object must contain at least two contrasts.")
        }
        contrast_x <- contrasts[1]
        contrast_y <- contrasts[2]
        
        # -----------------------------------------------------------------------------
        # Stage 1: Generate the 4-way plot using gg4way()
        # -----------------------------------------------------------------------------
        message("Generating 4-way plot...")
        p1 <- efit |>
            gg4way(x = contrast_x,
                   y = contrast_y)
        
        # Display/evaluate the plot
        p1
        
        # Save the plot to a PDF file
        ggsave("gg4way_plot.pdf", plot = p1, width = 6, height = 6.5)
        message("Saved 4-way plot to 'gg4way_plot.pdf'")
        
        # -----------------------------------------------------------------------------
        # Stage 2: Extract shared significant genes using getShared()
        # -----------------------------------------------------------------------------
        message("Extracting shared significant genes...")
        shared_genes <- p1 |>
            getShared()
        
        # Print the head of the shared genes table as documented
        print(head(shared_genes))
        
        # Save the complete table of shared significant genes to a CSV file
        write.csv(shared_genes, "shared_significant_genes.csv", row.names = FALSE)
        message("Saved shared significant genes to 'shared_significant_genes.csv'")
        
        # -----------------------------------------------------------------------------
        # Stage 3: Plot with specific gene labels
        # -----------------------------------------------------------------------------
        message("Generating 4-way plot with specific gene labels...")
        
        # Dynamically select up to 2 genes to label from the shared significant genes
        if ("symbol" %in% colnames(shared_genes)) {
            label_genes <- head(shared_genes\$symbol, 2)
        } else if ("ID" %in% colnames(shared_genes)) {
            label_genes <- head(shared_genes\$ID, 2)
        } else {
            label_genes <- head(shared_genes[[1]], 2)
        }
        label_genes <- label_genes[!is.na(label_genes)]
        
        if (length(label_genes) > 0) {
            p2 <- efit |>
                gg4way(x = contrast_x,
                       y = contrast_y,
                       label = label_genes)
        } else {
            p2 <- efit |>
                gg4way(x = contrast_x,
                       y = contrast_y)
        }
        
        # Save the labeled plot to a PDF file
        ggsave("gg4way_labeled_plot.pdf", plot = p2, width = 6, height = 6.5)
        message("Saved labeled 4-way plot to 'gg4way_labeled_plot.pdf'")
        
        # -----------------------------------------------------------------------------
        # Stage 4: Extract the Pearson correlation coefficient using getCor()
        # -----------------------------------------------------------------------------
        message("Extracting Pearson correlation coefficient...")
        correlation_coef <- p1 |>
            getCor()
        
        # Print the correlation coefficient
        print(correlation_coef)
        
        # Save the correlation coefficient to a text file
        writeLines(as.character(correlation_coef), "pearson_correlation.txt")
        message("Saved Pearson correlation coefficient to 'pearson_correlation.txt'")
        
        message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_GG4WAY_GG4WAY_WITH_LIMMA":',
        paste0('    gg4way: ', as.character(packageVersion('gg4way')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gg4way_with_limma.csv versions.yml
    """
}

workflow BIOC_GG4WAY_GG4WAY_WITH_LIMMA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ efit ] ]

    main:
    BIOC_GG4WAY_GG4WAY_WITH_LIMMA(ch_input)

    emit:
    tables   = BIOC_GG4WAY_GG4WAY_WITH_LIMMA.out.tables
    plots    = BIOC_GG4WAY_GG4WAY_WITH_LIMMA.out.plots
    objects  = BIOC_GG4WAY_GG4WAY_WITH_LIMMA.out.objects
    versions = BIOC_GG4WAY_GG4WAY_WITH_LIMMA.out.versions
}
