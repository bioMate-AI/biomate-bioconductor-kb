#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: treeio — treeio_transcriptome_phylogeny
// Build a sample-level phylogenetic tree from transcriptomic profiles, link sample metadata and QC metrics to the tree nodes using treeio, and export the annotate
// Input: counts.csv, coldata.csv
// Container: 1.34.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: treeio
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TREEIO_TREEIO_TRANSCRIPTOME_PHYLOGENY {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(treeio)
    library(stats)
    
    # Stage 1: Read input transcriptomics data
    counts <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # Stage 2: Preprocess and compute distance matrix
    # Log-transform counts to stabilize variance across samples
    log_counts <- log2(counts + 1)
    
    # Compute sample-to-sample Euclidean distance based on expression profiles
    sample_dist <- dist(t(log_counts))
    
    # Stage 3: Build hierarchical clustering tree and convert to phylo
    hc <- hclust(sample_dist, method = "average")
    # Convert hclust object to a phylo object using treeio's imported/exported methods
    phylo_tree <- treeio::as.phylo(hc)
    
    # Stage 4: Prepare metadata and QC metrics to link with the tree
    sample_summary <- data.frame(
      sample = colnames(counts),
      total_counts = colSums(counts),
      detected_genes = colSums(counts > 0),
      stringsAsFactors = FALSE
    )
    
    # Merge experimental design metadata with computed QC metrics
    metadata <- merge(coldata, sample_summary, by = "sample")
    
    # Stage 5: Link metadata to the phylogenetic tree using treeio
    # treeio::full_join merges the data frame with the phylo object by matching tip labels
    annotated_tree <- treeio::full_join(
      phylo_tree, 
      metadata, 
      by = c("label" = "sample")
    )
    
    # Stage 6: Export the annotated tree and association table
    # Write the tree with its associated node/tip data in BEAST NEXUS format
    treeio::write.beast(annotated_tree, file = "annotated_tree.beast")
    
    # Convert the treedata object to a tibble/dataframe to export as a flat table
    tree_df <- as.data.frame(treeio::as_tibble(annotated_tree))
    write.csv(tree_df, "tree_metadata_association.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_TREEIO_TREEIO_TRANSCRIPTOME_PHYLOGENY":',
        paste0('    treeio: ', as.character(packageVersion('treeio')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_treeio_transcriptome_phylogeny.csv versions.yml
    """
}

workflow BIOC_TREEIO_TREEIO_TRANSCRIPTOME_PHYLOGENY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_TREEIO_TREEIO_TRANSCRIPTOME_PHYLOGENY(ch_input)

    emit:
    tables   = BIOC_TREEIO_TREEIO_TRANSCRIPTOME_PHYLOGENY.out.tables
    plots    = BIOC_TREEIO_TREEIO_TRANSCRIPTOME_PHYLOGENY.out.plots
    objects  = BIOC_TREEIO_TREEIO_TRANSCRIPTOME_PHYLOGENY.out.objects
    versions = BIOC_TREEIO_TREEIO_TRANSCRIPTOME_PHYLOGENY.out.versions
}
