#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DEqMS — maxquant_lfq
// Perform differential protein expression analysis using MaxQuant label-free quantification (LFQ) output.
// Input: proteinGroups.txt
// Container: quay.io/biocontainers/bioconductor-deqms:1.28.0--r45hdfd78af_0
// R packages: DEqMS, limma, matrixStats
// Bioconductor: 3.20 | R: 4.4
// Requires: DEqMS, limma, matrixStats
// Visualizations: box plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read and filter out decoy/contaminant matches
//  * 2. [Core Analysis] Extract LFQ intensity columns and filter for missing values
//  * 3. [Core Analysis] Extract unique/razor peptide counts and add a pseudocount of 1
//  * 4. [Core Analysis] Log2 transform intensities
//  * 5. [Input & Preparation] Define design matrix and contrasts
//  * 6. [Core Analysis] Fit linear model using Limma (lmFit, contrasts.fit, eBayes)
//  * 7. [Core Analysis] Assign peptide count to the fit object
//  * 8. [Core Analysis] Run DEqMS variance estimation (spectraCounteBayes)
//  * 9. [Visualization & Output] Extract results (outputResult)

nextflow.enable.dsl = 2

process BIOC_DEQMS_MAXQUANT_LFQ {
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
    .bm_deps <- c("DEqMS", "limma", "matrixStats")
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
    library(DEqMS)
    library(matrixStats)
    library(limma)
    
    # 1. Read and filter out decoy/contaminant matches
    df.prot = read.table("proteinGroups.txt",header=T,sep="\t",stringsAsFactors = F,
                            comment.char = "",quote ="")
    df.prot = df.prot[!df.prot\$Reverse=="+",]
    df.prot = df.prot[!df.prot\$Contaminant=="+",]
    
    # 2. Extract LFQ intensity columns and filter for missing values
    lfq_cols <- grep("^LFQ\\\\.intensity\\\\.", colnames(df.prot))
    df.LFQ = df.prot[, lfq_cols, drop=FALSE]
    df.LFQ[df.LFQ==0] <- NA
    rownames(df.LFQ) = df.prot\$Majority.protein.IDs
    
    # Dynamically infer experimental design from sample names
    sample_names <- sub("^LFQ\\\\.intensity\\\\.", "", colnames(df.prot)[lfq_cols])
    class <- as.factor(gsub("[_\\\\.]?[0-9]+\$", "", sample_names))
    
    # Filter protein table. DEqMS requires a minimum of two values for each group.
    valid_per_group <- sapply(levels(class), function(g) {
      rowSums(!is.na(df.LFQ[, class == g, drop=FALSE]))
    })
    keep_idx <- rowSums(valid_per_group >= 2) == length(levels(class))
    df.LFQ.filter = df.LFQ[keep_idx, , drop=FALSE]
    
    # 3. Extract unique/razor peptide counts and add a pseudocount of 1
    pep_col_names <- paste0("Razor.and.unique.peptides.", sample_names)
    if (!all(pep_col_names %in% colnames(df.prot))) {
      pep_col_names <- paste0("Peptides.", sample_names)
    }
    pep.count.table = data.frame(count = rowMins(as.matrix(df.prot[, pep_col_names, drop=FALSE])),
                                 row.names = df.prot\$Majority.protein.IDs)
    pep.count.table\$count = pep.count.table\$count+1
    
    # 4. Log2 transform intensities
    protein.matrix = log2(as.matrix(df.LFQ.filter))
    
    # 5. Define design matrix and contrasts
    design = model.matrix(~0+class)
    colnames(design) = gsub("class","",colnames(design))
    
    # 6. Fit linear model using Limma
    fit1 = lmFit(protein.matrix,design = design)
    contrast_str <- paste(levels(class)[1], levels(class)[2], sep="-")
    cont <- makeContrasts(contrasts=contrast_str, levels = design)
    fit2 = contrasts.fit(fit1,contrasts = cont)
    fit3 <- eBayes(fit2)
    
    # 7. Assign peptide count to the fit object
    fit3\$count = pep.count.table[rownames(fit3\$coefficients),"count"]
    min(fit3\$count)
    
    # 8. Run DEqMS variance estimation
    fit4 = spectraCounteBayes(fit3)
    
    # Save Variance Boxplot to PDF
    pdf("VarianceBoxplot.pdf", width=8, height=6)
    VarianceBoxplot(fit4, n=20, main = "Label-free dataset PXD000279",
                    xlab="peptide count + 1")
    dev.off()
    
    # 9. Extract results
    DEqMS.results = outputResult(fit4,coef_col = 1)
    
    # Add Gene names to the data frame if Gene.names column exists in the input
    rownames(df.prot) = df.prot\$Majority.protein.IDs
    if ("Gene.names" %in% colnames(df.prot)) {
      DEqMS.results\$Gene.name = df.prot[DEqMS.results\$gene,]\$Gene.names
    }
    
    # Write outputs to files
    out_filename <- paste0(contrast_str, ".DEqMS.results.txt")
    write.table(DEqMS.results, out_filename, sep = "\t",
                row.names = F,quote=F)
    saveRDS(DEqMS.results, "DEqMS_results.rds")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # missing-value handling — scan .rds matrix/data.frame artifacts for max NA fraction
    .mv_na_fracs <- numeric(0)
    .mv_scanned <- character(0)
    for (.mv_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .mv_obj <- tryCatch(readRDS(.mv_rds), error = function(e) NULL)
      .mv_mat <- if (is.matrix(.mv_obj) || is.data.frame(.mv_obj)) .mv_obj else NULL
      if (!is.null(.mv_mat)) {
        .mv_vals <- suppressWarnings(as.numeric(as.matrix(.mv_mat)))
        if (length(.mv_vals) > 0) {
          .mv_na_fracs <- c(.mv_na_fracs, mean(is.na(.mv_vals)))
          .mv_scanned <- c(.mv_scanned, .mv_rds)
        }
      }
    }
    .mv_max <- if (length(.mv_na_fracs) > 0) round(max(.mv_na_fracs), 4) else NA_real_
    .gates_by_label[["missing-value handling"]] <- list(
      gate_row = "bioc_missing_value_handling",
      metric_name = "na_fraction_remaining",
      metric_value = .mv_max,
      passes = isTRUE(is.finite(.mv_max) && .mv_max < 0.05),
      status = if (is.finite(.mv_max)) paste0("computed (scanned ", length(.mv_scanned), " rds files)")
               else "not_computed (no matrix/data.frame .rds artifact present)"
    )

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

    # low-count filtering — fraction of genes retained (heuristic on matrix artifacts).
    # Pass band 30-60% per Chen 2016 F1000 (edgeR filterByExpr convention).
    .lcf_kept_fractions <- numeric(0)
    .lcf_scanned <- character(0)
    for (.lcf_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .lcf_obj <- tryCatch(readRDS(.lcf_rds), error = function(e) NULL)
      .lcf_mat <- if (is.matrix(.lcf_obj) || is.data.frame(.lcf_obj)) .lcf_obj else NULL
      if (!is.null(.lcf_mat) && nrow(.lcf_mat) > 100) {
        .lcf_m <- tryCatch(as.matrix(.lcf_mat), error = function(e) NULL)
        if (!is.null(.lcf_m)) {
          .lcf_row_med <- suppressWarnings(apply(.lcf_m, 1, function(r) median(as.numeric(r), na.rm = TRUE)))
          .lcf_kept <- sum(is.finite(.lcf_row_med) & .lcf_row_med >= 1) / nrow(.lcf_m)
          .lcf_kept_fractions <- c(.lcf_kept_fractions, .lcf_kept)
          .lcf_scanned <- c(.lcf_scanned, .lcf_rds)
        }
      }
    }
    .lcf_kept <- if (length(.lcf_kept_fractions) > 0) round(median(.lcf_kept_fractions), 4) else NA_real_
    .gates_by_label[["low-count filtering"]] <- list(
      gate_row = "bioc_low_count_filtering",
      metric_name = "genes_kept_fraction",
      metric_value = .lcf_kept,
      passes = isTRUE(is.finite(.lcf_kept) && .lcf_kept >= 0.3 && .lcf_kept <= 0.6),
      status = if (is.finite(.lcf_kept)) paste0("computed (proxy: rows w/ median count >=1 across ", length(.lcf_scanned), " matrix .rds)")
               else "not_computed (no count matrix .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_DEQMS_MAXQUANT_LFQ",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling", "count normalization", "low-count filtering"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_DEQMS_MAXQUANT_LFQ":',
        paste0('    DEqMS: ', as.character(packageVersion('DEqMS')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_maxquant_lfq.csv versions.yml
    """
}

workflow BIOC_DEQMS_MAXQUANT_LFQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ proteinGroups.txt ] ]

    main:
    BIOC_DEQMS_MAXQUANT_LFQ(ch_input)

    emit:
    tables   = BIOC_DEQMS_MAXQUANT_LFQ.out.tables
    plots    = BIOC_DEQMS_MAXQUANT_LFQ.out.plots
    objects  = BIOC_DEQMS_MAXQUANT_LFQ.out.objects
    versions = BIOC_DEQMS_MAXQUANT_LFQ.out.versions
}
