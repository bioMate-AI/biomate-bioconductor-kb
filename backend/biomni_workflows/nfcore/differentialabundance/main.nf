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
params.outdir           = './results'
params.email            = null
params.max_memory       = '64.GB'
params.max_cpus         = 8
params.max_time         = '72.h'
