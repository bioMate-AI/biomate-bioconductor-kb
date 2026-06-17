#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: tLOH — spatial_loh_analysis
// Import spatial transcriptomics VCF data, calculate Bayes factors for LOH, and generate visualization plots.
// Input: Example.vcf
// Container: quay.io/biocontainers/bioconductor-tloh:1.18.0--r45hdfd78af_0
// R packages: GenomicRanges, VariantAnnotation, dplyr, purrr, tLOH
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, VariantAnnotation, dplyr, purrr, tLOH
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Import VCF data using tLOHDataImport
//  * 2. [Core Analysis] Perform Bayes calculations using tLOHCalc
//  * 3. [Visualization & Output] Generate allele frequency plots using alleleFrequencyPlot
//  * 4. [Visualization & Output] Generate aggregate chromosome plots using aggregateCHRPlot

nextflow.enable.dsl = 2

process BIOC_TLOH_SPATIAL_LOH_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("GenomicRanges", "VariantAnnotation", "dplyr", "purrr", "tLOH")
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
        library(tLOH)
        library(VariantAnnotation)
        library(GenomicRanges)
        library(dplyr)
        library(purrr)
        
        # 1. Import VCF data using tLOHDataImport
        # The input file 'Example.vcf' must be decompressed and present in the working directory.
        humanGBMsampleAC <- tLOHDataImport('Example.vcf')
        
        # 2. Perform Bayes calculations using tLOHCalc
        df <- tLOHCalc(humanGBMsampleAC)
        
        # Save the calculation results
        write.csv(df, "tLOH_results.csv", row.names = FALSE)
        saveRDS(df, "tLOH_results.rds")
        
        # 3. Generate allele frequency plots using alleleFrequencyPlot
        pdf("allele_frequency_plot.pdf", width = 11, height = 8.5)
        print(alleleFrequencyPlot(df, "Example"))
        dev.off()
        
        # 4. Generate aggregate chromosome plots using aggregateCHRPlot
        pdf("aggregate_chr_plot.pdf", width = 11, height = 8.5)
        print(aggregateCHRPlot(df, "Example"))
        dev.off()

    writeLines(c(
        '"BIOC_TLOH_SPATIAL_LOH_ANALYSIS":',
        paste0('    tLOH: ', as.character(packageVersion('tLOH')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spatial_loh_analysis.csv versions.yml
    """
}

workflow BIOC_TLOH_SPATIAL_LOH_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Example.vcf ] ]

    main:
    BIOC_TLOH_SPATIAL_LOH_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_TLOH_SPATIAL_LOH_ANALYSIS.out.tables
    plots    = BIOC_TLOH_SPATIAL_LOH_ANALYSIS.out.plots
    objects  = BIOC_TLOH_SPATIAL_LOH_ANALYSIS.out.objects
    versions = BIOC_TLOH_SPATIAL_LOH_ANALYSIS.out.versions
}
