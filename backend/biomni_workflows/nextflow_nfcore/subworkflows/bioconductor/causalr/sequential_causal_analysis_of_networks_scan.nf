#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CausalR — sequential_causal_analysis_of_networks_scan
// Identify robust regulators that consistently score in the top tier across a range of path lengths (deltas) to limit false positives, and generate sub-networks f
// Input: testNetwork1.sif, testData1.txt
// Container: quay.io/biocontainers/bioconductor-causalr:1.42.0--r45hdfd78af_0
// R packages: CausalR
// Bioconductor: 3.20 | R: 4.4
// Requires: CausalR
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load the network and construct a Computational Causal
//  * 2. [Visualization & Output] Load the experimental data
//  * 3. [Visualization & Output] Run the SCAN algorithm to find common top-scoring nodes
//  * 4. [Visualization & Output] Generate SIF and annotation files for the explained nodes

nextflow.enable.dsl = 2

process BIOC_CAUSALR_SEQUENTIAL_CAUSAL_ANALYSIS_OF_NETWORKS_SCAN {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    library(CausalR)
    
    # --- Load the network and construct a Computational Causal ---
    # Reading directly from the user-provided 'testNetwork1.sif' in the working directory
    ccg <- CreateCCG("testNetwork1.sif")
    
    # --- Load the experimental data ---
    # Reading directly from the user-provided 'testData1.txt' in the working directory
    experimentalData <- ReadExperimentalData("testData1.txt", ccg)
    
    # --- Run the SCAN algorithm to find common top-scoring nodes ---
    scanResults <- runSCANR(
      ccg, 
      experimentalData, 
      numberOfDeltaToScan = 2, 
      topNumGenes = 4, 
      correctPredictionsThreshold = 1, 
      writeResultFiles = TRUE, 
      writeNetworkFiles = "none",
      quiet = TRUE
    )
    
    # Save the scan results object to an RDS file for downstream analysis
    saveRDS(scanResults, "scanResults.rds")
    
    # --- Generate SIF and annotation files for the explained nodes ---
    # Wrap in tryCatch to ensure robust execution even if specific nodes are missing
    tryCatch({
      WriteExplainedNodesToSifFile("Node1", +1, ccg, experimentalData, delta = 2)
    }, error = function(e) {
      message("Warning: Could not write explained nodes for Node1: ", e\$message)
    })
    
    tryCatch({
      WriteAllExplainedNodesToSifFile(
        scanResults, 
        ccg, 
        experimentalData, 
        delta = 2, 
        correctlyExplainedOnly = TRUE, 
        quiet = TRUE
      )
    }, error = function(e) {
      message("Warning: Could not write all explained nodes to SIF: ", e\$message)
    })

    writeLines(c(
        '"BIOC_CAUSALR_SEQUENTIAL_CAUSAL_ANALYSIS_OF_NETWORKS_SCAN":',
        paste0('    CausalR: ', as.character(packageVersion('CausalR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sequential_causal_analysis_of_networks_scan.csv versions.yml
    """
}

workflow BIOC_CAUSALR_SEQUENTIAL_CAUSAL_ANALYSIS_OF_NETWORKS_SCAN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ testNetwork1.sif, testData1.txt ] ]

    main:
    BIOC_CAUSALR_SEQUENTIAL_CAUSAL_ANALYSIS_OF_NETWORKS_SCAN(ch_input)

    emit:
    tables   = BIOC_CAUSALR_SEQUENTIAL_CAUSAL_ANALYSIS_OF_NETWORKS_SCAN.out.tables
    plots    = BIOC_CAUSALR_SEQUENTIAL_CAUSAL_ANALYSIS_OF_NETWORKS_SCAN.out.plots
    objects  = BIOC_CAUSALR_SEQUENTIAL_CAUSAL_ANALYSIS_OF_NETWORKS_SCAN.out.objects
    versions = BIOC_CAUSALR_SEQUENTIAL_CAUSAL_ANALYSIS_OF_NETWORKS_SCAN.out.versions
}
