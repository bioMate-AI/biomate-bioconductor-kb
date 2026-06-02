#!/usr/bin/env nextflow
/*
 * epigenomics/differential_binding_analysis
 *
 * Differential chromatin binding analysis using DiffBind (DESeq2 or edgeR backend).
 * Takes aligned BAMs and called peaks from CUT&Tag/ChIP-seq experiments and
 * identifies genomic regions with significantly different binding between conditions.
 *
 * Pipeline Steps:
 * 1. DIFFBIND_COUNT     -- Count reads in consensus peak set across all samples
 * 2. DIFFBIND_ANALYSE   -- DESeq2/edgeR statistical testing for differential binding
 * 3. ANNOTATE_DB_PEAKS  -- HOMER annotation of differential peaks
 * 4. VOLCANO_PLOT       -- Volcano plot of fold-change vs significance
 * 5. HEATMAP            -- deepTools plotHeatmap of differential peaks
 *
 * Outputs:
 *   differential_peaks.tsv   -- Differential binding results (FDR, fold-change, coordinates)
 *   volcano_plot.pdf         -- Volcano plot
 *   heatmap.pdf              -- Signal heatmap at differential peaks
 *   consensus_peaks.bed      -- Consensus peak set used for counting
 *
 * References:
 *   DiffBind: Ross-Innes et al. Nature 2012, 481:389-393
 *   DESeq2: Love et al. Genome Biology 2014, 15:550
 */

nextflow.enable.dsl = 2

// ============================================================================
// Parameters
// ============================================================================

params.input              = null          // Samplesheet CSV: sample,bam,bai,peaks,condition,replicate
params.method             = 'DESeq2'      // Statistical method: DESeq2 | edgeR
params.fdr_threshold      = 0.05          // FDR threshold for differential peaks
params.fold_change        = 1.5           // Minimum fold-change (absolute)
params.genome             = 'GRCh38'      // Reference genome for annotation
params.blacklist          = null          // ENCODE blacklist BED (optional)

// DiffBind parameters
params.score              = 'RPKM'        // Peak scoring: RPKM | counts | TMM
params.summits            = 200           // Summit extension (bp) for peak resizing
params.min_overlap        = 2             // Minimum samples a peak must appear in (consensus)

params.outdir             = './results/differential_binding_analysis'
params.publish_dir_mode   = 'copy'
params.max_memory         = '64.GB'
params.max_cpus           = 8
params.max_time           = '24.h'

// ============================================================================
// Processes
// ============================================================================

process DIFFBIND_COUNT {
    container 'quay.io/biocontainers/bioconductor-diffbind:3.12.0--r43hf17093f_0'
    publishDir "${params.outdir}", mode: params.publish_dir_mode, saveAs: { it == "consensus_peaks.bed" ? it : null }

    input:
    path(samplesheet)
    path(bams, stageAs: "bams/*")
    path(bais, stageAs: "bams/*")
    path(peaks, stageAs: "peaks/*")

    output:
    path("diffbind_dba.rds"),    emit: dba_object
    path("consensus_peaks.bed"), emit: consensus_peaks

    script:
    def blacklist_arg = params.blacklist ? ", blacklist='${params.blacklist}'" : ""
    """
    Rscript - <<'REOF'
    library(DiffBind)
    sample_info <- read.csv("${samplesheet}")
    dba <- dba(sampleSheet=sample_info)
    dba <- dba.blacklist(dba, blacklist=DBA_BLACKLIST_HG38${blacklist_arg})
    dba <- dba.count(dba, bUseSummarizeOverlaps=TRUE, score=DBA_SCORE_${params.score},
                     summits=${params.summits}, minOverlap=${params.min_overlap})
    saveRDS(dba, "diffbind_dba.rds")
    consensus <- dba.peakset(dba, bRetrieve=TRUE)
    rtracklayer::export(consensus, "consensus_peaks.bed", format="BED")
    REOF
    """
}

process DIFFBIND_ANALYSE {
    container 'quay.io/biocontainers/bioconductor-diffbind:3.12.0--r43hf17093f_0'
    publishDir "${params.outdir}", mode: params.publish_dir_mode

    input:
    path(dba_object)

    output:
    path("differential_peaks.tsv"), emit: differential_peaks
    path("volcano_plot.pdf"),        emit: volcano_plot
    path("pca_plot.pdf"),            emit: pca_plot

    script:
    """
    Rscript - <<'REOF'
    library(DiffBind)
    library(ggplot2)
    dba <- readRDS("${dba_object}")
    method <- if ("${params.method}" == "DESeq2") DBA_DESEQ2 else DBA_EDGER
    dba <- dba.contrast(dba, minMembers=2)
    dba <- dba.analyze(dba, method=method)

    # Export differential peaks
    db_results <- dba.report(dba, method=method,
                             th=${params.fdr_threshold}, fold=${params.fold_change},
                             bNormalized=TRUE)
    results_df <- as.data.frame(db_results)
    write.table(results_df, "differential_peaks.tsv", sep="\t", quote=FALSE, row.names=FALSE)

    # Volcano plot
    pdf("volcano_plot.pdf", width=8, height=6)
    dba.plotVolcano(dba, method=method)
    dev.off()

    # PCA plot
    pdf("pca_plot.pdf", width=6, height=6)
    dba.plotPCA(dba, method=method, label=DBA_CONDITION)
    dev.off()
    REOF
    """
}

// ============================================================================
// Workflow
// ============================================================================

workflow {
    def samplesheet = file(params.input)
    def bam_ch  = Channel.fromPath(params.input)
        .splitCsv(header: true)
        .map { row -> file(row.bam) }
        .collect()
    def bai_ch  = Channel.fromPath(params.input)
        .splitCsv(header: true)
        .map { row -> file(row.bai) }
        .collect()
    def peak_ch = Channel.fromPath(params.input)
        .splitCsv(header: true)
        .map { row -> file(row.peaks) }
        .collect()

    DIFFBIND_COUNT(samplesheet, bam_ch, bai_ch, peak_ch)
    DIFFBIND_ANALYSE(DIFFBIND_COUNT.out.dba_object)
}
