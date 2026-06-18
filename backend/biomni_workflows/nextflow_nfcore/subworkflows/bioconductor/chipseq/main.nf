#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: chipseq — chipseq_analysis_and_differential_peaks
// Perform ChIP-seq read extension, coverage calculation, peak calling, differential peak analysis between two samples, and genomic context annotation.
// Input: sampleFiles, TxDb.Mmusculus.UCSC.mm9.knownGene
// Container: quay.io/biocontainers/bioconductor-chipseq:1.60.0--r45h01b2380_0
// R packages: GenomicAlignments, GenomicFeatures, Rsamtools, ShortRead, TxDb.Mmusculus.UCSC.mm9.knownGene, chipseq, lattice, rtracklayer
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicAlignments, GenomicFeatures, Rsamtools, ShortRead, TxDb.Mmusculus.UCSC.mm9.knownGene, chipseq, lattice
// Visualizations: coverage plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Filter and load aligned reads using chipseqFilter and ShortRead
//  * 2. [Core Analysis] Estimate fragment length using estimate.mean.fraglen
//  * 3. [Core Analysis] Extend reads to estimated fragment length using resize
//  * 4. [Core Analysis] Calculate coverage using coverage
//  * 5. [Core Analysis] Identify islands and analyze depth using slice, viewSums, viewMaxs, and islandDepthPlot
//  * 6. [Core Analysis] Determine peak cutoff using peakCutoff and call peaks using slice
//  * 7. [Visualization & Output] Summarize peaks using peakSummary
//  * 8. [Visualization & Output] Plot strand-specific coverage using coverageplot
//  * 9. [Core Analysis] Perform differential peak analysis using diffPeakSummary
//  * 10. [Core Analysis] Annotate peaks with genomic features (promoters, genes) using GenomicFeatures and %over%

nextflow.enable.dsl = 2

process BIOC_CHIPSEQ_CHIPSEQ_ANALYSIS_AND_DIFFERENTIAL_PEAKS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("GenomicAlignments", "GenomicFeatures", "Rsamtools", "ShortRead", "TxDb.Mmusculus.UCSC.mm9.knownGene", "chipseq", "lattice", "rtracklayer")
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
            library(chipseq)
            library(GenomicFeatures)
            library(lattice)
            library(ShortRead)
            library(GenomicAlignments)
            library(Rsamtools)
            library(TxDb.Mmusculus.UCSC.mm9.knownGene)
            
            # Define the input files in the working directory
            # The pipeline expects these files to be present in the working directory.
            sampleFiles <- c(
              ctcf = "ctcf.bam",
              gfp = "gfp.bam"
            )
            
            # Verify that the input files exist before proceeding
            missing_files <- sampleFiles[!file.exists(sampleFiles)]
            if (length(missing_files) > 0) {
              stop(paste("Missing required input files in the working directory:",
                         paste(missing_files, collapse = ", ")))
            }
            
            # 1. Filter and load aligned reads using GenomicAlignments
            param <- ScanBamParam(mapqFilter = 15, flag = scanBamFlag(isDuplicate = FALSE, isUnmappedQuery = FALSE))
            cstest <- GRangesList(lapply(sampleFiles, function(file) {
              as(readGAlignments(file, param = param), "GRanges")
            }))
            
            # Subset to chromosomes 10, 11, and 12
            cstest <- tryCatch({
              cstest[seqnames(cstest) %in% c("chr10", "chr11", "chr12")]
            }, error = function(e) {
              # Fallback if direct subsetting on GenomicRangesList seqnames is not supported
              endoapply(cstest, function(gr) {
                gr[seqnames(gr) %in% c("chr10", "chr11", "chr12")]
              })
            })
            
            # 2. Estimate fragment length using estimate.mean.fraglen
            fraglen <- estimate.mean.fraglen(cstest\$ctcf, method="correlation")
            valid_fraglen <- fraglen[!is.na(fraglen)]
            write.csv(as.data.frame(valid_fraglen), "estimated_fragment_lengths.csv")
            
            # 3. Extend reads to estimated fragment length using resize
            ctcf.ext <- resize (cstest\$ctcf, width = 200)
            
            # 4. Calculate coverage using coverage
            cov.ctcf <- coverage(ctcf.ext)
            
            # 5. Identify islands and analyze depth using slice, viewSums, viewMaxs, and islandDepthPlot
            islands <- slice(cov.ctcf, lower = 1)
            
            viewSums(islands)
            viewMaxs(islands)
            
            nread.tab <- table(viewSums(islands) / 200)
            depth.tab <- table(viewMaxs(islands))
            
            write.csv(as.data.frame(nread.tab), "island_nreads_table.csv")
            write.csv(as.data.frame(depth.tab), "island_depths_table.csv")
            
            pdf("island_depth_plot.pdf")
            islandDepthPlot(cov.ctcf)
            dev.off()
            
            # 6. Determine peak cutoff using peakCutoff and call peaks using slice
            cutoff <- peakCutoff(cov.ctcf, fdr = 0.0001) 
            
            peaks.ctcf <- slice(cov.ctcf, lower = cutoff) 
            
            # 7. Summarize peaks using peakSummary
            peaks <- peakSummary(peaks.ctcf) 
            saveRDS(peaks, "peaks_ctcf_summary.rds")
            
            # 8. Plot strand-specific coverage using coverageplot
            peak.depths <- viewMaxs(peaks.ctcf)
            
            cov.pos <- coverage(ctcf.ext[strand(ctcf.ext) == "+"]) 
            cov.neg <- coverage(ctcf.ext[strand(ctcf.ext) == "-"])
            
            peaks.pos <- Views(cov.pos, ranges(peaks.ctcf)) 
            peaks.neg <- Views(cov.neg, ranges(peaks.ctcf))
            
            chroms_with_peaks <- names(peak.depths)[lengths(peak.depths) > 0]
            
            pdf("coverage_plots.pdf")
            if (length(chroms_with_peaks) > 0) {
              plot_chr <- chroms_with_peaks[1]
              wpeaks <- tail(order(peak.depths[[plot_chr]]), 4)
              
              if (length(wpeaks) >= 1) {
                coverageplot(peaks.pos[[plot_chr]][wpeaks[1]], peaks.neg[[plot_chr]][wpeaks[1]])
              }
              if (length(wpeaks) >= 2) {
                coverageplot(peaks.pos[[plot_chr]][wpeaks[2]], peaks.neg[[plot_chr]][wpeaks[2]])
              }
              if (length(wpeaks) >= 3) {
                coverageplot(peaks.pos[[plot_chr]][wpeaks[3]], peaks.neg[[plot_chr]][wpeaks[3]])
              }
              if (length(wpeaks) >= 4) {
                coverageplot(peaks.pos[[plot_chr]][wpeaks[4]], peaks.neg[[plot_chr]][wpeaks[4]])
              }
            }
            dev.off()
            
            # 9. Perform differential peak analysis using diffPeakSummary
            cov.gfp <- coverage(resize(cstest\$gfp, 200))
            peaks.gfp <- slice(cov.gfp, lower = cutoff)
            
            peakSummary <- diffPeakSummary(peaks.gfp, peaks.ctcf)
            
            mcols(peakSummary) <- 
                within(mcols(peakSummary), 
                   {
                       diffs <- asinh(sums2) - asinh(sums1) 
                       resids <- (diffs - median(diffs)) / mad(diffs) 
                       up <- resids > 2 
                       down <- resids < -2 
                       change <- ifelse(up, "up", ifelse(down, "down", "flat")) 
                   })
            
            # 10. Annotate peaks with genomic features (promoters, genes) using GenomicFeatures and %over%
            gregions <- transcripts(TxDb.Mmusculus.UCSC.mm9.knownGene) 
            
            promoters <- flank(gregions, 1000, both = TRUE) 
            
            peakSummary\$inPromoter <- peakSummary %over% promoters
            xtabs(~ inPromoter + change, peakSummary) 
            
            peakSummary\$inUpstream <- peakSummary %over% flank(gregions, 20000)
            peakSummary\$inGene <- peakSummary %over% gregions
            
            sumtab <- 
                as.data.frame(rbind(total = xtabs(~ change, peakSummary),
                                    promoter = xtabs(~ change, 
                                      subset(peakSummary, inPromoter)),
                                    upstream = xtabs(~ change, 
                                      subset(peakSummary, inUpstream)),
                                    gene = xtabs(~ change, subset(peakSummary, inGene))))
            
            # Write final outputs
            write.csv(sumtab, "differential_peaks_genomic_context_summary.csv")
            saveRDS(peakSummary, "differential_peaks_summary.rds")

    writeLines(c(
        '"BIOC_CHIPSEQ_CHIPSEQ_ANALYSIS_AND_DIFFERENTIAL_PEAKS":',
        paste0('    chipseq: ', as.character(packageVersion('chipseq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chipseq_analysis_and_differential_peaks.csv versions.yml
    """
}

workflow BIOC_CHIPSEQ_CHIPSEQ_ANALYSIS_AND_DIFFERENTIAL_PEAKS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sampleFiles, TxDb.Mmusculus.UCSC.mm9.knownGene ] ]

    main:
    BIOC_CHIPSEQ_CHIPSEQ_ANALYSIS_AND_DIFFERENTIAL_PEAKS(ch_input)

    emit:
    tables   = BIOC_CHIPSEQ_CHIPSEQ_ANALYSIS_AND_DIFFERENTIAL_PEAKS.out.tables
    plots    = BIOC_CHIPSEQ_CHIPSEQ_ANALYSIS_AND_DIFFERENTIAL_PEAKS.out.plots
    objects  = BIOC_CHIPSEQ_CHIPSEQ_ANALYSIS_AND_DIFFERENTIAL_PEAKS.out.objects
    versions = BIOC_CHIPSEQ_CHIPSEQ_ANALYSIS_AND_DIFFERENTIAL_PEAKS.out.versions
}
