#!/usr/bin/env nextflow
/*
 * transcriptomics/ont_rnaseq
 *
 * Long-read RNA-seq analysis for Oxford Nanopore (ONT) direct-RNA / cDNA reads.
 * Splice-aware alignment with minimap2, transcript discovery + isoform-level
 * quantification with bambu (long-read aware), and a per-sample read/alignment
 * QC summary. This is the pipeline behind the cold-start ability
 * "Long-read RNA-seq with Oxford Nanopore data" (previously mis-routed / dead-end).
 *
 * Pipeline Steps:
 * 1. MINIMAP2_ALIGN     -- Splice-aware alignment (minimap2 -ax splice) -> SAM
 * 2. ALIGN_QC           -- samtools sort/index + flagstat read/mapping QC -> BAM + JSON
 * 3. BAMBU_QUANT        -- Long-read transcript discovery + isoform/gene quantification (bambu)
 *
 * Outputs:
 *   <sample>.sorted.bam(.bai)   -- Splice-aware alignment
 *   <sample>.align_qc.json      -- Mapping-rate / read-count QC per sample
 *   counts_transcript.txt       -- Isoform-level counts (bambu)
 *   counts_gene.txt             -- Gene-level counts (bambu)
 *   extended_annotations.gtf    -- Discovered + reference transcripts (bambu)
 *   ont_rnaseq_summary.json     -- Aggregate QC / run summary for the gate monitor
 *
 * Real tools + real containers (per-process biocontainers, repo convention):
 *   minimap2 2.28  quay.io/biocontainers/minimap2:2.28--h577a1d6_4
 *   samtools 1.21  quay.io/biocontainers/samtools:1.21--h96c455f_1
 *   bambu 3.12.1   quay.io/biocontainers/bioconductor-bambu:3.12.1--r45ha27e39d_1
 *                  (same tag as the sibling bioconductor/bambu workflow)
 *
 * Honest-failure contract:
 *   Every process calls a real tool. There are NO stub / synthetic outputs.
 *   Missing FASTA/GTF (required by bambu) -> the workflow errors before launch.
 *
 * References:
 *   minimap2: Li H. Bioinformatics 2018, 34(18):3094-3100. doi:10.1093/bioinformatics/bty191
 *   bambu:    Chen Y. et al. Nat Commun 2023, 14:1934. doi:10.1038/s41467-023-37440-w
 */

nextflow.enable.dsl = 2

// ============================================================================
// Parameters
// ============================================================================

params.input                = null          // Samplesheet CSV: sample,fastq[,condition]
params.fasta                = null          // Reference genome FASTA (required)
params.gtf                  = null          // Reference annotation GTF (required by bambu)

// minimap2 long-read preset
params.mm2_preset           = 'splice'      // -ax preset for cDNA/direct-RNA ONT reads
params.mm2_kmer             = 14            // -k ; 14 is the ONT/splice default
params.mm2_extra            = ''            // extra minimap2 args (e.g. '-uf' for direct-RNA fwd)

// bambu options
params.quant_only           = false         // true -> quantify only vs reference (no discovery)

params.outdir               = './results/ont_rnaseq'
params.publish_dir_mode     = 'copy'
params.max_memory           = '32.GB'
params.max_cpus             = 8
params.max_time             = '24.h'

// ============================================================================
// Processes
// ============================================================================

process MINIMAP2_ALIGN {
    tag "${meta.id}"
    label 'process_medium'
    container 'quay.io/biocontainers/minimap2:2.28--h577a1d6_4'
    publishDir "${params.outdir}/alignments", mode: params.publish_dir_mode

    input:
    tuple val(meta), path(reads)
    path fasta

    output:
    tuple val(meta), path("${meta.id}.sam"), emit: sam

    script:
    """
    # Splice-aware long-read alignment. minimap2 -a -x splice emits SAM;
    # sorting/indexing is done in the samtools-backed ALIGN_QC step.
    minimap2 \\
        -a -x ${params.mm2_preset} \\
        -k ${params.mm2_kmer} \\
        -t ${task.cpus} \\
        ${params.mm2_extra} \\
        ${fasta} \\
        ${reads} \\
        > ${meta.id}.sam
    """
}

process ALIGN_QC {
    tag "${meta.id}"
    label 'process_low'
    container 'quay.io/biocontainers/samtools:1.21--h96c455f_1'
    publishDir "${params.outdir}/alignments", mode: params.publish_dir_mode

    input:
    tuple val(meta), path(sam)

    output:
    tuple val(meta), path("${meta.id}.sorted.bam"), path("${meta.id}.sorted.bam.bai"), emit: bam
    tuple val(meta), path("${meta.id}.align_qc.json"),                                  emit: qc

    script:
    """
    samtools sort -@ ${task.cpus} -o ${meta.id}.sorted.bam ${sam}
    samtools index ${meta.id}.sorted.bam
    samtools flagstat ${meta.id}.sorted.bam > ${meta.id}.flagstat.txt

    # Parse flagstat into a small JSON QC record (real numbers from samtools).
    python3 - "${meta.id}" <<'PY'
import json, re, sys
sample = sys.argv[1]
txt = open(sample + ".flagstat.txt").read()
def grab(pat):
    m = re.search(pat, txt)
    return int(m.group(1)) if m else 0
total   = grab(r'(\\d+) \\+ \\d+ in total')
mapped  = grab(r'(\\d+) \\+ \\d+ mapped')
primary = grab(r'(\\d+) \\+ \\d+ primary mapped')
rate = round(100.0 * mapped / total, 2) if total else 0.0
json.dump({
    "sample": sample,
    "total_records": total,
    "mapped_records": mapped,
    "primary_mapped": primary,
    "mapping_rate_pct": rate,
}, open(sample + ".align_qc.json", "w"), indent=2)
PY
    """
}

process BAMBU_QUANT {
    label 'process_medium'
    container 'quay.io/biocontainers/bioconductor-bambu:3.12.1--r45ha27e39d_1'
    publishDir "${params.outdir}/quant", mode: params.publish_dir_mode

    input:
    path bams
    path fasta
    path gtf

    output:
    path "counts_transcript.txt",     emit: transcript_counts
    path "counts_gene.txt",           emit: gene_counts
    path "extended_annotations.gtf",  emit: annotations
    path "ont_rnaseq_summary.json",   emit: summary
    path "versions.yml",              emit: versions

    script:
    def discovery = params.quant_only ? "FALSE" : "TRUE"
    """
    #!/usr/bin/env Rscript
    suppressMessages({ library(bambu); library(jsonlite) })

    bams <- sort(Sys.glob("*.sorted.bam"))
    if (length(bams) == 0L) stop("ont_rnaseq: no sorted BAMs reached BAMBU_QUANT")

    anno <- prepareAnnotations("${gtf}")
    se <- bambu(reads = bams, annotations = anno, genome = "${fasta}",
                discovery = ${discovery}, ncore = ${task.cpus})

    writeBambuOutput(se, path = ".", prefix = "")

    # Normalise bambu's default output names to the workflow's I/O contract.
    norm <- function(pattern, target) {
        if (file.exists(paste0(target, ".gz"))) R.utils::gunzip(paste0(target, ".gz"), overwrite = TRUE)
        if (!file.exists(target)) {
            hit <- list.files(".", pattern = pattern)
            if (length(hit)) file.rename(hit[1], target)
        }
    }
    norm("^counts_transcript", "counts_transcript.txt")
    norm("^counts_gene",       "counts_gene.txt")
    norm("\\\\.gtf\$",          "extended_annotations.gtf")

    n_tx    <- length(rowRanges(se))
    n_novel <- tryCatch(sum(mcols(rowRanges(se))\$novelTranscript, na.rm = TRUE),
                        error = function(e) NA_integer_)
    summ <- list(success = TRUE, n_samples = length(bams),
                 n_transcripts = n_tx, n_novel_transcripts = n_novel,
                 discovery = as.logical(${discovery}))
    writeLines(toJSON(summ, auto_unbox = TRUE, pretty = TRUE), "ont_rnaseq_summary.json")

    writeLines(c('"${task.process}":',
                 paste0('    bambu: ', as.character(packageVersion("bambu")))),
               "versions.yml")
    """
}

// ============================================================================
// Workflow
// ============================================================================

workflow ONT_RNASEQ_WORKFLOW {
    take:
    ch_reads   // channel: [ meta, fastq ]
    fasta      // path
    gtf        // path

    main:
    MINIMAP2_ALIGN(ch_reads, fasta)
    ALIGN_QC(MINIMAP2_ALIGN.out.sam)
    BAMBU_QUANT(
        ALIGN_QC.out.bam.map { it[1] }.collect(),
        fasta,
        gtf
    )

    emit:
    transcript_counts = BAMBU_QUANT.out.transcript_counts
    gene_counts       = BAMBU_QUANT.out.gene_counts
    annotations       = BAMBU_QUANT.out.annotations
    summary           = BAMBU_QUANT.out.summary
    versions          = BAMBU_QUANT.out.versions
}

workflow {
    if (!params.input) error "Please provide --input <samplesheet CSV: sample,fastq[,condition]>"
    if (!params.fasta) error "ont_rnaseq requires --fasta <reference genome FASTA> for minimap2 + bambu"
    if (!params.gtf)   error "ont_rnaseq requires --gtf <reference annotation GTF> for bambu quantification"

    def fasta = file(params.fasta)
    def gtf   = file(params.gtf)

    Channel.fromPath(params.input)
        .splitCsv(header: true)
        .map { row ->
            def meta = [id: row.sample, condition: row.condition ?: 'NA']
            [meta, file(row.fastq)]
        }
        .set { ch_reads }

    ONT_RNASEQ_WORKFLOW(ch_reads, fasta, gtf)
    ONT_RNASEQ_WORKFLOW.out.summary.view { "ONT RNA-seq summary: $it" }
}
