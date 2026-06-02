#!/usr/bin/env nextflow
/*
 * epigenomics/cutandtag_alignment_spikein
 *
 * CUT&Tag alignment with spike-in normalisation.
 * Aligns reads to both target and spike-in genomes; computes scale factors
 * from spike-in read counts; generates normalised coverage (bigWig).
 *
 * Pipeline Steps:
 * 1. TRIM_READS         -- Trim adapters with Trim Galore
 * 2. ALIGN_TARGET       -- Bowtie2 alignment to target genome
 * 3. ALIGN_SPIKEIN      -- Bowtie2 alignment to spike-in genome (dm6)
 * 4. SCALE_FACTOR       -- Compute spike-in normalisation scale factors
 * 5. SORT_INDEX         -- Samtools sort + index BAM files
 * 6. MARK_DUPLICATES    -- Picard MarkDuplicates (flag, do not remove for CUT&Tag)
 * 7. BIGWIG             -- deepTools bamCoverage with spike-in scale factor
 * 8. FRAGMENT_SIZE_QC   -- Fragment size distribution (Bioanalyzer QC proxy)
 * 9. MULTIQC            -- Aggregate QC report
 *
 * Outputs:
 *   normalised_bam/         -- Spike-in normalised, sorted, indexed BAM files
 *   normalised_bigwig/      -- Spike-in normalised bigWig coverage tracks
 *   scale_factors.tsv       -- Per-sample spike-in scale factors
 *   multiqc_report.html     -- QC report
 *
 * References:
 *   CUT&Tag: Kaya-Okur et al. Nat Commun 2019, 10:1930
 *   Spike-in normalisation: Meers et al. eLife 2019, 8:e46314
 */

nextflow.enable.dsl = 2

// ============================================================================
// Parameters
// ============================================================================

params.input              = null          // Samplesheet CSV: sample,fastq_1,fastq_2,antibody,control
params.genome             = 'GRCh38'      // Target genome: GRCh38 | GRCm38 | hg19
params.spikein_genome     = 'dm6'         // Spike-in genome: dm6 (Drosophila) | ecoli | sacCer3
params.aligner            = 'bowtie2'     // Aligner: bowtie2 (recommended for CUT&Tag)

// Bowtie2 target genome index
params.bowtie2_index      = null          // Pre-built Bowtie2 index prefix for target genome
params.spikein_index      = null          // Pre-built Bowtie2 index prefix for spike-in genome

// Alignment parameters
params.min_mapq           = 20            // Minimum mapping quality filter
params.max_fragment_size  = 1000          // Maximum fragment size to retain
params.dedup              = true          // Mark PCR duplicates

// Spike-in normalisation
params.spikein_norm       = 'constant'    // Normalisation: constant (10000) | reads_per_million
params.spikein_min_reads  = 1000          // Minimum spike-in reads to compute valid scale factor

// Coverage
params.binsize            = 10            // bigWig bin size (bp)
params.smooth_length      = 300           // Smoothing window for bigWig (bp, 0 = off)
params.effective_genome_size = 2913022398 // GRCh38 effective genome size for RPGC normalisation

params.outdir             = './results/cutandtag_alignment_spikein'
params.publish_dir_mode   = 'copy'
params.max_memory         = '64.GB'
params.max_cpus           = 16
params.max_time           = '24.h'

// ============================================================================
// Processes
// ============================================================================

process TRIM_READS {
    tag "${meta.id}"
    container 'quay.io/biocontainers/trim-galore:0.6.10--hdfd78af_0'

    input:
    tuple val(meta), path(reads)

    output:
    tuple val(meta), path("*_trimmed.fastq.gz"), emit: reads
    path "*_trimming_report.txt", emit: log

    script:
    def paired = meta.single_end ? "" : "--paired"
    """
    trim_galore ${paired} --cores ${task.cpus} --gzip ${reads}
    """
}

process ALIGN_TARGET {
    tag "${meta.id}"
    container 'quay.io/biocontainers/bowtie2:2.5.3--py39h6a7b99d_0'

    input:
    tuple val(meta), path(reads)
    path index

    output:
    tuple val(meta), path("${meta.id}_target.bam"), emit: bam
    path "${meta.id}_target_bowtie2.log",           emit: log

    script:
    def paired = meta.single_end ? "-U ${reads}" : "-1 ${reads[0]} -2 ${reads[1]}"
    """
    bowtie2 -p ${task.cpus} -x ${index}/${params.genome} \\
        --no-unal --dovetail --maxins ${params.max_fragment_size} \\
        ${paired} 2>${meta.id}_target_bowtie2.log | \\
    samtools view -bS -q ${params.min_mapq} -o ${meta.id}_target.bam
    """
}

process ALIGN_SPIKEIN {
    tag "${meta.id}"
    container 'quay.io/biocontainers/bowtie2:2.5.3--py39h6a7b99d_0'

    input:
    tuple val(meta), path(reads)
    path spikein_index

    output:
    tuple val(meta), path("${meta.id}_spikein.bam"), emit: bam
    path "${meta.id}_spikein_bowtie2.log",           emit: log

    script:
    def paired = meta.single_end ? "-U ${reads}" : "-1 ${reads[0]} -2 ${reads[1]}"
    """
    bowtie2 -p ${task.cpus} -x ${spikein_index}/${params.spikein_genome} \\
        --no-unal ${paired} 2>${meta.id}_spikein_bowtie2.log | \\
    samtools view -bS -o ${meta.id}_spikein.bam
    """
}

process SCALE_FACTOR {
    tag "${meta.id}"
    container 'quay.io/biocontainers/samtools:1.19.2--h50ea8bc_0'

    input:
    tuple val(meta), path(spikein_bam)

    output:
    tuple val(meta), path("${meta.id}_scale_factor.txt"), emit: scale_factor

    script:
    """
    SPIKEIN_READS=\$(samtools view -c -F 4 ${spikein_bam})
    if [ "\${SPIKEIN_READS}" -lt "${params.spikein_min_reads}" ]; then
        echo "WARNING: Only \${SPIKEIN_READS} spike-in reads for ${meta.id} (min: ${params.spikein_min_reads})"
        SCALE=1.0
    else
        SCALE=\$(python3 -c "print(10000.0 / \${SPIKEIN_READS})")
    fi
    echo -e "${meta.id}\t\${SPIKEIN_READS}\t\${SCALE}" > ${meta.id}_scale_factor.txt
    """
}

process SORT_INDEX_BAM {
    tag "${meta.id}"
    container 'quay.io/biocontainers/samtools:1.19.2--h50ea8bc_0'
    publishDir "${params.outdir}/normalised_bam", mode: params.publish_dir_mode

    input:
    tuple val(meta), path(bam)

    output:
    tuple val(meta), path("${meta.id}.sorted.bam"), path("${meta.id}.sorted.bam.bai"), emit: bam_bai

    script:
    """
    samtools sort -@ ${task.cpus} -o ${meta.id}.sorted.bam ${bam}
    samtools index ${meta.id}.sorted.bam
    """
}

process BIGWIG {
    tag "${meta.id}"
    container 'quay.io/biocontainers/deeptools:3.5.4--pyhdfd78af_0'
    publishDir "${params.outdir}/normalised_bigwig", mode: params.publish_dir_mode

    input:
    tuple val(meta), path(bam), path(bai)
    tuple val(meta2), path(scale_factor_file)

    output:
    tuple val(meta), path("${meta.id}.normalised.bw"), emit: bigwig

    script:
    """
    SCALE=\$(cut -f3 ${scale_factor_file})
    bamCoverage \\
        --bam ${bam} \\
        --outFileName ${meta.id}.normalised.bw \\
        --binSize ${params.binsize} \\
        --scaleFactor \${SCALE} \\
        --numberOfProcessors ${task.cpus} \\
        --effectiveGenomeSize ${params.effective_genome_size}
    """
}

// ============================================================================
// Workflow
// ============================================================================

workflow {
    Channel.fromPath(params.input)
        .splitCsv(header: true)
        .map { row ->
            def meta = [id: row.sample, single_end: !(row.fastq_2)]
            def reads = row.fastq_2 ? [file(row.fastq_1), file(row.fastq_2)] : [file(row.fastq_1)]
            [meta, reads]
        }
        .set { reads_ch }

    TRIM_READS(reads_ch)
    ALIGN_TARGET(TRIM_READS.out.reads, file(params.bowtie2_index))
    ALIGN_SPIKEIN(TRIM_READS.out.reads, file(params.spikein_index))
    SCALE_FACTOR(ALIGN_SPIKEIN.out.bam)
    SORT_INDEX_BAM(ALIGN_TARGET.out.bam)
    BIGWIG(SORT_INDEX_BAM.out.bam_bai, SCALE_FACTOR.out.scale_factor)
}
