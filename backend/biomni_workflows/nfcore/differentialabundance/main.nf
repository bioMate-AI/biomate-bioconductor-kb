// nf-core/differentialabundance — BioMate stub with embedded R (DESeq2)
// Input files are downloaded via aws s3 cp in the R script (no path staging).
// Pattern follows validation_deseq2_raw_counts/main.nf.

nextflow.enable.dsl = 2

params.input            = null          // Sample metadata CSV (S3 URI or local path)
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

// Steps:
//  * 1. [Input Download] Download samplesheet and count matrix from S3
//  * 2. [Normalisation] Normalise counts with DESeq2 VST/rlog
//  * 3. [Differential Abundance] Run DESeq2 per contrast
//  * 4. [Visualisation & Report] PCA, volcano, MA plots + HTML report

process DESEQ2_DIFFERENTIAL_ANALYSIS {
    tag "DESeq2"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

    // Input files are downloaded inside the R script via aws s3 cp.
    // Using val (not path) avoids Channel.fromPath S3-FS-type probing on Nextflow 25.x.
    input:
    val meta

    output:
    tuple val(meta), path("*.csv"),           emit: tables,   optional: true
    tuple val(meta), path("*.pdf"),           emit: plots,    optional: true
    tuple val(meta), path("*.rds"),           emit: objects,  optional: true
    tuple val(meta), path("*.html"),          emit: report,   optional: true
    tuple val(meta), path("qc_metrics.json"), emit: qc_metrics
    path "versions.yml",                      emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def min_fc    = params.differential_min_fold_change ?: 2.0
    def max_qval  = params.differential_max_qval ?: 0.05
    def input_uri = params.input ?: ''
    def matrix_uri    = params.matrix ?: ''
    def contrasts_uri = params.contrasts ?: ''
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies
    .bm_deps <- c("DESeq2", "ggplot2", "ggrepel", "pheatmap")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }

    # ── 1. Download inputs from S3 (or copy from local) ──────────────────────
    dl <- function(uri, dest) {
      if (is.null(uri) || nchar(trimws(uri)) == 0 || uri == "null") return(FALSE)
      if (startsWith(uri, "s3://")) {
        ret <- system(paste("aws s3 cp", shQuote(uri), shQuote(dest)), wait=TRUE)
        return(ret == 0 && file.exists(dest))
      } else if (file.exists(uri)) {
        return(file.copy(uri, dest))
      }
      FALSE
    }

    ok_meta <- dl("${input_uri}", "sample_metadata.csv")
    ok_mat  <- dl("${matrix_uri}", "counts_matrix.csv")
    ok_con  <- dl("${contrasts_uri}", "contrasts.csv")
    cat(sprintf("[DESeq2] downloads: metadata=%s  matrix=%s  contrasts=%s\\n",
                ok_meta, ok_mat, ok_con))

    library(DESeq2)
    library(ggplot2)

    # ── 2. Load inputs by name ────────────────────────────────────────────────
    all_files <- list.files(".", pattern = "\\.csv\$", recursive = FALSE)
    meta_file <- all_files[grepl("sample|metadata|samplesheet", tolower(all_files))][1]
    mat_file  <- all_files[grepl("matrix|count|expression", tolower(all_files))][1]
    con_file  <- all_files[grepl("contrast", tolower(all_files))][1]

    if (is.na(meta_file)) stop("No samplesheet/metadata CSV found. Provide a file with 'sample' in the name.")
    if (is.na(mat_file))  stop("No count matrix CSV found. Provide a file with 'matrix' or 'count' in the name.")

    metadata  <- read.csv(meta_file, stringsAsFactors=FALSE)
    count_mat <- read.csv(mat_file, row.names=1, check.names=FALSE)

    # Ensure integer counts
    count_mat <- round(count_mat)
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
      dds <- tryCatch(
        DESeqDataSetFromMatrix(countData=count_mat, colData=col_data,
                               design=as.formula(paste0("~", cvar))),
        error=function(e) stop("DESeq2 setup failed for contrast '", cid, "': ", e\$message)
      )
      dds <- estimateSizeFactors(dds)
      dds <- tryCatch(
        DESeq(dds, quiet=TRUE),
        error=function(e) stop("DESeq2 failed for contrast '", cid, "': ", e\$message)
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
      harness_version  = "0.3.0-deseq2-val"
    )
    cat(jsonlite::toJSON(.qc, auto_unbox=TRUE, pretty=TRUE, null="null"), file="qc_metrics.json")

    writeLines(c('"DESEQ2_DIFFERENTIAL_ANALYSIS":', paste0('    DESeq2: ', as.character(packageVersion('DESeq2')))), "versions.yml")
    """

    stub:
    """
    touch DESeq2_results.csv qc_metrics.json versions.yml
    """
}

workflow DIFFERENTIALABUNDANCE {
    main:
    if (!params.input) error "Please provide --input (sample metadata CSV or S3 URI)"

    DESEQ2_DIFFERENTIAL_ANALYSIS(Channel.value([id: 'run']))

    emit:
    tables   = DESEQ2_DIFFERENTIAL_ANALYSIS.out.tables
    plots    = DESEQ2_DIFFERENTIAL_ANALYSIS.out.plots
    objects  = DESEQ2_DIFFERENTIAL_ANALYSIS.out.objects
    versions = DESEQ2_DIFFERENTIAL_ANALYSIS.out.versions
}

workflow {
    DIFFERENTIALABUNDANCE()
}
