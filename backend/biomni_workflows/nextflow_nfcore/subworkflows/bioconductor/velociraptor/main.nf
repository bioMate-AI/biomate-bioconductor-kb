#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: velociraptor — rna_velocity_scvelo
// Calculate RNA velocity from spliced and unspliced single-cell RNA-seq counts, project the velocity vectors onto a low-dimensional embedding, and visualize the g
// Input: sce
// Container: quay.io/biocontainers/bioconductor-velociraptor:1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, ggplot2, scater, scran, scuttle, velociraptor
// Visualizations: t-SNE plot
// QC: cell QC metrics, count normalization, highly-variable feature selection
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Feature selection (identifying highly variable genes using scran)
//  * 2. [Core Analysis] RNA velocity estimation using scvelo()
//  * 3. [Core Analysis] Dimensionality reduction (PCA and t-SNE)
//  * 4. [Core Analysis] Velocity embedding projection using embedVelocity()
//  * 5. [Visualization & Output] Grid-based summarization of velocity vectors using gridVectors()
//  * 6. [Visualization & Output] Visualization of velocity pseudotime and vectors using ggplot2

nextflow.enable.dsl = 2

process BIOC_VELOCIRAPTOR_RNA_VELOCITY_SCVELO {
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
    .bm_deps <- c("scuttle", "scran", "velociraptor", "scater", "ggplot2")
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
    library(scuttle)
    library(scran)
    library(velociraptor)
    library(scater)
    library(ggplot2)
    
    # 1. Read User Input
    sce_path <- "sce"
    if (!file.exists(sce_path) && file.exists("sce.rds")) {
      sce_path <- "sce.rds"
    }
    sce <- readRDS(sce_path)
    
    # 2. Feature selection (identifying highly variable genes using scran)
    sce <- logNormCounts(sce, assay.type=1)
    dec <- modelGeneVar(sce)
    top.hvgs <- getTopHVGs(dec, n=2000)
    
    # 3. RNA velocity estimation using scvelo()
    velo.out <- scvelo(
      sce, subset.row=top.hvgs, assay.X="spliced",
      scvelo.params=list(neighbors=list(n_neighbors=30L))
    )
    
    # 4. Dimensionality reduction (PCA and t-SNE)
    set.seed(100)
    sce <- runPCA(sce, subset_row=top.hvgs)
    sce <- runTSNE(sce, dimred="PCA", perplexity = 30)
    
    sce\$velocity_pseudotime <- velo.out\$velocity_pseudotime
    
    # 5. Velocity embedding projection using embedVelocity()
    embedded <- embedVelocity(reducedDim(sce, "TSNE"), velo.out)
    
    # 6. Grid-based summarization of velocity vectors using gridVectors()
    grid.df <- gridVectors(sce, embedded, use.dimred = "TSNE")
    
    # 7. Visualization of velocity pseudotime and vectors using ggplot2
    p <- plotTSNE(sce, colour_by="velocity_pseudotime") +
        geom_segment(data=grid.df, mapping=aes(x=start.1, y=start.2, 
            xend=end.1, yend=end.2, colour=NULL), arrow=arrow(length=unit(0.05, "inches")))
    
    # Save outputs
    ggsave("velocity_tsne_plot.pdf", plot = p, width = 8, height = 7)
    write.csv(as.data.frame(grid.df), "grid_vectors.csv", row.names = FALSE)
    
    pseudotime_df <- data.frame(
      Cell = colnames(sce),
      velocity_pseudotime = sce\$velocity_pseudotime
    )
    write.csv(pseudotime_df, "velocity_pseudotime.csv", row.names = FALSE)
    
    saveRDS(velo.out, "velo_out.rds")
    saveRDS(sce, "sce_output.rds")

    writeLines(c(
        '"BIOC_VELOCIRAPTOR_RNA_VELOCITY_SCVELO":',
        paste0('    velociraptor: ', as.character(packageVersion('velociraptor')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rna_velocity_scvelo.csv versions.yml
    """
}

workflow BIOC_VELOCIRAPTOR_RNA_VELOCITY_SCVELO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce ] ]

    main:
    BIOC_VELOCIRAPTOR_RNA_VELOCITY_SCVELO(ch_input)

    emit:
    tables   = BIOC_VELOCIRAPTOR_RNA_VELOCITY_SCVELO.out.tables
    plots    = BIOC_VELOCIRAPTOR_RNA_VELOCITY_SCVELO.out.plots
    objects  = BIOC_VELOCIRAPTOR_RNA_VELOCITY_SCVELO.out.objects
    versions = BIOC_VELOCIRAPTOR_RNA_VELOCITY_SCVELO.out.versions
}
