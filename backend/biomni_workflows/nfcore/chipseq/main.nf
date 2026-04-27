// nf-core/chipseq — user-facing parameter stub
// ChIP-seq: FASTQ → alignment → peak calling → annotation → QC

params.input            = null          // Samplesheet CSV (sample,fastq_1,fastq_2,antibody,control)
params.genome           = null          // Reference genome: GRCh38 | GRCm39 | GRCm38 | BDGP6
params.macs_gsize       = null          // MACS2 genome size: hs | mm | ce | dm
params.narrow_peak      = false         // Call narrow peaks (default: broad)
params.skip_peak_qc     = false         // Skip peak QC with deepTools
params.skip_preseq      = true          // Skip library complexity estimation
params.min_trimmed_reads = 10000        // Minimum reads after trimming
params.fragment_size    = 200           // Expected fragment size for SE reads
params.keep_dups        = false         // Keep PCR duplicates
params.outdir           = './results'
params.email            = null
params.max_memory       = '128.GB'
params.max_cpus         = 16
params.max_time         = '240.h'
