#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scRepertoire — bcr_repertoire_clustering
// Process raw BCR contig data, group related clones using sequence similarity or alignment metrics, and analyze B cell clonal relationships.
// Input: b_contigs.csv
// Container: quay.io/biocontainers/bioconductor-screpertoire:2.2.0--r44he5774e6_0
// R packages: scRepertoire
// Bioconductor: 3.20 | R: 4.4
// Requires: scRepertoire
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Read the user input file from the working directory
//  * 2. [Core Analysis] Combine BCR contigs and cluster related clones using
//  * 3. [Core Analysis] Perform advanced alignment-based clustering using
//  * 4. [Core Analysis] Filter non-productive and multi-chain contigs
//  * 5. [Core Analysis] Write outputs to the working directory

nextflow.enable.dsl = 2

process BIOC_SCREPERTOIRE_BCR_REPERTOIRE_CLUSTERING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-single_cell:3.20-slim"

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
    .bm_deps <- c("scRepertoire")
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
    library(scRepertoire)
    
    # --- Read the user input file from the working directory ---
    BCR.contigs <- read.csv("b_contigs.csv")
    
    # --- Combine BCR contigs and cluster related clones using ---
    combined.BCR.clustered <- combineBCR(BCR.contigs, 
                                         samples = "Patient1", 
                                         threshold = 0.85)
    
    # --- Perform advanced alignment-based clustering using ---
    combined.BCR.aligned <- combineBCR(BCR.contigs, 
                                       samples = "Patient1",
                                       sequence = "aa",        
                                       dist_type = "nw",      
                                       dist_mat = "BLOSUM80",  
                                       threshold = 0.85)
    
    # --- Filter non-productive and multi-chain contigs ---
    cleaned.BCR <- combineBCR(BCR.contigs,
                              samples = "Patient1",
                              filterNonproductive = TRUE,
                              filterMulti = TRUE)
    
    # --- Write outputs to the working directory ---
    saveRDS(combined.BCR.clustered, "combined_BCR_clustered.rds")
    saveRDS(combined.BCR.aligned, "combined_BCR_aligned.rds")
    saveRDS(cleaned.BCR, "cleaned_BCR.rds")
    
    write.csv(combined.BCR.clustered[[1]], "combined_BCR_clustered_Patient1.csv", row.names = FALSE)
    write.csv(combined.BCR.aligned[[1]], "combined_BCR_aligned_Patient1.csv", row.names = FALSE)
    write.csv(cleaned.BCR[[1]], "cleaned_BCR_Patient1.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_SCREPERTOIRE_BCR_REPERTOIRE_CLUSTERING":',
        paste0('    scRepertoire: ', as.character(packageVersion('scRepertoire')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bcr_repertoire_clustering.csv versions.yml
    """
}

workflow BIOC_SCREPERTOIRE_BCR_REPERTOIRE_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ b_contigs.csv ] ]

    main:
    BIOC_SCREPERTOIRE_BCR_REPERTOIRE_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_SCREPERTOIRE_BCR_REPERTOIRE_CLUSTERING.out.tables
    plots    = BIOC_SCREPERTOIRE_BCR_REPERTOIRE_CLUSTERING.out.plots
    objects  = BIOC_SCREPERTOIRE_BCR_REPERTOIRE_CLUSTERING.out.objects
    versions = BIOC_SCREPERTOIRE_BCR_REPERTOIRE_CLUSTERING.out.versions
}
