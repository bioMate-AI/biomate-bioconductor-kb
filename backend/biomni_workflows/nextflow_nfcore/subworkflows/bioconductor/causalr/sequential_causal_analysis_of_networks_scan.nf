#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CausalR — sequential_causal_analysis_of_networks_scan
// Identify robust regulators that consistently score in the top tier across a range of path lengths (deltas) to limit false positives, and generate sub-networks f
// Input: testNetwork1.sif, testData1.txt
// Container: quay.io/biocontainers/bioconductor-causalr:1.42.0--r45hdfd78af_0
// Requires: CausalR
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load the network and construct a Computational Causal Graph (CCG) using CreateCCG. 2. Load the experimental data using ReadExperim

nextflow.enable.dsl = 2

process BIOC_CAUSALR_SEQUENTIAL_CAUSAL_ANALYSIS_OF_NETWORKS_SCAN {
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
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load the required library
    library(CausalR)
    
    # 1. Load the network and construct a Computational Causal Graph (CCG)
    # Reading directly from the user-provided 'testNetwork1.sif' in the working directory
    ccg <- CreateCCG("testNetwork1.sif")
    
    # 2. Load the experimental data
    # Reading directly from the user-provided 'testData1.txt' in the working directory
    experimentalData <- ReadExperimentalData("testData1.txt", ccg)
    
    # 3. Run the SCAN algorithm to find common top-scoring nodes across multiple deltas
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
    
    # 4. Generate SIF and annotation files for the explained nodes of specific hypotheses
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
