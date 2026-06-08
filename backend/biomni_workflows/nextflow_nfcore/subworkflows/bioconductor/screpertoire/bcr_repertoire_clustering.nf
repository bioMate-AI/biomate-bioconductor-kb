#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scRepertoire — bcr_repertoire_clustering
// Process raw BCR contig data, group related clones using sequence similarity or alignment metrics, and analyze B cell clonal relationships.
// Input: b_contigs.csv
// Container: quay.io/biocontainers/bioconductor-screpertoire:2.2.0--r44he5774e6_0
// Requires: scRepertoire
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Combine BCR contigs and cluster related clones using combineBCR(). 2. Perform advanced alignment-based clustering using Needleman-

nextflow.enable.dsl = 2

process BIOC_SCREPERTOIRE_BCR_REPERTOIRE_CLUSTERING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-single_cell:3.20"

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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load required libraries
    library(scRepertoire)
    
    # 1. Read the user input file from the working directory
    BCR.contigs <- read.csv("b_contigs.csv")
    
    # 2. Combine BCR contigs and cluster related clones using combineBCR()
    combined.BCR.clustered <- combineBCR(BCR.contigs, 
                                         samples = "Patient1", 
                                         threshold = 0.85)
    
    # 3. Perform advanced alignment-based clustering using Needleman-Wunsch and substitution matrices
    combined.BCR.aligned <- combineBCR(BCR.contigs, 
                                       samples = "Patient1",
                                       sequence = "aa",        
                                       dist_type = "nw",      
                                       dist_mat = "BLOSUM80",  
                                       threshold = 0.85)
    
    # 4. Filter non-productive and multi-chain contigs
    cleaned.BCR <- combineBCR(BCR.contigs,
                              samples = "Patient1",
                              filterNonproductive = TRUE,
                              filterMulti = TRUE)
    
    # 5. Write outputs to the working directory
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
