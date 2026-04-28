// nf-core/methylseq — user-facing parameter stub
// Bisulfite/WGBS: FASTQ → trimming → bismark alignment → methylation extraction → QC

params.input            = null          // Samplesheet CSV (sample,fastq_1,fastq_2)
params.genome           = null          // Reference genome: GRCh38 | GRCm39 | GRCm38
params.aligner          = 'bismark'     // Alignment tool: bismark | bismark_hisat | bwameth
params.comprehensive    = false         // Output all contexts (CpG, CHG, CHH)
params.cytosine_report  = false         // Generate genome-wide cytosine report
params.non_directional  = false         // Non-directional library (random priming)
params.skip_trimming    = false         // Skip adapter trimming
params.rrbs             = false         // RRBS mode (reduced representation)
params.pbat             = false         // PBAT (post-bisulfite adapter tagging) mode
params.min_coverage     = 1             // Minimum read coverage for methylation calling
params.ignore_flags     = false         // Ignore SAM flags for methylation extraction
params.outdir           = './results'
params.email            = null
params.max_memory       = '128.GB'
params.max_cpus         = 16
params.max_time         = '240.h'
