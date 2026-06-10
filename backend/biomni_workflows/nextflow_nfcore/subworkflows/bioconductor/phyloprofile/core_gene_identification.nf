#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PhyloProfile — core_gene_identification
// Identify core genes shared among a selected set of taxa.
// Input: processed_profile.RData
// Container: quay.io/biocontainers/bioconductor-phyloprofile:2.2.2--r45hdfd78af_0
// Requires: PhyloProfile, dplyr
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Sort input taxa using `sortInputTaxa`
//  * 2. [Core Analysis] Count taxa within each supertaxon
//  * 3. [Core Analysis] Identify core genes using `getCoreGene`

nextflow.enable.dsl = 2

process BIOC_PHYLOPROFILE_CORE_GENE_IDENTIFICATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
        
        # Load required libraries
        library(PhyloProfile)
        library(dplyr)
        
        # Read user input file
        if (!file.exists("processed_profile.RData")) {
          stop("Error: processed_profile.RData not found in the working directory.")
        }
        
        # Load the RData file and retrieve the processed profile object
        env <- new.env()
        load("processed_profile.RData", envir = env)
        obj_names <- ls(env)
        
        if ("fullProcessedProfile" %in% obj_names) {
          fullProcessedProfile <- env\$fullProcessedProfile
        } else if (length(obj_names) > 0) {
          fullProcessedProfile <- env[[obj_names[1]]]
        } else {
          stop("Error: Loaded RData file is empty.")
        }
        
        # Extract taxon IDs
        taxonIDs <- levels(as.factor(fullProcessedProfile\$ncbiID))
        
        # Dynamically determine taxaCore and refTaxon from the dataset
        raw_supertaxa <- as.character(unique(fullProcessedProfile\$supertaxon))
        taxaCore <- unique(gsub("^[0-9]+_", "", raw_supertaxa))
        refTaxon <- taxaCore[1]
        
        # Dynamically determine rankName
        possible_ranks <- c("strain", "species", "genus", "family", "order", "class", "phylum", "kingdom", "superkingdom")
        rankName <- "class" # fallback
        for (r in possible_ranks) {
          temp_sorted <- tryCatch(
            sortInputTaxa(taxonIDs, r, refTaxon, NULL, NULL, NULL),
            error = function(e) NULL
          )
          if (!is.null(temp_sorted) && "supertaxon" %in% colnames(temp_sorted)) {
            temp_taxa <- unique(gsub("^[0-9]+_", "", as.character(temp_sorted\$supertaxon)))
            if (all(taxaCore %in% temp_taxa)) {
              rankName <- r
              break
            }
          }
        }
        
        # Define parameters
        var1Cutoff <- c(0.75, 1.0)
        var2Cutoff <- c(0.75, 1.0)
        percentCutoff <- c(0.0, 1.0)
        coreCoverage <- 1
        
        # Stage 1: Sort input taxa using sortInputTaxa
        sortedInputTaxa <- sortInputTaxa(
            taxonIDs, rankName, refTaxon, NULL, NULL, NULL
        )
        
        # Stage 2: Count taxa within each supertaxon
        taxaCount <- sortedInputTaxa %>% dplyr::count(supertaxon)
        
        # Stage 3: Identify core genes using getCoreGene
        coreGenes <- getCoreGene(
            rankName,
            taxaCore,
            fullProcessedProfile,
            taxaCount,
            var1Cutoff, var2Cutoff,
            percentCutoff, coreCoverage
        )
        
        # Write outputs to files
        write.csv(as.data.frame(sortedInputTaxa), "sorted_input_taxa.csv", row.names = FALSE)
        write.csv(taxaCount, "taxa_count.csv", row.names = FALSE)
        writeLines(as.character(coreGenes), "core_genes.txt")
        saveRDS(coreGenes, "core_genes.rds")
        
        cat("Workflow completed successfully. Outputs saved to 'sorted_input_taxa.csv', 'taxa_count.csv', 'core_genes.txt', and 'core_genes.rds'.\n")

    writeLines(c(
        '"BIOC_PHYLOPROFILE_CORE_GENE_IDENTIFICATION":',
        paste0('    PhyloProfile: ', as.character(packageVersion('PhyloProfile')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_core_gene_identification.csv versions.yml
    """
}

workflow BIOC_PHYLOPROFILE_CORE_GENE_IDENTIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ processed_profile.RData ] ]

    main:
    BIOC_PHYLOPROFILE_CORE_GENE_IDENTIFICATION(ch_input)

    emit:
    tables   = BIOC_PHYLOPROFILE_CORE_GENE_IDENTIFICATION.out.tables
    plots    = BIOC_PHYLOPROFILE_CORE_GENE_IDENTIFICATION.out.plots
    objects  = BIOC_PHYLOPROFILE_CORE_GENE_IDENTIFICATION.out.objects
    versions = BIOC_PHYLOPROFILE_CORE_GENE_IDENTIFICATION.out.versions
}
