#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: dmrseq — dmr_detection
// Scan the genome to detect and perform inference on local differentially methylated regions (DMRs) from WGBS count data.
// Input: sample_bismark.cov.gz, sample_metadata.csv
// Container: quay.io/biocontainers/bioconductor-dmrseq:1.30.0--r45hdfd78af_0
// R packages: DelayedMatrixStats, GenomicRanges, annotatr, BiocParallel, bsseq, dmrseq
// Bioconductor: 3.20 | R: 4.4
// Requires: DelayedMatrixStats, GenomicRanges, annotatr, bsseq, dmrseq
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load Bismark coverage files into a BSseq object using read.bismark
//  * 2. [Core Analysis] Add sample metadata to the pData slot of the BSseq object
//  * 3. [Core Analysis] Filter out CpGs with zero coverage and subset samples
//  * 4. [Core Analysis] Run dmrseq to detect candidate regions and perform permutation-based inference
//  * 5. [Core Analysis] Extract significant regions and calculate raw mean differences using meanDiff
//  * 6. [Visualization & Output] Visualize DMRs and empirical distributions using plotDMRs and plotEmpiricalDistribution

nextflow.enable.dsl = 2

process BIOC_DMRSEQ_DMR_DETECTION {
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
    .bm_deps <- c("DelayedMatrixStats", "GenomicRanges", "annotatr", "BiocParallel", "bsseq", "dmrseq")
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
                    
        library(dmrseq)
        library(bsseq)
        library(DelayedMatrixStats)
        library(GenomicRanges)
        library(annotatr)
        
        # ==========================================
        # STAGE 1: Load Bismark coverage files into a BSseq object
        # ==========================================
        
        # Read user metadata
        metadata <- read.csv("sample_metadata.csv", stringsAsFactors = FALSE)
        
        # dmrseq requires at least 2 samples per condition (minimum 4 samples total for 2 groups)
        if (nrow(metadata) < 4) {
          stop("dmrseq requires at least 2 samples per condition (minimum 4 samples total).")
        }
        
        # Dynamically use sample names and conditions from metadata
        sampleNames <- metadata[[1]]
        condition <- metadata[[2]]
        
        # Read the Bismark coverage files
        infiles <- paste0(sampleNames, "_bismark.cov.gz")
        
        bs <- read.bismark(files = infiles,
                           colData = data.frame(row.names = sampleNames),
                           rmZeroCov = TRUE,
                           strandCollapse = FALSE,
                           verbose = TRUE)
        show(bs)
        
        # ==========================================
        # STAGE 2: Add sample metadata to the pData slot
        # ==========================================
        
        pData(bs)\$Condition <- condition
        pData(bs)\$Replicate <- ave(seq_along(condition), condition, FUN = seq_along)
        
        pData(bs)
        
        # ==========================================
        # STAGE 3: Filter out CpGs with zero coverage and subset samples
        # ==========================================
        
        loci.idx <- which(DelayedMatrixStats::rowSums2(getCoverage(bs, type="Cov")==0) == 0)
        sample.idx <- which(pData(bs)\$Condition %in% unique(condition))
        
        bs.filtered <- bs[loci.idx, sample.idx]
        
        # ==========================================
        # STAGE 4: Run dmrseq to detect candidate regions and perform inference
        # ==========================================
        
        testCovariate <- "Condition"
        regions <- dmrseq(bs=bs.filtered,
                          cutoff = 0.05,
                          testCovariate=testCovariate)
        show(regions)
        
        # Run block detection
        blocks <- dmrseq(bs=bs.filtered,
                          cutoff = 0.05,
                          testCovariate=testCovariate,
                          block = TRUE,
                          minInSpan = 500,
                          bpSpan = 5e4,
                          maxGapSmooth = 1e6,
                          maxGap = 5e3)
        head(blocks)
        
        # ==========================================
        # STAGE 5: Extract significant regions and calculate raw mean differences
        # ==========================================
        
        sum(regions\$qval < 0.05, na.rm = TRUE)
        
        sigRegions <- regions[which(regions\$qval < 0.05),]
        
        if (length(sigRegions) > 0) {
          print(sum(sigRegions\$stat > 0) / length(sigRegions))
          
          rawDiff <- meanDiff(bs.filtered, dmrs=sigRegions, testCovariate=testCovariate)
          str(rawDiff)
          saveRDS(rawDiff, file="raw_mean_differences.rds")
        } else {
          message("No significant regions found at FDR 0.05.")
        }
        
        # Export tabular results
        write.csv(as.data.frame(regions), file="dmrseq_results.csv")
        write.csv(as.data.frame(blocks), file="dmrseq_blocks.csv")
        saveRDS(regions, file="regions.rds")
        saveRDS(blocks, file="blocks.rds")
        
        # ==========================================
        # STAGE 6: Visualize DMRs and empirical distributions
        # ==========================================
        
        pdf("dmr_plots.pdf", width = 10, height = 8)
        
        # Plot first DMR region
        if (length(regions) > 0) {
          tryCatch({
            plotDMRs(bs.filtered, regions=regions[1,], testCovariate=testCovariate)
          }, error = function(e) {
            message("Error plotting DMR: ", e\$message)
          })
        }
        
        # Plot first block region
        if (length(blocks) > 0) {
          tryCatch({
            plotDMRs(bs.filtered, regions=blocks[1,], testCovariate=testCovariate)
          }, error = function(e) {
            message("Error plotting block: ", e\$message)
          })
        }
        
        # Plot empirical distributions
        tryCatch({
          plotEmpiricalDistribution(bs.filtered, testCovariate=testCovariate)
        }, error = function(e) {
          message("Error plotting empirical distribution: ", e\$message)
        })
        
        tryCatch({
          plotEmpiricalDistribution(bs.filtered, testCovariate=testCovariate, 
                                    type="Cov", bySample=TRUE)
        }, error = function(e) {
          message("Error plotting empirical distribution by sample: ", e\$message)
        })
        
        dev.off()
        
        sessionInfo()

    writeLines(c(
        '"BIOC_DMRSEQ_DMR_DETECTION":',
        paste0('    dmrseq: ', as.character(packageVersion('dmrseq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dmr_detection.csv versions.yml
    """
}

workflow BIOC_DMRSEQ_DMR_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sample_bismark.cov.gz, sample_metadata.csv ] ]

    main:
    BIOC_DMRSEQ_DMR_DETECTION(ch_input)

    emit:
    tables   = BIOC_DMRSEQ_DMR_DETECTION.out.tables
    plots    = BIOC_DMRSEQ_DMR_DETECTION.out.plots
    objects  = BIOC_DMRSEQ_DMR_DETECTION.out.objects
    versions = BIOC_DMRSEQ_DMR_DETECTION.out.versions
}
