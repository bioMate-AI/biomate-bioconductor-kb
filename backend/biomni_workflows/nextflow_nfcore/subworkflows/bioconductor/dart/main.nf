#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DART — step_by_step_dart
// Build, evaluate, and prune a relevance network step-by-step to predict signature activity scores in training and independent datasets.
// Input: vdx.data, modelSig, mainz.data
// Container: quay.io/biocontainers/bioconductor-dart:1.58.0--r45hdfd78af_0
// R packages: Biobase, breastcancermainz, breastcancervdx, DART
// Bioconductor: 3.20 | R: 4.4
// Requires: DART
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Build the relevance network using BuildRN
//  * 2. [Core Analysis] Evaluate network consistency using EvalConsNet
//  * 3. [Core Analysis] Prune inconsistent edges using PruneNet
//  * 4. [Core Analysis] Predict signature activity scores in the training dataset using PredActScore
//  * 5. [Core Analysis] Predict signature activity scores in an independent dataset using PredActScore

nextflow.enable.dsl = 2

process BIOC_DART_STEP_BY_STEP_DART {
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
    .bm_deps <- c("Biobase", "breastcancermainz", "breastcancervdx", "DART")
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
        
        library(DART)
        
        # Helper function to load input files robustly
        load_file <- function(path) {
          if (!file.exists(path)) {
            stop(paste("Required input file missing:", path))
          }
          
          # Try RDS
          obj <- tryCatch(readRDS(path), error = function(e) NULL)
          if (!is.null(obj)) return(obj)
          
          # Try reading as a matrix/data frame (TSV)
          obj <- tryCatch({
            mat <- as.matrix(read.table(path, header = TRUE, row.names = 1, sep = "\t", check.names = FALSE))
            if (ncol(mat) == 0) stop()
            mat
          }, error = function(e) NULL)
          if (!is.null(obj)) return(obj)
          
          # Try reading as a matrix/data frame (CSV)
          obj <- tryCatch({
            mat <- as.matrix(read.csv(path, header = TRUE, row.names = 1, check.names = FALSE))
            if (ncol(mat) == 0) stop()
            mat
          }, error = function(e) NULL)
          if (!is.null(obj)) return(obj)
          
          # Try reading as a named vector (TSV)
          obj <- tryCatch({
            tbl <- read.table(path, header = FALSE, sep = "\t", stringsAsFactors = FALSE)
            vec <- as.numeric(tbl[[2]])
            names(vec) <- as.character(tbl[[1]])
            vec
          }, error = function(e) NULL)
          if (!is.null(obj)) return(obj)
          
          # Try reading as a named vector (CSV)
          obj <- tryCatch({
            tbl <- read.csv(path, header = FALSE, stringsAsFactors = FALSE)
            vec <- as.numeric(tbl[[2]])
            names(vec) <- as.character(tbl[[1]])
            vec
          }, error = function(e) NULL)
          if (!is.null(obj)) return(obj)
          
          stop(paste("Failed to parse file:", path))
        }
        
        # Load inputs
        vdx.data_raw <- load_file("vdx.data")
        mainz.data_raw <- load_file("mainz.data")
        modelSig_raw <- load_file("modelSig")
        
        # Format vdx.data and mainz.data as matrices
        vdx.data <- as.matrix(vdx.data_raw)
        mainz.data <- as.matrix(mainz.data_raw)
        
        # Format modelSig as a named numeric vector
        if (is.list(modelSig_raw) && !is.data.frame(modelSig_raw)) {
          modelSig <- unlist(modelSig_raw)
        } else if (is.matrix(modelSig_raw) || is.data.frame(modelSig_raw)) {
          if (ncol(modelSig_raw) == 1) {
            modelSig <- as.numeric(modelSig_raw[, 1])
            names(modelSig) <- rownames(modelSig_raw)
          } else {
            modelSig <- as.numeric(modelSig_raw[, 2])
            names(modelSig) <- as.character(modelSig_raw[, 1])
          }
        } else {
          modelSig <- as.numeric(modelSig_raw)
          names(modelSig) <- names(modelSig_raw)
        }
        
        # 1. Build the relevance network
        rn.o <- BuildRN(vdx.data, modelSig, fdr=0.000001)
        
        # 2. Evaluate network consistency
        evalNet.o <- EvalConsNet(rn.o)
        
        # 3. Prune inconsistent edges
        prNet.o <- PruneNet(evalNet.o)
        
        # 4. Predict signature activity scores in the training dataset
        pred.o <- PredActScore(prNet.o, vdx.data)
        
        # 5. Predict signature activity scores in an independent dataset
        pred.mainz.o <- PredActScore(prNet.o, mainz.data)
        
        # Save outputs as RDS
        saveRDS(rn.o, "rn.o.rds")
        saveRDS(evalNet.o, "evalNet.o.rds")
        saveRDS(prNet.o, "prNet.o.rds")
        saveRDS(pred.o, "pred.o.rds")
        saveRDS(pred.mainz.o, "pred.mainz.o.rds")
        
        # Save predictions as CSV
        write.csv(data.frame(Sample = names(pred.o\$score), Score = pred.o\$score), "predictions_vdx.csv", row.names = FALSE)
        write.csv(data.frame(Sample = names(pred.mainz.o\$score), Score = pred.mainz.o\$score), "predictions_mainz.csv", row.names = FALSE)
        
        # Save consistency metrics
        write.csv(data.frame(Metric = names(evalNet.o\$netcons), Value = as.numeric(evalNet.o\$netcons)), "network_consistency.csv", row.names = FALSE)
        
        # Save a summary text file
        summary_conn <- file("pipeline_summary.txt", "w")
        cat("--- DART Pipeline Summary ---\n", file = summary_conn)
        cat("Relevance Network Nodes:", dim(rn.o\$adj)[1], "\n", file = summary_conn)
        cat("Relevance Network Edges:", sum(rn.o\$adj == 1)/2, "\n", file = summary_conn)
        cat("Consistency Score (fconsE):", evalNet.o\$netcons["fconsE"], "\n", file = summary_conn)
        cat("Consistency P-value:", evalNet.o\$netcons["Pval(consist)"], "\n", file = summary_conn)
        cat("Pruned Network Nodes:", dim(prNet.o\$pradjMC)[1], "\n", file = summary_conn)
        cat("Pruned Network Edges:", sum(prNet.o\$pradjMC)/2, "\n", file = summary_conn)
        close(summary_conn)

    writeLines(c(
        '"BIOC_DART_STEP_BY_STEP_DART":',
        paste0('    DART: ', as.character(packageVersion('DART')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_step_by_step_dart.csv versions.yml
    """
}

workflow BIOC_DART_STEP_BY_STEP_DART_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ vdx.data, modelSig, mainz.data ] ]

    main:
    BIOC_DART_STEP_BY_STEP_DART(ch_input)

    emit:
    tables   = BIOC_DART_STEP_BY_STEP_DART.out.tables
    plots    = BIOC_DART_STEP_BY_STEP_DART.out.plots
    objects  = BIOC_DART_STEP_BY_STEP_DART.out.objects
    versions = BIOC_DART_STEP_BY_STEP_DART.out.versions
}
