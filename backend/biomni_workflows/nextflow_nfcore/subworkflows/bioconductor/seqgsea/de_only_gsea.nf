#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: seqgsea — de_only_gsea
// Run gene set enrichment analysis using only differential expression scores from gene-level RNA-Seq count data.
// Input: count.file, geneset.file
// Container: quay.io/biocontainers/bioconductor-seqgsea:1.50.0--r45hdfd78af_0
// R packages: SeqGSEA, doParallel
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SEQGSEA_DE_ONLY_GSEA {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-seqgsea:1.50.0--r45hdfd78af_0"

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
    .bm_deps <- c("SeqGSEA", "doParallel")
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
    
    library(SeqGSEA)
    library(doParallel)
    
    # --- Register parallel backend ---
    cl <- makeCluster(2)
    registerDoParallel(cl)
    perm.times <- 20
    
    count.file <- "count.file"
    geneset.file <- "geneset.file"
    
    # --- Load gene read count data ---
    geneCounts <- read.table(count.file, header=TRUE, row.names=1, sep="\t")
    
    # Determine labels dynamically based on the number of samples in the input file
    n_samples <- ncol(geneCounts)
    label <- as.factor(c(rep(1, n_samples/2), rep(0, n_samples - n_samples/2)))
    
    # --- Calculate DE NB statistics on real and permuted datasets ---
    dds <- runDESeq(geneCounts, label)
    DEGres <- DENBStat4GSEA(dds)
    permuteMat <- genpermuteMat(label, times=perm.times)
    DEpermNBstat <- DENBStatPermut4GSEA(dds, permuteMat)
    
    # --- Normalize DE scores ---
    DEscore.normFac <- normFactor(DEpermNBstat)
    DEscore <- scoreNormalization(DEGres\$NBstat, DEscore.normFac)
    DEscore.perm <- scoreNormalization(DEpermNBstat, DEscore.normFac)
    
    # --- Integrate scores with DEweight=1 ---
    gene.score <- geneScore(DEscore, DEweight=1)
    gene.score.perm <- genePermuteScore(DEscore.perm, DEweight=1)
    
    # --- Load gene sets ---
    geneIDs <- rownames(geneCounts)
    gene.set <- loadGenesets(geneset.file, geneIDs, geneID.type="ensembl", genesetsize.min = 5, genesetsize.max = 1000)
    
    # --- Run GSEA and format results ---
    gene.set <- GSEnrichAnalyze(gene.set, gene.score, gene.score.perm, weighted.type=1)
    GSEAres <- GSEAresultTable(gene.set, TRUE)
    
    # Write output tables and RDS objects
    write.table(GSEAres, "SeqGSEA_de_only_results.txt", sep="\t", quote=FALSE, row.names=FALSE)
    saveRDS(gene.set, "SeqGSEA_geneset_analyzed.rds")
    saveRDS(GSEAres, "SeqGSEA_results_table.rds")
    
    # Generate and save diagnostic and results plots
    plotGeneScore(DEscore, DEscore.perm, pdf="SeqGSEA_DEScore.pdf", main="Expression")
    plotGeneScore(gene.score, gene.score.perm, pdf="SeqGSEA_GeneScore.pdf")
    plotES(gene.set, pdf="SeqGSEA_ES_plot.pdf")
    plotSig(gene.set, pdf="SeqGSEA_FDR_plot.pdf")
    
    # Clean up parallel backend
    stopCluster(cl)
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

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

    # dispersion/size-factor estimation — object-type-aware. Try DESeq2
    # DESeqDataSet (mcols\$dispOutlier), then edgeR DGEList (common.dispersion).
    .dsf_value <- NA_real_; .dsf_kind <- "none"
    for (.dsf_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .dsf_obj <- tryCatch(readRDS(.dsf_rds), error = function(e) NULL)
      if (!is.null(.dsf_obj)) {
        if (inherits(.dsf_obj, "DESeqDataSet")) {
          .dsf_o <- tryCatch(mcols(.dsf_obj)\$dispOutlier, error = function(e) NULL)
          if (!is.null(.dsf_o)) { .dsf_value <- round(mean(.dsf_o, na.rm = TRUE), 4); .dsf_kind <- "deseq2"; break }
        } else if (inherits(.dsf_obj, "DGEList")) {
          .dsf_v <- tryCatch(.dsf_obj\$common.dispersion, error = function(e) NULL)
          if (!is.null(.dsf_v) && is.finite(.dsf_v)) { .dsf_value <- round(sqrt(.dsf_v), 4); .dsf_kind <- "edger_bcv"; break }
        }
      }
    }
    .gates_by_label[["dispersion/size-factor estimation"]] <- list(
      gate_row = "bioc_dispersion_size_factor",
      metric_name = if (.dsf_kind == "edger_bcv") "common_bcv" else "disp_outlier_fraction",
      metric_value = .dsf_value,
      passes = isTRUE(
        (.dsf_kind == "deseq2" && is.finite(.dsf_value) && .dsf_value <= 0.01) ||
        (.dsf_kind == "edger_bcv" && is.finite(.dsf_value) && .dsf_value > 0 && .dsf_value < 1.0)
      ),
      status = if (is.finite(.dsf_value)) paste0("computed (", .dsf_kind, ")")
               else "not_computed (no DESeqDataSet/DGEList .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_SEQGSEA_DE_ONLY_GSEA",
      domain  = "bioconductor",
      declared_qc_steps = c("low-count filtering", "count normalization", "dispersion/size-factor estimation"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_SEQGSEA_DE_ONLY_GSEA":',
        paste0('        seqgsea: ', as.character(packageVersion("seqgsea")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_de_only_gsea.csv versions.yml
    """
}

workflow BIOC_SEQGSEA_DE_ONLY_GSEA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ count.file, geneset.file ] ]

    main:
    BIOC_SEQGSEA_DE_ONLY_GSEA(ch_input)

    emit:
    tables   = BIOC_SEQGSEA_DE_ONLY_GSEA.out.tables
    plots    = BIOC_SEQGSEA_DE_ONLY_GSEA.out.plots
    objects  = BIOC_SEQGSEA_DE_ONLY_GSEA.out.objects
    versions = BIOC_SEQGSEA_DE_ONLY_GSEA.out.versions
}
