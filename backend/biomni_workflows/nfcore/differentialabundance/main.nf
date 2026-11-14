// nf-core/differentialabundance — BioMate stub with embedded R (DESeq2 + limma)
// Inputs via Channel.fromPath (local demo under sample_data/mg_demo or staged paths).
// Pattern follows validation_deseq2_raw_counts/main.nf.
//
// Method is chosen from params.normalisation_method / params.study_type:
//   - normalisation_method='limma' OR study_type='affy'  → limma (microarray log-intensities;
//     NO integer coercion — the DESeq2 path's round() zeroes out array data)
//   - otherwise                                          → DESeq2 (integer counts, bulk RNA-seq)
// The execute-gate routes GEO microarray accessions here with limma/affy
// (docs/20261102_UNIFIED_PUBLIC_ID_ROUTING_DESIGN.md). Before this, the stub ran DESeq2
// regardless of the declared params → microarray failed with "all samples have 0 counts".

nextflow.enable.dsl = 2

params.samplesheet      = null          // Sample metadata / samplesheet CSV (S3 URI or local path)
params.input            = null          // Alias for samplesheet (nf-core convention)
params.matrix           = null          // Count matrix CSV (genes × samples)
params.contrasts        = null          // Contrasts CSV (id, variable, reference, target)
// User-specified contrast (overrides auto-inference). Either name the metadata column
// (contrast_variable) or just give the two group VALUES (contrast_target vs contrast_reference)
// and the column containing them is found automatically — so a user can say "tumor vs normal"
// without knowing the exact GEO pData column name.
params.contrast_variable  = null         // metadata column to contrast on (optional)
params.contrast_target    = null         // the "treatment"/numerator group value (optional)
params.contrast_reference = null         // the "control"/denominator group value (optional)
params.genome           = null          // Reference genome (for annotation, optional)
params.gtf              = null          // GTF annotation file (optional)
params.study_type       = 'rnaseq'      // Assay type: rnaseq | maxquant | affy | metab
params.differential_min_fold_change = 2.0
params.differential_max_qval        = 0.05
params.normalisation_method         = 'deseq2'
params.save_intermediates           = false
params.outdir           = './results'
params.email            = null
params.max_memory       = '64.GB'
params.max_cpus         = 8
params.max_time         = '72.h'

// Steps:
//  * 1. [Input Download] Download samplesheet and count matrix from S3
//  * 2. [Normalisation] Normalise counts with DESeq2 VST/rlog
//  * 3. [Differential Abundance] Run DESeq2 per contrast
//  * 4. [Visualisation & Report] PCA, volcano, MA plots + HTML report

process DESEQ2_DIFFERENTIAL_ANALYSIS {
    tag "DESeq2"
    label 'process_medium'

    publishDir "${params.outdir}", mode: 'copy'

    // Slim container — full :3.20 includes reactome.db which exhausts Batch EBS disk space.
    // Channel.fromPath handles S3 staging; aws cli is no longer needed in R.
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

    // Input files staged by Nextflow Channel.fromPath (not aws s3 cp in R script).
    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"),           emit: tables,    optional: true
    tuple val(meta), path("*.pdf"),           emit: plots,     optional: true
    tuple val(meta), path("*.rds"),           emit: objects,   optional: true
    tuple val(meta), path("*.html"),          emit: report,    optional: true
    tuple val(meta), path("qc_metrics.json"), emit: qc_metrics, optional: true
    path "versions.yml",                      emit: versions,  optional: true

    when:
    task.ext.when == null || task.ext.when

    script:
    def min_fc   = params.differential_min_fold_change ?: 2.0
    def max_qval = params.differential_max_qval ?: 0.05
    // Choose DE engine: limma for microarray/affy log-intensities, DESeq2 for integer counts.
    def de_method = ((params.normalisation_method ?: 'deseq2').toLowerCase() == 'limma' ||
                     (params.study_type ?: 'rnaseq').toLowerCase() == 'affy') ? 'limma' : 'deseq2'
    """
    #!/usr/bin/env Rscript
    de_method <- "${de_method}"

    # [biomate-deps] install only what is missing (container has DESeq2/limma/ggplot2 pre-installed)
    # ggrepel is optional — only needed for label repelling on volcano/PCA plots
    .bm_deps <- if (de_method == "limma") c("limma", "ggplot2") else c("DESeq2", "ggplot2")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      message("[biomate-deps] installing: ", paste(.bm_miss, collapse=", "))
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }
    # ggrepel optional — try to load, silence if absent
    suppressWarnings(try(library(ggrepel, warn.conflicts=FALSE), silent=TRUE))

    # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
    for (.bm_d in list.files(".", full.names = TRUE)) {
      if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
        for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
          if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
        }
      }
    }

    library(ggplot2)
    if (de_method == "limma") library(limma) else library(DESeq2)
    message("[differentialabundance] DE engine: ", de_method)

    # ── 1. Load inputs by name (files staged by Nextflow from S3) ─────────────
    all_files <- list.files(".", pattern = "\\\\.csv\$", recursive = FALSE)
    meta_file <- all_files[grepl("sample|metadata|samplesheet", tolower(all_files))][1]
    mat_file  <- all_files[grepl("matrix|count|expression", tolower(all_files))][1]
    con_file  <- all_files[grepl("contrast", tolower(all_files))][1]

    if (is.na(meta_file)) stop("No samplesheet/metadata CSV found. Provide a file with 'sample' in the name.")
    if (is.na(mat_file))  stop("No count matrix CSV found. Provide a file with 'matrix' or 'count' in the name.")

    metadata <- read.csv(meta_file, stringsAsFactors=FALSE, check.names=FALSE)
    # Read the matrix as NUMERIC (no rounding here — the DESeq2 branch rounds; limma must not).
    data_mat <- as.matrix(read.csv(mat_file, row.names=1, check.names=FALSE))

    # ── 2. Robust sample-ID column: the metadata column whose values match the
    #       matrix columns (GEO pData's rownames/geo_accession = GSM ids). Falls
    #       back to the first column. Replaces the fragile "sample"/first-col guess.
    mat_cols <- colnames(data_mat)
    sample_col <- NULL
    for (cc in names(metadata)) {
      if (length(intersect(as.character(metadata[[cc]]), mat_cols)) >= 2) { sample_col <- cc; break }
    }
    if (is.null(sample_col)) sample_col <- if ("sample" %in% names(metadata)) "sample" else names(metadata)[1]

    # ── 3. Build contrasts ─────────────────────────────────────────────────────
    # Robust grouping-variable inference: skip the sample-id column, constant columns,
    # and all-unique "ID-like" columns (title, geo_accession, GSM...) that the old
    # first-column heuristic wrongly picked (→ GSM_vs_GSM single-sample contrasts).
    # Prefer a column with exactly 2 groups, each with >=2 members, and a condition-like name.
    pick_condition_column <- function(md, scol) {
      cand <- setdiff(names(md), scol)
      best <- NA_character_; best_s <- -Inf
      # Skip GEO boilerplate / ID columns. NB: 'status'/'type' are intentionally NOT here —
      # they overlap biological conditions ("disease status:ch1", "sample type:ch1"); constant
      # GEO 'status'/'type' columns are dropped by the structural filters below instead.
      id_like <- "geo_accession|supplementary|_file|^url\$|^id\$|title|description|relation|contact|submission|last_update|date|molecule_ch|^label_ch|^platform|channel_count|taxid|^organism|data_row_count"
      for (cc in cand) {
        if (grepl(id_like, tolower(cc))) next
        v <- as.character(md[[cc]]); v[v == ""] <- NA
        vv <- v[!is.na(v)]
        if (length(vv) < 4) next                   # too few labelled samples to compare
        k <- length(unique(vv))
        if (k < 2 || k >= length(vv)) next          # constant, or all-unique (ID-like)
        minmemb <- min(table(vv))
        if (minmemb < 2) next                       # every group needs >=2 members
        kw <- grepl("group|condition|treat|genotype|disease|status|type|tissue|phenotyp|agent|character|class|cohort|sex|gender|stage|subtype|response|ch1", tolower(cc))
        s <- (if (k == 2) 100 else 50 - k) + (if (kw) 40 else 0) + minmemb
        if (s > best_s) { best_s <- s; best <- cc }
      }
      best
    }
    # User-specified contrast overrides (params). Match a value to the column that contains it
    # (case-insensitive substring) so the caller can say "tumor" vs "normal" without the exact
    # GEO column name. Returns c(column, matched_target_value, matched_reference_value) or NULL.
    .uvar <- "${params.contrast_variable ?: ''}"; .utgt <- "${params.contrast_target ?: ''}"; .uref <- "${params.contrast_reference ?: ''}"
    resolve_user_contrast <- function(md, scol) {
      if (.uvar == "" && .utgt == "" && .uref == "") return(NULL)
      find_val <- function(col, val) { # exact first, then case-insensitive substring
        u <- unique(as.character(md[[col]]))
        hit <- u[u == val]; if (length(hit)) return(hit[1])
        hit <- u[grepl(val, u, ignore.case=TRUE, fixed=FALSE)]; if (length(hit)) return(hit[1])
        NA_character_
      }
      cols <- if (.uvar != "" && .uvar %in% names(md)) .uvar else setdiff(names(md), scol)
      for (cc in cols) {
        tg <- if (.utgt != "") find_val(cc, .utgt) else NA_character_
        rf <- if (.uref != "") find_val(cc, .uref) else NA_character_
        # need at least the target resolved; reference defaults to the other largest group
        if (.utgt != "" && is.na(tg)) next
        if (.uref != "" && is.na(rf)) next
        if (is.na(tg) && .uvar == "") next
        lv <- names(sort(table(md[[cc]]), decreasing=TRUE))
        if (.uvar != "" && .utgt == "") { tg <- lv[1]; rf <- lv[2] }
        if (is.na(rf)) rf <- setdiff(lv, tg)[1]
        if (is.na(tg) || is.na(rf) || tg == rf) next
        return(c(cc, tg, rf))
      }
      NULL
    }
    user_ct <- resolve_user_contrast(metadata, sample_col)
    cond_col <- pick_condition_column(metadata, sample_col)
    if (!is.na(con_file)) {
      contrasts_df <- read.csv(con_file, stringsAsFactors=FALSE)
    } else if (!is.null(user_ct)) {
      message("[differentialabundance] user contrast on '", user_ct[1], "': ", user_ct[2], " vs ", user_ct[3])
      contrasts_df <- data.frame(id=paste0(make.names(user_ct[2]),"_vs_",make.names(user_ct[3])),
                                 variable=user_ct[1], reference=user_ct[3], target=user_ct[2],
                                 stringsAsFactors=FALSE)
    } else if (!is.na(cond_col)) {
      tb <- sort(table(metadata[[cond_col]]), decreasing=TRUE)
      lvls <- names(tb)[1:2]   # two largest groups
      message("[differentialabundance] inferred contrast on '", cond_col, "': ", lvls[1], " vs ", lvls[2])
      contrasts_df <- data.frame(id=paste0(make.names(lvls[1]),"_vs_",make.names(lvls[2])),
                                 variable=cond_col, reference=lvls[2], target=lvls[1],
                                 stringsAsFactors=FALSE)
    } else {
      stop(paste("Could not infer a grouping variable (>=2 groups, each >=2 samples) from the sample",
                 "metadata, and no contrasts CSV or contrast params were provided. Columns seen:",
                 paste(names(metadata), collapse=", ")))
    }

    # ── 4. Align samples (shared) ───────────────────────────────────────────────
    common <- intersect(as.character(metadata[[sample_col]]), colnames(data_mat))
    if (length(common) == 0) {
      stop(paste("No overlapping sample names between metadata and matrix.",
                 "Metadata samples:", paste(head(metadata[[sample_col]], 5), collapse=", "),
                 "| Matrix columns:", paste(head(colnames(data_mat), 5), collapse=", ")))
    }
    metadata <- metadata[as.character(metadata[[sample_col]]) %in% common, , drop=FALSE]
    data_mat <- data_mat[, as.character(metadata[[sample_col]]), drop=FALSE]

    all_results <- list()

    # ── shared volcano helper (res_df must have log2FoldChange, pvalue, padj) ─────
    volcano_plot <- function(res_df, cid) tryCatch({
      res_df\$significant <- !is.na(res_df\$padj) & res_df\$padj < ${max_qval} &
                              abs(res_df\$log2FoldChange) >= log2(${min_fc})
      res_df\$neglog10p <- -log10(pmax(res_df\$pvalue, 1e-300))
      if (requireNamespace("ggrepel", quietly=TRUE)) library(ggrepel)
      p <- ggplot(res_df[!is.na(res_df\$padj),], aes(x=log2FoldChange, y=neglog10p, colour=significant)) +
        geom_point(alpha=0.4, size=1.2) +
        scale_colour_manual(values=c("grey60", "firebrick")) +
        geom_vline(xintercept=c(-log2(${min_fc}), log2(${min_fc})), linetype="dashed", colour="navy", alpha=0.5) +
        geom_hline(yintercept=-log10(${max_qval}), linetype="dashed", colour="navy", alpha=0.5) +
        labs(title=paste0("Volcano: ", cid), x="log2 Fold Change", y="-log10(p-value)",
             caption=paste0(sum(res_df\$significant, na.rm=TRUE), " features significant")) +
        theme_bw(base_size=11) + theme(legend.position="none")
      ggsave(paste0(cid, "_volcano.pdf"), p, width=7, height=6)
    }, error=function(e) warning("Volcano plot failed: ", e\$message))

    if (de_method == "limma") {
      # ── limma path (microarray / affy log-intensities) ───────────────────────
      expr <- data_mat
      mode(expr) <- "numeric"
      # GEO series matrices are usually already log2; if the data looks linear (large
      # dynamic range), log2-transform. Never round — that is what zeroed the DESeq2 run.
      if (max(expr, na.rm=TRUE) > 50) { expr <- log2(expr + 1); message("[limma] log2-transformed (data looked linear)") }
      # keep informative probes: finite + non-constant across samples
      keep <- apply(expr, 1, function(r) { r <- r[is.finite(r)]; length(r) >= 2 && stats::sd(r) > 0 })
      expr <- expr[keep, , drop=FALSE]

      for (i in seq_len(nrow(contrasts_df))) {
        ct <- contrasts_df[i, ]; cid <- ct[["id"]]; cvar <- ct[["variable"]]
        cref <- ct[["reference"]]; ctgt <- ct[["target"]]
        if (!cvar %in% names(metadata)) { warning("Variable '", cvar, "' not in metadata; skipping '", cid, "'"); next }
        sel <- as.character(metadata[[cvar]]) %in% c(cref, ctgt)
        if (sum(sel) < 3) { warning("Too few samples for contrast '", cid, "'; skipping"); next }
        expr_c <- expr[, sel, drop=FALSE]
        grp <- factor(make.names(as.character(metadata[[cvar]][sel])),
                      levels=make.names(c(cref, ctgt)))
        design <- stats::model.matrix(~0 + grp); colnames(design) <- levels(grp)
        fit <- lmFit(expr_c, design)
        cmtx <- makeContrasts(contrasts=paste0(make.names(ctgt), "-", make.names(cref)), levels=design)
        fit2 <- eBayes(contrasts.fit(fit, cmtx))
        tt <- topTable(fit2, number=Inf, sort.by="none")
        # DESeq2-compatible column names so downstream parsing/plotting is uniform.
        res_df <- data.frame(baseMean=tt\$AveExpr, log2FoldChange=tt\$logFC,
                             pvalue=tt\$P.Value, padj=tt\$adj.P.Val, row.names=rownames(tt))
        res_df <- res_df[order(res_df\$padj, na.last=TRUE), ]
        write.csv(res_df, paste0(cid, "_limma_results.csv"), row.names=TRUE)
        all_results[[cid]] <- res_df

        sig <- rownames(res_df)[!is.na(res_df\$padj) & res_df\$padj < ${max_qval} &
                                abs(res_df\$log2FoldChange) >= log2(${min_fc})]
        if (length(sig) > 0) writeLines(sig, paste0(cid, "_significant_genes.txt"))
        volcano_plot(res_df, cid)
        # PCA from the expression matrix (no DESeq2 object needed)
        tryCatch({
          vg <- head(order(apply(expr_c, 1, stats::var), decreasing=TRUE), 500)
          pc <- stats::prcomp(t(expr_c[vg, , drop=FALSE]), scale.=FALSE)
          pv <- round(100 * (pc\$sdev^2 / sum(pc\$sdev^2))[1:2])
          pcd <- data.frame(PC1=pc\$x[,1], PC2=pc\$x[,2], group=as.character(metadata[[cvar]][sel]), name=colnames(expr_c))
          p_pca <- ggplot(pcd, aes(PC1, PC2, colour=group, label=name)) + geom_point(size=3.5) + theme_bw() +
            labs(x=paste0("PC1: ", pv[1], "% variance"), y=paste0("PC2: ", pv[2], "% variance"), title=paste0("PCA — ", cid))
          if (requireNamespace("ggrepel", quietly=TRUE)) p_pca <- p_pca + ggrepel::geom_text_repel(size=3, max.overlaps=20)
          ggsave(paste0(cid, "_PCA.pdf"), p_pca, width=7, height=5)
        }, error=function(e) warning("PCA plot failed: ", e\$message))
      }
    } else {
      # ── DESeq2 path (integer counts / bulk RNA-seq) ──────────────────────────
      count_mat <- data_mat
      storage.mode(count_mat) <- "double"
      count_mat <- round(count_mat); count_mat[is.na(count_mat)] <- 0
      storage.mode(count_mat) <- "integer"
      # Remove low-count genes
      keep <- rowSums(count_mat >= 10) >= max(1, ceiling(0.25 * ncol(count_mat)))
      count_mat <- count_mat[keep, , drop=FALSE]

      for (i in seq_len(nrow(contrasts_df))) {
        ct <- contrasts_df[i, ]; cid <- ct[["id"]]; cvar <- ct[["variable"]]
        cref <- ct[["reference"]]; ctgt <- ct[["target"]]
        if (!cvar %in% names(metadata)) { warning("Variable '", cvar, "' not in metadata; skipping '", cid, "'"); next }

        # Subset to the two contrast groups (handles >2-group / NA-containing metadata columns).
        sel <- as.character(metadata[[cvar]]) %in% c(cref, ctgt)
        if (sum(sel) < 3) { warning("Too few samples for contrast '", cid, "'; skipping"); next }
        col_data <- metadata[sel, , drop=FALSE]
        cmat_c <- count_mat[, sel, drop=FALSE]
        # Use a SAFE design-variable name — GEO condition columns like "disease state:ch1"
        # (spaces/colons) are invalid in an R formula. Keep original cvar for labelling.
        col_data\$condition_grp <- relevel(factor(as.character(col_data[[cvar]])), ref=cref)
        dds <- tryCatch(
          DESeqDataSetFromMatrix(countData=cmat_c, colData=col_data, design=~condition_grp),
          error=function(e) stop("DESeq2 setup failed for contrast '", cid, "': ", e\$message)
        )
        dds <- estimateSizeFactors(dds)
        # Robust dispersion estimation: parametric → local → gene-wise (DESeq2's own
        # recommended fallback chain for small / low-variance datasets).
        dds <- tryCatch(
          DESeq(dds, quiet=TRUE),
          error=function(e) {
            message("Parametric DESeq failed for '", cid, "' (", conditionMessage(e), "); retrying fitType='local'")
            tryCatch(
              DESeq(dds, fitType="local", quiet=TRUE),
              error=function(e2) {
                message("Local fit also failed (", conditionMessage(e2), "); using gene-wise dispersion estimates")
                dds <- estimateDispersionsGeneEst(dds, quiet=TRUE)
                dispersions(dds) <- mcols(dds)\$dispGeneEst
                nbinomWaldTest(dds)
              }
            )
          }
        )
        res <- results(dds, contrast=c("condition_grp", ctgt, cref), alpha=${max_qval})
        res_df <- as.data.frame(res)
        res_df <- res_df[order(res_df\$padj, na.last=TRUE), ]
        write.csv(res_df, paste0(cid, "_DESeq2_results.csv"), row.names=TRUE)
        all_results[[cid]] <- res_df

        sig_genes <- rownames(res_df)[!is.na(res_df\$padj) & res_df\$padj < ${max_qval} &
                                       abs(res_df\$log2FoldChange) >= log2(${min_fc})]
        if (length(sig_genes) > 0) writeLines(sig_genes, paste0(cid, "_significant_genes.txt"))
        volcano_plot(res_df, cid)

        tryCatch({
          vsd <- tryCatch(vst(dds, blind=TRUE), error=function(e) { warning("VST failed, using rlog: ", e\$message); rlog(dds, blind=TRUE) })
          pca_data <- plotPCA(vsd, intgroup="condition_grp", returnData=TRUE)
          pct_var  <- round(100 * attr(pca_data, "percentVar"))
          p_pca <- ggplot(pca_data, aes(PC1, PC2, colour=condition_grp, label=name)) +
            geom_point(size=3.5) + theme_bw() +
            labs(x=paste0("PC1: ", pct_var[1], "% variance"), y=paste0("PC2: ", pct_var[2], "% variance"), title=paste0("PCA — ", cid))
          if (requireNamespace("ggrepel", quietly=TRUE)) p_pca <- p_pca + ggrepel::geom_text_repel(size=3, max.overlaps=20)
          ggsave(paste0(cid, "_PCA.pdf"), p_pca, width=7, height=5)
        }, error=function(e) warning("PCA plot failed: ", e\$message))

        saveRDS(dds, paste0(cid, "_dds.rds"))
      }
    }

    # ── QC metrics (shared) ─────────────────────────────────────────────────────
    .n_sig_total <- sum(sapply(all_results, function(r) sum(!is.na(r\$padj) & r\$padj < ${max_qval} & abs(r\$log2FoldChange) >= log2(${min_fc}))))
    .n_tested    <- sum(sapply(all_results, nrow))
    .proc <- if (de_method == "limma") "LIMMA_DIFFERENTIAL_ANALYSIS" else "DESEQ2_DIFFERENTIAL_ANALYSIS"
    .qc <- list(
      success = TRUE,
      process = .proc,
      method  = de_method,
      domain  = "transcriptomics",
      n_contrasts      = nrow(contrasts_df),
      n_genes_tested   = .n_tested,
      n_significant    = .n_sig_total,
      pval_cutoff      = ${max_qval},
      fc_cutoff        = ${min_fc},
      gates_by_label   = list(
        "differential expression" = list(
          gate_row    = paste0(de_method, "_differential_expression"),
          metric_name = "n_significant_genes",
          metric_value = .n_sig_total,
          passes      = .n_sig_total > 0,
          status      = paste0(.n_sig_total, " features significant at padj<${max_qval}, |FC|>=${min_fc} (", de_method, ")")
        )
      ),
      harness_version  = "0.4.0-deseq2-limma"
    )
    cat(jsonlite::toJSON(.qc, auto_unbox=TRUE, pretty=TRUE, null="null"), file="qc_metrics.json")

    .ver <- if (de_method == "limma") as.character(packageVersion('limma')) else as.character(packageVersion('DESeq2'))
    writeLines(c(paste0('"', .proc, '":'), paste0('    ', de_method, ': ', .ver)), "versions.yml")
    """

    stub:
    """
    touch DESeq2_results.csv qc_metrics.json versions.yml
    """
}

workflow DIFFERENTIALABUNDANCE {
    main:
    def _blank = { v ->
        def s = (v == null) ? '' : v.toString().trim()
        return !s || s.equalsIgnoreCase('null') || s.equalsIgnoreCase('none')
    }
    // When no data inputs are supplied, use vendored GSE227835 MG PBMC tutorial
    // CSVs under sample_data/mg_demo (Channel.fromPath on local files — no remote
    // storage download). Partial supply still requires a samplesheet.
    def demo = _blank(params.samplesheet) && _blank(params.input) &&
               _blank(params.matrix) && _blank(params.contrasts)
    if (demo) {
        log.warn "[demo] no --samplesheet/--matrix/--contrasts -> sample_data/mg_demo/"
    } else if (_blank(params.samplesheet) && _blank(params.input)) {
        error "Please provide --samplesheet (sample metadata CSV, S3 URI, or local path)"
    }

    def demo_dir = "${projectDir}/../../sample_data/mg_demo"
    def ss  = demo ? "${demo_dir}/sample_metadata.csv" : (params.samplesheet ?: params.input)
    def mat = demo ? "${demo_dir}/counts_matrix.csv"   : (params.matrix ?: '')
    def con = demo ? "${demo_dir}/contrasts.csv"       : (params.contrasts ?: '')

    // Prefer local / already-staged paths. checkIfExists fails fast with a clear
    // path error instead of nf-amazon "Exception thrown downloading storage".
    ch_ss  = Channel.fromPath(ss, checkIfExists: true)
    ch_mat = (mat?.toString()?.trim()) ? Channel.fromPath(mat, checkIfExists: true) : Channel.empty()
    ch_con = (con?.toString()?.trim()) ? Channel.fromPath(con, checkIfExists: true) : Channel.empty()

    ch_input = ch_ss.mix(ch_mat).mix(ch_con)
        .collect()
        .map { files -> [[id: 'run'], files] }

    DESEQ2_DIFFERENTIAL_ANALYSIS(ch_input)

    emit:
    tables   = DESEQ2_DIFFERENTIAL_ANALYSIS.out.tables
    plots    = DESEQ2_DIFFERENTIAL_ANALYSIS.out.plots
    objects  = DESEQ2_DIFFERENTIAL_ANALYSIS.out.objects
    versions = DESEQ2_DIFFERENTIAL_ANALYSIS.out.versions
}

workflow {
    DIFFERENTIALABUNDANCE()
}
