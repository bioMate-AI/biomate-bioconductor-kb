// nf-core/rnaseq — user-facing parameter stub
// Full pipeline: FASTQ → trimming → alignment → quantification → QC
// These are the parameters users set when launching this workflow.

params.input            = null          // Samplesheet CSV (sample,fastq_1,fastq_2,strandedness)
params.genome           = null          // Reference genome: GRCh38 | GRCm39 | GRCz11 | BDGP6 | Rnor_6.0 | R64-1-1
params.strandedness     = 'auto'        // Library strandedness: reverse | forward | unstranded | auto
params.aligner          = 'star_salmon' // Alignment tool: star_salmon | hisat2 | star_rsem
params.pseudo_aligner   = null          // Pseudo-aligner: salmon | kallisto (skips genome alignment)
params.skip_trimming    = false         // Skip adapter trimming (Trim Galore)
params.skip_fastqc      = false         // Skip FastQC quality control
params.skip_multiqc     = false         // Skip MultiQC report generation
params.umi_discard_read = null          // Discard UMI-tagged reads: 1 | 2
params.save_unaligned   = false         // Save unaligned reads to output
params.outdir           = './results'   // Output directory
params.email            = null          // Email for completion notification
params.max_memory       = '128.GB'      // Maximum memory per process
params.max_cpus         = 16            // Maximum CPUs per process
params.max_time         = '240.h'       // Maximum wall time per process
