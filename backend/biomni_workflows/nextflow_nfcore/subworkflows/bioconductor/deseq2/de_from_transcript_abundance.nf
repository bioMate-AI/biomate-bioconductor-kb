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
    .bm_deps <- c("DESeq2", "readr", "tximport")
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
