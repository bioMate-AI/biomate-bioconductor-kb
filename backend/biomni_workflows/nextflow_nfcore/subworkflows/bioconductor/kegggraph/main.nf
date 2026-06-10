#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: kegggraph — pathway_parsing_and_topology_analysis
// Parse a KGML file into a gene-expanded graph and calculate node degrees to identify key regulatory genes.
// Input: hsa04010.xml
// Container: quay.io/biocontainers/bioconductor-kegggraph:1.70.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_KEGGGRAPH_PATHWAY_PARSING_AND_TOPOLOGY_ANALYSIS {
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
    .bm_deps <- c("biomart", "graph", "kegggraph", "rbgl", "rcolorbrewer", "rgraphviz", "spia")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(KEGGgraph)
    library(graph)
    
    # Define input file (must be present in the working directory)
    mapkKGML <- "hsa04010.xml"
    
    # Check if input file exists
    if (!file.exists(mapkKGML)) {
      stop(paste("Required input file", mapkKGML, "not found in the working directory."))
    }
    
    # 1. Parse the KGML file into a graphNEL object with gene expansion
    mapkG <- parseKGML2Graph(mapkKGML, expandGenes=TRUE)
    
    # 2. Extract node and edge information
    mapkNodes <- nodes(mapkG)
    mapkEdges <- edges(mapkG)
    
    # 3. Retrieve node-specific KEGG attributes
    mapkGnodedata <- getKEGGnodeData(mapkG)
    
    # 4. Calculate in-degrees and out-degrees to identify central regulatory nodes
    mapkGoutdegrees <- sapply(edges(mapkG), length)
    mapkGindegrees <- sapply(inEdges(mapkG), length)
    topouts <- sort(mapkGoutdegrees, decreasing=TRUE)
    topins <- sort(mapkGindegrees, decreasing=TRUE)
    
    # --- Save Outputs ---
    
    # Save the parsed graph object
    saveRDS(mapkG, file="mapk_graph.rds")
    
    # Save all node degrees
    degree_df <- data.frame(
      Node = names(mapkGoutdegrees),
      OutDegree = mapkGoutdegrees,
      InDegree = mapkGindegrees[names(mapkGoutdegrees)]
    )
    write.csv(degree_df, file="mapk_node_degrees.csv", row.names=FALSE)
    
    # Save top out-degrees and in-degrees
    write.csv(data.frame(Node = names(topouts), OutDegree = topouts), file="top_out_degrees.csv", row.names=FALSE)
    write.csv(data.frame(Node = names(topins), InDegree = topins), file="top_in_degrees.csv", row.names=FALSE)
    
    # Save node metadata
    node_names <- sapply(mapkGnodedata, getName)
    node_types <- sapply(mapkGnodedata, getType)
    node_display <- sapply(mapkGnodedata, getDisplayName)
    node_info_df <- data.frame(
      KEGGID = names(mapkGnodedata),
      Name = node_names,
      Type = node_types,
      DisplayName = node_display
    )
    write.csv(node_info_df, file="mapk_node_info.csv", row.names=FALSE)
    
    # Generate PDF plot of a subgraph of top central nodes
    pdf("mapk_top_nodes_subgraph.pdf", width=10, height=10)
    tryCatch({
      if (requireNamespace("Rgraphviz", quietly=TRUE)) {
        library(Rgraphviz)
        # Select top 15 out-degree and top 15 in-degree nodes
        top_nodes <- unique(c(names(topouts)[1:15], names(topins)[1:15]))
        subG <- subGraph(top_nodes, mapkG)
        plot(subG, main="MAPK Subgraph (Top Central Nodes)")
      } else {
        plot(1, type="n", axes=FALSE, xlab="", ylab="")
        text(1, 1, "Rgraphviz not available for plotting", cex=1.5)
      }
    }, error = function(e) {
      plot(1, type="n", axes=FALSE, xlab="", ylab="")
      text(1, 1, paste("Plotting failed:", e\$message), cex=1.2)
    })
    dev.off()
    
    cat("Pipeline completed successfully. Outputs saved to working directory.\n")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_KEGGGRAPH_PATHWAY_PARSING_AND_TOPOLOGY_ANALYSIS":
        kegggraph: \$(Rscript -e 'cat(as.character(packageVersion("kegggraph")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pathway_parsing_and_topology_analysis.csv versions.yml
    """
}

workflow BIOC_KEGGGRAPH_PATHWAY_PARSING_AND_TOPOLOGY_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ hsa04010.xml ] ]

    main:
    BIOC_KEGGGRAPH_PATHWAY_PARSING_AND_TOPOLOGY_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_KEGGGRAPH_PATHWAY_PARSING_AND_TOPOLOGY_ANALYSIS.out.tables
    plots    = BIOC_KEGGGRAPH_PATHWAY_PARSING_AND_TOPOLOGY_ANALYSIS.out.plots
    objects  = BIOC_KEGGGRAPH_PATHWAY_PARSING_AND_TOPOLOGY_ANALYSIS.out.objects
    versions = BIOC_KEGGGRAPH_PATHWAY_PARSING_AND_TOPOLOGY_ANALYSIS.out.versions
}
