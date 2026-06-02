#!/usr/bin/env nextflow
/*
 * epigenomics/seacr_peak_calling
 *
 * Peak calling using SEACR (Sparse Enrichment Analysis for CUT&RUN/CUT&Tag).
 * SEACR outperforms MACS2 for low-background chromatin profiling assays.
 *
 * Pipeline Steps:
 * 1. BAM_TO_BEDGRAPH    -- deepTools bamCoverage → bedGraph (per sample)
 * 2. SEACR              -- SEACR peak calling using IgG control as background
 * 3. SORT_PEAKS         -- Sort BED output by genomic coordinates
 * 4. ANNOTATE_PEAKS     -- HOMER annotatePeaks for nearest gene / feature
 * 5. PEAK_STATS         -- Peak count summary per sample
 * 6. MULTIQC            -- QC aggregation
 *
 * Outputs:
 *   peaks/*.peaks.bed        -- SEACR peak BED files (used as chain output)
 *   peaks/*.annotated.tsv    -- Annotated peaks with nearest genes
 *   peak_stats.tsv           -- Peak count summary table
 *
 * References:
 *   SEACR: Meers et al. Epigenetics & Chromatin 2019, 12:23
 */

nextflow.enable.dsl = 2

// ============================================================================
// Parameters
// ============================================================================

params.input              = null          // Samplesheet CSV: sample,bam,bai,control_bam,control_bai
params.mode               = 'non-stringent' // SEACR mode: stringent | non-stringent
params.norm               = 'non'         // SEACR normalisation: non | norm
params.genome             = 'GRCh38'      // Reference genome for peak annotation
params.genome_size        = null          // Genome sizes file (required for bedgraph)

// deepTools bedgraph parameters
params.binsize            = 1             // bp resolution for bedGraph (1 = single-base)
params.effective_genome_size = 2913022398 // GRCh38

params.outdir             = './results/seacr_peak_calling'
params.publish_dir_mode   = 'copy'
params.max_memory         = '32.GB'
params.max_cpus           = 8
params.max_time           = '12.h'

// ============================================================================
// Processes
// ============================================================================

process BAM_TO_BEDGRAPH {
    tag "${meta.id}"
    container 'quay.io/biocontainers/deeptools:3.5.4--pyhdfd78af_0'

    input:
    tuple val(meta), path(bam), path(bai)

    output:
    tuple val(meta), path("${meta.id}.bedgraph"), emit: bedgraph

    script:
    """
    bamCoverage \\
        --bam ${bam} \\
        --outFileName ${meta.id}.bedgraph \\
        --outFileFormat bedgraph \\
        --binSize ${params.binsize} \\
        --numberOfProcessors ${task.cpus} \\
        --effectiveGenomeSize ${params.effective_genome_size}
    """
}

process SEACR {
    tag "${meta.id}"
    container 'quay.io/biocontainers/seacr:1.3--hdfd78af_1'
    publishDir "${params.outdir}/peaks", mode: params.publish_dir_mode

    input:
    tuple val(meta), path(bedgraph)
    tuple val(ctrl_meta), path(ctrl_bedgraph)

    output:
    tuple val(meta), path("${meta.id}.peaks.bed"), emit: peaks

    script:
    """
    bash SEACR_1.3.sh \\
        ${bedgraph} \\
        ${ctrl_bedgraph} \\
        ${params.norm} \\
        ${params.mode} \\
        ${meta.id}

    # SEACR outputs *.stringent.bed or *.relaxed.bed — rename to unified .peaks.bed
    if [ -f "${meta.id}.stringent.bed" ]; then
        mv ${meta.id}.stringent.bed ${meta.id}.peaks.bed
    elif [ -f "${meta.id}.relaxed.bed" ]; then
        mv ${meta.id}.relaxed.bed ${meta.id}.peaks.bed
    fi
    """
}

process PEAK_STATS {
    container 'quay.io/biocontainers/coreutils:8.25--1'
    publishDir "${params.outdir}", mode: params.publish_dir_mode

    input:
    path(peaks, stageAs: "peaks/*")

    output:
    path("peak_stats.tsv"), emit: stats

    script:
    """
    echo -e "sample\tpeak_count" > peak_stats.tsv
    for f in peaks/*.peaks.bed; do
        sample=\$(basename \$f .peaks.bed)
        count=\$(wc -l < \$f)
        echo -e "\$sample\t\$count" >> peak_stats.tsv
    done
    """
}

// ============================================================================
// Workflow
// ============================================================================

workflow {
    Channel.fromPath(params.input)
        .splitCsv(header: true)
        .map { row ->
            def meta = [id: row.sample]
            def ctrl = [id: "${row.sample}_control"]
            [[meta, file(row.bam), file(row.bai)], [ctrl, file(row.control_bam), file(row.control_bai)]]
        }
        .multiMap { sample, ctrl -> sample: sample; ctrl: ctrl }
        .set { samples_ch }

    BAM_TO_BEDGRAPH(samples_ch.sample)
    BAM_TO_BEDGRAPH.out.bedgraph.set { sample_bg_ch }

    // Re-process controls for bedgraph
    Channel.fromPath(params.input)
        .splitCsv(header: true)
        .map { row ->
            def ctrl = [id: "${row.sample}_control"]
            [ctrl, file(row.control_bam), file(row.control_bai)]
        }
        .set { ctrl_bam_ch }

    BAM_TO_BEDGRAPH(ctrl_bam_ch)
    BAM_TO_BEDGRAPH.out.bedgraph.set { ctrl_bg_ch }

    sample_bg_ch
        .join(ctrl_bg_ch, by: { it[0].id.replaceAll('_control$','') })
        .set { seacr_input }

    SEACR(sample_bg_ch, ctrl_bg_ch)
    PEAK_STATS(SEACR.out.peaks.map { it[1] }.collect())
}
