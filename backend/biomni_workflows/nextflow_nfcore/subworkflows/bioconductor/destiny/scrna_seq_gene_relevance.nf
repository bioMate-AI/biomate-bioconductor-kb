#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: destiny — scrna_seq_gene_relevance
// Build diffusion maps from scRNA-seq data using different distance metrics and identify key driving genes via gene relevance.
// Input: allen_hvg
// Container: quay.io/biocontainers/bioconductor-destiny:3.24.0--r45ha27e39d_0
// R packages: SingleCellExperiment, destiny, ggplot2, gridExtra, purrr
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DESTINY_SCRNA_SEQ_GENE_RELEVANCE {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-destiny:3.24.0--r45ha27e39d_0"

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
    .bm_deps <- c("SingleCellExperiment", "destiny", "ggplot2", "gridExtra", "purrr")
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
    library(SingleCellExperiment)
    library(gridExtra)
    
    # Set seed for reproducibility
    set.seed(1)
    
    # Read the user input file (SingleCellExperiment object)
    allen_hvg <- readRDS("allen_hvg")
    
    # 1. Create DiffusionMap objects using multiple distance metrics
    dms <- c('euclidean', 'cosine', 'rankcor') %>% 
      set_names() %>% 
      map(~ DiffusionMap(allen_hvg, distance = ., knn_params = list(method = 'covertree')))
    
    # 2. Calculate gene relevance for each diffusion map
    grs <- map(dms, gene_relevance)
    
    # 3. Plot gene relevance to identify top driving genes
    gms <- imap(grs, function(gr, dist) plot(gr, iter_smooth = 0) + ggtitle(dist))
    
    # Save the DiffusionMap and Gene Relevance objects
    saveRDS(dms, "diffusion_maps.rds")
    saveRDS(grs, "gene_relevance.rds")
    
    # Save the plots to a PDF file
    pdf("gene_relevance_plots.pdf", width = 15, height = 5)
    grid.arrange(grobs = gms, ncol = 3)
    dev.off()
    
    # Extract top driving genes and save to CSV
    top_genes_list <- map(gms, function(p) {
      if (!is.null(p\$ids)) {
        return(p\$ids)
      } else {
        return(character(0))
      }
    })
    
    max_len <- max(map_int(top_genes_list, length), 0)
    if (max_len > 0) {
      top_genes_df <- as.data.frame(map(top_genes_list, function(x) {
        length(x) <- max_len
        x
      }))
      write.csv(top_genes_df, "top_driving_genes.csv", row.names = FALSE)
    }

    writeLines(c(
        '"BIOC_DESTINY_SCRNA_SEQ_GENE_RELEVANCE":',
        paste0('        destiny: ', as.character(packageVersion("destiny")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scrna_seq_gene_relevance.csv versions.yml
    """
}

workflow BIOC_DESTINY_SCRNA_SEQ_GENE_RELEVANCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ allen_hvg ] ]

    main:
    BIOC_DESTINY_SCRNA_SEQ_GENE_RELEVANCE(ch_input)

    emit:
    tables   = BIOC_DESTINY_SCRNA_SEQ_GENE_RELEVANCE.out.tables
    plots    = BIOC_DESTINY_SCRNA_SEQ_GENE_RELEVANCE.out.plots
    objects  = BIOC_DESTINY_SCRNA_SEQ_GENE_RELEVANCE.out.objects
    versions = BIOC_DESTINY_SCRNA_SEQ_GENE_RELEVANCE.out.versions
}
