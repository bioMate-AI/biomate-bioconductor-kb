#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PhyloProfile — gene_age_estimation
// Estimate the evolutionary age of genes from phylogenetic profiles using a Last Common Ancestor (LCA) algorithm.
// Input: processed_profile.RData
// Container: quay.io/biocontainers/bioconductor-phyloprofile:2.2.2--r45hdfd78af_0
// R packages: PhyloProfile, dplyr
// Bioconductor: 3.20 | R: 4.4
// Requires: PhyloProfile, dplyr
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Sort input taxa based on reference taxon using `sortInputTaxa`
//  * 2. [Core Analysis] Count taxa within each supertaxon
//  * 3. [Core Analysis] Estimate gene age using `estimateGeneAge`

nextflow.enable.dsl = 2

process BIOC_PHYLOPROFILE_GENE_AGE_ESTIMATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("PhyloProfile", "dplyr")
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
    library(PhyloProfile)
    library(dplyr)
    
    # 1. Load the user-provided processed phylogenetic profile
    if (!file.exists("processed_profile.RData")) {
        stop("Error: Input file 'processed_profile.RData' not found in the working directory.")
    }
    
    # Load RData into a temporary environment to safely extract the profile object
    env <- new.env()
    load("processed_profile.RData", envir = env)
    
    # Retrieve the processed profile object
    if ("fullProcessedProfile" %in% names(env)) {
        fullProcessedProfile <- env\$fullProcessedProfile
    } else {
        # Fallback to the first object in the loaded RData if not named 'fullProcessedProfile'
        obj_names <- names(env)
        if (length(obj_names) == 0) {
            stop("Error: 'processed_profile.RData' is empty.")
        }
        fullProcessedProfile <- env[[obj_names[1]]]
    }
    
    # 2. Define parameters
    rankName <- "class"
    refTaxon <- "Mammalia"
    
    # 3. Extract taxon IDs and sort input taxa based on reference taxon
    taxonIDs <- levels(as.factor(fullProcessedProfile\$ncbiID))
    sortedInputTaxa <- sortInputTaxa(
        taxonIDs, rankName, refTaxon, NULL, NULL, NULL
    )
    
    # 4. Count taxa within each supertaxon
    taxaCount <- sortedInputTaxa %>% dplyr::count(supertaxon)
    
    # 5. Set cutoff thresholds
    var1Cutoff <- c(0,1)
    var2Cutoff <- c(0,1)
    percentCutoff <- c(0,1)
    
    # 6. Estimate gene age using the LCA algorithm
    geneAgeEstimate <- estimateGeneAge(
        fullProcessedProfile, taxaCount, rankName, refTaxon,
        var1Cutoff, var2Cutoff, percentCutoff
    )
    
    # 7. Save meaningful results to output files
    write.csv(geneAgeEstimate, "estimated_gene_ages.csv", row.names = FALSE)
    saveRDS(geneAgeEstimate, "estimated_gene_ages.rds")
    
    write.csv(sortedInputTaxa, "sorted_input_taxa.csv", row.names = FALSE)
    write.csv(taxaCount, "taxa_count_per_supertaxon.csv", row.names = FALSE)
    
    cat("Gene age estimation completed successfully. Outputs saved to 'estimated_gene_ages.csv' and 'estimated_gene_ages.rds'.\n")

    writeLines(c(
        '"BIOC_PHYLOPROFILE_GENE_AGE_ESTIMATION":',
        paste0('    PhyloProfile: ', as.character(packageVersion('PhyloProfile')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gene_age_estimation.csv versions.yml
    """
}

workflow BIOC_PHYLOPROFILE_GENE_AGE_ESTIMATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ processed_profile.RData ] ]

    main:
    BIOC_PHYLOPROFILE_GENE_AGE_ESTIMATION(ch_input)

    emit:
    tables   = BIOC_PHYLOPROFILE_GENE_AGE_ESTIMATION.out.tables
    plots    = BIOC_PHYLOPROFILE_GENE_AGE_ESTIMATION.out.plots
    objects  = BIOC_PHYLOPROFILE_GENE_AGE_ESTIMATION.out.objects
    versions = BIOC_PHYLOPROFILE_GENE_AGE_ESTIMATION.out.versions
}
