#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MMUPHin — batch_effect_adjustment
// Correct for technical study and batch effects in microbial feature abundance tables while preserving biological variation of interest.
// Input: abundance_table.tsv, metadata.tsv
// Container: quay.io/biocontainers/bioconductor-mmuphin:1.16.0--r43hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MMUPHin, vegan
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run adjust_batch to generate batch-adjusted abundances
//  * 2. [Core Analysis] Calculate sample dissimilarity matrices before and after adjustment using vegan::vegdist
//  * 3. [Core Analysis] Evaluate batch effect reduction using PERMANOVA via vegan::adonis2

nextflow.enable.dsl = 2

process BIOC_MMUPHIN_BATCH_EFFECT_ADJUSTMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metagenomics:3.20-deps"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("MMUPHin", "vegan")
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
    library(MMUPHin)
    library(vegan)
    
    # 1. Read User Input Files
    # The pipeline expects 'abundance_table.tsv' and 'metadata.tsv' in the working directory.
    CRC_abd <- as.matrix(read.table("abundance_table.tsv", header = TRUE, sep = "\t", row.names = 1, check.names = FALSE))
    CRC_meta <- read.table("metadata.tsv", header = TRUE, sep = "\t", row.names = 1, check.names = FALSE)
    
    # Align sample IDs between abundance table (columns) and metadata (rows)
    common_samples <- intersect(colnames(CRC_abd), rownames(CRC_meta))
    if (length(common_samples) == 0) {
      stop("Error: No matching sample IDs found between abundance table columns and metadata rows.")
    }
    CRC_abd <- CRC_abd[, common_samples, drop = FALSE]
    CRC_meta <- CRC_meta[common_samples, , drop = FALSE]
    
    # 2. Run adjust_batch to generate batch-adjusted abundances
    fit_adjust_batch <- adjust_batch(feature_abd = CRC_abd,
                                     batch = "studyID",
                                     covariates = "study_condition",
                                     data = CRC_meta,
                                     control = list(verbose = FALSE))
    
    CRC_abd_adj <- fit_adjust_batch\$feature_abd_adj
    
    # 3. Calculate sample dissimilarity matrices before and after adjustment
    D_before <- vegdist(t(CRC_abd))
    D_after <- vegdist(t(CRC_abd_adj))
    
    # 4. Evaluate batch effect reduction using PERMANOVA
    set.seed(1)
    fit_adonis_before <- adonis2(D_before ~ studyID, data = CRC_meta)
    fit_adonis_after <- adonis2(D_after ~ studyID, data = CRC_meta)
    
    # 5. Write Output Files
    
    # Save adjusted abundance table
    write.table(CRC_abd_adj, "adjusted_abundance.tsv", sep = "\t", col.names = NA, quote = FALSE)
    
    # Save PERMANOVA results as RDS
    saveRDS(list(before = fit_adonis_before, after = fit_adonis_after), "permanova_results.rds")
    
    # Save PERMANOVA text summary
    sink("permanova_results.txt")
    cat("=== PERMANOVA Before Batch Correction ===\n")
    print(fit_adonis_before)
    cat("\n=== PERMANOVA After Batch Correction ===\n")
    print(fit_adonis_after)
    sink()
    
    # Generate and save PCoA diagnostic plot
    pdf("batch_adjustment_pcoa.pdf", width = 12, height = 6)
    par(mfrow = c(1, 2))
    studies <- as.factor(CRC_meta\$studyID)
    colors <- rainbow(length(levels(studies)))
    
    # PCoA Before Adjustment
    pcoa_before <- cmdscale(D_before, k = 2)
    plot(pcoa_before[, 1], pcoa_before[, 2], col = colors[studies], pch = 19,
         main = paste0("Before Adjustment (R2 = ", round(fit_adonis_before\$R2[1], 3), ")"),
         xlab = "PCoA 1", ylab = "PCoA 2")
    legend("topright", legend = levels(studies), col = colors, pch = 19, bty = "n", cex = 0.8)
    
    # PCoA After Adjustment
    pcoa_after <- cmdscale(D_after, k = 2)
    plot(pcoa_after[, 1], pcoa_after[, 2], col = colors[studies], pch = 19,
         main = paste0("After Adjustment (R2 = ", round(fit_adonis_after\$R2[1], 3), ")"),
         xlab = "PCoA 1", ylab = "PCoA 2")
    dev.off()

    writeLines(c(
        '"BIOC_MMUPHIN_BATCH_EFFECT_ADJUSTMENT":',
        paste0('    MMUPHin: ', as.character(packageVersion('MMUPHin')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_batch_effect_adjustment.csv versions.yml
    """
}

workflow BIOC_MMUPHIN_BATCH_EFFECT_ADJUSTMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ abundance_table.tsv, metadata.tsv ] ]

    main:
    BIOC_MMUPHIN_BATCH_EFFECT_ADJUSTMENT(ch_input)

    emit:
    tables   = BIOC_MMUPHIN_BATCH_EFFECT_ADJUSTMENT.out.tables
    plots    = BIOC_MMUPHIN_BATCH_EFFECT_ADJUSTMENT.out.plots
    objects  = BIOC_MMUPHIN_BATCH_EFFECT_ADJUSTMENT.out.objects
    versions = BIOC_MMUPHIN_BATCH_EFFECT_ADJUSTMENT.out.versions
}
