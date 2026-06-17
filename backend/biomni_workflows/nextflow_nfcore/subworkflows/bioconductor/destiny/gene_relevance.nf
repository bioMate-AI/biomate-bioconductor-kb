#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: destiny — gene_relevance
// Identify and plot genes that are most relevant to the diffusion map's components.
// Input: allen_hvg
// Container: quay.io/biocontainers/bioconductor-destiny:3.24.0--r45ha27e39d_0
// R packages: SingleCellExperiment, destiny, ggplot2, purrr
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, cowplot, destiny, ggplot2, purrr
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create DiffusionMap with specific distance metric
//  * 2. [Core Analysis] Calculate gene relevance
//  * 3. [Visualization & Output] Plot gene relevance

nextflow.enable.dsl = 2

process BIOC_DESTINY_GENE_RELEVANCE {
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
    .bm_deps <- c("SingleCellExperiment", "destiny", "ggplot2", "purrr")
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
    library(destiny)
    library(purrr)
    library(ggplot2)
    
    # Set seed for reproducibility
    set.seed(1)
    
    # Read the input file from the working directory
    input_file <- "allen_hvg"
    if (file.exists("allen_hvg.rds")) {
      input_file <- "allen_hvg.rds"
    } else if (!file.exists("allen_hvg")) {
      stop("Error: Input file 'allen_hvg' or 'allen_hvg.rds' not found in the working directory.")
    }
    
    allen_hvg <- readRDS(input_file)
    
    # 1. Create DiffusionMap with specific distance metrics (exactly as documented)
    dms <- c ( 'euclidean' , 'cosine' , 'rankcor' ) %>% set_names () %>% map ( ~ DiffusionMap (allen_hvg, distance = ., knn_params = list ( method = 'covertree' )))
    
    # 2. Calculate gene relevance (exactly as documented)
    grs <- map (dms, gene_relevance)
    
    # 3. Plot gene relevance (exactly as documented)
    gms <- imap (grs, function (gr, dist) plot (gr, iter_smooth = 0 ) + ggtitle (dist))
    
    # Save the DiffusionMap objects
    saveRDS(dms, "diffusion_maps.rds")
    
    # Save the GeneRelevance objects
    saveRDS(grs, "gene_relevance.rds")
    
    # Save the plots to a PDF file
    pdf("gene_relevance_plots.pdf", width = 15, height = 5)
    if (requireNamespace("cowplot", quietly = TRUE)) {
      print(cowplot::plot_grid(plotlist = gms, nrow = 1))
    } else {
      for (p in gms) {
        print(p)
      }
    }
    dev.off()
    
    # Extract and save the ranked relevant genes to a CSV
    tryCatch({
      top_genes_list <- map(gms, ~ .\$ids)
      max_len <- max(lengths(top_genes_list))
      top_genes_df <- data.frame(rank = 1:max_len, stringsAsFactors = FALSE)
      for (nm in names(top_genes_list)) {
        top_genes_df[[nm]] <- c(top_genes_list[[nm]], rep(NA, max_len - length(top_genes_list[[nm]])))
      }
      write.csv(top_genes_df, "top_relevant_genes.csv", row.names = FALSE)
    }, error = function(e) {
      warning("Could not export gene relevance table to CSV: ", e\$message)
    })

    writeLines(c(
        '"BIOC_DESTINY_GENE_RELEVANCE":',
        paste0('    destiny: ', as.character(packageVersion('destiny')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gene_relevance.csv versions.yml
    """
}

workflow BIOC_DESTINY_GENE_RELEVANCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ allen_hvg ] ]

    main:
    BIOC_DESTINY_GENE_RELEVANCE(ch_input)

    emit:
    tables   = BIOC_DESTINY_GENE_RELEVANCE.out.tables
    plots    = BIOC_DESTINY_GENE_RELEVANCE.out.plots
    objects  = BIOC_DESTINY_GENE_RELEVANCE.out.objects
    versions = BIOC_DESTINY_GENE_RELEVANCE.out.versions
}
