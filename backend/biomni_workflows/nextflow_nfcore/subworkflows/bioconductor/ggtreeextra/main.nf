#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ggtreeExtra — sequential_external_layers
// Align multiple sequential data layers (such as tip points, heatmaps, and bar charts) to the outer rings of a phylogenetic tree.
// Input: tree.nwk, tree_tippoint_bar.csv, first_ring_discrete.csv, second_ring_continuous.csv
// Container: quay.io/biocontainers/bioconductor-ggtreeextra:1.20.1--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ggnewscale, ggplot2, ggstar, ggtree, ggtreeExtra, treeio
// Visualizations: phylogenetic tree
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read the phylogenetic tree using read.tree
//  * 2. [Input & Preparation] Read the associated datasets using read.csv
//  * 3. [Visualization & Output] Initialize the tree plot using ggtree with a circular/fan layout
//  * 4. [Core Analysis] Add the first layer (star points) using geom_fruit with position="identity"
//  * 5. [Core Analysis] Reset the fill scale using new_scale_fill()
//  * 6. [Visualization & Output] Add the second layer (discrete heatmap) using geom_fruit with geom=geom_tile
//  * 7. [Core Analysis] Reset the fill scale using new_scale_fill()
//  * 8. [Visualization & Output] Add the third layer (continuous heatmap) using geom_fruit with geom=geom_tile and axis parameters
//  * 9. [Core Analysis] Reset the fill scale using new_scale_fill()
//  * 10. [Visualization & Output] Add the fourth layer (bar plot) using geom_fruit with geom=geom_col, axis parameters, and grid parameters

nextflow.enable.dsl = 2

process BIOC_GGTREEEXTRA_SEQUENTIAL_EXTERNAL_LAYERS {
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
    .bm_deps <- c("ggtreeExtra", "ggstar", "ggplot2", "ggtree", "treeio", "ggnewscale")
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
    library(ggtreeExtra)
    library(ggstar)
    library(ggplot2)
    library(ggtree)
    library(treeio)
    library(ggnewscale)
    
    # 1. Read the phylogenetic tree using read.tree
    tree <- read.tree("tree.nwk")
    
    # 2. Read the associated datasets using read.csv
    dat1 <- read.csv("tree_tippoint_bar.csv")
    dat2 <- read.csv("first_ring_discrete.csv")
    dat3 <- read.csv("second_ring_continuous.csv")
    
    # 3. Initialize the tree plot using ggtree with a circular/fan layout
    p <- ggtree(tree, layout="fan", open.angle=10, size=0.5)
    
    # 4. Add the first layer (star points) using geom_fruit with position="identity"
    p2 <- p + 
          geom_fruit(
              data=dat1,
              geom=geom_star,
              mapping=aes(y=ID, fill=Location, size=Length, starshape=Group),
              position="identity",
              starstroke=0.2
          ) + 
          scale_size_continuous(
              range=c(1, 3),
              guide=guide_legend(
                        keywidth=0.5, 
                        keyheight=0.5,
                        override.aes=list(starshape=15),
                        order=2
                    )
          ) +
          scale_fill_manual(
              values=c("#F8766D", "#C49A00", "#53B400", "#00C094", "#00B6EB", "#A58AFF", "#FB61D7"),
              guide="none" 
          ) + 
          scale_starshape_manual(
              values=c(1, 15),
              guide=guide_legend(
                        keywidth=0.5,
                        keyheight=0.5,
                        order=1
                    )
          )
    
    # 5. Reset the fill scale using new_scale_fill()
    # 6. Add the second layer (discrete heatmap) using geom_fruit with geom=geom_tile
    p3 <- p2 + 
          new_scale_fill() + 
          geom_fruit(
              data=dat2,
              geom=geom_tile,
              mapping=aes(y=ID, x=Pos, fill=Type),
              offset=0.08,
              pwidth=0.25
          ) + 
          scale_fill_manual(
              values=c("#339933", "#dfac03"),
              guide=guide_legend(keywidth=0.5, keyheight=0.5, order=3)
          ) 
    
    # 7. Reset the fill scale using new_scale_fill()
    # 8. Add the third layer (continuous heatmap) using geom_fruit with geom=geom_tile and axis parameters
    p4 <- p3 + 
          new_scale_fill() +
          geom_fruit(
              data=dat3,
              geom=geom_tile,
              mapping=aes(y=ID, x=Type2, alpha=Alpha, fill=Type2),
              pwidth=0.15,
              axis.params=list(
                              axis="x",
                              text.angle=-45,
                              hjust=0
                          )
          ) +
          scale_fill_manual(
              values=c("#b22222", "#005500", "#0000be", "#9f1f9f"),
              guide=guide_legend(keywidth=0.5, keyheight=0.5, order=4)
          ) +
          scale_alpha_continuous(
              range=c(0, 0.4),
              guide=guide_legend(keywidth=0.5, keyheight=0.5, order=5)
          ) 
    
    # 9. Reset the fill scale using new_scale_fill()
    # 10. Add the fourth layer (bar plot) using geom_fruit with geom=geom_col, axis parameters, and grid parameters
    p5 <- p4 + 
          new_scale_fill() +
          geom_fruit(
              data=dat1,
              geom=geom_col,
              mapping=aes(y=ID, x=Abundance, fill=Location),
              pwidth=0.4,
              axis.params=list(
                              axis="x",
                              text.angle=-45,
                              hjust=0
                          ),
              grid.params=list()
          ) + 
          scale_fill_manual(
              values=c("#F8766D", "#C49A00", "#53B400", "#00C094", "#00B6EB", "#A58AFF", "#FB61D7"),
              guide=guide_legend(keywidth=0.5, keyheight=0.5, order=6)
          ) +
          theme(
              legend.background=element_rect(fill=NA),
              legend.title=element_text(size=7),
              legend.text=element_text(size=6),
              legend.spacing.y = unit(0.02, "cm")
          )
    
    # Save the final plot and the plot object
    ggsave("sequential_external_layers_plot.pdf", plot=p5, width=10, height=10)
    saveRDS(p5, "sequential_external_layers_plot.rds")

    writeLines(c(
        '"BIOC_GGTREEEXTRA_SEQUENTIAL_EXTERNAL_LAYERS":',
        paste0('    ggtreeExtra: ', as.character(packageVersion('ggtreeExtra')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sequential_external_layers.csv versions.yml
    """
}

workflow BIOC_GGTREEEXTRA_SEQUENTIAL_EXTERNAL_LAYERS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ tree.nwk, tree_tippoint_bar.csv, first_ring_discrete.csv, second_ring_continuous.csv ] ]

    main:
    BIOC_GGTREEEXTRA_SEQUENTIAL_EXTERNAL_LAYERS(ch_input)

    emit:
    tables   = BIOC_GGTREEEXTRA_SEQUENTIAL_EXTERNAL_LAYERS.out.tables
    plots    = BIOC_GGTREEEXTRA_SEQUENTIAL_EXTERNAL_LAYERS.out.plots
    objects  = BIOC_GGTREEEXTRA_SEQUENTIAL_EXTERNAL_LAYERS.out.objects
    versions = BIOC_GGTREEEXTRA_SEQUENTIAL_EXTERNAL_LAYERS.out.versions
}
