#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PROMISE — promise_analysis_without_gsea
// Identify individual genomic features associated with multiple phenotypic endpoints according to a predefined pattern without performing gene set enrichment anal
// Input: expression_data.csv, phenotype_data.csv, pattern_definition.csv
// Container: quay.io/biocontainers/bioconductor-promise:1.62.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, GSEABase, PROMISE
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the PROMISE package and construct the ExpressionSet from expression and phenotype data
//  * 2. [Input & Preparation] Define the association pattern data frame mapping endpoints to statistical functions and coefficients
//  * 3. [Core Analysis] Run the PROMISE function with geneSet=NULL
//  * 4. [Core Analysis] Extract and inspect the gene-level association statistics and permutation p-values

nextflow.enable.dsl = 2

process BIOC_PROMISE_PROMISE_ANALYSIS_WITHOUT_GSEA {
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
    .bm_deps <- c("PROMISE", "Biobase", "GSEABase")
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
        library(PROMISE)
        library(Biobase)
        library(GSEABase)
        
        # 1. Read User Inputs
        # Read expression data
        expr_df <- read.csv("expression_data.csv", row.names = 1, check.names = FALSE)
        expr_mat <- as.matrix(expr_df)
        
        # Read phenotype data
        pheno_df <- read.csv("phenotype_data.csv", row.names = 1, check.names = FALSE)
        
        # Align samples between expression and phenotype data
        common_samples <- intersect(colnames(expr_mat), rownames(pheno_df))
        if (length(common_samples) == 0) {
          stop("Error: No common samples found between expression_data.csv and phenotype_data.csv")
        }
        expr_mat <- expr_mat[, common_samples, drop = FALSE]
        pheno_df <- pheno_df[common_samples, , drop = FALSE]
        
        # Create ExpressionSet
        metadata <- data.frame(labelDescription = colnames(pheno_df), row.names = colnames(pheno_df))
        pheno_data <- new("AnnotatedDataFrame", data = pheno_df, varMetadata = metadata)
        sampExprSet <- ExpressionSet(assayData = expr_mat, phenoData = pheno_data)
        
        # Read pattern definition
        phPatt <- read.csv("pattern_definition.csv", row.names = 1, stringsAsFactors = FALSE)
        phPatt\$stat.coef <- as.numeric(phPatt\$stat.coef)
        phPatt\$stat.func <- as.character(phPatt\$stat.func)
        phPatt\$endpt.vars <- as.character(phPatt\$endpt.vars)
        
        # 2. Run PROMISE Analysis
        test2 <- PROMISE(exprSet=sampExprSet,
                         geneSet=NULL, 
                         promise.pattern=phPatt, 
                         strat.var=NULL,
                         proj0=FALSE,
                         nbperm=FALSE,
                         max.ntail=10,
                         seed=13, 
                         nperms=100)
        
        # 3. Extract and Inspect Results
        gene.res2 <- test2\$generes
        head(gene.res2)
        
        set.res2 <- test2\$setres
        head(set.res2)
        
        # 4. Write Outputs
        write.csv(gene.res2, "gene_results.csv", row.names = FALSE)
        if (!is.null(set.res2)) {
          write.csv(set.res2, "geneset_results.csv", row.names = FALSE)
        }
        saveRDS(test2, "promise_results.rds")
        
        # Generate diagnostic plots
        pdf("promise_results_plots.pdf", width = 10, height = 5)
        par(mfrow = c(1, 2))
        if (!is.null(gene.res2) && "PROMISE.perm.p" %in% colnames(gene.res2)) {
          hist(gene.res2\$PROMISE.perm.p, 
               main = "Gene-level PROMISE P-values", 
               xlab = "P-value", 
               col = "lightblue", 
               breaks = 20)
        }
        if (!is.null(set.res2) && "PROMISE.perm.p" %in% colnames(set.res2)) {
          hist(set.res2\$PROMISE.perm.p, 
               main = "Gene Set PROMISE P-values", 
               xlab = "P-value", 
               col = "lightgreen", 
               breaks = 20)
        }
        dev.off()

    writeLines(c(
        '"BIOC_PROMISE_PROMISE_ANALYSIS_WITHOUT_GSEA":',
        paste0('    PROMISE: ', as.character(packageVersion('PROMISE')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_promise_analysis_without_gsea.csv versions.yml
    """
}

workflow BIOC_PROMISE_PROMISE_ANALYSIS_WITHOUT_GSEA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_data.csv, phenotype_data.csv, pattern_definition.csv ] ]

    main:
    BIOC_PROMISE_PROMISE_ANALYSIS_WITHOUT_GSEA(ch_input)

    emit:
    tables   = BIOC_PROMISE_PROMISE_ANALYSIS_WITHOUT_GSEA.out.tables
    plots    = BIOC_PROMISE_PROMISE_ANALYSIS_WITHOUT_GSEA.out.plots
    objects  = BIOC_PROMISE_PROMISE_ANALYSIS_WITHOUT_GSEA.out.objects
    versions = BIOC_PROMISE_PROMISE_ANALYSIS_WITHOUT_GSEA.out.versions
}
