// nf-core/drop — Detection of RNA Outliers Pipeline
// Aberrant expression detection (OUTRIDER) and aberrant splicing detection (FRASER)
// for RNA-seq-based rare disease diagnosis.
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
