#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scAnnotatR — cell_classification_pretrained
// Classify cell types in a single-cell RNA-seq dataset using pretrained models.
// Input: tirosh_mel80_example
// Container: quay.io/biocontainers/bioconductor-scannotatr:1.16.0--r45hdfd78af_0
// R packages: Seurat, scAnnotatR
// Bioconductor: 3.20 | R: 4.4
// Requires: Seurat, scAnnotatR
// Visualizations: UMAP/t-SNE plot, feature plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the scAnnotatR package
//  * 2. [Input & Preparation] Load the default pretrained models
//  * 3. [Input & Preparation] Load the single-cell dataset
//  * 4. [Core Analysis] Run cell classification using classify_cells
//  * 5. [Core Analysis] Inspect the classification results in the metadata
//  * 6. [Visualization & Output] Visualize the predicted cell types and prediction probabilities using Seurat plotting functions

nextflow.enable.dsl = 2

process BIOC_SCANNOTATR_CELL_CLASSIFICATION_PRETRAINED {
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
    .bm_deps <- c("Seurat", "scAnnotatR")
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
    
    # 1. Load the scAnnotatR and Seurat packages
    library(scAnnotatR)
    library(Seurat)
    
    # 2. Load the default pretrained models
    default_models <- load_models("default")
    print(names(default_models))
    print(default_models[['B cells']])
    
    # 3. Load the single-cell dataset from the user input file
    if (file.exists("tirosh_mel80_example")) {
      tirosh_mel80_example <- readRDS("tirosh_mel80_example")
    } else if (file.exists("tirosh_mel80_example.rds")) {
      tirosh_mel80_example <- readRDS("tirosh_mel80_example.rds")
    } else {
      stop("Error: Input file 'tirosh_mel80_example' or 'tirosh_mel80_example.rds' not found in the working directory.")
    }
    
    print(tirosh_mel80_example)
    print(head(tirosh_mel80_example[[]]))
    
    # 4. Run cell classification using classify_cells
    seurat.obj <- classify_cells(classify_obj = tirosh_mel80_example, 
                                 assay = 'RNA', layer = 'counts',
                                 cell_types = c('B cells', 'NK', 'T cells'), 
                                 path_to_models = 'default')
    
    # 5. Inspect the classification results in the metadata
    metadata_subset <- seurat.obj[[]][c(50:60), c(8:ncol(seurat.obj[[]]))]
    print(metadata_subset)
    
    # Save the full metadata and the subset to CSV files
    write.csv(seurat.obj[[]], "classified_cells_metadata.csv", row.names = TRUE)
    write.csv(metadata_subset, "classified_cells_metadata_subset.csv", row.names = TRUE)
    
    # Save the classified Seurat object
    saveRDS(seurat.obj, "classified_seurat_object.rds")
    
    # 6. Visualize the predicted cell types and prediction probabilities using Seurat plotting functions
    pdf("cell_classification_plots.pdf", width = 10, height = 8)
    
    # Visualize the cell types
    p1 <- Seurat::DimPlot(seurat.obj, group.by = "most_probable_cell_type")
    print(p1)
    
    # Visualize the B cell prediction probability
    p2 <- Seurat::FeaturePlot(seurat.obj, features = "B_cells_p")
    print(p2)
    
    # Visualize canonical marker expression
    p3 <- Seurat::FeaturePlot(seurat.obj, features = c("CD19", "MS4A1"), ncol = 2)
    print(p3)
    
    dev.off()
    
    print("Pipeline completed successfully. Outputs saved: 'classified_seurat_object.rds', 'classified_cells_metadata.csv', 'classified_cells_metadata_subset.csv', and 'cell_classification_plots.pdf'.")

    writeLines(c(
        '"BIOC_SCANNOTATR_CELL_CLASSIFICATION_PRETRAINED":',
        paste0('    scAnnotatR: ', as.character(packageVersion('scAnnotatR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cell_classification_pretrained.csv versions.yml
    """
}

workflow BIOC_SCANNOTATR_CELL_CLASSIFICATION_PRETRAINED_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ tirosh_mel80_example ] ]

    main:
    BIOC_SCANNOTATR_CELL_CLASSIFICATION_PRETRAINED(ch_input)

    emit:
    tables   = BIOC_SCANNOTATR_CELL_CLASSIFICATION_PRETRAINED.out.tables
    plots    = BIOC_SCANNOTATR_CELL_CLASSIFICATION_PRETRAINED.out.plots
    objects  = BIOC_SCANNOTATR_CELL_CLASSIFICATION_PRETRAINED.out.objects
    versions = BIOC_SCANNOTATR_CELL_CLASSIFICATION_PRETRAINED.out.versions
}
