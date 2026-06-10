#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: twilight — differential_expression_analysis
// Test for differential gene expression between two conditions and estimate local false discovery rates.
// Input: expression_matrix.csv, phenotype_labels.csv
// Container: quay.io/biocontainers/bioconductor-twilight:1.86.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: twilight
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Compute permutation-based p-values and q-values using twilight.pval
//  * 2. [Core Analysis] Estimate local false discovery rates and bootstrap confidence intervals using twilight
//  * 3. [Visualization & Output] Plot expected vs observed scores, q-values, local FDR curve, volcano plot, and effect size distribution

nextflow.enable.dsl = 2

process BIOC_TWILIGHT_DIFFERENTIAL_EXPRESSION_ANALYSIS {
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
    library(twilight)
    
    # Validate presence of user input files
    if (!file.exists("expression_matrix.csv") || !file.exists("phenotype_labels.csv")) {
      stop("Required input files 'expression_matrix.csv' and/or 'phenotype_labels.csv' are missing in the working directory.")
    }
    
    # Read user input files
    # expression_matrix.csv: normalized gene expression matrix on additive scale (genes in rows, samples in columns)
    expr_mat <- as.matrix(read.csv("expression_matrix.csv", row.names=1, check.names=FALSE))
    
    # phenotype_labels.csv: binary condition labels for samples
    pheno <- read.csv("phenotype_labels.csv", check.names=FALSE)
    
    # Align phenotype labels with expression matrix columns if sample IDs are provided
    if (ncol(pheno) >= 2 && any(pheno[[1]] %in% colnames(expr_mat))) {
      rownames(pheno) <- pheno[[1]]
      pheno <- pheno[colnames(expr_mat), ]
      id <- as.numeric(as.factor(pheno[[2]]))
    } else {
      id <- as.numeric(as.factor(pheno[[1]]))
    }
    
    # Map to the variable name used in the documented code
    golubNorm <- expr_mat
    
    # Stage 1: Compute permutation-based p-values and q-values using twilight.pval
    pval <- twilight.pval(golubNorm, id, B=100)
    expval <- pval
    
    # Stage 2: Estimate local false discovery rates and bootstrap confidence intervals using twilight
    exfdr <- twilight(expval, B=100)
    
    # Stage 3: Plot expected vs observed scores, q-values, local FDR curve, volcano plot, and effect size distribution
    pdf("twilight_plots.pdf", width=8, height=6)
    
    plot(expval,which="scores",grayscale=F,legend=F)
    plot(expval,which="qvalues")
    plot(exfdr,which="fdr",grayscale=F,legend=T)
    plot(exfdr,which="volcano")
    plot(exfdr,which="effectsize",legend=T)
    tab <- plot(exfdr,which="table")
    
    dev.off()
    
    # Write meaningful results to output files
    write.csv(expval\$result, "twilight_pval_results.csv", row.names=TRUE)
    write.csv(exfdr\$result, "twilight_fdr_results.csv", row.names=TRUE)
    write.csv(tab, "twilight_effectsize_table.csv", row.names=TRUE)
    saveRDS(exfdr, "twilight_fdr_object.rds")

    writeLines(c(
        '"BIOC_TWILIGHT_DIFFERENTIAL_EXPRESSION_ANALYSIS":',
        paste0('    twilight: ', as.character(packageVersion('twilight')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_expression_analysis.csv versions.yml
    """
}

workflow BIOC_TWILIGHT_DIFFERENTIAL_EXPRESSION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv, phenotype_labels.csv ] ]

    main:
    BIOC_TWILIGHT_DIFFERENTIAL_EXPRESSION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_TWILIGHT_DIFFERENTIAL_EXPRESSION_ANALYSIS.out.tables
    plots    = BIOC_TWILIGHT_DIFFERENTIAL_EXPRESSION_ANALYSIS.out.plots
    objects  = BIOC_TWILIGHT_DIFFERENTIAL_EXPRESSION_ANALYSIS.out.objects
    versions = BIOC_TWILIGHT_DIFFERENTIAL_EXPRESSION_ANALYSIS.out.versions
}
