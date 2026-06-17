#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: stageR — differential_gene_expression
// Perform stage-wise testing for differential gene expression with multiple contrasts using the stageR class.
// Input: pScreen, pConfirmation
// Container: quay.io/biocontainers/bioconductor-stager:1.32.0--r45hdfd78af_0
// R packages: Biobase, DEXSeq, edgeR, limma, stageR
// Bioconductor: 3.20 | R: 4.4
// Requires: stageR
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Construct the stageR object using stageR()
//  * 2. [Core Analysis] Perform stage-wise adjustment using stageWiseAdjustment()
//  * 3. [Core Analysis] Retrieve adjusted p-values using getAdjustedPValues()
//  * 4. [Core Analysis] Retrieve binary significance results using getResults()

nextflow.enable.dsl = 2

process BIOC_STAGER_DIFFERENTIAL_GENE_EXPRESSION {
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
    .bm_deps <- c("Biobase", "DEXSeq", "edgeR", "limma", "stageR")
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
        library(stageR)
        
        # Read user input files from the working directory
        # Supports both RDS and CSV formats for robustness
        if (file.exists("pScreen.rds")) {
          pScreen <- readRDS("pScreen.rds")
        } else if (file.exists("pScreen.csv")) {
          tmp_screen <- read.csv("pScreen.csv", row.names = 1, header = TRUE)
          pScreen <- tmp_screen[[1]]
          names(pScreen) <- rownames(tmp_screen)
        } else {
          stop("Error: pScreen file (pScreen.rds or pScreen.csv) not found in the working directory.")
        }
        
        if (file.exists("pConfirmation.rds")) {
          pConfirmation <- readRDS("pConfirmation.rds")
        } else if (file.exists("pConfirmation.csv")) {
          pConfirmation <- as.matrix(read.csv("pConfirmation.csv", row.names = 1, header = TRUE))
        } else {
          stop("Error: pConfirmation file (pConfirmation.rds or pConfirmation.csv) not found in the working directory.")
        }
        
        # Execute the stageR workflow exactly as documented
        stageRObj <- stageR(pScreen=pScreen, pConfirmation=pConfirmation, pScreenAdjusted=FALSE)
        stageRObj <- stageWiseAdjustment(object=stageRObj, method="holm", alpha=0.05)
        head(getAdjustedPValues(stageRObj, onlySignificantGenes=FALSE, order=FALSE))
        head(getAdjustedPValues(stageRObj, onlySignificantGenes=TRUE, order=TRUE))
        res <- getResults(stageRObj)
        
        # Save meaningful results to output files
        write.csv(getAdjustedPValues(stageRObj, onlySignificantGenes=FALSE, order=FALSE), 
                  file = "adjusted_pvalues_all.csv", row.names = TRUE)
        write.csv(getAdjustedPValues(stageRObj, onlySignificantGenes=TRUE, order=TRUE), 
                  file = "adjusted_pvalues_significant.csv", row.names = TRUE)
        write.csv(res, file = "results_matrix.csv", row.names = TRUE)
        saveRDS(stageRObj, file = "stageRObj.rds")

    writeLines(c(
        '"BIOC_STAGER_DIFFERENTIAL_GENE_EXPRESSION":',
        paste0('    stageR: ', as.character(packageVersion('stageR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_gene_expression.csv versions.yml
    """
}

workflow BIOC_STAGER_DIFFERENTIAL_GENE_EXPRESSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pScreen, pConfirmation ] ]

    main:
    BIOC_STAGER_DIFFERENTIAL_GENE_EXPRESSION(ch_input)

    emit:
    tables   = BIOC_STAGER_DIFFERENTIAL_GENE_EXPRESSION.out.tables
    plots    = BIOC_STAGER_DIFFERENTIAL_GENE_EXPRESSION.out.plots
    objects  = BIOC_STAGER_DIFFERENTIAL_GENE_EXPRESSION.out.objects
    versions = BIOC_STAGER_DIFFERENTIAL_GENE_EXPRESSION.out.versions
}
