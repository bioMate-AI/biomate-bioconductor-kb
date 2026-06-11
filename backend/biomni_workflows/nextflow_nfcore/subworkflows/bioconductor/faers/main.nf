#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: faers — faers_pharmacovigilance_analysis
// Download, preprocess, standardize, de-duplicate, and perform pharmacovigilance signal detection on FAERS quarterly data.
// Input: faers_ascii_2004q1.zip, standardized_data.rds
// Container: quay.io/biocontainers/bioconductor-faers:1.6.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, data.table, faers
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Check FAERS metadata using faers_meta()
//  * 2. [Input & Preparation] Download and parse quarterly data files using faers()
//  * 3. [Core Analysis] Retrieve specific field data using faers_get()
//  * 4. [Core Analysis] Standardize terminology with MedDRA using faers_standardize()
//  * 5. [Core Analysis] Retrieve MedDRA hierarchy information using faers_meddra()
//  * 6. [Visualization & Output] De-duplicate reports using faers_dedup()
//  * 7. [Core Analysis] Filter for drugs of interest (e.g., insulin) using fda_drugs() and faers_filter()
//  * 8. [Core Analysis] Perform pharmacovigilance signal analysis using faers_phv_signal()

nextflow.enable.dsl = 2

process BIOC_FAERS_FAERS_PHARMACOVIGILANCE_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(faers)
    library(BiocParallel)
    library(data.table)
    
    # Ensure the input ZIP file is named correctly for the package's expectations.
    # The package expects 'aers_ascii_2004q1.zip' for the 2004 Q1 ASCII dataset.
    if (file.exists("faers_ascii_2004q1.zip") && !file.exists("aers_ascii_2004q1.zip")) {
        file.copy("faers_ascii_2004q1.zip", "aers_ascii_2004q1.zip")
    }
    
    # 1. Check FAERS metadata
    faers_meta(internal = TRUE)
    
    # 2. Download and parse quarterly data files
    data1 <- faers(2004, "q1",
        dir = ".",
        compress_dir = tempdir()
    )
    data1
    
    # Since only 2004 Q1 is provided in the user input, we adapt the combined dataset step
    # to use the available 2004 Q1 data.
    data2 <- faers(2004, "q1",
        dir = ".",
        compress_dir = tempdir()
    )
    data2
    
    # 3. Retrieve specific field data
    faers_get(data2, "demo")
    
    # 4. Standardize terminology (using the provided standardized RDS file)
    data <- readRDS("standardized_data.rds")
    data
    
    # 5. Retrieve MedDRA hierarchy information
    faers_meddra(data)
    faers_meddra(data, use = "hierarchy")
    faers_get(data, "indi")
    faers_get(data, "reac")
    
    # 6. De-duplicate reports
    data <- faers_dedup(data)
    data
    
    # 7. Filter for drugs of interest (insulin)
    insulin_names <- "insulin"
    insulin_pattern <- paste(insulin_names, collapse = "|")
    fda_insulin <- fda_drugs()[
        grepl(insulin_pattern, ActiveIngredient, ignore.case = TRUE)
    ]
    insulin_pattern <- paste0(
        unique(tolower(c(insulin_names, fda_insulin\$DrugName))),
        collapse = "|"
    )
    insulin_data <- faers_filter(data, .fn = function(x) {
        idx <- grepl(insulin_pattern, x\$drugname, ignore.case = TRUE) |
            grepl(insulin_pattern, x\$prod_ai, ignore.case = TRUE)
        x[idx, primaryid]
    }, .field = "drug")
    insulin_data
    
    # 8. Perform pharmacovigilance signal analysis
    insulin_signals <- faers_phv_signal(insulin_data,
        .full = data,
        BPPARAM = BiocParallel::SerialParam(RNGseed = 1L)
    )
    insulin_signals
    
    insulin_signals_hlgt <- faers_phv_signal(
        insulin_data,
        .events = "hlgt_name", .full = data,
        BPPARAM = BiocParallel::SerialParam(RNGseed = 1L)
    )
    insulin_signals_hlgt
    
    # 9. Write output files
    demo_data <- faers_get(data2, "demo")
    data.table::fwrite(demo_data, "demo_data.csv")
    
    meddra_hier <- faers_meddra(data, use = "hierarchy")
    data.table::fwrite(meddra_hier, "meddra_hierarchy.csv")
    
    indi_data <- faers_get(data, "indi")
    data.table::fwrite(indi_data, "indi_data.csv")
    
    reac_data <- faers_get(data, "reac")
    data.table::fwrite(reac_data, "reac_data.csv")
    
    saveRDS(data, "deduplicated_data.rds")
    
    data.table::fwrite(insulin_signals, "insulin_signals.csv")
    data.table::fwrite(insulin_signals_hlgt, "insulin_signals_hlgt.csv")

    writeLines(c(
        '"BIOC_FAERS_FAERS_PHARMACOVIGILANCE_ANALYSIS":',
        paste0('    faers: ', as.character(packageVersion('faers')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_faers_pharmacovigilance_analysis.csv versions.yml
    """
}

workflow BIOC_FAERS_FAERS_PHARMACOVIGILANCE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ faers_ascii_2004q1.zip, standardized_data.rds ] ]

    main:
    BIOC_FAERS_FAERS_PHARMACOVIGILANCE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_FAERS_FAERS_PHARMACOVIGILANCE_ANALYSIS.out.tables
    plots    = BIOC_FAERS_FAERS_PHARMACOVIGILANCE_ANALYSIS.out.plots
    objects  = BIOC_FAERS_FAERS_PHARMACOVIGILANCE_ANALYSIS.out.objects
    versions = BIOC_FAERS_FAERS_PHARMACOVIGILANCE_ANALYSIS.out.versions
}
