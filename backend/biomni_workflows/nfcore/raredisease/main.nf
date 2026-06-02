// nf-core/raredisease — user-facing parameter stub
// Rare disease analysis: SNV/indel/SV/CNV calling + clinical annotation
//
// Pipeline phases:
// * 1. Input validation — samplesheet QC, pedigree / sex / phenotype check
// * 2. Preprocessing — adapter trimming, FastQC, duplicate marking
// * 3. Alignment — BWA-MEM2, BQSR base quality recalibration
// * 4. Variant calling — GATK HaplotypeCaller SNV/indel, SV (TIDDIT/Manta), CNV (EKLF)
// * 5. Annotation — VEP clinical annotation, CADD, ClinVar, OMIM/HPO ranking
// * 6. Report — MultiQC, ranked VCF, clinical variant report TSV

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
