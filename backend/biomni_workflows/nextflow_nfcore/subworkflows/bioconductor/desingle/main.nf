#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DEsingle — matrix_input_workflow
// Detect and classify differentially expressed genes between two groups of cells using a raw read counts matrix.
// Input: counts.ext, group.ext
// Container: quay.io/biocontainers/bioconductor-desingle:1.30.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: DEsingle
// Visualizations: bar plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the package and data
//  * 2. [Core Analysis] Specify the two groups to be compared as a factor vector
//  * 3. [Core Analysis] Detect DE genes using DEsingle()
//  * 4. [Core Analysis] Classify DE genes into three categories using DEtype()
//  * 5. [Core Analysis] Filter and extract significant DE genes and their subtypes

nextflow.enable.dsl = 2

process BIOC_DESINGLE_MATRIX_INPUT_WORKFLOW {
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
    library(DEsingle)
    
    # Helper function to robustly read the counts matrix
    read_counts <- function(file_path) {
      if (!file.exists(file_path)) {
        stop(paste("Error: Input file not found:", file_path))
      }
      
      # Try reading as RDS first
      obj <- tryCatch(readRDS(file_path), error = function(e) NULL)
      if (!is.null(obj)) {
        if (is.matrix(obj) || is.data.frame(obj)) {
          return(as.matrix(obj))
        }
        return(obj)
      }
      
      # Try reading as delimited text files
      for (sep in c("\t", ",", "")) {
        obj <- tryCatch({
          df <- read.table(file_path, header = TRUE, row.names = 1, sep = sep, check.names = FALSE)
          if (ncol(df) > 0) as.matrix(df) else NULL
        }, error = function(e) NULL)
        if (!is.null(obj)) {
          # Ensure numeric matrix
          mode(obj) <- "numeric"
          return(obj)
        }
      }
      
      stop(paste("Error: Failed to read", file_path, "as RDS or delimited text file."))
    }
    
    # Helper function to robustly read the group factor vector
    read_group <- function(file_path) {
      if (!file.exists(file_path)) {
        stop(paste("Error: Input file not found:", file_path))
      }
      
      # Try reading as RDS first
      obj <- tryCatch(readRDS(file_path), error = function(e) NULL)
      if (!is.null(obj)) return(as.factor(obj))
      
      # Try reading as delimited text file
      for (sep in c("\t", ",", "")) {
        obj <- tryCatch({
          df <- read.table(file_path, header = FALSE, sep = sep, stringsAsFactors = FALSE)
          as.factor(df[[1]])
        }, error = function(e) NULL)
        if (!is.null(obj)) return(obj)
      }
      
      stop(paste("Error: Failed to read", file_path, "as RDS or delimited text file."))
    }
    
    # 1. Load the data from the declared user input files
    counts <- read_counts("counts.ext")
    group <- read_group("group.ext")
    
    # Validate dimensions
    if (ncol(counts) != length(group)) {
      stop(sprintf("Dimension mismatch: counts matrix has %d columns (cells), but group vector has length %d.", 
                   ncol(counts), length(group)))
    }
    
    # 2. Specify the two groups to be compared as a factor vector
    group <- factor(group)
    
    # 3. Detect DE genes using DEsingle()
    results <- DEsingle(counts = counts, group = group)
    
    # 4. Classify DE genes into three categories using DEtype()
    results.classified <- DEtype(results = results, threshold = 0.05)
    
    # 5. Filter and extract significant DE genes and their subtypes
    results.sig <- results.classified[results.classified\$pvalue.adj.FDR < 0.05, ]
    results.DEs <- results.sig[results.sig\$Type == "DEs", ]
    results.DEa <- results.sig[results.sig\$Type == "DEa", ]
    results.DEg <- results.sig[results.sig\$Type == "DEg", ]
    
    # 6. Write output files
    write.csv(results.classified, "results_classified.csv", row.names = TRUE)
    write.csv(results.sig, "results_sig.csv", row.names = TRUE)
    write.csv(results.DEs, "results_DEs.csv", row.names = TRUE)
    write.csv(results.DEa, "results_DEa.csv", row.names = TRUE)
    write.csv(results.DEg, "results_DEg.csv", row.names = TRUE)
    
    saveRDS(results, "results_raw.rds")
    saveRDS(results.classified, "results_classified.rds")
    
    # Generate a summary visualization of the DE types
    pdf("de_types_summary.pdf", width = 6, height = 6)
    de_counts <- table(results.sig\$Type)
    all_types <- c("DEs", "DEa", "DEg")
    plot_counts <- setNames(rep(0, 3), all_types)
    plot_counts[names(de_counts)] <- de_counts
    
    barplot(plot_counts, 
            col = c("#56B4E9", "#E69F00", "#009E73"),
            main = "Number of DE Genes by Type (FDR < 0.05)",
            xlab = "DE Type", 
            ylab = "Number of Genes",
            ylim = c(0, max(plot_counts) * 1.2))
    text(x = seq_along(plot_counts) * 1.2 - 0.5, 
         y = plot_counts + (max(plot_counts) * 0.02), 
         labels = plot_counts, 
         pos = 3)
    dev.off()
    
    cat("Pipeline completed successfully. Outputs written to working directory.\n")

    writeLines(c(
        '"BIOC_DESINGLE_MATRIX_INPUT_WORKFLOW":',
        paste0('    DEsingle: ', as.character(packageVersion('DEsingle')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_matrix_input_workflow.csv versions.yml
    """
}

workflow BIOC_DESINGLE_MATRIX_INPUT_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ counts.ext, group.ext ] ]

    main:
    BIOC_DESINGLE_MATRIX_INPUT_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_DESINGLE_MATRIX_INPUT_WORKFLOW.out.tables
    plots    = BIOC_DESINGLE_MATRIX_INPUT_WORKFLOW.out.plots
    objects  = BIOC_DESINGLE_MATRIX_INPUT_WORKFLOW.out.objects
    versions = BIOC_DESINGLE_MATRIX_INPUT_WORKFLOW.out.versions
}
