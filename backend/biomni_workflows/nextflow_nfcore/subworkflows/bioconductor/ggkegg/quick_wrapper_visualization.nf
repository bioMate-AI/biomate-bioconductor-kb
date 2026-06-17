#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ggkegg — quick_wrapper_visualization
// Quickly generate a ggraph visualization of a KEGG pathway, module, or network using the wrapper function.
// Input: bpsp00270, N00002
// Container: quay.io/biocontainers/bioconductor-ggkegg:1.8.0--r45hdfd78af_0
// R packages: BiocFileCache, dplyr, ggkegg, ggplot2, tidygraph
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GGKEGG_QUICK_WRAPPER_VISUALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-ggkegg:1.8.0--r45hdfd78af_0"

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
    .bm_deps <- c("BiocFileCache", "dplyr", "ggkegg", "ggplot2", "tidygraph")
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
    library(ggkegg)
    library(tidygraph)
    library(dplyr)
    library(ggplot2)
    library(BiocFileCache)
    
    # Ensure the user input files exist in the working directory
    input_pathway <- "bpsp00270"
    input_network <- "N00002"
    
    if (!file.exists(input_pathway)) {
      stop(paste("Required input file missing:", input_pathway))
    }
    if (!file.exists(input_network)) {
      stop(paste("Required input file missing:", input_network))
    }
    
    # Populate BiocFileCache so ggkegg uses the local user input files
    tryCatch({
      cache_dir <- tools::R_user_dir("ggkegg", which = "cache")
      bfc <- BiocFileCache(cache_dir, ask = FALSE)
      
      # Define potential cache query keys that ggkegg might use
      pathway_keys <- c(
        "bpsp00270",
        "https://rest.kegg.jp/get/bpsp00270/kgml",
        "http://rest.kegg.jp/get/bpsp00270/kgml",
        "https://rest.kegg.jp/get/bpsp00270",
        "http://rest.kegg.jp/get/bpsp00270"
      )
      
      for (k in pathway_keys) {
        if (nrow(bfcquery(bfc, k)) == 0) {
          bfcadd(bfc, rname = k, fpath = input_pathway, action = "copy")
        }
      }
      
      network_keys <- c(
        "N00002",
        "https://rest.kegg.jp/get/N00002",
        "http://rest.kegg.jp/get/N00002"
      )
      
      for (k in network_keys) {
        if (nrow(bfcquery(bfc, k)) == 0) {
          bfcadd(bfc, rname = k, fpath = input_network, action = "copy")
        }
      }
    }, error = function(e) {
      warning("Failed to pre-populate BiocFileCache: ", e\$message)
    })
    
    # Also copy files to the working directory with .xml extension as a fallback
    file.copy(input_pathway, "bpsp00270.xml", overwrite = TRUE)
    file.copy(input_network, "N00002.xml", overwrite = TRUE)
    
    # === DOCUMENTED CODE ===
    # Call the ggkegg wrapper function to automatically generate and return a ggraph plot object
    ggkegg_class <- ggkegg("bpsp00270") |> class() ## Returns ggraph
    ggkegg_plot <- ggkegg("N00002") ## Returns the KEGG NETWORK plot
    # === END DOCUMENTED CODE ===
    
    # Save the class information to a text file
    writeLines(ggkegg_class, "bpsp00270_class.txt")
    
    # Save the generated pathway plot
    p1 <- ggkegg("bpsp00270")
    ggsave("bpsp00270_pathway_plot.pdf", plot = p1, width = 10, height = 8)
    
    # Save the generated network plot
    ggsave("N00002_network_plot.pdf", plot = ggkegg_plot, width = 10, height = 8)

    writeLines(c(
        '"BIOC_GGKEGG_QUICK_WRAPPER_VISUALIZATION":',
        paste0('        ggkegg: ', as.character(packageVersion("ggkegg")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_quick_wrapper_visualization.csv versions.yml
    """
}

workflow BIOC_GGKEGG_QUICK_WRAPPER_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bpsp00270, N00002 ] ]

    main:
    BIOC_GGKEGG_QUICK_WRAPPER_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_GGKEGG_QUICK_WRAPPER_VISUALIZATION.out.tables
    plots    = BIOC_GGKEGG_QUICK_WRAPPER_VISUALIZATION.out.plots
    objects  = BIOC_GGKEGG_QUICK_WRAPPER_VISUALIZATION.out.objects
    versions = BIOC_GGKEGG_QUICK_WRAPPER_VISUALIZATION.out.versions
}
