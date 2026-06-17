#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MSstatsConvert — label_free_maxquant_workflow
// Import, clean, preprocess, and balance label-free or SRM mass spectrometry data (e.g., MaxQuant output) for downstream MSstats analysis.
// Input: mq_ev.csv, mq_pg.csv, annotation.csv
// Container: quay.io/biocontainers/bioconductor-msstatsconvert:1.20.0--r45ha27e39d_1
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MSstatsConvert
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Set up logging settings using MSstatsLogsSettings
//  * 2. [Input & Preparation] Import raw files using MSstatsImport
//  * 3. [Core Analysis] Clean the imported data using MSstatsClean
//  * 4. [Input & Preparation] Create annotation using MSstatsMakeAnnotation
//  * 5. [Core Analysis] Preprocess and filter the data using MSstatsPreprocess
//  * 6. [Input & Preparation] Create a balanced design using MSstatsBalancedDesign
//  * 7. [Visualization & Output] Save session info using MSstatsSaveSessionInfo

nextflow.enable.dsl = 2

process BIOC_MSSTATSCONVERT_LABEL_FREE_MAXQUANT_WORKFLOW {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20-slim"

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
    .bm_deps <- c("MSstatsConvert")
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
    
    # Load required library
    library(MSstatsConvert)
    
    # 1. Set up logging settings
    MSstatsLogsSettings(use_log_file = TRUE, append = FALSE) 
    
    # 2. Import raw files from the working directory
    maxquant_evidence = read.csv("mq_ev.csv")
    maxquant_proteins = read.csv("mq_pg.csv")
    
    maxquant_imported = MSstatsImport(list(evidence = maxquant_evidence,
                                           protein_groups = maxquant_proteins),
                                      type = "MSstats", tool = "MaxQuant")
    
    # 3. Clean the imported data
    maxquant_cleaned = MSstatsClean(maxquant_imported, protein_id_col = "Proteins")
    
    # 4. Create annotation using the annotation file in the working directory
    maxquant_annotation = read.csv("annotation.csv")
    maxquant_annotation = MSstatsMakeAnnotation(maxquant_cleaned,
                                                maxquant_annotation,
                                                Run = "Rawfile")
    
    # 5. Preprocess and filter the data
    m_filter = list(col_name = "PeptideSequence", 
                    pattern = "M", 
                    filter = TRUE, 
                    drop_column = FALSE)
    
    oxidation_filter = list(col_name = "Modifications", 
                            pattern = "Oxidation", 
                            filter = TRUE, 
                            drop_column = TRUE)
    
    feature_columns = c("PeptideSequence", "PrecursorCharge")
    
    maxquant_processed = MSstatsPreprocess(
      maxquant_cleaned, 
      maxquant_annotation,
      feature_columns,
      remove_shared_peptides = TRUE, 
      remove_single_feature_proteins = FALSE,
      pattern_filtering = list(oxidation = oxidation_filter,
                               m = m_filter),
      feature_cleaning = list(remove_features_with_few_measurements = TRUE,
                              summarize_multiple_psms = max),
      columns_to_fill = list("FragmentIon" = NA,
                             "ProductCharge" = NA,
                             "IsotopeLabelType" = "L"))
    
    # 6. Create a balanced design
    maxquant_balanced = MSstatsBalancedDesign(maxquant_processed, feature_columns)
    
    # 7. Save session info
    MSstatsSaveSessionInfo()
    
    # Write output files
    write.csv(maxquant_processed, "maxquant_processed.csv", row.names = FALSE)
    write.csv(maxquant_balanced, "maxquant_balanced.csv", row.names = FALSE)
    saveRDS(maxquant_balanced, "maxquant_balanced.rds")

    writeLines(c(
        '"BIOC_MSSTATSCONVERT_LABEL_FREE_MAXQUANT_WORKFLOW":',
        paste0('    MSstatsConvert: ', as.character(packageVersion('MSstatsConvert')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_label_free_maxquant_workflow.csv versions.yml
    """
}

workflow BIOC_MSSTATSCONVERT_LABEL_FREE_MAXQUANT_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mq_ev.csv, mq_pg.csv, annotation.csv ] ]

    main:
    BIOC_MSSTATSCONVERT_LABEL_FREE_MAXQUANT_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_MSSTATSCONVERT_LABEL_FREE_MAXQUANT_WORKFLOW.out.tables
    plots    = BIOC_MSSTATSCONVERT_LABEL_FREE_MAXQUANT_WORKFLOW.out.plots
    objects  = BIOC_MSSTATSCONVERT_LABEL_FREE_MAXQUANT_WORKFLOW.out.objects
    versions = BIOC_MSSTATSCONVERT_LABEL_FREE_MAXQUANT_WORKFLOW.out.versions
}
