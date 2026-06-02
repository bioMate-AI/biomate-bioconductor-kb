// nf-core/drop — Detection of RNA Outliers Pipeline
// Aberrant expression detection (OUTRIDER) and aberrant splicing detection (FRASER)
// for RNA-seq-based rare disease diagnosis.
//
// Pipeline phases:
// * 1. Input validation — sample annotation TSV QC, BAM format check
// * 2. Count matrix — gene expression counting (featureCounts), splice junction extraction
// * 3. OUTRIDER — aberrant expression detection, autoencoder denoising, p-value correction
// * 4. FRASER — aberrant splicing detection, junction filtering, dPSI calculation
// * 5. MAE — monoallelic expression analysis (optional, requires VCF)
// * 6. Report — HTML summary, outlier tables, results TSV
//
// Reference: Mertes et al. Genome Medicine 2021, 13:141
//   https://doi.org/10.1186/s13073-021-00985-8

params.input             = null          // Sample annotation TSV with sample, RNA_BAM_FILE, DROP_GROUP
params.genome            = 'hg38'        // Reference genome: hg38 | hg19 | mm10
params.hpo_file          = null          // HPO terms file (optional, for phenotype matching)
params.gene_annotation   = null          // GTF gene annotation (optional, overrides genome default)

// OUTRIDER (aberrant expression)
params.outrider          = true          // Enable OUTRIDER outlier detection
params.outrider_q_value  = 0.05          // FDR threshold for calling aberrant expression
params.outrider_z_score  = 3.0           // Z-score threshold for expression outliers
params.outrider_min_exp  = 1.0           // Minimum median count to include a gene

// FRASER (aberrant splicing)
params.fraser            = true          // Enable FRASER splicing outlier detection
params.fraser_q_value    = 0.05          // FDR threshold for calling aberrant splicing
params.fraser_dpsi       = 0.1           // Minimum |dPSI| for splicing change
params.fraser_version    = 'FRASER2'     // FRASER | FRASER2 (more specific)

// MAE (monoallelic expression, optional)
params.mae               = false         // Enable monoallelic expression analysis
params.mae_vcf           = null          // VCF file for MAE allele-specific expression

// Output
params.outdir            = './results/drop'
params.publish_dir_mode  = 'copy'
params.email             = null

// Resources
params.max_memory        = '128.GB'
params.max_cpus          = 16
params.max_time          = '96.h'

// [Input Validation]
process VALIDATE_INPUT {
    script: """
    check_sample_annotation.py --input ${params.input} \
        --genome ${params.genome} \
        ${params.gene_annotation ? "--gtf ${params.gene_annotation}" : ''} \
        ${params.hpo_file ? "--hpo ${params.hpo_file}" : ''}
    """
}

// [Count Matrix]
process COUNT_MATRIX {
    script: """
    drop_count_matrix.R \
        --input ${params.input} \
        --genome ${params.genome} \
        ${params.gene_annotation ? "--gtf ${params.gene_annotation}" : ''} \
        --outdir ${params.outdir}
    """
}

// [OUTRIDER]
process OUTRIDER_ANALYSIS {
    script: """
    outrider_run.R \
        ${params.outrider ? '' : '--skip'} \
        --q_value ${params.outrider_q_value} \
        --z_score ${params.outrider_z_score} \
        --min_expression ${params.outrider_min_exp} \
        --outdir ${params.outdir}
    """
}

// [FRASER]
process FRASER_ANALYSIS {
    script: """
    fraser_run.R \
        ${params.fraser ? '' : '--skip'} \
        --q_value ${params.fraser_q_value} \
        --min_dpsi ${params.fraser_dpsi} \
        --version ${params.fraser_version} \
        --outdir ${params.outdir}
    """
}

// [MAE]
process MAE_ANALYSIS {
    script: """
    mae_run.R \
        ${params.mae ? '' : '--skip'} \
        ${params.mae_vcf ? "--vcf ${params.mae_vcf}" : ''} \
        --outdir ${params.outdir}
    """
}

// [Report]
process DROP_REPORT {
    script: """
    drop_report.R \
        --genome ${params.genome} \
        ${params.hpo_file ? "--hpo ${params.hpo_file}" : ''} \
        --outdir ${params.outdir} \
        ${params.email ? "--email ${params.email}" : ''}
    """
}
