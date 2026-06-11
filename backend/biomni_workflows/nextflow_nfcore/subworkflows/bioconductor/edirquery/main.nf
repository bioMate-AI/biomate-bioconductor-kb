#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: EDIRquery — edir_gene_repeat_query
// Search for exome interspersed repeats (EDIR) within a user-provided list of genes, retrieving both tabular annotations and genomic interaction structures.
// Input: input.csv
// Container: 1.10.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: EDIRquery
// Visualizations: bar plot
// QC: missing-value handling
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EDIRQUERY_EDIR_GENE_REPEAT_QUERY {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    library(EDIRquery)
    
    # Define input and output file paths
    input_file <- "input.csv"
    output_csv <- "edir_query_results.csv"
    output_rds <- "edir_query_interactions.rds"
    output_pdf <- "edir_summary_plots.pdf"
    
    # ==========================================
    # Stage 1: Read and Parse Input Defensively
    # ==========================================
    if (!file.exists(input_file)) {
      stop(paste("Required input file missing:", input_file))
    }
    
    message("Reading input gene list from ", input_file)
    inp <- read.csv(input_file, stringsAsFactors = FALSE, check.names = FALSE)
    
    # Extract gene identifiers from the input CSV
    genes <- c()
    if ("feature_id" %in% colnames(inp)) {
      genes <- inp\$feature_id
    } else if (ncol(inp) == 1) {
      genes <- inp[[1]]
    } else {
      # Fallback: use row names or the first column
      genes <- rownames(inp)
      if (is.null(genes) || all(genes == as.character(seq_len(nrow(inp))))) {
        genes <- inp[[1]]
      }
    }
    
    # Clean and deduplicate gene list
    genes <- unique(na.omit(as.character(genes)))
    genes <- genes[genes != ""]
    
    if (length(genes) == 0) {
      stop("No valid gene identifiers found in the input file.")
    }
    
    message("Found ", length(genes), " unique gene(s) to query.")
    
    # ==========================================
    # Stage 2: Query EDIR Database (Tabular & GInteractions)
    # ==========================================
    results_list <- list()
    interactions_list <- list()
    
    for (g in genes) {
      message("Querying EDIR database for gene: ", g)
      
      # 1. Query tabular data frame format
      res_df <- tryCatch({
        gene_lookup(g, mismatch = TRUE)
      }, error = function(e) {
        warning("Error querying tabular data for gene ", g, ": ", e\$message)
        NULL
      })
      
      if (!is.null(res_df) && nrow(res_df) > 0) {
        # Ensure a tracking column for the queried gene exists
        if (!"query_gene" %in% colnames(res_df)) {
          res_df\$query_gene <- g
        }
        results_list[[g]] <- res_df
      }
      
      # 2. Query GInteractions format
      res_gi <- tryCatch({
        gene_lookup(g, format = "GInteractions", mismatch = TRUE)
      }, error = function(e) {
        warning("Error querying GInteractions for gene ", g, ": ", e\$message)
        NULL
      })
      
      if (!is.null(res_gi) && length(res_gi) > 0) {
        interactions_list[[g]] <- res_gi
      }
    }
    
    # ==========================================
    # Stage 3: Process and Save Outputs
    # ==========================================
    
    # Save tabular results
    if (length(results_list) > 0) {
      combined_df <- do.call(rbind, results_list)
      write.csv(combined_df, output_csv, row.names = FALSE)
      message("Saved tabular results to ", output_csv)
    } else {
      message("No EDIR repeats found. Writing empty fallback CSV.")
      write.csv(data.frame(query_gene = character(), message = "No repeats found"), 
                output_csv, row.names = FALSE)
    }
    
    # Save GInteractions results
    if (length(interactions_list) > 0) {
      saveRDS(interactions_list, output_rds)
      message("Saved GInteractions structures to ", output_rds)
    } else {
      message("No GInteractions structures found. Saving empty list RDS.")
      saveRDS(list(), output_rds)
    }
    
    # ==========================================
    # Stage 4: Visualization and Diagnostics
    # ==========================================
    message("Generating diagnostic plots...")
    pdf(output_pdf, width = 8, height = 6)
    
    if (exists("combined_df") && nrow(combined_df) > 0) {
      # Determine the column representing the gene
      gene_col <- if ("query_gene" %in% colnames(combined_df)) "query_gene" else "gene"
      
      if (gene_col %in% colnames(combined_df)) {
        gene_counts <- table(combined_df[[gene_col]])
        
        # Adjust margins for long gene names
        par(mar = c(7, 4, 4, 2) + 0.1)
        barplot(gene_counts, 
                main = "EDIR Interspersed Repeats Detected per Gene",
                ylab = "Number of Repeats", 
                col = "skyblue", 
                las = 2,
                cex.names = 0.8)
      } else {
        plot.new()
        text(0.5, 0.5, "No gene identifier column found in results to plot.", cex = 1.2)
      }
    } else {
      plot.new()
      text(0.5, 0.5, "No EDIR repeats detected for the queried genes.", cex = 1.2)
    }
    
    dev.off()
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_EDIRQUERY_EDIR_GENE_REPEAT_QUERY":',
        paste0('    EDIRquery: ', as.character(packageVersion('EDIRquery')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_edir_gene_repeat_query.csv versions.yml
    """
}

workflow BIOC_EDIRQUERY_EDIR_GENE_REPEAT_QUERY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_EDIRQUERY_EDIR_GENE_REPEAT_QUERY(ch_input)

    emit:
    tables   = BIOC_EDIRQUERY_EDIR_GENE_REPEAT_QUERY.out.tables
    plots    = BIOC_EDIRQUERY_EDIR_GENE_REPEAT_QUERY.out.plots
    objects  = BIOC_EDIRQUERY_EDIR_GENE_REPEAT_QUERY.out.objects
    versions = BIOC_EDIRQUERY_EDIR_GENE_REPEAT_QUERY.out.versions
}
