#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CCPROMISE — gene_level_ccpromise
// Perform CCPROMISE analysis at the gene level to integrate two genomic datasets with multiple phenotypic endpoints.
// Input: exmplGeneSet, exmplESet, exmplMSet, exmplPat
// Container: quay.io/biocontainers/bioconductor-ccpromise:1.36.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, CCPROMISE
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the CCPROMISE package and example datasets
//  * 2. [Core Analysis] Run the CCPROMISE function at the gene level with fast negative binomial permutation
//  * 3. [Core Analysis] Inspect the gene-level PROMISE results

nextflow.enable.dsl = 2

process BIOC_CCPROMISE_GENE_LEVEL_CCPROMISE {
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
    .bm_deps <- c("CCPROMISE", "Biobase")
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
    
    # Load required libraries
    library(CCPROMISE)
    library(Biobase)
    
    # Read user input files from the working directory
    exmplGeneSet <- readRDS("exmplGeneSet.rds")
    exmplESet <- readRDS("exmplESet.rds")
    exmplMSet <- readRDS("exmplMSet.rds")
    exmplPat <- readRDS("exmplPat.rds")
    
    # Run CCPROMISE analysis at the gene level
    test1 <- CCPROMISE(geneSet=exmplGeneSet, 
                  ESet=exmplESet, 
                  MSet=exmplMSet, 
                  promise.pattern=exmplPat,                                            
                  strat.var=NULL,
                  prlbl=c('LC50', 'MRD22', 'EFS', 'PR3'), 
                  EMlbl=c("Expr", "Methyl"), 
                  nbperm=TRUE,
                  max.ntail=10,
                  nperms=100,
                  seed=13)
    
    # Inspect the gene-level PROMISE results
    head(test1\$PRres)
    
    # Write outputs to the working directory
    write.csv(test1\$PRres, file = "gene_level_promise_results.csv", row.names = FALSE)
    saveRDS(test1, file = "ccpromise_results.rds")

    writeLines(c(
        '"BIOC_CCPROMISE_GENE_LEVEL_CCPROMISE":',
        paste0('    CCPROMISE: ', as.character(packageVersion('CCPROMISE')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gene_level_ccpromise.csv versions.yml
    """
}

workflow BIOC_CCPROMISE_GENE_LEVEL_CCPROMISE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ exmplGeneSet, exmplESet, exmplMSet, exmplPat ] ]

    main:
    BIOC_CCPROMISE_GENE_LEVEL_CCPROMISE(ch_input)

    emit:
    tables   = BIOC_CCPROMISE_GENE_LEVEL_CCPROMISE.out.tables
    plots    = BIOC_CCPROMISE_GENE_LEVEL_CCPROMISE.out.plots
    objects  = BIOC_CCPROMISE_GENE_LEVEL_CCPROMISE.out.objects
    versions = BIOC_CCPROMISE_GENE_LEVEL_CCPROMISE.out.versions
}
