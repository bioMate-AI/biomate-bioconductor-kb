#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: a4 — microarray_differential_expression
// Perform unsupervised exploration, filter low-variance genes, detect differential expression using t-test or limma, and visualize results.
// Input: ExpressionSet
// Container: quay.io/biocontainers/bioconductor-a4:1.58.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, a4
// Visualizations: volcano plot, box plot
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Add gene annotation
//  * 2. [Core Analysis] Unsupervised exploration
//  * 3. [Core Analysis] Filter genes based on variance and intensity
//  * 4. [Core Analysis] Detect differential expression
//  * 5. [Visualization & Output] Visualize p-value distribution and estimate proportion of DE genes
//  * 6. [Core Analysis] Extract top genes
//  * 7. [Visualization & Output] Visualize differential expression using volcano, box, and single-gene plots

nextflow.enable.dsl = 2

process BIOC_A4_MICROARRAY_DIFFERENTIAL_EXPRESSION {
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
    .bm_deps <- c("a4", "Biobase", "annot_pkg")
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
    library(a4)
    library(Biobase)
    
    # ==========================================
    # STAGE 0: Read User Input & Setup Metadata
    # ==========================================
    
    # Read the user-provided ExpressionSet object from the working directory
    if (!file.exists("expression_set.rds")) {
      stop("Error: 'expression_set.rds' not found in the working directory.")
    }
    ALL <- readRDS("expression_set.rds")
    
    # Dynamically load the appropriate annotation package if available
    annot_pkg <- paste0(annotation(ALL), ".db")
    if (requireNamespace(annot_pkg, quietly = TRUE)) {
      library(annot_pkg, character.only = TRUE)
    }
    
    # Dynamically identify grouping variables from the user's ExpressionSet
    pdata <- pData(ALL)
    valid_cols <- sapply(pdata, function(x) {
      n_levels <- length(unique(na.omit(x)))
      n_levels >= 2 && n_levels < nrow(pdata)
    })
    
    if (!any(valid_cols)) {
      stop("Error: No suitable grouping variable found in the ExpressionSet.")
    }
    
    # Prefer a binary variable for differential expression
    binary_cols <- sapply(pdata, function(x) length(unique(na.omit(x))) == 2)
    if (any(binary_cols)) {
      group_var <- names(pdata)[binary_cols][1]
    } else {
      group_var <- names(pdata)[valid_cols][1]
      # Subset to the first two levels for two-group comparisons
      levels_to_keep <- unique(na.omit(pdata[[group_var]]))[1:2]
      ALL <- ALL[, pdata[[group_var]] %in% levels_to_keep]
    }
    
    # Ensure the grouping variable is a factor
    ALL[[group_var]] <- factor(ALL[[group_var]])
    
    # Re-evaluate valid columns for secondary grouping after potential subsetting
    pdata_sub <- pData(ALL)
    valid_cols_sub <- sapply(pdata_sub, function(x) {
      n_levels <- length(unique(na.omit(x)))
      n_levels >= 2 && n_levels < nrow(pdata_sub)
    })
    
    if (sum(valid_cols_sub) > 1) {
      col_group_var <- names(pdata_sub)[valid_cols_sub][names(pdata_sub)[valid_cols_sub] != group_var][1]
    } else {
      col_group_var <- group_var
    }
    
    # ==========================================
    # STAGE 1: Add Gene Annotation
    # ==========================================
    
    ALL <- addGeneInfo(ALL)
    bcrAblOrNeg <- ALL
    
    # ==========================================
    # STAGE 2: Unsupervised Exploration
    # ==========================================
    
    pdf("spectral_map.pdf", width = 8, height = 8)
    spectralMap(object = ALL, groups = col_group_var)
    dev.off()
    
    # ==========================================
    # STAGE 3: Filter Low-Variance Genes
    # ==========================================
    
    selBcrAblOrNeg <- filterVarInt(object = bcrAblOrNeg)
    
    # ==========================================
    # STAGE 4: Detect Differential Expression (t-Test)
    # ==========================================
    
    tTestResult <- tTest(selBcrAblOrNeg, group_var)
    saveRDS(tTestResult, "ttest_result.rds")
    
    # ==========================================
    # STAGE 5: Visualize P-Value Distribution & Estimate DE Proportion
    # ==========================================
    
    pdf("pvalue_histogram.pdf", width = 7, height = 6)
    histPvalue(tTestResult[,"p"], addLegend = TRUE)
    dev.off()
    
    propDEgenesRes <- propDEgenes(tTestResult[,"p"])
    write.csv(data.frame(propDEgenes = propDEgenesRes), "prop_de_genes.csv", row.names = FALSE)
    
    # ==========================================
    # STAGE 6: Extract Top Genes (t-Test)
    # ==========================================
    
    tabTTest <- topTable(tTestResult, n = 10)
    write.csv(tabTTest, "top_table_ttest.csv", row.names = TRUE)
    
    pdf("volcano_ttest.pdf", width = 8, height = 8)
    volcanoPlot(tTestResult, topPValues = 5, topLogRatios = 5)
    dev.off()
    
    # ==========================================
    # STAGE 7: Detect Differential Expression (Limma)
    # ==========================================
    
    limmaResult <- limmaTwoLevels(selBcrAblOrNeg, group_var)
    saveRDS(limmaResult, "limma_result.rds")
    
    pdf("volcano_limma.pdf", width = 8, height = 8)
    volcanoPlot(limmaResult)
    dev.off()
    
    tabLimma <- topTable(limmaResult, n = 10, coef = 2)
    write.csv(tabLimma, "top_table_limma.csv", row.names = TRUE)
    
    # Prepare display and hyperlink data for the annotation table
    required_cols <- c("SYMBOL", "logFC", "AveExpr", "P.Value", "adj.P.Val", "GENENAME")
    for (col in required_cols) {
      if (!col %in% colnames(tabLimma)) {
        tabLimma[[col]] <- if (col %in% c("logFC", "AveExpr")) 0 else if (col %in% c("P.Value", "adj.P.Val")) 1 else "Unknown"
      }
    }
    if (!"ENTREZID" %in% colnames(tabLimma)) {
      tabLimma\$ENTREZID <- "0"
    }
    
    tabLimmaSel <- tabLimma[, required_cols]
    tabLimmaSel[, "GENENAME"] <- substr(tabLimmaSel[,"GENENAME"], 1, 38)
    dData <- data.frame(Gene = tabLimmaSel[, 1], tabLimmaSel[,-1], stringsAsFactors = FALSE, row.names = NULL)
    hData <- data.frame(Gene = generateEntrezIdLinks(tabLimma[,"ENTREZID"]))
    
    tabAnnot <- annotationTable(displayData = dData, hrefData = hData)
    saveRDS(tabAnnot, "annotation_table.rds")
    
    # ==========================================
    # STAGE 8: Visualize Specific Genes
    # ==========================================
    
    pdf("plot_1gene.pdf", width = 7, height = 6)
    plot1gene(probesetId = rownames(tTestResult)[1], object = selBcrAblOrNeg, groups = group_var, legendPos = "topright")
    dev.off()
    
    pdf("boxplot_1gene.pdf", width = 7, height = 6)
    boxPlot(probesetId = rownames(tTestResult)[1], object = selBcrAblOrNeg, boxwex = 0.3, groups = group_var, colgroups = col_group_var, legendPos = "topright")
    dev.off()

    writeLines(c(
        '"BIOC_A4_MICROARRAY_DIFFERENTIAL_EXPRESSION":',
        paste0('    a4: ', as.character(packageVersion('a4')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_microarray_differential_expression.csv versions.yml
    """
}

workflow BIOC_A4_MICROARRAY_DIFFERENTIAL_EXPRESSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ExpressionSet ] ]

    main:
    BIOC_A4_MICROARRAY_DIFFERENTIAL_EXPRESSION(ch_input)

    emit:
    tables   = BIOC_A4_MICROARRAY_DIFFERENTIAL_EXPRESSION.out.tables
    plots    = BIOC_A4_MICROARRAY_DIFFERENTIAL_EXPRESSION.out.plots
    objects  = BIOC_A4_MICROARRAY_DIFFERENTIAL_EXPRESSION.out.objects
    versions = BIOC_A4_MICROARRAY_DIFFERENTIAL_EXPRESSION.out.versions
}
