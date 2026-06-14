#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RedeR — tree_and_leaf_diagrams
// Convert a hierarchical clustering object into a tree-and-leaf diagram, map experimental variables to node colors and sizes, and visualize it using a force-direc
// Input: iris
// Container: quay.io/biocontainers/bioconductor-reder:3.6.0--r45hdfd78af_0
// R packages: RedeR, TreeAndLeaf, igraph
// Bioconductor: 3.20 | R: 4.4
// Requires: RedeR, TreeAndLeaf, igraph
// Visualizations: phylogenetic tree
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Perform hierarchical clustering on the input dataset using hclust
//  * 2. [Core Analysis] Convert the hclust object into a tree-and-leaf igraph object using treeAndLeaf
//  * 3. [Core Analysis] Map dataset variables to the tree-and-leaf graph using att.mapv
//  * 4. [Core Analysis] Set node colors and sizes based on variables using att.setv
//  * 5. [Core Analysis] Clear node labels and set edge colors using igraph shortcuts
//  * 6. [Core Analysis] Send the tree-and-leaf graph to RedeR using addGraphToRedeR
//  * 7. [Core Analysis] Anchor inner (non-leaf) nodes using selectNodes with anchor=TRUE
//  * 8. [Core Analysis] Fine-tune the layout of leaf nodes using relaxRedeR
//  * 9. [Core Analysis] Add legends for node color and size using addLegendToRedeR

nextflow.enable.dsl = 2

process BIOC_REDER_TREE_AND_LEAF_DIAGRAMS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("RedeR", "TreeAndLeaf", "igraph")
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
        
        # Load required packages
        library("RedeR")
        library("igraph")
        library("TreeAndLeaf")
        
        # -------------------------------------------------------------------------
        # 1. Read User Input File
        # -------------------------------------------------------------------------
        # The pipeline must read the 'iris' file from the working directory.
        if (file.exists("iris")) {
          iris_data <- read.csv("iris", stringsAsFactors = TRUE)
        } else if (file.exists("iris.csv")) {
          iris_data <- read.csv("iris.csv", stringsAsFactors = TRUE)
        } else {
          stop("Required input file 'iris' or 'iris.csv' not found in the working directory.")
        }
        
        # Ensure row names are set correctly for mapping
        if ("X" %in% colnames(iris_data)) {
          rownames(iris_data) <- iris_data\$X
          iris_data\$X <- NULL
        } else if (!is.numeric(iris_data[[1]]) && !any(duplicated(iris_data[[1]]))) {
          rownames(iris_data) <- iris_data[[1]]
          iris_data <- iris_data[, -1, drop = FALSE]
        } else {
          rownames(iris_data) <- as.character(1:nrow(iris_data))
        }
        
        # Assign to 'iris' to match the documented code variables
        iris <- iris_data
        
        # -------------------------------------------------------------------------
        # 2. Perform Hierarchical Clustering
        # -------------------------------------------------------------------------
        hc_iris <- hclust(dist(iris[,-5]))
        
        # -------------------------------------------------------------------------
        # 3. Convert to Tree-and-Leaf Object
        # -------------------------------------------------------------------------
        tal <- treeAndLeaf(hc_iris)
        
        # -------------------------------------------------------------------------
        # 4. Map Dataset Variables to the Graph
        # -------------------------------------------------------------------------
        tal <- att.mapv(g = tal, dat = iris, refcol = 0)
        
        # -------------------------------------------------------------------------
        # 5. Set Node Colors and Sizes Based on Variables
        # -------------------------------------------------------------------------
        cols <- c("#80b1d3","#fb8072","#8dd3c7")
        tal <- att.setv(tal, from="Species", to="nodeColor", cols=cols)
        tal <- att.setv(tal, from="Species", to="nodeLineColor", cols=cols)	
        tal <- att.setv(tal, from="Petal.Width", to="nodeSize", nquant=6, xlim=c(5,50,1))
        
        # -------------------------------------------------------------------------
        # 6. Clear Node Labels and Set Edge Colors Using igraph Shortcuts
        # -------------------------------------------------------------------------
        V(tal)\$nodeLabel <- ""
        E(tal)\$edgeLineColor <- "grey70"
        
        # -------------------------------------------------------------------------
        # 7. Visualize in RedeR (Wrapped in tryCatch for Headless/Non-GUI Environments)
        # -------------------------------------------------------------------------
        tryCatch({
          # Initialize/Reset RedeR
          startRedeR()
          resetRedeR()
          
          # Send the tree-and-leaf graph to RedeR
          addGraphToRedeR(tal, zoom=50)
          
          # Anchor inner (non-leaf) nodes
          selectNodes(V(tal)\$name[!V(tal)\$isLeaf], anchor=TRUE)
          
          # Fine-tune the layout of leaf nodes using relaxRedeR
          relaxRedeR(p1=10, p2=100, p3=5, p4=120, p5=1, p6=100)
          
          # Add legends for node color and size
          addLegendToRedeR(tal, type="nodecolor", title="Species", stretch=0.2)
          addLegendToRedeR(tal, type="nodesize", title="PetalWidth")
        }, error = function(e) {
          message("Note: RedeR Java application interface not available or failed to initialize: ", e\$message)
          message("Proceeding to write static outputs.")
        })
        
        # -------------------------------------------------------------------------
        # 8. Write Meaningful Output Files
        # -------------------------------------------------------------------------
        # Save the hierarchical clustering object
        saveRDS(hc_iris, file = "hc_iris.rds")
        
        # Save the final tree-and-leaf igraph object
        saveRDS(tal, file = "tree_and_leaf_graph.rds")
        
        # Generate a static PDF plot of the tree-and-leaf diagram as a fallback/record
        pdf("tree_and_leaf_plot.pdf", width = 10, height = 10)
        plot(
          tal,
          vertex.color = V(tal)\$nodeColor,
          vertex.size = V(tal)\$nodeSize / 5, # Scale down node size for standard igraph plotting
          vertex.frame.color = V(tal)\$nodeLineColor,
          vertex.label = NA,
          edge.color = E(tal)\$edgeLineColor,
          main = "Tree-and-Leaf Diagram (Iris Dataset)"
        )
        legend(
          "bottomleft",
          legend = unique(iris\$Species),
          col = cols,
          pch = 19,
          title = "Species",
          bty = "n"
        )
        dev.off()
        
        message("Pipeline completed successfully. Outputs written to 'hc_iris.rds', 'tree_and_leaf_graph.rds', and 'tree_and_leaf_plot.pdf'.")

    writeLines(c(
        '"BIOC_REDER_TREE_AND_LEAF_DIAGRAMS":',
        paste0('    RedeR: ', as.character(packageVersion('RedeR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tree_and_leaf_diagrams.csv versions.yml
    """
}

workflow BIOC_REDER_TREE_AND_LEAF_DIAGRAMS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ iris ] ]

    main:
    BIOC_REDER_TREE_AND_LEAF_DIAGRAMS(ch_input)

    emit:
    tables   = BIOC_REDER_TREE_AND_LEAF_DIAGRAMS.out.tables
    plots    = BIOC_REDER_TREE_AND_LEAF_DIAGRAMS.out.plots
    objects  = BIOC_REDER_TREE_AND_LEAF_DIAGRAMS.out.objects
    versions = BIOC_REDER_TREE_AND_LEAF_DIAGRAMS.out.versions
}
