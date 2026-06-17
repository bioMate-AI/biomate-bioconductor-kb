#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: limpca — asca_apca_analysis
// Perform GLM-based ASCA, APCA, or ASCA-E analysis on high-dimensional designed data to decompose and visualize multivariate experimental effects.
// Input: outcomes.tsv, design.tsv
// Container: quay.io/biocontainers/bioconductor-limpca:1.6.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, car, ggplot2, gridExtra, limpca, pander
// Visualizations: PCA plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Format data into an lmpDataList using data2LmpDataList
//  * 2. [Visualization & Output] Explore raw data using plotDesign, plotLine, plotScatter, plotScatterM, and plotMeans
//  * 3. [Core Analysis] Perform exploratory PCA using pcaBySvd, pcaScreePlot, and pcaScorePlot
//  * 4. [Core Analysis] Generate the GLM model matrix using lmpModelMatrix
//  * 5. [Core Analysis] Estimate the model and decompose outcomes into effect matrices using lmpEffectMatrices
//  * 6. [Core Analysis] Test effect significance using parametric bootstrap via lmpBootstrapTests
//  * 7. [Core Analysis] Perform PCA decomposition of effect matrices using lmpPcaEffects
//  * 8. [Visualization & Output] Calculate and plot contributions using lmpContributions
//  * 9. [Visualization & Output] Visualize scores, loadings, and interaction effects using lmpScorePlot, lmpLoading1dPlot, lmpLoading2dPlot, lmpScoreScatterPlotM, 

nextflow.enable.dsl = 2

process BIOC_LIMPCA_ASCA_APCA_ANALYSIS {
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
    .bm_deps <- c("limpca", "ggplot2", "gridExtra", "pander", "car", "SummarizedExperiment")
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
        library(SummarizedExperiment)
        library(limpca)
        library(ggplot2)
        library(gridExtra)
        library(pander)
        library(car)
        
        # 1. Data import / formatting from user input files
        outcomes_mat <- as.matrix(read.delim("outcomes.tsv", row.names = 1, check.names = FALSE))
        design_df <- read.delim("design.tsv", row.names = 1, check.names = FALSE)
        
        # Ensure design columns are factors
        for (col in colnames(design_df)) {
          design_df[[col]] <- as.factor(design_df[[col]])
        }
        
        # Determine formula based on design columns (defaulting to UCH formula if columns match)
        cols <- colnames(design_df)[1:min(3, ncol(design_df))]
        if (all(c("Hippurate", "Citrate", "Time") %in% colnames(design_df))) {
          formula_str <- "outcomes ~ Hippurate + Citrate + Time + Hippurate:Citrate + Time:Hippurate + Time:Citrate + Hippurate:Citrate:Time"
          cols <- c("Hippurate", "Citrate", "Time")
        } else {
          if (length(cols) == 3) {
            formula_str <- paste0("outcomes ~ ", cols[1], " + ", cols[2], " + ", cols[3], " + ",
                                  cols[1], ":", cols[2], " + ", cols[1], ":", cols[3], " + ",
                                  cols[2], ":", cols[3], " + ", cols[1], ":", cols[2], ":", cols[3])
          } else if (length(cols) == 2) {
            formula_str <- paste0("outcomes ~ ", cols[1], " + ", cols[2], " + ", cols[1], ":", cols[2])
          } else {
            formula_str <- paste0("outcomes ~ ", cols[1])
          }
        }
        
        # Extract dynamic factor names for plotting
        fac1 <- cols[1]
        fac2 <- if (length(cols) >= 2) cols[2] else cols[1]
        fac3 <- if (length(cols) >= 3) cols[3] else cols[1]
        
        # Construct the UCH-like list object
        UCH <- list(
          outcomes = outcomes_mat,
          design = design_df,
          formula = formula_str
        )
        
        # Format data into lmpDataList
        UCH2 <- data2LmpDataList(outcomes = UCH\$outcomes, design = UCH\$design, formula = UCH\$formula)
        
        # Format from SummarizedExperiment
        se <- SummarizedExperiment(
          assays = list(counts = t(UCH\$outcomes)),
          colData = UCH\$design,
          metadata = list(formula = UCH\$formula)
        )
        UCH3 <- data2LmpDataList(se, assay_name = "counts")
        
        
        # 2. Data exploration
        pdf("data_exploration_plots.pdf", width = 8, height = 6)
        
        tryCatch({
          if (length(cols) >= 3) {
            print(plotDesign(design = UCH2\$design, x = cols[1], y = cols[2], rows = cols[3], title = "Design of the dataset"))
          } else if (length(cols) == 2) {
            print(plotDesign(design = UCH2\$design, x = cols[1], y = cols[2], title = "Design of the dataset"))
          } else {
            print(plotDesign(design = UCH2\$design, x = cols[1], title = "Design of the dataset"))
          }
        }, error = function(e) {
          warning("plotDesign failed: ", e\$message)
        })
        
        tryCatch({
          p1 <- plotLine(Y = UCH2\$outcomes, title = "Outcomes line plot", rows = c(1), xlab = "Variables", ylab = "Intensity")
          print(p1)
        }, error = function(e) {
          warning("plotLine failed: ", e\$message)
        })
        
        tryCatch({
          xy_cols <- if(ncol(UCH2\$outcomes) >= 2) c(1, 2) else c(1, 1)
          print(plotScatter(Y = UCH2\$outcomes, xy = xy_cols, design = UCH2\$design, color = fac1, shape = fac2))
        }, error = function(e) {
          warning("plotScatter failed: ", e\$message)
        })
        
        tryCatch({
          scatterM_cols <- 1:min(5, ncol(UCH2\$outcomes))
          print(plotScatterM(Y = UCH2\$outcomes, cols = scatterM_cols, design = UCH2\$design, varname.colorup = fac1, varname.colordown = fac2))
        }, error = function(e) {
          warning("plotScatterM failed: ", e\$message)
        })
        
        tryCatch({
          if (length(cols) >= 3) {
            pm <- plotMeans(Y = UCH2\$outcomes, design = UCH2\$design, cols = c(1), x = cols[2], w = cols[1], z = cols[3], ylab = "Intensity", title = c("Mean response"))
          } else if (length(cols) == 2) {
            pm <- plotMeans(Y = UCH2\$outcomes, design = UCH2\$design, cols = c(1), x = cols[2], w = cols[1], ylab = "Intensity", title = c("Mean response"))
          } else {
            pm <- plotMeans(Y = UCH2\$outcomes, design = UCH2\$design, cols = c(1), x = cols[1], ylab = "Intensity", title = c("Mean response"))
          }
          for (p in pm) print(p)
        }, error = function(e) {
          warning("plotMeans failed: ", e\$message)
        })
        
        dev.off()
        
        
        # 3. PCA
        pdf("pca_plots.pdf", width = 8, height = 6)
        
        ResPCA <- pcaBySvd(UCH2\$outcomes)
        print(pcaScreePlot(ResPCA, nPC = min(6, length(ResPCA\$singvar))))
        
        tryCatch({
          print(pcaScorePlot(resPcaBySvd = ResPCA, axes = c(1, 2), title = "PCA scores plot: PC1 and PC2", design = UCH2\$design, color = fac1, shape = fac2, points_labs_rn = FALSE))
        }, error = function(e) {
          warning("pcaScorePlot failed: ", e\$message)
        })
        
        tryCatch({
          p2 <- pcaLoading1dPlot(resPcaBySvd = ResPCA, axes = c(1, 2), title = "PCA loadings plot", xlab = "Variables", ylab = "Intensity")
          print(p2)
        }, error = function(e) {
          warning("pcaLoading1dPlot failed: ", e\$message)
        })
        
        dev.off()
        
        
        # 4. Model estimation and effect matrix decomposition
        resLmpModelMatrix <- lmpModelMatrix(UCH2)
        resLmpEffectMatrices <- lmpEffectMatrices(resLmpModelMatrix)
        
        pdf("effect_matrices_plots.pdf", width = 8, height = 6)
        print(resLmpEffectMatrices\$varPercentagesPlot)
        dev.off()
        
        # Save variation percentages
        write.csv(as.data.frame(resLmpEffectMatrices\$variationPercentages), "variation_percentages.csv", row.names = TRUE)
        
        
        # 5. Bootstrap tests
        resLmpBootstrapTests <- lmpBootstrapTests(resLmpEffectMatrices = resLmpEffectMatrices, nboot = 100)
        write.csv(resLmpBootstrapTests\$resultsTable, "bootstrap_results.csv", row.names = TRUE)
        
        
        # 6. ASCA
        if (length(cols) >= 2) {
          combine_eff <- list(c(cols[1], cols[2], paste0(cols[1], ":", cols[2])))
        } else {
          combine_eff <- NULL
        }
        resASCA <- lmpPcaEffects(resLmpEffectMatrices = resLmpEffectMatrices, method = "ASCA", combineEffects = combine_eff)
        resLmpContributions <- lmpContributions(resASCA)
        
        pdf("asca_contributions_plots.pdf", width = 8, height = 6)
        print(resLmpContributions\$plotTotal)
        print(resLmpContributions\$plotContrib)
        dev.off()
        
        # Save contribution tables
        write.csv(resLmpContributions\$totalContribTable, "asca_total_contributions.csv", row.names = TRUE)
        write.csv(resLmpContributions\$effectTable, "asca_effect_contributions.csv", row.names = TRUE)
        write.csv(resLmpContributions\$contribTable, "asca_pc_contributions.csv", row.names = TRUE)
        
        
        # 7. ASCA Scores and Loadings
        pdf("asca_scores_loadings_plots.pdf", width = 8, height = 6)
        
        tryCatch({
          all_loadings_pl <- lmpLoading1dPlot(resASCA, effectNames = names(resASCA), axes = 1, xlab = "Variables")
          for (p in all_loadings_pl) print(p)
        }, error = function(e) {
          warning("all_loadings_pl failed: ", e\$message)
        })
        
        tryCatch({
          hip_scores_pl <- lmpScorePlot(resASCA, effectNames = fac1, color = fac1, shape = fac1)
          print(hip_scores_pl)
        }, error = function(e) {
          warning("hip_scores_pl failed: ", e\$message)
        })
        
        tryCatch({
          pcdim_vec <- rep(1, length(names(resASCA)))
          print(lmpScoreScatterPlotM(resASCA, PCdim = pcdim_vec, modelAbbrev = TRUE, varname.colorup = fac2, varname.colordown = fac1, varname.pchup = fac1, varname.pchdown = fac2, title = "ASCA scores scatterplot matrix"))
        }, error = function(e) {
          warning("lmpScoreScatterPlotM failed: ", e\$message)
        })
        
        tryCatch({
          print(lmpLoading2dPlot(resLmpPcaEffects = resASCA, effectNames = c(fac1), axes = c(1, 2), addRownames = TRUE, pl_n = 10))
        }, error = function(e) {
          warning("lmpLoading2dPlot failed: ", e\$message)
        })
        
        dev.off()
        
        
        # 8. Effects plot
        pdf("effects_plots.pdf", width = 8, height = 6)
        
        tryCatch({
          ep1 <- lmpEffectPlot(resASCA, effectName = fac1, x = fac1)
          for (p in ep1) print(p)
        }, error = function(e) {
          warning("lmpEffectPlot 1 failed: ", e\$message)
        })
        
        tryCatch({
          if (length(cols) >= 2) {
            ep2 <- lmpEffectPlot(resASCA, effectName = paste0(cols[1], ":", cols[2]), x = cols[1], z = cols[2])
            for (p in ep2) print(p)
          }
        }, error = function(e) {
          warning("lmpEffectPlot 2 failed: ", e\$message)
        })
        
        dev.off()
        
        
        # 9. APCA
        resAPCA <- lmpPcaEffects(resLmpEffectMatrices = resLmpEffectMatrices, method = "APCA")
        
        pdf("apca_plots.pdf", width = 8, height = 6)
        
        tryCatch({
          print(lmpScorePlot(resAPCA, effectNames = fac1, color = fac1, shape = fac1, drawShapes = "ellipse"))
        }, error = function(e) {
          warning("APCA lmpScorePlot failed: ", e\$message)
        })
        
        tryCatch({
          apca_loadings <- lmpLoading1dPlot(resAPCA, effectNames = names(resAPCA), axes = 1)
          for (p in apca_loadings) print(p)
        }, error = function(e) {
          warning("APCA lmpLoading1dPlot failed: ", e\$message)
        })
        
        dev.off()
        
        
        # 10. ASCA-E
        resASCAE <- lmpPcaEffects(resLmpEffectMatrices = resLmpEffectMatrices, method = "ASCA-E")
        
        pdf("ascae_plots.pdf", width = 8, height = 6)
        
        tryCatch({
          print(lmpScorePlot(resASCAE, effectNames = fac1, color = fac1, shape = fac1))
        }, error = function(e) {
          warning("ASCA-E lmpScorePlot failed: ", e\$message)
        })
        
        dev.off()
        
        
        # Save RDS objects for downstream analysis
        saveRDS(resASCA, "resASCA.rds")
        saveRDS(resAPCA, "resAPCA.rds")
        saveRDS(resASCAE, "resASCAE.rds")
        saveRDS(resLmpEffectMatrices, "resLmpEffectMatrices.rds")
        
        message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_LIMPCA_ASCA_APCA_ANALYSIS":',
        paste0('    limpca: ', as.character(packageVersion('limpca')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_asca_apca_analysis.csv versions.yml
    """
}

workflow BIOC_LIMPCA_ASCA_APCA_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ outcomes.tsv, design.tsv ] ]

    main:
    BIOC_LIMPCA_ASCA_APCA_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_LIMPCA_ASCA_APCA_ANALYSIS.out.tables
    plots    = BIOC_LIMPCA_ASCA_APCA_ANALYSIS.out.plots
    objects  = BIOC_LIMPCA_ASCA_APCA_ANALYSIS.out.objects
    versions = BIOC_LIMPCA_ASCA_APCA_ANALYSIS.out.versions
}
