// nf-core/proteomicslfq — user-facing parameter stub
// Label-free quantification proteomics: raw files → identification → quantification → statistics

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
