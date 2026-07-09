#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DESeq2 — de_from_transcript_abundance
// Import transcript-level quantification files and summarize them to gene-level counts for differential expression analysis.
// Input: quant.sf.gz, samples.txt, tx2gene.gencode.v27.csv
// Container: quay.io/biocontainers/bioconductor-deseq2:1.50.2--r45ha27e39d_0
// R packages: DESeq2, readr, tximport
// Bioconductor: 3.20 | R: 4.4
// Requires: DESeq2, readr, tximport
// Visualizations: MA plot
// QC: diagnostic MA/PCA QC
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read sample metadata
//  * 2. [Core Analysis] Locate quantification files
//  * 3. [Visualization & Output] Import and summarize to gene-level counts using tximport
//  * 4. [Input & Preparation] Construct DESeqDataSet from tximport object

nextflow.enable.dsl = 2

process BIOC_DESEQ2_DE_FROM_TRANSCRIPT_ABUNDANCE {
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
    .bm_deps <- c("DESeq2", "readr", "tximport")
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
        library("tximport")
        library("readr")
        library("DESeq2")
        
        # 1. Read sample metadata
        dir <- "."
        samples <- read.table(file.path(dir, "samples.txt"), header=TRUE)
        
        sample_ids <- as.character(samples[, 1])
        rownames(samples) <- sample_ids
        
        # 2. Locate quantification files
        files <- file.path(dir, "salmon", sample_ids, "quant.sf.gz")
        if (!all(file.exists(files))) {
          files <- file.path(dir, sample_ids, "quant.sf.gz")
        }
        if (!all(file.exists(files))) {
          # Fallback search for any quant.sf.gz files in the directory structure
          all_quants <- list.files(path = dir, pattern = "quant\\\\.sf\\\\.gz\$", recursive = TRUE, full.names = TRUE)
          if (length(all_quants) >= nrow(samples)) {
            matched_files <- sapply(sample_ids, function(r) {
              match <- all_quants[grepl(r, all_quants)]
              if (length(match) > 0) match[1] else ""
            })
            if (all(matched_files != "")) {
              files <- matched_files
            }
          }
        }
        names(files) <- sample_ids
        
        # 3. Import and summarize to gene-level counts using tximport
        tx2gene <- read_csv(file.path(dir, "tx2gene.gencode.v27.csv"))
        txi <- tximport(files, type="salmon", tx2gene=tx2gene)
        
        # 4. Construct DESeqDataSet from tximport object
        ddsTxi <- DESeqDataSetFromTximport(txi,
                                           colData = samples,
                                           design = ~ condition)
        
        # Run standard differential expression analysis pipeline
        dds <- DESeq(ddsTxi)
        
        # Extract and order results
        res <- results(dds)
        resOrdered <- res[order(res\$pvalue), ]
        
        # Save results to CSV
        write.csv(as.data.frame(resOrdered), file="deseq2_results.csv", row.names=TRUE)
        
        # Save dds object to RDS
        saveRDS(dds, file="dds_output.rds")
        
        # Shrink log fold changes dynamically using available estimators
        coef_name <- resultsNames(dds)[2]
        resLFC <- tryCatch({
          lfcShrink(dds, coef=coef_name, type="apeglm")
        }, error = function(e) {
          tryCatch({
            lfcShrink(dds, coef=coef_name, type="ashr")
          }, error = function(e2) {
            lfcShrink(dds, coef=coef_name, type="normal")
          })
        })
        
        # Save shrunken results to CSV
        write.csv(as.data.frame(resLFC), file="deseq2_shrunken_results.csv", row.names=TRUE)
        
        # Generate diagnostic plots and save to PDF
        pdf("deseq2_plots.pdf")
        plotMA(res, ylim=c(-2, 2), main="MA Plot (unshrunken)")
        plotMA(resLFC, ylim=c(-2, 2), main="MA Plot (shrunken)")
        dev.off()
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # diagnostic MA/PCA QC — PC1 variance explained on any large matrix.
    # Pass when PC1 > 10% (Risso 2014 RUV-seq diagnostic).
    .pca_pc1 <- NA_real_; .pca_files <- character(0)
    for (.pca_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .pca_obj <- tryCatch(readRDS(.pca_rds), error = function(e) NULL)
      .pca_mat <- if (is.matrix(.pca_obj) || is.data.frame(.pca_obj)) .pca_obj else NULL
      if (!is.null(.pca_mat) && ncol(.pca_mat) >= 3 && nrow(.pca_mat) >= 100) {
        .pca_m <- suppressWarnings(as.matrix(.pca_mat))
        .pca_kept <- apply(.pca_m, 1, function(r) all(is.finite(r)) && var(r) > 0)
        if (sum(.pca_kept) >= 50) {
          .pca_fit <- tryCatch(prcomp(t(.pca_m[.pca_kept, , drop = FALSE])), error = function(e) NULL)
          if (!is.null(.pca_fit)) {
            .pca_vars <- (.pca_fit\$sdev^2) / sum(.pca_fit\$sdev^2)
            .pca_pc1 <- round(.pca_vars[1] * 100, 2); .pca_files <- c(.pca_files, .pca_rds); break
          }
        }
      }
    }
    .gates_by_label[["diagnostic MA/PCA QC"]] <- list(
      gate_row = "bioc_diagnostic_ma_pca_qc",
      metric_name = "pc1_var_explained",
      metric_value = .pca_pc1,
      passes = isTRUE(is.finite(.pca_pc1) && .pca_pc1 > 10),
      status = if (is.finite(.pca_pc1)) paste0("computed (PC1=", .pca_pc1, "%)")
               else "not_computed (no large numeric matrix .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_DESEQ2_DE_FROM_TRANSCRIPT_ABUNDANCE",
      domain  = "bioconductor",
      declared_qc_steps = c("diagnostic MA/PCA QC"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_DESEQ2_DE_FROM_TRANSCRIPT_ABUNDANCE":',
        paste0('    DESeq2: ', as.character(packageVersion('DESeq2')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_de_from_transcript_abundance.csv versions.yml
    """
}

workflow BIOC_DESEQ2_DE_FROM_TRANSCRIPT_ABUNDANCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ quant.sf.gz, samples.txt, tx2gene.gencode.v27.csv ] ]

    main:
    BIOC_DESEQ2_DE_FROM_TRANSCRIPT_ABUNDANCE(ch_input)

    emit:
    tables   = BIOC_DESEQ2_DE_FROM_TRANSCRIPT_ABUNDANCE.out.tables
    plots    = BIOC_DESEQ2_DE_FROM_TRANSCRIPT_ABUNDANCE.out.plots
    objects  = BIOC_DESEQ2_DE_FROM_TRANSCRIPT_ABUNDANCE.out.objects
    versions = BIOC_DESEQ2_DE_FROM_TRANSCRIPT_ABUNDANCE.out.versions
}
