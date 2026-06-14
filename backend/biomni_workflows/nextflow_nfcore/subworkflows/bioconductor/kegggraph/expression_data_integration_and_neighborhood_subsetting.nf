#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: kegggraph — expression_data_integration_and_neighborhood_subsetting
// Map differential expression data onto a KEGG pathway graph and subset the graph to focus on active gene neighborhoods.
// Input: hsa05210.xml, DE_Colorectal, ALL_Colorectal
// Container: quay.io/biocontainers/bioconductor-kegggraph:1.70.0--r45hdfd78af_0
// R packages: KEGGgraph, RBGL, RColorBrewer, Rgraphviz, org.Hs.eg.db
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_KEGGGRAPH_EXPRESSION_DATA_INTEGRATION_AND_NEIGHBORHOOD_SUBSETTING {
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
    .bm_deps <- c("KEGGgraph", "RBGL", "RColorBrewer", "Rgraphviz", "org.Hs.eg.db")
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
    library(org.Hs.eg.db)
    library(RColorBrewer)
    library(Rgraphviz)
    library(RBGL)
    
    # --- Read User Input Files ---
    # Read DE_Colorectal (Named numeric vector of log fold changes with Entrez IDs as names)
    if (file.exists("DE_Colorectal")) {
      DE_Colorectal <- tryCatch({
        readRDS("DE_Colorectal")
      }, error = function(e) {
        tab <- read.table("DE_Colorectal", header=FALSE, stringsAsFactors=FALSE)
        val <- as.numeric(tab[[2]])
        names(val) <- as.character(tab[[1]])
        val
      })
    } else {
      stop("Required input file 'DE_Colorectal' not found in the working directory.")
    }
    
    # Read ALL_Colorectal (Character vector of all detected Entrez IDs)
    if (file.exists("ALL_Colorectal")) {
      ALL_Colorectal <- tryCatch({
        readRDS("ALL_Colorectal")
      }, error = function(e) {
        as.character(readLines("ALL_Colorectal"))
      })
    } else {
      stop("Required input file 'ALL_Colorectal' not found in the working directory.")
    }
    
    # Colorectal cancer pathway KGML file
    colFile <- "hsa05210.xml"
    if (!file.exists(colFile)) {
      stop("Required input file 'hsa05210.xml' not found in the working directory.")
    }
    
    # --- Parse the pathway KGML file into a graph ---
    g <- parseKGML2Graph(colFile)
    
    # --- Translate Entrez IDs to KEGG IDs ---
    deKID <- translateGeneID2KEGGID(names(DE_Colorectal))
    allKID <- translateGeneID2KEGGID(ALL_Colorectal)
    isDiffExp <- nodes(g) %in% deKID
    
    # Define logfcs for the nodes in the graph (as documented in the vignette)
    logfcs <- DE_Colorectal[match(nodes(g), deKID)]
    names(logfcs) <- nodes(g)
    logfcs[is.na(logfcs)] <- 0
    
    # --- Identify upregulated genes ---
    ups <- nodes(g)[logfcs > 0]
    
    # --- Find the neighborhood of upregulated genes and subset the ---
    upNs <- unique(unlist(neighborhood(g, ups, return.self=TRUE)))
    upSub <- subKEGGgraph(upNs, g)
    
    # --- Save meaningful results ---
    # Save the subsetted graph as an RDS object
    saveRDS(upSub, "upSub_graph.rds")
    
    # Translate KEGG IDs to Gene Symbols and Entrez IDs for the output table
    upSub_nodes <- nodes(upSub)
    upSub_entrez <- translateKEGGID2GeneID(upSub_nodes)
    upSub_symbols <- sapply(upSub_entrez, function(x) {
      sym <- mget(x, org.Hs.egSYMBOL, ifnotfound=NA)[[1]]
      if (is.na(sym)) x else sym
    })
    
    # Create a summary data frame and write to CSV
    summary_df <- data.frame(
      KEGG_ID = upSub_nodes,
      Entrez_ID = upSub_entrez,
      Symbol = upSub_symbols,
      LogFC = logfcs[upSub_nodes],
      stringsAsFactors = FALSE
    )
    write.csv(summary_df, "upregulated_neighborhood_genes.csv", row.names = FALSE)
    
    # --- Generate PDF Plot of the subsetted neighborhood graph ---
    tryCatch({
      ar <- 20
      cols <- rev(colorRampPalette(brewer.pal(6, "RdBu"))(ar))
      
      # Map logfcs to colors
      incol <- round((logfcs[upSub_nodes] + 2) * 5)
      incol[incol > ar] <- ar
      incol[incol < 1] <- 1
      
      logcol <- cols[incol]
      logcol[logfcs[upSub_nodes] == 0] <- "darkgrey"
      names(logcol) <- upSub_nodes
      
      pdf("colorectal_cancer_neighborhood_plot.pdf", width = 12, height = 12)
      upnA <- makeNodeAttrs(upSub, fillcolor = logcol, label = upSub_symbols, fixedsize = TRUE, width = 10, height = 10, font = 20)
      plot(upSub, "dot", nodeAttrs = upnA)
      dev.off()
    }, error = function(e) {
      warning("Failed to generate PDF plot: ", e\$message)
    })
    
    cat("Pipeline completed successfully. Outputs written to 'upSub_graph.rds', 'upregulated_neighborhood_genes.csv', and 'colorectal_cancer_neighborhood_plot.pdf'.\n")

    writeLines(c(
        '"BIOC_KEGGGRAPH_EXPRESSION_DATA_INTEGRATION_AND_NEIGHBORHOOD_SUBSETTING":',
        paste0('        kegggraph: ', as.character(packageVersion("kegggraph")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_expression_data_integration_and_neighborhood_subsetting.csv versions.yml
    """
}

workflow BIOC_KEGGGRAPH_EXPRESSION_DATA_INTEGRATION_AND_NEIGHBORHOOD_SUBSETTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ hsa05210.xml, DE_Colorectal, ALL_Colorectal ] ]

    main:
    BIOC_KEGGGRAPH_EXPRESSION_DATA_INTEGRATION_AND_NEIGHBORHOOD_SUBSETTING(ch_input)

    emit:
    tables   = BIOC_KEGGGRAPH_EXPRESSION_DATA_INTEGRATION_AND_NEIGHBORHOOD_SUBSETTING.out.tables
    plots    = BIOC_KEGGGRAPH_EXPRESSION_DATA_INTEGRATION_AND_NEIGHBORHOOD_SUBSETTING.out.plots
    objects  = BIOC_KEGGGRAPH_EXPRESSION_DATA_INTEGRATION_AND_NEIGHBORHOOD_SUBSETTING.out.objects
    versions = BIOC_KEGGGRAPH_EXPRESSION_DATA_INTEGRATION_AND_NEIGHBORHOOD_SUBSETTING.out.versions
}
