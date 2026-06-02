// nf-core/proteomicslfq — user-facing parameter stub
// Label-free quantification proteomics: raw files → identification → quantification → statistics
//
// Pipeline phases:
// * 1. Input validation — raw / mzML format check, FASTA database validation
// * 2. Database search — Comet / MSGF+ peptide identification, decoy FDR filtering
// * 3. Quantification — OpenMS feature detection, label-free quantification
// * 4. Statistical analysis — protein-level FDR, differential abundance (MSstats)
// * 5. Report — MultiQC, protein/peptide TSV tables, volcano plot PDF

params.input                = null          // Input files (*.raw, *.mzML, *.mzml)
params.database             = null          // FASTA protein database
params.labeling_reagent     = null          // Isobaric label: TMT16plex | TMT11plex | TMT10plex | TMT6plex | iTRAQ8plex | iTRAQ4plex | none
params.enable_umi           = false         // Enable UMI-based deduplication
params.target_fdr           = 0.01          // Protein/peptide FDR threshold
params.add_decoys           = true          // Add decoy sequences to database
params.search_engines       = 'comet'       // Search engine: comet | msgf
params.run_mass_calibration = true          // Run mass calibration
params.protein_level_fdr_cutoff = 0.05     // Protein-level FDR cutoff
params.ms2_tolerance        = 0.01          // MS2 fragment tolerance in Da
params.precursor_tolerance  = 10            // Precursor mass tolerance in ppm
params.outdir               = './results'
params.email                = null
params.max_memory           = '64.GB'
params.max_cpus             = 8
params.max_time             = '72.h'

// [Input Validation]
process VALIDATE_INPUT {
    script: """
    check_input_files.py \
        --input ${params.input} \
        --database ${params.database}
    """
}

// [Database Search]
process PEPTIDE_IDENTIFICATION {
    script: """
    ${params.search_engines}_search.py \
        --input ${params.input} \
        --database ${params.database} \
        ${params.add_decoys ? '--add_decoys' : ''} \
        --target_fdr ${params.target_fdr} \
        --ms2_tolerance ${params.ms2_tolerance} \
        --precursor_tolerance ${params.precursor_tolerance} \
        ${params.run_mass_calibration ? '--mass_calibration' : ''} \
        --outdir ${params.outdir}
    """
}

// [Quantification]
process LFQ_QUANTIFICATION {
    script: """
    openms_lfq.py \
        ${params.labeling_reagent ? "--labeling_reagent ${params.labeling_reagent}" : ''} \
        ${params.enable_umi ? '--enable_umi' : ''} \
        --target_fdr ${params.target_fdr} \
        --outdir ${params.outdir}
    """
}

// [Statistical Analysis]
process MSSTATS_ANALYSIS {
    script: """
    msstats_analysis.R \
        --protein_fdr ${params.protein_level_fdr_cutoff} \
        ${params.labeling_reagent ? "--labeling_reagent ${params.labeling_reagent}" : ''} \
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
