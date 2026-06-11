#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: clustComp — flat_vs_flat_comparison
// Compare and visualize two flat clustering results using barycentre layout optimization and greedy supercluster mapping.
// Input: flat1, flat2
// Container: quay.io/biocontainers/bioconductor-clustcomp:1.38.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: clustComp
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Perform initial flat-versus-flat comparison and layout
//  * 2. [Visualization & Output] Manually adjust node coordinates or layout orientation to
//  * 3. [Visualization & Output] Construct a one-to-one mapping of superclusters using the
//  * 4. [Visualization & Output] Visualize the supercluster mapping in the bipartite graph

nextflow.enable.dsl = 2

process BIOC_CLUSTCOMP_FLAT_VS_FLAT_COMPARISON {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(clustComp)
    
    # Helper function to read input files robustly from the working directory
    read_input <- function(filename) {
      if (file.exists(filename)) {
        # Try reading as RDS
        res <- tryCatch({
          readRDS(filename)
        }, error = function(e) {
          NULL
        })
        if (!is.null(res)) return(res)
        
        # Try reading as plain text lines
        res <- tryCatch({
          scan(filename, what = character(), quiet = TRUE)
        }, error = function(e) {
          NULL
        })
        if (!is.null(res)) return(res)
        
        stop(paste("Could not parse file:", filename))
      } else if (file.exists(paste0(filename, ".rds"))) {
        return(readRDS(paste0(filename, ".rds")))
      } else if (file.exists(paste0(filename, ".txt"))) {
        return(scan(paste0(filename, ".txt"), what = character(), quiet = TRUE))
      } else {
        stop(paste("Required input file", filename, "not found in the working directory."))
      }
    }
    
    # Read user inputs
    flat1 <- read_input("flat1")
    flat2 <- read_input("flat2")
    
    # Ensure inputs are vectors
    flat1 <- as.vector(flat1)
    flat2 <- as.vector(flat2)
    
    # --- Perform initial flat-versus-flat comparison and layout ---
    pdf("flat_vs_flat_initial.pdf", width = 7, height = 7)
    res_initial <- flatVSflat( flat1, flat2, line.wd = 5, h.min = 0.3, greedy = FALSE)
    dev.off()
    saveRDS(res_initial, "flat_vs_flat_initial_results.rds")
    
    # --- Manually adjust node coordinates or layout orientation to ---
    # We dynamically generate coordinates based on the number of unique clusters in the inputs to ensure robustness.
    pdf("flat_vs_flat_coords.pdf", width = 7, height = 7)
    res_coords <- flatVSflat(flat1, flat2, 
                             coord1 = sample(length(unique(flat1))), 
                             coord2 = sample(length(unique(flat2))), 
                             greedy = FALSE)
    dev.off()
    saveRDS(res_coords, "flat_vs_flat_coords_results.rds")
    
    # Layout orientation adjustment (evenly distributed, horizontal)
    pdf("flat_vs_flat_evenly_horiz.pdf", width = 7, height = 7)
    res_evenly <- flatVSflat(flat1, flat2, evenly=TRUE, horiz=TRUE, greedy = FALSE)
    dev.off()
    saveRDS(res_evenly, "flat_vs_flat_evenly_results.rds")
    
    # --- Construct a one-to-one mapping of superclusters using the ---
    pdf("sc_mapping.pdf", width = 7, height = 7)
    myMapping<-SCmapping(flat1, flat2)
    dev.off()
    saveRDS(myMapping, "myMapping.rds")
    
    # --- Visualize the supercluster mapping in the bipartite graph ---
    pdf("flat_vs_flat_greedy.pdf", width = 7, height = 7)
    res_greedy <- flatVSflat( flat1, flat2, line.wd = 5, h.min = 0.3, greedy = TRUE)
    dev.off()
    saveRDS(res_greedy, "flat_vs_flat_greedy_results.rds")
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_CLUSTCOMP_FLAT_VS_FLAT_COMPARISON":',
        paste0('    clustComp: ', as.character(packageVersion('clustComp')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_flat_vs_flat_comparison.csv versions.yml
    """
}

workflow BIOC_CLUSTCOMP_FLAT_VS_FLAT_COMPARISON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ flat1, flat2 ] ]

    main:
    BIOC_CLUSTCOMP_FLAT_VS_FLAT_COMPARISON(ch_input)

    emit:
    tables   = BIOC_CLUSTCOMP_FLAT_VS_FLAT_COMPARISON.out.tables
    plots    = BIOC_CLUSTCOMP_FLAT_VS_FLAT_COMPARISON.out.plots
    objects  = BIOC_CLUSTCOMP_FLAT_VS_FLAT_COMPARISON.out.objects
    versions = BIOC_CLUSTCOMP_FLAT_VS_FLAT_COMPARISON.out.versions
}
