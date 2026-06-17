#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: decoupleR — pathway_activity_scrnaseq
// Infer pathway activities from single-cell RNA-seq data using the PROGENy model and a multivariate linear model (MLM).
// Input: sc_data.rds
// Container: quay.io/biocontainers/bioconductor-decoupler:2.16.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Seurat, decoupleR, dplyr, ggplot2, pheatmap, tibble, tidyr
// Visualizations: heatmap, UMAP/t-SNE plot, feature plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load Seurat object
//  * 2. [Core Analysis] Retrieve PROGENy pathway-gene weights using get_progeny()
//  * 3. [Core Analysis] Extract normalized log-transformed counts matrix from Seurat object
//  * 4. [Core Analysis] Run Multivariate Linear Model using run_mlm()
//  * 5. [Core Analysis] Store inferred activities back into the Seurat object as a new assay
//  * 6. [Visualization & Output] Scale and visualize pathway activities

nextflow.enable.dsl = 2

process BIOC_DECOUPLER_PATHWAY_ACTIVITY_SCRNASEQ {
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
    .bm_deps <- c("Seurat", "decoupleR", "dplyr", "tibble", "tidyr", "ggplot2", "pheatmap")
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
    library(Seurat)
    library(decoupleR)
    library(dplyr)
    library(tibble)
    library(tidyr)
    library(ggplot2)
    library(pheatmap)
    
    # 1. Load Seurat object from the user input file
    data <- readRDS("sc_data.rds")
    
    # 2. Retrieve PROGENy pathway-gene weights using get_progeny()
    net <- get_progeny(organism = 'human', top = 500)
    
    # 3. Extract normalized log-transformed counts matrix from Seurat object
    mat <- as.matrix(data@assays\$RNA@data)
    
    # 4. Run Multivariate Linear Model using run_mlm()
    acts <- run_mlm(mat=mat, net=net, .source='source', .target='target', .mor='weight', minsize = 5)
    
    # 5. Store inferred activities back into the Seurat object as a new assay
    data[['pathwaysmlm']] <- acts %>% 
      pivot_wider(id_cols = 'source', names_from = 'condition', values_from = 'score') %>% 
      column_to_rownames('source') %>% 
      Seurat::CreateAssayObject(.)
    
    DefaultAssay(object = data) <- "pathwaysmlm"
    data <- ScaleData(data)
    data@assays\$pathwaysmlm@data <- data@assays\$pathwaysmlm@scale.data
    
    # Save the inferred activities table
    write.csv(acts, "pathway_activities_mlm.csv", row.names = FALSE)
    
    # Save the updated Seurat object
    saveRDS(data, "sc_data_with_pathways.rds")
    
    # 6. Visualize pathway activities and save to PDF
    pdf("pathway_activity_plots.pdf", width = 12, height = 8)
    
    # Try to plot UMAP and FeaturePlot if coordinates and identities exist
    tryCatch({
      p1 <- DimPlot(data, reduction = "umap", label = TRUE, pt.size = 0.5) + 
        NoLegend() + 
        ggtitle('Cell types')
      print(p1)
    }, error = function(e) {
      message("Could not generate DimPlot: ", e\$message)
    })
    
    tryCatch({
      p2 <- (FeaturePlot(data, features = c("Trail")) & 
               scale_colour_gradient2(low = 'blue', mid = 'white', high = 'red')) + 
        ggtitle('Trail activity')
      print(p2)
    }, error = function(e) {
      message("Could not generate FeaturePlot: ", e\$message)
    })
    
    # Generate heatmap of mean activity per cluster
    tryCatch({
      df <- t(as.matrix(data@assays\$pathwaysmlm@data)) %>% 
        as.data.frame() %>% 
        mutate(cluster = Idents(data)) %>% 
        pivot_longer(cols = -cluster, names_to = "source", values_to = "score") %>% 
        group_by(cluster, source) %>% 
        summarise(mean = mean(score), .groups = 'drop')
    
      top_acts_mat <- df %>% 
        pivot_wider(id_cols = 'cluster', names_from = 'source', values_from = 'mean') %>% 
        column_to_rownames('cluster') %>% 
        as.matrix()
    
      palette_length <- 100
      my_color <- colorRampPalette(c("Darkblue", "white", "red"))(palette_length)
      my_breaks <- c(seq(-2, 0, length.out=ceiling(palette_length/2) + 1), 
                     seq(0.05, 2, length.out=floor(palette_length/2)))
    
      pheatmap(top_acts_mat, border_color = NA, color=my_color, breaks = my_breaks, 
               main = "Mean Pathway Activity per Cluster")
    }, error = function(e) {
      message("Could not generate Heatmap: ", e\$message)
    })
    
    dev.off()

    writeLines(c(
        '"BIOC_DECOUPLER_PATHWAY_ACTIVITY_SCRNASEQ":',
        paste0('    decoupleR: ', as.character(packageVersion('decoupleR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pathway_activity_scrnaseq.csv versions.yml
    """
}

workflow BIOC_DECOUPLER_PATHWAY_ACTIVITY_SCRNASEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sc_data.rds ] ]

    main:
    BIOC_DECOUPLER_PATHWAY_ACTIVITY_SCRNASEQ(ch_input)

    emit:
    tables   = BIOC_DECOUPLER_PATHWAY_ACTIVITY_SCRNASEQ.out.tables
    plots    = BIOC_DECOUPLER_PATHWAY_ACTIVITY_SCRNASEQ.out.plots
    objects  = BIOC_DECOUPLER_PATHWAY_ACTIVITY_SCRNASEQ.out.objects
    versions = BIOC_DECOUPLER_PATHWAY_ACTIVITY_SCRNASEQ.out.versions
}
