#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: qdnaseq — standard_cnv_profiling
// Perform copy number profiling, normalization, segmentation, and calling from raw BAM files.
// Input: tumor.bam, bins
// Container: quay.io/biocontainers/bioconductor-qdnaseq:1.46.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_QDNASEQ_STANDARD_CNV_PROFILING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-qdnaseq:1.46.0--r45hdfd78af_0"

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
    .bm_deps <- c("Rsamtools", "biobase", "qdnaseq")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(QDNAseq)
    library(Rsamtools)
    
    # 1. Load bin annotations
    # Read from the user-provided 'bins' file if it exists, otherwise retrieve default annotations
    if (file.exists("bins")) {
      bins <- tryCatch({
        readRDS("bins")
      }, error = function(e) {
        message("Could not read 'bins' as RDS, falling back to getBinAnnotations.")
        getBinAnnotations(binSize=15)
      })
    } else if (file.exists("bins.rds")) {
      bins <- readRDS("bins.rds")
    } else {
      bins <- getBinAnnotations(binSize=15)
    }
    
    # Ensure the BAM file is indexed
    if (file.exists("tumor.bam") && !file.exists("tumor.bam.bai")) {
      message("Indexing tumor.bam...")
      indexBam("tumor.bam")
    }
    
    # 2. Bin read counts from BAM files
    readCounts <- binReadCounts(bins, bamfiles="tumor.bam")
    
    # Plot raw copy number profile
    pdf("raw_profile.pdf")
    plot(readCounts, logTransform=FALSE, ylim=c(-50, 200))
    highlightFilters(readCounts, logTransform=FALSE, residual=TRUE, blacklist=TRUE)
    dev.off()
    
    # 3. Filter bins
    readCountsFiltered <- applyFilters(readCounts, residual=TRUE, blacklist=TRUE)
    
    # Plot isobar
    pdf("isobar_plot.pdf")
    isobarPlot(readCountsFiltered)
    dev.off()
    
    # 4. Estimate GC and mappability correction
    readCountsFiltered <- estimateCorrection(readCountsFiltered)
    
    # Plot noise
    pdf("noise_plot.pdf")
    noisePlot(readCountsFiltered)
    dev.off()
    
    # 5. Apply correction
    copyNumbers <- correctBins(readCountsFiltered)
    
    # 6. Normalize copy numbers
    copyNumbersNormalized <- normalizeBins(copyNumbers)
    
    # 7. Smooth outliers
    copyNumbersSmooth <- smoothOutlierBins(copyNumbersNormalized)
    
    # Plot smoothed profile
    pdf("smoothed_profile.pdf")
    plot(copyNumbersSmooth)
    dev.off()
    
    # Export smoothed bins
    exportBins(copyNumbersSmooth, file="LGG150.txt")
    exportBins(copyNumbersSmooth, file="LGG150.igv", format="igv")
    exportBins(copyNumbersSmooth, file="LGG150.bed", format="bed")
    
    # 8. Segment bins
    copyNumbersSegmented <- segmentBins(copyNumbersSmooth, transformFun="sqrt")
    
    # 9. Normalize segmented bins
    copyNumbersSegmented <- normalizeSegmentedBins(copyNumbersSegmented)
    
    # Plot segmented profile
    pdf("segmented_profile.pdf")
    plot(copyNumbersSegmented)
    dev.off()
    
    # 10. Call copy number aberrations
    # Fallback to cutoff method if default CGHcall fails (common for single samples)
    copyNumbersCalled <- tryCatch({
      callBins(copyNumbersSegmented)
    }, error = function(e) {
      message("Default CGHcall failed, falling back to cutoff method: ", e\$message)
      callBins(copyNumbersSegmented, method="cutoff")
    })
    
    # Plot called profile
    pdf("called_profile.pdf")
    plot(copyNumbersCalled)
    dev.off()
    
    # Export called bins
    exportBins(copyNumbersCalled, format="vcf")
    exportBins(copyNumbersCalled, format="seg")
    
    # 11. Convert to CGH object
    cgh <- makeCgh(copyNumbersCalled)
    
    # Save final R objects for downstream analysis
    saveRDS(copyNumbersCalled, "copyNumbersCalled.rds")
    saveRDS(cgh, "cgh.rds")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_QDNASEQ_STANDARD_CNV_PROFILING":
        qdnaseq: \$(Rscript -e 'cat(as.character(packageVersion("qdnaseq")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_cnv_profiling.csv versions.yml
    """
}

workflow BIOC_QDNASEQ_STANDARD_CNV_PROFILING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ tumor.bam, bins ] ]

    main:
    BIOC_QDNASEQ_STANDARD_CNV_PROFILING(ch_input)

    emit:
    tables   = BIOC_QDNASEQ_STANDARD_CNV_PROFILING.out.tables
    plots    = BIOC_QDNASEQ_STANDARD_CNV_PROFILING.out.plots
    objects  = BIOC_QDNASEQ_STANDARD_CNV_PROFILING.out.objects
    versions = BIOC_QDNASEQ_STANDARD_CNV_PROFILING.out.versions
}
