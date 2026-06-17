#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: qusage — standard_qusage_analysis
// Perform standard gene set enrichment analysis on a single dataset, calculate p-values, adjust for multiple testing, and visualize pathway activity.
// Input: eset, gene_sets.gmt
// Container: quay.io/biocontainers/bioconductor-qusage:2.44.0--r45hdfd78af_1
// R packages: Biobase, nlme, qusage
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, nlme, qusage
// Visualizations: density plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read gene sets from a GMT file using read.gmt
//  * 2. [Core Analysis] Run the qusage wrapper function to calculate gene-level comparisons, aggregate gene data, and calculate variance inflation factors
//  * 3. [Core Analysis] Extract p-values using pdf.pVal
//  * 4. [Core Analysis] Adjust p-values for multiple testing using p.adjust
//  * 5. [Visualization & Output] Generate a summary table of results using qsTable
//  * 6. [Visualization & Output] Plot confidence intervals or density curves using plot or plotDensityCurves

nextflow.enable.dsl = 2

process BIOC_QUSAGE_STANDARD_QUSAGE_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("Biobase", "nlme", "qusage")
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
            library(qusage)
            library(nlme)
            library(Biobase)
            
            # ----------------------------------------------------------------------
            # Stage 1: Read User Input Files
            # ----------------------------------------------------------------------
            
            # Read eset (matrix or ExpressionSet of log2-normalized gene expression data)
            if (file.exists("eset")) {
              eset <- tryCatch({
                readRDS("eset")
              }, error = function(e) {
                as.matrix(read.csv("eset", row.names = 1, check.names = FALSE))
              })
            } else {
              stop("Required input file 'eset' not found in the working directory.")
            }
            
            # Read gene_sets.gmt (GMT file containing gene sets of interest)
            if (file.exists("gene_sets.gmt")) {
              gene_sets <- read.gmt("gene_sets.gmt")
            } else {
              stop("Required input file 'gene_sets.gmt' not found in the working directory.")
            }
            
            # ----------------------------------------------------------------------
            # Stage 2: Define Labels and Run qusage
            # ----------------------------------------------------------------------
            
            # Extract expression matrix if eset is an ExpressionSet
            if (inherits(eset, "ExpressionSet")) {
              expr_mat <- exprs(eset)
            } else {
              expr_mat <- eset
            }
            
            # Create generic labels for the two groups (first half vs second half)
            n_samples <- ncol(expr_mat)
            half <- floor(n_samples / 2)
            labels <- c(rep("Control", half), rep("Treatment", n_samples - half))
            contrast <- "Treatment-Control"
            
            # Run the standard qusage wrapper function
            qusage.result <- qusage(expr_mat, labels, contrast, gene_sets)
            
            # Extract and save the qusage table
            tbl_qusage <- qsTable(qusage.result, number = length(gene_sets))
            write.csv(tbl_qusage, "qs_table.csv", row.names = FALSE)
            saveRDS(qusage.result, "qusage_result.rds")
            
            # ----------------------------------------------------------------------
            # Stage 3: Extract and Adjust p-values
            # ----------------------------------------------------------------------
            
            # Extract p-values
            p.vals <- pdf.pVal(qusage.result)
            
            # Adjust p-values for multiple testing
            q.vals <- p.adjust(p.vals, method="fdr")
            
            # Save p-values and adjusted p-values
            pvals_df <- data.frame(Pathway = names(p.vals), p.value = p.vals, FDR = q.vals)
            write.csv(pvals_df, "qusage_pvalues.csv", row.names = FALSE)
            
            # ----------------------------------------------------------------------
            # Stage 4: Plot Results
            # ----------------------------------------------------------------------
            
            pdf("density_curves_comparison.pdf", width = 8, height = 6)
            # Select the top 5 gene sets based on p-values for plotting
            topSets <- order(p.vals)[1:min(5, length(p.vals))]
            
            plotDensityCurves(qusage.result, path.index=topSets, col=1:length(topSets), 
                              lwd=2, xlab=expression(log[2](Activity)))
            legend("topright", legend=names(p.vals)[topSets], 
                   col=1:length(topSets), lty=1, lwd=2, cex=0.8)
            dev.off()

    writeLines(c(
        '"BIOC_QUSAGE_STANDARD_QUSAGE_ANALYSIS":',
        paste0('    qusage: ', as.character(packageVersion('qusage')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_qusage_analysis.csv versions.yml
    """
}

workflow BIOC_QUSAGE_STANDARD_QUSAGE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ eset, gene_sets.gmt ] ]

    main:
    BIOC_QUSAGE_STANDARD_QUSAGE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_QUSAGE_STANDARD_QUSAGE_ANALYSIS.out.tables
    plots    = BIOC_QUSAGE_STANDARD_QUSAGE_ANALYSIS.out.plots
    objects  = BIOC_QUSAGE_STANDARD_QUSAGE_ANALYSIS.out.objects
    versions = BIOC_QUSAGE_STANDARD_QUSAGE_ANALYSIS.out.versions
}
