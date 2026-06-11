#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DESeq2 — standard_de_from_matrix
// Perform standard differential expression analysis starting from a raw count matrix and sample metadata.
// Input: cts, coldata
// Container: quay.io/biocontainers/bioconductor-deseq2:1.50.2--r45ha27e39d_0
// R packages: airway, BiocParallel, DESeq2, ggplot2, IHW, RColorBrewer
// Bioconductor: 3.20 | R: 4.4
// Requires: DESeq2
// Visualizations: MA plot, gene count plot
// QC: diagnostic MA/PCA QC, low-count filtering
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Construct DESeqDataSet from matrix
//  * 2. [Core Analysis] Pre-filter low count genes
//  * 3. [Core Analysis] Set factor levels and reference group
//  * 4. [Core Analysis] Run DESeq() pipeline
//  * 5. [Core Analysis] Extract results and apply LFC shrinkage
//  * 6. [Visualization & Output] Visualize results (MA-plot, plotCounts)
//  * 7. [Visualization & Output] Export results to CSV

nextflow.enable.dsl = 2

process BIOC_DESEQ2_STANDARD_DE_FROM_MATRIX {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("airway", "BiocParallel", "DESeq2", "ggplot2", "IHW", "RColorBrewer")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
        
        # Load required libraries
        library("DESeq2")
        
        # Helper function to read input files robustly
        read_input_file <- function(base_name) {
          extensions <- c("", ".csv", ".tsv", ".txt")
          for (ext in extensions) {
            full_path <- paste0(base_name, ext)
            if (file.exists(full_path)) {
              # Try reading as CSV first, then fallback to whitespace-separated
              return(
                tryCatch({
                  read.csv(full_path, row.names = 1, check.names = FALSE)
                }, error = function(e) {
                  read.table(full_path, header = TRUE, row.names = 1, check.names = FALSE, sep = "")
                })
              )
            }
          }
          stop(paste("Required input file for", base_name, "not found in the working directory."))
        }
        
        # 1. Read user input files
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        cts_df <- read_input_file("cts")
        cts <- as.matrix(cts_df)
        storage.mode(cts) <- "integer"
        
        coldata <- read_input_file("coldata")
        
        # Ensure sample names match and are in the same order
        common_samples <- intersect(colnames(cts), rownames(coldata))
        if (length(common_samples) == 0) {
          stop("No matching sample names found between cts columns and coldata rows.")
        }
        cts <- cts[, common_samples, drop = FALSE]
        coldata <- coldata[common_samples, , drop = FALSE]
        
        # Ensure the condition column exists
        if (!"condition" %in% colnames(coldata)) {
          stop("The coldata metadata must contain a 'condition' column.")
        }
        
        # 2. Construct DESeqDataSet from matrix
        dds <- DESeqDataSetFromMatrix(countData = cts,
                                      colData = coldata,
                                      design = ~ condition)
        
        # 3. Pre-filter low count genes
        smallestGroupSize <- min(table(dds\$condition))
        keep <- rowSums(counts(dds) >= 10) >= smallestGroupSize
        dds <- dds[keep,]
        
        # 4. Set factor levels and reference group
        dds\$condition <- factor(dds\$condition)
        dds\$condition <- relevel(dds\$condition, ref = levels(dds\$condition)[1])
        
        # 5. Run DESeq() pipeline
        dds <- DESeq(dds)
        
        # 6. Extract results and apply LFC shrinkage
        res <- results(dds)
        resultsNames(dds)
        res_coef <- resultsNames(dds)[length(resultsNames(dds))]
        resLFC <- lfcShrink(dds, coef=res_coef, type="apeglm")
        resOrdered <- res[order(res\$pvalue),]
        
        # Print summary to console
        summary(res)
        
        # 7. Visualize results and save to PDF
        pdf("deseq2_plots.pdf", width = 7, height = 7)
        plotMA(res, ylim=c(-2,2))
        plotMA(resLFC, ylim=c(-2,2))
        # Handle potential NA values in padj when finding the minimum
        valid_padj_idx <- which(!is.na(res\$padj))
        if (length(valid_padj_idx) > 0) {
          best_gene <- valid_padj_idx[which.min(res\$padj[valid_padj_idx])]
          plotCounts(dds, gene=best_gene, intgroup="condition")
        }
        dev.off()
        
        # 8. Export results to CSV and RDS
        write.csv(as.data.frame(resOrdered),
                  file="condition_treated_results.csv")
        
        saveRDS(dds, "dds.rds")
        saveRDS(res, "res.rds")
        saveRDS(resLFC, "resLFC.rds")

    writeLines(c(
        '"BIOC_DESEQ2_STANDARD_DE_FROM_MATRIX":',
        paste0('    DESeq2: ', as.character(packageVersion('DESeq2')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_de_from_matrix.csv versions.yml
    """
}

workflow BIOC_DESEQ2_STANDARD_DE_FROM_MATRIX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ cts, coldata ] ]

    main:
    BIOC_DESEQ2_STANDARD_DE_FROM_MATRIX(ch_input)

    emit:
    tables   = BIOC_DESEQ2_STANDARD_DE_FROM_MATRIX.out.tables
    plots    = BIOC_DESEQ2_STANDARD_DE_FROM_MATRIX.out.plots
    objects  = BIOC_DESEQ2_STANDARD_DE_FROM_MATRIX.out.objects
    versions = BIOC_DESEQ2_STANDARD_DE_FROM_MATRIX.out.versions
}
