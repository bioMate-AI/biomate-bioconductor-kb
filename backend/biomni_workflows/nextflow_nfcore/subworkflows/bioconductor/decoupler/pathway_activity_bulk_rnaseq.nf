#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: decoupleR — pathway_activity_bulk_rnaseq
// Infer pathway activities from bulk RNA-seq differential expression statistics (t-values) or counts using the PROGENy model and a multivariate linear model (MLM)
// Input: bk_data.rds
// Container: quay.io/biocontainers/bioconductor-decoupler:2.16.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: decoupleR, dplyr, ggplot2, ggrepel, pheatmap, tibble, tidyr
// Visualizations: heatmap, bar plot, scatter plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load bulk RNA-seq data
//  * 2. [Core Analysis] Extract normalized log-transformed counts and limma t-values
//  * 3. [Core Analysis] Retrieve PROGENy pathway-gene weights using get_progeny()
//  * 4. [Core Analysis] Run Multivariate Linear Model on counts or t-values using run_mlm()
//  * 5. [Visualization & Output] Visualize sample-specific or contrast-specific pathway activities

nextflow.enable.dsl = 2

process BIOC_DECOUPLER_PATHWAY_ACTIVITY_BULK_RNASEQ {
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
    
    # 1. Load required packages
    library(decoupleR)
    library(dplyr)
    library(tibble)
    library(tidyr)
    library(ggplot2)
    library(pheatmap)
    library(ggrepel)
    
    # 2. Load bulk RNA-seq data
    input_file <- "bk_data.rds"
    if (!file.exists(input_file)) {
      stop(paste("Error: Input file", input_file, "not found in the working directory."))
    }
    data <- readRDS(input_file)
    
    # 3. Extract normalized log-transformed counts and limma t-values
    counts <- data\$counts %>% 
      dplyr::mutate_if(~ any(is.na(.x)), ~ if_else(is.na(.x), 0, .x)) %>% 
      column_to_rownames(var = "gene") %>% 
      as.matrix()
    
    deg <- data\$limma_ttop %>% 
      select(ID, t) %>% 
      filter(!is.na(t)) %>% 
      column_to_rownames(var = "ID") %>% 
      as.matrix()
    
    # 4. Retrieve PROGENy pathway-gene weights using get_progeny()
    net <- get_progeny(organism = 'human', top = 500)
    
    # 5. Run Multivariate Linear Model on counts and t-values using run_mlm()
    sample_acts <- run_mlm(mat=counts, net=net, .source='source', .target='target', .mor='weight', minsize = 5)
    contrast_acts <- run_mlm(mat=deg, net=net, .source='source', .target='target', .mor='weight', minsize = 5)
    
    # 6. Save meaningful results to files
    write.csv(sample_acts, "sample_pathway_activities.csv", row.names = FALSE)
    write.csv(contrast_acts, "contrast_pathway_activities.csv", row.names = FALSE)
    saveRDS(sample_acts, "sample_pathway_activities.rds")
    saveRDS(contrast_acts, "contrast_pathway_activities.rds")
    
    # 7. Visualize sample-specific and contrast-specific pathway activities
    
    # (a) Heatmap of sample-specific pathway activities
    sample_acts_mat <- sample_acts %>% 
      pivot_wider(id_cols = 'condition', names_from = 'source', values_from = 'score') %>% 
      column_to_rownames('condition') %>% 
      as.matrix()
    
    # Scale per feature
    sample_acts_mat <- scale(sample_acts_mat)
    
    palette_length <- 100
    my_color <- colorRampPalette(c("Darkblue", "white", "red"))(palette_length)
    my_breaks <- c(seq(-3, 0, length.out=ceiling(palette_length/2) + 1), 
                   seq(0.05, 3, length.out=floor(palette_length/2)))
    
    pdf("sample_pathway_activities_heatmap.pdf", width = 8, height = 6)
    pheatmap(sample_acts_mat, border_color = NA, color=my_color, breaks = my_breaks)
    dev.off()
    
    # (b) Barplot of contrast-specific pathway activities
    p_contrast <- ggplot(contrast_acts, aes(x = reorder(source, score), y = score)) +
      geom_bar(aes(fill = score), stat = "identity") +
      scale_fill_gradient2(low = "darkblue", high = "indianred", mid = "whitesmoke", midpoint = 0) +
      theme_minimal() +
      theme(axis.title = element_text(face = "bold", size = 12),
            axis.text.x = element_text(angle = 45, hjust = 1, size = 10, face = "bold"),
            axis.text.y = element_text(size = 10, face = "bold"),
            panel.grid.major = element_blank(),
            panel.grid.minor = element_blank()) +
      xlab("Pathways") +
      ylab("Activity Score (t-value)") +
      ggtitle("Contrast-specific Pathway Activities (KO vs WT)")
    
    ggsave("contrast_pathway_activities_barplot.pdf", plot = p_contrast, width = 8, height = 6)
    
    # (c) Scatter plot of the most responsive genes in the MAPK pathway
    pathway <- 'MAPK'
    df <- net %>% 
      filter(source == pathway) %>% 
      arrange(target) %>% 
      mutate(ID = target, color = "3") %>% 
      column_to_rownames('target')
    
    inter <- sort(intersect(rownames(deg), rownames(df)))
    df <- df[inter, ]
    df['t_value'] <- deg[inter, ]
    
    df <- df %>% 
      mutate(color = if_else(weight > 0 & t_value > 0, '1', color)) %>% 
      mutate(color = if_else(weight > 0 & t_value < 0, '2', color)) %>% 
      mutate(color = if_else(weight < 0 & t_value > 0, '2', color)) %>% 
      mutate(color = if_else(weight < 0 & t_value < 0, '1', color))
    
    p_mapk <- ggplot(df, aes(x = weight, y = t_value, color = color)) +
      geom_point() +
      scale_colour_manual(values = c("red", "royalblue3", "grey")) +
      geom_label_repel(aes(label = ID), max.overlaps = 20) +
      theme_minimal() +
      theme(legend.position = "none") +
      geom_vline(xintercept = 0, linetype = 'dotted') +
      geom_hline(yintercept = 0, linetype = 'dotted') +
      ggtitle(paste(pathway, "Pathway Target Genes & t-values")) +
      xlab("Interaction Weight") +
      ylab("Gene t-value (Contrast)")
    
    ggsave("mapk_pathway_targets_scatter.pdf", plot = p_mapk, width = 8, height = 6)

    writeLines(c(
        '"BIOC_DECOUPLER_PATHWAY_ACTIVITY_BULK_RNASEQ":',
        paste0('    decoupleR: ', as.character(packageVersion('decoupleR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pathway_activity_bulk_rnaseq.csv versions.yml
    """
}

workflow BIOC_DECOUPLER_PATHWAY_ACTIVITY_BULK_RNASEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bk_data.rds ] ]

    main:
    BIOC_DECOUPLER_PATHWAY_ACTIVITY_BULK_RNASEQ(ch_input)

    emit:
    tables   = BIOC_DECOUPLER_PATHWAY_ACTIVITY_BULK_RNASEQ.out.tables
    plots    = BIOC_DECOUPLER_PATHWAY_ACTIVITY_BULK_RNASEQ.out.plots
    objects  = BIOC_DECOUPLER_PATHWAY_ACTIVITY_BULK_RNASEQ.out.objects
    versions = BIOC_DECOUPLER_PATHWAY_ACTIVITY_BULK_RNASEQ.out.versions
}
