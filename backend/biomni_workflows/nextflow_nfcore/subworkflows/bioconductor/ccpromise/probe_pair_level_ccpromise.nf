#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CCPROMISE — probe_pair_level_ccpromise
// Perform CCPROMISE analysis at the probe pair level to evaluate associations and correlations between individual probe pairs across two genomic datasets.
// Input: exmplGeneSet, exmplESet, exmplMSet, exmplPat
// Container: quay.io/biocontainers/bioconductor-ccpromise:1.36.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, CCPROMISE
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the CCPROMISE package and example datasets
//  * 2. [Core Analysis] Run the PrbPROMISE function at the probe pair level with fast negative binomial permutation
//  * 3. [Core Analysis] Inspect the probe-pair-level correlation results
//  * 4. [Core Analysis] Inspect the probe-pair-level PROMISE results

nextflow.enable.dsl = 2

process BIOC_CCPROMISE_PROBE_PAIR_LEVEL_CCPROMISE {
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
    .bm_deps <- c("CCPROMISE", "Biobase")
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
    
    # 1. Load required libraries
    library(CCPROMISE)
    library(Biobase)
    
    # Helper function to robustly read the input files
    read_input <- function(name) {
      if (file.exists(name)) {
        return(readRDS(name))
      } else if (file.exists(paste0(name, ".rds"))) {
        return(readRDS(paste0(name, ".rds")))
      } else {
        stop(paste("Required input file not found:", name))
      }
    }
    
    # Load the user-provided input datasets from the working directory
    exmplGeneSet <- read_input("exmplGeneSet")
    exmplESet <- read_input("exmplESet")
    exmplMSet <- read_input("exmplMSet")
    exmplPat <- read_input("exmplPat")
    
    # 2. Run the PrbPROMISE function at the probe pair level
    test2 <- PrbPROMISE(geneSet=exmplGeneSet, 
                  ESet=exmplESet, 
                  MSet=exmplMSet, 
                  promise.pattern=exmplPat,
                  strat.var=NULL,
                  prlbl=c('LC50', 'MRD22', 'EFS', 'PR3'), 
                  EMlbl=c("Expr", "Methyl"),
                  nbperm=TRUE,
                  max.ntail=10,
                  nperms=100,
                  seed=13)
    
    # 3. Inspect and save the probe-pair-level correlation results
    cor_results <- test2\$CORres
    cat("Probe-pair-level correlation results (head):\n")
    print(head(cor_results))
    write.csv(cor_results, file = "probe_pair_correlation_results.csv", row.names = TRUE)
    
    # 4. Inspect and save the probe-pair-level PROMISE results
    promise_results <- test2\$PRres
    cat("\nProbe-pair-level PROMISE results (head):\n")
    print(head(promise_results))
    write.csv(promise_results, file = "probe_pair_promise_results.csv", row.names = TRUE)
    
    # Save the complete output object
    saveRDS(test2, file = "probe_pair_promise_output.rds")

    writeLines(c(
        '"BIOC_CCPROMISE_PROBE_PAIR_LEVEL_CCPROMISE":',
        paste0('    CCPROMISE: ', as.character(packageVersion('CCPROMISE')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_probe_pair_level_ccpromise.csv versions.yml
    """
}

workflow BIOC_CCPROMISE_PROBE_PAIR_LEVEL_CCPROMISE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ exmplGeneSet, exmplESet, exmplMSet, exmplPat ] ]

    main:
    BIOC_CCPROMISE_PROBE_PAIR_LEVEL_CCPROMISE(ch_input)

    emit:
    tables   = BIOC_CCPROMISE_PROBE_PAIR_LEVEL_CCPROMISE.out.tables
    plots    = BIOC_CCPROMISE_PROBE_PAIR_LEVEL_CCPROMISE.out.plots
    objects  = BIOC_CCPROMISE_PROBE_PAIR_LEVEL_CCPROMISE.out.objects
    versions = BIOC_CCPROMISE_PROBE_PAIR_LEVEL_CCPROMISE.out.versions
}
