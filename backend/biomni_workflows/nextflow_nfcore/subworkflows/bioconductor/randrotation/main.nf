#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: randRotation — linear_model_batch_correction
// Perform batch effect correction and linear model analysis while obtaining unskewed, rotation-based p-values and false discovery rates (FDR).
// Input: edata, pdata
// Container: quay.io/biocontainers/bioconductor-randrotation:1.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: limma, randRotation, sva
// Visualizations: plot (ggplot/base)
// QC: batch-effect correction
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load User Input Files
//  * 2. [Input & Preparation] Execute Documented Workflow
//  * 3. [Input & Preparation] Save Outputs

nextflow.enable.dsl = 2

process BIOC_RANDROTATION_LINEAR_MODEL_BATCH_CORRECTION {
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
    .bm_deps <- c("randRotation", "sva", "limma")
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
    library(randRotation)
    library(sva)
    library(limma)
    
    # --- Load User Input Files ---
    if (file.exists("pdata.rds")) {
      pdata <- readRDS("pdata.rds")
    } else if (file.exists("pdata.csv")) {
      pdata <- read.csv("pdata.csv", row.names = 1, stringsAsFactors = TRUE)
    } else if (file.exists("pdata.tsv")) {
      pdata <- read.delim("pdata.tsv", row.names = 1, stringsAsFactors = TRUE)
    } else {
      stop("pdata file not found (pdata.rds, pdata.csv, or pdata.tsv)")
    }
    
    if (file.exists("edata.rds")) {
      edata <- readRDS("edata.rds")
    } else if (file.exists("edata.csv")) {
      edata <- as.matrix(read.csv("edata.csv", row.names = 1))
    } else if (file.exists("edata.tsv")) {
      edata <- as.matrix(read.delim("edata.tsv", row.names = 1))
    } else {
      stop("edata file not found (edata.rds, edata.csv, or edata.tsv)")
    }
    
    # Ensure correct types and structures
    pdata\$batch <- as.factor(pdata\$batch)
    pdata\$phenotype <- as.factor(pdata\$phenotype)
    edata <- as.matrix(edata)
    
    # --- Execute Documented Workflow ---
    mod1 <- model.matrix(~1+phenotype, pdata)
    rr <- initBatchRandrot(Y = edata, X = mod1, coef.h = 2, batch = pdata\$batch)
    
    statistic <- function(Y, batch, mod){
      Y <- sva::ComBat(dat = Y, batch = batch, mod = mod)
      fit1 <- limma::lmFit(Y, design = mod)
      fit1 <- limma::eBayes(fit1)
      abs(fit1\$t[,2])
    }
    
    rs1 <- rotateStat(initialised.obj = rr, R = 10, statistic = statistic,
                       batch = pdata\$batch, mod = mod1)
    
    p.vals <- pFdr(rs1)
    fdr.q  <- pFdr(rs1, "fdr.q")
    fdr.qu <- pFdr(rs1, "fdr.qu")
    fdr.BH <- pFdr(rs1, "BH")
    
    # --- Save Outputs ---
    # Save RDS of the rotation statistics object
    saveRDS(rs1, "rotate_stat_results.rds")
    
    # Save CSV of the results
    results_df <- data.frame(
      Feature = rownames(edata),
      p_value = as.vector(p.vals),
      fdr_q = as.vector(fdr.q),
      fdr_qu = as.vector(fdr.qu),
      fdr_BH = as.vector(fdr.BH),
      stringsAsFactors = FALSE
    )
    write.csv(results_df, "randRotation_results.csv", row.names = FALSE)
    
    # Save PDF plots
    pdf("randRotation_plots.pdf", width = 10, height = 5)
    par(mfrow = c(1, 2))
    hist(p.vals, col = "lightgreen", main = "Histogram of Rotation p-values", xlab = "p-values")
    abline(h = nrow(edata)/10, col = "blue", lty = 2)
    qqunif(p.vals)
    dev.off()
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # batch-effect correction — declarative pass via corrected-output presence
    # (kBET acceptance metric is a future per-workflow follow-on).
    .bec_artifacts <- list.files(".", pattern = "(?i)(corrected|batch|combat|harmony|mnn).*\\.(rds|csv|h5ad)\$")
    .bec_passes <- length(.bec_artifacts) > 0
    .gates_by_label[["batch-effect correction"]] <- list(
      gate_row = "bioc_batch_effect_correction",
      metric_name = "batch_corrected_artifacts",
      metric_value = length(.bec_artifacts),
      passes = .bec_passes,
      status = if (.bec_passes) "computed (declarative; kBET acceptance pending)"
               else "not_computed (no batch-corrected artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_RANDROTATION_LINEAR_MODEL_BATCH_CORRECTION",
      domain  = "bioconductor",
      declared_qc_steps = c("batch-effect correction"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_RANDROTATION_LINEAR_MODEL_BATCH_CORRECTION":',
        paste0('    randRotation: ', as.character(packageVersion('randRotation')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_linear_model_batch_correction.csv versions.yml
    """
}

workflow BIOC_RANDROTATION_LINEAR_MODEL_BATCH_CORRECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ edata, pdata ] ]

    main:
    BIOC_RANDROTATION_LINEAR_MODEL_BATCH_CORRECTION(ch_input)

    emit:
    tables   = BIOC_RANDROTATION_LINEAR_MODEL_BATCH_CORRECTION.out.tables
    plots    = BIOC_RANDROTATION_LINEAR_MODEL_BATCH_CORRECTION.out.plots
    objects  = BIOC_RANDROTATION_LINEAR_MODEL_BATCH_CORRECTION.out.objects
    versions = BIOC_RANDROTATION_LINEAR_MODEL_BATCH_CORRECTION.out.versions
}
