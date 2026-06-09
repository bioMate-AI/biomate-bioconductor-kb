#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: decoupleR — tf_activity_scrnaseq
// Infer transcription factor activities from single-cell RNA-seq data using the CollecTRI network and a univariate linear model (ULM).
// Input: sc_data.rds
// Container: quay.io/biocontainers/bioconductor-decoupler:2.16.0--r45hdfd78af_0
// Requires: Seurat, decoupleR, dplyr, pheatmap, tibble, tidyr
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load Seurat object
//  * 2. [Core Analysis] Retrieve CollecTRI network using get_collectri()
//  * 3. [Core Analysis] Extract normalized log-transformed counts matrix from Seurat object
//  * 4. [Core Analysis] Run Univariate Linear Model using run_ulm()
//  * 5. [Core Analysis] Store inferred TF activities back into the Seurat object as a new assay
//  * 6. [Visualization & Output] Scale and visualize TF activities

nextflow.enable.dsl = 2

process BIOC_DECOUPLER_TF_ACTIVITY_SCRNASEQ {
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
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load required libraries
    library(Seurat)
    library(decoupleR)
    library(dplyr)
    library(tibble)
    library(tidyr)
    library(pheatmap)
    
    # 1. Load Seurat object from the working directory
    if (!file.exists("sc_data.rds")) {
      stop("Input file 'sc_data.rds' not found in the working directory.")
    }
    data <- readRDS("sc_data.rds")
    
    # 2. Retrieve CollecTRI network using get_collectri()
    net <- get_collectri(organism='human', split_complexes=FALSE)
    
    # 3. Extract normalized log-transformed counts matrix from Seurat object
    mat <- as.matrix(data@assays\$RNA@data)
    
    # 4. Run Univariate Linear Model using run_ulm()
    acts <- run_ulm(mat=mat, net=net, .source='source', .target='target', .mor='mor', minsize = 5)
    
    # 5. Store inferred TF activities back into the Seurat object as a new assay
    data[['tfsulm']] <- acts %>% 
      pivot_wider(id_cols = 'source', names_from = 'condition', values_from = 'score') %>% 
      column_to_rownames('source') %>% 
      Seurat::CreateAssayObject(.)
    
    # 6. Scale and visualize TF activities
    DefaultAssay(object = data) <- "tfsulm"
    data <- ScaleData(data)
    data@assays\$tfsulm@data <- data@assays\$tfsulm@scale.data
    
    # Save the raw activities table
    write.csv(acts, "tf_activities_ulm.csv", row.names = FALSE)
    
    # Save the updated Seurat object
    saveRDS(data, "sc_data_with_tfsulm.rds")
    
    # Generate visualization: Heatmap of top 25 most variable TFs across cells
    pdf("tf_activity_heatmap.pdf", width = 10, height = 8)
    tryCatch({
      n_tfs <- 25
      tf_mat <- as.matrix(data@assays\$tfsulm@data)
      tf_vars <- apply(tf_mat, 1, sd)
      top_tfs <- names(sort(tf_vars, decreasing = TRUE))[1:min(n_tfs, length(tf_vars))]
      
      pheatmap(tf_mat[top_tfs, ], 
               show_colnames = FALSE, 
               main = "Top 25 Most Variable TF Activities (ULM)",
               color = colorRampPalette(c("darkblue", "white", "red"))(100))
    }, error = function(e) {
      message("Could not generate cell-level heatmap: ", e\$message)
    })
    dev.off()
    
    # Generate visualization: Mean TF activity per cluster (if identity classes are available)
    pdf("tf_activity_mean_heatmap.pdf", width = 8, height = 8)
    tryCatch({
      df <- t(as.matrix(data@assays\$tfsulm@data)) %>% 
        as.data.frame() %>% 
        mutate(cluster = Idents(data)) %>% 
        pivot_longer(cols = -cluster, names_to = "source", values_to = "score") %>% 
        group_by(cluster, source) %>% 
        summarise(mean = mean(score), .groups = 'drop')
      
      tfs <- df %>% 
        group_by(source) %>% 
        summarise(std = sd(mean), .groups = 'drop') %>% 
        arrange(-abs(std)) %>% 
        head(25) %>% 
        pull(source)
      
      top_acts_mat <- df %>% 
        filter(source %in% tfs) %>% 
        pivot_wider(id_cols = 'cluster', names_from = 'source', values_from = 'mean') %>% 
        column_to_rownames('cluster') %>% 
        as.matrix()
      
      palette_length = 100
      my_color = colorRampPalette(c("Darkblue", "white","red"))(palette_length)
      my_breaks <- c(seq(-3, 0, length.out=ceiling(palette_length/2) + 1), 
                     seq(0.05, 3, length.out=floor(palette_length/2)))
      
      pheatmap(top_acts_mat, border_color = NA, color=my_color, breaks = my_breaks,
               main = "Mean TF Activity per Cluster")
    }, error = function(e) {
      message("Could not generate cluster-level mean heatmap: ", e\$message)
    })
    dev.off()

    writeLines(c(
        '"BIOC_DECOUPLER_TF_ACTIVITY_SCRNASEQ":',
        paste0('    decoupleR: ', as.character(packageVersion('decoupleR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tf_activity_scrnaseq.csv versions.yml
    """
}

workflow BIOC_DECOUPLER_TF_ACTIVITY_SCRNASEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sc_data.rds ] ]

    main:
    BIOC_DECOUPLER_TF_ACTIVITY_SCRNASEQ(ch_input)

    emit:
    tables   = BIOC_DECOUPLER_TF_ACTIVITY_SCRNASEQ.out.tables
    plots    = BIOC_DECOUPLER_TF_ACTIVITY_SCRNASEQ.out.plots
    objects  = BIOC_DECOUPLER_TF_ACTIVITY_SCRNASEQ.out.objects
    versions = BIOC_DECOUPLER_TF_ACTIVITY_SCRNASEQ.out.versions
}
