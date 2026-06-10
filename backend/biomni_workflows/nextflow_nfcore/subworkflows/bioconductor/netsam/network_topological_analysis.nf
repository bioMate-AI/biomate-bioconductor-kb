#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: NetSAM — network_topological_analysis
// Calculate topological properties of a network, including node degree, clustering coefficient, betweenness, closeness centrality, and pairwise shortest path dist
// Input: exampleNetwork.net
// Container: quay.io/biocontainers/bioconductor-netsam:1.50.0--r45hdfd78af_0
// Requires: NetSAM
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Run NetAnalyzer to calculate topological metrics and generate distribution plots

nextflow.enable.dsl = 2

process BIOC_NETSAM_NETWORK_TOPOLOGICAL_ANALYSIS {
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
    .bm_deps <- c("NetSAM")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Check if the required input file exists in the working directory
    input_file <- "exampleNetwork.net"
    if (!file.exists(input_file)) {
      stop(paste("Required input file", input_file, "is missing from the working directory."))
    }
    
    # Load the NetSAM library
    library("NetSAM")
    
    # Define the input network path and output file prefix
    inputNetwork <- input_file
    outputFileName <- paste(getwd(), "/NetSAM", sep = "")
    
    # Run NetAnalyzer to calculate topological metrics and generate distribution plots
    NetAnalyzer(inputNetwork, outputFileName, "unweighted")

    writeLines(c(
        '"BIOC_NETSAM_NETWORK_TOPOLOGICAL_ANALYSIS":',
        paste0('    NetSAM: ', as.character(packageVersion('NetSAM')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_network_topological_analysis.csv versions.yml
    """
}

workflow BIOC_NETSAM_NETWORK_TOPOLOGICAL_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ exampleNetwork.net ] ]

    main:
    BIOC_NETSAM_NETWORK_TOPOLOGICAL_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_NETSAM_NETWORK_TOPOLOGICAL_ANALYSIS.out.tables
    plots    = BIOC_NETSAM_NETWORK_TOPOLOGICAL_ANALYSIS.out.plots
    objects  = BIOC_NETSAM_NETWORK_TOPOLOGICAL_ANALYSIS.out.objects
    versions = BIOC_NETSAM_NETWORK_TOPOLOGICAL_ANALYSIS.out.versions
}
