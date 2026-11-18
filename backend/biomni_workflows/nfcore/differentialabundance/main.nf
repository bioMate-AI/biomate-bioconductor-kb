// nf-core/differentialabundance — BioMate stub with embedded R (DESeq2)
// Input files are downloaded via aws s3 cp in the R script (no path staging).
// Pattern follows validation_deseq2_raw_counts/main.nf.

nextflow.enable.dsl = 2

params.samplesheet      = null          // Sample metadata / samplesheet CSV (S3 URI or local path)
params.input            = null          // Alias for samplesheet (nf-core convention)
params.matrix           = null          // Count matrix CSV (genes × samples)
params.contrasts        = null          // Contrasts CSV (id, variable, reference, target)
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

// Input: samplesheet.csv, matrix.csv, contrasts.csv
// Steps:
//  * 1. [Input Staging] Declared data inputs are staged to local files by the executor
//  * 2. [Normalisation] Normalise counts with DESeq2 VST/rlog
//  * 3. [Differential Abundance] Run DESeq2 per contrast (with design-QC self-correction)
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
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] install only what is missing (container has DESeq2/ggplot2/jsonlite pre-installed)
    # ggrepel is optional — only needed for label repelling on volcano/PCA plots
    .bm_deps <- c("DESeq2", "ggplot2")
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

    library(DESeq2)
    library(ggplot2)

    # ── 1. Load inputs by name (files staged by Nextflow from S3) ─────────────
    all_files <- list.files(".", pattern = "\\\\.csv\$", recursive = FALSE)
    meta_file <- all_files[grepl("sample|metadata|samplesheet", tolower(all_files))][1]
    mat_file  <- all_files[grepl("matrix|count|expression", tolower(all_files))][1]
    con_file  <- all_files[grepl("contrast", tolower(all_files))][1]

    if (is.na(meta_file)) stop("No samplesheet/metadata CSV found. Provide a file with 'sample' in the name.")
    if (is.na(mat_file))  stop("No count matrix CSV found. Provide a file with 'matrix' or 'count' in the name.")

    metadata  <- read.csv(meta_file, stringsAsFactors=FALSE)
    count_mat <- read.csv(mat_file, row.names=1, check.names=FALSE)

    # Ensure integer counts (read.csv returns data.frame; as.matrix() required before storage.mode)
    count_mat <- as.matrix(round(count_mat))
    count_mat[is.na(count_mat)] <- 0L
    storage.mode(count_mat) <- "integer"

    # ── 3. Build contrasts ─────────────────────────────────────────────────────
    if (!is.na(con_file)) {
      contrasts_df <- read.csv(con_file, stringsAsFactors=FALSE)
    } else {
      cond_col <- names(metadata)[names(metadata) != "sample"][1]
      lvls <- unique(metadata[[cond_col]])
      contrasts_df <- data.frame(id=paste0(lvls[1],"_vs_",lvls[2]),
                                 variable=cond_col, reference=lvls[2], target=lvls[1])
    }

    # ── 4. Align samples ───────────────────────────────────────────────────────
    sample_col <- if ("sample" %in% names(metadata)) "sample" else names(metadata)[1]
    common <- intersect(metadata[[sample_col]], colnames(count_mat))
    if (length(common) == 0) {
      stop(paste("No overlapping sample names between metadata and count matrix.",
                 "Metadata samples:", paste(head(metadata[[sample_col]], 5), collapse=", "),
                 "| Matrix columns:", paste(head(colnames(count_mat), 5), collapse=", ")))
    }
    metadata  <- metadata[metadata[[sample_col]] %in% common, , drop=FALSE]
    count_mat <- count_mat[, metadata[[sample_col]], drop=FALSE]

    # Remove zero-variance genes
    keep <- rowSums(count_mat >= 10) >= max(1, ceiling(0.25 * ncol(count_mat)))
    count_mat <- count_mat[keep, , drop=FALSE]

    all_results <- list()
    design_info <- list()

    for (i in seq_len(nrow(contrasts_df))) {
      ct <- contrasts_df[i, ]
      cid  <- ct[["id"]]
      cvar <- ct[["variable"]]
      cref <- ct[["reference"]]
      ctgt <- ct[["target"]]

      if (!cvar %in% names(metadata)) {
        warning("Variable '", cvar, "' not in metadata; skipping contrast '", cid, "'")
        next
      }

      # ── 5. DESeq2 ─────────────────────────────────────────────────────────
      col_data <- metadata
      col_data[[cvar]] <- relevel(factor(col_data[[cvar]]), ref=cref)

      # ── 5a. Design-QC self-correction ────────────────────────────────────
      # A naive design ~cvar ignores any blocking/paired factor present in the
      # metadata. If an unmodeled covariate (e.g. cell line, batch, donor) is
      # balanced across the contrast AND explains real variance, leaving it out
      # confounds the test. We DETECT it (LRT ~block+cvar vs ~cvar), flag a
      # design_qc gate, and RE-FIT with it as a blocking factor — the correction
      # actually changes the DE result. An explicit 'blocking' column in the
      # contrasts CSV (nf-core convention) is honoured directly.
      block_var <- NA_character_; n_sig_block <- 0L; design_confounded <- FALSE
      if ("blocking" %in% names(ct) && !is.na(ct[["blocking"]]) && nzchar(as.character(ct[["blocking"]]))) {
        bv <- strsplit(as.character(ct[["blocking"]]), "[;,]")[[1]][1]
        if (bv %in% names(col_data)) { block_var <- bv; design_confounded <- TRUE }
      } else {
        block_candidates <- setdiff(names(col_data), c(sample_col, cvar))
        for (bc in block_candidates) {
          f <- factor(col_data[[bc]])
          if (nlevels(f) < 2 || nlevels(f) >= nrow(col_data)) next
          # balanced = each blocking level spans >=2 levels of the contrast variable
          tab <- table(f, factor(col_data[[cvar]]))
          if (!all(rowSums(tab > 0) >= 2)) next
          cd2 <- col_data; cd2[[bc]] <- f
          ddf <- tryCatch(DESeqDataSetFromMatrix(count_mat, cd2,
                            design=as.formula(paste0("~", bc, "+", cvar))), error=function(e) NULL)
          if (is.null(ddf)) next
          ddf <- tryCatch(DESeq(ddf, test="LRT", reduced=as.formula(paste0("~", cvar)), quiet=TRUE),
                          error=function(e) NULL)
          if (is.null(ddf)) next
          rb <- results(ddf); nb <- sum(!is.na(rb\$padj) & rb\$padj < ${max_qval})
          if (nb > n_sig_block) { n_sig_block <- nb; block_var <- bc }
        }
        # confounded if the best blocking covariate explains >=2% of tested genes
        design_confounded <- !is.na(block_var) && n_sig_block >= max(1, ceiling(0.02 * nrow(count_mat)))
        if (!design_confounded) block_var <- NA_character_
      }
      design_naive     <- paste0("~", cvar)
      design_corrected <- if (!is.na(block_var)) paste0("~", block_var, "+", cvar) else design_naive
      final_design     <- if (design_confounded && !is.na(block_var)) design_corrected else design_naive

      # Naive fit (~cvar) for the before/after delta the self-correction reports
      n_sig_naive <- NA_integer_
      if (design_confounded && !is.na(block_var)) {
        ddn <- tryCatch(DESeqDataSetFromMatrix(count_mat, col_data, design=as.formula(design_naive)), error=function(e) NULL)
        if (!is.null(ddn)) {
          ddn <- tryCatch(DESeq(ddn, quiet=TRUE), error=function(e) tryCatch(DESeq(ddn, fitType="local", quiet=TRUE), error=function(e2) NULL))
          if (!is.null(ddn)) {
            rn <- results(ddn, contrast=c(cvar, ctgt, cref), alpha=${max_qval})
            n_sig_naive <- sum(!is.na(rn\$padj) & rn\$padj < ${max_qval} & abs(rn\$log2FoldChange) >= log2(${min_fc}))
          }
        }
      }
      if (!is.na(block_var)) col_data[[block_var]] <- factor(col_data[[block_var]])
      message("[design-qc] contrast '", cid, "': naive design ", design_naive,
              if (design_confounded) paste0(" -> CONFOUNDED by '", block_var, "' (", n_sig_block,
              " genes); re-fitting ", final_design) else " (no blocking confounder detected)")

      dds <- tryCatch(
        DESeqDataSetFromMatrix(countData=count_mat, colData=col_data,
                               design=as.formula(final_design)),
        error=function(e) stop("DESeq2 setup failed for contrast '", cid, "': ", e\$message)
      )
      dds <- estimateSizeFactors(dds)
      # Robust dispersion estimation. The default parametric fit throws on small or
      # low-variance datasets ("all gene-wise dispersion estimates are within 2 orders
      # of magnitude from the minimum value ..."). Fall back to a local fit, then to
      # gene-wise estimates as final — exactly the recovery DESeq2's own error message
      # recommends. This is the canonical robust pipeline, correct for real small-n
      # studies, not a demo-only workaround.
      dds <- tryCatch(
        DESeq(dds, quiet=TRUE),
        error=function(e) {
          message("Parametric DESeq failed for '", cid, "' (", conditionMessage(e),
                  "); retrying with fitType='local'")
          tryCatch(
            DESeq(dds, fitType="local", quiet=TRUE),
            error=function(e2) {
              message("Local fit also failed (", conditionMessage(e2),
                      "); using gene-wise dispersion estimates as final")
              dds <- estimateDispersionsGeneEst(dds, quiet=TRUE)
              dispersions(dds) <- mcols(dds)\$dispGeneEst
              nbinomWaldTest(dds)
            }
          )
        }
      )
      res <- results(dds, contrast=c(cvar, ctgt, cref), alpha=${max_qval})
      res_df <- as.data.frame(res)
      res_df <- res_df[order(res_df\$padj, na.last=TRUE), ]
      out_csv <- paste0(cid, "_DESeq2_results.csv")
      write.csv(res_df, out_csv, row.names=TRUE)
      all_results[[cid]] <- res_df

      # ── 6. Significant gene list ─────────────────────────────────────────
      sig_genes <- rownames(res_df)[!is.na(res_df\$padj) & res_df\$padj < ${max_qval} &
                                     abs(res_df\$log2FoldChange) >= log2(${min_fc})]
      if (length(sig_genes) > 0) {
        writeLines(sig_genes, paste0(cid, "_significant_genes.txt"))
      }
      design_info[[cid]] <- list(
        blocking_var = if (is.na(block_var)) NA else block_var,
        confounded   = isTRUE(design_confounded),
        naive_design = design_naive,
        final_design = final_design,
        n_sig_block  = as.integer(n_sig_block),
        n_sig_naive  = n_sig_naive,
        n_sig_corrected = length(sig_genes)
      )

      # ── 7. Volcano plot ───────────────────────────────────────────────────
      tryCatch({
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
               caption=paste0(sum(res_df\$significant, na.rm=TRUE), " genes significant")) +
          theme_bw(base_size=11) + theme(legend.position="none")
        top_genes <- head(rownames(res_df[res_df\$significant & !is.na(res_df\$significant), ]), 15)
        if (exists("geom_text_repel") && length(top_genes) > 0) {
          p <- p + geom_text_repel(data=res_df[top_genes,], aes(label=rownames(res_df[top_genes,])),
                                    size=2.5, max.overlaps=20)
        }
        ggsave(paste0(cid, "_volcano.pdf"), p, width=7, height=6)
      }, error=function(e) warning("Volcano plot failed: ", e\$message))

      # ── 8. PCA plot ───────────────────────────────────────────────────────
      tryCatch({
        vsd <- tryCatch(vst(dds, blind=TRUE), error=function(e) {
          warning("VST failed, using rlog: ", e\$message)
          rlog(dds, blind=TRUE)
        })
        pca_data <- plotPCA(vsd, intgroup=cvar, returnData=TRUE)
        pct_var  <- round(100 * attr(pca_data, "percentVar"))
        p_pca <- ggplot(pca_data, aes(PC1, PC2, colour=.data[[cvar]], label=name)) +
          geom_point(size=3.5) + theme_bw() +
          labs(x=paste0("PC1: ", pct_var[1], "% variance"),
               y=paste0("PC2: ", pct_var[2], "% variance"),
               title=paste0("PCA — ", cid))
        if (requireNamespace("ggrepel", quietly=TRUE))
          p_pca <- p_pca + ggrepel::geom_text_repel(size=3, max.overlaps=20)
        ggsave(paste0(cid, "_PCA.pdf"), p_pca, width=7, height=5)
      }, error=function(e) warning("PCA plot failed: ", e\$message))

      saveRDS(dds, paste0(cid, "_dds.rds"))
    }

    # ── 9. QC metrics ─────────────────────────────────────────────────────────
    .n_sig_total <- sum(sapply(all_results, function(r) sum(!is.na(r\$padj) & r\$padj < ${max_qval} & abs(r\$log2FoldChange) >= log2(${min_fc}))))
    .n_tested    <- sum(sapply(all_results, nrow))
    .qc <- list(
      success = TRUE,
      process = "DESEQ2_DIFFERENTIAL_ANALYSIS",
      domain  = "transcriptomics",
      n_contrasts      = nrow(contrasts_df),
      n_genes_tested   = .n_tested,
      n_significant    = .n_sig_total,
      pval_cutoff      = ${max_qval},
      fc_cutoff        = ${min_fc},
      gates_by_label   = list(
        "differential expression" = list(
          gate_row    = "deseq2_differential_expression",
          metric_name = "n_significant_genes",
          metric_value = .n_sig_total,
          passes      = .n_sig_total > 0,
          status      = paste0(.n_sig_total, " genes significant at padj<${max_qval}, |FC|>=${min_fc}")
        )
      ),
      design_qc        = lapply(names(design_info), function(.c) design_info[[.c]]),
      harness_version  = "0.4.0-deseq2-designqc"
    )
    names(.qc\$design_qc) <- names(design_info)
    # Explicit design block for the Phase-0 run contract (design.json): the (corrected)
    # final design formula of the primary contrast, its modeled covariates, the
    # candidate blocking factors, and the exposure-of-interest (contrast variable).
    # Populated so the design-aware critics read a real formula instead of a null.
    if (length(design_info) > 0) {
      .primary_di <- design_info[[1]]
      .final_fml  <- if (!is.null(.primary_di\$final_design)) .primary_di\$final_design else .primary_di\$naive_design
      .covs       <- strsplit(sub("^~", "", .final_fml), "\\\\+")[[1]]
      .covs       <- trimws(.covs[nzchar(trimws(.covs))])
      .exposure   <- if (length(.covs) > 0) .covs[length(.covs)] else NA
      .blocks     <- unique(unlist(lapply(design_info, function(d) if (!is.na(d\$blocking_var)) d\$blocking_var else NULL)))
      # group_sizes = samples per exposure level (low-replicate critic); n_samples = total.
      .grp <- tryCatch(as.list(table(metadata[[.exposure]])), error = function(e) NULL)
      .qc\$design <- list(
        formula              = .final_fml,
        covariates           = as.list(.covs),
        candidate_covariates = as.list(.blocks),
        exposure_of_interest = if (is.na(.exposure)) NULL else .exposure,
        model_type           = "de",
        n_samples            = nrow(metadata),
        n_covariates         = length(.covs),
        group_sizes          = .grp,
        design_source        = "workflow"
      )
    }
    # Surface the design-formula self-correction as a gate the harness renders.
    .conf <- Filter(function(x) isTRUE(x\$confounded), design_info)
    if (length(.conf) > 0) {
      .d <- .conf[[1]]
      .qc\$gates_by_label[["design formula"]] <- list(
        gate_row    = "bioc_deseq2_design_blocking",
        metric_name = "blocked_covariate_significant_genes",
        metric_value = as.integer(.d\$n_sig_block),
        passes      = FALSE,
        blocking_var = .d\$blocking_var,
        status      = paste0("Confounder '", .d\$blocking_var, "' omitted from naive design ",
                             .d\$naive_design, "; re-fit as ", .d\$final_design,
                             " (", .d\$n_sig_block, " genes vary by '", .d\$blocking_var,
                             "'; significant genes ", ifelse(is.na(.d\$n_sig_naive), "NA", .d\$n_sig_naive),
                             " -> ", .d\$n_sig_corrected, ")"),
        remediation = paste0("add blocking factor '", .d\$blocking_var, "' to the design formula")
      )
    }
    cat(jsonlite::toJSON(.qc, auto_unbox=TRUE, pretty=TRUE, null="null"), file="qc_metrics.json")

    writeLines(c('"DESEQ2_DIFFERENTIAL_ANALYSIS":', paste0('    DESeq2: ', as.character(packageVersion('DESeq2')))), "versions.yml")
    """

    stub:
    """
    touch DESeq2_results.csv qc_metrics.json versions.yml
    """
}

// Declared-input Bioconductor shape: a `take:`-bound named workflow + the
// `// Input:` header above. The executor stages samplesheet/matrix/contrasts
// as LOCAL files (backend-managed download) and binds the process channel —
// NO anonymous `workflow { }`, so raw `Channel.fromPath(s3://…)` (which throws
// "Exception thrown downloading S3 object") is never used. Mirrors the Cox /
// deseq2 subworkflows that stage reliably via path(input_files, stageAs).
workflow DIFFERENTIALABUNDANCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ samplesheet.csv, matrix.csv, contrasts.csv ] ]

    main:
    DESEQ2_DIFFERENTIAL_ANALYSIS(ch_input)

    emit:
    tables     = DESEQ2_DIFFERENTIAL_ANALYSIS.out.tables
    plots      = DESEQ2_DIFFERENTIAL_ANALYSIS.out.plots
    objects    = DESEQ2_DIFFERENTIAL_ANALYSIS.out.objects
    report     = DESEQ2_DIFFERENTIAL_ANALYSIS.out.report
    qc_metrics = DESEQ2_DIFFERENTIAL_ANALYSIS.out.qc_metrics
    versions   = DESEQ2_DIFFERENTIAL_ANALYSIS.out.versions
}
