#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GOSemSim — go_semantic_similarity_analysis
// Perform Gene Ontology (GO) semantic similarity analysis on genes associated with genomic regions.
// Input: regions.bed, coldata.csv
// Container: 2.36.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GOSemSim, GenomicRanges, org.Hs.eg.db, rtracklayer
// Visualizations: heatmap
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GOSEMSIM_GO_SEMANTIC_SIMILARITY_ANALYSIS {
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
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(rtracklayer)
    library(GenomicRanges)
    library(GOSemSim)
    library(org.Hs.eg.db) # Standard organism database for human annotation
    
    # Define parameters
    ONTOLOGY <- "BP"
    MEASURE <- "Wang"
    
    # -------------------------------------------------------------------------
    # Stage 1: Import and Parse Inputs
    # -------------------------------------------------------------------------
    message("Stage 1: Importing genomic regions and metadata...")
    
    if (!file.exists("regions.bed")) {
      stop("Required input file 'regions.bed' is missing.")
    }
    
    # Import BED file using rtracklayer
    gr <- rtracklayer::import("regions.bed")
    
    # Extract gene identifiers from the 'name' column of the BED file
    if (!"name" %in% colnames(mcols(gr))) {
      stop("The BED file must contain a 'name' column representing gene identifiers.")
    }
    
    genes <- unique(mcols(gr)\$name)
    genes <- genes[!is.na(genes) & genes != ""]
    
    if (length(genes) == 0) {
      stop("No valid gene identifiers found in the 'name' column of the BED file.")
    }
    
    # Read optional metadata/coldata
    coldata <- NULL
    if (file.exists("coldata.csv")) {
      message("Found coldata.csv. Loading metadata for cluster-level analysis...")
      coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    }
    
    # -------------------------------------------------------------------------
    # Stage 2: Prepare GO Data
    # -------------------------------------------------------------------------
    message("Stage 2: Preparing GO database annotation...")
    
    # Determine keytype (ENTREZID if all numeric, otherwise SYMBOL)
    is_numeric_id <- all(grepl("^\\\\d+\$", genes))
    key_type <- if (is_numeric_id) "ENTREZID" else "SYMBOL"
    message(paste("Detected gene keytype:", key_type))
    
    # Build the semantic similarity database using GOSemSim
    sem_data <- tryCatch({
      GOSemSim::godata(
        OrgDb = "org.Hs.eg.db",
        ont = ONTOLOGY,
        keytype = key_type,
        computeIC = TRUE
      )
    }, error = function(e) {
      message("Error building GO data: ", e\$message)
      NULL
    })
    
    # -------------------------------------------------------------------------
    # Stage 3: Compute Gene Semantic Similarity
    # -------------------------------------------------------------------------
    message("Stage 3: Computing pairwise gene semantic similarity...")
    
    sim_matrix <- NULL
    if (!is.null(sem_data)) {
      # Limit to top 150 genes to avoid excessive computation times
      genes_to_sim <- if (length(genes) > 150) genes[1:150] else genes
      
      sim_matrix <- tryCatch({
        GOSemSim::mgeneSim(
          genes = genes_to_sim,
          semData = sem_data,
          measure = MEASURE,
          drop = TRUE
        )
      }, error = function(e) {
        message("Error computing gene similarity: ", e\$message)
        NULL
      })
    }
    
    # Write gene similarity matrix to CSV
    if (!is.null(sim_matrix)) {
      write.csv(as.data.frame(sim_matrix), "gene_similarity_matrix.csv", row.names = TRUE)
      message("Saved gene similarity matrix to 'gene_similarity_matrix.csv'.")
    } else {
      write.csv(data.frame(Warning = "Could not compute gene similarity"), "gene_similarity_matrix.csv", row.names = FALSE)
    }
    
    # -------------------------------------------------------------------------
    # Stage 4: Compute Cluster/Group Semantic Similarity
    # -------------------------------------------------------------------------
    message("Stage 4: Computing cluster-level semantic similarity...")
    
    cluster_sim_matrix <- NULL
    if (!is.null(sem_data) && !is.null(coldata)) {
      # Expecting coldata to have 'name' (matching BED names) and 'group' columns
      if ("name" %in% colnames(coldata) && "group" %in% colnames(coldata)) {
        coldata_sub <- coldata[coldata\$name %in% genes, ]
        gene_clusters <- split(coldata_sub\$name, coldata_sub\$group)
        
        # Filter to clusters with at least 2 genes
        gene_clusters <- gene_clusters[sapply(gene_clusters, length) >= 2]
        
        if (length(gene_clusters) >= 2) {
          cluster_sim_matrix <- tryCatch({
            GOSemSim::mclusterSim(
              gene_clusters,
              semData = sem_data,
              measure = MEASURE,
              combine = "BMA"
            )
          }, error = function(e) {
            message("Error computing cluster similarity: ", e\$message)
            NULL
          })
        } else {
          message("Insufficient clusters with >= 2 genes for cluster-level analysis.")
        }
      } else {
        message("Metadata 'coldata.csv' must contain 'name' and 'group' columns.")
      }
    }
    
    # Write cluster similarity matrix to CSV
    if (!is.null(cluster_sim_matrix)) {
      write.csv(as.data.frame(cluster_sim_matrix), "cluster_similarity_matrix.csv", row.names = TRUE)
      message("Saved cluster similarity matrix to 'cluster_similarity_matrix.csv'.")
    } else {
      write.csv(data.frame(Warning = "No cluster similarity computed"), "cluster_similarity_matrix.csv", row.names = FALSE)
    }
    
    # -------------------------------------------------------------------------
    # Stage 5: Visualization
    # -------------------------------------------------------------------------
    message("Stage 5: Generating similarity heatmap...")
    
    pdf("go_similarity_heatmap.pdf", width = 10, height = 10)
    if (!is.null(sim_matrix) && nrow(sim_matrix) > 1) {
      # Replace NA values with 0 for visualization purposes
      plot_mat <- sim_matrix
      plot_mat[is.na(plot_mat)] <- 0
      
      heatmap(
        plot_mat,
        main = paste("Gene GO Semantic Similarity (", MEASURE, ")", sep = ""),
        col = heat.colors(256),
        margins = c(10, 10)
      )
    } else {
      plot.new()
      text(0.5, 0.5, "Insufficient data or error occurred\nHeatmap could not be generated.", cex = 1.2)
    }
    dev.off()
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_GOSEMSIM_GO_SEMANTIC_SIMILARITY_ANALYSIS":',
        paste0('    GOSemSim: ', as.character(packageVersion('GOSemSim')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_go_semantic_similarity_analysis.csv versions.yml
    """
}

workflow BIOC_GOSEMSIM_GO_SEMANTIC_SIMILARITY_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_GOSEMSIM_GO_SEMANTIC_SIMILARITY_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_GOSEMSIM_GO_SEMANTIC_SIMILARITY_ANALYSIS.out.tables
    plots    = BIOC_GOSEMSIM_GO_SEMANTIC_SIMILARITY_ANALYSIS.out.plots
    objects  = BIOC_GOSEMSIM_GO_SEMANTIC_SIMILARITY_ANALYSIS.out.objects
    versions = BIOC_GOSEMSIM_GO_SEMANTIC_SIMILARITY_ANALYSIS.out.versions
}
