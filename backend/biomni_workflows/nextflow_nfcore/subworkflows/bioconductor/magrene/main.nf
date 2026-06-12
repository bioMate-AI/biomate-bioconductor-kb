#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: magrene — motif_analysis
// Identify network motifs (PPI V, V, lambda, delta, bifan) in GRN and PPI networks, and evaluate their statistical significance using simulated null distributions
// Input: grn_edgelist.tsv, ppi_edgelist.tsv, paralog_pairs.tsv
// Container: quay.io/biocontainers/bioconductor-magrene:1.12.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: magrene
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Find PPI V motifs using find_ppi_v()
//  * 2. [Core Analysis] Find V motifs using find_v()
//  * 3. [Core Analysis] Find Lambda motifs using find_lambda()
//  * 4. [Core Analysis] Find Delta motifs using find_delta() by passing the identified lambda motifs
//  * 5. [Core Analysis] Find Bifan motifs using find_bifan() by passing the identified lambda motifs
//  * 6. [Core Analysis] Generate null distributions of motif frequencies using generate_nulls()
//  * 7. [Core Analysis] Calculate Z-scores for observed motif frequencies using calculate_Z()

nextflow.enable.dsl = 2

process BIOC_MAGRENE_MOTIF_ANALYSIS {
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
    
    # Set seed for reproducibility
    set.seed(123)
    
    # Check for required input files in the working directory
    required_files <- c("grn_edgelist.tsv", "ppi_edgelist.tsv", "paralog_pairs.tsv")
    for (f in required_files) {
      if (!file.exists(f)) {
        stop(paste("Required input file missing:", f))
      }
    }
    
    # Read and format Protein-Protein Interaction (PPI) network
    gma_ppi <- read.delim("ppi_edgelist.tsv", header = TRUE)[, 1:2]
    colnames(gma_ppi) <- c("node1", "node2")
    
    # Read and format Gene Regulatory Network (GRN)
    grn_raw <- read.delim("grn_edgelist.tsv", header = TRUE)
    grn <- grn_raw[, 1:2]
    colnames(grn) <- c("Node1", "Node2")
    
    # Read and format Paralogous gene pairs
    paralogs_raw <- read.delim("paralog_pairs.tsv", header = TRUE)
    if ("type" %in% colnames(paralogs_raw)) {
      # If duplication type is available, prioritize WGD-derived paralogs as in the vignette
      paralogs <- paralogs_raw[paralogs_raw\$type == "WGD", 1:2]
      if (nrow(paralogs) == 0) {
        paralogs <- paralogs_raw[, 1:2]
      }
    } else {
      paralogs <- paralogs_raw[, 1:2]
    }
    colnames(paralogs) <- c("duplicate1", "duplicate2")
    
    # 1. Find PPI V motifs
    ppi_v <- find_ppi_v(gma_ppi, paralogs)
    
    # 2. Find V motifs
    v <- find_v(grn, paralogs)
    
    # 3. Find Lambda motifs
    lambda <- find_lambda(grn, paralogs)
    
    # 4. Find Delta motifs using the identified lambda motifs
    delta <- find_delta(edgelist_ppi = gma_ppi, lambda_vec = lambda)
    
    # 5. Find Bifan motifs using the identified lambda motifs
    bifan <- find_bifan(paralogs = paralogs, lambda_vec = lambda)
    
    # 6. Generate null distributions of motif frequencies
    nulls <- generate_nulls(grn, paralogs, gma_ppi, n = 5)
    
    # 7. Calculate Z-scores for observed motif frequencies
    observed <- list(
        lambda = length(lambda), 
        bifan = length(bifan), 
        V = length(v),
        PPI_V = length(ppi_v),
        delta = length(delta)
    )
    
    z_scores <- calculate_Z(observed, nulls)
    
    # 8. Evaluate interaction similarity (Sorensen-Dice similarity)
    sim <- sd_similarity(gma_ppi, paralogs)
    
    # Write outputs to the working directory
    writeLines(ppi_v, "ppi_v_motifs.txt")
    writeLines(v, "v_motifs.txt")
    writeLines(lambda, "lambda_motifs.txt")
    writeLines(delta, "delta_motifs.txt")
    writeLines(bifan, "bifan_motifs.txt")
    
    # Save observed counts
    counts_df <- data.frame(
      Motif = names(observed),
      Count = unlist(observed)
    )
    write.csv(counts_df, "observed_motif_counts.csv", row.names = FALSE)
    
    # Save Z-scores
    z_df <- data.frame(
      Motif = names(z_scores),
      Z_Score = as.numeric(z_scores)
    )
    write.csv(z_df, "motif_z_scores.csv", row.names = FALSE)
    
    # Save Sorensen-Dice similarity scores
    write.csv(sim, "sorensen_dice_similarity.csv", row.names = FALSE)
    
    # Save null distributions as an RDS object for downstream analysis
    saveRDS(nulls, "null_distributions.rds")
    
    message("Pipeline completed successfully. All outputs have been written to the working directory.")

    writeLines(c(
        '"BIOC_MAGRENE_MOTIF_ANALYSIS":',
        paste0('    magrene: ', as.character(packageVersion('magrene')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_motif_analysis.csv versions.yml
    """
}

workflow BIOC_MAGRENE_MOTIF_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ grn_edgelist.tsv, ppi_edgelist.tsv, paralog_pairs.tsv ] ]

    main:
    BIOC_MAGRENE_MOTIF_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MAGRENE_MOTIF_ANALYSIS.out.tables
    plots    = BIOC_MAGRENE_MOTIF_ANALYSIS.out.plots
    objects  = BIOC_MAGRENE_MOTIF_ANALYSIS.out.objects
    versions = BIOC_MAGRENE_MOTIF_ANALYSIS.out.versions
}
