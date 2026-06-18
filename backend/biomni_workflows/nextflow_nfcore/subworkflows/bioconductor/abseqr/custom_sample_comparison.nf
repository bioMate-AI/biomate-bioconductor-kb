#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: abseqR — custom_sample_comparison
// Combine and compare specific samples from different sequencing runs or directories using S4 object addition and generate a refined report.
// Input: dataPath, SRR_CTRL, SRR_EXP
// Container: quay.io/biocontainers/bioconductor-abseqr:1.28.0--r45hdfd78af_0
// R packages: abseqR
// Bioconductor: 3.20 | R: 4.4
// Requires: abseqR
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load S4 objects from directories using abseqReport
//  * 2. [Core Analysis] Combine specific samples using the + operator or Reduce
//  * 3. [Visualization & Output] Generate a standalone comparative HTML report using report()

nextflow.enable.dsl = 2

process BIOC_ABSEQR_CUSTOM_SAMPLE_COMPARISON {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("abseqR")
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
        library(abseqR)
        
        # Define user input directories present in the working directory
        dataPath <- "dataPath"
        SRR_CTRL <- "SRR_CTRL"
        SRR_EXP <- "SRR_EXP"
        sandboxDirectory <- "."
        
        # Verify input directories exist before proceeding
        if (!dir.exists(dataPath)) {
            stop(paste("Required input directory 'dataPath' not found in the working directory:", getwd()))
        }
        if (!dir.exists(SRR_CTRL)) {
            stop(paste("Required input directory 'SRR_CTRL' not found in the working directory:", getwd()))
        }
        if (!dir.exists(SRR_EXP)) {
            stop(paste("Required input directory 'SRR_EXP' not found in the working directory:", getwd()))
        }
        
        # 1. Load S4 objects from the first set of abseqPy outputs (dataPath)
        # Using report = 0 for lazy loading of S4 objects without generating full reports immediately
        samples <- abseqReport(dataPath, report = 0)
        
        # 2. Combine specific samples using the + operator and generate a refined report
        if (length(samples) > 1) {
            combined_samples <- samples[[1]] + samples[[2]]
        } else {
            combined_samples <- samples[[1]]
        }
        
        refinedComparison <- report(combined_samples,
                                    outputDir = file.path(sandboxDirectory,
                                                          "refined_comparison"),
                                    report = 3)
        
        # 3. Load control and experimental groups, combine them, and generate a comparative report
        SRRControl <- abseqReport("SRR_CTRL")
        SRRExp <- abseqReport("SRR_EXP")
        all.samples <- Reduce("+", c(SRRControl, SRRExp))
        finalReport <- report(all.samples, outputDir = "SRRControl_vs_SRRExp")
        
        # Save meaningful results as RDS objects for downstream analysis
        saveRDS(refinedComparison, file = "refinedComparison.rds")
        saveRDS(all.samples, file = "all_samples_comparison.rds")
        saveRDS(finalReport, file = "finalReport.rds")

    writeLines(c(
        '"BIOC_ABSEQR_CUSTOM_SAMPLE_COMPARISON":',
        paste0('    abseqR: ', as.character(packageVersion('abseqR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_sample_comparison.csv versions.yml
    """
}

workflow BIOC_ABSEQR_CUSTOM_SAMPLE_COMPARISON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dataPath, SRR_CTRL, SRR_EXP ] ]

    main:
    BIOC_ABSEQR_CUSTOM_SAMPLE_COMPARISON(ch_input)

    emit:
    tables   = BIOC_ABSEQR_CUSTOM_SAMPLE_COMPARISON.out.tables
    plots    = BIOC_ABSEQR_CUSTOM_SAMPLE_COMPARISON.out.plots
    objects  = BIOC_ABSEQR_CUSTOM_SAMPLE_COMPARISON.out.objects
    versions = BIOC_ABSEQR_CUSTOM_SAMPLE_COMPARISON.out.versions
}
