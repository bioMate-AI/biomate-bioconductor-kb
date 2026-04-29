// nf-core/sarek — user-facing parameter stub
// Somatic/germline variant calling: WGS/WES → trimming → alignment → variant calling → annotation

params.input            = null          // Samplesheet CSV (patient,sample,status,fastq_1,fastq_2)
params.genome           = 'GRCh38'      // Reference genome: GRCh38 | GRCh37 | GRCm38
params.tools            = null          // Variant callers: mutect2 | haplotypecaller | strelka | freebayes | deepvariant | cnvkit | manta
params.analysis_type    = 'germline'    // Analysis type: germline | somatic | tumor_only
params.step             = 'mapping'     // Pipeline step: mapping | markduplicates | prepare_recalibration | recalibrate | variant_calling | annotate
params.wes              = false         // Whole exome sequencing mode (uses intervals)
params.intervals        = null          // BED file with target regions for WES
params.genome_coverage  = null          // Target sequencing coverage in X (e.g. 30 | 50 | 100)
params.nucleotides_per_second = 200000  // Genome size estimate for interval splitting
params.no_intervals     = false         // Disable interval splitting (use full genome)
params.skip_tools       = null          // Tools to skip: baserecalibrator | markduplicates | bamqc
params.joint_germline   = false         // Joint germline calling across samples
params.split_fastq      = 50000000      // Split FASTQ at this read count (0 = no split)
params.outdir           = './results'
params.email            = null
params.max_memory       = '128.GB'
params.max_cpus         = 16
params.max_time         = '240.h'
