#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SigCheck — survival_analysis
// Evaluate a gene signature's survival prediction performance against random signatures, known signatures, and permuted data.
// Input: nki, knownSignatures$cancer$VANTVEER
// Container: quay.io/biocontainers/bioconductor-sigcheck:2.42.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, SigCheck
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter out samples with missing metadata
//  * 2. [Core Analysis] Initialize the SigCheckObject and compute baseline survival performance
//  * 3. [Core Analysis] Run all comparison checks (random, known, permuted survival, permuted features)
//  * 4. [Visualization & Output] Plot the comparison distributions
//  * 5. [Core Analysis] Extract empirical p-values for each check

nextflow.enable.dsl = 2

process BIOC_SIGCHECK_SURVIVAL_ANALYSIS {
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
    .bm_deps <- c("SigCheck", "Biobase")
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
    
    library(SigCheck)
    library(Biobase)
    
    # Helper function to robustly load user input files (RDS or RData)
    load_input <- function(filename) {
      if (file.exists(filename)) {
        res <- try(readRDS(filename), silent=TRUE)
        if (!inherits(res, "try-error")) return(res)
        env <- new.env()
        res_load <- try(load(filename, envir=env), silent=TRUE)
        if (!inherits(res_load, "try-error")) {
          vars <- ls(env)
          if (length(vars) > 0) return(env[[vars[1]]])
        }
      }
      for (ext in c(".rds", ".RData", ".RDS", ".RDATA")) {
        fn <- paste0(filename, ext)
        if (file.exists(fn)) {
          res <- try(readRDS(fn), silent=TRUE)
          if (!inherits(res, "try-error")) return(res)
          env <- new.env()
          res_load <- try(load(fn, envir=env), silent=TRUE)
          if (!inherits(res_load, "try-error")) {
            vars <- ls(env)
            if (length(vars) > 0) return(env[[vars[1]]])
          }
        }
      }
      stop(paste("Could not find or load file:", filename))
    }
    
    # Load the required user inputs from the working directory
    nki <- load_input("nki")
    
    knownSignatures <- tryCatch({
      load_input("knownSignatures")
    }, error = function(e) {
      # Fallback if the signature is provided directly as a vector
      vv <- tryCatch({
        load_input("vantveer")
      }, error = function(e2) {
        load_input("VANTVEER")
      })
      list(cancer = list(VANTVEER = vv))
    })
    
    # Stage 1: Filter out samples with missing metadata
    nki <- nki[,!is.na(nki\$e.dmfs)]
    
    # Stage 2: Initialize the SigCheckObject and compute baseline survival performance
    check <- sigCheck(nki, classes="e.dmfs", survival="t.dmfs",
                      signature=knownSignatures\$cancer\$VANTVEER,
                      annotation="HUGO.gene.symbol",
                      validationSamples=which(nki\$series=="NKI2")) 
    
    baseline_pval <- check@survivalPval
    
    # Stage 3: Run all comparison checks (random, known, permuted survival, permuted features)
    nkiResults <- sigCheckAll(check, iterations=1000) 
    
    # Stage 4: Plot the comparison distributions to a PDF file
    pdf("sigcheck_plots.pdf", width=10, height=8)
    sigCheckPlot(nkiResults)
    dev.off()
    
    # Stage 5: Extract empirical p-values for each check and save results
    pvals <- data.frame(
      Check = c("Baseline", "Random", "Known", "PermutedSurvival", "PermutedFeatures"),
      Pval = c(
        baseline_pval,
        nkiResults\$checkRandom\$checkPval,
        nkiResults\$checkKnown\$checkPval,
        nkiResults\$checkPermutedSurvival\$checkPval,
        nkiResults\$checkPermutedFeatures\$checkPval
      )
    )
    
    write.csv(pvals, "sigcheck_pvalues.csv", row.names=FALSE)
    saveRDS(nkiResults, "sigcheck_results.rds")

    writeLines(c(
        '"BIOC_SIGCHECK_SURVIVAL_ANALYSIS":',
        paste0('    SigCheck: ', as.character(packageVersion('SigCheck')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_survival_analysis.csv versions.yml
    """
}

workflow BIOC_SIGCHECK_SURVIVAL_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ nki, knownSignatures$cancer$VANTVEER ] ]

    main:
    BIOC_SIGCHECK_SURVIVAL_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SIGCHECK_SURVIVAL_ANALYSIS.out.tables
    plots    = BIOC_SIGCHECK_SURVIVAL_ANALYSIS.out.plots
    objects  = BIOC_SIGCHECK_SURVIVAL_ANALYSIS.out.objects
    versions = BIOC_SIGCHECK_SURVIVAL_ANALYSIS.out.versions
}
