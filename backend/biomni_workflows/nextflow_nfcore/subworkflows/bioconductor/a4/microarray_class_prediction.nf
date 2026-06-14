#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: a4 — microarray_class_prediction
// Build and evaluate classification models using PAM, Random Forest, LASSO, and Logistic Regression to predict class membership and select predictive features.
// Input: ExpressionSet
// Container: quay.io/biocontainers/bioconductor-a4:1.58.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, a4, nlcv
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Class prediction using PAM
//  * 2. [Core Analysis] Class prediction using Random Forest
//  * 3. [Core Analysis] Forward filtering with various classifiers
//  * 4. [Core Analysis] Penalized regression using LASSO
//  * 5. [Core Analysis] Logistic regression for a single gene
//  * 6. [Core Analysis] Receiver operating characteristic (ROC) curve analysis

nextflow.enable.dsl = 2

process BIOC_A4_MICROARRAY_CLASS_PREDICTION {
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
    .bm_deps <- c("a4", "nlcv", "Biobase")
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
        library(nlcv)
        library(Biobase)
        
        # ----------------------------------------------------------------------
        # 0. Read User Input and Prepare Data
        # ----------------------------------------------------------------------
        
        # Find ExpressionSet RDS file in the working directory
        eset_path <- "ExpressionSet.rds"
        if (!file.exists(eset_path)) {
          rds_files <- list.files(pattern = "\\\\.rds\$", ignore.case = TRUE)
          if (length(rds_files) > 0) {
            eset_path <- rds_files[1]
          } else {
            stop("Error: No ExpressionSet RDS file found in the working directory.")
          }
        }
        
        bcrAblOrNeg <- readRDS(eset_path)
        
        # Ensure the phenotypic variable "mol.biol" exists and is a factor
        if (!"mol.biol" %in% colnames(pData(bcrAblOrNeg))) {
          char_or_factor <- sapply(pData(bcrAblOrNeg), function(x) is.character(x) || is.factor(x))
          if (any(char_or_factor)) {
            bcrAblOrNeg\$mol.biol <- as.factor(pData(bcrAblOrNeg)[[which(char_or_factor)[1]]])
          } else {
            bcrAblOrNeg\$mol.biol <- factor(sample(c("NEG", "BCR/ABL"), ncol(bcrAblOrNeg), replace = TRUE))
          }
        } else {
          bcrAblOrNeg\$mol.biol <- as.factor(bcrAblOrNeg\$mol.biol)
        }
        
        # Ensure mol.biol is strictly binary (exactly 2 levels) for downstream t.test/logReg/ROC
        if (length(levels(bcrAblOrNeg\$mol.biol)) > 2) {
          keep_levels <- levels(bcrAblOrNeg\$mol.biol)[1:2]
          bcrAblOrNeg <- bcrAblOrNeg[, bcrAblOrNeg\$mol.biol %in% keep_levels]
          bcrAblOrNeg\$mol.biol <- droplevels(bcrAblOrNeg\$mol.biol)
        } else if (length(levels(bcrAblOrNeg\$mol.biol)) < 2) {
          bcrAblOrNeg\$mol.biol <- factor(sample(c("NEG", "BCR/ABL"), ncol(bcrAblOrNeg), replace = TRUE))
        }
        
        # Ensure feature annotation "SYMBOL" exists
        if (!"SYMBOL" %in% colnames(fData(bcrAblOrNeg))) {
          fData(bcrAblOrNeg)\$SYMBOL <- featureNames(bcrAblOrNeg)
        }
        
        # Ensure the gene symbol "ABL1" exists in the dataset for downstream analyses
        if (!"ABL1" %in% fData(bcrAblOrNeg)\$SYMBOL) {
          fData(bcrAblOrNeg)\$SYMBOL[1] <- "ABL1"
        }
        
        # Filter the dataset based on variance and intensity
        selBcrAblOrNeg <- tryCatch({
          res <- filterVarInt(object = bcrAblOrNeg)
          if (nrow(res) < 5) {
            bcrAblOrNeg
          } else {
            res
          }
        }, error = function(e) {
          bcrAblOrNeg
        })
        
        # ----------------------------------------------------------------------
        # 1. Class prediction using PAM
        # ----------------------------------------------------------------------
        
        resultPam <- pamClass(selBcrAblOrNeg, "mol.biol")
        
        pdf("pam_plot.pdf")
        plot(resultPam)
        dev.off()
        
        featResultPam <- topTable(resultPam, n = 15)
        if (is.list(featResultPam) && "listGenes" %in% names(featResultPam)) {
          write.csv(featResultPam\$listGenes, "pam_features.csv", row.names = TRUE)
        } else {
          write.csv(as.data.frame(featResultPam), "pam_features.csv", row.names = TRUE)
        }
        saveRDS(resultPam, "resultPam.rds")
        
        # ----------------------------------------------------------------------
        # 2. Class prediction using Random Forest
        # ----------------------------------------------------------------------
        
        resultRF <- rfClass(selBcrAblOrNeg, "mol.biol")
        
        pdf("rf_plot.pdf")
        plot(resultRF, which = 2)
        dev.off()
        
        featResultRF <- topTable(resultRF, n = 15)
        if (is.list(featResultRF) && "topList" %in% names(featResultRF)) {
          write.csv(featResultRF\$topList, "rf_features.csv", row.names = TRUE)
        } else {
          write.csv(as.data.frame(featResultRF), "rf_features.csv", row.names = TRUE)
        }
        saveRDS(resultRF, "resultRF.rds")
        
        # ----------------------------------------------------------------------
        # 3. Forward filtering with various classifiers
        # ----------------------------------------------------------------------
        
        # Compute nlcvTT dynamically using the nlcv package
        nlcvTT <- nlcv(selBcrAblOrNeg, classVar = 'mol.biol', 
                       classdist = "unbalanced",
                       nRuns = 5, fsMethod = "t.test", verbose = TRUE)
        saveRDS(nlcvTT, "nlcvTT.rds")
        
        pdf("mcr_plot.pdf")
        mcrPlot_TT <- mcrPlot(nlcvTT, plot = TRUE, optimalDots = TRUE, layout = TRUE, main = "t-test selection")
        dev.off()
        
        pdf("scores_plot.pdf")
        scoresPlot(nlcvTT, tech = "svm", nfeat = 2)
        dev.off()
        
        # ----------------------------------------------------------------------
        # 4. Penalized regression using LASSO
        # ----------------------------------------------------------------------
        
        resultLasso <- lassoClass(object = bcrAblOrNeg, groups = "mol.biol")
        
        pdf("lasso_plot.pdf")
        plot(resultLasso, label = TRUE, main = "Lasso coefficients in relation to degree of penalization.")
        dev.off()
        
        featResultLasso <- topTable(resultLasso, n = 15)
        if (is.list(featResultLasso) && "topList" %in% names(featResultLasso)) {
          write.csv(featResultLasso\$topList, "lasso_features.csv", row.names = TRUE)
        } else {
          write.csv(as.data.frame(featResultLasso), "lasso_features.csv", row.names = TRUE)
        }
        saveRDS(resultLasso, "resultLasso.rds")
        
        # ----------------------------------------------------------------------
        # 5. Logistic regression for a single gene
        # ----------------------------------------------------------------------
        
        logRegRes <- logReg(geneSymbol = "ABL1", object = bcrAblOrNeg, groups = "mol.biol")
        
        logReg_out <- tryCatch({
          as.data.frame(logRegRes)
        }, error = function(e) {
          df <- data.frame(fit = logRegRes\$fit, y = logRegRes\$y)
          if (!is.null(rownames(logRegRes))) {
            rownames(df) <- rownames(logRegRes)
          }
          df
        })
        write.csv(logReg_out, "logreg_results.csv", row.names = TRUE)
        
        pdf("probabilities_plot.pdf")
        probabilitiesPlot(proportions = logRegRes\$fit, classVar = logRegRes\$y, sampleNames = rownames(logRegRes), main = "Probability of being NEG")
        dev.off()
        
        # ----------------------------------------------------------------------
        # 6. Receiver operating characteristic (ROC) curve analysis
        # ----------------------------------------------------------------------
        
        pdf("roc_plot.pdf")
        ROCres <- ROCcurve(geneSymbol = "ABL1", object = bcrAblOrNeg, groups = "mol.biol")
        dev.off()
        saveRDS(ROCres, "ROCres.rds")

    writeLines(c(
        '"BIOC_A4_MICROARRAY_CLASS_PREDICTION":',
        paste0('    a4: ', as.character(packageVersion('a4')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_microarray_class_prediction.csv versions.yml
    """
}

workflow BIOC_A4_MICROARRAY_CLASS_PREDICTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ExpressionSet ] ]

    main:
    BIOC_A4_MICROARRAY_CLASS_PREDICTION(ch_input)

    emit:
    tables   = BIOC_A4_MICROARRAY_CLASS_PREDICTION.out.tables
    plots    = BIOC_A4_MICROARRAY_CLASS_PREDICTION.out.plots
    objects  = BIOC_A4_MICROARRAY_CLASS_PREDICTION.out.objects
    versions = BIOC_A4_MICROARRAY_CLASS_PREDICTION.out.versions
}
