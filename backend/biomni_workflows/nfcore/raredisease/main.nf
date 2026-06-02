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

// [Input Validation]
process VALIDATE_INPUT {
    script: """
    check_samplesheet.py --input ${params.input} \
        --genome ${params.genome} \
        --analysis_type ${params.analysis_type}
    """
}

// [Preprocessing]
process FASTQC_TRIMGALORE {
    script: """
    trim_galore \
        --outdir ${params.outdir}
    fastqc \
        --outdir ${params.outdir}
    """
}

// [Alignment]
process BWAMEM2_BQSR {
    script: """
    bwa-mem2 mem ${params.genome} \
        --outdir ${params.outdir}
    gatk BaseRecalibrator \
        --reference ${params.genome} \
        ${params.intervals ? "--intervals ${params.intervals}" : ''} \
        --outdir ${params.outdir}
    """
}

// [Variant Calling]
process VARIANT_CALLING {
    script: """
    gatk HaplotypeCaller \
        --reference ${params.genome} \
        ${params.tools ? "--tools ${params.tools}" : ''} \
        ${params.skip_tools ? "--skip_tools ${params.skip_tools}" : ''} \
        ${params.intervals ? "--intervals ${params.intervals}" : ''} \
        ${params.analysis_type == 'wes' ? '--wes' : ''} \
        ${params.variant_catalog ? "--variant_catalog ${params.variant_catalog}" : ''} \
        --outdir ${params.outdir}
    """
}

// [Annotation]
process VEP_ANNOTATE {
    script: """
    vep \
        --genome ${params.genome} \
        ${params.vep_cache ? "--cache ${params.vep_cache}" : ''} \
        ${params.cadd_resources ? "--cadd_resources ${params.cadd_resources}" : ''} \
        ${params.vcfanno_toml ? "--vcfanno_toml ${params.vcfanno_toml}" : ''} \
        ${params.rank_results ? '--rank' : ''} \
        --outdir ${params.outdir}
    """
}

// [Report]
process MULTIQC {
    script: """
    multiqc --outdir ${params.outdir} \
        ${params.email ? "--email ${params.email}" : ''}
    """
}
