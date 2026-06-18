#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: knowYourCG — gene_linkage_and_go
// Test whether CpG probes are associated with specific genes and perform Gene Ontology analysis.
// Input: character vector
// Container: quay.io/biocontainers/bioconductor-knowyourcg:1.6.3--r45h01b2380_0
// R packages: SummarizedExperiment, gprofiler2, knowYourCG, sesameData
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, gprofiler2, knowYourCG, sesameData
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Build gene databases
//  * 2. [Core Analysis] Run enrichment testing with gene inclusion
//  * 3. [Core Analysis] Link probes to proximal genes
//  * 4. [Core Analysis] Perform GO enrichment using gprofiler2

nextflow.enable.dsl = 2

process BIOC_KNOWYOURCG_GENE_LINKAGE_AND_GO {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("SummarizedExperiment", "gprofiler2", "knowYourCG", "sesameData")
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
        library(knowYourCG)
        library(sesameData)
        library(gprofiler2)
        
        # Define input file path
        input_file <- "cpg_probes.txt"
        
        # Check if input file exists
        if (!file.exists(input_file)) {
          stop(paste("Error: Input file", input_file, "not found in the working directory."))
        }
        
        # Read CpG probe IDs from the user input file
        user_probes <- readLines(input_file)
        user_probes <- trimws(user_probes)
        user_probes <- user_probes[user_probes != ""]
        
        if (length(user_probes) == 0) {
          stop("Error: The input file is empty or contains no valid probe IDs.")
        }
        
        # Assign the user-provided probes to the query variables used in the workflow
        query <- user_probes
        query_probes <- user_probes
        
        # Stage 1 & 2: Build gene databases and run enrichment testing
        # First enrichment test using dynamically built gene databases
        results_gene_db <- testEnrichment(
          query, 
          buildGeneDBs(query, max_distance = 100000, platform = "MM285"), 
          platform = "MM285"
        )
        
        # Save the first enrichment results
        write.csv(results_gene_db, "enrichment_results_gene_db.csv", row.names = FALSE)
        
        # Define target databases
        dbs <- c(
          "KYCG.MM285.chromHMM.20210210", 
          "KYCG.HM450.TFBSconsensus.20211013", 
          "KYCG.MM285.chromosome.mm10.20210630"
        )
        
        # Second enrichment test including gene enrichment testing with specified databases
        results_multi_db <- testEnrichment(
          query, 
          databases = dbs, 
          platform = "MM285", 
          include_genes = TRUE
        )
        
        # Save the second enrichment results
        write.csv(results_multi_db, "enrichment_results_multi_db.csv", row.names = FALSE)
        
        # Stage 3: Link probes to proximal genes
        genes <- linkProbesToProximalGenes(query_probes, platform = "MM285")\$gene_name
        
        # Save the linked genes list
        writeLines(genes, "linked_genes.txt")
        
        # Stage 4: Perform GO enrichment using gprofiler2
        gostres <- gprofiler2::gost(genes, organism = "mmusculus")
        
        # Save the gprofiler2 results
        saveRDS(gostres, "gost_results.rds")
        
        if (!is.null(gostres) && !is.null(gostres\$result)) {
          res_df <- gostres\$result
          # Convert list columns to character strings to prevent write.csv errors
          for (col in names(res_df)) {
            if (is.list(res_df[[col]])) {
              res_df[[col]] <- vapply(res_df[[col]], paste, collapse = ",", FUN.VALUE = character(1))
            }
          }
          write.csv(res_df, "gost_results_table.csv", row.names = FALSE)
        } else {
          message("No significant GO enrichment results found by gprofiler2.")
        }

    writeLines(c(
        '"BIOC_KNOWYOURCG_GENE_LINKAGE_AND_GO":',
        paste0('    knowYourCG: ', as.character(packageVersion('knowYourCG')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gene_linkage_and_go.csv versions.yml
    """
}

workflow BIOC_KNOWYOURCG_GENE_LINKAGE_AND_GO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ character vector ] ]

    main:
    BIOC_KNOWYOURCG_GENE_LINKAGE_AND_GO(ch_input)

    emit:
    tables   = BIOC_KNOWYOURCG_GENE_LINKAGE_AND_GO.out.tables
    plots    = BIOC_KNOWYOURCG_GENE_LINKAGE_AND_GO.out.plots
    objects  = BIOC_KNOWYOURCG_GENE_LINKAGE_AND_GO.out.objects
    versions = BIOC_KNOWYOURCG_GENE_LINKAGE_AND_GO.out.versions
}
