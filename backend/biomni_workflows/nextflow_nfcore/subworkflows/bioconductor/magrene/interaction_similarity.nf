#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: magrene — interaction_similarity
// Calculate the Sorensen-Dice similarity index for paralogous gene pairs to evaluate interaction similarity.
// Input: ppi_edgelist.tsv, paralog_pairs.tsv
// Container: quay.io/biocontainers/bioconductor-magrene:1.12.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("magrene")
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
