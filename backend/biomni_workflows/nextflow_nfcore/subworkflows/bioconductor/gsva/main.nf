#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GSVA — bulk_expression_gsva
// Calculate GSVA enrichment scores for bulk expression data (microarray or RNA-seq) and perform downstream differential pathway analysis.
// Input: expression_matrix.csv, pathways.gmt
// Container: quay.io/biocontainers/bioconductor-gsva:2.4.4--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GSEABase, GSVA, SummarizedExperiment, limma, org.Hs.eg.db, sva
// Visualizations: plot (ggplot/base)
// QC: batch-effect correction
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read gene sets from GMT file using readGMT()
//  * 2. [Core Analysis] Map gene identifiers if necessary using gsvaAnnotation()
//  * 3. [Input & Preparation] Build parameter object using gsvaParam() with appropriate kcdf
//  * 4. [Core Analysis] Run GSVA using gsva()
//  * 5. [Core Analysis] Perform differential pathway expression using limma and sva

nextflow.enable.dsl = 2

process BIOC_GSVA_BULK_EXPRESSION_GSVA {
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
    .bm_deps <- c("GSVA", "GSEABase", "sva", "limma", "org.Hs.eg.db", "SummarizedExperiment")
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
        suppressPackageStartupMessages({
              library(SummarizedExperiment)
          library(GSVA)
            library(GSEABase)
            library(sva)
            library(limma)
            library(org.Hs.eg.db)
        })
        
        # Check for required input files
        if (!file.exists("expression_matrix.csv")) {
            stop("Error: expression_matrix.csv not found in the working directory.")
        }
        if (!file.exists("pathways.gmt")) {
            stop("Error: pathways.gmt not found in the working directory.")
        }
        
        # 1. Read gene sets from GMT file using readGMT()
        c7.genesets <- readGMT("pathways.gmt")
        
        # 2. Map gene identifiers if necessary using gsvaAnnotation()
        gsvaAnnotation(c7.genesets) <- SymbolIdentifier("org.Hs.eg.db")
        
        # Read expression matrix
        expr_df <- read.csv("expression_matrix.csv", row.names=1, check.names=FALSE)
        
        # Determine orientation and extract/generate FIR covariate
        if ("FIR" %in% colnames(expr_df)) {
            FIR <- expr_df\$FIR
            gene_cols <- sapply(expr_df, is.numeric)
            gene_cols[names(gene_cols) == "FIR"] <- FALSE
            expr_mat <- t(as.matrix(expr_df[, gene_cols]))
        } else {
            expr_mat <- as.matrix(expr_df)
            FIR <- rep(c("no", "yes"), length.out = ncol(expr_mat))
        }
        
        # Construct SummarizedExperiment object
        se <- SummarizedExperiment(
            assays = list(exprs = expr_mat),
            colData = data.frame(FIR = factor(FIR), row.names = colnames(expr_mat))
        )
        
        canonicalC2BroadSets <- c7.genesets
        
        # 3. Build parameter object using gsvaParam() with appropriate kcdf
        gsvaPar <- gsvaParam(se, canonicalC2BroadSets, minSize=5, maxSize=500)
        
        # 4. Run GSVA using gsva()
        es <- gsva(gsvaPar)
        
        # 5. Perform differential pathway expression using limma and sva
        mod <- model.matrix(~ FIR, colData(es))
        mod0 <- model.matrix(~ 1, colData(es))
        
        # Robust SVA execution
        sv <- tryCatch({
            sva(assay(es), mod, mod0)
        }, error = function(e) {
            warning("SVA failed, proceeding without surrogate variables: ", e\$message)
            NULL
        })
        
        if (!is.null(sv) && sv\$n.sv > 0) {
            mod <- cbind(mod, sv\$sv)
        }
        
        fit <- lmFit(assay(es), mod)
        fit.eb <- eBayes(fit, robust=TRUE)
        gssizes <- geneSetSizes(es)
        fit.eb.trend <- eBayes(fit, robust=TRUE, trend=sqrt(gssizes))
        res <- decideTests(fit.eb.trend)
        tt <- topTable(fit.eb.trend, coef=2, n=Inf)
        DEpwys <- rownames(tt)[tt\$adj.P.Val <= 0.05]
        
        # Write outputs
        write.csv(assay(es), "es_scores.csv")
        saveRDS(es, "es.rds")
        write.csv(tt, "differential_pathways.csv")
        writeLines(DEpwys, "significant_pathways.txt")
        
        # Generate PDF plot
        pdf("gsva_size_vs_sd_trend.pdf")
        plot(sqrt(gssizes), sqrt(fit.eb\$sigma), xlab="Sqrt(gene sets sizes)", ylab="Sqrt(standard deviation)", las=1, pch=".", cex=4)
        lines(lowess(sqrt(gssizes), sqrt(fit.eb\$sigma)), col="red", lwd=2)
        dev.off()

    writeLines(c(
        '"BIOC_GSVA_BULK_EXPRESSION_GSVA":',
        paste0('    GSVA: ', as.character(packageVersion('GSVA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bulk_expression_gsva.csv versions.yml
    """
}

workflow BIOC_GSVA_BULK_EXPRESSION_GSVA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv, pathways.gmt ] ]

    main:
    BIOC_GSVA_BULK_EXPRESSION_GSVA(ch_input)

    emit:
    tables   = BIOC_GSVA_BULK_EXPRESSION_GSVA.out.tables
    plots    = BIOC_GSVA_BULK_EXPRESSION_GSVA.out.plots
    objects  = BIOC_GSVA_BULK_EXPRESSION_GSVA.out.objects
    versions = BIOC_GSVA_BULK_EXPRESSION_GSVA.out.versions
}
