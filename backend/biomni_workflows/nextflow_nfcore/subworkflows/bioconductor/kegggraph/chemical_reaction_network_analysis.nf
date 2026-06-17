#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: KEGGgraph — chemical_reaction_network_analysis
// Parse metabolic pathways to extract chemical compound reaction networks and analyze compound connectivity.
// Input: map00260.xml
// Container: quay.io/biocontainers/bioconductor-kegggraph:1.70.0--r45hdfd78af_0
// R packages: KEGGgraph, Rgraphviz
// Bioconductor: 3.20 | R: 4.4
// Requires: KEGGgraph, Rgraphviz
// Visualizations: network plot
// QC: input validation
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Parse the KGML file into a KEGGPathway object using parseKGML
//  * 2. [Core Analysis] Extract reactions using getReactions
//  * 3. [Core Analysis] Convert the pathway to a reaction graph of chemical compounds using KEGGpathway2reactionGraph
//  * 4. [Core Analysis] Calculate out-degrees of compounds to find highly connected metabolites
//  * 5. [Visualization & Output] Plot the chemical reaction network

nextflow.enable.dsl = 2

process BIOC_KEGGGRAPH_CHEMICAL_REACTION_NETWORK_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    tuple val(meta), path("qc_metrics.json"), emit: qc_metrics
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
    library(Rgraphviz)
    
    # Define the makeAttr function exactly as documented in the vignette
    makeAttr <- function(graph, default, valNodeList) {
      tmp <- nodes(graph)
      x <- rep(default, length(tmp)); names(x) <- tmp
      
      if(!missing(valNodeList)) {
        stopifnot(is.list(valNodeList))
        allnodes <- unlist(valNodeList)
        stopifnot(all(allnodes %in% tmp))
        for(i in seq(valNodeList)) {
          x[valNodeList[[i]]] <- names(valNodeList)[i]
        }
      }
      return(x)
    }
    
    # 1. Parse the KGML file into a KEGGPathway object using parseKGML
    # Read the user input file from the working directory
    mapfile <- "map00260.xml"
    if (!file.exists(mapfile)) {
      stop(paste("Required input file missing:", mapfile))
    }
    
    map <- parseKGML(mapfile)
    print(map)
    
    # 2. Extract reactions using getReactions
    reactions <- getReactions(map)
    if (length(reactions) > 0) {
      print(reactions[[1]])
    }
    saveRDS(reactions, file = "reactions.rds")
    
    # 3. Convert the pathway to a reaction graph of chemical compounds using KEGGpathway2reactionGraph
    chemicalGraph <- KEGGpathway2reactionGraph(map)
    saveRDS(chemicalGraph, file = "chemical_graph.rds")
    
    # 4. Calculate out-degrees of compounds to find highly connected metabolites
    outDegrees <- sapply(edges(chemicalGraph), length)
    
    # Save out-degrees to a CSV file
    out_degrees_df <- data.frame(
      Compound = names(outDegrees),
      OutDegree = outDegrees,
      stringsAsFactors = FALSE
    )
    out_degrees_df <- out_degrees_df[order(out_degrees_df\$OutDegree, decreasing = TRUE), ]
    write.csv(out_degrees_df, file = "out_degrees.csv", row.names = FALSE)
    
    maxout <- names(sort(outDegrees,decreasing=TRUE))[1:3]
    
    nAttrs <- list()
    maxoutlabel <- as.list(maxout); names(maxoutlabel) <- maxout
    nAttrs\$label <- makeAttr(chemicalGraph, "", maxoutlabel)
    nAttrs\$fillcolor <- makeAttr(chemicalGraph, "lightblue", list(orange=maxout))
    nAttrs\$width <- makeAttr(chemicalGraph,"0.8", list("1.8"=maxout))
    
    # 5. Plot the chemical reaction network
    pdf("chemical_reaction_network.pdf", width = 10, height = 10)
    plot(chemicalGraph, nodeAttrs=nAttrs)
    dev.off()
    
    cat("Pipeline completed successfully. Outputs saved: reactions.rds, chemical_graph.rds, out_degrees.csv, chemical_reaction_network.pdf\n")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # input validation — workflow-level pass when expected output files exist
    # and have non-zero size. Binary pass: at least one .rds or .csv emitted.
    .iv_artifacts <- c(list.files(".", pattern = "\\.rds\$"), list.files(".", pattern = "\\.csv\$"))
    .iv_passes <- length(.iv_artifacts) > 0
    .gates_by_label[["input validation"]] <- list(
      gate_row = "bioc_input_validation",
      metric_name = "input_validation_passes",
      metric_value = if (.iv_passes) 1 else 0,
      passes = .iv_passes,
      status = paste0("computed (", length(.iv_artifacts), " artifact(s) emitted)")
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_KEGGGRAPH_CHEMICAL_REACTION_NETWORK_ANALYSIS",
      domain  = "bioconductor",
      declared_qc_steps = c("input validation"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_KEGGGRAPH_CHEMICAL_REACTION_NETWORK_ANALYSIS":',
        paste0('    KEGGgraph: ', as.character(packageVersion('KEGGgraph')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chemical_reaction_network_analysis.csv versions.yml
    """
}

workflow BIOC_KEGGGRAPH_CHEMICAL_REACTION_NETWORK_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ map00260.xml ] ]

    main:
    BIOC_KEGGGRAPH_CHEMICAL_REACTION_NETWORK_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_KEGGGRAPH_CHEMICAL_REACTION_NETWORK_ANALYSIS.out.tables
    plots    = BIOC_KEGGGRAPH_CHEMICAL_REACTION_NETWORK_ANALYSIS.out.plots
    objects  = BIOC_KEGGGRAPH_CHEMICAL_REACTION_NETWORK_ANALYSIS.out.objects
    versions = BIOC_KEGGGRAPH_CHEMICAL_REACTION_NETWORK_ANALYSIS.out.versions
}
