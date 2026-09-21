#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: faers — faers_pharmacovigilance_analysis
// Download, preprocess, standardize, de-duplicate, and perform pharmacovigilance signal detection on FAERS quarterly data.
// Params: faers_year (default 2004), faers_quarter (default q1), drug_substance (default insulin)
// Input: faers_ascii_<year><quarter>.zip (default faers_ascii_2004q1.zip), standardized_data.rds
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
//  * 7. [Core Analysis] Filter for the drug/substance of interest (params.drug_substance) using fda_drugs() and faers_filter()
//  * 8. [Core Analysis] Perform pharmacovigilance signal analysis using faers_phv_signal()

nextflow.enable.dsl = 2

// [Global] User-facing pharmacovigilance query parameters
params.faers_year    = 2004      // FAERS reporting year (four-digit, e.g. 2004 or 2017)
params.faers_quarter = 'q1'      // FAERS reporting quarter: q1 | q2 | q3 | q4
params.drug_substance = 'insulin' // Drug or active-substance name to detect safety signals for (matched case-insensitively against drugname and prod_ai)

process BIOC_FAERS_FAERS_PHARMACOVIGILANCE_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    publishDir "${params.outdir}", mode: 'copy'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("faers", "BiocParallel", "data.table")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }
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
    
    # User-provided pharmacovigilance query parameters (injected by Nextflow).
    faers_year    <- ${params.faers_year}
    faers_quarter <- tolower("${params.faers_quarter}")
    drug_substance <- "${params.drug_substance}"

    # Ensure the input ZIP file is named correctly for the package's expectations.
    # The package expects 'aers_ascii_<year><quarter>.zip' (e.g. aers_ascii_2004q1.zip).
    expected_zip <- sprintf("aers_ascii_%d%s.zip", faers_year, faers_quarter)
    # Accept either the canonical name or a 'faers_'-prefixed upload, for any year/quarter.
    prefixed_zip <- sprintf("faers_ascii_%d%s.zip", faers_year, faers_quarter)
    if (file.exists(prefixed_zip) && !file.exists(expected_zip)) {
        file.copy(prefixed_zip, expected_zip)
    }

    # 1. Check FAERS metadata
    faers_meta(internal = TRUE)

    # 2. Download and parse quarterly data files for the requested reporting period
    data1 <- faers(faers_year, faers_quarter,
        dir = ".",
        compress_dir = tempdir()
    )
    data1

    # The combined-dataset step uses the same requested period (single quarter provided
    # as workflow input); extend `dir`/period vectors here to combine multiple quarters.
    data2 <- faers(faers_year, faers_quarter,
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
    
    # 7. Filter for the drug / substance of interest (user-provided)
    drug_names <- drug_substance
    drug_pattern <- paste(drug_names, collapse = "|")
    fda_drug <- fda_drugs()[
        grepl(drug_pattern, ActiveIngredient, ignore.case = TRUE)
    ]
    drug_pattern <- paste0(
        unique(tolower(c(drug_names, fda_drug\$DrugName))),
        collapse = "|"
    )
    drug_data <- faers_filter(data, .fn = function(x) {
        idx <- grepl(drug_pattern, x\$drugname, ignore.case = TRUE) |
            grepl(drug_pattern, x\$prod_ai, ignore.case = TRUE)
        x[idx, primaryid]
    }, .field = "drug")
    drug_data

    # 8. Perform pharmacovigilance signal analysis
    drug_signals <- faers_phv_signal(drug_data,
        .full = data,
        BPPARAM = BiocParallel::SerialParam(RNGseed = 1L)
    )
    drug_signals

    drug_signals_hlgt <- faers_phv_signal(
        drug_data,
        .events = "hlgt_name", .full = data,
        BPPARAM = BiocParallel::SerialParam(RNGseed = 1L)
    )
    drug_signals_hlgt
    
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
    
    data.table::fwrite(drug_signals, "drug_signals.csv")
    data.table::fwrite(drug_signals_hlgt, "drug_signals_hlgt.csv")

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
    ch_input  // channel: [ val(meta), [ faers_ascii_<year><quarter>.zip, standardized_data.rds ] ]

    main:
    BIOC_FAERS_FAERS_PHARMACOVIGILANCE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_FAERS_FAERS_PHARMACOVIGILANCE_ANALYSIS.out.tables
    plots    = BIOC_FAERS_FAERS_PHARMACOVIGILANCE_ANALYSIS.out.plots
    objects  = BIOC_FAERS_FAERS_PHARMACOVIGILANCE_ANALYSIS.out.objects
    versions = BIOC_FAERS_FAERS_PHARMACOVIGILANCE_ANALYSIS.out.versions
}
