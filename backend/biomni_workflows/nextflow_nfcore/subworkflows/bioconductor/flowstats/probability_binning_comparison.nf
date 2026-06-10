#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: flowStats — probability_binning_comparison
// Quantitate multivariate distribution differences between experimental flow cytometry samples and a control sample using probability binning.
// Input: gs
// Container: quay.io/biocontainers/bioconductor-flowstats:4.22.0--r45hdfd78af_0
// R packages: flowCore, flowStats, flowWorkspace
// Bioconductor: 3.20 | R: 4.4
// Requires: flowCore, flowStats, flowWorkspace
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Extract flow data from GatingSet
//  * 2. [Input & Preparation] Create a control dataset by combining and subsampling flowFrames
//  * 3. [Core Analysis] Apply probability binning to the control data using proBin
//  * 4. [Core Analysis] Apply control bin positions to sample data using binByRef via fsApply
//  * 5. [Core Analysis] Calculate Pearson Chi-Square and Roederer's probability binning statistics using calcPearsonChi and calcPBChiSquare

nextflow.enable.dsl = 2

process BIOC_FLOWSTATS_PROBABILITY_BINNING_COMPARISON {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("flowCore", "flowStats", "flowWorkspace")
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
        
        library(flowCore)
        library(flowStats)
        library(flowWorkspace)
        
        # 1. Load the input 'gs' from the working directory
        if (dir.exists("gs")) {
          gs <- load_gs("gs")
        } else if (file.exists("gs")) {
          gs <- readRDS("gs")
        } else {
          stop("Input 'gs' (GatingSet directory or RDS file) not found in the working directory.")
        }
        
        # If gs is a flowSet, wrap it in a GatingSet to ensure gs_cyto_data(gs) works
        if (is(gs, "flowSet")) {
          gs <- GatingSet(gs)
        }
        
        # 2. Run the documented workflow exactly as specified
        dat <- gs_cyto_data(gs)
        datComb <- as(dat,"flowFrame")
        subCount <- as.integer(nrow(exprs(datComb))/length(dat))
        sf <- sampleFilter(filterId="mySampleFilter", size=subCount)
        fres <- filter(datComb, sf)
        ctrlData <- Subset(datComb, fres)
        ctrlData <- ctrlData[,-ncol(ctrlData)]
        minRow=subCount*0.05
        chs <- colnames(ctrlData)[1:2]
        refBins<-proBin(ctrlData,minRow,channels=chs)
        sampBins <- fsApply(dat,function(x){
        		   binByRef(refBins,x)
        		   })
        pearsonStat <- lapply(sampBins,function(x){
        		      calcPearsonChi(refBins,x)
                             })
        sCount <- fsApply(dat,nrow)
        pBStat <-lapply(seq_along(sampBins),function(x){
        		calcPBChiSquare(refBins,sampBins[[x]],subCount,sCount[x])
        		})
        
        # 3. Save outputs
        saveRDS(refBins, "refBins.rds")
        saveRDS(pearsonStat, "pearsonStat.rds")
        saveRDS(pBStat, "pBStat.rds")
        
        # Create and save statistics table
        patNames <- sampleNames(dat)
        chi_Square_Statistic <- unlist(lapply(pearsonStat, function(x) {
          x\$statistic
        }))
        pBin_Statistic <- unlist(lapply(pBStat, function(x) {
          x\$pbStat
        })) 
        frame <- data.frame(chi_Square_Statistic, pBin_Statistic)
        rownames(frame) <- patNames
        write.csv(frame, "probability_binning_statistics.csv", row.names=TRUE)
        
        # Create and save plots
        pdf("probability_binning_plots.pdf", width=10, height=10)
        par(mfrow=c(4,4), mar=c(1.5,1.5,1.5,1.5))
        plotBins(refBins, ctrlData, channels=chs, title="Control Data")
        tm <- lapply(seq_len(length(dat)), function(x) {
          plotBins(refBins, dat[[x]], channels=chs,
                   title=patNames[x],
                   residuals=pearsonStat[[x]]\$residuals[2,],
                   shadeFactor=0.7)
        })
        dev.off()

    writeLines(c(
        '"BIOC_FLOWSTATS_PROBABILITY_BINNING_COMPARISON":',
        paste0('    flowStats: ', as.character(packageVersion('flowStats')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_probability_binning_comparison.csv versions.yml
    """
}

workflow BIOC_FLOWSTATS_PROBABILITY_BINNING_COMPARISON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gs ] ]

    main:
    BIOC_FLOWSTATS_PROBABILITY_BINNING_COMPARISON(ch_input)

    emit:
    tables   = BIOC_FLOWSTATS_PROBABILITY_BINNING_COMPARISON.out.tables
    plots    = BIOC_FLOWSTATS_PROBABILITY_BINNING_COMPARISON.out.plots
    objects  = BIOC_FLOWSTATS_PROBABILITY_BINNING_COMPARISON.out.objects
    versions = BIOC_FLOWSTATS_PROBABILITY_BINNING_COMPARISON.out.versions
}
