#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Rnits — data_matrix_workflow
// Analyze time-course gene expression data starting from a raw data matrix and separate metadata data frames.
// Input: expression_matrix, probedata_df, phenodata_df
// Container: quay.io/biocontainers/r-base:4.3.1
// R packages: Rnits
// Bioconductor: 3.20 | R: 4.4
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_RNITS_DATA_MATRIX_WORKFLOW {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/r-base:4.3.1"

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
    .bm_deps <- c("Rnits")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    library(Rnits)
    
    # Helper function to read input files robustly
    read_input_file <- function(filename) {
      # Try reading as RDS first
      if (file.exists(filename)) {
        obj <- tryCatch(readRDS(filename), error = function(e) NULL)
        if (!is.null(obj)) return(obj)
        
        obj <- tryCatch(read.csv(filename, stringsAsFactors = FALSE, check.names = FALSE), error = function(e) NULL)
        if (!is.null(obj)) return(obj)
      }
      
      # Try with .csv extension
      csv_file <- paste0(filename, ".csv")
      if (file.exists(csv_file)) {
        return(read.csv(csv_file, stringsAsFactors = FALSE, check.names = FALSE))
      }
      
      # Try with .rds extension
      rds_file <- paste0(filename, ".rds")
      if (file.exists(rds_file)) {
        return(readRDS(rds_file))
      }
      
      stop(paste("Error: File", filename, "not found in the working directory."))
    }
    
    # --- Read User Inputs ---
    message("Reading input files...")
    datdf <- read_input_file("expression_matrix")
    probedata <- read_input_file("probedata_df")
    phenodata <- read_input_file("phenodata_df")
    
    # Ensure datdf is a numeric matrix
    if (is.data.frame(datdf)) {
      # If the first column is non-numeric (e.g., Probe IDs), set as rownames
      if (!is.numeric(datdf[[1]])) {
        rownames(datdf) <- datdf[[1]]
        datdf <- datdf[, -1, drop = FALSE]
      }
      datdf <- as.matrix(datdf)
    }
    
    # Ensure phenodata row names match colnames of datdf
    if (!all(colnames(datdf) %in% rownames(phenodata))) {
      # Try to find a column in phenodata that matches colnames of datdf
      matching_col <- sapply(phenodata, function(col) all(colnames(datdf) %in% col))
      if (any(matching_col)) {
        idx <- which(matching_col)[1]
        rownames(phenodata) <- phenodata[[idx]]
      } else if (nrow(phenodata) == ncol(datdf)) {
        rownames(phenodata) <- colnames(datdf)
      }
    }
    
    # --- Build Rnits object ---
    message("Building Rnits object...")
    rnitsobj0 = build.Rnits(datdf, probedata = probedata, phenodata = phenodata, logscale = TRUE, normmethod = 'Between')
    
    # --- Fit B-spline models ---
    message("Fitting B-spline models...")
    rnitsobj <- fit(rnitsobj0, gene.level = TRUE, clusterallsamples = TRUE)
    
    # Save the fitted object
    saveRDS(rnitsobj, "rnitsobj.rds")
    
    # --- Extract p-values and statistics ---
    message("Extracting statistics...")
    pval <- getPval(rnitsobj)
    write.csv(as.data.frame(pval), "pvalues.csv", row.names = TRUE)
    
    stat <- getStat(rnitsobj)
    write.csv(as.data.frame(stat), "statistics.csv", row.names = TRUE)
    
    cid_table <- table(getCID(rnitsobj))
    write.csv(as.data.frame(cid_table), "cluster_distribution.csv", row.names = FALSE)
    
    fitdata <- getFitModel(rnitsobj)
    write.csv(fitdata, "fit_model_data.csv", row.names = TRUE)
    
    # --- Summarize top genes ---
    message("Summarizing top genes...")
    sum_df <- summary(rnitsobj, top = 10)
    write.csv(sum_df, "summary_top10.csv", row.names = TRUE)
    
    td <- topData(rnitsobj, fdr = 5)
    write.csv(td, "top_genes_data.csv", row.names = TRUE)
    
    # --- Plot gene trajectories ---
    message("Plotting gene trajectories...")
    pdf("top_genes_trajectories.pdf", width = 10, height = 8)
    plotResults(rnitsobj, top = 16)
    dev.off()
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_RNITS_DATA_MATRIX_WORKFLOW":',
        paste0('        Rnits: ', as.character(packageVersion("Rnits")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_data_matrix_workflow.csv versions.yml
    """
}

workflow BIOC_RNITS_DATA_MATRIX_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix, probedata_df, phenodata_df ] ]

    main:
    BIOC_RNITS_DATA_MATRIX_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_RNITS_DATA_MATRIX_WORKFLOW.out.tables
    plots    = BIOC_RNITS_DATA_MATRIX_WORKFLOW.out.plots
    objects  = BIOC_RNITS_DATA_MATRIX_WORKFLOW.out.objects
    versions = BIOC_RNITS_DATA_MATRIX_WORKFLOW.out.versions
}
