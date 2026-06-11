#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: QUBIC — query_based_biclustering
// Perform guided biclustering by incorporating external biological information (e.g., protein-protein interaction network weights).
// Input: expression_matrix.csv, weight_matrix.csv
// Container: quay.io/biocontainers/bioconductor-qubic:1.38.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: QUBIC
// Visualizations: heatmap, cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Read the user input files from the working directory
//  * 2. [Core Analysis] Run the QUBIC algorithm with the weight parameter
//  * 3. [Core Analysis] Save the meaningful results to output files

nextflow.enable.dsl = 2

process BIOC_QUBIC_QUERY_BASED_BICLUSTERING {
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
    library(QUBIC)
    
    # --- Read the user input files from the working directory ---
    # expression_matrix.csv: Gene expression matrix (genes as rows, conditions as columns)
    if (!file.exists("expression_matrix.csv")) {
      stop("Error: 'expression_matrix.csv' not found in the working directory.")
    }
    ecoli <- as.matrix(read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE))
    
    # weight_matrix.csv: Adjacency matrix representing interaction weights between genes
    if (!file.exists("weight_matrix.csv")) {
      stop("Error: 'weight_matrix.csv' not found in the working directory.")
    }
    ecoli.weight <- as.matrix(read.csv("weight_matrix.csv", row.names = 1, check.names = FALSE))
    
    # --- Run the QUBIC algorithm with the weight parameter ---
    res4 <- qubiclust(ecoli, weight = ecoli.weight, verbose = FALSE)
    
    # --- Save the meaningful results to output files ---
    # Save the complete biclustering result object
    saveRDS(res4, "biclustering_result.rds")
    
    # Extract and save a summary of the identified biclusters
    if (res4@Number > 0) {
      bicluster_summary <- data.frame(
        Bicluster = seq_len(res4@Number),
        Num_Genes = colSums(res4@RowxNumber),
        Num_Conditions = rowSums(res4@NumberxCol)
      )
      write.csv(bicluster_summary, "bicluster_summary.csv", row.names = FALSE)
      
      # Export the genes and conditions for each bicluster to a text file
      sink("biclusters_detailed.txt")
      for (i in seq_len(res4@Number)) {
        genes <- rownames(ecoli)[res4@RowxNumber[, i]]
        conditions <- colnames(ecoli)[res4@NumberxCol[i, ]]
        cat(paste0("Bicluster ", i, ":\n"))
        cat(paste0("  Genes (", length(genes), "): ", paste(genes, collapse = ", "), "\n"))
        cat(paste0("  Conditions (", length(conditions), "): ", paste(conditions, collapse = ", "), "\n\n"))
      }
      sink()
      
      # Generate a heatmap for the first identified bicluster
      pdf("bicluster_1_heatmap.pdf", width = 8, height = 8)
      paleta <- colorRampPalette(c("#D73027", "#FC8D59", "#FEE090", "#FFFFBF", "#E0F3F8", "#91BFDB", "#4575B4"))(11)
      tryCatch({
        quheatmap(ecoli, res4, number = 1, showlabel = TRUE, col = paleta)
      }, error = function(e) {
        warning("Could not generate heatmap: ", e\$message)
      })
      dev.off()
    } else {
      writeLines("No biclusters were found with the given parameters and weight matrix.", "bicluster_summary.csv")
    }

    writeLines(c(
        '"BIOC_QUBIC_QUERY_BASED_BICLUSTERING":',
        paste0('    QUBIC: ', as.character(packageVersion('QUBIC')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_query_based_biclustering.csv versions.yml
    """
}

workflow BIOC_QUBIC_QUERY_BASED_BICLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv, weight_matrix.csv ] ]

    main:
    BIOC_QUBIC_QUERY_BASED_BICLUSTERING(ch_input)

    emit:
    tables   = BIOC_QUBIC_QUERY_BASED_BICLUSTERING.out.tables
    plots    = BIOC_QUBIC_QUERY_BASED_BICLUSTERING.out.plots
    objects  = BIOC_QUBIC_QUERY_BASED_BICLUSTERING.out.objects
    versions = BIOC_QUBIC_QUERY_BASED_BICLUSTERING.out.versions
}
