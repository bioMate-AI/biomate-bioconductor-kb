#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GraphAlignment — weighted_undirected_network_alignment
// Align two weighted undirected networks using node similarity and link weight similarity.
// Input: ex$a, ex$b, ex$r
// Container: quay.io/biocontainers/bioconductor-graphalignment:1.74.0--r45h01b2380_0
// R packages: GraphAlignment
// Bioconductor: 3.20 | R: 4.4
// Requires: GraphAlignment
// Visualizations: image plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Generate example data and initial alignment
//  * 2. [Input & Preparation] Define link and node lookup bins
//  * 3. [Core Analysis] Compute link and node scoring parameters
//  * 4. [Core Analysis] Align networks using simulated annealing
//  * 5. [Core Analysis] Compute alignment scores
//  * 6. [Core Analysis] Analyze alignment characteristics

nextflow.enable.dsl = 2

process BIOC_GRAPHALIGNMENT_WEIGHTED_UNDIRECTED_NETWORK_ALIGNMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("GraphAlignment")
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
    
    # Load required library
    library(GraphAlignment)
    
    # Helper function to robustly read input files (RDS or CSV)
    read_input <- function(filename) {
      if (!file.exists(filename)) {
        stop(paste("Required input file missing:", filename))
      }
      
      # Try reading as RDS first
      obj <- tryCatch({
        readRDS(filename)
      }, error = function(e) {
        NULL
      })
      
      if (!is.null(obj)) {
        return(as.matrix(obj))
      }
      
      # If not RDS, try reading as CSV
      obj <- tryCatch({
        as.matrix(read.csv(filename, row.names = 1, check.names = FALSE))
      }, error = function(e) {
        # Try without row names if that fails
        as.matrix(read.csv(filename, check.names = FALSE))
      })
      
      return(obj)
    }
    
    # Read user input files from the working directory
    ex <- list(
      a = read_input("ex\$a"),
      b = read_input("ex\$b"),
      r = read_input("ex\$r")
    )
    
    # Determine dimensions dynamically from the input matrices
    dimA <- nrow(ex\$a)
    dimB <- nrow(ex\$b)
    psize <- dimA + dimB  # Robust choice to accommodate dummy nodes and prevent forced incorrect alignments
    
    # 1. Generate initial alignment
    pinitial <- InitialAlignment(psize=psize, r=ex\$r, mode="reciprocal")
    
    # 2. Define link and node lookup bins
    lookupLink <- seq(-2, 2, .5)
    
    # 3. Compute link and node scoring parameters
    linkParams <- ComputeLinkParameters(ex\$a, ex\$b, pinitial, lookupLink)
    lookupNode <- c(-.5, .5, 1.5)
    nodeParams <- ComputeNodeParameters(dimA=dimA, dimB=dimB, ex\$r,
        pinitial, lookupNode)
    
    # 4. Align networks using simulated annealing
    al <- AlignNetworks(A=ex\$a, B=ex\$b, R=ex\$r, P=pinitial, 
        linkScore=linkParams\$ls,
        selfLinkScore=linkParams\$ls,
        nodeScore1=nodeParams\$s1, nodeScore0=nodeParams\$s0,
        lookupLink=lookupLink, lookupNode=lookupNode,
        bStart=.1, bEnd=30,
        maxNumSteps=50)
    
    # 5. Compute alignment scores
    scores <- ComputeScores(A=ex\$a, B=ex\$b, R=ex\$r, P=al, 
        linkScore=linkParams\$ls,
        selfLinkScore=linkParams\$ls,
        nodeScore1=nodeParams\$s1, nodeScore0=nodeParams\$s0,
        lookupLink=lookupLink, lookupNode=lookupNode,
        symmetric=TRUE)
    
    # 6. Analyze alignment characteristics
    analysis <- AnalyzeAlignment(A=ex\$a, B=ex\$b, R=ex\$r, P=al, lookupNode,
        epsilon=.5)
    
    # --- Save Outputs ---
    
    # Save alignment vector as RDS
    saveRDS(al, "alignment.rds")
    
    # Extract and save aligned pairs as CSV
    aligned_pairs <- AlignedPairs(ex\$a, ex\$b, al)
    write.csv(aligned_pairs, "aligned_pairs.csv", row.names = FALSE)
    
    # Save scores and analysis results as RDS
    results <- list(
      scores = scores,
      analysis = analysis
    )
    saveRDS(results, "alignment_results.rds")
    
    # Write a text summary of the alignment results
    sink("alignment_summary.txt")
    cat("=== Alignment Scores ===\n")
    print(scores)
    cat("\n=== Alignment Analysis ===\n")
    print(analysis)
    sink()
    
    # Generate diagnostic plots
    pdf("alignment_plots.pdf", width = 8, height = 8)
    par(mfrow = c(2, 2))
    image(ex\$a, main = "Network A Adjacency")
    image(ex\$b, main = "Network B Adjacency")
    image(ex\$r, main = "Node Similarity R")
    if (nrow(aligned_pairs) > 0) {
      plot(aligned_pairs[, 1], aligned_pairs[, 2], 
           xlab = "Network A Node Index", 
           ylab = "Network B Node Index",
           main = "Aligned Node Pairs", 
           pch = 19, col = "blue")
    } else {
      plot(1, type = "n", axes = FALSE, xlab = "", ylab = "", main = "No Aligned Pairs")
    }
    dev.off()

    writeLines(c(
        '"BIOC_GRAPHALIGNMENT_WEIGHTED_UNDIRECTED_NETWORK_ALIGNMENT":',
        paste0('    GraphAlignment: ', as.character(packageVersion('GraphAlignment')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_weighted_undirected_network_alignment.csv versions.yml
    """
}

workflow BIOC_GRAPHALIGNMENT_WEIGHTED_UNDIRECTED_NETWORK_ALIGNMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ex$a, ex$b, ex$r ] ]

    main:
    BIOC_GRAPHALIGNMENT_WEIGHTED_UNDIRECTED_NETWORK_ALIGNMENT(ch_input)

    emit:
    tables   = BIOC_GRAPHALIGNMENT_WEIGHTED_UNDIRECTED_NETWORK_ALIGNMENT.out.tables
    plots    = BIOC_GRAPHALIGNMENT_WEIGHTED_UNDIRECTED_NETWORK_ALIGNMENT.out.plots
    objects  = BIOC_GRAPHALIGNMENT_WEIGHTED_UNDIRECTED_NETWORK_ALIGNMENT.out.objects
    versions = BIOC_GRAPHALIGNMENT_WEIGHTED_UNDIRECTED_NETWORK_ALIGNMENT.out.versions
}
