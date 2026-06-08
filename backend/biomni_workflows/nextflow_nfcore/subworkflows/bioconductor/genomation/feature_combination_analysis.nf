#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: genomation — feature_combination_analysis
// Find combinations of overlapping genomic features (e.g., multiple transcription factor peaks) and visualize their signal.
// Input: tf_peaks_1.broadPeak, tf_peaks_2.broadPeak, aligned_reads.bam
// Container: quay.io/biocontainers/bioconductor-genomation:1.42.0--r45ha27e39d_0
// Requires: GenomicRanges, Rsamtools, genomation
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read multiple peak files into a GRangesList
//  * 2. [Core Analysis] Find combinations of features using findFeatureComb
//  * 3. [Core Analysis] Extract signal over these combinations using ScoreMatrixList
//  * 4. [Visualization & Output] Scale and plot using multiHeatMatrix

nextflow.enable.dsl = 2

process BIOC_GENOMATION_FEATURE_COMBINATION_ANALYSIS {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load required libraries
    library(genomation)
    library(GenomicRanges)
    library(Rsamtools)
    
    # Define sample info matching the user input files
    sampleInfo = read.table(text = "
    fileName\tsampleName
    tf_peaks_1.broadPeak\tTF1
    tf_peaks_2.broadPeak\tTF2
    aligned_reads.bam\tReads
    ", header=TRUE, sep='\t', stringsAsFactors=FALSE)
    
    # 1. Read multiple peak files into a GRangesList
    peak.files = c("tf_peaks_1.broadPeak", "tf_peaks_2.broadPeak")
    peaks = list()
    for(i in 1:length(peak.files)){
      file = peak.files[i]
      name=sampleInfo\$sampleName[match(basename(file),sampleInfo\$fileName)]
      message(name)
      peaks[[name]] = readGeneric(file, meta.col=list(score=5))
    }
    peaks = GRangesList(peaks)
    
    # Filter peaks (robustly choosing chromosome to avoid empty sets if chr21 is not present)
    available_chrs = unique(as.character(unlist(seqnames(peaks))))
    target_chr = if ("chr21" %in% available_chrs) "chr21" else available_chrs[1]
    peaks = peaks[seqnames(peaks) == target_chr & width(peaks) < 1000  & width(peaks) > 100]
    
    # 2. Find combinations of features using findFeatureComb
    tf.comb = findFeatureComb(peaks, width=1000)
    
    tf.comb = tf.comb[order(tf.comb\$class)]
    
    # Ensure BAM file is indexed
    bam.files = "aligned_reads.bam"
    for (bf in bam.files) {
      if (!file.exists(paste0(bf, ".bai")) && !file.exists(sub("\\\\.bam\$", ".bai", bf))) {
        indexBam(bf)
      }
    }
    
    # 3. Extract signal over these combinations using ScoreMatrixList
    sml = ScoreMatrixList(bam.files, tf.comb, bin.num=20, type='bam')
    names(sml) = sampleInfo\$sampleName[match(names(sml),sampleInfo\$fileName)]
    
    # 4. Scale and plot using multiHeatMatrix
    sml.scaled = scaleScoreMatrixList(sml)
    
    # Save outputs
    write.csv(as.data.frame(tf.comb), "tf_combinations.csv", row.names=FALSE)
    saveRDS(sml.scaled, "sml_scaled.rds")
    
    pdf("feature_combination_heatmap.pdf", width=10, height=8)
    multiHeatMatrix(sml.scaled, xcoords=c(-500, 500), col=c('lightgray', 'blue'))
    dev.off()
    
    message("Pipeline completed successfully. Outputs saved to 'tf_combinations.csv', 'sml_scaled.rds', and 'feature_combination_heatmap.pdf'.")

    writeLines(c(
        '"BIOC_GENOMATION_FEATURE_COMBINATION_ANALYSIS":',
        paste0('    genomation: ', as.character(packageVersion('genomation')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_feature_combination_analysis.csv versions.yml
    """
}

workflow BIOC_GENOMATION_FEATURE_COMBINATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ tf_peaks_1.broadPeak, tf_peaks_2.broadPeak, aligned_reads.bam ] ]

    main:
    BIOC_GENOMATION_FEATURE_COMBINATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_GENOMATION_FEATURE_COMBINATION_ANALYSIS.out.tables
    plots    = BIOC_GENOMATION_FEATURE_COMBINATION_ANALYSIS.out.plots
    objects  = BIOC_GENOMATION_FEATURE_COMBINATION_ANALYSIS.out.objects
    versions = BIOC_GENOMATION_FEATURE_COMBINATION_ANALYSIS.out.versions
}
