#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: geneplast — network_rooting_mapping
// Map inferred evolutionary roots to a protein-protein interaction (PPI) or transcriptional regulatory network represented as an igraph object.
// Input: ogr, cogdata, ppi.gs
// Container: quay.io/biocontainers/bioconductor-geneplast:1.36.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: RColorBrewer, RedeR, geneplast, igraph
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Map rooting annotations to the igraph object using ogr2igraph
//  * 2. [Core Analysis] Set aesthetic attributes (like node colors based on roots) using att.setv

nextflow.enable.dsl = 2

process BIOC_GENEPLAST_NETWORK_ROOTING_MAPPING {
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
    .bm_deps <- c("geneplast", "igraph", "RColorBrewer", "RedeR")
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
    library(geneplast)
    library(igraph)
    library(RColorBrewer)
    library(grDevices)
    library(RedeR)
    
    # Helper function to read user input files from the working directory
    read_input <- function(name, is_df = FALSE) {
      if (file.exists(name)) {
        tryCatch({
          return(readRDS(name))
        }, error = function(e) {
          if (is_df) {
            return(read.csv(name, stringsAsFactors = FALSE))
          } else {
            stop(paste("Failed to read file:", name))
          }
        })
      } else if (file.exists(paste0(name, ".rds"))) {
        return(readRDS(paste0(name, ".rds")))
      } else if (is_df && file.exists(paste0(name, ".csv"))) {
        return(read.csv(paste0(name, ".csv"), stringsAsFactors = FALSE))
      } else {
        stop(paste("Required input file not found in working directory:", name))
      }
    }
    
    # 1. Load User Inputs
    # The pipeline reads exactly these files from the working directory
    ogr <- read_input("ogr")
    cogdata <- read_input("cogdata", is_df = TRUE)
    ppi.gs <- read_input("ppi.gs")
    
    # 2. Map rooting annotations to the igraph object
    g <- ogr2igraph(ogr, cogdata, ppi.gs, idkey = "ENTREZ")
    
    # 3. Set aesthetic attributes (like node colors based on roots)
    pal <- brewer.pal(9, "RdYlBu")
    color_col <- colorRampPalette(pal)(25)
    g <- att.setv(g=g, from="Root", to="nodeColor", cols=color_col, na.col="grey80", breaks=seq(1,25))
    g <- att.setv(g = g, from = "SYMBOL", to = "nodeAlias")
    
    # 4. Save Outputs
    # Save the complete mapped igraph object
    saveRDS(g, "mapped_network.rds")
    
    # Extract and save node attributes as a CSV table
    node_attribs <- as_data_frame(g, what = "vertices")
    write.csv(node_attribs, "mapped_network_nodes.csv", row.names = FALSE)
    
    # Generate a PDF plot showing the distribution of evolutionary roots in the network
    if ("Root" %in% colnames(node_attribs)) {
      pdf("root_distribution_histogram.pdf", width = 7, height = 5)
      # Filter out NA roots for plotting
      valid_roots <- node_attribs\$Root[!is.na(node_attribs\$Root)]
      if (length(valid_roots) > 0) {
        hist(valid_roots, 
             breaks = seq(0.5, 25.5, by = 1),
             col = color_col, 
             main = "Distribution of Evolutionary Roots in Network",
             xlab = "Root", 
             ylab = "Frequency",
             xaxt = "n")
        axis(1, at = 1:25, labels = 1:25)
      } else {
        plot.new()
        text(0.5, 0.5, "No valid Root annotations found to plot", cex = 1.2)
      }
      dev.off()
    }

    writeLines(c(
        '"BIOC_GENEPLAST_NETWORK_ROOTING_MAPPING":',
        paste0('    geneplast: ', as.character(packageVersion('geneplast')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_network_rooting_mapping.csv versions.yml
    """
}

workflow BIOC_GENEPLAST_NETWORK_ROOTING_MAPPING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ogr, cogdata, ppi.gs ] ]

    main:
    BIOC_GENEPLAST_NETWORK_ROOTING_MAPPING(ch_input)

    emit:
    tables   = BIOC_GENEPLAST_NETWORK_ROOTING_MAPPING.out.tables
    plots    = BIOC_GENEPLAST_NETWORK_ROOTING_MAPPING.out.plots
    objects  = BIOC_GENEPLAST_NETWORK_ROOTING_MAPPING.out.objects
    versions = BIOC_GENEPLAST_NETWORK_ROOTING_MAPPING.out.versions
}
