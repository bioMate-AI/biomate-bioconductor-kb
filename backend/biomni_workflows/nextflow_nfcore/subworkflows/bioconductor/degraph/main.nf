#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DEGraph — network_differential_expression_testing
// Perform topology-based multivariate differential expression testing on gene networks and visualize the results.
// Input: exprData, classData, grList, annData
// Container: quay.io/biocontainers/bioconductor-degraph:1.62.0--r45hdfd78af_0
// R packages: R.utils, corpcor, DEGraph, fields, KEGGgraph, lattice, marray, RBGL, Rgraphviz
// Bioconductor: 3.20 | R: 4.4
// Requires: DEGraph, KEGGgraph, R.utils, Rgraphviz, corpcor, fields, lattice, marray
// Visualizations: pathway diagram
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read User Input Files
//  * 2. [Visualization & Output] Calculate Individual Gene t-statistics for Visualization
//  * 3. [Visualization & Output] Perform Multivariate Testing on Each Network
//  * 4. [Visualization & Output] Filter Out NULL Results (no connected component of size >
//  * 5. [Visualization & Output] Extract p-values and Identify Significant Networks
//  * 6. [Visualization & Output] Translate Gene IDs and Visualize Significant Networks

nextflow.enable.dsl = 2

process BIOC_DEGRAPH_NETWORK_DIFFERENTIAL_EXPRESSION_TESTING {
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
    .bm_deps <- c("R.utils", "corpcor", "DEGraph", "fields", "KEGGgraph", "lattice", "marray", "RBGL", "Rgraphviz")
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
        
        # Load required libraries
        library(DEGraph)
        library(R.utils)
        library(corpcor)
        library(KEGGgraph)
        library(Rgraphviz)
        library(fields)
        library(lattice)
        library(marray)
        
        verbose <- TRUE
        
        # -------------------------------------------------------------------------
        # --- Read User Input Files ---
        # -------------------------------------------------------------------------
        # The pipeline reads exactly these files from the working directory
        exprData  <- readRDS("exprData.rds")
        classData <- readRDS("classData.rds")
        grList    <- readRDS("grList.rds")
        annData   <- readRDS("annData.rds")
        
        # -------------------------------------------------------------------------
        # --- Calculate Individual Gene t-statistics for Visualization ---
        # -------------------------------------------------------------------------
        classes <- unique(classData)
        X1 <- t(exprData[, classData == classes[1]])
        X2 <- t(exprData[, classData == classes[2]])
        ttpv <- c()
        tts <- c()
        for(i in 1:ncol(X1)) {
          tt <- t.test(X1[,i], X2[,i])
          ttpv[i] <- unlist(tt\$p.value)
          tts[i]  <- unlist(tt\$statistic)
        }
        names(ttpv) <- names(tts) <- rownames(exprData)
        
        # Save gene-level statistics
        gene_stats <- data.frame(
          GeneID = rownames(exprData),
          t_statistic = tts,
          p_value = ttpv,
          stringsAsFactors = FALSE
        )
        write.csv(gene_stats, "gene_level_stats.csv", row.names = FALSE)
        
        # -------------------------------------------------------------------------
        # --- Perform Multivariate Testing on Each Network ---
        # -------------------------------------------------------------------------
        prop <- 0.2
        resList <- NULL
        for (ii in seq(along=grList)) {
          gr <- grList[[ii]]
          res <- testOneGraph(gr, exprData, classData, verbose=verbose, prop=prop)
          resList <- c(resList, list(res))
        }
        resNames <- names(grList)
        pLabels <- sapply(grList, attr, "label")
        
        # -------------------------------------------------------------------------
        # --- Filter Out NULL Results (no connected component of size > ---
        # -------------------------------------------------------------------------
        isNULL <- sapply(resList, is.null)
        if (sum(isNULL)) {
          grList[isNULL]
          resList <- resList[!isNULL]
          resNames <- names(grList)[!isNULL]
          pLabels <- pLabels[!isNULL]
        }
        
        # Save raw results list
        saveRDS(resList, "resList.rds")
        
        # -------------------------------------------------------------------------
        # --- Extract p-values and Identify Significant Networks ---
        # -------------------------------------------------------------------------
        resL <- sapply(resList, length)
        graphNames <- rep(resNames, times=resL)
        pathwayNames <- rep(pLabels, times=resL)
        
        graphList <- NULL
        for (res in resList) {
          grl <- lapply(res, FUN=function(x) {
            x\$graph
          })
          graphList <- c(graphList, as.list(grl))
        }
        
        ndims <- NULL
        for (res in resList) {
          ndim <- sapply(res, FUN=function(x) {
            x\$k
          })
          ndims <- c(ndims, ndim)
        }
        
        pKEGG <- NULL
        for (res in resList) {
          pp <- sapply(res, FUN=function(x) {
            x\$p.value
          })
          pKEGG <- cbind(pKEGG, pp)
        }
        colnames(pKEGG) <- graphNames
        rn <- rownames(pKEGG)
        rownames(pKEGG)[grep("Fourier", rn)] <- paste("T2 (", round(100*prop), "% Fourier components)", sep="")
        
        # Save pathway p-values
        write.csv(pKEGG, "pathway_pvalues.csv", row.names = TRUE)
        
        # -------------------------------------------------------------------------
        # --- Translate Gene IDs and Visualize Significant Networks ---
        # -------------------------------------------------------------------------
        if (exists("maPalette", mode="function")) {
          pal <- maPalette(low="red", high="green", mid="black", k=100)
        } else {
          pal <- heat.colors(100)
        }
        
        shift <- tts
        names(shift) <- translateGeneID2KEGGID(names(tts))
        fSignif <- which(pKEGG[2,] < 0.05)
        fSignif <- fSignif[order(pKEGG[2,fSignif])]
        
        # Plot significant pathways to a PDF file
        pdf("DEGraph_significant_pathways.pdf", width=10, height=8)
        
        if (length(fSignif) > 0) {
          # Plot up to the top 5 significant pathways
          num_plots <- min(5, length(fSignif))
          for (i in 1:num_plots) {
            gIdx <- fSignif[i]
            gr <- graphList[[gIdx]]
            mm <- match(translateKEGGID2GeneID(nodes(gr)), rownames(annData))
            dn <- annData[mm, 1]
            
            # Plot the valued graph
            res <- plotValuedGraph(gr, values=shift, nodeLabels=dn, qMax=0.95, colorPalette=pal, height=40, lwd=1, cex=0.3, verbose=verbose)
            stext(side=3, pos=0, pathwayNames[gIdx])
            ps <- signif(pKEGG[, gIdx], 2)
            txt1 <- paste("p(T2)=", ps[1], sep="")
            txt2 <- paste("p(T2F[", ndims[gIdx], "])=", ps[2], sep="")
            txt <- paste(txt1, txt2, sep="\n")
            stext(side=3, pos=1, txt)
            image.plot(legend.only=TRUE, zlim=range(res\$breaks), col=pal, legend.shrink=0.3, legend.width=0.8, legend.lab="t-scores", legend.mar=3.3)
          }
        } else {
          plot.new()
          text(0.5, 0.5, "No significant pathways found (p < 0.05)")
        }
        
        dev.off()

    writeLines(c(
        '"BIOC_DEGRAPH_NETWORK_DIFFERENTIAL_EXPRESSION_TESTING":',
        paste0('    DEGraph: ', as.character(packageVersion('DEGraph')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_network_differential_expression_testing.csv versions.yml
    """
}

workflow BIOC_DEGRAPH_NETWORK_DIFFERENTIAL_EXPRESSION_TESTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ exprData, classData, grList, annData ] ]

    main:
    BIOC_DEGRAPH_NETWORK_DIFFERENTIAL_EXPRESSION_TESTING(ch_input)

    emit:
    tables   = BIOC_DEGRAPH_NETWORK_DIFFERENTIAL_EXPRESSION_TESTING.out.tables
    plots    = BIOC_DEGRAPH_NETWORK_DIFFERENTIAL_EXPRESSION_TESTING.out.plots
    objects  = BIOC_DEGRAPH_NETWORK_DIFFERENTIAL_EXPRESSION_TESTING.out.objects
    versions = BIOC_DEGRAPH_NETWORK_DIFFERENTIAL_EXPRESSION_TESTING.out.versions
}
