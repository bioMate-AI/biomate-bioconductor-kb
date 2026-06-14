#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: tweeDEseq — standard_differential_expression
// Perform differential expression analysis between two groups using the score-based tweeDE test.
// Input: countsNigerian, genderNigerian
// Container: quay.io/biocontainers/bioconductor-tweedeseq:1.56.0--r45ha27e39d_0
// R packages: tweeDEseq, xtable
// Bioconductor: 3.20 | R: 4.4
// Requires: tweeDEseq
// Visualizations: MA plot
// QC: count normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Normalize raw counts using normalizeCounts
//  * 2. [Core Analysis] Filter out low-expression genes using filterCounts
//  * 3. [Core Analysis] Test for differential expression using tweeDE
//  * 4. [Core Analysis] Extract and annotate differentially expressed genes using print and merge
//  * 5. [Visualization & Output] Visualize results using MAplot and Vplot

nextflow.enable.dsl = 2

process BIOC_TWEEDESEQ_STANDARD_DIFFERENTIAL_EXPRESSION {
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
    .bm_deps <- c("tweeDEseq", "xtable")
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
        library(tweeDEseq)
        
        # ==========================================
        # 1. READ USER INPUT FILES
        # ==========================================
        
        # Read countsNigerian
        if (file.exists("countsNigerian.rds")) {
          countsNigerian <- readRDS("countsNigerian.rds")
        } else if (file.exists("countsNigerian.csv")) {
          countsNigerian <- as.matrix(read.csv("countsNigerian.csv", row.names = 1, check.names = FALSE))
        } else if (file.exists("countsNigerian.tsv")) {
          countsNigerian <- as.matrix(read.delim("countsNigerian.tsv", row.names = 1, check.names = FALSE))
        } else if (file.exists("countsNigerian.txt")) {
          countsNigerian <- as.matrix(read.table("countsNigerian.txt", header = TRUE, row.names = 1, check.names = FALSE))
        } else {
          stop("countsNigerian file not found in working directory (expected .rds, .csv, .tsv, or .txt)")
        }
        
        # Read genderNigerian
        if (file.exists("genderNigerian.rds")) {
          genderNigerian <- readRDS("genderNigerian.rds")
        } else if (file.exists("genderNigerian.csv")) {
          genderNigerian <- read.csv("genderNigerian.csv", header = FALSE)[, 1]
        } else if (file.exists("genderNigerian.tsv")) {
          genderNigerian <- read.delim("genderNigerian.tsv", header = FALSE)[, 1]
        } else if (file.exists("genderNigerian.txt")) {
          genderNigerian <- read.table("genderNigerian.txt", header = FALSE)[, 1]
        } else {
          stop("genderNigerian file not found in working directory (expected .rds, .csv, .tsv, or .txt)")
        }
        
        # Ensure genderNigerian is a factor matching the columns of countsNigerian
        genderNigerian <- as.factor(genderNigerian)
        
        # ==========================================
        # 2. CONSTRUCT ANNOTATION PLACEHOLDER
        # ==========================================
        # Construct a mock annotEnsembl63 data frame to avoid using forbidden data() calls
        genes <- rownames(countsNigerian)
        annotEnsembl63 <- data.frame(
          Symbol = genes,
          Chr = rep("unknown", length(genes)),
          Start = rep(0, length(genes)),
          End = rep(0, length(genes)),
          EntrezID = rep(NA, length(genes)),
          Description = rep("unknown", length(genes)),
          Length = rep(NA, length(genes)),
          GCcontent = rep(NA, length(genes)),
          row.names = genes,
          stringsAsFactors = FALSE
        )
        
        # ==========================================
        # 3. RUN WORKFLOW
        # ==========================================
        
        # Normalize raw counts
        countsNigerianNorm <- normalizeCounts(countsNigerian, genderNigerian)
        
        # Filter out low-expression genes
        countsNigerianNorm <- filterCounts(countsNigerianNorm)
        
        # Save normalized counts
        write.csv(countsNigerianNorm, "counts_nigerian_normalized.csv")
        
        # Test for differential expression using tweeDE
        resPT <- tweeDE(countsNigerianNorm, group = genderNigerian)
        
        # Print results to console
        print(resPT)
        
        # Extract differentially expressed genes
        deGenes <- print(resPT, n=Inf, log2fc=log2(1.5), pval.adjust=0.05, print=FALSE)
        
        # Merge with annotation and save to file
        deGenesAnnotated <- merge(deGenes, annotEnsembl63, by="row.names", sort=FALSE)
        write.csv(deGenesAnnotated, "de_genes_annotated.csv", row.names = FALSE)
        
        # Overwrite deGenes with rownames as in the documented code
        deGenes <- rownames(print(resPT, n=Inf, log2fc=log2(1.5), pval.adjust=0.05, print=FALSE))
        
        # Save the raw tweeDE results object
        saveRDS(resPT, "tweeDE_results.rds")
        
        # ==========================================
        # 4. VISUALIZATION
        # ==========================================
        
        # Define highlight list (hl) using empty vectors for msYgenes and XiEgenes to avoid data() calls
        msYgenes <- character(0)
        XiEgenes <- character(0)
        hl <- list(
          list(genes=msYgenes, pch=21, col="blue", bg="blue", cex=0.7),
          list(genes=XiEgenes, pch=21, col="skyblue", bg="skyblue", cex=0.7),
          list(genes=deGenes, pch=1, col="red", lwd=2, cex=1.5)
        )
        
        # Generate and save plots
        pdf("differential_expression_plots.pdf", width = 12, height = 6)
        par(mfrow=c(1,2), mar=c(4, 5, 3, 2))
        MAplot(resPT, cex=0.7, log2fc.cutoff=log2(1.5), highlight=hl, main="MA-plot")
        Vplot(resPT, cex=0.7, highlight=hl, log2fc.cutoff=log2(1.5), pval.adjust.cutoff=0.05, main="Volcano plot")
        dev.off()

    writeLines(c(
        '"BIOC_TWEEDESEQ_STANDARD_DIFFERENTIAL_EXPRESSION":',
        paste0('    tweeDEseq: ', as.character(packageVersion('tweeDEseq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_differential_expression.csv versions.yml
    """
}

workflow BIOC_TWEEDESEQ_STANDARD_DIFFERENTIAL_EXPRESSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ countsNigerian, genderNigerian ] ]

    main:
    BIOC_TWEEDESEQ_STANDARD_DIFFERENTIAL_EXPRESSION(ch_input)

    emit:
    tables   = BIOC_TWEEDESEQ_STANDARD_DIFFERENTIAL_EXPRESSION.out.tables
    plots    = BIOC_TWEEDESEQ_STANDARD_DIFFERENTIAL_EXPRESSION.out.plots
    objects  = BIOC_TWEEDESEQ_STANDARD_DIFFERENTIAL_EXPRESSION.out.objects
    versions = BIOC_TWEEDESEQ_STANDARD_DIFFERENTIAL_EXPRESSION.out.versions
}
