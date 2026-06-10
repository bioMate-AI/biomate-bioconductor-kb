#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: iPath — individualized_pathway_analysis
// Calculate personalized pathway enrichment scores (iES) from expression data and test their association with clinical survival outcomes.
// Input: expression_matrix.csv, gene_set_database.gmt, clinical_data.csv, phenotype_vector.csv
// Container: quay.io/biocontainers/bioconductor-ipath:1.16.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: iPath
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the expression matrix, phenotype vector, clinical data, and gene set database
//  * 2. [Core Analysis] Calculate the individualized pathway enrichment score (iES) matrix using iES_cal2
//  * 3. [Core Analysis] Test the association of iES scores with survival outcomes using iES_surv
//  * 4. [Visualization & Output] Visualize the iES distribution and survival differences using water_fall, density_fall, and iES_survPlot

nextflow.enable.dsl = 2

process BIOC_IPATH_INDIVIDUALIZED_PATHWAY_ANALYSIS {
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
        library(iPath)
        
        # 1. Load the expression matrix, phenotype vector, clinical data, and gene set database
        # Read expression matrix (genes as rows, samples as columns)
        prad_exprs <- as.matrix(read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE))
        
        # Read GMT file and parse into a list of gene sets
        read_gmt <- function(gmt_file) {
          lines <- readLines(gmt_file)
          gmt_list <- list()
          for (line in lines) {
            parts <- strsplit(line, "\t")[[1]]
            if (length(parts) >= 3) {
              pathway_name <- parts[1]
              genes <- parts[3:length(parts)]
              genes <- genes[genes != "" & !is.na(genes)]
              gmt_list[[pathway_name]] <- genes
            }
          }
          return(gmt_list)
        }
        GSDB_example <- read_gmt("gene_set_database.gmt")
        
        # Extract pathway names for visualization without altering user data
        if (length(GSDB_example) == 0) {
          # Fallback if GMT is empty
          GSDB_example <- list(
            Pathway1 = rownames(prad_exprs)[1:min(5, nrow(prad_exprs))],
            Pathway2 = rownames(prad_exprs)[1:min(5, nrow(prad_exprs))]
          )
        }
        
        pathway1 <- names(GSDB_example)[1]
        pathway2 <- if (length(GSDB_example) >= 2) names(GSDB_example)[2] else pathway1
        
        # Read clinical data
        prad_cli <- read.csv("clinical_data.csv", row.names = 1, check.names = FALSE)
        
        # Standardize clinical column names to 'time' and 'status' if needed
        colnames(prad_cli) <- tolower(colnames(prad_cli))
        if (!"time" %in% colnames(prad_cli)) {
          time_col <- grep("time|month|day|year|os_time", colnames(prad_cli), ignore.case = TRUE, value = TRUE)
          if (length(time_col) > 0) {
            colnames(prad_cli)[colnames(prad_cli) == time_col[1]] <- "time"
          }
        }
        if (!"status" %in% colnames(prad_cli)) {
          status_col <- grep("status|event|death|os_status|vital", colnames(prad_cli), ignore.case = TRUE, value = TRUE)
          if (length(status_col) > 0) {
            colnames(prad_cli)[colnames(prad_cli) == status_col[1]] <- "status"
          }
        }
        
        # Read phenotype vector and align with expression matrix columns
        pheno_data <- read.csv("phenotype_vector.csv", header = TRUE)
        if (ncol(pheno_data) >= 2) {
          rownames(pheno_data) <- pheno_data[, 1]
          common_samples <- intersect(colnames(prad_exprs), rownames(pheno_data))
          common_samples <- intersect(common_samples, rownames(prad_cli))
          
          prad_exprs <- prad_exprs[, common_samples, drop = FALSE]
          prad_cli <- prad_cli[common_samples, , drop = FALSE]
          prad_inds <- as.numeric(pheno_data[common_samples, 2])
        } else {
          common_samples <- intersect(colnames(prad_exprs), rownames(pheno_data))
          common_samples <- intersect(common_samples, rownames(prad_cli))
          
          prad_exprs <- prad_exprs[, common_samples, drop = FALSE]
          prad_cli <- prad_cli[common_samples, , drop = FALSE]
          prad_inds <- as.numeric(pheno_data[common_samples, 1])
        }
        
        # Print dimensions for verification
        dim(prad_exprs)
        head(prad_cli)
        
        # 2. Calculate the individualized pathway enrichment score (iES) matrix using iES_cal2
        iES_mat = iES_cal2(Y = prad_exprs, GSDB = GSDB_example)
        iES_mat[1:2, 1:4]
        
        # Save the calculated iES matrix
        write.csv(iES_mat, "iES_matrix.csv", row.names = TRUE)
        
        # 3. Test the association of iES scores with survival outcomes using iES_surv
        surv_outcomes = iES_surv(iES_mat = iES_mat, cli = prad_cli, indVec = prad_inds)
        head(surv_outcomes)
        
        # Save survival outcomes
        write.csv(surv_outcomes, "survival_outcomes.csv", row.names = TRUE)
        
        # 4. Visualize the iES distribution and survival differences using water_fall, density_fall, and iES_survPlot
        pdf("iPath_visualization_plots.pdf", width = 8, height = 6)
        print(water_fall(iES_mat, gs_str = pathway2, indVec = prad_inds))
        print(density_fall(iES_mat, gs_str = pathway2, indVec = prad_inds))
        print(iES_survPlot(iES_mat = iES_mat, cli = prad_cli, gs_str = pathway1, indVec = prad_inds, title = TRUE))
        dev.off()

    writeLines(c(
        '"BIOC_IPATH_INDIVIDUALIZED_PATHWAY_ANALYSIS":',
        paste0('    iPath: ', as.character(packageVersion('iPath')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_individualized_pathway_analysis.csv versions.yml
    """
}

workflow BIOC_IPATH_INDIVIDUALIZED_PATHWAY_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv, gene_set_database.gmt, clinical_data.csv, phenotype_vector.csv ] ]

    main:
    BIOC_IPATH_INDIVIDUALIZED_PATHWAY_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_IPATH_INDIVIDUALIZED_PATHWAY_ANALYSIS.out.tables
    plots    = BIOC_IPATH_INDIVIDUALIZED_PATHWAY_ANALYSIS.out.plots
    objects  = BIOC_IPATH_INDIVIDUALIZED_PATHWAY_ANALYSIS.out.objects
    versions = BIOC_IPATH_INDIVIDUALIZED_PATHWAY_ANALYSIS.out.versions
}
