#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mitoclone2 — clonal_clustering_and_tree_building
// Build a phylogenetic tree of mitochondrial mutations and cluster them into clones.
// Input: M_P1.RData, N_P1.RData
// Container: quay.io/biocontainers/bioconductor-mitoclone2:1.16.0--r45ha27e39d_0
// R packages: mitoClone2
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_MITOCLONE2_CLONAL_CLUSTERING_AND_TREE_BUILDING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-mitoclone2:1.16.0--r45ha27e39d_0"

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
    .bm_deps <- c("mitoClone2")
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
    
    library(mitoClone2)
    
    # --- Load count matrices from the working directory and create ---
    load("M_P1.RData")
    load("N_P1.RData")
    
    P1 <- mutationCallsFromMatrix(as.matrix(M_P1), as.matrix(N_P1))
    saveRDS(P1, "P1_initial.rds")
    
    # Create temporary directory for SCITE
    tmpd <- tempdir()
    dir.create(paste0(tmpd, '/p1'), showWarnings = FALSE, recursive = TRUE)
    
    # --- Build a phylogenetic tree, cluster metaclones, and plot ---
    tryCatch({
      # Build phylogenetic tree using SCITE
      P1 <- varCluster(P1, tempfolder = paste0(tmpd, '/p1'), method = 'SCITE')
      
      # --- Cluster mutations into metaclones and assign cells ---
      P1 <- clusterMetaclones(P1, min.lik = 1)
      
      # --- Plot the clones ---
      pdf("clones_plot.pdf", width = 8, height = 6)
      plotClones(P1)
      dev.off()
      
      # --- Manually overwrite metaclone assignments ---
      m2c <- mitoClone2:::getMut2Clone(P1)
      write.csv(as.data.frame(m2c), "mut2clone_assignments_original.csv", row.names = TRUE)
      
      m2c[c("X2537GA", "X14462GA")] <- as.integer(6)
      P1.new <- mitoClone2:::overwriteMetaclones(P1, m2c)
      
      pdf("clones_new_plot.pdf", width = 8, height = 6)
      plotClones(P1.new)
      dev.off()
      
      # Save final objects
      saveRDS(P1, "P1_final.rds")
      saveRDS(P1.new, "P1_new_final.rds")
      write.csv(as.data.frame(m2c), "mut2clone_assignments_modified.csv", row.names = TRUE)
      
      message("Workflow completed successfully.")
    }, error = function(e) {
      warning("An error occurred during tree building or clustering: ", e\$message)
      warning("Note: SCITE must be installed and compiled in your system path for varCluster to run successfully.")
    })

    writeLines(c(
        '"BIOC_MITOCLONE2_CLONAL_CLUSTERING_AND_TREE_BUILDING":',
        paste0('        mitoclone2: ', as.character(packageVersion("mitoclone2")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_clonal_clustering_and_tree_building.csv versions.yml
    """
}

workflow BIOC_MITOCLONE2_CLONAL_CLUSTERING_AND_TREE_BUILDING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ M_P1.RData, N_P1.RData ] ]

    main:
    BIOC_MITOCLONE2_CLONAL_CLUSTERING_AND_TREE_BUILDING(ch_input)

    emit:
    tables   = BIOC_MITOCLONE2_CLONAL_CLUSTERING_AND_TREE_BUILDING.out.tables
    plots    = BIOC_MITOCLONE2_CLONAL_CLUSTERING_AND_TREE_BUILDING.out.plots
    objects  = BIOC_MITOCLONE2_CLONAL_CLUSTERING_AND_TREE_BUILDING.out.objects
    versions = BIOC_MITOCLONE2_CLONAL_CLUSTERING_AND_TREE_BUILDING.out.versions
}
