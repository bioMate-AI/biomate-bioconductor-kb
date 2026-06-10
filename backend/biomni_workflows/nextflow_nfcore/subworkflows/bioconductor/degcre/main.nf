#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DegCre — deg_cre_association_analysis
// Associate differentially expressed genes with cis-regulatory elements, optimize the significance threshold, visualize the results, and export the associations t
// Input: subDegGR, subCreGR
// Container: quay.io/biocontainers/bioconductor-degcre:1.6.0--r45hdfd78af_0
// R packages: TxDb.Hsapiens.UCSC.hg38.knownGene, DegCre, GenomicRanges, InteractionSet, magick, org.Hs.eg.db, plotgardener
// Bioconductor: 3.20 | R: 4.4
// Requires: DegCre, GenomicRanges, InteractionSet, TxDb.Hsapiens.UCSC.hg38.knownGene, magick, org.Hs.eg.db, plotgardener
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Run the core association algorithm using runDegCre or optimize the DEG significance threshold using optimizeAlphaDegCre. 2. Filter

nextflow.enable.dsl = 2

process BIOC_DEGCRE_DEG_CRE_ASSOCIATION_ANALYSIS {
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
    .bm_deps <- c("TxDb.Hsapiens.UCSC.hg38.knownGene", "DegCre", "GenomicRanges", "InteractionSet", "magick", "org.Hs.eg.db", "plotgardener")
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
    library(GenomicRanges)
    library(InteractionSet)
    library(plotgardener)
    library(TxDb.Hsapiens.UCSC.hg38.knownGene)
    library(org.Hs.eg.db)
    library(DegCre)
    library(magick)
    
    # ------------------------------------------------------------------------------
    # 1. Read User Input Files
    # ------------------------------------------------------------------------------
    # The pipeline expects 'subDegGR.rds' and 'subCreGR.rds' in the working directory.
    if (!file.exists("subDegGR.rds") || !file.exists("subCreGR.rds")) {
      stop("Required input files 'subDegGR.rds' and/or 'subCreGR.rds' are missing from the working directory.")
    }
    
    subDegGR <- readRDS("subDegGR.rds")
    subCreGR <- readRDS("subCreGR.rds")
    
    # ------------------------------------------------------------------------------
    # 2. Run Core Association Algorithm
    # ------------------------------------------------------------------------------
    myDegCreResList <- runDegCre(DegGR=subDegGR,
                                 DegP=subDegGR\$pVal,
                                 DegLfc=subDegGR\$logFC,
                                 CreGR=subCreGR,
                                 CreP=subCreGR\$pVal,
                                 CreLfc=subCreGR\$logFC,
                                 reqEffectDirConcord=TRUE,
                                 verbose=FALSE)
    
    # Save the initial association results
    saveRDS(myDegCreResList, "myDegCreResList.rds")
    
    # ------------------------------------------------------------------------------
    # 3. Filter Hits Object by FDR and Association Probability
    # ------------------------------------------------------------------------------
    passFDR <- which(mcols(myDegCreResList\$degCreHits)\$assocProbFDR <= 0.05)
    passProb <- which(mcols(myDegCreResList\$degCreHits)\$assocProb >= 0.25)
    
    keepDegCreHits <- myDegCreResList\$degCreHits[intersect(passFDR,passProb)]
    
    # Save the filtered hits
    saveRDS(keepDegCreHits, "keepDegCreHits.rds")
    
    # ------------------------------------------------------------------------------
    # 4. Optimize DEG Significance Threshold (Alpha)
    # ------------------------------------------------------------------------------
    alphaOptList <- optimizeAlphaDegCre(DegGR=subDegGR,
                                        DegP=subDegGR\$pVal,
                                        DegLfc=subDegGR\$logFC,
                                        CreGR=subCreGR,
                                        CreP=subCreGR\$pVal,
                                        CreLfc=subCreGR\$logFC,
                                        reqEffectDirConcord=TRUE,
                                        verbose=FALSE)
    
    bestAlphaId <- which.max(alphaOptList\$alphaPRMat[,4])
    
    bestDegCreResList <- alphaOptList\$degCreResListsByAlpha[[bestAlphaId]]
    
    # Save the optimized results list
    saveRDS(bestDegCreResList, "bestDegCreResList.rds")
    
    # ------------------------------------------------------------------------------
    # 5. Visualizations: Association Probabilities, Binning Heuristic, and PR Curve
    # ------------------------------------------------------------------------------
    # Plot 1: Association Probabilities vs Distance
    pdf("assoc_prob_vs_dist.pdf", width=8, height=6)
    par(mai=c(0.8,1.6,0.4,0.1))
    par(mgp=c(1.7,0.5,0))
    par(cex.axis=1)
    par(cex.lab=1.4)
    par(bty="l")
    par(lwd=2)
    binStats <- plotDegCreAssocProbVsDist(degCreResList=bestDegCreResList,
                                          assocProbFDRThresh=0.05)
    dev.off()
    
    # Plot 2: Binning Heuristic
    pdf("bin_heuristic.pdf", width=6, height=6)
    par(mai=c(0.8,0.6,0.4,0.1))
    par(mgp=c(1.7,0.5,0))
    par(cex.axis=1)
    par(cex.lab=1.4)
    par(bty="l")
    par(lwd=1.5)
    plotDegCreBinHeuristic(degCreResList=bestDegCreResList)
    dev.off()
    
    # Plot 3: Precision-Recall Curve
    pdf("pr_auc_curve.pdf", width=6, height=6)
    par(mai=c(0.8,0.6,0.4,0.1))
    par(mgp=c(1.7,0.5,0))
    par(cex.axis=1)
    par(cex.lab=1.4)
    par(bty="l")
    par(lwd=1.5)
    degCrePRAUC(degCreResList=bestDegCreResList)
    dev.off()
    
    # ------------------------------------------------------------------------------
    # 6. Estimate and Plot Expected Associations per DEG
    # ------------------------------------------------------------------------------
    expectAssocPerDegDf <- getExpectAssocPerDEG(degCreResList=bestDegCreResList,
                                                geneNameColName="GeneSymb",
                                                assocAlpha=0.05)
    
    # Export expected associations to CSV
    write.csv(as.data.frame(expectAssocPerDegDf), "expectAssocPerDegDf.csv", row.names=FALSE)
    
    # Plot 4: Expected Associations Histogram
    pdf("expected_assocs_per_deg.pdf", width=6, height=6)
    par(mai=c(0.8,0.6,0.4,0.1))
    par(mgp=c(1.7,0.5,0))
    par(cex.axis=1)
    par(cex.lab=1.4)
    par(bty="l")
    plotExpectedAssocsPerDeg(expectAssocPerDegDf=expectAssocPerDegDf)
    dev.off()
    
    # ------------------------------------------------------------------------------
    # 7. Browser-Style Visualizations
    # ------------------------------------------------------------------------------
    # Robustly select a gene name present in the dataset (fallback if ERRFI1 is missing)
    geneName <- "ERRFI1"
    if (!(geneName %in% bestDegCreResList\$DegGR\$GeneSymb)) {
      if (nrow(expectAssocPerDegDf) > 0) {
        geneName <- expectAssocPerDegDf\$GeneSymb[1]
      } else {
        geneName <- bestDegCreResList\$DegGR\$GeneSymb[1]
      }
    }
    
    # Define a robust zoom region around the selected gene (+/- 250kb)
    gene_idx <- which(bestDegCreResList\$DegGR\$GeneSymb == geneName)[1]
    gene_gr <- bestDegCreResList\$DegGR[gene_idx]
    zoom_start <- max(1, start(gene_gr) - 250000)
    zoom_end <- end(gene_gr) + 250000
    zoomGR <- GRanges(seqnames=as.character(seqnames(gene_gr)),
                      ranges=IRanges(start=zoom_start, end=zoom_end))
    
    # Generate browser plots inside a single PDF
    pdf("browser_plots.pdf", width=8, height=10)
    tryCatch({
      # Standard Browser View
      browserOuts <- plotBrowserDegCre(degCreResList=bestDegCreResList,
                                       geneName=geneName,
                                       geneNameColName="GeneSymb",
                                       CreSignalName="NR3C1",
                                       panelTitleFontSize=8,
                                       geneLabelFontsize=10,
                                       plotXbegin=0.9,
                                       plotWidth=5)
      
      # Zoomed Browser View
      zoomBrowserOuts <- plotBrowserDegCre(degCreResList=bestDegCreResList,
                                           plotRegionGR=zoomGR,
                                           geneNameColName="GeneSymb",
                                           CreSignalName="NR3C1",
                                           panelTitleFontSize=8,
                                           geneLabelFontsize=10,
                                           plotXbegin=0.9,
                                           plotWidth=5)
      
      # Highlighted Browser View
      geneHighDf <- data.frame(gene=bestDegCreResList\$DegGR\$GeneSymb,
                               col="gray")
      geneHighDf[which(geneHighDf\$gene==geneName), 2] <- "black"
      
      highLightBrowserOuts <- plotBrowserDegCre(degCreResList=bestDegCreResList,
                                                plotRegionGR=zoomGR,
                                                CreSignalName="NR3C1",
                                                geneNameColName="GeneSymb",
                                                geneHighlightDf=geneHighDf,
                                                panelTitleFontSize=8,
                                                geneLabelFontsize=10,
                                                plotXbegin=0.9,
                                                plotWidth=5)
    }, error = function(e) {
      message("Warning: Browser plotting encountered an issue: ", e\$message)
    })
    dev.off()
    
    # ------------------------------------------------------------------------------
    # 8. Convert Results to Standard Formats and Export
    # ------------------------------------------------------------------------------
    # Convert to GInteractions object
    degCreGInter <- convertdegCreResListToGInteraction(degCreResList=bestDegCreResList,
                                                       assocAlpha=0.05)
    saveRDS(degCreGInter, "degCreGInter.rds")
    
    # Convert to BEDPE-like DataFrame
    degCreDf <- convertDegCreDataFrame(degCreResList=bestDegCreResList,
                                       assocAlpha=0.05)
    write.csv(degCreDf, "degCreDf.csv", row.names=FALSE)
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_DEGCRE_DEG_CRE_ASSOCIATION_ANALYSIS":',
        paste0('    DegCre: ', as.character(packageVersion('DegCre')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_deg_cre_association_analysis.csv versions.yml
    """
}

workflow BIOC_DEGCRE_DEG_CRE_ASSOCIATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ subDegGR, subCreGR ] ]

    main:
    BIOC_DEGCRE_DEG_CRE_ASSOCIATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_DEGCRE_DEG_CRE_ASSOCIATION_ANALYSIS.out.tables
    plots    = BIOC_DEGCRE_DEG_CRE_ASSOCIATION_ANALYSIS.out.plots
    objects  = BIOC_DEGCRE_DEG_CRE_ASSOCIATION_ANALYSIS.out.objects
    versions = BIOC_DEGCRE_DEG_CRE_ASSOCIATION_ANALYSIS.out.versions
}
