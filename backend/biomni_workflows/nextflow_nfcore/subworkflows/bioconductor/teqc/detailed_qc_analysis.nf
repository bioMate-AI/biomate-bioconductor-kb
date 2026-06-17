#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: TEQC — detailed_qc_analysis
// Perform a step-by-step manual quality control analysis of target capture data, including specificity, coverage, duplicates, and reproducibility.
// Input: ExampleSet_Targets.bed, ExampleSet_Reads.bed, ExampleSet_Baits.txt
// Container: quay.io/biocontainers/bioconductor-teqc:4.32.0--r45hdfd78af_0
// R packages: TEQC
// Bioconductor: 3.20 | R: 4.4
// Requires: TEQC
// Visualizations: bar plot, density plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load target regions and calculate targeted fraction of the genome
//  * 2. [Input & Preparation] Load aligned reads and optionally pair them
//  * 3. [Visualization & Output] Plot insert size distribution (for paired-end data)
//  * 4. [Visualization & Output] Visualize read distribution across chromosomes
//  * 5. [Core Analysis] Calculate capture specificity and enrichment
//  * 6. [Core Analysis] Calculate and analyze target coverage
//  * 7. [Visualization & Output] Plot coverage distribution and uniformity
//  * 8. [Core Analysis] Analyze coverage relation to target length and GC content
//  * 9. [Visualization & Output] Visualize coverage along chromosomes and export wiggle files
//  * 10. [Input & Preparation] Analyze read duplicates
//  * 11. [Core Analysis] Assess reproducibility across replicates

nextflow.enable.dsl = 2

process BIOC_TEQC_DETAILED_QC_ANALYSIS {
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
    .bm_deps <- c("TEQC")
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
        
        library(TEQC)
        
        # 1. Load target regions and calculate targeted fraction of the genome
        targets <- get.targets(targetsfile="ExampleSet_Targets.bed", chrcol = 1, startcol = 2, endcol = 3, skip = 0)
        ft <- fraction.target(targets, genome = "hg38")
        
        # 2. Load aligned reads and optionally pair them
        reads <- get.reads("ExampleSet_Reads.bed", chrcol = 1, startcol = 2, endcol = 3, idcol = 4, zerobased = F, skip = 0)
        readpairs <- reads2pairs(reads)
        
        # Check if reads2pairs returned a list (happens when single reads are present)
        if (inherits(readpairs, "list")) {
            readpairs <- readpairs\$readpairs
        }
        
        # 3. Plot insert size distribution (for paired-end data)
        pdf("insert_size_hist.pdf")
        insert.size.hist(readpairs, breaks=10)
        dev.off()
        
        # 4. Visualize read distribution across chromosomes
        pdf("chrom_barplot.pdf")
        chrom.barplot(reads, targets)
        dev.off()
        
        # 5. Calculate capture specificity and enrichment
        fr <- fraction.reads.target(reads, targets)
        fr_offset <- fraction.reads.target(reads, targets, Offset=100)
        enrichment <- fr / ft
        fr_pairs <- fraction.reads.target(readpairs, targets)
        
        # 6. Calculate and analyze target coverage
        Coverage <- coverage.target(reads, targets, perTarget=T, perBase=T)
        targets2 <- Coverage\$targetCoverages
        targets2 <- readsPerTarget(reads, targets2)
        
        # Export target coverage table
        write.table(as.data.frame(targets2), file="target_coverage.txt", sep="\t", row.names=F, quote=F)
        
        # Calculate fraction of target bases achieving at least k coverage
        ck <- covered.k(Coverage\$coverageTarget, k=c(1, 5, 10))
        write.csv(as.data.frame(t(ck)), file="covered_k.csv", row.names=F)
        
        # 7. Plot coverage distribution and uniformity
        pdf("coverage_hist.pdf")
        coverage.hist(Coverage\$coverageTarget, covthreshold=8)
        dev.off()
        
        pdf("coverage_uniformity.pdf")
        coverage.uniformity(Coverage)
        dev.off()
        
        # 8. Analyze coverage relation to target length and GC content
        pdf("coverage_targetlength.pdf", width=10, height=5)
        par(mfrow=c(1,2))
        coverage.targetlength.plot(targets2, plotcolumn="nReads", pch=16, cex=1.5)
        coverage.targetlength.plot(targets2, plotcolumn="avgCoverage", pch=16, cex=1.5)
        dev.off()
        
        baits <- get.baits("ExampleSet_Baits.txt", chrcol=3, startcol=4, endcol=5, seqcol=2)
        
        pdf("coverage_GC.pdf")
        coverage.GC(Coverage\$coverageAll, baits, pch=16, cex=1.5)
        dev.off()
        
        # 9. Visualize coverage along chromosomes and export wiggle files
        # Dynamically extract coordinates from the first target region for plotting
        plot_chr <- as.character(seqnames(targets)[1])
        plot_start <- max(1, start(targets)[1] - 500)
        plot_end <- end(targets)[1] + 500
    
        pdf("coverage_plot.pdf")
        coverage.plot(Coverage\$coverageAll, targets, Offset=100, chr=plot_chr, Start=plot_start, End=plot_end)
        dev.off()
        
        make.wigfiles(Coverage\$coverageAll)
        
        # 10. Analyze read duplicates
        pdf("duplicates_barplot_reads.pdf")
        duplicates.barplot(reads, targets)
        dev.off()
        
        pdf("duplicates_barplot_pairs.pdf")
        duplicates.barplot(readpairs, targets, ylab="Fraction of read pairs")
        dev.off()
        
        reads.collapsed <- unique(reads)
        ID.nondups <- names(unique(readpairs))
        reads.collapsed.pairs <- reads[names(reads) %in% ID.nondups]
        
        cov_collapsed <- coverage.target(reads.collapsed, targets, perBase=F, perTarget=F)
        cov_collapsed_pairs <- coverage.target(reads.collapsed.pairs, targets, perBase=F, perTarget=F)
        
        # 11. Assess reproducibility across replicates
        set.seed(123)
        r <- sample(length(reads), 0.1 * length(reads))
        reads2 <- reads[-r]
        Coverage2 <- coverage.target(reads2, targets, perBase=T)
        
        covlist <- list(Coverage, Coverage2)
        
        pdf("coverage_density.pdf", width=10, height=5)
        par(mfrow=c(1,2))
        coverage.density(covlist)
        coverage.density(covlist, normalized=F)
        dev.off()
        
        pdf("coverage_uniformity_comparison.pdf")
        coverage.uniformity(Coverage, addlines=F)
        coverage.uniformity(Coverage2, addlines=F, add=T, col="blue", lty=2)
        dev.off()
        
        pdf("coverage_plot_comparison.pdf")
        coverage.plot(Coverage\$coverageAll, targets, Offset=100, chr=plot_chr, Start=plot_start, End=plot_end)
        coverage.plot(Coverage2\$coverageAll, add=T, col.line=2, chr=plot_chr, Start=plot_start, End=plot_end)
        dev.off()
        
        pdf("coverage_correlation.pdf")
        coverage.correlation(covlist, plotfrac=0.1, cex.pch=4)
        dev.off()
        
        # Save final R objects and summary metrics
        saveRDS(Coverage, "Coverage.rds")
        saveRDS(Coverage2, "Coverage2.rds")
        
        sink("summary_metrics.txt")
        cat("=== TEQC QC Analysis Summary ===\n")
        cat("Fraction Target (hg38):", ft, "\n")
        cat("Fraction Reads on Target:", fr, "\n")
        cat("Fraction Reads on Target (Offset=100):", fr_offset, "\n")
        cat("Enrichment:", enrichment, "\n")
        cat("Fraction Pairs on Target:", fr_pairs, "\n")
        cat("Average Target Coverage:", Coverage\$avgTargetCoverage, "\n")
        cat("Target Coverage SD:", Coverage\$targetCoverageSD, "\n")
        cat("Average Target Coverage (Collapsed):", cov_collapsed\$avgTargetCoverage, "\n")
        cat("Average Target Coverage (Collapsed Pairs):", cov_collapsed_pairs\$avgTargetCoverage, "\n")
        sink()

    writeLines(c(
        '"BIOC_TEQC_DETAILED_QC_ANALYSIS":',
        paste0('    TEQC: ', as.character(packageVersion('TEQC')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_detailed_qc_analysis.csv versions.yml
    """
}

workflow BIOC_TEQC_DETAILED_QC_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ExampleSet_Targets.bed, ExampleSet_Reads.bed, ExampleSet_Baits.txt ] ]

    main:
    BIOC_TEQC_DETAILED_QC_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_TEQC_DETAILED_QC_ANALYSIS.out.tables
    plots    = BIOC_TEQC_DETAILED_QC_ANALYSIS.out.plots
    objects  = BIOC_TEQC_DETAILED_QC_ANALYSIS.out.objects
    versions = BIOC_TEQC_DETAILED_QC_ANALYSIS.out.versions
}
