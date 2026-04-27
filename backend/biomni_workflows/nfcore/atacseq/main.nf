// nf-core/atacseq — user-facing parameter stub
// ATAC-seq: FASTQ → trimming → alignment → peak calling → annotation → QC

params.input            = null          // Samplesheet CSV (sample,fastq_1,fastq_2,replicate)
params.genome           = null          // Reference genome: GRCh38 | GRCm39 | GRCm38 | BDGP6
params.macs_gsize       = null          // MACS2 genome size: hs | mm | ce | dm (or numeric)
params.narrow_peak      = false         // Call narrow peaks (default: broad peaks for ATAC)
params.skip_peak_qc     = false         // Skip peak QC with deepTools
params.skip_ataqv       = false         // Skip ataqv QC
params.skip_preseq      = true          // Skip library complexity (preseq)
params.min_trimmed_reads = 10000        // Minimum reads after trimming
params.read_length      = null          // Read length for fragment calculation
params.fragment_size    = 200           // Expected fragment size for single-end
params.outdir           = './results'
params.email            = null
params.max_memory       = '128.GB'
params.max_cpus         = 16
params.max_time         = '240.h'
