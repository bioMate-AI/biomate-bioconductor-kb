#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GSCA — gsca_enrichment_analysis
// Identify and visualize biological contexts (cell types, tissues, or diseases) enriched with a specific gene set activity pattern.
// Input: genedata.csv, pattern.csv
// Container: quay.io/biocontainers/bioconductor-gsca:2.40.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GSCA
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Format the gene set data and weights into the required three-column data frame structure
//  * 2. [Input & Preparation] Define the target activity pattern and cutoffs in a four-column data frame
//  * 3. [Core Analysis] Run the enrichment search across the selected compendium using GSCA
//  * 4. [Visualization & Output] Visualize the top-ranked biological contexts using GSCAplot

nextflow.enable.dsl = 2

process BIOC_GSCA_GSCA_ENRICHMENT_ANALYSIS {
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
    .bm_deps <- c("GSCA")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        
        # Load the required Bioconductor library
        library(GSCA)
        
        # Read user input files from the working directory
        # genedata.csv must contain columns: gsname, gene (numeric Entrez ID), weight (1 or -1)
        Octgenedata <- read.csv("genedata.csv", stringsAsFactors = FALSE)
        
        # pattern.csv must contain columns: gsname, acttype ("High"/"Low"), cotype ("Norm"/"Quantile"/"Exprs"), cutoff (numeric)
        Octpattern <- read.csv("pattern.csv", stringsAsFactors = FALSE)
        
        # Ensure correct data types for GSCA input requirements
        Octgenedata\$gene <- as.numeric(Octgenedata\$gene)
        Octgenedata\$weight <- as.numeric(Octgenedata\$weight)
        Octpattern\$cutoff <- as.numeric(Octpattern\$cutoff)
        
        # Run the enrichment search across the selected compendium (hgu133a)
        displayoct <- Octoutput <- GSCA(Octgenedata, Octpattern, "hgu133a", Pval.co = 0.05, directory = NULL)
        
        # Save the meaningful results to output files
        # 1. Save the ranking table of biological contexts as a CSV file
        write.csv(Octoutput[[1]], "gsca_results.csv", row.names = FALSE)
        
        # 2. Save the complete GSCA output object as an RDS file
        saveRDS(Octoutput, "gsca_output.rds")
        
        # 3. Visualize the top-ranked biological contexts and save to a PDF file
        GSCAplot(Octoutput, N = 5, plotfile = "gsca_plot.pdf", Title = "GSCA Plot")

    writeLines(c(
        '"BIOC_GSCA_GSCA_ENRICHMENT_ANALYSIS":',
        paste0('    GSCA: ', as.character(packageVersion('GSCA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gsca_enrichment_analysis.csv versions.yml
    """
}

workflow BIOC_GSCA_GSCA_ENRICHMENT_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genedata.csv, pattern.csv ] ]

    main:
    BIOC_GSCA_GSCA_ENRICHMENT_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_GSCA_GSCA_ENRICHMENT_ANALYSIS.out.tables
    plots    = BIOC_GSCA_GSCA_ENRICHMENT_ANALYSIS.out.plots
    objects  = BIOC_GSCA_GSCA_ENRICHMENT_ANALYSIS.out.objects
    versions = BIOC_GSCA_GSCA_ENRICHMENT_ANALYSIS.out.versions
}
