#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: magrene — interaction_similarity
// Calculate the Sorensen-Dice similarity index for paralogous gene pairs to evaluate interaction similarity.
// Input: ppi_edgelist.tsv, paralog_pairs.tsv
// Container: quay.io/biocontainers/bioconductor-magrene:1.12.0--r45hdfd78af_0
// Requires: magrene
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Calculate Sorensen-Dice similarity using sd_similarity()
//  * 2. [Visualization & Output] Summarize the similarity scores

nextflow.enable.dsl = 2

process BIOC_MAGRENE_INTERACTION_SIMILARITY {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    
    # Load required library
    library(magrene)
    
    # -----------------------------------------------------------------------------
    # Stage 0: Read User Input Files
    # -----------------------------------------------------------------------------
    # Read the PPI network edge list
    gma_ppi <- read.delim("ppi_edgelist.tsv", header = TRUE, stringsAsFactors = FALSE)
    
    # Read the paralogous gene pairs
    paralogs <- read.delim("paralog_pairs.tsv", header = TRUE, stringsAsFactors = FALSE)
    
    # -----------------------------------------------------------------------------
    # Stage 1: Calculate Sorensen-Dice similarity using sd_similarity()
    # -----------------------------------------------------------------------------
    sim <- sd_similarity(gma_ppi, paralogs)
    
    # Display the first few rows of the similarity data frame
    head(sim)
    
    # -----------------------------------------------------------------------------
    # Stage 2: Summarize the similarity scores
    # -----------------------------------------------------------------------------
    summary(sim\$sorensen_dice)
    
    # -----------------------------------------------------------------------------
    # Stage 3: Write Output Files
    # -----------------------------------------------------------------------------
    # Save the complete similarity results as a CSV table
    write.csv(sim, "similarity_results.csv", row.names = FALSE)
    
    # Save the similarity results as an RDS object for downstream R analyses
    saveRDS(sim, "similarity_results.rds")
    
    # Save the summary statistics to a text file
    sink("similarity_summary.txt")
    cat("Sorensen-Dice Similarity Summary Statistics:\n")
    print(summary(sim\$sorensen_dice))
    sink()

    writeLines(c(
        '"BIOC_MAGRENE_INTERACTION_SIMILARITY":',
        paste0('    magrene: ', as.character(packageVersion('magrene')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_interaction_similarity.csv versions.yml
    """
}

workflow BIOC_MAGRENE_INTERACTION_SIMILARITY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ppi_edgelist.tsv, paralog_pairs.tsv ] ]

    main:
    BIOC_MAGRENE_INTERACTION_SIMILARITY(ch_input)

    emit:
    tables   = BIOC_MAGRENE_INTERACTION_SIMILARITY.out.tables
    plots    = BIOC_MAGRENE_INTERACTION_SIMILARITY.out.plots
    objects  = BIOC_MAGRENE_INTERACTION_SIMILARITY.out.objects
    versions = BIOC_MAGRENE_INTERACTION_SIMILARITY.out.versions
}
