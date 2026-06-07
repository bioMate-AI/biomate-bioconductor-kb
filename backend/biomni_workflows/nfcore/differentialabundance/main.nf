// nf-core/differentialabundance — user-facing parameter stub
// Differential abundance: count matrix → normalisation → DE analysis → visualisation

params.input            = null          // Sample metadata CSV (sample, condition, replicate, ...)
params.matrix           = null          // Count matrix (genes × samples TSV/CSV)
params.transcript_length_matrix = null  // Transcript length matrix for TPM (optional)
params.contrasts        = null          // Contrasts CSV (id, variable, reference, target)
params.genome           = null          // Reference genome (for annotation, optional)
params.gtf              = null          // GTF annotation file (for gene info)
params.study_type       = 'rnaseq'      // Assay type: rnaseq | maxquant | affy | metab
params.differential_min_fold_change = 2.0  // Min fold change threshold for volcano plot
params.differential_max_qval = 0.05     // Max adjusted p-value threshold
params.normalisation_method = 'deseq2' // Normalisation: deseq2 | edger | limma
params.save_intermediates   = false    // Save intermediate RDS/RData files for debugging
params.outdir           = './results'
params.email            = null
params.max_memory       = '64.GB'
params.max_cpus         = 8
params.max_time         = '72.h'

// [Input Validation]
process CHECK_SAMPLESHEET {
    label 'process_low'
    script:
    """
    check_samplesheet.py \\
        --input ${params.input} \\
        --matrix ${params.matrix} \\
        --contrasts ${params.contrasts}
    """
}

// [Input Validation]
process CHECK_CONTRASTS {
    label 'process_low'
    script:
    """
    check_contrasts.py \\
        --contrasts ${params.contrasts} \\
        --gtf ${params.gtf} \\
        --genome ${params.genome}
    """
}

// [Normalisation]
process DESEQ2_NORM {
    label 'process_medium'
    script:
    """
    deseq2_norm.R \\
        --matrix ${params.matrix} \\
        --transcript_length_matrix ${params.transcript_length_matrix} \\
        --normalisation_method ${params.normalisation_method} \\
        --study_type ${params.study_type} \\
        ${params.save_intermediates ? '--save_intermediates' : ''} \\
        --outdir ${params.outdir}
    """
}

// [Differential Abundance]
process DESEQ2_DE {
    label 'process_medium'
    script:
    """
    deseq2_de.R \\
        --contrasts ${params.contrasts} \\
        --differential_max_qval ${params.differential_max_qval} \\
        --differential_min_fold_change ${params.differential_min_fold_change} \\
        --outdir ${params.outdir}
    """
}

// [Visualisation & Report]
process PLOT_EXPLORATORY {
    label 'process_low'
    script:
    """
    plot_exploratory.R \\
        --outdir ${params.outdir}
    """
}

// [Visualisation & Report]
process MULTIQC {
    label 'process_low'
    script:
    """
    multiqc . \\
        --outdir ${params.outdir} \\
        ${params.email ? "--email ${params.email}" : ''}
    """
}
