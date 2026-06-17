#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: causalr — sequential_causal_analysis_scan
// Run Sequential Causal Analysis of Networks (SCAN) across multiple deltas to identify robust upstream regulators and generate their explained sub-networks.
// Input: testNetwork1.sif, testData1.txt
// Container: quay.io/biocontainers/bioconductor-causalr:1.42.0--r45hdfd78af_0
// R packages: CausalR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CAUSALR_SEQUENTIAL_CAUSAL_ANALYSIS_SCAN {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-causalr:1.42.0--r45hdfd78af_0"

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
    .bm_deps <- c("CausalR")
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
    library(CausalR)
    
    # Define input file paths (must exist in the working directory)
    network_file <- "testNetwork1.sif"
    data_file <- "testData1.txt"
    
    # Verify input files exist before proceeding
    if (!file.exists(network_file)) {
      stop(paste("Required input file missing:", network_file))
    }
    if (!file.exists(data_file)) {
      stop(paste("Required input file missing:", data_file))
    }
    
    # --- Load the network and construct a Computational Causal ---
    ccg <- CreateCCG(network_file)
    
    # --- Load the experimental data and map it to the CCG ---
    experimentalData <- ReadExperimentalData(data_file, ccg)
    
    # --- Run the SCAN algorithm across a range of deltas to find ---
    scanResults <- runSCANR(
      ccg, 
      experimentalData, 
      numberOfDeltaToScan = 2, 
      topNumGenes = 4,
      correctPredictionsThreshold = 1, 
      writeResultFiles = FALSE, 
      writeNetworkFiles = "none",
      quiet = FALSE
    )
    
    # --- Export the sub-networks of correctly explained nodes for ---
    WriteAllExplainedNodesToSifFile(
      scanResults, 
      ccg, 
      experimentalData, 
      delta = 2, 
      correctlyExplainedOnly = TRUE, 
      quiet = TRUE
    )
    
    # --- Save structured outputs to the working directory ---
    # Save the full scan results object
    saveRDS(scanResults, file = "scan_results.rds")
    
    # Save the common nodes identified across deltas
    if (!is.null(scanResults\$commonNodes)) {
      write.table(
        scanResults\$commonNodes, 
        file = "scan_common_nodes.txt", 
        row.names = FALSE, 
        col.names = FALSE, 
        quote = FALSE
      )
    }
    
    # Save the unique nodes with their maximum delta
    if (!is.null(scanResults\$uniqueNodes)) {
      write.csv(
        scanResults\$uniqueNodes, 
        file = "scan_unique_nodes.csv", 
        row.names = FALSE
      )
    }

    writeLines(c(
        '"BIOC_CAUSALR_SEQUENTIAL_CAUSAL_ANALYSIS_SCAN":',
        paste0('        causalr: ', as.character(packageVersion("causalr")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sequential_causal_analysis_scan.csv versions.yml
    """
}

workflow BIOC_CAUSALR_SEQUENTIAL_CAUSAL_ANALYSIS_SCAN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ testNetwork1.sif, testData1.txt ] ]

    main:
    BIOC_CAUSALR_SEQUENTIAL_CAUSAL_ANALYSIS_SCAN(ch_input)

    emit:
    tables   = BIOC_CAUSALR_SEQUENTIAL_CAUSAL_ANALYSIS_SCAN.out.tables
    plots    = BIOC_CAUSALR_SEQUENTIAL_CAUSAL_ANALYSIS_SCAN.out.plots
    objects  = BIOC_CAUSALR_SEQUENTIAL_CAUSAL_ANALYSIS_SCAN.out.objects
    versions = BIOC_CAUSALR_SEQUENTIAL_CAUSAL_ANALYSIS_SCAN.out.versions
}
