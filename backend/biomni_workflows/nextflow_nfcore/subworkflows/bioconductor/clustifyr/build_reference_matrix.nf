#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: clustifyr — build_reference_matrix
// Generate a reference expression matrix from single-cell expression data by averaging cluster expression.
// Input: pbmc_matrix, pbmc_meta, sce, so
// Container: quay.io/biocontainers/bioconductor-clustifyr:1.22.0--r45hdfd78af_0
// R packages: Seurat, SingleCellExperiment, clustifyr
// Bioconductor: 3.20 | R: 4.4
// Requires: Seurat, SingleCellExperiment, clustifyr
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Average expression of a single-cell matrix by cluster using average_clusters
//  * 2. [Core Analysis] Generate a reference matrix from a SingleCellExperiment object using object_ref
//  * 3. [Core Analysis] Generate a reference matrix from a Seurat object using seurat_ref

nextflow.enable.dsl = 2

process BIOC_CLUSTIFYR_BUILD_REFERENCE_MATRIX {
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
    .bm_deps <- c("Seurat", "SingleCellExperiment", "clustifyr")
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
    library(Seurat)
    
    # ==========================================
    # 1. Read User Input Files
    # ==========================================
    # The pipeline reads the declared user input files from the working directory.
    pbmc_matrix <- readRDS("pbmc_matrix.rds")
    pbmc_meta   <- readRDS("pbmc_meta.rds")
    sce         <- readRDS("sce.rds")
    so          <- readRDS("so.rds")
    
    # ==========================================
    # 2. Build Reference Matrices
    # ==========================================
    
    # Stage 1: Average expression of a single-cell matrix by cluster using average_clusters
    new_ref_matrix <- average_clusters(
        mat = pbmc_matrix,
        metadata = pbmc_meta\$classified, # or use metadata = pbmc_meta, cluster_col = "classified"
        if_log = TRUE # whether the expression matrix is already log transformed
    )
    
    print("Head of new_ref_matrix:")
    print(head(new_ref_matrix))
    
    # Stage 2: Generate a reference matrix from a SingleCellExperiment object using object_ref
    new_ref_matrix_sce <- object_ref(
        input = sce, # SCE object
        cluster_col = "clusters" # name of column in colData containing cell identities
    )
    
    # Stage 3: Generate a reference matrix from a Seurat object using seurat_ref
    new_ref_matrix_so <- seurat_ref(
        seurat_object = so, # Seurat object
        cluster_col = "seurat_clusters" # name of column in meta.data containing cell identities
    )
    
    print("Tail of new_ref_matrix_so:")
    print(tail(new_ref_matrix_so))
    
    # ==========================================
    # 3. Save Outputs
    # ==========================================
    # Save the generated reference matrices as RDS and CSV files
    saveRDS(new_ref_matrix, "new_ref_matrix.rds")
    write.csv(as.data.frame(new_ref_matrix), "new_ref_matrix.csv", row.names = TRUE)
    
    saveRDS(new_ref_matrix_sce, "new_ref_matrix_sce.rds")
    write.csv(as.data.frame(new_ref_matrix_sce), "new_ref_matrix_sce.csv", row.names = TRUE)
    
    saveRDS(new_ref_matrix_so, "new_ref_matrix_so.rds")
    write.csv(as.data.frame(new_ref_matrix_so), "new_ref_matrix_so.csv", row.names = TRUE)
    
    print("Pipeline completed successfully. Outputs saved.")

    writeLines(c(
        '"BIOC_CLUSTIFYR_BUILD_REFERENCE_MATRIX":',
        paste0('    clustifyr: ', as.character(packageVersion('clustifyr')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_build_reference_matrix.csv versions.yml
    """
}

workflow BIOC_CLUSTIFYR_BUILD_REFERENCE_MATRIX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pbmc_matrix, pbmc_meta, sce, so ] ]

    main:
    BIOC_CLUSTIFYR_BUILD_REFERENCE_MATRIX(ch_input)

    emit:
    tables   = BIOC_CLUSTIFYR_BUILD_REFERENCE_MATRIX.out.tables
    plots    = BIOC_CLUSTIFYR_BUILD_REFERENCE_MATRIX.out.plots
    objects  = BIOC_CLUSTIFYR_BUILD_REFERENCE_MATRIX.out.objects
    versions = BIOC_CLUSTIFYR_BUILD_REFERENCE_MATRIX.out.versions
}
