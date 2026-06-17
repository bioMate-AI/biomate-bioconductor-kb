#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: fenr — fast_functional_enrichment
// Perform rapid functional enrichment analysis on a selected set of genes against a background set using fetched Gene Ontology annotations.
// Input: background_genes.txt, selected_genes.txt
// Container: quay.io/biocontainers/bioconductor-fenr:1.8.1--r45hdfd78af_0
// R packages: fenr, tibble, topGO
// Bioconductor: 3.20 | R: 4.4
// Requires: fenr
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Fetch Gene Ontology terms and gene mappings for the target species using fetch_go
//  * 2. [Input & Preparation] Prepare the fetched terms and mappings for fast enrichment against the background gene set using prepare_for_enrichment
//  * 3. [Core Analysis] Run the rapid functional enrichment test on the selected genes using functional_enrichment

nextflow.enable.dsl = 2

process BIOC_FENR_FAST_FUNCTIONAL_ENRICHMENT {
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
    .bm_deps <- c("fenr", "tibble", "topGO")
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
    library(fenr)
    
    # Read user input files
    background_file <- "background_genes.txt"
    selected_file <- "selected_genes.txt"
    
    if (!file.exists(background_file)) {
      stop(paste("Error: Background genes file not found:", background_file))
    }
    if (!file.exists(selected_file)) {
      stop(paste("Error: Selected genes file not found:", selected_file))
    }
    
    # Read background genes
    exmpl_all <- trimws(readLines(background_file))
    exmpl_all <- exmpl_all[exmpl_all != ""]
    
    # Read selected genes of interest
    exmpl_sel <- trimws(readLines(selected_file))
    exmpl_sel <- exmpl_sel[exmpl_sel != ""]
    
    # 1. Fetch Gene Ontology terms and gene mappings for the target species
    go <- fetch_go(species = "sgd")
    
    # 2. Prepare the fetched terms and mappings for fast enrichment against the background gene set
    go_terms <- prepare_for_enrichment(go\$terms, go\$mapping, exmpl_all, feature_name = "gene_symbol")
    
    # 3. Run the rapid functional enrichment test on the selected genes
    enr <- functional_enrichment(exmpl_all, exmpl_sel, go_terms)
    
    # Write outputs
    write.csv(enr, "enrichment_results.csv", row.names = FALSE)
    saveRDS(go_terms, "go_terms.rds")

    writeLines(c(
        '"BIOC_FENR_FAST_FUNCTIONAL_ENRICHMENT":',
        paste0('    fenr: ', as.character(packageVersion('fenr')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fast_functional_enrichment.csv versions.yml
    """
}

workflow BIOC_FENR_FAST_FUNCTIONAL_ENRICHMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ background_genes.txt, selected_genes.txt ] ]

    main:
    BIOC_FENR_FAST_FUNCTIONAL_ENRICHMENT(ch_input)

    emit:
    tables   = BIOC_FENR_FAST_FUNCTIONAL_ENRICHMENT.out.tables
    plots    = BIOC_FENR_FAST_FUNCTIONAL_ENRICHMENT.out.plots
    objects  = BIOC_FENR_FAST_FUNCTIONAL_ENRICHMENT.out.objects
    versions = BIOC_FENR_FAST_FUNCTIONAL_ENRICHMENT.out.versions
}
