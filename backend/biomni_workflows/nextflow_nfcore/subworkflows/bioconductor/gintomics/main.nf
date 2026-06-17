#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: gINTomics — two_omics_integration
// Integrate gene or miRNA expression data with a single genomic modification (CNV or methylation) or transcriptional regulator (TF or miRNA) using individual matr
// Input: gene_exp_matrix.csv, cnv_matrix.csv, meth_matrix.csv, miRNA_exp_matrix.csv
// Container: quay.io/biocontainers/r-base:4.3.1
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: gINTomics
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Transpose input matrices so that samples are represented as rows and features as columns
//  * 2. [Core Analysis] Run the specific integration function (run_genomic_integration, run_cnv_integration, run_met_integration, or run_tf_integration)
//  * 3. [Visualization & Output] Summarize the integration model results using summary

nextflow.enable.dsl = 2

process BIOC_GINTOMICS_TWO_OMICS_INTEGRATION {
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
    .bm_deps <- c("gINTomics")
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
        library(gINTomics)
        
        # Read user input files from the working directory
        gene_exp_matrix  <- as.matrix(read.csv("gene_exp_matrix.csv", row.names = 1, check.names = FALSE))
        gene_cnv_matrix  <- as.matrix(read.csv("cnv_matrix.csv", row.names = 1, check.names = FALSE))
        meth_matrix      <- as.matrix(read.csv("meth_matrix.csv", row.names = 1, check.names = FALSE))
        miRNA_exp_matrix <- as.matrix(read.csv("miRNA_exp_matrix.csv", row.names = 1, check.names = FALSE))
        
        # 1. Run Genomic Integration (Gene Expression ~ CNV + Methylation)
        gene_genomic_integration <- run_genomic_integration(expression = t(gene_exp_matrix),
                                                            cnv_data = t(gene_cnv_matrix),
                                                            methylation = t(meth_matrix))
        summary(gene_genomic_integration)
        saveRDS(gene_genomic_integration, "gene_genomic_integration.rds")
        
        # 2. Run CNV Integration (Gene Expression ~ CNV)
        gene_cnv_integration <- run_cnv_integration(expression = t(gene_exp_matrix),
                                                    cnv_data = t(gene_cnv_matrix))
        summary(gene_cnv_integration)
        saveRDS(gene_cnv_integration, "gene_cnv_integration.rds")
        
        # 3. Run Methylation Integration (Gene Expression ~ Methylation)
        gene_met_integration <- run_met_integration(expression = t(gene_exp_matrix),
                                                    methylation = t(meth_matrix))
        summary(gene_met_integration)
        saveRDS(gene_met_integration, "gene_met_integration.rds")
        
        # 4. Run TF-target Integration (Gene Expression ~ TF Expression)
        tf_target_integration <- run_tf_integration(expression = t(gene_exp_matrix),
                                                    type = "tf")
        summary(tf_target_integration)
        saveRDS(tf_target_integration, "tf_target_integration.rds")
        
        # 5. Run miRNA-target Integration (Gene Expression ~ miRNA Expression)
        miRNA_target_integration <- run_tf_integration(expression = t(gene_exp_matrix),
                                                       tf_expression = t(miRNA_exp_matrix),
                                                       type = "miRNA_target")
        summary(miRNA_target_integration)
        saveRDS(miRNA_target_integration, "miRNA_target_integration.rds")
        
        # 6. Run TF-miRNA Integration (miRNA Expression ~ TF Expression)
        tf_miRNA_integration <- run_tf_integration(expression = t(miRNA_exp_matrix),
                                                   tf_expression = t(gene_exp_matrix),
                                                   type = "tf_miRNA")
        summary(tf_miRNA_integration)
        saveRDS(tf_miRNA_integration, "tf_miRNA_integration.rds")
        
        # Helper function to export integration results to CSV files
        export_results <- function(integration_obj, prefix) {
          if (!is.null(integration_obj\$coef_data)) {
            for (i in seq_along(integration_obj\$coef_data)) {
              n <- names(integration_obj\$coef_data)[i]
              suffix <- if (!is.null(n) && n != "") paste0("_", n) else paste0("_", i)
              write.csv(integration_obj\$coef_data[[i]], paste0(prefix, "_coefficients", suffix, ".csv"), row.names = TRUE)
            }
          }
          if (!is.null(integration_obj\$pval_data)) {
            for (i in seq_along(integration_obj\$pval_data)) {
              n <- names(integration_obj\$pval_data)[i]
              suffix <- if (!is.null(n) && n != "") paste0("_", n) else paste0("_", i)
              write.csv(integration_obj\$pval_data[[i]], paste0(prefix, "_pvalues", suffix, ".csv"), row.names = TRUE)
            }
          }
          if (!is.null(integration_obj\$fdr_data)) {
            for (i in seq_along(integration_obj\$fdr_data)) {
              n <- names(integration_obj\$fdr_data)[i]
              suffix <- if (!is.null(n) && n != "") paste0("_", n) else paste0("_", i)
              write.csv(integration_obj\$fdr_data[[i]], paste0(prefix, "_fdr", suffix, ".csv"), row.names = TRUE)
            }
          }
        }
        
        # Export all results to CSV
        export_results(gene_genomic_integration, "gene_genomic")
        export_results(gene_cnv_integration, "gene_cnv")
        export_results(gene_met_integration, "gene_met")
        export_results(tf_target_integration, "tf_target")
        export_results(miRNA_target_integration, "miRNA_target")
        export_results(tf_miRNA_integration, "tf_miRNA")

    writeLines(c(
        '"BIOC_GINTOMICS_TWO_OMICS_INTEGRATION":',
        paste0('    gINTomics: ', as.character(packageVersion('gINTomics')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_two_omics_integration.csv versions.yml
    """
}

workflow BIOC_GINTOMICS_TWO_OMICS_INTEGRATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gene_exp_matrix.csv, cnv_matrix.csv, meth_matrix.csv, miRNA_exp_matrix.csv ] ]

    main:
    BIOC_GINTOMICS_TWO_OMICS_INTEGRATION(ch_input)

    emit:
    tables   = BIOC_GINTOMICS_TWO_OMICS_INTEGRATION.out.tables
    plots    = BIOC_GINTOMICS_TWO_OMICS_INTEGRATION.out.plots
    objects  = BIOC_GINTOMICS_TWO_OMICS_INTEGRATION.out.objects
    versions = BIOC_GINTOMICS_TWO_OMICS_INTEGRATION.out.versions
}
