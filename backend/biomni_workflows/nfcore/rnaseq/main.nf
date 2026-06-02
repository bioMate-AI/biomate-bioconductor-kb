// nf-core/rnaseq — user-facing parameter stub
// Full pipeline: FASTQ → trimming → alignment → quantification → QC
// These are the parameters users set when launching this workflow.
//
// Pipeline phases:
// * 1. Input validation — samplesheet QC, FASTQ format check, strandedness detection
// * 2. Trimming & QC — adapter trimming (Trim Galore), FastQC read quality
// * 3. Alignment — STAR / HISAT2 / Salmon pseudo-alignment
// * 4. Quantification — gene/transcript counts (RSEM, Salmon), TPM/FPKM matrix
// * 5. Differential expression — DESeq2 size-factor normalisation, PCA, sample distance
// * 6. Report — MultiQC HTML, counts matrix TSV, alignment statistics

params.input            = null          // Samplesheet CSV (sample,fastq_1,fastq_2,strandedness)
params.genome           = null          // Reference genome: GRCh38 | GRCm39 | GRCz11 | BDGP6 | Rnor_6.0 | R64-1-1
params.strandedness     = 'auto'        // Library strandedness: reverse | forward | unstranded | auto
params.aligner          = 'star_salmon' // Alignment tool: star_salmon | hisat2 | star_rsem
params.pseudo_aligner   = null          // Pseudo-aligner: salmon | kallisto (skips genome alignment)
params.single_end       = false         // Single-end library (false = paired-end)
params.read_length      = null          // Read length in bp (e.g. 75 | 100 | 150)
params.skip_trimming    = false         // Skip adapter trimming (Trim Galore)
params.skip_fastqc      = false         // Skip FastQC quality control
params.skip_multiqc     = false         // Skip MultiQC report generation
params.umi_discard_read = null          // Discard UMI-tagged reads: 1 | 2
params.with_umi         = false         // UMI-based library preparation (true | false)
params.save_unaligned   = false         // Save unaligned reads to output
params.save_trimmed     = false         // Save trimmed FASTQ files to output (true | false)
params.clip_r1          = null          // Clip adapter sequence from R1 reads (e.g. CTGTCTCTTATACACATCT for Nextera XT)
params.clip_r2          = null          // Clip adapter sequence from R2 reads
params.max_reads        = null          // Maximum number of reads per sample (for pilot runs)
params.min_reads        = null          // Minimum reads per UMI group to retain
params.clip_a_tail      = null          // Minimum poly-A tail length to trim (nt, e.g. 10)
params.trim_quality     = null          // Quality cutoff Phred score for adapter trimming (e.g. 20)
params.minlen           = null          // Minimum read length after trimming (bp, discard shorter)
params.gpu_acceleration = null          // Enable GPU acceleration (true | false)
params.outdir           = './results'   // Output directory
params.email            = null          // Email for completion notification
params.max_memory       = '128.GB'      // Maximum memory per process
params.max_cpus         = 16            // Maximum CPUs per process
params.max_time         = '240.h'       // Maximum wall time per process
