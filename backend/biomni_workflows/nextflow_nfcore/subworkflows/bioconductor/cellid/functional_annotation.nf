#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CelliD — functional_annotation
// Perform per-cell functional enrichment analysis against biological pathways or ontologies to interpret cell states.
// Input: expression_matrix.rds, metadata.rds, pathway_genesets.rds
// Container: quay.io/biocontainers/bioconductor-cellid:1.18.0--r45ha27e39d_0
// R packages: CelliD, Seurat, ggpubr, tidyverse
// Bioconductor: 3.20 | R: 4.4
// Requires: CelliD, Seurat, ggpubr, tidyverse
// Visualizations: feature plot, enrichment plot
// QC: highly-variable feature selection
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Preprocess and run MCA on the dataset
//  * 2. [Core Analysis] Assess per-cell enrichment against functional pathways using RunCellHGT
//  * 3. [Core Analysis] Integrate enrichment scores as a new assay slot in the Seurat object using CreateAssayObject
//  * 4. [Visualization & Output] Visualize enrichment scores on a dimensionality reduction plot using FeaturePlot

nextflow.enable.dsl = 2

process BIOC_CELLID_FUNCTIONAL_ANNOTATION {
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
    .bm_deps <- c("CelliD", "Seurat", "ggpubr", "tidyverse")
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
        
    library(CelliD)
    library(Seurat)
    library(tidyverse)
    library(ggpubr)
    
    # 1. Read the declared user input files
    counts <- readRDS("expression_matrix.rds")
    metadata <- readRDS("metadata.rds")
    Hallmark <- readRDS("pathway_genesets.rds")
    
    # 2. Preprocess and run MCA on the dataset
    Seger <- CreateSeuratObject(counts = counts, min.cells = 5, meta.data = metadata)
    Seger <- NormalizeData(Seger)
    Seger <- FindVariableFeatures(Seger)
    Seger <- ScaleData(Seger)
    
    # Run MCA (required for CelliD)
    Seger <- RunMCA(Seger, nmcs = 50)
    
    # Run PCA and tSNE (required for FeaturePlot visualization using reduction = "tsne")
    Seger <- RunPCA(Seger, features = VariableFeatures(Seger))
    Seger <- RunTSNE(Seger, dims = 1:30)
    
    # 3. Assess per-cell enrichment against functional pathways using RunCellHGT (Documented Code)
    HGT_Hallmark <- RunCellHGT(Seger, pathways = Hallmark, dims = 1:50)
    
    # 4. Integrate enrichment scores as a new assay slot in the Seurat object (Documented Code)
    Seger[["Hallmark"]] <- CreateAssayObject(HGT_Hallmark)
    
    # 5. Visualize enrichment scores on a dimensionality reduction plot (Documented Code)
    # Dynamically select the first pathway for plotting, replacing underscores with dashes as Seurat does
    plot_feature <- gsub("_", "-", names(Hallmark)[1])
    
    ggG2Mcell <- FeaturePlot(Seger, plot_feature, order = TRUE, reduction = "tsne", min.cutoff = 2) + 
      theme(legend.text = element_text(size =10), aspect.ratio = 1)
    
    # 6. Write named output files for the meaningful results
    saveRDS(Seger, "seger_annotated.rds")
    write.csv(as.data.frame(HGT_Hallmark), "HGT_Hallmark_scores.csv", row.names = TRUE)
    
    pdf("g2m_checkpoint_enrichment_plot.pdf", width = 6, height = 6)
    print(ggG2Mcell)
    dev.off()

    writeLines(c(
        '"BIOC_CELLID_FUNCTIONAL_ANNOTATION":',
        paste0('    CelliD: ', as.character(packageVersion('CelliD')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_functional_annotation.csv versions.yml
    """
}

workflow BIOC_CELLID_FUNCTIONAL_ANNOTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.rds, metadata.rds, pathway_genesets.rds ] ]

    main:
    BIOC_CELLID_FUNCTIONAL_ANNOTATION(ch_input)

    emit:
    tables   = BIOC_CELLID_FUNCTIONAL_ANNOTATION.out.tables
    plots    = BIOC_CELLID_FUNCTIONAL_ANNOTATION.out.plots
    objects  = BIOC_CELLID_FUNCTIONAL_ANNOTATION.out.objects
    versions = BIOC_CELLID_FUNCTIONAL_ANNOTATION.out.versions
}
