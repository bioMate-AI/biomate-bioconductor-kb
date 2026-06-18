#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: NCIgraph — pathway_loading_and_parsing
// Load raw NCI pathways and parse them into gene-level graphNEL objects for downstream analysis and visualization.
// Input: NCI.demo.cyList
// Container: quay.io/biocontainers/bioconductor-ncigraph:1.58.0--r45hdfd78af_0
// R packages: graph, NCIgraph, Rgraphviz
// Bioconductor: 3.20 | R: 4.4
// Requires: NCIgraph, Rgraphviz, graph
// Visualizations: pathway diagram
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the NCIgraph package and the raw pathway data
//  * 2. [Input & Preparation] Parse the raw pathways to keep only Entrez-ID-associated nodes and optionally propagate regulation
//  * 3. [Visualization & Output] Visualize the raw and parsed pathways using Rgraphviz

nextflow.enable.dsl = 2

process BIOC_NCIGRAPH_PATHWAY_LOADING_AND_PARSING {
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
    .bm_deps <- c("graph", "NCIgraph", "Rgraphviz")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    library(NCIgraph)
    library(graph)
    library(Rgraphviz)
    
    # 1. Load the raw pathway data from the user input file
    input_file <- "NCI.demo.cyList"
    if (!file.exists(input_file)) {
      stop(paste("Error: Required input file '", input_file, "' not found in the working directory.", sep=""))
    }
    
    # Robust loading of NCI.demo.cyList (handles RDS or RData formats)
    NCI.demo.cyList <- tryCatch({
      readRDS(input_file)
    }, error = function(e) {
      env <- new.env()
      load(input_file, envir = env)
      if ("NCI.demo.cyList" %in% names(env)) {
        env\$NCI.demo.cyList
      } else {
        env[[ls(env)[1]]]
      }
    })
    
    # 2. Parse the raw pathways to keep only Entrez-ID-associated nodes
    grList <- getNCIPathways(cyList=NCI.demo.cyList, parseNetworks=TRUE, entrezOnly=TRUE, verbose=TRUE)\$pList
    
    # Save the parsed pathways to an RDS file
    saveRDS(grList, file = "parsed_pathways.rds")
    
    # Create a summary table of the pathways before and after parsing
    summary_df <- data.frame(
      Pathway_Index = seq_along(NCI.demo.cyList),
      Raw_Nodes = sapply(NCI.demo.cyList, numNodes),
      Raw_Edges = sapply(NCI.demo.cyList, numEdges),
      Parsed_Nodes = sapply(grList, function(g) if(!is.null(g)) numNodes(g) else 0),
      Parsed_Edges = sapply(grList, function(g) if(!is.null(g)) numEdges(g) else 0)
    )
    write.csv(summary_df, file = "pathway_summary.csv", row.names = FALSE)
    
    # 3. Visualize the raw and parsed pathways using Rgraphviz
    pdf("pathway_plots.pdf", width = 10, height = 10)
    
    # Plot Raw Pathway
    graph <- NCI.demo.cyList[[1]]
    gNames <- unlist(lapply(graph@nodeData@data,FUN=function(e) e\$biopax.name))
    names(gNames) <- nodes(graph)
    graph <- layoutGraph(graph)
    nodeRenderInfo(graph) <- list(label=gNames, cex=0.75)
    renderGraph(graph)  
    
    # Plot Parsed Pathway
    graph <- grList[[1]]
    gNames <- unlist(lapply(graph@nodeData@data,FUN=function(e) unique(e\$biopax.xref.ENTREZGENE)))
    names(gNames) <- nodes(graph)
    graph <- layoutGraph(graph)
    nodeRenderInfo(graph) <- list(label=gNames, cex=0.75)
    renderGraph(graph)
    
    dev.off()

    writeLines(c(
        '"BIOC_NCIGRAPH_PATHWAY_LOADING_AND_PARSING":',
        paste0('    NCIgraph: ', as.character(packageVersion('NCIgraph')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pathway_loading_and_parsing.csv versions.yml
    """
}

workflow BIOC_NCIGRAPH_PATHWAY_LOADING_AND_PARSING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ NCI.demo.cyList ] ]

    main:
    BIOC_NCIGRAPH_PATHWAY_LOADING_AND_PARSING(ch_input)

    emit:
    tables   = BIOC_NCIGRAPH_PATHWAY_LOADING_AND_PARSING.out.tables
    plots    = BIOC_NCIGRAPH_PATHWAY_LOADING_AND_PARSING.out.plots
    objects  = BIOC_NCIGRAPH_PATHWAY_LOADING_AND_PARSING.out.objects
    versions = BIOC_NCIGRAPH_PATHWAY_LOADING_AND_PARSING.out.versions
}
