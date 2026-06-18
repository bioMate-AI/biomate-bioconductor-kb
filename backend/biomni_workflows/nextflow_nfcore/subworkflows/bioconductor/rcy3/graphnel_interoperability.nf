#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RCy3 — graphnel_interoperability
// Convert a graphNEL network to Cytoscape, and retrieve a Cytoscape network back into R as a graphNEL object.
// Input: g
// Container: quay.io/biocontainers/bioconductor-rcy3:2.30.1--r45hdfd78af_0
// R packages: RCy3, graph
// Bioconductor: 3.20 | R: 4.4
// Requires: RCy3, graph
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Verify Cytoscape connection
//  * 2. [Core Analysis] Convert graphNEL network to Cytoscape
//  * 3. [Core Analysis] Retrieve Cytoscape network as graphNEL

nextflow.enable.dsl = 2

process BIOC_RCY3_GRAPHNEL_INTEROPERABILITY {
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
    .bm_deps <- c("RCy3", "graph")
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
    library(RCy3)
    library(graph)
    
    # 1. Verify Cytoscape connection
    cytoscapePing()
    
    # Load the user input graphNEL object from the working directory
    g <- readRDS("g.rds")
    
    # 2. Convert graphNEL network to Cytoscape
    createNetworkFromGraph(g, "myGraph")
    
    # 3. Retrieve Cytoscape network as graphNEL
    g2 <- createGraphFromNetwork("myGraph")
    
    # Save the retrieved graphNEL object to the working directory
    saveRDS(g2, "g2.rds")

    writeLines(c(
        '"BIOC_RCY3_GRAPHNEL_INTEROPERABILITY":',
        paste0('    RCy3: ', as.character(packageVersion('RCy3')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_graphnel_interoperability.csv versions.yml
    """
}

workflow BIOC_RCY3_GRAPHNEL_INTEROPERABILITY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ g ] ]

    main:
    BIOC_RCY3_GRAPHNEL_INTEROPERABILITY(ch_input)

    emit:
    tables   = BIOC_RCY3_GRAPHNEL_INTEROPERABILITY.out.tables
    plots    = BIOC_RCY3_GRAPHNEL_INTEROPERABILITY.out.plots
    objects  = BIOC_RCY3_GRAPHNEL_INTEROPERABILITY.out.objects
    versions = BIOC_RCY3_GRAPHNEL_INTEROPERABILITY.out.versions
}
