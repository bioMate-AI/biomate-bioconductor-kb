#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BiSeq — group_wise_dmr_detection
// Detect de novo differentially methylated regions (DMRs) between two groups of samples using clustering, smoothing, beta regression, and hierarchical testing.
// Input: files.ext, colData
// Container: quay.io/biocontainers/bioconductor-biseq:1.50.0--r45hdfd78af_0
// R packages: GenomicRanges, BiSeq
// Bioconductor: 3.20 | R: 4.4
// Requires: BiSeq, GenomicRanges
// Visualizations: box plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Import Bismark files
//  * 2. [Input & Preparation] Define CpG clusters
//  * 3. [Core Analysis] Limit high coverage
//  * 4. [Core Analysis] Smooth methylation data
//  * 5. [Core Analysis] Model group effect with beta regression
//  * 6. [Core Analysis] Model null group effect on resampled data
//  * 7. [Core Analysis] Estimate and smooth the variogram under the null
//  * 8. [Core Analysis] Estimate local correlation of Z-scores
//  * 9. [Core Analysis] Test CpG clusters for differential methylation
//  * 10. [Core Analysis] Trim rejected clusters
//  * 11. [Input & Preparation] Define DMR boundaries

nextflow.enable.dsl = 2

process BIOC_BISEQ_GROUP_WISE_DMR_DETECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("GenomicRanges", "BiSeq")
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
        library(BiSeq)
        library(GenomicRanges)
        
        # ==========================================
        # STAGE 1: Import Bismark files
        # ==========================================
        
        # Read colData from the working directory
        if (file.exists("colData")) {
          colData <- tryCatch({
            readRDS("colData")
          }, error = function(e) {
            tryCatch({
              read.csv("colData", row.names = 1)
            }, error = function(e2) {
              read.table("colData", header = TRUE, row.names = 1)
            })
          })
        } else if (file.exists("colData.csv")) {
          colData <- read.csv("colData.csv", row.names = 1)
        } else if (file.exists("colData.rds")) {
          colData <- readRDS("colData.rds")
        } else {
          stop("Error: colData file not found in the working directory!")
        }
        
        # Ensure colData is a DataFrame
        colData <- DataFrame(colData)
        
        # Read files.ext from the working directory
        if (file.exists("files.ext")) {
          files <- readLines("files.ext")
          files <- trimws(files)
          files <- files[files != ""]
        } else {
          stop("Error: files.ext file not found in the working directory!")
        }
        
        # Import Bismark CpG context output files
        message("Importing Bismark files...")
        rrbs <- readBismark(files, colData)
        
        # ==========================================
        # STAGE 2: Define CpG clusters
        # ==========================================
        message("Defining CpG clusters...")
        
        rrbs.clust.unlim <- clusterSites(object = rrbs,
                                         groups = colData(rrbs)\$group,
                                         perc.samples = 4/5,
                                         min.sites = 20,
                                         max.dist = 100)
        
        # ==========================================
        # STAGE 3: Limit high coverage
        # ==========================================
        message("Limiting high coverage...")
        ind.cov <- totalReads(rrbs.clust.unlim) > 0
        quant <- quantile(totalReads(rrbs.clust.unlim)[ind.cov], 0.9)
        rrbs.clust.lim <- limitCov(rrbs.clust.unlim, maxCov = quant)
        
        # Save coverage boxplots
        pdf("coverage_boxplots.pdf")
        covBoxplots(rrbs.clust.lim, col = "cornflowerblue", las = 2)
        dev.off()
        
        # ==========================================
        # STAGE 4: Smooth methylation data
        # ==========================================
        message("Smoothing methylation data...")
        predictedMeth <- predictMeth(object = rrbs.clust.lim)
        
        # ==========================================
        # STAGE 5: Model group effect with beta regression
        # ==========================================
        message("Modeling group effect with beta regression...")
        betaResults <- betaRegression(formula = ~group,
                                      link = "probit",
                                      object = predictedMeth,
                                      type = "BR")
        
        # Save beta regression results
        write.csv(as.data.frame(betaResults), "beta_results.csv", row.names = TRUE)
        
        # ==========================================
        # STAGE 6: Model null group effect on resampled data
        # ==========================================
        message("Modeling null group effect on resampled data...")
        
        # Robustly construct predictedMethNull based on available samples
        n_samples <- ncol(predictedMeth)
        if (n_samples >= 8) {
          grps <- as.character(colData(predictedMeth)\$group)
          unique_grps <- unique(grps)
          if (length(unique_grps) >= 2) {
            idx1 <- which(grps == unique_grps[1])
            idx2 <- which(grps == unique_grps[2])
            n_each <- min(length(idx1), length(idx2), 4)
            if (n_each >= 2) {
              predictedMethNull <- predictedMeth[, c(idx1[1:n_each], idx2[1:n_each])]
              colData(predictedMethNull)\$group.null <- rep(c(1, 2), ncol(predictedMethNull)/2)
            } else {
              predictedMethNull <- predictedMeth[, 1:(2 * (n_samples %/% 2))]
              colData(predictedMethNull)\$group.null <- rep(c(1, 2), ncol(predictedMethNull)/2)
            }
          } else {
            predictedMethNull <- predictedMeth[, 1:(2 * (n_samples %/% 2))]
            colData(predictedMethNull)\$group.null <- rep(c(1, 2), ncol(predictedMethNull)/2)
          }
        } else {
          predictedMethNull <- predictedMeth[, 1:(2 * (n_samples %/% 2))]
          colData(predictedMethNull)\$group.null <- rep(c(1, 2), ncol(predictedMethNull)/2)
        }
        
        betaResultsNull <- betaRegression(formula = ~group.null,
                                          link = "probit",
                                          object = predictedMethNull,
                                          type = "BR")
        
        # ==========================================
        # STAGE 7: Estimate and smooth the variogram under the null
        # ==========================================
        message("Estimating and smoothing the variogram...")
        vario <- makeVariogram(betaResultsNull)
        vario.sm <- smoothVariogram(vario, sill = 0.9)
        
        # Save variogram plot
        pdf("variogram_plot.pdf")
        plot(vario\$variogram\$v, main = "Variogram of Z-scores under Null")
        lines(vario.sm\$variogram[, c("h", "v.sm")], col = "red", lwd = 1.5)
        grid()
        dev.off()
        
        # Replace the pValsList with the test results of interest
        vario.aux <- makeVariogram(betaResults, make.variogram = FALSE)
        vario.sm\$pValsList <- vario.aux\$pValsList
        
        # ==========================================
        # STAGE 8: Estimate local correlation of Z-scores
        # ==========================================
        message("Estimating local correlation of Z-scores...")
        locCor <- estLocCor(vario.sm)
        
        # ==========================================
        # STAGE 9: Test CpG clusters for differential methylation
        # ==========================================
        message("Testing CpG clusters for differential methylation...")
        clusters.rej <- testClusters(locCor, FDR.cluster = 0.1)
        
        # ==========================================
        # STAGE 10: Trim rejected clusters
        # ==========================================
        message("Trimming rejected clusters...")
        clusters.trimmed <- trimClusters(clusters.rej, FDR.loc = 0.05)
        
        # Save trimmed clusters
        write.csv(as.data.frame(clusters.trimmed), "clusters_trimmed.csv", row.names = TRUE)
        
        # ==========================================
        # STAGE 11: Define DMR boundaries
        # ==========================================
        message("Defining DMR boundaries...")
        DMRs <- findDMRs(clusters.trimmed, max.dist = 100, diff.dir = TRUE)
        
        # Save final DMRs
        write.csv(as.data.frame(DMRs), "DMRs.csv", row.names = FALSE)
        saveRDS(DMRs, "DMRs.rds")
        
        message("Pipeline completed successfully! Outputs written to working directory.")

    writeLines(c(
        '"BIOC_BISEQ_GROUP_WISE_DMR_DETECTION":',
        paste0('    BiSeq: ', as.character(packageVersion('BiSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_group_wise_dmr_detection.csv versions.yml
    """
}

workflow BIOC_BISEQ_GROUP_WISE_DMR_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ files.ext, colData ] ]

    main:
    BIOC_BISEQ_GROUP_WISE_DMR_DETECTION(ch_input)

    emit:
    tables   = BIOC_BISEQ_GROUP_WISE_DMR_DETECTION.out.tables
    plots    = BIOC_BISEQ_GROUP_WISE_DMR_DETECTION.out.plots
    objects  = BIOC_BISEQ_GROUP_WISE_DMR_DETECTION.out.objects
    versions = BIOC_BISEQ_GROUP_WISE_DMR_DETECTION.out.versions
}
