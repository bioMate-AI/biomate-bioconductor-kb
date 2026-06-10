#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: nucler — ngs_nucleosome_calling
// Process NGS BAM files to call, score, and plot nucleosome positions.
// Input: cellCycleM_chrII_5000-25000.bam
// Container: quay.io/biocontainers/bioconductor-nucler:2.42.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NUCLER_NGS_NUCLEOSOME_CALLING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-nucler:2.42.0--r45hdfd78af_0"

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
    .bm_deps <- c("genomicranges", "ggplot2", "iranges", "nucler")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(nucleR)
    library(GenomicRanges)
    library(IRanges)
    
    # 1. Import BAM file
    sample.file <- "cellCycleM_chrII_5000-25000.bam"
    reads <- readBAM(sample.file, type="paired")
    
    # 2. Process and trim reads
    # We use the imported 'reads' object instead of the bundled 'nucleosome_htseq' dataset
    reads_pair <- processReads(reads, type="paired", fragmentLen=200)
    reads_trim <- processReads(reads, type="paired", fragmentLen=200, trim=40)
    
    # 3. Calculate normalized coverage
    cover_pair <- coverage.rpm(reads_pair)
    cover_trim <- coverage.rpm(reads_trim)
    
    # 4. Smooth coverage signal
    htseq_raw <- as.vector(cover_trim[[1]])
    htseq_fft <- filterFFT(htseq_raw, pcKeepComp=0.02)
    
    # Set up PDF for plots
    pdf("nucleosome_plots.pdf", width=10, height=6)
    
    # 5. Detect and score peaks (without score)
    peaks <- peakDetection(htseq_fft, threshold="25%", score=FALSE)
    write.csv(data.frame(peak_position=peaks), "peaks_no_score.csv", row.names=FALSE)
    plotPeaks(peaks, htseq_fft, threshold="25%", ylab="coverage")
    
    # 6. Detect and score peaks (with score)
    peaks <- peakDetection(htseq_fft, threshold="25%", score=TRUE)
    write.csv(peaks, "peaks_with_score.csv", row.names=FALSE)
    plotPeaks(peaks, htseq_fft, threshold="25%")
    
    # 7. Detect and score peaks (with score and width)
    peaks <- peakDetection(htseq_fft, threshold="25%", score=TRUE, width=140)
    saveRDS(peaks, "peaks_width140.rds")
    write.csv(as.data.frame(peaks), "peaks_width140.csv", row.names=FALSE)
    plotPeaks(peaks, htseq_fft, threshold="25%")
    
    # Close PDF device
    dev.off()

    cat <<-END_VERSIONS > versions.yml
    "BIOC_NUCLER_NGS_NUCLEOSOME_CALLING":
        nucler: \$(Rscript -e 'cat(as.character(packageVersion("nucler")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ngs_nucleosome_calling.csv versions.yml
    """
}

workflow BIOC_NUCLER_NGS_NUCLEOSOME_CALLING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ cellCycleM_chrII_5000-25000.bam ] ]

    main:
    BIOC_NUCLER_NGS_NUCLEOSOME_CALLING(ch_input)

    emit:
    tables   = BIOC_NUCLER_NGS_NUCLEOSOME_CALLING.out.tables
    plots    = BIOC_NUCLER_NGS_NUCLEOSOME_CALLING.out.plots
    objects  = BIOC_NUCLER_NGS_NUCLEOSOME_CALLING.out.objects
    versions = BIOC_NUCLER_NGS_NUCLEOSOME_CALLING.out.versions
}
