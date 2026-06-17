#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: motifTestR — clustered_motif_analysis
// Group highly similar motifs into clusters to reduce redundancy, and test the clusters for positional bias and enrichment.
// Input: ex_pfm, test_seq, rm_seq
// Container: quay.io/biocontainers/bioconductor-motiftestr:1.6.1--r45hdfd78af_0
// R packages: Biostrings, motifTestR
// Bioconductor: 3.20 | R: 4.4
// Requires: Biostrings, motifTestR
// Visualizations: cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Cluster similar motifs using clusterMotifs()
//  * 2. [Core Analysis] Split the PFMs into clusters
//  * 3. [Core Analysis] Find matches for clustered motifs using getClusterMatches()
//  * 4. [Core Analysis] Test clustered motifs for positional bias using testClusterPos()
//  * 5. [Core Analysis] Test clustered motifs for enrichment using testClusterEnrich()

nextflow.enable.dsl = 2

process BIOC_MOTIFTESTR_CLUSTERED_MOTIF_ANALYSIS {
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
    .bm_deps <- c("Biostrings", "motifTestR")
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
    library(motifTestR)
    library(Biostrings)
    library(parallel)
    
    # Define key parameters
    score_thresh <- "70%"
    cores <- 1
    
    # Helper function to robustly read user input files from the working directory
    read_input <- function(base_name) {
      if (file.exists(base_name)) {
        return(readRDS(base_name))
      } else if (file.exists(paste0(base_name, ".rds"))) {
        return(readRDS(paste0(base_name, ".rds")))
      } else if (file.exists(paste0(base_name, ".RDS"))) {
        return(readRDS(paste0(base_name, ".RDS")))
      } else {
        stop(paste("Required input file", base_name, "not found in the working directory."))
      }
    }
    
    # Load user inputs
    ex_pfm <- read_input("ex_pfm")
    test_seq <- read_input("test_seq")
    rm_seq <- read_input("rm_seq")
    
    # 1. Cluster similar motifs using clusterMotifs()
    # Since plot = TRUE, we wrap the call in a PDF device to save the dendrogram
    pdf("motif_clusters_dendrogram.pdf", width = 8, height = 6)
    cl <- clusterMotifs(ex_pfm, plot = TRUE, labels = NULL)
    dev.off()
    
    # 2. Split the PFMs into clusters
    ex_cl <- split(ex_pfm, cl)
    names(ex_cl) <- vapply(split(names(cl), cl), paste, character(1), collapse = "/")
    saveRDS(ex_cl, "ex_cl.rds")
    
    # 3. Find matches for clustered motifs using getClusterMatches()
    cl_matches <- getClusterMatches(
        ex_cl, test_seq, min_score = score_thresh, best_only = TRUE
    )
    saveRDS(cl_matches, "cl_matches.rds")
    
    # 4. Test clustered motifs for positional bias using testClusterPos()
    cl_pos_res <- testClusterPos(cl_matches, test_seq, abs = TRUE)
    write.csv(as.data.frame(cl_pos_res), "cluster_positional_bias_results.csv", row.names = TRUE)
    
    # 5. Test clustered motifs for enrichment using testClusterEnrich()
    cl_enrich_res <- testClusterEnrich(
      ex_cl, test_seq, rm_seq, min_score = score_thresh, model = "quasi", mc.cores = cores
    )
    write.csv(as.data.frame(cl_enrich_res), "cluster_enrichment_results.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_MOTIFTESTR_CLUSTERED_MOTIF_ANALYSIS":',
        paste0('    motifTestR: ', as.character(packageVersion('motifTestR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_clustered_motif_analysis.csv versions.yml
    """
}

workflow BIOC_MOTIFTESTR_CLUSTERED_MOTIF_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ex_pfm, test_seq, rm_seq ] ]

    main:
    BIOC_MOTIFTESTR_CLUSTERED_MOTIF_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MOTIFTESTR_CLUSTERED_MOTIF_ANALYSIS.out.tables
    plots    = BIOC_MOTIFTESTR_CLUSTERED_MOTIF_ANALYSIS.out.plots
    objects  = BIOC_MOTIFTESTR_CLUSTERED_MOTIF_ANALYSIS.out.objects
    versions = BIOC_MOTIFTESTR_CLUSTERED_MOTIF_ANALYSIS.out.versions
}
