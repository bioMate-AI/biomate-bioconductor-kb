#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Mfuzz — global_cluster_structure_analysis
// Analyze the overlap, coupling, and global relationships between clusters to evaluate cluster stability and sub-cluster emergence across different cluster number
// Input: yeast.s, cl
// Container: quay.io/biocontainers/bioconductor-mfuzz:2.70.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, Mfuzz
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Calculate the overlap/coupling matrix between clusters using overlap
//  * 2. [Visualization & Output] Visualise the cluster overlap structure using overlap.plot
//  * 3. [Core Analysis] Perform clustering with alternative cluster numbers (c) to examine sub-cluster emergence and global structures

nextflow.enable.dsl = 2

process BIOC_MFUZZ_GLOBAL_CLUSTER_STRUCTURE_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20-slim"

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
    .bm_deps <- c("Mfuzz", "Biobase")
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
    library(Mfuzz)
    library(Biobase)
    
    # ----------------------------------------------------------------------
    # 1. Read User Input Files
    # ----------------------------------------------------------------------
    # The pipeline reads the standardized ExpressionSet and the clustering result
    # from the working directory.
    yeast.s <- readRDS("yeast.s")
    cl <- readRDS("cl")
    
    # ----------------------------------------------------------------------
    # 2. Global Cluster Structure Analysis (Documented Workflow)
    # ----------------------------------------------------------------------
    
    # Calculate the overlap/coupling matrix between clusters for the initial clustering
    O <- overlap(cl)
    write.csv(O, file = "overlap_matrix_cl.csv", row.names = TRUE)
    
    # Visualise the cluster overlap structure and save the projection coordinates (Ptmp)
    pdf("overlap_plot_cl.pdf", width = 7, height = 7)
    Ptmp <- overlap.plot(cl, over = O, thres = 0.05)
    dev.off()
    
    # Perform clustering with alternative cluster number c = 10
    cl3 <- mfuzz(yeast.s, c = 10, m = 1.25)
    saveRDS(cl3, file = "cl3.rds")
    
    # Plot the clusters for c = 10
    pdf("mfuzz_plot_cl3.pdf", width = 10, height = 8)
    mfuzz.plot(yeast.s, cl = cl3, mfrow = c(3, 4))
    dev.off()
    
    # Calculate overlap for c = 10
    O3 <- overlap(cl3)
    write.csv(O3, file = "overlap_matrix_cl3.csv", row.names = TRUE)
    
    # Visualise overlap for c = 10 using the same projection coordinates
    pdf("overlap_plot_cl3.pdf", width = 7, height = 7)
    overlap.plot(cl3, over = O3, P = Ptmp, thres = 0.05)
    dev.off()
    
    # Perform clustering with alternative cluster number c = 25
    cl4 <- mfuzz(yeast.s, c = 25, m = 1.25)
    saveRDS(cl4, file = "cl4.rds")
    
    # Plot the clusters for c = 25
    pdf("mfuzz_plot_cl4.pdf", width = 12, height = 12)
    mfuzz.plot(yeast.s, cl = cl4, mfrow = c(5, 5))
    dev.off()
    
    # Calculate overlap for c = 25
    O4 <- overlap(cl4)
    write.csv(O4, file = "overlap_matrix_cl4.csv", row.names = TRUE)
    
    # Visualise overlap for c = 25 using the same projection coordinates
    pdf("overlap_plot_cl4.pdf", width = 7, height = 7)
    overlap.plot(cl4, over = O4, P = Ptmp, thres = 0.05)
    dev.off()

    writeLines(c(
        '"BIOC_MFUZZ_GLOBAL_CLUSTER_STRUCTURE_ANALYSIS":',
        paste0('    Mfuzz: ', as.character(packageVersion('Mfuzz')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_global_cluster_structure_analysis.csv versions.yml
    """
}

workflow BIOC_MFUZZ_GLOBAL_CLUSTER_STRUCTURE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ yeast.s, cl ] ]

    main:
    BIOC_MFUZZ_GLOBAL_CLUSTER_STRUCTURE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MFUZZ_GLOBAL_CLUSTER_STRUCTURE_ANALYSIS.out.tables
    plots    = BIOC_MFUZZ_GLOBAL_CLUSTER_STRUCTURE_ANALYSIS.out.plots
    objects  = BIOC_MFUZZ_GLOBAL_CLUSTER_STRUCTURE_ANALYSIS.out.objects
    versions = BIOC_MFUZZ_GLOBAL_CLUSTER_STRUCTURE_ANALYSIS.out.versions
}
