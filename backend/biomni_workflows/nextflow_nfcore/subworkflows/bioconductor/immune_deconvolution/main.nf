#!/usr/bin/env nextflow
// ============================================================
// BioMate: Immune Deconvolution Subworkflow
// Sprint 2 — Immune deconvolution of bulk RNA-seq data
//
// Estimates the cellular composition of bulk RNA-seq mixtures
// using the DeconRNASeq Bioconductor package (CIBERSORT-style).
// A post-processing step computes per-sample immune scores and
// optionally correlates immune fractions with clinical metadata.
//
// Processes:
//   BIOC_DECONRNASEQ      — deconvolution (genes × samples → fractions)
//   IMMUNEDECONV_SUMMARY  — immune scoring + correlation heatmap
//
// Entry workflow: IMMUNE_DECONVOLUTION
// ============================================================

nextflow.enable.dsl = 2

// ────────────────────────────────────────────────────────────
// Parameters
// ────────────────────────────────────────────────────────────
params.outdir              = './results/immune_deconvolution'
params.mock_mode           = true
// Real inputs (ignored in mock mode)
params.counts_matrix       = null   // TSV/CSV: genes × samples (raw counts)
params.signature_matrix    = null   // TSV/CSV: genes × cell-types (LM22 or custom)
params.clinical_metadata   = null   // TSV/CSV: sample → clinical variables (optional)
// Deconvolution settings
params.method              = 'DeconRNASeq'   // DeconRNASeq | EPIC | BayesDeBulk
params.scale_counts        = true
params.checksig            = false

// ────────────────────────────────────────────────────────────
// PROCESS 1: Immune deconvolution
// ────────────────────────────────────────────────────────────

process BIOC_DECONRNASEQ {
    tag "${meta.id}"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}/deconvolution", mode: 'copy'

    conda "bioconductor-deconrnaseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-deconrnaseq:1.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-deconrnaseq:1.46.0--r44_0'}"

    input:
    tuple val(meta), path(counts_matrix), path(signature_matrix)

    output:
    tuple val(meta), path("${meta.id}_cell_fractions.csv"),    emit: cell_fractions
    tuple val(meta), path("${meta.id}_deconvolution_plot.pdf"), emit: plot
    tuple val(meta), path("${meta.id}_deconvolution.rds"),     emit: rds
    path "versions.yml",                                         emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix   = task.ext.prefix ?: "${meta.id}"
    def mock     = params.mock_mode
    def scale    = params.scale_counts
    def checksig = params.checksig
    """
    #!/usr/bin/env Rscript
    suppressPackageStartupMessages({
        library(DeconRNASeq)
    })

    mock_mode  <- ${mock}
    scale      <- ${scale}
    checksig   <- ${checksig}
    prefix     <- "${prefix}"

    # Eight canonical immune cell types present in LM22 / TIMER2.0
    IMMUNE_CELL_TYPES <- c(
        "CD8_T_cell", "CD4_T_cell", "NK_cell",
        "B_cell", "Monocyte", "Dendritic_cell",
        "Neutrophil", "Mast_cell"
    )

    if (mock_mode) {
        # ── Mock mode ──────────────────────────────────────────────
        # Generate a synthetic fractions matrix (10 samples × 8 cell types).
        # Each row sums to 1 (Dirichlet-like composition).
        set.seed(42)
        n_samples   <- 10
        sample_ids  <- paste0("SAMPLE_", seq_len(n_samples))

        # Simulate immune-hot vs immune-cold samples
        fractions <- matrix(NA_real_, nrow = n_samples, ncol = length(IMMUNE_CELL_TYPES),
                            dimnames = list(sample_ids, IMMUNE_CELL_TYPES))

        for (i in seq_len(n_samples)) {
            alpha <- if (i <= 5) {
                # Immune-hot: T-cell enriched
                c(0.25, 0.20, 0.10, 0.10, 0.15, 0.08, 0.07, 0.05)
            } else {
                # Immune-cold: monocyte/neutrophil enriched
                c(0.05, 0.08, 0.04, 0.06, 0.30, 0.12, 0.28, 0.07)
            }
            # Add Dirichlet-like noise
            raw      <- alpha + abs(rnorm(length(alpha), 0, 0.03))
            fractions[i, ] <- raw / sum(raw)
        }

        result_df  <- as.data.frame(fractions)
        decon_obj  <- list(
            out.all     = result_df,
            method      = "DeconRNASeq_mock",
            mock        = TRUE,
            cell_types  = IMMUNE_CELL_TYPES,
            n_samples   = n_samples
        )
    } else {
        # ── Live mode ──────────────────────────────────────────────
        counts_file <- "${counts_matrix}"
        sig_file    <- "${signature_matrix}"

        # Read inputs — accept TSV or CSV
        read_table_auto <- function(f) {
            sep <- if (grepl("\\\\.tsv\$", f, ignore.case = TRUE)) "\\t" else ","
            read.table(f, header = TRUE, sep = sep, row.names = 1,
                       check.names = FALSE, stringsAsFactors = FALSE)
        }

        datasets   <- read_table_auto(counts_file)
        signatures <- read_table_auto(sig_file)

        # Align genes
        common_genes <- intersect(rownames(datasets), rownames(signatures))
        if (length(common_genes) < 50)
            stop(sprintf("Only %d genes overlap between counts and signature matrix", length(common_genes)))

        datasets   <- datasets[common_genes, , drop = FALSE]
        signatures <- signatures[common_genes, , drop = FALSE]

        decon_obj  <- DeconRNASeq(
            datasets   = datasets,
            signatures = signatures,
            checksig   = checksig,
            use.scale  = scale,
            fig        = FALSE
        )
        result_df  <- as.data.frame(decon_obj\$out.all)
        rownames(result_df) <- colnames(datasets)
    }

    # ── Write outputs ──────────────────────────────────────────
    write.csv(result_df, paste0(prefix, "_cell_fractions.csv"), row.names = TRUE)
    saveRDS(decon_obj, paste0(prefix, "_deconvolution.rds"))

    # ── Simple barplot of mean fractions ──────────────────────
    pdf(paste0(prefix, "_deconvolution_plot.pdf"), width = 10, height = 6)
    mean_fracs <- colMeans(result_df, na.rm = TRUE)
    barplot(
        t(as.matrix(result_df)),
        beside      = FALSE,
        col         = rainbow(ncol(result_df)),
        main        = "Immune Cell Fractions per Sample",
        ylab        = "Estimated fraction",
        xlab        = "Sample",
        las         = 2,
        cex.names   = 0.7,
        legend.text = colnames(result_df),
        args.legend = list(x = "topright", cex = 0.6)
    )
    dev.off()

    # ── versions.yml ──────────────────────────────────────────
    pkg_ver <- tryCatch(as.character(packageVersion("DeconRNASeq")), error = function(e) "unknown")
    writeLines(
        c("BIOC_DECONRNASEQ:",
          paste0("    DeconRNASeq: ", pkg_ver),
          paste0("    R: ", R.version\$major, ".", R.version\$minor)),
        "versions.yml"
    )

    message(sprintf("DeconRNASeq complete: %d samples, %d cell types",
                    nrow(result_df), ncol(result_df)))
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cell_fractions.csv
    touch ${prefix}_deconvolution_plot.pdf
    touch ${prefix}_deconvolution.rds
    echo "BIOC_DECONRNASEQ:" > versions.yml
    echo "    DeconRNASeq: 1.46.0" >> versions.yml
    echo "    R: 4.4" >> versions.yml
    """
}

// ────────────────────────────────────────────────────────────
// PROCESS 2: Immune summary + correlation
// ────────────────────────────────────────────────────────────

process IMMUNEDECONV_SUMMARY {
    tag "${meta.id}"
    label 'process_low'
    publishDir "${params.outdir}/${meta.id}/summary", mode: 'copy'

    conda "bioconductor-deconrnaseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-deconrnaseq:1.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-deconrnaseq:1.46.0--r44_0'}"

    input:
    tuple val(meta), path(cell_fractions)
    path(clinical_metadata)   // optional — pass file('NO_FILE') when absent

    output:
    tuple val(meta), path("${meta.id}_immune_summary.csv"),    emit: summary
    tuple val(meta), path("${meta.id}_correlation_heatmap.pdf"), emit: heatmap
    path "versions.yml",                                          emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix   = task.ext.prefix ?: "${meta.id}"
    def mock     = params.mock_mode
    def has_clin = (clinical_metadata.name != 'NO_FILE')
    """
    #!/usr/bin/env Rscript
    suppressPackageStartupMessages({
        library(stats)
        library(grDevices)
    })

    prefix     <- "${prefix}"
    mock_mode  <- ${mock}
    has_clin   <- ${has_clin}

    # ── Load cell fractions ────────────────────────────────────
    fractions <- read.csv("${cell_fractions}", row.names = 1, check.names = FALSE)

    # ── Compute immune scores ──────────────────────────────────
    # T-cell inflamed score (TIS): mean of CD8+T, CD4+T, NK (consensus panel proxy)
    t_cell_cols <- intersect(
        c("CD8_T_cell", "CD4_T_cell", "NK_cell"),
        colnames(fractions)
    )
    # Total immune score: 1 - (largest non-immune fraction)
    # Here we treat Neutrophil as the dominant non-immune proxy
    neutrophil_col <- intersect("Neutrophil", colnames(fractions))

    summary_df <- data.frame(
        sample_id           = rownames(fractions),
        total_immune_score  = rowSums(fractions, na.rm = TRUE),   # should be ~1 but shows composition
        t_cell_inflamed_score = if (length(t_cell_cols) > 0)
                                    rowMeans(fractions[, t_cell_cols, drop = FALSE], na.rm = TRUE)
                                else NA_real_,
        immune_class        = NA_character_,
        stringsAsFactors    = FALSE
    )

    # Simple 3-tier classifier
    tis <- summary_df\$t_cell_inflamed_score
    summary_df\$immune_class <- ifelse(
        is.na(tis), "unknown",
        ifelse(tis > 0.18, "immune_hot",
        ifelse(tis < 0.08, "immune_cold", "immune_intermediate"))
    )

    # ── Correlation with clinical variables (if provided) ─────
    clin_cols_used <- character(0)
    if (has_clin && file.exists("${clinical_metadata}")) {
        clin <- tryCatch({
            read.table("${clinical_metadata}", header = TRUE, sep = "\\t",
                       row.names = 1, stringsAsFactors = FALSE)
        }, error = function(e) NULL)

        if (!is.null(clin)) {
            common_samples <- intersect(rownames(fractions), rownames(clin))
            if (length(common_samples) >= 3) {
                num_clin <- clin[common_samples, sapply(clin, is.numeric), drop = FALSE]
                if (ncol(num_clin) > 0) {
                    clin_cols_used <- colnames(num_clin)
                    # Append clinical columns to summary
                    summary_df_clin <- merge(
                        summary_df,
                        cbind(sample_id = rownames(num_clin), num_clin),
                        by = "sample_id", all.x = TRUE
                    )
                    summary_df <- summary_df_clin
                }
            }
        }
    }

    # ── Write immune summary ───────────────────────────────────
    write.csv(summary_df, paste0(prefix, "_immune_summary.csv"), row.names = FALSE)

    # ── Correlation heatmap ────────────────────────────────────
    pdf(paste0(prefix, "_correlation_heatmap.pdf"), width = 8, height = 8)

    if (mock_mode || ncol(fractions) < 2) {
        # Simple cell-type correlation matrix
        cor_mat <- cor(fractions, use = "pairwise.complete.obs")
        image(
            x    = seq_len(nrow(cor_mat)),
            y    = seq_len(ncol(cor_mat)),
            z    = cor_mat,
            col  = colorRampPalette(c("#2166AC", "white", "#D6604D"))(100),
            xaxt = "n", yaxt = "n",
            main = "Cell-type Correlation Matrix",
            xlab = "", ylab = ""
        )
        axis(1, at = seq_len(nrow(cor_mat)), labels = rownames(cor_mat), las = 2, cex.axis = 0.7)
        axis(2, at = seq_len(ncol(cor_mat)), labels = colnames(cor_mat), las = 1, cex.axis = 0.7)
    } else {
        # Fraction heatmap across samples
        mat <- t(as.matrix(fractions))
        image(
            x    = seq_len(nrow(mat)),
            y    = seq_len(ncol(mat)),
            z    = mat,
            col  = colorRampPalette(c("white", "#1A5276", "#E74C3C"))(100),
            xaxt = "n", yaxt = "n",
            main = "Immune Fractions Heatmap (samples × cell types)",
            xlab = "Sample", ylab = "Cell type"
        )
        axis(1, at = seq_len(nrow(mat)), labels = rownames(mat), las = 2, cex.axis = 0.6)
        axis(2, at = seq_len(ncol(mat)), labels = colnames(mat), las = 1, cex.axis = 0.7)
    }
    dev.off()

    # ── versions.yml ──────────────────────────────────────────
    writeLines(
        c("IMMUNEDECONV_SUMMARY:",
          paste0("    R: ", R.version\$major, ".", R.version\$minor),
          "    immunedeconv_summary: 1.0.0"),
        "versions.yml"
    )

    message(sprintf("Immune summary complete: %d samples classified", nrow(summary_df)))
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_immune_summary.csv
    touch ${prefix}_correlation_heatmap.pdf
    echo "IMMUNEDECONV_SUMMARY:" > versions.yml
    echo "    R: 4.4" >> versions.yml
    """
}

// ────────────────────────────────────────────────────────────
// Entry sub-workflow
// ────────────────────────────────────────────────────────────

workflow IMMUNE_DECONVOLUTION {
    take:
    ch_input     // channel: [ val(meta), path(counts_matrix), path(signature_matrix) ]
    ch_clinical  // channel: path(clinical_metadata) — use file('NO_FILE') when absent

    main:
    BIOC_DECONRNASEQ(ch_input)

    IMMUNEDECONV_SUMMARY(
        BIOC_DECONRNASEQ.out.cell_fractions,
        ch_clinical
    )

    emit:
    cell_fractions  = BIOC_DECONRNASEQ.out.cell_fractions    // [ val(meta), path(csv) ]
    deconv_plot     = BIOC_DECONRNASEQ.out.plot              // [ val(meta), path(pdf) ]
    rds             = BIOC_DECONRNASEQ.out.rds               // [ val(meta), path(rds) ]
    immune_summary  = IMMUNEDECONV_SUMMARY.out.summary       // [ val(meta), path(csv) ]
    heatmap         = IMMUNEDECONV_SUMMARY.out.heatmap       // [ val(meta), path(pdf) ]
    versions        = BIOC_DECONRNASEQ.out.versions.mix(
                          IMMUNEDECONV_SUMMARY.out.versions) // path(versions.yml)
}

// ────────────────────────────────────────────────────────────
// Standalone execution entry point
// ────────────────────────────────────────────────────────────

workflow {
    // In mock mode the actual file paths are ignored inside the R script.
    // Supply placeholder paths so the channel tuple is well-formed.
    // Use distinct names to avoid Nextflow filename-collision error in stub mode.
    def counts_path = params.counts_matrix
        ? file(params.counts_matrix)
        : file('NO_COUNTS_FILE')

    def sig_path = params.signature_matrix
        ? file(params.signature_matrix)
        : file('NO_SIGNATURE_FILE')

    def clin_path = params.clinical_metadata
        ? file(params.clinical_metadata)
        : file('NO_FILE')

    ch_input = Channel.of([[id: 'run'], counts_path, sig_path])

    IMMUNE_DECONVOLUTION(ch_input, clin_path)

    IMMUNE_DECONVOLUTION.out.immune_summary.view { meta, f ->
        "Immune summary written to: ${f}"
    }
}
