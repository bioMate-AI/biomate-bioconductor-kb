#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: similaRpeak — chipseq_profile_similarity
// Extract coverage from BAM files, normalize to RPM, and calculate all similarity metrics between two ChIP-Seq profiles.
// Input: align1.bam, region
// Container: quay.io/biocontainers/bioconductor-similarpeak:1.42.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicAlignments, Rsamtools, rtracklayer, similaRpeak
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the similaRpeak package and alignment packages
//  * 2. [Input & Preparation] Define the genomic region of interest as a GRanges object
//  * 3. [Core Analysis] Extract raw coverage for the region from the BAM file
//  * 4. [Core Analysis] Convert raw coverage to numeric vector
//  * 5. [Core Analysis] Calculate total BAM records to compute weight for Reads Per Million (RPM) normalization
//  * 6. [Core Analysis] Extract RPM-normalized coverage for the region
//  * 7. [Core Analysis] Calculate similarity metrics using the similarity function

nextflow.enable.dsl = 2

process BIOC_SIMILARPEAK_CHIPSEQ_PROFILE_SIMILARITY {
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
    .bm_deps <- c("similaRpeak", "GenomicAlignments", "rtracklayer", "Rsamtools")
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
            
            # Stage 1: Load the similaRpeak package and alignment packages
            library(similaRpeak)
            suppressMessages(library(GenomicAlignments))
            suppressMessages(library(rtracklayer))
            suppressMessages(library(Rsamtools))
            
            # Stage 2: Define the genomic region of interest as a GRanges object
            # Reading the user-provided BAM file and GRanges region object from the working directory
            bamFile01 <- "align1.bam"
            
            if (file.exists("region.rds")) {
              region <- readRDS("region.rds")
            } else if (file.exists("region")) {
              region <- readRDS("region")
            } else {
              stop("Error: Required input 'region' (GRanges RDS file) not found in the working directory.")
            }
            
            if (!file.exists(bamFile01)) {
              stop("Error: Required input 'align1.bam' not found in the working directory.")
            }
            
            # Stage 3: Extract raw coverage for the region from the BAM file
            # Ensure the BAM is indexed — a ranged read (which=) requires a .bai.
            if (!file.exists(paste0(bamFile01, ".bai"))) Rsamtools::indexBam(bamFile01)
            param <- ScanBamParam(which = region)
            alignments <- readGAlignments(bamFile01, param = param)
            
            # Compare positive and negative strands of the single BAM file
            alignments01 <- alignments[strand(alignments) == "+"]
            alignments02 <- alignments[strand(alignments) == "-"]
            
            coveragesRegion01 <- coverage(alignments01)[region]
            coveragesRegion02 <- coverage(alignments02)[region]
            
            # Stage 4: Convert raw coverage to numeric vector
            chr_name <- as.character(seqnames(region)[1])
            coveragesRegion01 <- as.numeric(coveragesRegion01[[chr_name]])
            coveragesRegion02 <- as.numeric(coveragesRegion02[[chr_name]])
            
            # Stage 5: Calculate total BAM records to compute weight for Reads Per Million (RPM) normalization
            param <- ScanBamParam(flag = scanBamFlag(isUnmappedQuery=FALSE))
            count01 <- countBam(bamFile01, param = param)\$records
            
            # Stage 6: Extract RPM-normalized coverage for the region
            coveragesRPMRegion01 <- coverage(alignments01, weight=1000000/count01)[region]
            coveragesRPMRegion01 <- as.numeric(coveragesRPMRegion01[[chr_name]])
            
            coveragesRPMRegion02 <- coverage(alignments02, weight=1000000/count01)[region]
            coveragesRPMRegion02 <- as.numeric(coveragesRPMRegion02[[chr_name]])
            
            # Stage 7: Calculate similarity metrics using the similarity function
            # We compare the RPM-normalized profile of the positive strand against the RPM-normalized profile of the negative strand
            metrics <- similarity(coveragesRPMRegion01, 
                                  coveragesRPMRegion02, 
                                  ratioAreaThreshold=5, 
                                  ratioMaxMaxThreshold=2, 
                                  ratioIntersectThreshold=5, 
                                  ratioNormalizedIntersectThreshold=2,
                                  diffPosMaxThresholdMinValue=10, 
                                  diffPosMaxThresholdMaxDiff=100, 
                                  diffPosMaxTolerance=0.01)
            
            # Save the full metrics list as an RDS object
            saveRDS(metrics, "similarity_metrics.rds")
            
            # Format and save the calculated metrics as a CSV table
            metrics_results <- data.frame(
              Metric = names(metrics\$metrics),
              Value = unlist(metrics\$metrics),
              stringsAsFactors = FALSE
            )
            write.csv(metrics_results, "similarity_metrics.csv", row.names = FALSE)
            
            # Generate a PDF plot comparing the two profiles
            pdf("profiles_comparison_plot.pdf", width = 8, height = 6)
            plot(coveragesRPMRegion01, type="l", col="blue", lwd=2,
                 xlab="Genomic Position", ylab="Positive Strand Coverage (RPM)", 
                 main="ChIP-Seq Profiles Comparison (Positive vs Negative Strand)")
            par(new=TRUE)
            plot(coveragesRPMRegion02, type="l", col="darkgreen", lty=2, lwd=2,
                 axes=FALSE, xlab="", ylab="")
            axis(side=4)
            mtext("Negative Strand Coverage (RPM)", side=4, line=3)
            legend("topright", legend=c("Positive Strand (Left Axis)", "Negative Strand (Right Axis)"), 
                   col=c("blue", "darkgreen"), lty=c(1, 2), lwd=2)
            dev.off()

    writeLines(c(
        '"BIOC_SIMILARPEAK_CHIPSEQ_PROFILE_SIMILARITY":',
        paste0('    similaRpeak: ', as.character(packageVersion('similaRpeak')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chipseq_profile_similarity.csv versions.yml
    """
}

workflow BIOC_SIMILARPEAK_CHIPSEQ_PROFILE_SIMILARITY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ align1.bam, region ] ]

    main:
    BIOC_SIMILARPEAK_CHIPSEQ_PROFILE_SIMILARITY(ch_input)

    emit:
    tables   = BIOC_SIMILARPEAK_CHIPSEQ_PROFILE_SIMILARITY.out.tables
    plots    = BIOC_SIMILARPEAK_CHIPSEQ_PROFILE_SIMILARITY.out.plots
    objects  = BIOC_SIMILARPEAK_CHIPSEQ_PROFILE_SIMILARITY.out.objects
    versions = BIOC_SIMILARPEAK_CHIPSEQ_PROFILE_SIMILARITY.out.versions
}
