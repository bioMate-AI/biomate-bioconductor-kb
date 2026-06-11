#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ggtree — ggtree_genomic_clustering
// Cluster genomic regions based on spatial distance and visualize the resulting hierarchical tree annotated with genomic metadata using ggtree.
// Input: regions.bed, coldata.csv
// Container: 4.0.4--r45hdfd78af_1
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, ggplot2, ggtree
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GGTREE_GGTREE_GENOMIC_CLUSTERING {
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
    .bm_deps <- c("GenomicRanges", "ggtree", "ggplot2")
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
    library(GenomicRanges)
    library(ggtree)
    library(ggplot2)
    
    # --- Import genomic intervals and metadata ---
    message("Reading input files...")
    bed_data <- read.table("regions.bed", header = FALSE, sep = "\t", stringsAsFactors = FALSE)
    colnames(bed_data) <- c("chrom", "start", "end", "name", "score", "strand")[1:min(6, ncol(bed_data))]
    
    # Create GRanges object
    gr <- GRanges(
      seqnames = bed_data\$chrom,
      ranges = IRanges(start = bed_data\$start, end = bed_data\$end),
      strand = if ("strand" %in% colnames(bed_data)) bed_data\$strand else "*",
      name = if ("name" %in% colnames(bed_data)) bed_data\$name else paste0("region_", seq_len(nrow(bed_data))),
      score = if ("score" %in% colnames(bed_data)) bed_data\$score else 0
    )
    
    # --- Compute distance matrix and perform hierarchical ---
    message("Clustering genomic regions...")
    midpoints <- (start(gr) + end(gr)) / 2
    dist_matrix <- dist(matrix(midpoints, ncol = 1))
    labels(dist_matrix) <- gr\$name
    
    # Generate hierarchical clustering tree
    hc <- hclust(dist_matrix, method = "average")
    
    # --- Prepare and merge metadata ---
    message("Preparing metadata...")
    df_meta <- data.frame(
      label = gr\$name,
      chrom = as.character(seqnames(gr)),
      width = width(gr),
      score = gr\$score,
      stringsAsFactors = FALSE
    )
    
    if (file.exists("coldata.csv")) {
      coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
      if ("name" %in% colnames(coldata)) {
        colnames(coldata)[colnames(coldata) == "name"] <- "label"
      }
      df_meta <- merge(df_meta, coldata, by = "label", all.x = TRUE)
    }
    
    # Export combined metadata
    write.csv(df_meta, "tree_metadata.csv", row.names = FALSE)
    
    # --- Visualize and annotate tree using ggtree ---
    message("Generating ggtree visualization...")
    p <- ggtree(hc)
    
    # Attach metadata to the tree structure
    p <- p %<+% df_meta
    
    # Add tree annotations and layers
    p <- p + 
      geom_tiplab(aes(label = label), size = 3, hjust = -0.2) +
      geom_tippoint(aes(color = chrom, size = width), alpha = 0.8) +
      geom_treescale()
    
    # Programmatically highlight a clade if the tree has sufficient nodes
    num_tips <- length(hc\$order)
    if (num_tips > 3) {
      # Highlight the second internal node as a representative clade
      target_node <- num_tips + 2
      p <- p + 
        geom_hilight(node = target_node, fill = "steelblue", alpha = 0.3) +
        geom_cladelabel(node = target_node, label = "Clade A", color = "darkblue", offset = 0.5)
    }
    
    # Save the final annotated tree plot
    ggsave("tree_plot.pdf", plot = p, width = 10, height = 8)
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_GGTREE_GGTREE_GENOMIC_CLUSTERING":',
        paste0('    ggtree: ', as.character(packageVersion('ggtree')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ggtree_genomic_clustering.csv versions.yml
    """
}

workflow BIOC_GGTREE_GGTREE_GENOMIC_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_GGTREE_GGTREE_GENOMIC_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_GGTREE_GGTREE_GENOMIC_CLUSTERING.out.tables
    plots    = BIOC_GGTREE_GGTREE_GENOMIC_CLUSTERING.out.plots
    objects  = BIOC_GGTREE_GGTREE_GENOMIC_CLUSTERING.out.objects
    versions = BIOC_GGTREE_GGTREE_GENOMIC_CLUSTERING.out.versions
}
