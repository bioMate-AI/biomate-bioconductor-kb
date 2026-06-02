#!/usr/bin/env nextflow
/*
 * transcriptomics/polyaminer_bulk
 *
 * Alternative polyadenylation (APA) analysis from bulk RNA-seq alignments
 * using PolyAMiner-Bulk. Detects differential 3'UTR length changes between
 * conditions by analysing soft-clipped reads at polyadenylation sites.
 *
 * Pipeline Steps:
 * 1. POLYAMINER         -- Identify and quantify APA sites from BAM files
 * 2. FILTER_APA         -- Filter low-confidence APA events (min reads)
 * 3. DIFFERENTIAL_APA   -- Statistical comparison between conditions (PolyAIndex)
 * 4. VISUALISE_APA      -- Read density plots for top differential APA genes
 * 5. SUMMARISE          -- Summary table of differential APA genes + metrics
 *
 * Outputs:
 *   apa_results.tsv          -- Differential APA genes with PolyAIndex metric
 *   utr_length_plots.pdf     -- Read density visualisations for top genes
 *   apa_site_atlas.bed       -- All detected APA sites across samples
 *
 * References:
 *   PolyAMiner-Bulk: Ye et al. Nucleic Acids Research 2023, 51(7):e36
 *   https://doi.org/10.1093/nar/gkad059
 */

nextflow.enable.dsl = 2

// ============================================================================
// Parameters
// ============================================================================

params.input                 = null          // Samplesheet CSV: sample,bam,bai,condition,replicate
params.genome                = 'GRCh38'      // Reference genome: GRCh38 | GRCm38 | hg19 | mm10
params.gtf                   = null          // Gene annotation GTF (required)
params.three_prime_utr_bed   = null          // Pre-computed 3'UTR BED (optional, speeds up run)

// PolyAMiner parameters
params.clustering_mode       = 'softclipped_assisted'  // clustering_mode: softclipped_assisted | peak_based
params.min_reads_per_site    = 5             // Minimum supporting reads per APA site
params.min_usage_change      = 0.1           // Minimum PolyAIndex change |ΔPAI| to call differential APA
params.fdr_threshold         = 0.05          // FDR threshold for differential APA
params.top_genes_plot        = 20            // Number of top differential APA genes to visualise

// Strand awareness
params.strand                = 'RF'          // Library strandedness: RF | FR | unstranded

params.outdir                = './results/polyaminer_bulk'
params.publish_dir_mode      = 'copy'
params.max_memory            = '32.GB'
params.max_cpus              = 8
params.max_time              = '24.h'

// ============================================================================
// Processes
// ============================================================================

process POLYAMINER {
    tag "${meta.id}"
    container 'quay.io/biocontainers/polyaminer:1.1.0--pyhdfd78af_0'
    publishDir "${params.outdir}/apa_sites", mode: params.publish_dir_mode

    input:
    tuple val(meta), path(bam), path(bai)
    path gtf
    path utr_bed

    output:
    tuple val(meta), path("${meta.id}_apa_sites.bed"), emit: apa_sites
    tuple val(meta), path("${meta.id}_site_counts.tsv"), emit: counts

    script:
    def utr_arg = utr_bed ? "--utr_bed ${utr_bed}" : ""
    """
    polyaminer \\
        --bam ${bam} \\
        --gtf ${gtf} \\
        --clustering_mode ${params.clustering_mode} \\
        --min_reads ${params.min_reads_per_site} \\
        --strand ${params.strand} \\
        ${utr_arg} \\
        --output_prefix ${meta.id} \\
        --threads ${task.cpus}
    """
}

process DIFFERENTIAL_APA {
    container 'quay.io/biocontainers/polyaminer:1.1.0--pyhdfd78af_0'
    publishDir "${params.outdir}", mode: params.publish_dir_mode

    input:
    path(counts, stageAs: "counts/*")
    path(samplesheet)

    output:
    path("apa_results.tsv"),   emit: apa_results
    path("apa_site_atlas.bed"),emit: site_atlas

    script:
    """
    polyaminer_diff \\
        --counts counts/ \\
        --samplesheet ${samplesheet} \\
        --min_delta_pai ${params.min_usage_change} \\
        --fdr ${params.fdr_threshold} \\
        --output apa_results.tsv

    # Merge all site BEDs into atlas
    cat counts/*.bed | sort -k1,1 -k2,2n | bedtools merge > apa_site_atlas.bed
    """
}

process VISUALISE_APA {
    container 'quay.io/biocontainers/polyaminer:1.1.0--pyhdfd78af_0'
    publishDir "${params.outdir}", mode: params.publish_dir_mode

    input:
    path(apa_results)
    path(bams, stageAs: "bams/*")
    path(gtf)

    output:
    path("utr_length_plots.pdf"), emit: plots

    script:
    """
    polyaminer_plot \\
        --results ${apa_results} \\
        --bam_dir bams/ \\
        --gtf ${gtf} \\
        --top_n ${params.top_genes_plot} \\
        --output utr_length_plots.pdf
    """
}

// ============================================================================
// Workflow
// ============================================================================

workflow {
    def samplesheet = file(params.input)
    def gtf         = file(params.gtf)
    def utr_bed     = params.three_prime_utr_bed ? file(params.three_prime_utr_bed) : []

    Channel.fromPath(params.input)
        .splitCsv(header: true)
        .map { row ->
            def meta = [id: row.sample, condition: row.condition]
            [meta, file(row.bam), file(row.bai)]
        }
        .set { bam_ch }

    POLYAMINER(bam_ch, gtf, utr_bed)

    DIFFERENTIAL_APA(
        POLYAMINER.out.counts.map { it[1] }.collect(),
        samplesheet
    )

    VISUALISE_APA(
        DIFFERENTIAL_APA.out.apa_results,
        bam_ch.map { it[1] }.collect(),
        gtf
    )
}
