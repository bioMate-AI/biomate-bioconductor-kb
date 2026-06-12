#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scBubbletree — sc_bubbletree_external_clustering
// Incorporate external clustering results (e.g., PAM/k-medoids) into the scBubbletree workflow to generate a hierarchical bubbletree and annotate it.
// Input: A, m
// Container: quay.io/biocontainers/bioconductor-scbubbletree:1.12.0--r45hdfd78af_0
// R packages: cluster, ggplot2, ggtree, patchwork, scBubbletree
// Bioconductor: 3.20 | R: 4.4
// Requires: cluster, ggplot2, ggtree, patchwork, scBubbletree
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Perform external clustering (PAM/k-medoids)
//  * 2. [Core Analysis] Generate a dummy bubbletree using get_bubbletree_dummy
//  * 3. [Core Analysis] Annotate the dummy bubbletree with categorical features

nextflow.enable.dsl = 2

process BIOC_SCBUBBLETREE_SC_BUBBLETREE_EXTERNAL_CLUSTERING {
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
    .bm_deps <- c("cluster", "ggplot2", "ggtree", "patchwork", "scBubbletree")
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
    library(scBubbletree)
    library(ggplot2)
    library(ggtree)
    library(patchwork)
    library(cluster)
    
    # Read user input files from the working directory
    if (file.exists("A.rds")) {
      A <- readRDS("A.rds")
    } else if (file.exists("A.csv")) {
      A <- as.matrix(read.csv("A.csv", row.names = 1))
    } else {
      stop("Required input file 'A' (PCA embedding matrix) not found in working directory (expected A.rds or A.csv).")
    }
    
    if (file.exists("m.rds")) {
      m <- readRDS("m.rds")
    } else if (file.exists("m.csv")) {
      m <- read.csv("m.csv", row.names = 1)
    } else {
      stop("Required input file 'm' (cell metadata dataframe) not found in working directory (expected m.rds or m.csv).")
    }
    
    # Ensure A is a numeric matrix
    A <- as.matrix(A)
    
    # --- Perform external clustering (PAM/k-medoids) ---
    pam_k5 <- cluster::pam(x = A, k = 5, metric = "euclidean")
    
    # --- Generate a dummy bubbletree using get_bubbletree_dummy ---
    dummy_k5_pam <- get_bubbletree_dummy(x = A,
                                         cs = pam_k5\$clustering,
                                         B = 200,
                                         N_eff = 200,
                                         cores = 2,
                                         round_digits = 1)
    
    # --- Annotate the dummy bubbletree with categorical features ---
    # and generate the combined plot
    p <- dummy_k5_pam\$tree |
      get_cat_tiles(btd = dummy_k5_pam, 
                    f = m[, 1],
                    integrate_vertical = TRUE,
                    round_digits = 1,
                    tile_text_size = 2.75,
                    x_axis_name = colnames(m)[1],
                    rotate_x_axis_labels = TRUE)\$plot
    
    # Save outputs
    # Save the combined plot as a PDF
    ggsave("bubbletree_pam_k5.pdf", plot = p, width = 10, height = 6)
    
    # Save the dummy bubbletree object as an RDS file
    saveRDS(dummy_k5_pam, "dummy_k5_pam.rds")
    
    # Save clustering results as a CSV
    clustering_df <- data.frame(
      cell_id = rownames(A),
      cluster = pam_k5\$clustering
    )
    write.csv(clustering_df, "pam_k5_clustering.csv", row.names = FALSE)
    
    # Save tree metadata as a CSV
    write.csv(dummy_k5_pam\$tree_meta, "dummy_k5_pam_tree_meta.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_SCBUBBLETREE_SC_BUBBLETREE_EXTERNAL_CLUSTERING":',
        paste0('    scBubbletree: ', as.character(packageVersion('scBubbletree')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sc_bubbletree_external_clustering.csv versions.yml
    """
}

workflow BIOC_SCBUBBLETREE_SC_BUBBLETREE_EXTERNAL_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ A, m ] ]

    main:
    BIOC_SCBUBBLETREE_SC_BUBBLETREE_EXTERNAL_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_SCBUBBLETREE_SC_BUBBLETREE_EXTERNAL_CLUSTERING.out.tables
    plots    = BIOC_SCBUBBLETREE_SC_BUBBLETREE_EXTERNAL_CLUSTERING.out.plots
    objects  = BIOC_SCBUBBLETREE_SC_BUBBLETREE_EXTERNAL_CLUSTERING.out.objects
    versions = BIOC_SCBUBBLETREE_SC_BUBBLETREE_EXTERNAL_CLUSTERING.out.versions
}
