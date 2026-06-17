#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: gep2pep — condition_set_enrichment_analysis
// Perform Condition-Set Enrichment Analysis (CondSEA/DSEA) to identify pathways consistently dysregulated by a specific set of conditions/drugs.
// Input: rp, pgset
// Container: quay.io/biocontainers/bioconductor-gep2pep:1.30.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GSEABase, gep2pep
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define the set of conditions of interest
//  * 2. [Core Analysis] Run CondSEA using CondSEA
//  * 3. [Core Analysis] Retrieve results for a specific collection using getResults
//  * 4. [Visualization & Output] Export results to XLS format using exportSEA

nextflow.enable.dsl = 2

process BIOC_GEP2PEP_CONDITION_SET_ENRICHMENT_ANALYSIS {
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
    .bm_deps <- c("gep2pep", "GSEABase")
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
        library(gep2pep)
        library(GSEABase)
        
        # 1. Define the set of conditions of interest (Read from user input)
        if (!dir.exists("rp")) {
          stop("Error: 'rp' repository directory not found in the working directory.")
        }
        if (!file.exists("pgset")) {
          stop("Error: 'pgset' file not found in the working directory.")
        }
        
        # Open the gep2pep repository from the local directory
        rp <- openRepository("rp")
        
        # Read the pgset (conditions/drugs of interest)
        pgset <- tryCatch({
          readRDS("pgset")
        }, error = function(e) {
          readLines("pgset")
        })
        
        # Ensure pgset is a character vector
        pgset <- as.character(pgset)
        
        # 2. Run CondSEA using CondSEA
        psea <- CondSEA(rp, pgset)
        
        # 3. Retrieve results for the first available collection using getResults
        collection_name <- names(psea\$CondSEA)[1]
        res_collection <- getResults(psea, collection_name)
        
        # Save the retrieved results to a CSV file
        write.csv(res_collection, paste0(collection_name, "_results.csv"), row.names = TRUE)
        
        # Save the complete psea object as an RDS file
        saveRDS(psea, "psea_results.rds")
        
        # 4. Export results to XLS format using exportSEA
        exportSEA(rp, psea)
        
        # Print completion message
        cat(sprintf("CondSEA workflow completed successfully. Results saved to '%s_results.csv' and 'psea_results.rds'.\n", collection_name))

    writeLines(c(
        '"BIOC_GEP2PEP_CONDITION_SET_ENRICHMENT_ANALYSIS":',
        paste0('    gep2pep: ', as.character(packageVersion('gep2pep')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_condition_set_enrichment_analysis.csv versions.yml
    """
}

workflow BIOC_GEP2PEP_CONDITION_SET_ENRICHMENT_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ rp, pgset ] ]

    main:
    BIOC_GEP2PEP_CONDITION_SET_ENRICHMENT_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_GEP2PEP_CONDITION_SET_ENRICHMENT_ANALYSIS.out.tables
    plots    = BIOC_GEP2PEP_CONDITION_SET_ENRICHMENT_ANALYSIS.out.plots
    objects  = BIOC_GEP2PEP_CONDITION_SET_ENRICHMENT_ANALYSIS.out.objects
    versions = BIOC_GEP2PEP_CONDITION_SET_ENRICHMENT_ANALYSIS.out.versions
}
