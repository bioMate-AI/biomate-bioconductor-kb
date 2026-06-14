#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: sarks — kmer_clustering_and_mapping
// Cluster similar discovered k-mers into broader motifs and map/count them in the input sequences.
// Input: kmers, simulatedSeqs
// Container: quay.io/biocontainers/bioconductor-sarks:1.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: rJava, sarks
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define or input a vector of k-mers
//  * 2. [Core Analysis] Cluster k-mers treating them as equivalent to their reverse-complements
//  * 3. [Core Analysis] Count occurrences of each cluster in the sequences
//  * 4. [Core Analysis] Locate the exact positions and matches of the clusters in the sequences

nextflow.enable.dsl = 2

process BIOC_SARKS_KMER_CLUSTERING_AND_MAPPING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("rJava", "sarks")
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
    
    # Initialize Java parameters before loading rJava and sarks
    options(java.parameters = '-Xmx8G')
    library(rJava)
    .jinit()
    
    library(sarks)
    
    # ==========================================
    # 1. READ USER INPUT FILES
    # ==========================================
    
    # Read kmers (character vector of discovered k-mers)
    if (file.exists("kmers.rds")) {
      kmers <- readRDS("kmers.rds")
    } else if (file.exists("kmers.txt")) {
      kmers <- readLines("kmers.txt")
      kmers <- kmers[kmers != ""]
    } else {
      stop("Error: 'kmers' input file not found. Please provide 'kmers.rds' or 'kmers.txt' in the working directory.")
    }
    
    # Read simulatedSeqs (named character vector of sequences)
    if (file.exists("simulatedSeqs.rds")) {
      simulatedSeqs <- readRDS("simulatedSeqs.rds")
    } else if (file.exists("simulatedSeqs.fa") || file.exists("simulatedSeqs.fasta")) {
      fasta_file <- ifelse(file.exists("simulatedSeqs.fa"), "simulatedSeqs.fa", "simulatedSeqs.fasta")
      lines <- readLines(fasta_file)
      header_idx <- grep("^>", lines)
      if (length(header_idx) == 0) {
        stop("Error: FASTA file is invalid (no headers starting with '>')")
      }
      seq_names <- sub("^>", "", lines[header_idx])
      seq_starts <- header_idx + 1
      seq_ends <- c(header_idx[-1] - 1, length(lines))
      seqs <- character(length(header_idx))
      for (i in seq_along(header_idx)) {
        seqs[i] <- paste(lines[seq_starts[i]:seq_ends[i]], collapse = "")
      }
      names(seqs) <- seq_names
      simulatedSeqs <- seqs
    } else if (file.exists("simulatedSeqs.txt")) {
      simulatedSeqs <- readLines("simulatedSeqs.txt")
      simulatedSeqs <- simulatedSeqs[simulatedSeqs != ""]
      names(simulatedSeqs) <- as.character(seq_along(simulatedSeqs) - 1)
    } else {
      stop("Error: 'simulatedSeqs' input file not found. Please provide 'simulatedSeqs.rds', 'simulatedSeqs.fa', or 'simulatedSeqs.txt' in the working directory.")
    }
    
    # ==========================================
    # 2. RUN WORKFLOW
    # ==========================================
    
    # Cluster similar discovered k-mers treating them as equivalent to their reverse-complements
    kmClust <- clusterKmers(kmers, directional=FALSE)
    
    # Count occurrences of each cluster in the sequences
    clCounts <- clusterCounts(kmClust, simulatedSeqs, directional=FALSE)
    
    # Locate the exact positions and matches of the clusters in the sequences
    clLoci <- locateClusters(kmClust, simulatedSeqs, directional=FALSE, showMatch=TRUE)
    
    # ==========================================
    # 3. WRITE OUTPUTS
    # ==========================================
    
    # Save kmClust (the cluster list)
    saveRDS(kmClust, "kmClust.rds")
    sink("kmClust_summary.txt")
    print(kmClust)
    sink()
    
    # Save clCounts (the counts matrix)
    saveRDS(clCounts, "clCounts.rds")
    write.csv(as.data.frame(clCounts), "cluster_counts.csv", row.names = TRUE)
    
    # Save clLoci (the locations data frame)
    saveRDS(clLoci, "clLoci.rds")
    write.csv(clLoci, "cluster_loci.csv", row.names = FALSE)
    
    message("Workflow completed successfully. Outputs written to 'kmClust.rds', 'kmClust_summary.txt', 'cluster_counts.csv', and 'cluster_loci.csv'.")

    writeLines(c(
        '"BIOC_SARKS_KMER_CLUSTERING_AND_MAPPING":',
        paste0('    sarks: ', as.character(packageVersion('sarks')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_kmer_clustering_and_mapping.csv versions.yml
    """
}

workflow BIOC_SARKS_KMER_CLUSTERING_AND_MAPPING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ kmers, simulatedSeqs ] ]

    main:
    BIOC_SARKS_KMER_CLUSTERING_AND_MAPPING(ch_input)

    emit:
    tables   = BIOC_SARKS_KMER_CLUSTERING_AND_MAPPING.out.tables
    plots    = BIOC_SARKS_KMER_CLUSTERING_AND_MAPPING.out.plots
    objects  = BIOC_SARKS_KMER_CLUSTERING_AND_MAPPING.out.objects
    versions = BIOC_SARKS_KMER_CLUSTERING_AND_MAPPING.out.versions
}
