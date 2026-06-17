#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: clustifyr — direct_object_annotation
// Annotate cell types directly on Seurat or SingleCellExperiment objects and return the updated object.
// Input: sce, so, cbmc_ref
// Container: quay.io/biocontainers/bioconductor-clustifyr:1.22.0--r45hdfd78af_0
// R packages: Seurat, SingleCellExperiment, clustifyr
// Bioconductor: 3.20 | R: 4.4
// Requires: Seurat, SingleCellExperiment, clustifyr
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run clustify on the SingleCellExperiment object with obj_out = TRUE
//  * 2. [Core Analysis] Run clustify on the Seurat object with obj_out = TRUE
//  * 3. [Core Analysis] Extract the assigned cell types and correlation values from the object metadata

nextflow.enable.dsl = 2

process BIOC_CLUSTIFYR_DIRECT_OBJECT_ANNOTATION {
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
    .bm_deps <- c("Seurat", "SingleCellExperiment", "clustifyr", "SummarizedExperiment")
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
    library(clustifyr)
    library(SummarizedExperiment)
    library(Seurat)
    
    # Read user input files from the working directory
    sce <- readRDS("sce")
    so <- readRDS("so")
    cbmc_ref <- readRDS("cbmc_ref")
    
    # Stage 1: Run clustify on the SingleCellExperiment object with obj_out = TRUE
    res_sce <- clustify(
        input = sce, # an SCE object
        ref_mat = cbmc_ref, # matrix of RNA-seq expression data for each cell type
        cluster_col = "clusters", # name of column in meta.data containing cell clusters
        obj_out = TRUE # output SCE object with cell type inserted as "type" column
    )
    
    # Stage 3 (Part 1): Extract the assigned cell types and correlation values from the SCE object metadata
    sce_extracted <- colData(res_sce)[, c("type", "r"), drop = FALSE]
    
    # Save SCE results
    write.csv(as.data.frame(sce_extracted), "sce_annotations.csv", row.names = TRUE)
    saveRDS(res_sce, "sce_annotated.rds")
    
    # Stage 2: Run clustify on the Seurat object with obj_out = TRUE
    res_so <- clustify(
        input = so, # a Seurat object
        ref_mat = cbmc_ref, # matrix of RNA-seq expression data for each cell type
        cluster_col = "seurat_clusters", # name of column in meta.data containing cell clusters
        obj_out = TRUE # output Seurat object with cell type inserted as "type" column
    )
    
    # Stage 3 (Part 2): Extract the assigned cell types and correlation values from the Seurat object metadata
    so_extracted <- res_so[[c("type", "r")]]
    
    # Save Seurat results
    write.csv(as.data.frame(so_extracted), "so_annotations.csv", row.names = TRUE)
    saveRDS(res_so, "so_annotated.rds")

    writeLines(c(
        '"BIOC_CLUSTIFYR_DIRECT_OBJECT_ANNOTATION":',
        paste0('    clustifyr: ', as.character(packageVersion('clustifyr')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_direct_object_annotation.csv versions.yml
    """
}

workflow BIOC_CLUSTIFYR_DIRECT_OBJECT_ANNOTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce, so, cbmc_ref ] ]

    main:
    BIOC_CLUSTIFYR_DIRECT_OBJECT_ANNOTATION(ch_input)

    emit:
    tables   = BIOC_CLUSTIFYR_DIRECT_OBJECT_ANNOTATION.out.tables
    plots    = BIOC_CLUSTIFYR_DIRECT_OBJECT_ANNOTATION.out.plots
    objects  = BIOC_CLUSTIFYR_DIRECT_OBJECT_ANNOTATION.out.objects
    versions = BIOC_CLUSTIFYR_DIRECT_OBJECT_ANNOTATION.out.versions
}
