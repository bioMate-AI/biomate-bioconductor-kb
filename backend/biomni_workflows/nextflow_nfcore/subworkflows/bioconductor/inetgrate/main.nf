#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: iNETgrate — inetgrate_pipeline
// Integrate gene expression and DNA methylation data to build a gene network, identify modules, compute eigengenes, and perform survival analysis to classify pati
// Input: genExpr, genExprSampleInfo, rawDnam, clinical, locus2gene
// Container: quay.io/biocontainers/bioconductor-inetgrate:1.4.0--r44hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Pigengene, iNETgrate, org.Hs.eg.db
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define clinical settings and clean/preprocess all input datasets using cleanAllData
//  * 2. [Core Analysis] Filter and select genes/loci correlated with survival using electGenes
//  * 3. [Core Analysis] Compute gene-level DNA methylation values (eigenloci) using computEigenloci
//  * 4. [Input & Preparation] Construct the integrated gene network and identify modules using makeNetwork
//  * 5. [Core Analysis] Calculate module eigengenes using computEigengenes
//  * 6. [Core Analysis] Perform survival analysis (AFT/Cox regression) to identify predictive modules using analyzeSurvival
//  * 7. [Core Analysis] Extract the best model weights using bestInetgrator
//  * 8. [Core Analysis] Perform pathway enrichment analysis on selected modules using Pigengene::get.enriched.pw

nextflow.enable.dsl = 2

process BIOC_INETGRATE_INETGRATE_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    tuple val(meta), path("qc_metrics.json"), emit: qc_metrics
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("iNETgrate", "org.Hs.eg.db")
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
    library(iNETgrate)
    library(org.Hs.eg.db)
    
    # Helper function to load inputs robustly from the working directory
    load_input <- function(var_name) {
      extensions <- c(".rds", ".csv", ".tsv", ".txt", "")
      for (ext in extensions) {
        file_path <- paste0(var_name, ext)
        if (file.exists(file_path)) {
          if (grepl("\\\\.rds\$", file_path, ignore.case = TRUE)) {
            return(readRDS(file_path))
          }
          res <- tryCatch({
            read.csv(file_path, row.names = 1, check.names = FALSE, stringsAsFactors = FALSE)
          }, error = function(e) {
            read.csv(file_path, check.names = FALSE, stringsAsFactors = FALSE)
          })
          return(res)
        }
      }
      stop(paste("Error: Could not find input file for", var_name))
    }
    
    # Read user inputs
    genExpr <- as.matrix(load_input("genExpr"))
    genExprSampleInfo <- load_input("genExprSampleInfo")
    rawDnam <- as.matrix(load_input("rawDnam"))
    clinical <- load_input("clinical")
    locus2gene <- load_input("locus2gene")
    
    # Set up paths
    resPath <- "iNETgrateRes"
    netPath <- file.path(resPath, "net")
    survivalPath <- file.path(netPath, "surv")
    dir.create(survivalPath, showWarnings = FALSE, recursive = TRUE)
    
    # Dynamically infer clinical settings columns and categories
    riskCatCol <- grep("risk|category|group", colnames(clinical), ignore.case = TRUE, value = TRUE)[1]
    if (is.na(riskCatCol)) riskCatCol <- colnames(clinical)[ncol(clinical)]
    
    riskFactorCol <- grep("factor|abnormalities", colnames(clinical), ignore.case = TRUE, value = TRUE)[1]
    if (is.na(riskFactorCol)) riskFactorCol <- riskCatCol
    
    risk_levels <- unique(na.omit(clinical[[riskCatCol]]))
    riskHigh <- grep("high|poor|severe|bad", risk_levels, ignore.case = TRUE, value = TRUE)[1]
    riskLow <- grep("low|favorable|good|mild", risk_levels, ignore.case = TRUE, value = TRUE)[1]
    if (is.na(riskHigh)) riskHigh <- risk_levels[1]
    if (is.na(riskLow)) riskLow <- risk_levels[length(risk_levels)]
    if (riskHigh == riskLow && length(risk_levels) > 1) {
        riskLow <- setdiff(risk_levels, riskHigh)[1]
    }
    
    vitalCol <- grep("vital|status|event|survival", colnames(clinical), ignore.case = TRUE, value = TRUE)[1]
    if (is.na(vitalCol)) vitalCol <- colnames(clinical)[2]
    event_levels <- unique(na.omit(clinical[[vitalCol]]))
    event_val <- grep("dead|death|1|deceased|event", event_levels, ignore.case = TRUE, value = TRUE)[1]
    if (is.na(event_val)) event_val <- event_levels[1]
    
    # Step 1: Clean and preprocess all input datasets
    cleanedToy <- cleanAllData(genExpr=genExpr,
                                genExprSampleInfo=genExprSampleInfo, 
                                rawDnam=rawDnam, savePath=resPath, 
                                clinical=clinical, 
                                riskCatCol=riskCatCol, riskFactorCol=riskFactorCol, 
                                riskHigh=riskHigh, riskLow=riskLow, 
                                verbose=1)
    
    cleaned <- cleanedToy
    if (is.null(cleaned\$locus2gene)) {
      cleaned\$locus2gene <- locus2gene
    }
    
    # Infer intermediate risk category for subsetting
    all_risks <- unique(as.character(cleaned\$survival\$Risk1))
    subSet_val <- setdiff(all_risks, c("High", "Low"))[1]
    if (is.na(subSet_val)) subSet_val <- all_risks[1]
    
    # Step 2: Filter and select genes/loci correlated with survival
    elected <- electGenes(genExpr=cleaned\$genExpr, dnam=cleaned\$dnam,
                           survival=cleaned\$survival, savePath=resPath, 
                           event=event_val, locus2gene=cleaned\$locus2gene, 
                           doAlLoci=FALSE, verbose=1)
    
    # Step 3: Compute gene-level DNA methylation values (eigenloci)
    patientLabel <- setNames(as.character(cleaned\$survival\$Risk1),
                             nm=rownames(cleaned\$survival))
    inBoth <- intersect(colnames(cleaned\$dnam), names(patientLabel))
    computedEloci <- computEigenloci(dnam=cleaned\$dnam[ ,inBoth],
        Labels=patientLabel[inBoth],
        geNames=elected\$unionGenes,
        locus2gene=cleaned\$locus2gene,
        plotPath=resPath,
        Label1="Low", Label2="High",
        verbose=1)
    
    # Step 4: Construct the integrated gene network and identify modules
    eigenloci <- computedEloci\$eigenloci
    madeNet <- makeNetwork(genExpr=cleaned\$genExpr, eigenloci=eigenloci,
                                geNames=elected\$unionGenes, mus=0.6, 
                                doRemoveTOM=TRUE, outPath=netPath, 
                                verbose=1)
    print(madeNet\$mu2modules[,1:5, drop=FALSE])               
    
    # Step 5: Calculate module eigengenes
    e1 <- computEigengenes(genExpr=cleaned\$genExpr, eigenloci=eigenloci, 
                              netPath=netPath, geNames=elected\$unionGenes,
                              Labels=patientLabel, Label1="Low", 
                              Label2="High", mus=c(0.6), combiningMu=NA,
                              doIgnoreNas=TRUE, survival=cleaned\$survival, 
                              event=event_val, verbose=1, 
                              mu2modules=madeNet\$mu2modules)
    
    # Step 6: Perform survival analysis (AFT/Cox regression)
    s1 <- analyzeSurvival(survival=cleaned\$survival, 
                            favRisk="High", 
                            subSet=subSet_val, mus=0.6, 
                            netPath=netPath, outPath=survivalPath, 
                            xmax1=15, xmin1=0, verbose=1)
    
    # Step 7: Extract the best model weights
    inetgrator <- bestInetgrator(bestPvalues=s1\$bestPvalues, 
                      usefuLoci=computedEloci\$usefuLoci,
                      lociPigen=computedEloci\$lociPigen,
                      netPath=netPath)
    
    # Step 8: Perform pathway enrichment analysis on selected modules
    selectedModules <- names(inetgrator\$modules)
    geneList <- list()
    for(m1 in selectedModules)
        geneList[[m1]] <- names(inetgrator\$modules[[m1]]\$genes)
    
    got <- Pigengene::get.enriched.pw(geneList, idType="SYMBOL",
                     pathwayDb="KEGG", outPath=survivalPath)
    
    # Save meaningful results to working directory
    saveRDS(cleaned, file = "cleaned_data.rds")
    saveRDS(elected, file = "elected_genes.rds")
    saveRDS(computedEloci, file = "computed_eigenloci.rds")
    saveRDS(madeNet, file = "made_network.rds")
    saveRDS(e1, file = "computed_eigengenes.rds")
    saveRDS(s1, file = "survival_analysis_results.rds")
    saveRDS(inetgrator, file = "best_inetgrator.rds")
    saveRDS(got, file = "enriched_pathways.rds")
    
    write.csv(as.data.frame(madeNet\$mu2modules), "mu2modules.csv", row.names = TRUE)
    write.csv(as.data.frame(s1\$bestPvalues), "best_pvalues.csv", row.names = TRUE)
    
    message("Pipeline completed successfully. Outputs saved to working directory and iNETgrateRes/.")
    # ── BIOC_QC_HARNESS — Phase 3c bulk adoption (missing-value handling) ───
    # Defensive scan: list every *.rds the workflow produced, load each one,
    # compute NA fraction across numeric cells where the artifact is a
    # matrix or data.frame. Report max NA fraction across artifacts.
    # Threshold from bioc_missing_value_handling: < 5% pass.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()
    .na_fracs <- numeric(0)
    .scanned_files <- character(0)
    for (.rds_file in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .obj <- tryCatch(readRDS(.rds_file), error = function(e) NULL)
      .mat <- if (is.matrix(.obj) || is.data.frame(.obj)) .obj else NULL
      if (!is.null(.mat)) {
        .vals <- suppressWarnings(as.numeric(as.matrix(.mat)))
        if (length(.vals) > 0) {
          .na_fracs <- c(.na_fracs, mean(is.na(.vals)))
          .scanned_files <- c(.scanned_files, .rds_file)
        }
      }
    }
    .na_max <- if (length(.na_fracs) > 0) round(max(.na_fracs), 4) else NA_real_
    .gates_by_label[["missing-value handling"]] <- list(
      gate_row = "bioc_missing_value_handling",
      metric_name = "na_fraction_remaining",
      metric_value = .na_max,
      passes = isTRUE(is.finite(.na_max) && .na_max < 0.05),
      status = if (is.finite(.na_max)) paste0("computed (scanned ", length(.scanned_files), " rds files)")
               else "not_computed (no matrix/data.frame .rds artifact present)"
    )
    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_INETGRATE_INETGRATE_PIPELINE",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling"),
      gates_by_label = .gates_by_label,
      evidence_tier = "SILVER (Lazar 2013 NAR; <5% community convention)",
      harness_version = "0.1.0-bulk-mv"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_INETGRATE_INETGRATE_PIPELINE":',
        paste0('    iNETgrate: ', as.character(packageVersion('iNETgrate')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_inetgrate_pipeline.csv versions.yml
    """
}

workflow BIOC_INETGRATE_INETGRATE_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genExpr, genExprSampleInfo, rawDnam, clinical, locus2gene ] ]

    main:
    BIOC_INETGRATE_INETGRATE_PIPELINE(ch_input)

    emit:
    tables   = BIOC_INETGRATE_INETGRATE_PIPELINE.out.tables
    plots    = BIOC_INETGRATE_INETGRATE_PIPELINE.out.plots
    objects  = BIOC_INETGRATE_INETGRATE_PIPELINE.out.objects
    versions = BIOC_INETGRATE_INETGRATE_PIPELINE.out.versions
}
