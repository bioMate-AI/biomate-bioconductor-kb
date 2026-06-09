#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ggtreeExtra — same_position_multiple_layers
// Add multiple overlapping or co-located data layers on the exact same external panel/ring of a phylogenetic tree.
// Input: tree.nwk, associated_data.csv
// Container: quay.io/biocontainers/bioconductor-ggtreeextra:1.20.1--r45hdfd78af_0
// Requires: ggnewscale, ggplot2, ggstar, ggtree, ggtreeExtra, treeio
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Generate or read a phylogenetic tree
//  * 2. [Input & Preparation] Prepare associated datasets with matching tip labels
//  * 3. [Visualization & Output] Initialize the tree plot using ggtree
//  * 4. [Core Analysis] Add the first ring using geom_fruit
//  * 5. [Core Analysis] Reset the fill scale using new_scale_fill()
//  * 6. [Core Analysis] Add multiple layers to the second ring using geom_fruit_list, ensuring the first element is a geom_fruit layer, followed by scales
//  * 7. [Core Analysis] Reset the fill scale and add subsequent rings as needed

nextflow.enable.dsl = 2

process BIOC_GGTREEEXTRA_SAME_POSITION_MULTIPLE_LAYERS {
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
        library(ggtreeExtra)
        library(ggstar)
        library(ggplot2)
        library(ggtree)
        library(treeio)
        library(ggnewscale)
        
        # 1. Generate or read a phylogenetic tree
        if (!file.exists("tree.nwk")) {
          stop("Required input file 'tree.nwk' not found in the working directory.")
        }
        tr <- read.tree("tree.nwk")
        
        # 2. Prepare associated datasets with matching tip labels
        if (!file.exists("associated_data.csv")) {
          stop("Required input file 'associated_data.csv' not found in the working directory.")
        }
        dt <- read.csv("associated_data.csv")
        
        # Standardize column names to match the documented code expectations (id, value, group)
        id_col <- grep("id|ID|label|tip|taxa", colnames(dt), ignore.case = TRUE, value = TRUE)
        if (length(id_col) > 0) {
          colnames(dt)[colnames(dt) == id_col[1]] <- "id"
        } else {
          colnames(dt)[1] <- "id"
        }
        
        val_col <- grep("value|val|abundance|length", colnames(dt), ignore.case = TRUE, value = TRUE)
        if (length(val_col) > 0) {
          colnames(dt)[colnames(dt) == val_col[1]] <- "value"
        } else {
          colnames(dt)[2] <- "value"
        }
        
        grp_col <- grep("group|class|type", colnames(dt), ignore.case = TRUE, value = TRUE)
        if (length(grp_col) > 0) {
          colnames(dt)[colnames(dt) == grp_col[1]] <- "group"
        } else {
          colnames(dt)[3] <- "group"
        }
        
        # Ensure value is numeric
        dt\$value <- as.numeric(dt\$value)
        
        # Replicate the data preparation from the documented code
        df <- dt
        dtf <- dt
        colnames(df)[[3]] <- "group2"
        colnames(dtf)[[3]] <- "group3"
        
        # 3. Initialize the tree plot using ggtree
        p <- ggtree(tr, layout="fan", open.angle=0)
        
        # 4. Add the first ring using geom_fruit
        p1 <- p + 
              geom_fruit(
                  data = dt,
                  geom = geom_col,
                  mapping = aes(y=id, x=value, fill=group)
              ) + 
              # 5. Reset the fill scale using new_scale_fill()
              new_scale_fill()
        
        # Determine the number of unique groups to dynamically generate color palettes
        n_groups <- length(unique(dt\$group))
        
        # 6. Add multiple layers to the second ring using geom_fruit_list, ensuring the first element is a geom_fruit layer, followed by scales and additional geom_fruit layers
        p2 <- p1 + 
              geom_fruit_list(
                  geom_fruit(
                      data = df,
                      geom = geom_col,
                      mapping = aes(y=id, x=value, fill=group2)
                  ),
                  scale_fill_manual(values=colorRampPalette(c("blue", "red"))(n_groups)),
                  new_scale_fill(),
                  geom_fruit(
                      data = dt,
                      geom = geom_star,
                      mapping = aes(y=id, x=value, fill=group),
                      size = 2.5,
                      color = NA,
                      starstroke = 0
                  )
              ) + 
              # 7. Reset the fill scale and add subsequent rings as needed
              new_scale_fill()
        
        p3 <- p2 + 
              geom_fruit(
                  data = dtf,
                  geom = geom_col,
                  mapping = aes(y=id, x=value, fill=group3)
              ) +
              scale_fill_manual(values=colorRampPalette(c("#00AED7", "#009E73"))(n_groups))
        
        # Save the outputs
        ggsave("same_position_multiple_layers_plot.pdf", plot = p3, width = 10, height = 10)
        saveRDS(p3, "same_position_multiple_layers_plot.rds")
        write.csv(dt, "processed_associated_data.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_GGTREEEXTRA_SAME_POSITION_MULTIPLE_LAYERS":',
        paste0('    ggtreeExtra: ', as.character(packageVersion('ggtreeExtra')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_same_position_multiple_layers.csv versions.yml
    """
}

workflow BIOC_GGTREEEXTRA_SAME_POSITION_MULTIPLE_LAYERS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ tree.nwk, associated_data.csv ] ]

    main:
    BIOC_GGTREEEXTRA_SAME_POSITION_MULTIPLE_LAYERS(ch_input)

    emit:
    tables   = BIOC_GGTREEEXTRA_SAME_POSITION_MULTIPLE_LAYERS.out.tables
    plots    = BIOC_GGTREEEXTRA_SAME_POSITION_MULTIPLE_LAYERS.out.plots
    objects  = BIOC_GGTREEEXTRA_SAME_POSITION_MULTIPLE_LAYERS.out.objects
    versions = BIOC_GGTREEEXTRA_SAME_POSITION_MULTIPLE_LAYERS.out.versions
}
