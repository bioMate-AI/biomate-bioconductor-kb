// nf-core/raredisease — user-facing parameter stub
// Rare disease analysis: SNV/indel/SV/CNV calling + clinical annotation

params.input            = null          // Samplesheet CSV (sample,sex,phenotype,paternal_id,maternal_id,fastq_1,fastq_2)
params.genome           = 'GRCh38'      // Reference genome: GRCh38 | GRCh37
params.analysis_type    = 'wgs'         // Analysis type: wgs | wes | panel
params.tools            = null          // Analysis modules: snv | sv | cnv | mobile_elements | methylation
params.skip_tools       = null          // Modules to skip
params.intervals        = null          // BED file for WES/panel capture regions
params.variant_catalog  = null          // STR variant catalog (JSON)
params.cadd_resources   = null          // CADD annotation resources path
params.vcfanno_toml     = null          // vcfanno annotation config
params.rank_results     = true          // Rank variants by OMIM/HPO phenotype relevance
params.vep_cache        = null          // VEP annotation cache directory
params.outdir           = './results'
params.email            = null
params.max_memory       = '128.GB'
params.max_cpus         = 16
params.max_time         = '240.h'
