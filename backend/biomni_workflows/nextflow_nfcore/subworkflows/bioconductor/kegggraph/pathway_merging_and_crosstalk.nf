#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: kegggraph — pathway_merging_and_crosstalk
// Merge multiple KEGG pathways to study crosstalk and shared nodes between biological processes.
// Input: hsa04010.xml, hsa04310.xml
// Container: quay.io/biocontainers/bioconductor-kegggraph:1.70.0--r45hdfd78af_0
// R packages: KEGGgraph, Rgraphviz
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_KEGGGRAPH_PATHWAY_MERGING_AND_CROSSTALK {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-kegggraph:1.70.0--r45hdfd78af_0"

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
    .bm_deps <- c("KEGGgraph", "Rgraphviz")
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
    library(KEGGgraph)
    
    # Define input file paths (read directly from the working directory)
    mapkKGML <- "hsa04010.xml"
    wntKGML <- "hsa04310.xml"
    
    # Verify input files exist before parsing
    if (!file.exists(mapkKGML)) {
      stop(paste("Required input file missing:", mapkKGML))
    }
    if (!file.exists(wntKGML)) {
      stop(paste("Required input file missing:", wntKGML))
    }
    
    # 1. Parse individual KGML files into graphs with gene expansion enabled
    mapkG <- parseKGML2Graph(mapkKGML, expandGenes=TRUE)
    wntG <- parseKGML2Graph(wntKGML, expandGenes=TRUE)
    
    # 2. Combine the parsed graphs into a named list
    graphs <- list(mapk=mapkG, wnt=wntG)
    
    # 3. Merge the graphs into a single unified network
    merged <- mergeGraphs(graphs)
    
    # --- Output Generation ---
    
    # Save the complete merged graph object as an RDS file
    saveRDS(merged, "merged_pathway_graph.rds")
    
    # Calculate node degrees (in-degree and out-degree) to study crosstalk hubs
    node_degrees <- data.frame(
      Node = nodes(merged),
      InDegree = sapply(inEdges(merged), length),
      OutDegree = sapply(edges(merged), length),
      stringsAsFactors = FALSE
    )
    
    # Identify which nodes are shared between the two pathways (crosstalk nodes)
    shared_nodes <- intersect(nodes(mapkG), nodes(wntG))
    node_degrees\$IsShared <- node_degrees\$Node %in% shared_nodes
    
    # Save the node degree and crosstalk status table as a CSV
    write.csv(node_degrees, "merged_node_degrees.csv", row.names = FALSE)
    
    # Generate a PDF plot of the crosstalk region (shared nodes and their neighbors)
    if (length(shared_nodes) > 0) {
      tryCatch({
        library(Rgraphviz)
        
        # Get shared nodes and their immediate neighbors in the merged graph
        neighbors <- unique(unlist(c(shared_nodes, 
                                     unlist(edges(merged)[shared_nodes]), 
                                     unlist(inEdges(merged)[shared_nodes]))))
        
        # Subset to a plottable size if necessary
        if (length(neighbors) > 60) {
          neighbors <- neighbors[1:60]
        }
        
        crosstalk_subgraph <- subGraph(neighbors, merged)
        
        # Set up node colors: orange for shared crosstalk nodes, lightblue for others
        node_colors <- rep("lightblue", length(nodes(crosstalk_subgraph)))
        names(node_colors) <- nodes(crosstalk_subgraph)
        node_colors[names(node_colors) %in% shared_nodes] <- "orange"
        
        nAttrs <- list(fillcolor = node_colors)
        
        pdf("crosstalk_subgraph.pdf", width = 10, height = 10)
        plot(crosstalk_subgraph, "neato", nodeAttrs = nAttrs,
             main = "MAPK-Wnt Crosstalk Subgraph\n(Orange nodes are shared between pathways)")
        dev.off()
      }, error = function(e) {
        warning("Could not generate PDF plot: ", e\$message)
      })
    }

    cat <<-END_VERSIONS > versions.yml
    "BIOC_KEGGGRAPH_PATHWAY_MERGING_AND_CROSSTALK":
        kegggraph: \$(Rscript -e 'cat(as.character(packageVersion("kegggraph")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pathway_merging_and_crosstalk.csv versions.yml
    """
}

workflow BIOC_KEGGGRAPH_PATHWAY_MERGING_AND_CROSSTALK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ hsa04010.xml, hsa04310.xml ] ]

    main:
    BIOC_KEGGGRAPH_PATHWAY_MERGING_AND_CROSSTALK(ch_input)

    emit:
    tables   = BIOC_KEGGGRAPH_PATHWAY_MERGING_AND_CROSSTALK.out.tables
    plots    = BIOC_KEGGGRAPH_PATHWAY_MERGING_AND_CROSSTALK.out.plots
    objects  = BIOC_KEGGGRAPH_PATHWAY_MERGING_AND_CROSSTALK.out.objects
    versions = BIOC_KEGGGRAPH_PATHWAY_MERGING_AND_CROSSTALK.out.versions
}
