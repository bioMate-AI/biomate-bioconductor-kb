#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: diffcoexp — differential_coexpression_analysis
// Identify differentially coexpressed gene pairs (DCLs) and genes (DCGs) from normalized expression data under two conditions.
// Input: exprs.1, exprs.2
// Container: quay.io/biocontainers/bioconductor-diffcoexp:1.30.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, diffcoexp
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the package and enable multi-threading
//  * 2. [Core Analysis] Run the differential coexpression analysis using diffcoexp
//  * 3. [Visualization & Output] Inspect the structure of the output list containing DCGs and DCLs

nextflow.enable.dsl = 2

process BIOC_DIFFCOEXP_DIFFERENTIAL_COEXPRESSION_ANALYSIS {
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
    library(diffcoexp)
    
    # Helper function to load expression data robustly
    load_expression_data <- function(filepath) {
      if (!file.exists(filepath)) {
        exts <- c(".rds", ".csv", ".tsv", ".txt")
        found <- FALSE
        for (ext in exts) {
          if (file.exists(paste0(filepath, ext))) {
            filepath <- paste0(filepath, ext)
            found <- TRUE
            break
          }
        }
        if (!found) {
          stop(paste("Required input file not found:", filepath))
        }
      }
      
      if (grepl("\\\\.rds\$", filepath, ignore.case = TRUE)) {
        return(readRDS(filepath))
      } else if (grepl("\\\\.csv\$", filepath, ignore.case = TRUE)) {
        return(read.csv(filepath, row.names = 1, check.names = FALSE))
      } else if (grepl("\\\\.(tsv|txt)\$", filepath, ignore.case = TRUE)) {
        return(read.table(filepath, header = TRUE, row.names = 1, sep = "\t", check.names = FALSE))
      } else {
        # Fallback: try RDS, then try read.table
        res <- tryCatch(readRDS(filepath), error = function(e) NULL)
        if (!is.null(res)) return(res)
        return(read.table(filepath, header = TRUE, row.names = 1, check.names = FALSE))
      }
    }
    
    # Load user inputs
    exprs.1 <- load_expression_data("exprs.1")
    exprs.2 <- load_expression_data("exprs.2")
    
    # Align genes to ensure they have the exact same genes in the exact same order
    is_se1 <- inherits(exprs.1, "SummarizedExperiment")
    is_se2 <- inherits(exprs.2, "SummarizedExperiment")
    
    if (is_se1 && is_se2) {
      common_genes <- intersect(rownames(exprs.1), rownames(exprs.2))
      if (length(common_genes) == 0) {
        stop("No common genes found between exprs.1 and exprs.2.")
      }
      exprs.1 <- exprs.1[common_genes, ]
      exprs.2 <- exprs.2[common_genes, ]
    } else {
      # Ensure they are matrices or data frames
      if (is_se1) exprs.1 <- as.matrix(SummarizedExperiment::assay(exprs.1))
      if (is_se2) exprs.2 <- as.matrix(SummarizedExperiment::assay(exprs.2))
      
      common_genes <- intersect(rownames(exprs.1), rownames(exprs.2))
      if (length(common_genes) == 0) {
        stop("No common genes found between exprs.1 and exprs.2.")
      }
      exprs.1 <- exprs.1[common_genes, , drop = FALSE]
      exprs.2 <- exprs.2[common_genes, , drop = FALSE]
      
      # Convert to matrix to ensure numeric compatibility
      exprs.1 <- as.matrix(exprs.1)
      exprs.2 <- as.matrix(exprs.2)
    }
    
    # Enable multi-threading
    allowWGCNAThreads()
    
    # Run differential coexpression analysis
    res=diffcoexp(exprs.1 = exprs.1, exprs.2 = exprs.2, r.method = "spearman" )
    
    # Inspect the structure of the output
    str(res)
    
    # Save results
    saveRDS(res, "diffcoexp_results.rds")
    
    if (!is.null(res\$DCGs) && nrow(res\$DCGs) > 0) {
      write.csv(res\$DCGs, "diffcoexp_DCGs.csv", row.names = FALSE)
    } else {
      write.csv(data.frame(Message = "No DCGs identified"), "diffcoexp_DCGs.csv", row.names = FALSE)
    }
    
    if (!is.null(res\$DCLs) && nrow(res\$DCLs) > 0) {
      write.csv(res\$DCLs, "diffcoexp_DCLs.csv", row.names = FALSE)
      
      # Generate a visualization plot of the correlation differences
      pdf("diffcoexp_plots.pdf", width = 7, height = 5)
      hist(res\$DCLs\$cor.diff, 
           breaks = 30, 
           col = "skyblue", 
           main = "Distribution of Correlation Differences (DCLs)", 
           xlab = "Correlation Difference (Condition 2 - Condition 1)")
      dev.off()
    } else {
      write.csv(data.frame(Message = "No DCLs identified"), "diffcoexp_DCLs.csv", row.names = FALSE)
    }

    writeLines(c(
        '"BIOC_DIFFCOEXP_DIFFERENTIAL_COEXPRESSION_ANALYSIS":',
        paste0('    diffcoexp: ', as.character(packageVersion('diffcoexp')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_coexpression_analysis.csv versions.yml
    """
}

workflow BIOC_DIFFCOEXP_DIFFERENTIAL_COEXPRESSION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ exprs.1, exprs.2 ] ]

    main:
    BIOC_DIFFCOEXP_DIFFERENTIAL_COEXPRESSION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_DIFFCOEXP_DIFFERENTIAL_COEXPRESSION_ANALYSIS.out.tables
    plots    = BIOC_DIFFCOEXP_DIFFERENTIAL_COEXPRESSION_ANALYSIS.out.plots
    objects  = BIOC_DIFFCOEXP_DIFFERENTIAL_COEXPRESSION_ANALYSIS.out.objects
    versions = BIOC_DIFFCOEXP_DIFFERENTIAL_COEXPRESSION_ANALYSIS.out.versions
}
