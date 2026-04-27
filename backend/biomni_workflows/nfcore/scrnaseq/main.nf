// nf-core/scrnaseq — user-facing parameter stub
// Single-cell RNA-seq: FASTQ → barcode demultiplexing → alignment → count matrix

params.input            = null          // Samplesheet CSV (sample,fastq_1,fastq_2,expected_cells)
params.genome           = null          // Reference genome: GRCh38 | GRCm39
params.protocol         = '10XV3'       // Library protocol: 10XV3 | 10XV2 | 10XV1 | dropseq | chromium
params.aligner          = 'cellranger'  // Aligner: cellranger | alevin | starsolo | kallisto | simpleaf
params.barcode_whitelist = null         // Barcode whitelist (auto-detected for 10X)
params.expected_cells   = 3000         // Expected number of cells per sample
params.skip_emptydrops  = false         // Skip EmptyDrops cell filtering
params.outdir           = './results'
params.email            = null
params.max_memory       = '128.GB'
params.max_cpus         = 16
params.max_time         = '240.h'
