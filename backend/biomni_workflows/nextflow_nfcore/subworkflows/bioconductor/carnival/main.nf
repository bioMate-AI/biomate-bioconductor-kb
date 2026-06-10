#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CARNIVAL — standard_carnival
// Contextualize a signaling network when the upstream perturbation targets are known.
// Input: toy_perturbations_ex1.RData, toy_measurements_ex1.RData, toy_network_ex1.RData
// Container: quay.io/biocontainers/bioconductor-carnival:2.20.0--r45hdfd78af_0
// R packages: CARNIVAL, igraph
// Bioconductor: 3.20 | R: 4.4
// Requires: CARNIVAL, igraph
// Visualizations: network plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load input data and prior knowledge network
//  * 2. [Core Analysis] Initialize solver options using defaultLpSolveCarnivalOptions
//  * 3. [Visualization & Output] Set output folder
//  * 4. [Core Analysis] Run standard pipeline using runVanillaCarnival
//  * 5. [Visualization & Output] Save results using saveRDS

nextflow.enable.dsl = 2

process BIOC_CARNIVAL_STANDARD_CARNIVAL {
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
    .bm_deps <- c("CARNIVAL", "igraph")
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
    library(CARNIVAL)
    library(igraph)
    
    # 1. Load input data and prior knowledge network from the working directory
    load(file = "toy_perturbations_ex1.RData")
    load(file = "toy_measurements_ex1.RData")
    load(file = "toy_network_ex1.RData")
    
    # 2. Initialize solver options using defaultLpSolveCarnivalOptions
    carnivalOptions <- defaultLpSolveCarnivalOptions()
    
    # 3. Set output folder
    output_dir <- "ToyExample1"
    dir.create(output_dir, showWarnings = FALSE)
    carnivalOptions\$outputFolder <- output_dir
    
    # 4. Run standard pipeline using runVanillaCarnival
    resultsLpSolve <- runVanillaCarnival(perturbations = toy_perturbations_ex1, 
                                         measurements = toy_measurements_ex1,
                                         priorKnowledgeNetwork = toy_network_ex1, 
                                         carnivalOptions = carnivalOptions)
    
    # 5. Save results using saveRDS
    saveRDS(resultsLpSolve, file = file.path(output_dir, "network_solution.Rds"))
    
    # Save meaningful results as CSV tables
    if (!is.null(resultsLpSolve\$weightedSIF)) {
      write.csv(resultsLpSolve\$weightedSIF, 
                file = file.path(output_dir, "weightedSIF.csv"), 
                row.names = FALSE)
    }
    
    if (!is.null(resultsLpSolve\$nodesAttributes)) {
      write.csv(resultsLpSolve\$nodesAttributes, 
                file = file.path(output_dir, "nodesAttributes.csv"), 
                row.names = FALSE)
    }
    
    # Generate a PDF plot of the network if weightedSIF is available
    if (!is.null(resultsLpSolve\$weightedSIF) && nrow(resultsLpSolve\$weightedSIF) > 0) {
      tryCatch({
        sif <- resultsLpSolve\$weightedSIF
        # Create igraph object from the network structure
        g <- graph_from_data_frame(sif[, c("Node1", "Node2")], directed = TRUE)
        
        pdf(file.path(output_dir, "network_plot.pdf"), width = 7, height = 7)
        plot(g, 
             vertex.color = "lightblue", 
             vertex.size = 25, 
             vertex.label.color = "black", 
             vertex.label.cex = 0.8,
             edge.arrow.size = 0.5,
             main = "CARNIVAL Reconstructed Network")
        dev.off()
      }, error = function(e) {
        message("Could not generate network plot: ", e\$message)
      })
    }

    writeLines(c(
        '"BIOC_CARNIVAL_STANDARD_CARNIVAL":',
        paste0('    CARNIVAL: ', as.character(packageVersion('CARNIVAL')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_carnival.csv versions.yml
    """
}

workflow BIOC_CARNIVAL_STANDARD_CARNIVAL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ toy_perturbations_ex1.RData, toy_measurements_ex1.RData, toy_network_ex1.RData ] ]

    main:
    BIOC_CARNIVAL_STANDARD_CARNIVAL(ch_input)

    emit:
    tables   = BIOC_CARNIVAL_STANDARD_CARNIVAL.out.tables
    plots    = BIOC_CARNIVAL_STANDARD_CARNIVAL.out.plots
    objects  = BIOC_CARNIVAL_STANDARD_CARNIVAL.out.objects
    versions = BIOC_CARNIVAL_STANDARD_CARNIVAL.out.versions
}
