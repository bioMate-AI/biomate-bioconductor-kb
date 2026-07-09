#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GSALightning — unpaired_gsa
// Perform permutation-based gene set analysis on unpaired two-sample expression data with optional restandardization.
// Input: expression_matrix.csv, sample_metadata.csv, gene_sets.gmt
// Container: quay.io/biocontainers/bioconductor-gsalightning:1.38.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GSALightning
// Visualizations: plot (ggplot/base)
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter out genes with zero variance
//  * 2. [Core Analysis] Run GSALight with specified statistics, size filters, and missing gene handling
//  * 3. [Core Analysis] Run GSALight with restandardization enabled to obtain corrected p-values and q-values

nextflow.enable.dsl = 2

process BIOC_GSALIGHTNING_UNPAIRED_GSA {
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
    .bm_deps <- c("GSALightning")
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
        library(GSALightning)
        
        # Helper function to read GMT files into a list of gene sets
        read_gmt <- function(file) {
          lines <- readLines(file)
          gsets <- list()
          for (line in lines) {
            if (trimws(line) == "") next
            parts <- strsplit(line, "\t")[[1]]
            if (length(parts) >= 3) {
              genes <- parts[3:length(parts)]
              genes <- genes[genes != "" & !is.na(genes)]
              gsets[[parts[1]]] <- genes
            }
          }
          return(gsets)
        }
        
        # 1. Read User Input Files
        expression <- as.matrix(read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE))
        mode(expression) <- "numeric"
        expression <- na.omit(expression)
        
        sampleInfo <- read.csv("sample_metadata.csv", stringsAsFactors = FALSE)
        # Ensure the TN column exists; if not, fallback to the second column
        if (!"TN" %in% colnames(sampleInfo)) {
          colnames(sampleInfo)[2] <- "TN"
        }
        
        targetGenes <- read_gmt("gene_sets.gmt")
        
        # 2. Filter out genes with zero variance
        expression <- expression[apply(expression,1,sd) != 0,]
        
        # 3. Run GSALight with specified statistics, size filters, and missing gene handling
        GSALightResults <- GSALight(eset = expression, fac = factor(sampleInfo\$TN), gs = targetGenes, nperm = 1000, minsize = 10, rmGSGenes = 'gene')
        write.csv(GSALightResults, "gsa_results_basic.csv", row.names = TRUE)
        
        GSALightResults <- GSALight(eset = expression, fac = factor(sampleInfo\$TN), gs = targetGenes, nperm = 1000, method = 'maxmean', restandardize = FALSE, minsize = 10, maxsize = 30, rmGSGenes = 'gene', verbose = FALSE)
        write.csv(GSALightResults, "gsa_results_maxmean_norestand.csv", row.names = TRUE)
        
        # Save the non-restandardized results for plotting
        GSALightResultsNoReStand <- GSALightResults
        
        # 4. Run GSALight with restandardization enabled to obtain corrected p-values and q-values
        GSALightResultsReStand <- GSALight(eset = expression, fac = factor(sampleInfo\$TN), gs = targetGenes, nperm = NULL, method = 'maxmean', restandardize = TRUE, minsize = 10, rmGSGenes = 'gene', verbose = FALSE)
        write.csv(GSALightResultsReStand, "gsa_results_restandardized.csv", row.names = TRUE)
        
        # 5. Generate Diagnostic Plots (Histogram of P-values)
        pdf("pvalue_comparison_histogram.pdf", width = 10, height = 5)
        par(mfrow = c(1, 2))
        
        pcol_norestand <- grep("p-value", colnames(GSALightResultsNoReStand), value = TRUE)[1]
        pcol_restand <- grep("p-value", colnames(GSALightResultsReStand), value = TRUE)[1]
        
        if (!is.na(pcol_norestand)) {
          hist(GSALightResultsNoReStand[, pcol_norestand], 
               main = "Without Restandardization", 
               xlab = "p-value", 
               col = "skyblue", 
               border = "white")
        }
        
        if (!is.na(pcol_restand)) {
          hist(GSALightResultsReStand[, pcol_restand], 
               main = "With Restandardization", 
               xlab = "p-value", 
               col = "tomato", 
               border = "white")
        }
        dev.off()
        
        # Save R objects for downstream analysis
        saveRDS(GSALightResultsNoReStand, "GSALightResultsNoReStand.rds")
        saveRDS(GSALightResultsReStand, "GSALightResultsReStand.rds")
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
      process = "BIOC_GSALIGHTNING_UNPAIRED_GSA",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling"),
      gates_by_label = .gates_by_label,
      evidence_tier = "SILVER (Lazar 2013 NAR; <5% community convention)",
      harness_version = "0.1.0-bulk-mv"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_GSALIGHTNING_UNPAIRED_GSA":',
        paste0('    GSALightning: ', as.character(packageVersion('GSALightning')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_unpaired_gsa.csv versions.yml
    """
}

workflow BIOC_GSALIGHTNING_UNPAIRED_GSA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv, sample_metadata.csv, gene_sets.gmt ] ]

    main:
    BIOC_GSALIGHTNING_UNPAIRED_GSA(ch_input)

    emit:
    tables   = BIOC_GSALIGHTNING_UNPAIRED_GSA.out.tables
    plots    = BIOC_GSALIGHTNING_UNPAIRED_GSA.out.plots
    objects  = BIOC_GSALIGHTNING_UNPAIRED_GSA.out.objects
    versions = BIOC_GSALIGHTNING_UNPAIRED_GSA.out.versions
}
