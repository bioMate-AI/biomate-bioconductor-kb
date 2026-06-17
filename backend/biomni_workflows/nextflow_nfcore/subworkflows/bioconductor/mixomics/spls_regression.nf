#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mixOmics — spls_regression
// Integrate two quantitative datasets to model their covariance and select key variables from both datasets.
// Input: predictor_matrix.csv, response_matrix.csv
// Container: quay.io/biocontainers/bioconductor-mixomics:6.34.0--r45h575d39b_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, mixOmics
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Tune the number of components using the Q2 criterion via pls and perf
//  * 2. [Core Analysis] Tune the number of variables to select in X and Y using tune.spls
//  * 3. [Core Analysis] Run final sparse PLS using spls
//  * 4. [Core Analysis] Extract selected variables and VIP scores using selectVar and vip
//  * 5. [Core Analysis] Evaluate model performance using perf
//  * 6. [Visualization & Output] Visualize sample projections, arrows, and variable correlations using plotIndiv, plotArrow, plotVar, network, and cim

nextflow.enable.dsl = 2

process BIOC_MIXOMICS_SPLS_REGRESSION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20-slim"

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
    .bm_deps <- c("mixOmics", "BiocParallel")
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
    
    library(mixOmics)
    library(BiocParallel)
    
    # Read user input files
    X_df <- read.csv("predictor_matrix.csv", row.names = 1, header = TRUE)
    Y_df <- read.csv("response_matrix.csv", row.names = 1, header = TRUE)
    
    X <- as.matrix(X_df)
    Y <- as.matrix(Y_df)
    
    # Align rows to ensure matching samples
    common_samples <- intersect(rownames(X), rownames(Y))
    if (length(common_samples) == 0) {
      stop("Error: No matching sample names found between predictor_matrix.csv and response_matrix.csv.")
    }
    X <- X[common_samples, , drop = FALSE]
    Y <- Y[common_samples, , drop = FALSE]
    
    # Print dimensions and head of row names to verify alignment
    print(dim(X))
    print(dim(Y))
    print(head(data.frame(rownames(X), rownames(Y))))
    
    # Generate dummy treatment groups to match the liver.toxicity metadata structure for plotting
    set.seed(33)
    treatment_Time_Group <- factor(sample(c('18', '24', '48', '6'), nrow(X), replace = TRUE))
    treatment_Dose_Group <- factor(sample(c('50', '150', '1500', '2000'), nrow(X), replace = TRUE))
    gene_ID <- data.frame(geneBank = colnames(X), stringsAsFactors = FALSE)
    rownames(gene_ID) <- colnames(X)
    
    # Define robust parameters based on dataset dimensions
    folds_val <- min(10, nrow(X))
    if (folds_val < 2) {
      folds_val <- 2
    }
    
    list.keepX <- c(5:10, seq(15, 50, 5))
    list.keepX <- list.keepX[list.keepX < ncol(X)]
    if (length(list.keepX) == 0) {
      list.keepX <- seq(2, max(2, min(10, ncol(X) - 1)), 1)
    }
    
    list.keepY <- c(3:10)
    list.keepY <- list.keepY[list.keepY < ncol(Y)]
    if (length(list.keepY) == 0) {
      list.keepY <- seq(2, max(2, min(5, ncol(Y) - 1)), 1)
    }
    
    # Open PDF device to save all plots
    pdf("spls_regression_plots.pdf", width = 10, height = 8)
    
    # ==========================================
    # STAGE 1: sPLS1 Regression (Single Response)
    # ==========================================
    
    # Select single response variable (use "ALB.g.dL." if present, otherwise default to first column)
    y <- if("ALB.g.dL." %in% colnames(Y)) Y[, "ALB.g.dL."] else Y[, 1]
    
    # 1. Tune the number of components using the Q2 criterion via pls and perf
    tune.pls1.liver <- pls(X = X, Y = y, ncomp = min(4, ncol(X), nrow(X) - 2), mode = 'regression')
    set.seed(33)
    Q2.pls1.liver <- perf(tune.pls1.liver, validation = 'Mfold', 
                          folds = folds_val, nrepeat = 5)
    plot(Q2.pls1.liver, criterion = 'Q2')
    
    # 2. Tune the number of variables to select in X using tune.spls
    set.seed(33)
    tune.spls1.MAE <- tune.spls(X, y, ncomp = min(2, tune.pls1.liver\$ncomp), 
                                test.keepX = list.keepX, 
                                validation = 'Mfold', 
                                folds = folds_val,
                                nrepeat = 5, 
                                progressBar = FALSE, 
                                measure = 'MAE')
    plot(tune.spls1.MAE)
    
    choice.ncomp <- tune.spls1.MAE\$choice.ncomp\$ncomp
    if (is.null(choice.ncomp) || is.na(choice.ncomp) || choice.ncomp == 0) {
      choice.ncomp <- 1
    }
    choice.keepX <- tune.spls1.MAE\$choice.keepX[1:choice.ncomp]
    if (any(is.na(choice.keepX)) || is.null(choice.keepX)) {
      choice.keepX <- list.keepX[1]
    }
    
    # 3. Run final sparse PLS using spls
    spls1.liver <- spls(X, y, ncomp = choice.ncomp, keepX = choice.keepX, 
                        mode = "regression")
    
    cat("sPLS1 Expl Var X:\n")
    print(spls1.liver\$prop_expl_var\$X)
    cat("PLS1 Expl Var X:\n")
    print(tune.pls1.liver\$prop_expl_var\$X)
    
    # 2-component model for visualization
    spls1.liver.c2 <- spls(X, y, ncomp = 2, keepX = c(rep(choice.keepX[1], 2)), 
                       mode = "regression")
    
    # 6. Visualize sample projections
    plotIndiv(spls1.liver.c2,
              group = treatment_Time_Group,
              pch = as.factor(treatment_Dose_Group),
              legend = TRUE, legend.title = 'Time', legend.title.pch = 'Dose')
    
    time.liver <- factor(treatment_Time_Group, 
                         levels = c('18', '24', '48', '6'))
    dose.liver <- factor(treatment_Dose_Group, 
                         levels = c('50', '150', '1500', '2000'))
    col.liver <- color.mixo(time.liver)
    pch.liver <- as.numeric(dose.liver)
    
    plot(spls1.liver.c2\$variates\$X[,1], spls1.liver.c2\$variates\$Y[,1],
         xlab = 'X component', ylab = 'y component / scaled y',
         col = col.liver, pch = pch.liver)
    legend('topleft', col = color.mixo(1:4), legend = levels(time.liver),
           lty = 1, title = 'Time')
    legend('bottomright', legend = levels(dose.liver), pch = 1:4,
           title = 'Dose')
    
    cat("Correlation between X and Y variates (sPLS1):\n")
    print(cor(spls1.liver.c2\$variates\$X, spls1.liver.c2\$variates\$Y))
    
    # Performance comparison
    set.seed(33)
    pls1.liver <- pls(X, y, ncomp = choice.ncomp, mode = "regression")
    perf.pls1.liver <- perf(pls1.liver, validation = "Mfold", folds = folds_val, 
                       nrepeat = 5, progressBar = FALSE)
    cat("PLS1 MSEP Summary:\n")
    print(perf.pls1.liver\$measures\$MSEP\$summary)
    
    perf.spls1.liver <- perf(spls1.liver, validation = "Mfold", folds = folds_val, 
                       nrepeat = 5, progressBar = FALSE)
    cat("sPLS1 MSEP Summary:\n")
    print(perf.spls1.liver\$measures\$MSEP\$summary)
    
    
    # ==========================================
    # STAGE 2: sPLS2 Regression (Multiple Response)
    # ==========================================
    
    # 1. Tune the number of components using the Q2 criterion via pls and perf
    tune.pls2.liver <- pls(X = X, Y = Y, ncomp = min(5, ncol(X), ncol(Y), nrow(X) - 2), mode = 'regression')
    set.seed(33)
    Q2.pls2.liver <- perf(tune.pls2.liver, validation = 'Mfold', folds = folds_val, 
                          nrepeat = 5)
    plot(Q2.pls2.liver, criterion = 'Q2.total')
    
    # 2. Tune the number of variables to select in X and Y using tune.spls
    set.seed(33)
    tune.spls.liver <- tune.spls(X, Y, test.keepX = list.keepX, 
                                 test.keepY = list.keepY, ncomp = 2, 
                                 nrepeat = 1, folds = folds_val, mode = 'regression', 
                                 measure = 'cor', 
                                 BPPARAM = BiocParallel::SnowParam(workers = 2)
                                )
    plot(tune.spls.liver)
    
    choice.keepX <- tune.spls.liver\$choice.keepX
    choice.keepY <- tune.spls.liver\$choice.keepY
    if (is.null(choice.keepX)) choice.keepX <- list.keepX[1:2]
    if (is.null(choice.keepY)) choice.keepY <- list.keepY[1:2]
    choice.ncomp <- length(choice.keepX)
    
    # 3. Run final sparse PLS using spls
    spls2.liver <- spls(X, Y, ncomp = choice.ncomp, 
                       keepX = choice.keepX,
                       keepY = choice.keepY,
                       mode = "regression")
    
    cat("sPLS2 Expl Var:\n")
    print(spls2.liver\$prop_expl_var)
    
    # 4. Extract selected variables and VIP scores using selectVar and vip
    vip.spls2.liver <- vip(spls2.liver)
    selected_X_comp1 <- selectVar(spls2.liver, comp = 1)\$X\$name
    cat("VIP scores for selected X variables on Comp 1:\n")
    print(head(vip.spls2.liver[selected_X_comp1, 1, drop = FALSE]))
    
    # 5. Evaluate model performance using perf
    perf.spls2.liver <- perf(spls2.liver, validation = 'Mfold', folds = folds_val, nrepeat = 5)
    stab.spls2.liver.comp1 <- perf.spls2.liver\$features\$stability.X\$comp1
    cat("Stability of top selected X variables on Comp 1:\n")
    print(head(stab.spls2.liver.comp1[1:choice.keepX[1]]))
    
    extr.stab.spls2.liver.comp1 <- stab.spls2.liver.comp1[selected_X_comp1]
    
    # 6. Visualize sample projections, arrows, and variable correlations
    plotIndiv(spls2.liver, ind.names = FALSE, 
              group = treatment_Time_Group, 
              pch = as.factor(treatment_Dose_Group), 
              col.per.group = color.mixo(1:4),
              legend = TRUE, legend.title = 'Time', 
              legend.title.pch = 'Dose')
    
    plotArrow(spls2.liver, ind.names = FALSE, 
              group = treatment_Time_Group,
              col.per.group = color.mixo(1:4),
              legend.title = 'Time.Group')
    
    plotVar(spls2.liver, cex = c(3,4), var.names = c(FALSE, TRUE))
    
    plotVar(spls2.liver,
            var.names = list(X.label = gene_ID[,'geneBank'],
            Y.label = TRUE), cex = c(3,4))
    
    color.edge <- color.GreenRed(50)
    network(spls2.liver, comp = 1:2,
            cutoff = 0.7,
            shape.node = c("rectangle", "circle"),
            color.node = c("cyan", "pink"),
            color.edge = color.edge,
            )
    
    cim(spls2.liver, comp = 1:2, xlab = "clinic", ylab = "genes",
        )
    
    # Performance comparison PLS vs sPLS
    pls.liver <- pls(X, Y, mode = 'regression', ncomp = 2)
    perf.pls.liver <-  perf(pls.liver, validation = 'Mfold', folds = folds_val, 
                            nrepeat = 5)
    perf.spls.liver <-  perf(spls2.liver, validation = 'Mfold', folds = folds_val, 
                             nrepeat = 5)
    
    plot(c(1,2), perf.pls.liver\$measures\$cor.upred\$summary\$mean, 
         col = 'blue', pch = 16, 
         ylim = c(0.6,1), xaxt = 'n',
         xlab = 'Component', ylab = 't or u Cor', 
         main = 's/PLS performance based on Correlation')
    axis(1, 1:2)  # X-axis label
    points(perf.pls.liver\$measures\$cor.tpred\$summary\$mean, col = 'red', pch = 16)
    points(perf.spls.liver\$measures\$cor.upred\$summary\$mean, col = 'blue', pch = 17)
    points(perf.spls.liver\$measures\$cor.tpred\$summary\$mean, col = 'red', pch = 17)
    legend('bottomleft', col = c('blue', 'red', 'blue', 'red'), 
           pch = c(16, 16, 17, 17), c('u PLS', 't PLS', 'u sPLS', 't sPLS'))
    
    dev.off()
    
    # ==========================================
    # STAGE 7: Save Outputs to Files
    # ==========================================
    
    # Save RDS models
    saveRDS(spls1.liver, "spls1_model.rds")
    saveRDS(spls2.liver, "spls2_model.rds")
    
    # Save selected variables
    write.csv(data.frame(Selected_X = selectVar(spls1.liver, comp = 1)\$X\$name), 
              "spls1_selected_variables_comp1.csv", row.names = FALSE)
    
    write.csv(data.frame(Selected_X = selectVar(spls2.liver, comp = 1)\$X\$name), 
              "spls2_selected_variables_comp1.csv", row.names = FALSE)
    
    # Save VIP scores
    write.csv(as.data.frame(vip.spls2.liver), "spls2_vip_scores.csv")
    
    # Save stability
    write.csv(data.frame(Variable = names(extr.stab.spls2.liver.comp1), 
                         Stability = extr.stab.spls2.liver.comp1), 
              "spls2_stability_comp1.csv", row.names = FALSE)
    
    cat("Pipeline completed successfully. Outputs saved to working directory.\n")

    writeLines(c(
        '"BIOC_MIXOMICS_SPLS_REGRESSION":',
        paste0('    mixOmics: ', as.character(packageVersion('mixOmics')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spls_regression.csv versions.yml
    """
}

workflow BIOC_MIXOMICS_SPLS_REGRESSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ predictor_matrix.csv, response_matrix.csv ] ]

    main:
    BIOC_MIXOMICS_SPLS_REGRESSION(ch_input)

    emit:
    tables   = BIOC_MIXOMICS_SPLS_REGRESSION.out.tables
    plots    = BIOC_MIXOMICS_SPLS_REGRESSION.out.plots
    objects  = BIOC_MIXOMICS_SPLS_REGRESSION.out.objects
    versions = BIOC_MIXOMICS_SPLS_REGRESSION.out.versions
}
