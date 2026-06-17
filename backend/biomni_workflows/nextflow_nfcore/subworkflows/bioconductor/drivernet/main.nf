#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DriverNet — driver_gene_prediction
// Identify and rank candidate cancer driver genes by integrating patient mutation data, expression outlier data, and a gene-gene influence graph, followed by sign
// Input: samplePatientMutationMatrix.ext, samplePatientOutlierMatrix.ext, sampleInfluenceGraph.ext, sampleGeneNames.ext
// Container: quay.io/biocontainers/bioconductor-drivernet:1.50.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: DriverNet
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Compute driver genes using a greedy algorithm with computeDrivers
//  * 2. [Core Analysis] Assess statistical significance of driver genes using a randomization framework with computeRandomizedResult
//  * 3. [Visualization & Output] Summarize the results using resultSummary

nextflow.enable.dsl = 2

process BIOC_DRIVERNET_DRIVER_GENE_PREDICTION {
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
    .bm_deps <- c("DriverNet")
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
    
    # Load required library
    library(DriverNet)
    
    # Helper function to read input files robustly
    read_input <- function(filename) {
      if (!file.exists(filename)) {
        stop(paste("Required input file not found:", filename))
      }
    
      # Try reading as RDS first
      res <- tryCatch(readRDS(filename), error = function(e) NULL)
      if (!is.null(res)) return(res)
    
      # If it's the gene names file, read as character vector
      if (grepl("GeneNames", filename, ignore.case = TRUE)) {
        return(as.character(readLines(filename)))
      }
    
      # Otherwise, read as matrix
      mat <- tryCatch({
        d <- read.table(filename, header = TRUE, row.names = 1, sep = "\t", check.names = FALSE)
        as.matrix(d)
      }, error = function(e) {
        tryCatch({
          d <- read.csv(filename, header = TRUE, row.names = 1, check.names = FALSE)
          as.matrix(d)
        }, error = function(e2) {
          as.matrix(read.table(filename, header = FALSE))
        })
      })
      return(mat)
    }
    
    # Read user input files from the working directory
    samplePatientMutationMatrix <- read_input("samplePatientMutationMatrix.ext")
    samplePatientOutlierMatrix <- read_input("samplePatientOutlierMatrix.ext")
    sampleInfluenceGraph <- read_input("sampleInfluenceGraph.ext")
    sampleGeneNames <- read_input("sampleGeneNames.ext")
    
    # 1. Compute driver genes using a greedy algorithm
    driversList = computeDrivers(samplePatientMutationMatrix, 
                  samplePatientOutlierMatrix,sampleInfluenceGraph,
                  outputFolder=NULL, printToConsole=FALSE)
    
    drivers(driversList)[1:10]
    
    # 2. Assess statistical significance of driver genes using a randomization framework
    randomDriversResult = computeRandomizedResult(
      patMutMatrix=samplePatientMutationMatrix,
      patOutMatrix=samplePatientOutlierMatrix, 
      influenceGraph=sampleInfluenceGraph,
      geneNameList= sampleGeneNames, outputFolder=NULL, 
      printToConsole=FALSE,numberOfRandomTests=20, weight=FALSE, 
      purturbGraph=FALSE, purturbData=TRUE)
    
    # 3. Summarize the results
    res = resultSummary(driversList, randomDriversResult, 
          samplePatientMutationMatrix,sampleInfluenceGraph,
          outputFolder=NULL, printToConsole=FALSE)
    res[1:2,]
    
    # Write output files
    saveRDS(driversList, file = "driversList.rds")
    saveRDS(randomDriversResult, file = "randomDriversResult.rds")
    write.csv(res, file = "drivernet_results_summary.csv", row.names = FALSE)
    
    # Extract and write the ranked list of predicted driver genes
    predicted_drivers <- drivers(driversList)
    write.table(predicted_drivers, file = "predicted_drivers.txt", 
                row.names = FALSE, col.names = FALSE, quote = FALSE)

    writeLines(c(
        '"BIOC_DRIVERNET_DRIVER_GENE_PREDICTION":',
        paste0('    DriverNet: ', as.character(packageVersion('DriverNet')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_driver_gene_prediction.csv versions.yml
    """
}

workflow BIOC_DRIVERNET_DRIVER_GENE_PREDICTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ samplePatientMutationMatrix.ext, samplePatientOutlierMatrix.ext, sampleInfluenceGraph.ext, sampleGeneNames.ext ] ]

    main:
    BIOC_DRIVERNET_DRIVER_GENE_PREDICTION(ch_input)

    emit:
    tables   = BIOC_DRIVERNET_DRIVER_GENE_PREDICTION.out.tables
    plots    = BIOC_DRIVERNET_DRIVER_GENE_PREDICTION.out.plots
    objects  = BIOC_DRIVERNET_DRIVER_GENE_PREDICTION.out.objects
    versions = BIOC_DRIVERNET_DRIVER_GENE_PREDICTION.out.versions
}
