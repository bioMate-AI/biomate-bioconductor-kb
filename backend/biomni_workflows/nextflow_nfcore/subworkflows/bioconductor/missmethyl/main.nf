#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: missMethyl — standard_diff_meth_and_gsa
// Perform SWAN normalization, quality filtering, differential methylation analysis using limma, and bias-corrected gene set testing.
// Input: targets, idat files
// Container: quay.io/biocontainers/bioconductor-missmethyl:1.44.0--r45hdfd78af_0
// R packages: IlluminaHumanMethylation450kanno.ilmn12.hg19, DMRcate, edgeR, limma, minfi, minfidata, missMethyl
// Bioconductor: 3.20 | R: 4.4
// Requires: IlluminaHumanMethylation450kanno.ilmn12.hg19, limma, minfi, missMethyl
// Visualizations: plot (ggplot/base)
// QC: array detection QC
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read targets and IDAT files from the current working
//  * 2. [Input & Preparation] Preprocess raw data and apply SWAN normalization
//  * 3. [Input & Preparation] Filter out poor quality probes based on detection p-values
//  * 4. [Input & Preparation] Extract M-values and Beta values
//  * 5. [Input & Preparation] Set up design matrix and fit linear model using limma
//  * 6. [Input & Preparation] Perform gene set testing (GO/KEGG) using gometh and
//  * 7. [Input & Preparation] Write named output files for the meaningful results

nextflow.enable.dsl = 2

process BIOC_MISSMETHYL_STANDARD_DIFF_METH_AND_GSA {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

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
    .bm_deps <- c("IlluminaHumanMethylation450kanno.ilmn12.hg19", "DMRcate", "edgeR", "limma", "minfi", "minfidata", "missMethyl")
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
        library(missMethyl)
        library(limma)
        library(minfi)
        library(IlluminaHumanMethylation450kanno.ilmn12.hg19)
        
        # --- Read targets and IDAT files from the current working ---
        targets <- read.metharray.sheet(".")
        rgSet <- read.metharray.exp(targets = targets)
        
        # Robustly handle targets column names for downstream analysis
        if (!"status" %in% colnames(targets)) {
          status_col <- grep("group|status|condition|dx|class", colnames(targets), ignore.case=TRUE)[1]
          if (!is.na(status_col)) {
            colnames(targets)[status_col] <- "status"
          } else {
            targets\$status <- "normal" # Fallback default
          }
        }
        
        if (!"person" %in% colnames(targets)) {
          person_col <- grep("person|individual|patient|subject|id", colnames(targets), ignore.case=TRUE)[1]
          if (!is.na(person_col)) {
            colnames(targets)[person_col] <- "person"
          } else {
            targets\$person <- paste0("id", seq_len(nrow(targets))) # Fallback default
          }
        }
        
        # --- Preprocess raw data and apply SWAN normalization ---
        mSet <- preprocessRaw(rgSet)
        mSetSw <- SWAN(mSet, verbose=TRUE)
        
        # --- Filter out poor quality probes based on detection p-values ---
        detP <- detectionP(rgSet)
        keep <- rowSums(detP < 0.01) == ncol(rgSet)
        mSetSw <- mSetSw[keep,]
        
        # --- Extract M-values and Beta values ---
        meth <- getMeth(mSetSw)
        unmeth <- getUnmeth(mSetSw)
        Mval <- log2((meth + 100)/(unmeth + 100))
        beta <- getBeta(mSetSw)
        
        # --- Set up design matrix and fit linear model using limma ---
        # Ensure levels match the expected "normal" and "cancer" if present, otherwise use unique values
        if (all(c("normal", "cancer") %in% targets\$status)) {
          group <- factor(targets\$status, levels=c("normal","cancer"))
        } else {
          group <- factor(targets\$status)
        }
        id <- factor(targets\$person)
        
        # Fix: Prevent overparameterization if 'id' is unique for every sample (unpaired) or has only 1 level
        if (length(unique(id)) == length(id) || length(unique(id)) == 1) {
          design <- model.matrix(~group)
        } else {
          design <- model.matrix(~id + group)
        }
        
        fit.reduced <- lmFit(Mval, design)
        fit.reduced <- eBayes(fit.reduced, robust=TRUE)
        
        # Determine the correct coefficient for the group comparison (usually the last column)
        group_coef <- ncol(design)
        
        # Fix: Set number=Inf to return all CpGs so the background universe for GSA is correct
        top <- topTable(fit.reduced, coef=group_coef, number=Inf)
        
        # Reconstruct rfit4 using the RUVm 2-stage approach to make topRUV runnable
        rfit4 <- NULL
        tryCatch({
          meth_all <- getMeth(mSetSw)
          unmeth_all <- getUnmeth(mSetSw)
          M <- log2((meth_all + 100)/(unmeth_all + 100))
          grp <- factor(targets\$status)
          INCs <- getINCs(rgSet)
          Mc <- rbind(M, INCs)
          ctl1 <- rownames(Mc) %in% rownames(INCs)
          rfit1 <- RUVfit(Y = Mc, X = grp, ctl = ctl1)
          rfit2 <- RUVadj(Y = Mc, fit = rfit1)
          top1 <- topRUV(rfit2, num=Inf, p.BH = 1)
          ctl2 <- rownames(M) %in% rownames(top1[top1\$p.BH_X1.1 > 0.5,])
          rfit3 <- RUVfit(Y = M, X = grp, ctl = ctl2)
          rfit4 <- RUVadj(Y = M, fit = rfit3)
        }, error = function(e) {
          warning("RUVm alignment failed: ", e\$message)
        })
        
        # Retrieve top CpGs using topRUV if available, otherwise fallback to standard topTable
        if (!is.null(rfit4)) {
          topCpGs <- topRUV(rfit4, number=10000)
        } else {
          topCpGs <- topTable(fit.reduced, coef=group_coef, number=10000)
        }
        
        sigCpGs <- rownames(topCpGs)
        check <- getMappedEntrezIDs(sig.cpg = sigCpGs)
        
        # --- Perform gene set testing (GO/KEGG) using gometh and ---
        # Save the bias plot to a PDF file
        pdf("probe_bias_plot.pdf")
        gst <- gometh(sig.cpg=sigCpGs, all.cpg=rownames(top), collection="GO", plot.bias=TRUE)
        dev.off()
        
        gst.kegg <- gometh(sig.cpg=sigCpGs, all.cpg=rownames(top), collection="KEGG")
        gst.kegg.prom <- gometh(sig.cpg=sigCpGs, all.cpg=rownames(top), collection="KEGG", genomic.features = c("TSS200", "TSS1500", "1stExon"))
        gst.kegg.body <- gometh(sig.cpg=sigCpGs, all.cpg=rownames(top), collection="KEGG", genomic.features = c("Body"), sig.genes = TRUE)
        
        # Download and run Hallmark gene set testing
        hallmark <- NULL
        tryCatch({
          hallmark <- readRDS(url("http://bioinf.wehi.edu.au/MSigDB/v7.1/Hs.h.all.v7.1.entrez.rds"))
        }, error = function(e) {
          warning("Could not download Hallmark gene sets: ", e\$message)
        })
        
        if (!is.null(hallmark)) {
          gsa <- gsameth(sig.cpg=sigCpGs, all.cpg=rownames(top), collection=hallmark)
        } else {
          gsa <- NULL
        }
        
        # --- Write named output files for the meaningful results ---
        write.csv(top, "limma_differential_methylation_results.csv", row.names=TRUE)
        write.csv(topCpGs, "top_significant_cpgs.csv", row.names=TRUE)
        saveRDS(check, "mapped_entrez_ids.rds")
        
        write.csv(topGSA(gst, n=nrow(gst)), "go_enrichment_results.csv", row.names=TRUE)
        write.csv(topGSA(gst.kegg, n=nrow(gst.kegg)), "kegg_enrichment_results.csv", row.names=TRUE)
        write.csv(topGSA(gst.kegg.prom, n=nrow(gst.kegg.prom)), "kegg_promoter_enrichment_results.csv", row.names=TRUE)
        write.csv(topGSA(gst.kegg.body, n=nrow(gst.kegg.body)), "kegg_body_enrichment_results.csv", row.names=TRUE)
        
        if (!is.null(gsa)) {
          write.csv(topGSA(gsa, n=nrow(gsa)), "hallmark_enrichment_results.csv", row.names=TRUE)
        }
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # array detection QC — ExpressionSet detection p-values or detection-column data.frame.
    .adq_rate <- NA_real_
    for (.adq_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .adq_obj <- tryCatch(readRDS(.adq_rds), error = function(e) NULL)
      .adq_pv <- NULL
      if (!is.null(.adq_obj)) {
        if (inherits(.adq_obj, "ExpressionSet")) {
          .adq_pv <- tryCatch(Biobase::assayDataElement(.adq_obj, "Detection"), error = function(e) NULL)
        } else if (is.matrix(.adq_obj) || is.data.frame(.adq_obj)) {
          .adq_cols <- grep("(?i)(detection|pvalue|pval)", colnames(.adq_obj), value = TRUE)
          if (length(.adq_cols) > 0) .adq_pv <- as.matrix(.adq_obj[, .adq_cols, drop = FALSE])
        }
      }
      if (!is.null(.adq_pv) && length(.adq_pv) > 0) {
        .adq_rate <- round(mean(as.numeric(.adq_pv) < 0.05, na.rm = TRUE), 4); break
      }
    }
    .gates_by_label[["array detection QC"]] <- list(
      gate_row = "bioc_array_detection_qc",
      metric_name = "detection_rate",
      metric_value = .adq_rate,
      passes = isTRUE(is.finite(.adq_rate) && .adq_rate >= 0.75),
      status = if (is.finite(.adq_rate)) "computed (probe-detection p<0.05 fraction)"
               else "not_computed (no ExpressionSet/detection-p .rds present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_MISSMETHYL_STANDARD_DIFF_METH_AND_GSA",
      domain  = "bioconductor",
      declared_qc_steps = c("array detection QC"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_MISSMETHYL_STANDARD_DIFF_METH_AND_GSA":',
        paste0('    missMethyl: ', as.character(packageVersion('missMethyl')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_diff_meth_and_gsa.csv versions.yml
    """
}

workflow BIOC_MISSMETHYL_STANDARD_DIFF_METH_AND_GSA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ targets, idat files ] ]

    main:
    BIOC_MISSMETHYL_STANDARD_DIFF_METH_AND_GSA(ch_input)

    emit:
    tables   = BIOC_MISSMETHYL_STANDARD_DIFF_METH_AND_GSA.out.tables
    plots    = BIOC_MISSMETHYL_STANDARD_DIFF_METH_AND_GSA.out.plots
    objects  = BIOC_MISSMETHYL_STANDARD_DIFF_METH_AND_GSA.out.objects
    versions = BIOC_MISSMETHYL_STANDARD_DIFF_METH_AND_GSA.out.versions
}
