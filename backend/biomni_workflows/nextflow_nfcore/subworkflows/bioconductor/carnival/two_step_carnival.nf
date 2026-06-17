#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CARNIVAL — two_step_carnival
// Generate an LP file first to inspect or modify, and then run the optimization pipeline from the generated LP file.
// Input: toy_perturbations_ex1.RData, toy_measurements_ex1.RData, toy_network_ex1.RData
// Container: quay.io/biocontainers/bioconductor-carnival:2.20.0--r45hdfd78af_0
// R packages: CARNIVAL
// Bioconductor: 3.20 | R: 4.4
// Requires: CARNIVAL
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load input data
//  * 2. [Core Analysis] Initialize solver options
//  * 3. [Core Analysis] Generate LP and parsed data files using generateLpFileCarnival
//  * 4. [Core Analysis] Run CARNIVAL optimization from the generated files using runFromLpCarnival

nextflow.enable.dsl = 2

process BIOC_CARNIVAL_TWO_STEP_CARNIVAL {
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
    .bm_deps <- c("CARNIVAL")
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
    
    # Load the CARNIVAL library
    library(CARNIVAL)
    
    # 1. Load input data from the working directory
    load("toy_perturbations_ex1.RData")
    load("toy_measurements_ex1.RData")
    load("toy_network_ex1.RData")
    
    # 2. Initialize solver options
    carnivalOptions <- defaultLpSolveCarnivalOptions()
    
    # Create output directory and set it in options
    dir.create("ToyExample3", showWarnings = FALSE)
    carnivalOptions\$outputFolder <- "ToyExample3"
    
    # 3. Generate LP and parsed data files using generateLpFileCarnival
    generateLpFileCarnival(perturbations = toy_perturbations_ex1,
                           measurements = toy_measurements_ex1, 
                           priorKnowledgeNetwork = toy_network_ex1, 
                           carnivalOptions = carnivalOptions)
    
    # Dynamically locate the generated LP and parsed data files in the output directory
    lp_files <- list.files("ToyExample3", pattern = "\\\\.lp\$", full.names = TRUE)
    rdata_files <- list.files("ToyExample3", pattern = "parsedData.*\\\\.RData\$", full.names = TRUE)
    
    lpFilename <- if (length(lp_files) > 0) lp_files[1] else "ToyExample3/lpFile.lp"
    parsedDataFile <- if (length(rdata_files) > 0) rdata_files[1] else "ToyExample3/parsedData.RData"
    
    # 4. Run CARNIVAL optimization from the generated files using runFromLpCarnival
    resultsFromLp <- runFromLpCarnival(lpFile = lpFilename,
                                       parsedDataFile = parsedDataFile,
                                       carnivalOptions = defaultLpSolveCarnivalOptions())
    
    # Write named output files for the meaningful results
    saveRDS(resultsFromLp, "ToyExample3/resultsFromLp.Rds")
    
    if (!is.null(resultsFromLp\$weightedSIF)) {
      write.csv(resultsFromLp\$weightedSIF, "ToyExample3/weightedSIF.csv", row.names = FALSE)
    }
    
    if (!is.null(resultsFromLp\$nodesAttributes)) {
      write.csv(resultsFromLp\$nodesAttributes, "ToyExample3/nodesAttributes.csv", row.names = FALSE)
    }

    writeLines(c(
        '"BIOC_CARNIVAL_TWO_STEP_CARNIVAL":',
        paste0('    CARNIVAL: ', as.character(packageVersion('CARNIVAL')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_two_step_carnival.csv versions.yml
    """
}

workflow BIOC_CARNIVAL_TWO_STEP_CARNIVAL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ toy_perturbations_ex1.RData, toy_measurements_ex1.RData, toy_network_ex1.RData ] ]

    main:
    BIOC_CARNIVAL_TWO_STEP_CARNIVAL(ch_input)

    emit:
    tables   = BIOC_CARNIVAL_TWO_STEP_CARNIVAL.out.tables
    plots    = BIOC_CARNIVAL_TWO_STEP_CARNIVAL.out.plots
    objects  = BIOC_CARNIVAL_TWO_STEP_CARNIVAL.out.objects
    versions = BIOC_CARNIVAL_TWO_STEP_CARNIVAL.out.versions
}
