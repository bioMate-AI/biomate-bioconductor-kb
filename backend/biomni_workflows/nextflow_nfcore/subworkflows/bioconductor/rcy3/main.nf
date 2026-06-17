#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RCy3 — network_from_data_frames_and_styling
// Create a network from node and edge data frames, apply custom visual styles (discrete and continuous mappings), and export the visualization.
// Input: nodes_df, edges_df
// Container: quay.io/biocontainers/bioconductor-rcy3:2.30.1--r45hdfd78af_0
// R packages: ndexr, RColorBrewer, RCy3
// Bioconductor: 3.20 | R: 4.4
// Requires: RCy3
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Verify Cytoscape connection
//  * 2. [Input & Preparation] Create network from data frames
//  * 3. [Input & Preparation] Define and apply custom visual style defaults and mappings
//  * 4. [Core Analysis] Select nodes and neighbors
//  * 5. [Visualization & Output] Save session and export high-resolution image

nextflow.enable.dsl = 2

process BIOC_RCY3_NETWORK_FROM_DATA_FRAMES_AND_STYLING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("ndexr", "RColorBrewer", "RCy3")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
        
        # Load required library
        library(RCy3)
        
        # 1. Verify Cytoscape connection
        cytoscapePing()
        cytoscapeVersionInfo()
        
        # Helper function to read user input files robustly
        read_input_file <- function(base_name) {
          if (file.exists(base_name)) {
            tryCatch({
              return(readRDS(base_name))
            }, error = function(e) {
              tryCatch({
                return(read.csv(base_name, stringsAsFactors=FALSE))
              }, error = function(e2) {
                stop(paste("Could not read file:", base_name))
              })
            })
          }
          
          extensions <- c(".csv", ".rds", ".tsv", ".txt")
          for (ext in extensions) {
            fp <- paste0(base_name, ext)
            if (file.exists(fp)) {
              if (ext == ".rds") {
                return(readRDS(fp))
              } else if (ext == ".csv") {
                return(read.csv(fp, stringsAsFactors=FALSE))
              } else {
                return(read.delim(fp, stringsAsFactors=FALSE))
              }
            }
          }
          stop(paste("File not found for:", base_name))
        }
        
        # Read user input files
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        nodes <- read_input_file("nodes_df")
        edges <- read_input_file("edges_df")
        
        # 2. Create network from data frames
        createNetworkFromDataFrames(nodes, edges, title="my first network", collection="DataFrame Example")
        
        # 3. Define and apply custom visual style defaults and mappings
        setVisualStyle('Marquee')
        style.name = "myStyle"
        defaults <- list(NODE_SHAPE="diamond", NODE_SIZE=30, EDGE_TRANSPARENCY=120, NODE_LABEL_POSITION="W,E,c,0.00,0.00")
        
        tryCatch({
          mapping_list <- list()
          
          if ("id" %in% colnames(nodes)) {
            mapping_list <- c(mapping_list, list(mapVisualProperty('node label','id','p')))
          } else if ("name" %in% colnames(nodes)) {
            mapping_list <- c(mapping_list, list(mapVisualProperty('node label','name','p')))
          }
          
          if ("group" %in% colnames(nodes)) {
            mapping_list <- c(mapping_list, list(mapVisualProperty('node fill color','group','d',c("A","B"), c("#FF9900","#66AAAA"))))
          }
          
          if ("interaction" %in% colnames(edges)) {
            mapping_list <- c(mapping_list, list(mapVisualProperty('Edge Target Arrow Shape','interaction','d',c("activates","inhibits","interacts"),c("Arrow","T","None"))))
          }
          
          if ("weight" %in% colnames(edges)) {
            mapping_list <- c(mapping_list, list(mapVisualProperty('edge width','weight','p')))
          }
          
          createVisualStyle(style.name, defaults, mapping_list)
          setVisualStyle(style.name)
        }, error = function(e) {
          warning("Could not create or apply visual style with mappings: ", e\$message)
          tryCatch({
            createVisualStyle(style.name, defaults, list())
            setVisualStyle(style.name)
          }, error = function(e2) {
            warning("Could not create fallback visual style: ", e2\$message)
          })
        })
        
        lockNodeDimensions(FALSE, style.name)
        setNodeShapeDefault ('OCTAGON')
        setNodeColorDefault ('#AAFF88')
        setNodeSizeDefault (60)
        setNodeFontSizeDefault (30)
        getNodeShapes ()
        
        # Apply mappings with tryCatch to handle potential missing columns in user data
        tryCatch({
          if ("moleculeType" %in% colnames(nodes)) {
            column <- 'moleculeType'
            values <- c ('kinase', 'TF','cytokine')
            shapes <- c ('DIAMOND', 'TRIANGLE', 'RECTANGLE')
            setNodeShapeMapping (column, values, shapes)
          }
        }, error = function(e) {
          warning("Could not apply moleculeType mapping: ", e\$message)
        })
        
        tryCatch({
          if ("log2fc" %in% colnames(nodes)) {
            column <- 'log2fc'
            control.points <- c (-3.0, 0.0, 3.0)
            colors <- c ('#5588DD', '#FFFFFF', '#DD8855')
            setNodeColorMapping (column, control.points, colors)
            
            control.points <- c (-2.0, 0.0, 2.0)
            colors <- c ('#2255CC', '#5588DD', '#FFFFFF', '#DD8855','#CC5522')
            setNodeColorMapping (column, control.points, colors)
            
            control.points = c (-3.0, 2.0, 3.0)
            sizes = c (20, 80, 90)
            setNodeSizeMapping (column, control.points, sizes)
          }
        }, error = function(e) {
          warning("Could not apply log2fc mapping: ", e\$message)
        })
        
        # 4. Select nodes and neighbors
        tryCatch({
          if (nrow(nodes) > 0 && ncol(nodes) > 0) {
            selectNodes (as.character(nodes[1, 1]), colnames(nodes)[1])
          }
          getSelectedNodes ()
          selectFirstNeighbors ()
          node.names <- getSelectedNodes ()
          write.csv(data.frame(selected_nodes = node.names), "selected_nodes.csv", row.names=FALSE)
          clearSelection()
        }, error = function(e) {
          warning("Could not perform node selection: ", e\$message)
          write.csv(data.frame(selected_nodes = character(0)), "selected_nodes.csv", row.names=FALSE)
        })
        
        # 5. Save session and export high-resolution image
        saveSession('vignette_session')
        full.path=paste(getwd(),'vignette_image',sep='/')
        exportImage(full.path, 'PNG', zoom=200)
        exportImage(full.path, 'PDF')
        
        # Write processed data frames as outputs
        write.csv(nodes, "processed_nodes.csv", row.names=FALSE)
        write.csv(edges, "processed_edges.csv", row.names=FALSE)

    writeLines(c(
        '"BIOC_RCY3_NETWORK_FROM_DATA_FRAMES_AND_STYLING":',
        paste0('    RCy3: ', as.character(packageVersion('RCy3')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_network_from_data_frames_and_styling.csv versions.yml
    """
}

workflow BIOC_RCY3_NETWORK_FROM_DATA_FRAMES_AND_STYLING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ nodes_df, edges_df ] ]

    main:
    BIOC_RCY3_NETWORK_FROM_DATA_FRAMES_AND_STYLING(ch_input)

    emit:
    tables   = BIOC_RCY3_NETWORK_FROM_DATA_FRAMES_AND_STYLING.out.tables
    plots    = BIOC_RCY3_NETWORK_FROM_DATA_FRAMES_AND_STYLING.out.plots
    objects  = BIOC_RCY3_NETWORK_FROM_DATA_FRAMES_AND_STYLING.out.objects
    versions = BIOC_RCY3_NETWORK_FROM_DATA_FRAMES_AND_STYLING.out.versions
}
