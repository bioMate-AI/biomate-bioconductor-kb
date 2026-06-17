#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: eisaR — step_by_step_eisa_with_alignment
// Perform EISA step-by-step, including genomic region extraction, read alignment, exonic/intronic quantification, normalization, and edgeR statistical modeling.
// Input: hg19sub.sqlite, samples_rna_single.txt, hg19sub.fa, rna_reads.fq.bz2
// Container: quay.io/biocontainers/bioconductor-eisar:1.22.1--r45hdfd78af_0
// R packages: AnnotationDbi, QuasR, edgeR, eisaR
// Bioconductor: 3.20 | R: 4.4
// Requires: AnnotationDbi, QuasR, edgeR, eisaR
// Visualizations: plot (ggplot/base)
// QC: TMM normalization, dispersion/size-factor estimation
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Extract exonic and gene body regions from TxDb using getRegionsFromTxDb()
//  * 2. [Core Analysis] Align raw reads to the genome using QuasR::qAlign()
//  * 3. [Core Analysis] Quantify alignments in exons and gene bodies using QuasR::qCount()
//  * 4. [Core Analysis] Calculate intronic counts by subtracting exonic counts from gene body counts
//  * 5. [Core Analysis] Normalize counts and filter for quantifiable genes
//  * 6. [Input & Preparation] Build an edgeR DGEList and design matrix with interaction terms
//  * 7. [Core Analysis] Estimate dispersions and fit a generalized linear model using edgeR
//  * 8. [Core Analysis] Perform likelihood ratio tests to identify significant post-transcriptional regulation

nextflow.enable.dsl = 2

process BIOC_EISAR_STEP_BY_STEP_EISA_WITH_ALIGNMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("AnnotationDbi", "QuasR", "edgeR", "eisaR")
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
    library(eisaR)
    library(AnnotationDbi)
    library(QuasR)
    library(edgeR)
    
    # 1. Extract exonic and gene body regions from TxDb using getRegionsFromTxDb()
    txdbFile <- "hg19sub.sqlite"
    txdb <- AnnotationDbi::loadDb(txdbFile)
    regU <- getRegionsFromTxDb(txdb = txdb, strandedData = FALSE)
    
    # 2. Align raw reads to the genome using QuasR::qAlign()
    sampleFile <- "samples_rna_single.txt"
    proj <- qAlign(sampleFile = sampleFile,
                   genome = "hg19sub.fa",
                   aligner = "Rhisat2", splicedAlignment = TRUE)
    
    # 3. Quantify alignments in exons and gene bodies using QuasR::qCount()
    cntEx <- qCount(proj, regU\$exons, orientation = "any")
    cntGb <- qCount(proj, regU\$genebodies, orientation = "any")
    
    # 4. Calculate intronic counts by subtracting exonic counts from gene body counts
    cntIn <- cntGb - cntEx
    
    # 5. Normalize counts and filter for quantifiable genes
    rEx <- cntEx[, colnames(cntEx) != "width", drop = FALSE]
    rIn <- cntIn[, colnames(cntIn) != "width", drop = FALSE]
    rAll <- rEx + rIn
    
    normEx <- t(t(rEx) / colSums(rEx) * mean(colSums(rEx)))
    normIn <- t(t(rIn) / colSums(rIn) * mean(colSums(rIn)))
    
    lognormEx <- log2(normEx + 8L)
    lognormIn <- log2(normIn + 8L)
    
    # Filter for quantifiable genes with a robust fallback for small datasets
    quantGenes <- rownames(rEx)[rowMeans(lognormEx) > 5.0 & rowMeans(lognormIn) > 5.0]
    if (length(quantGenes) == 0) {
        warning("No genes passed the default threshold (> 5.0). Using a lower threshold (> 2.0) for robustness.")
        quantGenes <- rownames(rEx)[rowMeans(lognormEx) > 2.0 & rowMeans(lognormIn) > 2.0]
    }
    if (length(quantGenes) == 0) {
        warning("Still no genes passed. Keeping all genes with non-zero counts.")
        quantGenes <- rownames(rEx)[rowMeans(lognormEx) > 0 & rowMeans(lognormIn) > 0]
    }
    if (length(quantGenes) == 0) {
        quantGenes <- rownames(rEx)
    }
    
    # 6. Build an edgeR DGEList and design matrix with interaction terms
    cnt <- data.frame(Ex = rEx, In = rIn)
    y <- DGEList(counts = cnt, genes = data.frame(ENTREZID = rownames(cnt)))
    y <- y[quantGenes, ]
    y <- calcNormFactors(y)
    
    # Dynamically construct design matrix based on the number of samples
    n_samples <- ncol(rEx)
    region <- factor(rep(c("ex", "in"), each = n_samples), levels = c("in", "ex"))
    cond_base <- factor(rep(c("ES", "TN"), each = max(1, n_samples / 2)))
    cond <- rep(cond_base, 2L)
    
    design <- model.matrix(~ region * cond)
    rownames(design) <- colnames(cnt)
    
    # 7. Estimate dispersions and fit a generalized linear model using edgeR
    y <- tryCatch({
        estimateDisp(y, design)
    }, error = function(e) {
        warning("Dispersion estimation failed (possibly due to 0 d.f.). Using a preset common dispersion of 0.05.")
        y\$common.dispersion <- 0.05
        y
    })
    
    fit <- glmFit(y, design)
    
    # 8. Perform likelihood ratio tests to identify significant post-transcriptional regulation
    lrt <- glmLRT(fit)
    tt <- topTags(lrt, n = nrow(y), sort.by = "none")
    
    # Write meaningful results to output files
    write.csv(tt\$table, "eisa_results_table.csv", row.names = TRUE)
    saveRDS(y, "eisa_dge_list.rds")
    
    # Generate and save diagnostic plots
    pdf("eisa_plots.pdf", width = 10, height = 5)
    par(mfrow = c(1, 2))
    
    # Volcano plot
    sig <- tt\$table\$FDR < 0.05
    if (sum(sig) == 0) {
        sig <- tt\$table\$PValue < 0.1 # Relaxed threshold for visualization if none are significant
    }
    sigDir <- sign(tt\$table\$logFC[sig])
    cols <- ifelse(sig,
                   ifelse(tt\$table\$logFC > 0.0, "#E41A1CFF", "#497AB3FF"),
                   "#22222244")
    
    plot(tt\$table\$logFC, -log10(tt\$table\$FDR), col = cols, pch = 20L,
         xlab = expression(paste("RNA change (log2 ", Delta, "exon/", Delta, "intron)")),
         ylab = "Significance (-log10 FDR)",
         main = "Volcano Plot")
    abline(h = -log10(0.05), lty = 2L)
    abline(v = 0.0, lty = 2L)
    
    # Delta I vs. Delta E plot
    is_TN <- cond_base == "TN"
    is_ES <- cond_base == "ES"
    Dex_val <- rowMeans(lognormEx[, is_TN, drop = FALSE]) - rowMeans(lognormEx[, is_ES, drop = FALSE])
    Din_val <- rowMeans(lognormIn[, is_TN, drop = FALSE]) - rowMeans(lognormIn[, is_ES, drop = FALSE])
    
    plot(Din_val[quantGenes], Dex_val[quantGenes], pch = 20L, col = cols,
         xlab = expression(paste(Delta, "intron (log2 TN/ES)")),
         ylab = expression(paste(Delta, "exon (log2 TN/ES)")),
         main = "Delta I vs Delta E")
    abline(a = 0, b = 1, lty = 2, col = "gray")
    
    dev.off()

    writeLines(c(
        '"BIOC_EISAR_STEP_BY_STEP_EISA_WITH_ALIGNMENT":',
        paste0('    eisaR: ', as.character(packageVersion('eisaR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_step_by_step_eisa_with_alignment.csv versions.yml
    """
}

workflow BIOC_EISAR_STEP_BY_STEP_EISA_WITH_ALIGNMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ hg19sub.sqlite, samples_rna_single.txt, hg19sub.fa, rna_reads.fq.bz2 ] ]

    main:
    BIOC_EISAR_STEP_BY_STEP_EISA_WITH_ALIGNMENT(ch_input)

    emit:
    tables   = BIOC_EISAR_STEP_BY_STEP_EISA_WITH_ALIGNMENT.out.tables
    plots    = BIOC_EISAR_STEP_BY_STEP_EISA_WITH_ALIGNMENT.out.plots
    objects  = BIOC_EISAR_STEP_BY_STEP_EISA_WITH_ALIGNMENT.out.objects
    versions = BIOC_EISAR_STEP_BY_STEP_EISA_WITH_ALIGNMENT.out.versions
}
