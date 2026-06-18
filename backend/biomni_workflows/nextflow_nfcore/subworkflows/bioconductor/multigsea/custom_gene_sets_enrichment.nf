#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: multiGSEA — custom_gene_sets_enrichment
// Format and run single or multi-omics GSEA using custom gene sets (e.g., MSigDB Hallmark) instead of downloaded database pathways.
// Input: hallmark
// Container: quay.io/biocontainers/bioconductor-multigsea:1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: dplyr, multiGSEA
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Retrieve and format custom gene sets from MSigDB using msigdbr
//  * 2. [Core Analysis] Format the custom gene sets into a nested list structure

nextflow.enable.dsl = 2

process BIOC_MULTIGSEA_CUSTOM_GENE_SETS_ENRICHMENT {
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
    .bm_deps <- c("multiGSEA", "dplyr")
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
    library(multiGSEA)
    library(dplyr)
    
    # 1. Retrieve and format custom gene sets from MSigDB (adapted to read from user input)
    # Read the user input file 'hallmark' from the working directory
    if (file.exists("hallmark.rds")) {
      input_data <- readRDS("hallmark.rds")
    } else if (file.exists("hallmark")) {
      input_data <- readRDS("hallmark")
    } else if (file.exists("hallmark.csv")) {
      input_data <- read.csv("hallmark.csv")
    } else {
      stop("Required user input file 'hallmark' (RDS or CSV) not found in the working directory.")
    }
    
    # Format the custom gene sets using the documented pipeline if it is a data frame
    if (is.data.frame(input_data)) {
      hallmark <- input_data %>%
        dplyr::select(gs_name, ensembl_gene) %>%
        dplyr::filter(!is.na(ensembl_gene)) %>%
        unstack(ensembl_gene ~ gs_name)
    } else {
      hallmark <- input_data
    }
    
    # 2. Format the custom gene sets into a nested list structure
    pathways <- list("transcriptome" = hallmark)
    
    # Save the formatted pathways object to an RDS file
    saveRDS(pathways, "custom_pathways.rds")
    
    # Create and save a summary table of the custom pathways
    pathway_summary <- data.frame(
      pathway = names(pathways\$transcriptome),
      gene_count = sapply(pathways\$transcriptome, length)
    )
    write.csv(pathway_summary, "custom_pathways_summary.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_MULTIGSEA_CUSTOM_GENE_SETS_ENRICHMENT":',
        paste0('    multiGSEA: ', as.character(packageVersion('multiGSEA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_gene_sets_enrichment.csv versions.yml
    """
}

workflow BIOC_MULTIGSEA_CUSTOM_GENE_SETS_ENRICHMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ hallmark ] ]

    main:
    BIOC_MULTIGSEA_CUSTOM_GENE_SETS_ENRICHMENT(ch_input)

    emit:
    tables   = BIOC_MULTIGSEA_CUSTOM_GENE_SETS_ENRICHMENT.out.tables
    plots    = BIOC_MULTIGSEA_CUSTOM_GENE_SETS_ENRICHMENT.out.plots
    objects  = BIOC_MULTIGSEA_CUSTOM_GENE_SETS_ENRICHMENT.out.objects
    versions = BIOC_MULTIGSEA_CUSTOM_GENE_SETS_ENRICHMENT.out.versions
}
