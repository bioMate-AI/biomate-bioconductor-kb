#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BadRegionFinder — coverage_quality_analysis
// Determine, classify, and report genomic coverage quality across multiple samples, map bad regions to genes, and visualize the results.
// Input: SampleNames2.txt, targetRegions2.bed, BAM/BAI files, regionsOfInterest
// Container: quay.io/biocontainers/bioconductor-badregionfinder:1.38.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BadRegionFinder, biomaRt
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Determine coverage across samples using determineCoverage
//  * 2. [Core Analysis] Classify coverage quality using determineCoverageQuality
//  * 3. [Core Analysis] Filter for regions of interest using determineRegionsOfInterest
//  * 4. [Visualization & Output] Retrieve gene annotations and report bad regions using reportBadRegionsSummary, reportBadRegionsDetailed, and reportBadRegionsGene
//  * 5. [Visualization & Output] Visualize results using plotSummary, plotDetailed, and plotSummaryGenes
//  * 6. [Core Analysis] Calculate quantiles using determineQuantiles

nextflow.enable.dsl = 2

process BIOC_BADREGIONFINDER_COVERAGE_QUALITY_ANALYSIS {
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
    .bm_deps <- c("BadRegionFinder", "biomaRt")
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
    library(BadRegionFinder)
    library(biomaRt)
    
    # Create output directory
    dir.create("output", showWarnings = FALSE, recursive = TRUE)
    
    # 1. Read User Inputs
    # Read sample names (without .bam suffix)
    samples <- read.table("SampleNames2.txt", header = FALSE, stringsAsFactors = FALSE)
    
    # Read target regions (BED format: chromosome, start, end)
    targetRegions <- read.table("targetRegions2.bed", header = FALSE, stringsAsFactors = FALSE)
    
    # Determine BAM input directory
    bam_input <- "BAM"
    if (!dir.exists(bam_input)) {
      bam_input <- "."
    }
    
    # Read optional regions of interest
    if (file.exists("regionsOfInterest.txt")) {
      regionsOfInterest <- read.table("regionsOfInterest.txt", header = TRUE, stringsAsFactors = FALSE)
    } else if (file.exists("regionsOfInterest.bed")) {
      regionsOfInterest <- read.table("regionsOfInterest.bed", header = FALSE, stringsAsFactors = FALSE)
      colnames(regionsOfInterest)[1:3] <- c("chr", "start", "end")
    } else {
      # Fallback to target regions if file is not present
      regionsOfInterest <- targetRegions
      colnames(regionsOfInterest)[1:3] <- c("chr", "start", "end")
    }
    
    # 2. Determine coverage across samples
    coverage_summary <- determineCoverage(samples, bam_input, targetRegions, "output", TRonly = FALSE)
    
    # Define thresholds
    threshold1 <- 20
    threshold2 <- 100
    percentage1 <- 0.80
    percentage2 <- 0.90
    
    # 3. Classify coverage quality
    coverage_indicators <- determineCoverageQuality(threshold1, threshold2, percentage1, percentage2, coverage_summary)
    
    # 4. Filter for regions of interest
    coverage_indicators_2 <- determineRegionsOfInterest(regionsOfInterest, coverage_indicators)
    
    # 5. Retrieve gene annotations and report bad regions
    # Use tryCatch for biomaRt to handle potential network/server issues gracefully
    mart <- tryCatch({
      useMart(biomart="ENSEMBL_MART_ENSEMBL", host="https://grch37.ensembl.org", path="/biomart/martservice", dataset="hsapiens_gene_ensembl")
    }, error = function(e) {
      message("Warning: Failed to connect to Ensembl via biomaRt. Falling back to default hg19 annotation.")
      ""
    })
    
    badCoverageSummary <- reportBadRegionsSummary(threshold1, threshold2, percentage1, percentage2, coverage_indicators_2, mart, "output")
    
    coverage_indicators_temp <- reportBadRegionsDetailed(threshold1, threshold2, percentage1, percentage2, coverage_indicators_2, mart, samples, "output")
    
    badCoverageOverview <- reportBadRegionsGenes(threshold1, threshold2, percentage1, percentage2, badCoverageSummary, "output")
    
    # 6. Visualize results
    plotSummary(threshold1, threshold2, percentage1, percentage2, badCoverageSummary, "output")
    
    plotDetailed(threshold1, threshold2, percentage1, percentage2, coverage_indicators_temp, "output")
    
    plotSummaryGenes(threshold1, threshold2, percentage1, percentage2, badCoverageOverview, "output")
    
    # 7. Calculate quantiles
    quantiles <- c(0.5)
    coverage_summary2 <- determineQuantiles(coverage_summary, quantiles, "output")
    
    # Save R objects for downstream analysis
    saveRDS(coverage_summary, "output/coverage_summary.rds")
    saveRDS(coverage_indicators, "output/coverage_indicators.rds")
    saveRDS(coverage_indicators_2, "output/coverage_indicators_2.rds")
    saveRDS(badCoverageSummary, "output/badCoverageSummary.rds")
    saveRDS(coverage_indicators_temp, "output/coverage_indicators_temp.rds")
    saveRDS(badCoverageOverview, "output/badCoverageOverview.rds")
    saveRDS(coverage_summary2, "output/coverage_summary2.rds")
    
    message("Pipeline completed successfully. Outputs saved to 'output/' directory.")

    writeLines(c(
        '"BIOC_BADREGIONFINDER_COVERAGE_QUALITY_ANALYSIS":',
        paste0('    BadRegionFinder: ', as.character(packageVersion('BadRegionFinder')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_coverage_quality_analysis.csv versions.yml
    """
}

workflow BIOC_BADREGIONFINDER_COVERAGE_QUALITY_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ SampleNames2.txt, targetRegions2.bed, BAM/BAI files, regionsOfInterest ] ]

    main:
    BIOC_BADREGIONFINDER_COVERAGE_QUALITY_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_BADREGIONFINDER_COVERAGE_QUALITY_ANALYSIS.out.tables
    plots    = BIOC_BADREGIONFINDER_COVERAGE_QUALITY_ANALYSIS.out.plots
    objects  = BIOC_BADREGIONFINDER_COVERAGE_QUALITY_ANALYSIS.out.objects
    versions = BIOC_BADREGIONFINDER_COVERAGE_QUALITY_ANALYSIS.out.versions
}
