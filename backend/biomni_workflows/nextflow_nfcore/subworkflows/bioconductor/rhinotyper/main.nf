#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rhinotyper — rhinovirus_genotyping_external_alignment
// Genotype rhinovirus sequences by exporting prototype references, aligning them externally, importing the curated alignment, and performing downstream distance a
// Input: user_sequences.fasta, input_aln.fasta
// Container: quay.io/biocontainers/bioconductor-rhinotyper:1.4.0--r45hdfd78af_0
// R packages: Biostrings, rhinotypeR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RHINOTYPER_RHINOVIRUS_GENOTYPING_EXTERNAL_ALIGNMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-rhinotyper:1.4.0--r45hdfd78af_0"

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
    .bm_deps <- c("Biostrings", "rhinotypeR")
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
    library(rhinotypeR)
    library(Biostrings)
    
    # Define input file paths
    user_seqs_file <- "user_sequences.fasta"
    curated_aln_file <- "input_aln.fasta"
    
    # Verify input files exist
    if (!file.exists(user_seqs_file)) {
      stop(paste("Required input file missing:", user_seqs_file))
    }
    if (!file.exists(curated_aln_file)) {
      stop(paste("Required input file missing:", curated_aln_file))
    }
    
    # 1. Export prototype sequences to the current working directory
    getPrototypeSeqs(".")
    
    # 2. Import the externally aligned and curated FASTA file
    aln_curated <- Biostrings::readDNAStringSet(curated_aln_file)
    
    # 3. Assign genotypes
    res <- assignTypes(aln_curated, model = "IUPAC", deleteGapsGlobally = FALSE, threshold = 0.105)
    write.csv(res, "genotype_assignments.csv", row.names = FALSE)
    
    # 4. Plot genotype frequencies
    pdf("genotype_frequency_plot.pdf", width = 8, height = 6)
    plotFrequency(res)
    dev.off()
    
    # Load the unaligned user sequences into the variable name used in the documentation
    rhinovirusVP4 <- Biostrings::readDNAStringSet(user_seqs_file)
    
    # 5. Compute pairwise distances
    d <- pairwiseDistances(
      fastaData = rhinovirusVP4,
      model = "IUPAC",
      deleteGapsGlobally = FALSE   # set TRUE to apply global deletion inside the function
    )
    saveRDS(d, "pairwise_distances.rds")
    write.csv(as.matrix(d), "pairwise_distances.csv")
    
    # 6. Compute overall mean distance
    mean_dist <- overallMeanDistance(rhinovirusVP4, model = "IUPAC")
    writeLines(as.character(mean_dist), "overall_mean_distance.txt")
    
    # 7. Plot distance heatmap and tree
    pdf("distance_heatmap.pdf", width = 10, height = 8)
    plotDistances(d)  
    dev.off()
    
    # Safely subset distances to avoid out-of-bounds errors if there are fewer than 30 sequences
    n_samples <- min(30, nrow(d))
    sampled_distances <- d[1:n_samples, 1:n_samples, drop = FALSE]
    
    pdf("distance_tree.pdf", width = 10, height = 8)
    plotTree(sampled_distances, hang = -1, cex = 0.6, 
             main = "A simple tree", xlab = "", ylab = "Genetic distance")
    dev.off()
    
    # 8. Visualize SNPs
    pdf("snpeek_plot.pdf", width = 12, height = 8)
    SNPeek(rhinovirusVP4)
    dev.off()

    writeLines(c(
        '"BIOC_RHINOTYPER_RHINOVIRUS_GENOTYPING_EXTERNAL_ALIGNMENT":',
        paste0('        rhinotyper: ', as.character(packageVersion("rhinotyper")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rhinovirus_genotyping_external_alignment.csv versions.yml
    """
}

workflow BIOC_RHINOTYPER_RHINOVIRUS_GENOTYPING_EXTERNAL_ALIGNMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ user_sequences.fasta, input_aln.fasta ] ]

    main:
    BIOC_RHINOTYPER_RHINOVIRUS_GENOTYPING_EXTERNAL_ALIGNMENT(ch_input)

    emit:
    tables   = BIOC_RHINOTYPER_RHINOVIRUS_GENOTYPING_EXTERNAL_ALIGNMENT.out.tables
    plots    = BIOC_RHINOTYPER_RHINOVIRUS_GENOTYPING_EXTERNAL_ALIGNMENT.out.plots
    objects  = BIOC_RHINOTYPER_RHINOVIRUS_GENOTYPING_EXTERNAL_ALIGNMENT.out.objects
    versions = BIOC_RHINOTYPER_RHINOVIRUS_GENOTYPING_EXTERNAL_ALIGNMENT.out.versions
}
