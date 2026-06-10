#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: kegggraph — chemical_reaction_network_parsing
// Parse a metabolic pathway to build and analyze a chemical reaction network of compounds.
// Input: map00260.xml
// Container: quay.io/biocontainers/bioconductor-kegggraph:1.70.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_KEGGGRAPH_CHEMICAL_REACTION_NETWORK_PARSING {
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
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(KEGGgraph)
    
    # Define the input file in the working directory
    mapfile <- "map00260.xml"
    
    # Verify input file existence
    if (!file.exists(mapfile)) {
      stop(paste("Required input file missing:", mapfile))
    }
    
    # 1. Parse the KGML file into a KEGGPathway object
    map <- parseKGML(mapfile)
    
    # 2. Extract chemical reactions
    reactions <- getReactions(map)
    
    # 3. Convert the pathway into a reaction graph of chemical compounds
    chemicalGraph <- KEGGpathway2reactionGraph(map)
    
    # 4. Calculate compound out-degrees
    outDegrees <- sapply(edges(chemicalGraph), length)
    
    # Save meaningful results to output files
    # Save the reactions list as an RDS object
    saveRDS(reactions, file = "reactions.rds")
    
    # Save the chemical graph as an RDS object
    saveRDS(chemicalGraph, file = "chemical_graph.rds")
    
    # Save the out-degrees as a CSV table
    out_degrees_df <- data.frame(
      Compound = names(outDegrees),
      OutDegree = outDegrees,
      stringsAsFactors = FALSE
    )
    # Sort by out-degree descending
    out_degrees_df <- out_degrees_df[order(-out_degrees_df\$OutDegree), ]
    write.csv(out_degrees_df, file = "compound_out_degrees.csv", row.names = FALSE)
    
    # Generate a PDF plot of the chemical reaction network
    pdf("chemical_reaction_graph.pdf", width = 12, height = 12)
    tryCatch({
      library(Rgraphviz)
      
      # Identify top 3 compounds with maximum out-degree for highlighting
      maxout <- names(sort(outDegrees, decreasing = TRUE))[1:3]
      
      # Helper function to assign node attributes (reproduced from vignette)
      makeAttr <- function(graph, default, valNodeList) {
        tmp <- nodes(graph)
        x <- rep(default, length(tmp))
        names(x) <- tmp
        
        if(!missing(valNodeList)) {
          stopifnot(is.list(valNodeList))
          allnodes <- unlist(valNodeList)
          stopifnot(all(allnodes %in% tmp))
          for(i in seq(along = valNodeList)) {
            x[valNodeList[[i]]] <- names(valNodeList)[i]
          }
        }
        return(x)
      }
      
      nAttrs <- list()
      maxoutlabel <- as.list(maxout)
      names(maxoutlabel) <- maxout
      
      nAttrs\$label <- makeAttr(chemicalGraph, "", maxoutlabel)
      nAttrs\$fillcolor <- makeAttr(chemicalGraph, "lightblue", list(orange = maxout))
      nAttrs\$width <- makeAttr(chemicalGraph, "0.8", list("1.8" = maxout))
      
      plot(chemicalGraph, nodeAttrs = nAttrs, main = "Chemical Reaction Network (Glycine, serine and threonine metabolism)")
    }, error = function(e) {
      # Fallback if Rgraphviz is not available or fails
      plot(1, type = "n", axes = FALSE, xlab = "", ylab = "")
      text(1, 1, paste("Rgraphviz plotting failed or not installed:\n", e\$message), cex = 1.2)
    })
    dev.off()
    
    cat("Pipeline completed successfully. Outputs generated:\n")
    cat("- reactions.rds\n")
    cat("- chemical_graph.rds\n")
    cat("- compound_out_degrees.csv\n")
    cat("- chemical_reaction_graph.pdf\n")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_KEGGGRAPH_CHEMICAL_REACTION_NETWORK_PARSING":
        kegggraph: \$(Rscript -e 'cat(as.character(packageVersion("kegggraph")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chemical_reaction_network_parsing.csv versions.yml
    """
}

workflow BIOC_KEGGGRAPH_CHEMICAL_REACTION_NETWORK_PARSING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ map00260.xml ] ]

    main:
    BIOC_KEGGGRAPH_CHEMICAL_REACTION_NETWORK_PARSING(ch_input)

    emit:
    tables   = BIOC_KEGGGRAPH_CHEMICAL_REACTION_NETWORK_PARSING.out.tables
    plots    = BIOC_KEGGGRAPH_CHEMICAL_REACTION_NETWORK_PARSING.out.plots
    objects  = BIOC_KEGGGRAPH_CHEMICAL_REACTION_NETWORK_PARSING.out.objects
    versions = BIOC_KEGGGRAPH_CHEMICAL_REACTION_NETWORK_PARSING.out.versions
}
