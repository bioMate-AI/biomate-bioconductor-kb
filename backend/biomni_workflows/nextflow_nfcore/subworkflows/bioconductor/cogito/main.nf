#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Cogito — compare_annotated_genomic_intervals
// Aggregate multi-omics genomic interval data across conditions and generate a comprehensive summary report.
// Input: ranges, organism
// Container: quay.io/biocontainers/bioconductor-cogito:1.16.0--r45hdfd78af_0
// R packages: GenomicFeatures, GenomicRanges, Cogito
// Bioconductor: 3.20 | R: 4.4
// Requires: Cogito, GenomicFeatures, GenomicRanges
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the reference genome TxDb object
//  * 2. [Core Analysis] Combine the genomic interval datasets into a named list
//  * 3. [Core Analysis] Aggregate the genomic intervals to genes using aggregateRanges
//  * 4. [Core Analysis] Inspect and optionally correct the automatically generated configuration lists for technologies and conditions
//  * 5. [Visualization & Output] Generate the summary report, Rmd, and RData files using summarizeRanges

nextflow.enable.dsl = 2

process BIOC_COGITO_COMPARE_ANNOTATED_GENOMIC_INTERVALS {
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
    .bm_deps <- c("GenomicFeatures", "GenomicRanges", "Cogito")
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
    library(Cogito)
    library(GenomicRanges)
    library(GenomicFeatures)
    
    # Read user inputs from the working directory
    ranges <- readRDS("ranges.rds")
    organism <- readRDS("organism.rds")
    
    # Aggregate the genomic intervals to genes using aggregateRanges
    aggregated.ranges <- aggregateRanges(ranges = ranges,
                                         organism = organism,
                                         name = "murine.example")
    
    # Inspect the automatically generated configuration lists
    tech_head <- lapply(aggregated.ranges\$config\$technologies, head, 3)
    cond_head <- head(lapply(aggregated.ranges\$config\$conditions, head, 3), 3)
    
    # Print inspection results to stdout
    print(tech_head)
    print(cond_head)
    
    # Generate the summary report, Rmd, and RData files using summarizeRanges
    summarizeRanges(aggregated.ranges = aggregated.ranges)
    
    # Save meaningful results to output files
    saveRDS(aggregated.ranges, "aggregated_ranges.rds")
    
    # Export aggregated genes as a CSV table
    if (!is.null(aggregated.ranges\$genes)) {
      genes_df <- as.data.frame(aggregated.ranges\$genes)
      write.csv(genes_df, "aggregated_genes.csv", row.names = FALSE)
    }

    writeLines(c(
        '"BIOC_COGITO_COMPARE_ANNOTATED_GENOMIC_INTERVALS":',
        paste0('    Cogito: ', as.character(packageVersion('Cogito')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_compare_annotated_genomic_intervals.csv versions.yml
    """
}

workflow BIOC_COGITO_COMPARE_ANNOTATED_GENOMIC_INTERVALS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ranges, organism ] ]

    main:
    BIOC_COGITO_COMPARE_ANNOTATED_GENOMIC_INTERVALS(ch_input)

    emit:
    tables   = BIOC_COGITO_COMPARE_ANNOTATED_GENOMIC_INTERVALS.out.tables
    plots    = BIOC_COGITO_COMPARE_ANNOTATED_GENOMIC_INTERVALS.out.plots
    objects  = BIOC_COGITO_COMPARE_ANNOTATED_GENOMIC_INTERVALS.out.objects
    versions = BIOC_COGITO_COMPARE_ANNOTATED_GENOMIC_INTERVALS.out.versions
}
