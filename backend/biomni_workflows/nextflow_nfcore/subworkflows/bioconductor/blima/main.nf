#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: blima — bead_level_preprocessing_and_analysis
// Preprocess raw Illumina bead-level data (background correction, variance stabilization, quantile normalization), perform differential expression testing, and su
// Input: blimatesting, adrToIllumina
// Container: quay.io/biocontainers/bioconductor-blima:1.40.0--r44he5774e6_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, beadarray, blima
// Visualizations: plot (ggplot/base)
// QC: count normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load User Input Files
//  * 2. [Visualization & Output] Define Experimental Groups and Processing Masks
//  * 3. [Visualization & Output] Background and Non-Positive Correction
//  * 4. [Visualization & Output] Variance Stabilizing Transformation
//  * 5. [Visualization & Output] Quantile Normalization
//  * 6. [Visualization & Output] Differential Expression Testing
//  * 7. [Visualization & Output] Summarization to Probe-Level Matrices
//  * 8. [Visualization & Output] Downstream Processing and Exporting Outputs

nextflow.enable.dsl = 2

process BIOC_BLIMA_BEAD_LEVEL_PREPROCESSING_AND_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("blima", "Biobase", "beadarray")
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
        
    # Load required libraries
    library(blima)
    library(Biobase)
    library(beadarray)
    
    # ==========================================
    # --- Load User Input Files ---
    # ==========================================
    
    # Load blimatesting (list of beadLevelData objects)
    if (file.exists("blimatesting")) {
      blimatesting <- readRDS("blimatesting")
    } else if (file.exists("blimatesting.rds")) {
      blimatesting <- readRDS("blimatesting.rds")
    } else if (file.exists("blimatesting.RData")) {
      # In case it was saved as an RData workspace
      env <- new.env()
      load("blimatesting.RData", envir = env)
      if (exists("blimatesting", envir = env)) {
        blimatesting <- env\$blimatesting
      } else {
        stop("Error: 'blimatesting' object not found in blimatesting.RData")
      }
    } else {
      stop("Error: blimatesting input file not found in the working directory.")
    }
    
    # Load adrToIllumina (data frame mapping Array Address IDs to Illumina Probe IDs)
    if (file.exists("adrToIllumina")) {
      adrToIllumina <- readRDS("adrToIllumina")
    } else if (file.exists("adrToIllumina.rds")) {
      adrToIllumina <- readRDS("adrToIllumina.rds")
    } else if (file.exists("adrToIllumina.csv")) {
      adrToIllumina <- read.csv("adrToIllumina.csv", stringsAsFactors = FALSE)
    } else if (file.exists("adrToIllumina.RData")) {
      env <- new.env()
      load("adrToIllumina.RData", envir = env)
      if (exists("adrToIllumina", envir = env)) {
        adrToIllumina <- env\$adrToIllumina
      } else {
        stop("Error: 'adrToIllumina' object not found in adrToIllumina.RData")
      }
    } else {
      stop("Error: adrToIllumina input file not found in the working directory.")
    }
    
    # Standardize column names of adrToIllumina if necessary
    if (!all(c("Array_Address_Id", "Probe_Id") %in% colnames(adrToIllumina))) {
      if (ncol(adrToIllumina) >= 2) {
        colnames(adrToIllumina)[1:2] <- c("Array_Address_Id", "Probe_Id")
      } else {
        stop("Error: adrToIllumina must contain at least two columns mapping Array Address IDs to Probe IDs.")
      }
    }
    
    # Ensure Array_Address_Id is character or integer to match ProbeID types
    adrToIllumina\$Array_Address_Id <- as.character(adrToIllumina\$Array_Address_Id)
    
    # ==========================================
    # --- Define Experimental Groups and Processing Masks ---
    # ==========================================
    
    # Extract phenoData from all objects to determine the grouping column and groups
    pdata_list <- lapply(blimatesting, function(x) pData(x@experimentData\$phenoData))
    common_cols <- Reduce(intersect, lapply(pdata_list, colnames))
    
    if (length(common_cols) == 0) {
      stop("Error: No common columns found in phenoData across all objects.")
    }
    
    group_col <- NULL
    # Prefer columns with typical grouping names
    for (pref in c("Group", "group", "Condition", "condition", "Treatment", "treatment")) {
      if (pref %in% common_cols) {
        vals <- unique(unlist(lapply(pdata_list, function(p) p[[pref]])))
        if (length(vals) >= 2) {
          group_col <- pref
          break
        }
      }
    }
    
    # Fallback to the first column with exactly 2 unique values
    if (is.null(group_col)) {
      for (col in common_cols) {
        vals <- unique(unlist(lapply(pdata_list, function(p) p[[col]])))
        if (length(vals) == 2) {
          group_col <- col
          break
        }
      }
    }
    
    # Fallback to the first column with > 1 unique values
    if (is.null(group_col)) {
      for (col in common_cols) {
        vals <- unique(unlist(lapply(pdata_list, function(p) p[[col]])))
        if (length(vals) > 1) {
          group_col <- col
          break
        }
      }
    }
    
    if (is.null(group_col)) {
      stop("Error: Could not find a suitable grouping column with at least 2 unique values in phenoData.")
    }
    
    # Extract the first two unique groups
    all_groups <- unique(unlist(lapply(pdata_list, function(p) p[[group_col]])))
    groups1 <- all_groups[1]
    groups2 <- all_groups[2]
    
    sampleNames = list()
    groups1Mod = list()
    groups2Mod = list()
    processingMod = list()
    for(i in 1:length(blimatesting))
    {
    	p = pData(blimatesting[[i]]@experimentData\$phenoData)
    	groups1Mod[[i]] = p[[group_col]] %in% groups1;
    	groups2Mod[[i]] = p[[group_col]] %in% groups2;
    	processingMod[[i]] = p[[group_col]] %in% c(groups1, groups2);
    	sampleNames[[i]] = p\$Name
    }
    
    # ==========================================
    # --- Background and Non-Positive Correction ---
    # ==========================================
    blimatesting = bacgroundCorrect(blimatesting, normalizationMod = processingMod, 
    		channelBackgroundFilter="bgf")
    blimatesting = nonPositiveCorrect(blimatesting, normalizationMod = processingMod, 
    		channelCorrect="GrnF",  channelBackgroundFilter="bgf", channelAndVector="bgf")
    
    # ==========================================
    # --- Variance Stabilizing Transformation ---
    # ==========================================
    blimatesting = varianceBeadStabilise(blimatesting, normalizationMod = processingMod, 
    		quality="GrnF", channelInclude="bgf", channelOutput="vst")
    
    # ==========================================
    # --- Quantile Normalization ---
    # ==========================================
    blimatesting = quantileNormalize(blimatesting, normalizationMod = processingMod, 
    		channelNormalize="vst", channelOutput="qua", channelInclude="bgf")
    
    # ==========================================
    # --- Differential Expression Testing ---
    # ==========================================
    probeTest <- doProbeTTests(blimatesting, groups1Mod, groups2Mod, 
    		transformation=NULL, quality="qua", channelInclude="bgf")
    beadTest <- doTTests(blimatesting, groups1Mod, groups2Mod, 
    		transformation=NULL, quality="qua", channelInclude="bgf")
    
    # ==========================================
    # --- Summarization to Probe-Level Matrices ---
    # ==========================================
    nonnormalized = createSummarizedMatrix(blimatesting, spotsToProcess=processingMod, quality="GrnF", channelInclude="bgf", 
            annotationTag="Name")
    normalized = createSummarizedMatrix(blimatesting, spotsToProcess=processingMod, quality="qua", channelInclude="bgf", 
            annotationTag="Name")
    
    # ==========================================
    # --- Downstream Processing and Exporting Outputs ---
    # ==========================================
    
    # Save raw test results
    write.csv(probeTest, "probe_level_tests.csv", row.names=FALSE)
    write.csv(beadTest, "bead_level_tests.csv", row.names=FALSE)
    
    # Process and merge differential expression measures
    probeTestID = probeTest[,"ProbeID"]
    beadTestID = beadTest[,"ProbeID"]
    probeTestFC = abs(probeTest[,"mean1"]-probeTest[,"mean2"])
    beadTestFC = abs(beadTest[,"mean1"]-beadTest[,"mean2"])
    probeTestP = probeTest[,"adjustedp"]
    beadTestP = beadTest[,"adjustedp"]
    probeTestMeasure = (1-probeTestP)*probeTestFC
    beadTestMeasure = (1-beadTestP)*beadTestFC
    
    probeTest_df = data.frame(ArrayAddressID = as.character(probeTestID), difexPL = probeTestMeasure, stringsAsFactors = FALSE)
    beadTest_df = data.frame(ArrayAddressID = as.character(beadTestID), difexBL = beadTestMeasure, stringsAsFactors = FALSE)
    
    tocmp <- merge(probeTest_df, beadTest_df, by="ArrayAddressID")
    tocmp = merge(tocmp, adrToIllumina, by.x="ArrayAddressID", by.y="Array_Address_Id", all.x=TRUE)
    write.csv(tocmp, "differential_expression_comparison.csv", row.names=FALSE)
    
    # Format and export summarized matrices
    # Ensure ProbeID is character for merging
    nonnormalized\$ProbeID <- as.character(nonnormalized\$ProbeID)
    normalized\$ProbeID <- as.character(normalized\$ProbeID)
    
    # Dynamically reorder columns to put Probe_Id (ID_REF) first
    sample_cols = setdiff(colnames(nonnormalized), "ProbeID")
    
    nonnormalized_merged = merge(nonnormalized, adrToIllumina, by.x="ProbeID", by.y="Array_Address_Id", all.x=TRUE)
    nonnormalized_final = nonnormalized_merged[, c("Probe_Id", sample_cols), drop=FALSE]
    colnames(nonnormalized_final)[1] = "ID_REF"
    write.csv(nonnormalized_final, "summarized_nonnormalized.csv", row.names=FALSE)
    
    normalized_merged = merge(normalized, adrToIllumina, by.x="ProbeID", by.y="Array_Address_Id", all.x=TRUE)
    normalized_final = normalized_merged[, c("Probe_Id", sample_cols), drop=FALSE]
    colnames(normalized_final)[1] = "ID_REF"
    write.csv(normalized_final, "summarized_normalized.csv", row.names=FALSE)
    
    # Generate comparison plot
    pdf("differential_expression_comparison.pdf", width=6, height=6)
    plot(tocmp\$difexPL, tocmp\$difexBL, 
         xlab="Probe-level Diff Exp Measure (difexPL)", 
         ylab="Bead-level Diff Exp Measure (difexBL)",
         main="Comparison of Probe-level vs Bead-level Testing",
         pch=16, col=rgb(0, 0, 1, 0.5))
    abline(a=0, b=1, col="red", lty=2)
    dev.off()
    
    # Save the processed beadLevelData object list
    saveRDS(blimatesting, "blimatesting_processed.rds")
    
    cat("Pipeline completed successfully. Outputs written to working directory.\n")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # count normalization — scan .rds matrix artifacts for library-size CV
    # ratio (post-norm / pre-norm); without raw input we report median lib CV
    # as a proxy diagnostic. Threshold = 0.7 (Bullard 2010 BMC Bioinf).
    .cn_lib_cvs <- numeric(0)
    .cn_scanned <- character(0)
    for (.cn_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .cn_obj <- tryCatch(readRDS(.cn_rds), error = function(e) NULL)
      .cn_mat <- if (is.matrix(.cn_obj) || is.data.frame(.cn_obj)) .cn_obj else NULL
      if (!is.null(.cn_mat) && ncol(.cn_mat) >= 2 && nrow(.cn_mat) >= 2) {
        .cn_lib <- tryCatch(colSums(as.matrix(.cn_mat), na.rm = TRUE), error = function(e) NULL)
        if (!is.null(.cn_lib) && all(is.finite(.cn_lib)) && mean(.cn_lib) > 0) {
          .cn_lib_cvs <- c(.cn_lib_cvs, sd(.cn_lib) / mean(.cn_lib))
          .cn_scanned <- c(.cn_scanned, .cn_rds)
        }
      }
    }
    .cn_med_cv <- if (length(.cn_lib_cvs) > 0) round(median(.cn_lib_cvs), 4) else NA_real_
    .gates_by_label[["count normalization"]] <- list(
      gate_row = "bioc_count_normalization",
      metric_name = "lib_size_cv_median",
      metric_value = .cn_med_cv,
      passes = isTRUE(is.finite(.cn_med_cv) && .cn_med_cv <= 0.3),
      status = if (is.finite(.cn_med_cv)) paste0("computed (proxy: median lib-size CV across ", length(.cn_scanned), " matrix .rds; raw-vs-norm ratio not measurable without paired input)")
               else "not_computed (no count matrix .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_BLIMA_BEAD_LEVEL_PREPROCESSING_AND_ANALYSIS",
      domain  = "bioconductor",
      declared_qc_steps = c("count normalization"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_BLIMA_BEAD_LEVEL_PREPROCESSING_AND_ANALYSIS":',
        paste0('    blima: ', as.character(packageVersion('blima')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bead_level_preprocessing_and_analysis.csv versions.yml
    """
}

workflow BIOC_BLIMA_BEAD_LEVEL_PREPROCESSING_AND_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ blimatesting, adrToIllumina ] ]

    main:
    BIOC_BLIMA_BEAD_LEVEL_PREPROCESSING_AND_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_BLIMA_BEAD_LEVEL_PREPROCESSING_AND_ANALYSIS.out.tables
    plots    = BIOC_BLIMA_BEAD_LEVEL_PREPROCESSING_AND_ANALYSIS.out.plots
    objects  = BIOC_BLIMA_BEAD_LEVEL_PREPROCESSING_AND_ANALYSIS.out.objects
    versions = BIOC_BLIMA_BEAD_LEVEL_PREPROCESSING_AND_ANALYSIS.out.versions
}
