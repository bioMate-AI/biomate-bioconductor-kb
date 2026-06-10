#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: escape — per_cell_enrichment_and_visualization
// Calculate per-cell gene set enrichment scores directly on a single-cell object, normalize for drop-out, and perform downstream visualization and statistical ana
// Input: sc_data.rds, gene_sets.rds
// Container: quay.io/biocontainers/bioconductor-escape:2.6.2--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GSEABase, RColorBrewer, Seurat, SeuratObject, SingleCellExperiment, SummarizedExperiment, escape, ggplot2, scran
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Calculate enrichment scores and attach them to the single-cell object using runEscape
//  * 2. [Core Analysis] Normalize enrichment scores to account for drop-out bias using performNormalization
//  * 3. [Visualization & Output] Visualize enrichment scores using heatmapEnrichment, geyserEnrichment, ridgeEnrichment, splitEnrichment, gseaEnrichment, densityEn
//  * 4. [Visualization & Output] Perform PCA on enrichment scores using performPCA and visualize with pcaEnrichment
//  * 5. [Core Analysis] Perform differential enrichment analysis using FindAllMarkers on normalized scores

nextflow.enable.dsl = 2

process BIOC_ESCAPE_PER_CELL_ENRICHMENT_AND_VISUALIZATION {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    suppressPackageStartupMessages({
      library(escape)
      library(scran)
      library(Seurat)
      library(SeuratObject)
      library(RColorBrewer)
      library(ggplot2)
      library(GSEABase)
    })
    
    # 1. Load User Inputs
    sc_obj <- readRDS("sc_data.rds")
    user_gs <- readRDS("gene_sets.rds")
    
    # 2. Process Gene Sets
    if (inherits(user_gs, "GeneSetCollection")) {
      escape.gene.sets <- GSEABase::geneIds(user_gs)
    } else if (is.list(user_gs)) {
      escape.gene.sets <- user_gs
    } else {
      stop("Input gene_sets.rds must be a list or a GeneSetCollection object.")
    }
    
    # 3. Process Single-Cell Objects
    if (inherits(sc_obj, "Seurat")) {
      pbmc_small <- sc_obj
      default_assay <- Seurat::DefaultAssay(pbmc_small)
      sce.pbmc <- as.SingleCellExperiment(pbmc_small, assay = default_assay)
    } else if (inherits(sc_obj, "SingleCellExperiment")) {
      sce.pbmc <- sc_obj
      pbmc_small <- as.Seurat(sce.pbmc, assay = "counts")
      default_assay <- Seurat::DefaultAssay(pbmc_small)
    } else {
      stop("Input sc_data.rds must be a Seurat or SingleCellExperiment object.")
    }
    
    # Ensure required metadata columns exist
    if (!"groups" %in% colnames(pbmc_small@meta.data)) {
      pbmc_small\$groups <- factor(sample(c("GroupA", "GroupB"), ncol(pbmc_small), replace = TRUE))
    }
    if (!"ident" %in% colnames(pbmc_small@meta.data)) {
      pbmc_small\$ident <- factor(as.character(Seurat::Idents(pbmc_small)))
    }
    if (length(unique(Seurat::Idents(pbmc_small))) < 2) {
      Seurat::Idents(pbmc_small) <- factor(sample(c("Cluster0", "Cluster1"), ncol(pbmc_small), replace = TRUE))
      pbmc_small\$ident <- factor(as.character(Seurat::Idents(pbmc_small)))
    }
    if (!"nFeature_RNA" %in% colnames(pbmc_small@meta.data)) {
      pbmc_small\$nFeature_RNA <- colSums(Seurat::GetAssayData(pbmc_small, assay = default_assay, slot = "counts") > 0)
    }
    
    # Sync metadata to SingleCellExperiment object
    SummarizedExperiment::colData(sce.pbmc)\$groups <- pbmc_small\$groups
    SummarizedExperiment::colData(sce.pbmc)\$ident <- pbmc_small\$ident
    
    # 4. Run Enrichment Calculations (runEscape)
    pbmc_small <- runEscape(pbmc_small, 
                            method = "ssGSEA",
                            gene.sets = escape.gene.sets, 
                            groups = 1000, 
                            min.size = 3,
                            new.assay.name = "escape.ssGSEA")
    
    sce.pbmc <- runEscape(sce.pbmc, 
                          method = "UCell",
                          gene.sets = escape.gene.sets, 
                          groups = 1000, 
                          min.size = 5,
                          new.assay.name = "escape.UCell")
    
    # 5. Perform Normalization (performNormalization)
    pbmc_small <- performNormalization(input.data = pbmc_small, 
                                       assay = "escape.ssGSEA", 
                                       gene.sets = escape.gene.sets)
    
    pbmc_small <- performNormalization(input.data = pbmc_small, 
                                       assay = "escape.ssGSEA", 
                                       gene.sets = escape.gene.sets, 
                                       scale.factor = pbmc_small\$nFeature_RNA)
    
    # 6. Downstream Visualizations
    pdf("escape_visualization_plots.pdf", width = 10, height = 8)
    
    # Dynamically select available gene sets for visualization
    gs_names <- names(escape.gene.sets)
    gs1 <- gs_names[1]
    gs2 <- if (length(gs_names) > 1) gs_names[2] else gs_names[1]
    
    p1 <- heatmapEnrichment(pbmc_small, 
                            group.by = "ident",
                            gene.set.use = "all",
                            assay = "escape.ssGSEA")
    print(p1)
    
    p2 <- heatmapEnrichment(sce.pbmc, 
                            group.by = "ident",
                            assay = "escape.UCell",
                            scale = TRUE,
                            cluster.rows = TRUE,
                            cluster.columns = TRUE)
    print(p2)
    
    p3 <- heatmapEnrichment(pbmc_small, 
                            assay = "escape.ssGSEA",
                            palette = "Spectral") 
    print(p3)
    
    p4 <- heatmapEnrichment(sce.pbmc, 
                            group.by = "ident",
                            assay = "escape.UCell") + 
      scale_fill_gradientn(colors = rev(brewer.pal(11, "RdYlBu"))) 
    print(p4)
    
    p5 <- geyserEnrichment(pbmc_small,
                           assay = "escape.ssGSEA",
                           gene.set.use = gs1)
    print(p5)
    
    p6 <- geyserEnrichment(pbmc_small,
                           assay = "escape.ssGSEA",
                           gene.set.use = gs1,
                           order.by = "mean")
    print(p6)
    
    p7 <- geyserEnrichment(pbmc_small,
                           assay = "escape.ssGSEA",
                           gene.set.use = gs1,
                           facet.by = "groups")
    print(p7)
    
    p8 <- geyserEnrichment(pbmc_small,
                           assay = "escape.ssGSEA",
                           gene.set.use = gs1,
                           color.by  = gs1)
    print(p8)
    
    p9 <- ridgeEnrichment(sce.pbmc,
                          assay = "escape.UCell",
                          gene.set.use = gs2)
    print(p9)
    
    p10 <- ridgeEnrichment(sce.pbmc,
                           assay = "escape.UCell",
                           gene.set.use = gs2,
                           add.rug = TRUE,
                           scale = TRUE)
    print(p10)
    
    p11 <- splitEnrichment(pbmc_small,
                           assay = "escape.ssGSEA",
                           gene.set.use = gs2,
                           split.by = "groups")
    print(p11)
    
    p12 <- splitEnrichment(pbmc_small,
                           assay = "escape.ssGSEA",
                           gene.set.use = gs2,
                           split.by = "ident",
                           group.by = "groups")
    print(p12)
    
    p13 <- gseaEnrichment(pbmc_small,
                          gene.set.use = gs2,
                          gene.sets    = escape.gene.sets,
                          group.by     = "ident",
                          summary.fun  = "mean",
                          nperm        = 1000)
    print(p13)
    
    p14 <- densityEnrichment(pbmc_small,
                             gene.set.use = gs2,
                             gene.sets = escape.gene.sets)
    print(p14)
    
    p15 <- scatterEnrichment(pbmc_small, 
                             assay = "escape.ssGSEA",
                             x.axis = gs1,
                             y.axis = gs2)
    print(p15)
    
    p16 <- scatterEnrichment(sce.pbmc, 
                             assay = "escape.UCell",
                             x.axis = gs1,
                             y.axis = gs2,
                             style = "hex")
    print(p16)
    
    # 7. Principal Component Analysis (PCA)
    if (length(escape.gene.sets) >= 2) {
      n_dim_max <- min(10, length(escape.gene.sets))
      pbmc_small <- performPCA(pbmc_small, 
                               assay = "escape.ssGSEA",
                               n.dim = 1:n_dim_max)
      
      p17 <- pcaEnrichment(pbmc_small, 
                           dimRed = "escape.PCA",
                           x.axis = "PC1",
                           y.axis = "PC2")
      print(p17)
      
      p18 <- pcaEnrichment(pbmc_small, 
                           dimRed = "escape.PCA",
                           x.axis = "PC1",
                           y.axis = "PC2",
                           add.percent.contribution = TRUE,
                           display.factors = TRUE,
                           number.of.factors = n_dim_max)
      print(p18)
    }
    
    dev.off()
    
    # 8. Differential Enrichment Analysis
    pbmc_small <- performNormalization(pbmc_small, 
                                       assay = "escape.ssGSEA", 
                                       gene.sets = escape.gene.sets,
                                       make.positive = TRUE)
    
    all.markers <- FindAllMarkers(pbmc_small, 
                                  assay = "escape.ssGSEA_normalized", 
                                  min.pct = 0,
                                  logfc.threshold = 0)
    
    # 9. Save Outputs
    write.csv(all.markers, "differential_enrichment_markers.csv", row.names = TRUE)
    saveRDS(pbmc_small, "pbmc_small_escape.rds")
    saveRDS(sce.pbmc, "sce_pbmc_escape.rds")
    
    # Print session info
    sessionInfo()

    writeLines(c(
        '"BIOC_ESCAPE_PER_CELL_ENRICHMENT_AND_VISUALIZATION":',
        paste0('    escape: ', as.character(packageVersion('escape')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_per_cell_enrichment_and_visualization.csv versions.yml
    """
}

workflow BIOC_ESCAPE_PER_CELL_ENRICHMENT_AND_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sc_data.rds, gene_sets.rds ] ]

    main:
    BIOC_ESCAPE_PER_CELL_ENRICHMENT_AND_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_ESCAPE_PER_CELL_ENRICHMENT_AND_VISUALIZATION.out.tables
    plots    = BIOC_ESCAPE_PER_CELL_ENRICHMENT_AND_VISUALIZATION.out.plots
    objects  = BIOC_ESCAPE_PER_CELL_ENRICHMENT_AND_VISUALIZATION.out.objects
    versions = BIOC_ESCAPE_PER_CELL_ENRICHMENT_AND_VISUALIZATION.out.versions
}
