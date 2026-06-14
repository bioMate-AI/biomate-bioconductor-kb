#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: netsam — network_seriation_and_modularization
// Perform network seriation and modularization on an existing network file or object to identify hierarchical modules and optimal leaf ordering, and optionally an
// Input: network.net
// Container: quay.io/biocontainers/bioconductor-netsam:1.50.0--r45hdfd78af_0
// R packages: NetSAM
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NETSAM_NETWORK_SERIATION_AND_MODULARIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-netsam:1.50.0--r45hdfd78af_0"

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
    .bm_deps <- c("NetSAM")
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
    
    # Load the required library
    library("NetSAM")
    
    # Define input file path (must read EXACTLY network.net from the working directory)
    inputNetworkDir <- "network.net"
    
    # Check if the input file exists
    if (!file.exists(inputNetworkDir)) {
      stop("Error: Input file 'network.net' not found in the working directory.")
    }
    
    # Define output file path prefix
    outputFileName <- paste(getwd(), "/NetSAM", sep="")
    
    # --- Run NetSAM to identify hierarchical modules and optimal ---
    message("Running NetSAM...")
    result <- NetSAM(
      inputNetwork = inputNetworkDir, 
      outputFileName = outputFileName, 
      outputFormat = "nsm",
      edgeType = "unweighted", 
      map_to_genesymbol = FALSE, 
      organism = "hsapiens", 
      idType = "auto", 
      minModule = 0.003,
      stepIte = FALSE, 
      maxStep = 4, 
      moduleSigMethod = "cutoff", 
      modularityThr = 0.2, 
      ZRanNum = 10,
      PerRanNum = 100, 
      ranSig = 0.05, 
      edgeThr = (-1), 
      nodeThr = (-1), 
      nThreads = 3
    )
    
    # Save the result object to an RDS file
    saveRDS(result, file = "NetSAM_result.rds")
    message("NetSAM analysis complete. Result saved to 'NetSAM_result.rds'.")
    
    # --- Run NetAnalyzer to calculate network centrality ---
    message("Running NetAnalyzer...")
    inputNetwork <- "network.net"
    NetAnalyzer(inputNetwork, outputFileName, "unweighted")
    message("NetAnalyzer analysis complete. Outputs saved with prefix 'NetSAM'.")

    writeLines(c(
        '"BIOC_NETSAM_NETWORK_SERIATION_AND_MODULARIZATION":',
        paste0('        netsam: ', as.character(packageVersion("netsam")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_network_seriation_and_modularization.csv versions.yml
    """
}

workflow BIOC_NETSAM_NETWORK_SERIATION_AND_MODULARIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ network.net ] ]

    main:
    BIOC_NETSAM_NETWORK_SERIATION_AND_MODULARIZATION(ch_input)

    emit:
    tables   = BIOC_NETSAM_NETWORK_SERIATION_AND_MODULARIZATION.out.tables
    plots    = BIOC_NETSAM_NETWORK_SERIATION_AND_MODULARIZATION.out.plots
    objects  = BIOC_NETSAM_NETWORK_SERIATION_AND_MODULARIZATION.out.objects
    versions = BIOC_NETSAM_NETWORK_SERIATION_AND_MODULARIZATION.out.versions
}
