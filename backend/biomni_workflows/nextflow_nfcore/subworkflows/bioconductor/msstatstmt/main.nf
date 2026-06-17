#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MSstatsTMT — tmt_differential_abundance_analysis
// Preprocess, normalize, summarize, and perform differential abundance testing on TMT proteomics data.
// Input: raw.pd, annotation.pd
// Container: quay.io/biocontainers/bioconductor-msstatstmt:2.18.0--r45hdfd78af_0
// R packages: MSstatsTMT
// Bioconductor: 3.20 | R: 4.4
// Requires: MSstatsTMT
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read user input files from the working directory
//  * 2. [Visualization & Output] Convert raw search engine output and annotation into
//  * 3. [Visualization & Output] Perform protein-level summarization, missing value
//  * 4. [Visualization & Output] Generate diagnostic profile plots
//  * 5. [Visualization & Output] Test for significant changes in protein abundance
//  * 6. [Visualization & Output] Test for significant changes using a custom contrast

nextflow.enable.dsl = 2

process BIOC_MSSTATSTMT_TMT_DIFFERENTIAL_ABUNDANCE_ANALYSIS {
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
    .bm_deps <- c("MSstatsTMT")
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
    
    # Load required package
    library(MSstatsTMT)
    
    # --- Read user input files from the working directory ---
    # raw.pd is typically a tab-separated Proteome Discoverer PSM export
    raw.pd <- read.delim("raw.pd", header = TRUE, sep = "\t", stringsAsFactors = FALSE)
    annotation.pd <- read.csv("annotation.pd", header = TRUE, stringsAsFactors = FALSE)
    
    # --- Convert raw search engine output and annotation into ---
    input.pd <- PDtoMSstatsTMTFormat(raw.pd, annotation.pd, 
                                     which.proteinid = "Protein.Accessions")
    
    # --- Perform protein-level summarization, missing value ---
    quant.msstats <- proteinSummarization(input.pd,
                                          method="msstats",
                                          global_norm=TRUE,
                                          reference_norm=TRUE,
                                          remove_norm_channel = TRUE,
                                          remove_empty_channel = TRUE)
    
    # Save summarization results
    saveRDS(quant.msstats, "quant_msstats.rds")
    if (!is.null(quant.msstats\$ProteinLevelData)) {
      write.csv(quant.msstats\$ProteinLevelData, "quant_msstats_protein_level.csv", row.names = FALSE)
    }
    
    # --- Generate diagnostic profile plots ---
    # This function automatically saves PDF files (e.g., "ProfilePlot.pdf") in the working directory
    dataProcessPlotsTMT(data=quant.msstats,
                         type = 'ProfilePlot',
                         width = 21, # adjust the figure width since there are 15 TMT runs.
                         height = 7)
    
    # --- Test for significant changes in protein abundance ---
    test.pairwise <- groupComparisonTMT(quant.msstats, moderated = TRUE)
    
    # Save pairwise comparison results
    if (!is.null(test.pairwise\$ComparisonResult)) {
      write.csv(test.pairwise\$ComparisonResult, "test_pairwise_results.csv", row.names = FALSE)
    }
    
    # --- Test for significant changes using a custom contrast ---
    # Note: This specific contrast matrix assumes conditions "0.125", "0.5", "0.667", and "1" are present.
    # We wrap this in a tryCatch block to ensure the pipeline remains robust if the user's annotation
    # contains different condition names, while strictly preserving the documented code.
    tryCatch({
      comparison<-matrix(c(-1,0,0,1),nrow=1)
      row.names(comparison)<-"1-0.125"
      colnames(comparison)<- c("0.125", "0.5", "0.667", "1")
    
      test.contrast <- groupComparisonTMT(data = quant.msstats, contrast.matrix = comparison, moderated = TRUE)
      
      if (!is.null(test.contrast\$ComparisonResult)) {
        write.csv(test.contrast\$ComparisonResult, "test_contrast_results.csv", row.names = FALSE)
      }
    }, error = function(e) {
      warning("Custom contrast comparison could not be completed. Check if condition names match '0.125', '0.5', '0.667', '1'. Error: ", e\$message)
    })

    writeLines(c(
        '"BIOC_MSSTATSTMT_TMT_DIFFERENTIAL_ABUNDANCE_ANALYSIS":',
        paste0('    MSstatsTMT: ', as.character(packageVersion('MSstatsTMT')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tmt_differential_abundance_analysis.csv versions.yml
    """
}

workflow BIOC_MSSTATSTMT_TMT_DIFFERENTIAL_ABUNDANCE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ raw.pd, annotation.pd ] ]

    main:
    BIOC_MSSTATSTMT_TMT_DIFFERENTIAL_ABUNDANCE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MSSTATSTMT_TMT_DIFFERENTIAL_ABUNDANCE_ANALYSIS.out.tables
    plots    = BIOC_MSSTATSTMT_TMT_DIFFERENTIAL_ABUNDANCE_ANALYSIS.out.plots
    objects  = BIOC_MSSTATSTMT_TMT_DIFFERENTIAL_ABUNDANCE_ANALYSIS.out.objects
    versions = BIOC_MSSTATSTMT_TMT_DIFFERENTIAL_ABUNDANCE_ANALYSIS.out.versions
}
