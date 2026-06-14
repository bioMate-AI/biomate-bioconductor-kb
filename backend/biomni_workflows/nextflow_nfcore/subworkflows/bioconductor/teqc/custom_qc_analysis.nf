#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: teqc — custom_qc_analysis
// Perform a step-by-step programmatic quality control analysis of target capture data including specificity, coverage, duplicates, and reproducibility.
// Input: ExampleSet_Targets.bed, ExampleSet_Reads.bed, ExampleSet_Baits.txt
// Container: quay.io/biocontainers/bioconductor-teqc:4.32.0--r45hdfd78af_0
// R packages: TEQC
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: bar plot, coverage plot, density plot

nextflow.enable.dsl = 2

process BIOC_TEQC_CUSTOM_QC_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-teqc:4.32.0--r45hdfd78af_0"

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
    .bm_deps <- c("TEQC")
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
    
    # Load required library
    library(TEQC)
    
    # --- Load targets and reads data ---
    # Reading user input files from the working directory
    targets_file <- "ExampleSet_Targets.bed"
    reads_file <- "ExampleSet_Reads.bed"
    baits_file <- "ExampleSet_Baits.txt"
    
    # Check if files exist
    if (!file.exists(targets_file)) stop(paste("Missing required input file:", targets_file))
    if (!file.exists(reads_file)) stop(paste("Missing required input file:", reads_file))
    if (!file.exists(baits_file)) stop(paste("Missing required input file:", baits_file))
    
    # Load targets
    targets <- get.targets(targetsfile=targets_file, chrcol = 1, startcol = 2, endcol = 3, skip = 0)
    
    # Calculate fraction of genome targeted
    ft <- fraction.target(targets, genome = "hg38")
    
    # Load reads
    reads <- get.reads(reads_file, chrcol = 1, startcol = 2, endcol = 3, idcol = 4, zerobased = F, skip = 0)
    
    # --- Convert reads to pairs for paired-end data and plot ---
    readpairs <- reads2pairs(reads)
    
    pdf("plot1_insert_size.pdf")
    insert.size.hist(readpairs, breaks=10)
    dev.off()
    
    # --- Calculate specificity, enrichment, and plot chromosome ---
    pdf("plot2_chrom_barplot.pdf")
    chrom.barplot(reads, targets)
    dev.off()
    
    fr <- fraction.reads.target(reads, targets)
    fr_offset <- fraction.reads.target(reads, targets, Offset=100)
    enrichment <- fr / ft
    fr_pairs <- fraction.reads.target(readpairs, targets)
    
    # Save specificity and enrichment stats
    spec_stats <- data.frame(
      Metric = c("Fraction_Reads_On_Target", "Fraction_Reads_On_Target_Offset100", "Enrichment", "Fraction_Pairs_On_Target"),
      Value = c(fr, fr_offset, enrichment, fr_pairs)
    )
    write.csv(spec_stats, "specificity_enrichment_stats.csv", row.names = FALSE)
    
    # --- Calculate coverage statistics and plot coverage ---
    Coverage <- coverage.target(reads, targets, perTarget=T, perBase=T)
    saveRDS(Coverage, "Coverage_object.rds")
    
    targets2 <- Coverage\$targetCoverages
    targets2 <- readsPerTarget(reads, targets2)
    
    # Save target coverages table
    write.table(as.data.frame(targets2), file="target_coverage.txt", sep="\t", row.names=F, quote=F)
    
    # Covered k fractions
    cov_k <- covered.k(Coverage\$coverageTarget, k=c(1, 5, 10))
    write.csv(as.data.frame(t(cov_k)), "covered_k_stats.csv", row.names = FALSE)
    
    pdf("plot3_coverage_hist.pdf")
    coverage.hist(Coverage\$coverageTarget, covthreshold=8)
    dev.off()
    
    pdf("plot4_coverage_uniformity.pdf")
    coverage.uniformity(Coverage)
    dev.off()
    
    pdf("plot5_coverage_targetlength.pdf", width=10, height=5)
    par(mfrow=c(1,2))
    coverage.targetlength.plot(targets2, plotcolumn="nReads", pch=16, cex=1.5)
    coverage.targetlength.plot(targets2, plotcolumn="avgCoverage", pch=16, cex=1.5)
    dev.off()
    
    # Load baits and plot GC bias
    baits <- get.baits(baits_file, chrcol=3, startcol=4, endcol=5, seqcol=2)
    
    pdf("plot6_coverage_GC.pdf")
    coverage.GC(Coverage\$coverageAll, baits, pch=16, cex=1.5)
    dev.off()
    
    # Coverage plot along chromosome (wrapped in tryCatch in case coordinates are out of bounds for custom data)
    pdf("plot7_coverage_plot.pdf")
    tryCatch({
      coverage.plot(Coverage\$coverageAll, targets, Offset=100, chr="chr1", Start=11157524, End=11158764)
    }, error = function(e) {
      warning("Could not plot coverage for chr1:11157524-11158764. Coordinates might not be present in the input data.")
    })
    dev.off()
    
    # --- Analyze and plot read duplicates ---
    pdf("plot8_duplicates_barplot.pdf")
    duplicates.barplot(reads, targets)
    dev.off()
    
    pdf("plot9_duplicates_barplot_pairs.pdf")
    duplicates.barplot(readpairs, targets, ylab="Fraction of read pairs")
    dev.off()
    
    # Collapse duplicates
    reads.collapsed <- unique(reads)
    ID.nondups <- names(unique(readpairs))
    reads.collapsed.pairs <- reads[names(reads) %in% ID.nondups,,drop=T]
    
    cov_collapsed <- coverage.target(reads.collapsed, targets, perBase=F, perTarget=F)
    cov_collapsed_pairs <- coverage.target(reads.collapsed.pairs, targets, perBase=F, perTarget=F)
    
    # Save collapsed coverage stats
    collapsed_stats <- data.frame(
      Dataset = c("Collapsed_Single", "Collapsed_Pairs"),
      AvgTargetCoverage = c(cov_collapsed\$avgTargetCoverage, cov_collapsed_pairs\$avgTargetCoverage),
      TargetCoverageSD = c(cov_collapsed\$targetCoverageSD, cov_collapsed_pairs\$targetCoverageSD)
    )
    write.csv(collapsed_stats, "collapsed_coverage_stats.csv", row.names = FALSE)
    
    # --- Assess reproducibility across samples ---
    set.seed(123) # For reproducibility of sampling
    r <- sample(length(reads), 0.1 * length(reads))
    reads2 <- reads[-r,,drop=T]
    Coverage2 <- coverage.target(reads2, targets, perBase=T)
    saveRDS(Coverage2, "Coverage2_object.rds")
    
    covlist <- list(Coverage, Coverage2)
    
    pdf("plot10_coverage_density.pdf", width=10, height=5)
    par(mfrow=c(1,2))
    coverage.density(covlist)
    coverage.density(covlist, normalized=F)
    dev.off()
    
    pdf("plot11_coverage_uniformity_comparison.pdf")
    coverage.uniformity(Coverage, addlines=F)
    coverage.uniformity(Coverage2, addlines=F, add=T, col="blue", lty=2)
    dev.off()
    
    pdf("plot12_coverage_plot_comparison.pdf")
    tryCatch({
      coverage.plot(Coverage\$coverageAll, targets, Offset=100, chr="chr1", Start=11157524, End=11158764)
      coverage.plot(Coverage2\$coverageAll, add=T, col.line=2, chr="chr1", Start=11157524, End=11158764)
    }, error = function(e) {
      warning("Could not plot coverage comparison for chr1:11157524-11158764.")
    })
    dev.off()
    
    pdf("plot13_coverage_correlation.pdf")
    coverage.correlation(covlist, plotfrac=0.1, cex.pch=4)
    dev.off()
    
    cat("Pipeline completed successfully!\n")

    writeLines(c(
        '"BIOC_TEQC_CUSTOM_QC_ANALYSIS":',
        paste0('        teqc: ', as.character(packageVersion("teqc")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_qc_analysis.csv versions.yml
    """
}

workflow BIOC_TEQC_CUSTOM_QC_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ExampleSet_Targets.bed, ExampleSet_Reads.bed, ExampleSet_Baits.txt ] ]

    main:
    BIOC_TEQC_CUSTOM_QC_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_TEQC_CUSTOM_QC_ANALYSIS.out.tables
    plots    = BIOC_TEQC_CUSTOM_QC_ANALYSIS.out.plots
    objects  = BIOC_TEQC_CUSTOM_QC_ANALYSIS.out.objects
    versions = BIOC_TEQC_CUSTOM_QC_ANALYSIS.out.versions
}
