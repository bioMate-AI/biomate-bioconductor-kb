#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DEWSeq — dewseq_clip_analysis
// Identify differentially enriched RNA-binding protein binding regions from eCLIP/iCLIP sliding window count data compared to size-matched input controls.
// Input: countFile.txt.gz, annotationFile.txt.gz, maxCountFile.txt.gz
// Container: quay.io/biocontainers/bioconductor-dewseq:1.24.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: DEWSeq, data.table, dplyr, tidyverse
// Visualizations: dispersion plot
// QC: dispersion/size-factor estimation, dispersion QC plot, low-count filtering, missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load count and annotation data using fread
//  * 2. [Input & Preparation] Define sample metadata (colData) and construct a DESeqDataSet using DESeqDataSetFromSlidingWindows
//  * 3. [Core Analysis] Prefilter low-count windows using filterCounts
//  * 4. [Core Analysis] Estimate size factors, optionally adjusting for asymmetric enrichment by temporarily identifying and excluding significant windows
//  * 5. [Core Analysis] Estimate dispersions (comparing parametric and local fits) and run the Wald test using estimateDispersions and nbinomWaldTest
//  * 6. [Core Analysis] Perform one-sided significance testing for IP enrichment using resultsDEWSeq
//  * 7. [Core Analysis] Apply multiple hypothesis correction using IHW
//  * 8. [Core Analysis] Combine overlapping significant windows into binding regions using extractRegions
//  * 9. [Visualization & Output] Export the final regions to a BED file using toBED

nextflow.enable.dsl = 2

process BIOC_DEWSEQ_DEWSEQ_CLIP_ANALYSIS {
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
    .bm_deps <- c("DEWSeq", "IHW", "tidyverse", "data.table", "SummarizedExperiment")
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
        library(DEWSeq)
        library(IHW)
        library(tidyverse)
        library(data.table)
        
        # Define input files
        countFile <- "countFile.txt.gz"
        annotationFile <- "annotationFile.txt.gz"
        maxCountFile <- "maxCountFile.txt.gz"
        
        # Check if files exist
        if (!file.exists(countFile)) {
          stop(paste("Required input file missing:", countFile))
        }
        if (!file.exists(annotationFile)) {
          stop(paste("Required input file missing:", annotationFile))
        }
        
        # Read data
        countData <- fread(countFile, sep = "\t")
        annotationData <- fread(annotationFile, sep = "\t")
        
        # Define sample metadata (colData) dynamically based on columns of countData
        sample_names <- colnames(countData)[-1]
        types <- rep("IP", length(sample_names))
        smi_indices <- grep("SMI|input|control", sample_names, ignore.case = TRUE)
        if (length(smi_indices) > 0) {
          types[smi_indices] <- "SMI"
        } else {
          # Fallback: if no SMI is found in names, assume the last one is SMI
          types[length(types)] <- "SMI"
        }
        
        colData <- data.frame(
          row.names = sample_names,
          type      = factor(types, levels = c("IP", "SMI"))
        )
        
        # Construct DESeqDataSet
        ddw <- DESeqDataSetFromSlidingWindows(countData  = countData,
                                              colData    = colData,
                                              annotObj   = annotationData,
                                              tidy       = TRUE,
                                              design     = ~type)
        
        ddw <- estimateSizeFactors(ddw)
        
        # Prefilter low-count windows
        if (file.exists(maxCountFile)) {
          ddw <- filterCounts( object = ddw, maxCountFile = maxCountFile, 
                                countThresh = 5, nsamples = 2)
        } else {
          # Fallback filtering if maxCountFile is not provided
          keep <- rowSums(counts(ddw)) >= 10
          ddw <- ddw[keep,]
        }
        
        # Estimate size factors based on protein coding genes
        if ("gene_type" %in% colnames(rowData(ddw)) && any(rowData(ddw)[,"gene_type"] == "protein_coding")) {
          ddw_mRNAs <- ddw[ rowData(ddw)[,"gene_type"] == "protein_coding", ]
        } else {
          ddw_mRNAs <- ddw
        }
        
        ddw_mRNAs <- estimateSizeFactors(ddw_mRNAs)
        sizeFactors(ddw) <- sizeFactors(ddw_mRNAs)
        
        # Estimate size factors for asymmetric data
        ddw_tmp <- ddw
        ddw_tmp <- estimateDispersions(ddw_tmp, fitType = "local", quiet = TRUE)
        ddw_tmp <- nbinomWaldTest(ddw_tmp)
        ddw_tmp_results <- results(ddw_tmp, contrast = c("type", "IP", "SMI"),
                                   tidy = TRUE, filterFun = ihw)
        tmp_significant_windows <- ddw_tmp_results %>%
                                   dplyr::filter(padj < 0.05) %>% 
                                   dplyr::pull(row)
        rm(list = c("ddw_tmp", "ddw_tmp_results"))
        
        ddw_mRNAs <- ddw_mRNAs[ !rownames(ddw_mRNAs) %in% tmp_significant_windows, ]
        ddw_mRNAs <- estimateSizeFactors(ddw_mRNAs)
        sizeFactors(ddw) <- sizeFactors(ddw_mRNAs)
        rm( list = c("tmp_significant_windows", "ddw_mRNAs"))
        
        # Decide fit type
        decide_fit <- TRUE
        parametric_ddw  <- estimateDispersions(ddw, fitType="parametric")
        if(decide_fit){
          local_ddw  <- estimateDispersions(ddw, fitType="local")
        }
        
        parametricResid <- na.omit(with(mcols(parametric_ddw),abs(log(dispGeneEst)-log(dispFit))))
        if(decide_fit){
          localResid <- na.omit(with(mcols(local_ddw),abs(log(dispGeneEst)-log(dispFit))))
          residDf <- data.frame(residuals=c(parametricResid,localResid),
                                fitType=c(rep("parametric",length(parametricResid)),
                                          rep("local",length(localResid))))
        }
        
        if (median(localResid) <= median(parametricResid)){
          cat("chosen fitType: local\n")
          ddw <- local_ddw
        }else{
          cat("chosen fitType: parametric\n")
          ddw <- parametric_ddw
        }
        rm(local_ddw,parametric_ddw,residDf,parametricResid,localResid)
        
        # Run Wald test
        ddw <- nbinomWaldTest(ddw)
        
        # Save dispersion plot
        pdf("dispersion_plots.pdf")
        plotDispEsts(ddw)
        dev.off()
        
        # Significance testing
        resultWindows <- resultsDEWSeq(ddw,
                                      contrast = c("type", "IP", "SMI"),
                                      tidy = TRUE) %>% as_tibble
        
        resultWindows[,"p_adj_IHW"] <- adj_pvalues(ihw(pSlidingWindows ~ baseMean, 
                             data = resultWindows,
                             alpha = 0.05,
                             nfolds = 10))
        
        resultWindows <- resultWindows %>% 
                              mutate(significant = resultWindows\$p_adj_IHW < 0.01)
        
        # Combine overlapping significant windows into binding regions
        resultRegions <- extractRegions(windowRes  = resultWindows,
                                        padjCol    = "p_adj_IHW",
                                        padjThresh = 0.01, 
                                        log2FoldChangeThresh = 0.5) %>% as_tibble
        
        # Export final regions to BED
        toBED(windowRes = resultWindows,
              regionRes = resultRegions,
              fileName  = "enrichedWindowsRegions.bed")
        
        # Save additional outputs
        write_tsv(resultWindows, "resultWindows.tsv")
        write_tsv(resultRegions, "resultRegions.tsv")
        saveRDS(ddw, "ddw_final.rds")
        
        cat("Pipeline completed successfully.\n")

    writeLines(c(
        '"BIOC_DEWSEQ_DEWSEQ_CLIP_ANALYSIS":',
        paste0('    DEWSeq: ', as.character(packageVersion('DEWSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dewseq_clip_analysis.csv versions.yml
    """
}

workflow BIOC_DEWSEQ_DEWSEQ_CLIP_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ countFile.txt.gz, annotationFile.txt.gz, maxCountFile.txt.gz ] ]

    main:
    BIOC_DEWSEQ_DEWSEQ_CLIP_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_DEWSEQ_DEWSEQ_CLIP_ANALYSIS.out.tables
    plots    = BIOC_DEWSEQ_DEWSEQ_CLIP_ANALYSIS.out.plots
    objects  = BIOC_DEWSEQ_DEWSEQ_CLIP_ANALYSIS.out.objects
    versions = BIOC_DEWSEQ_DEWSEQ_CLIP_ANALYSIS.out.versions
}
