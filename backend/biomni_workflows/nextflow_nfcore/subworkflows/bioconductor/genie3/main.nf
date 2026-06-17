#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GENIE3 — standard_network_inference
// Infer a gene regulatory network from a gene expression matrix using default or customized tree-based parameters and extract ranked regulatory links.
// Input: exprMatr
// Container: quay.io/biocontainers/bioconductor-genie3:1.32.0--r45h01b2380_0
// R packages: GENIE3
// Bioconductor: 3.20 | R: 4.4
// Requires: GENIE3
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Prepare the gene expression matrix
//  * 2. [Core Analysis] Run GENIE3 to compute regulatory link weights (optionally customizing tree method, parameters, or parallelization)
//  * 3. [Core Analysis] Extract and filter the ranked list of regulatory links

nextflow.enable.dsl = 2

process BIOC_GENIE3_STANDARD_NETWORK_INFERENCE {
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
    .bm_deps <- c("GENIE3")
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
        library(GENIE3)
        
        # 1. Prepare the gene expression matrix
        # Read the user input file 'exprMatr' from the working directory.
        # We support CSV, TSV, or RDS formats.
        if (file.exists("exprMatr.csv")) {
          exprMatr <- as.matrix(read.csv("exprMatr.csv", row.names = 1, check.names = FALSE))
        } else if (file.exists("exprMatr.tsv")) {
          exprMatr <- as.matrix(read.delim("exprMatr.tsv", row.names = 1, check.names = FALSE))
        } else if (file.exists("exprMatr.rds")) {
          exprMatr <- readRDS("exprMatr.rds")
          if (!is.matrix(exprMatr)) {
            exprMatr <- as.matrix(exprMatr)
          }
        } else {
          stop("Error: Input file 'exprMatr' (as .csv, .tsv, or .rds) not found in the working directory.")
        }
        
        # 2. Run GENIE3 to compute regulatory link weights
        set.seed(123) # For reproducibility of results
        
        # We use tryCatch in case the system environment restricts multi-core execution.
        # K="sqrt" is used as a sensible default appropriate for the dataset size.
        weightMat <- tryCatch({
          GENIE3(exprMatr, K="sqrt", nCores=4, verbose=TRUE)
        }, error = function(e) {
          warning("Parallel GENIE3 run failed, falling back to single core: ", e\$message)
          GENIE3(exprMatr, K="sqrt", nCores=1, verbose=TRUE)
        })
        saveRDS(weightMat, "weightMat_final.rds")
        write.csv(weightMat, "weightMat_final.csv")
        
        # 3. Extract and filter the ranked list of regulatory links
        # Extract all regulatory links (single sensible extraction)
        linkList_all <- getLinkList(weightMat)
        write.csv(linkList_all, "linkList_all.csv", row.names = FALSE)
        
        message("GENIE3 workflow completed successfully. Outputs saved to the working directory.")

    writeLines(c(
        '"BIOC_GENIE3_STANDARD_NETWORK_INFERENCE":',
        paste0('    GENIE3: ', as.character(packageVersion('GENIE3')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_network_inference.csv versions.yml
    """
}

workflow BIOC_GENIE3_STANDARD_NETWORK_INFERENCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ exprMatr ] ]

    main:
    BIOC_GENIE3_STANDARD_NETWORK_INFERENCE(ch_input)

    emit:
    tables   = BIOC_GENIE3_STANDARD_NETWORK_INFERENCE.out.tables
    plots    = BIOC_GENIE3_STANDARD_NETWORK_INFERENCE.out.plots
    objects  = BIOC_GENIE3_STANDARD_NETWORK_INFERENCE.out.objects
    versions = BIOC_GENIE3_STANDARD_NETWORK_INFERENCE.out.versions
}
