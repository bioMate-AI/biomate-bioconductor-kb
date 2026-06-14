#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GlobalAncova — generalized_and_hierarchical_testing
// Apply global testing to non-quantitative or mixed variables (e.g., SNPs) and perform hierarchical testing to identify significant variable clusters.
// Input: variable_matrix.csv, phenotype_data.csv
// Container: quay.io/biocontainers/bioconductor-globalancova:4.28.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GlobalAncova
// Visualizations: dendrogram
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Run generalized GlobalAncova to test for global
//  * 2. [Visualization & Output] Generate a features plot to visualize variable-wise
//  * 3. [Visualization & Output] Cluster the variables to create a dendrogram hierarchy
//  * 4. [Visualization & Output] Perform hierarchical testing down the dendrogram to
//  * 5. [Visualization & Output] Plot the hierarchy highlighting significant paths

nextflow.enable.dsl = 2

process BIOC_GLOBALANCOVA_GENERALIZED_AND_HIERARCHICAL_TESTING {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("GlobalAncova")
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
    library(GlobalAncova)
    
    # Check for required input files
    if (!file.exists("variable_matrix.csv") || !file.exists("phenotype_data.csv")) {
      stop("Required input files 'variable_matrix.csv' and/or 'phenotype_data.csv' are missing in the working directory.")
    }
    
    # Helper function to read input files robustly
    read_input <- function(file) {
      df <- read.csv(file, stringsAsFactors = TRUE, check.names = FALSE)
      # If the first column is non-numeric, treat it as row names
      if (is.character(df[[1]]) || is.factor(df[[1]])) {
        rownames(df) <- as.character(df[[1]])
        df <- df[, -1, drop = FALSE]
      }
      return(df)
    }
    
    # Read phenotype data
    bindata <- read_input("phenotype_data.csv")
    
    # Ensure the 'group' column exists in bindata (rename first column if missing)
    if (!"group" %in% colnames(bindata)) {
      colnames(bindata)[1] <- "group"
    }
    
    # Read variable matrix (e.g., SNPs, categorical or mixed variables)
    X_df <- read_input("variable_matrix.csv")
    X <- as.matrix(X_df)
    
    # Align samples between X and bindata
    common_samples <- intersect(rownames(X), rownames(bindata))
    if (length(common_samples) > 0) {
      X <- X[common_samples, , drop = FALSE]
      bindata <- bindata[common_samples, , drop = FALSE]
    } else {
      stop("No matching sample IDs found between variable_matrix.csv and phenotype_data.csv.")
    }
    
    # --- Run generalized GlobalAncova to test for global ---
    ga_global <- gGlobalAncova(X, formula.full=~group, model.dat=bindata, perm=1000)
    write.csv(ga_global\$ANOVA, "global_ancova_anova.csv", row.names = TRUE)
    write.csv(ga_global\$test.result, "global_ancova_test_results.csv", row.names = TRUE)
    
    # --- Generate a features plot to visualize variable-wise ---
    pdf("features_plot.pdf", width = 10, height = 8)
    Plot.features(X, formula.full=~group, model.dat=bindata)
    dev.off()
    
    # --- Cluster the variables to create a dendrogram hierarchy ---
    dend <- as.dendrogram(hclust(dist(t(X))))
    
    # --- Perform hierarchical testing down the dendrogram to ---
    set.seed(555)
    res <- gGlobalAncova.hierarchical(X, H=dend, formula.full=~group, model.dat=bindata, alpha=0.05, perm=1000)
    
    # Save the hierarchical test object
    saveRDS(res, "hierarchical_results.rds")
    
    # Save significant end nodes and results table
    res_table <- results(res)
    write.csv(res_table, "hierarchical_significant_nodes.csv", row.names = TRUE)
    
    sig_nodes <- sigEndnodes(res)
    if (!is.null(sig_nodes) && length(sig_nodes) > 0) {
      nodes_df <- data.frame(
        Node = rep(names(sig_nodes), lengths(sig_nodes)),
        Variable = unlist(sig_nodes, use.names = FALSE)
      )
      write.csv(
        nodes_df,
        "significant_endnodes.csv",
        row.names = FALSE
      )
    } else {
      write.csv(
        data.frame(Message = "No significant end nodes found at alpha = 0.05"),
        "significant_endnodes.csv",
        row.names = FALSE
      )
    }
    
    # --- Plot the hierarchy highlighting significant paths ---
    pdf("hierarchy_plot.pdf", width = 12, height = 8)
    Plot.hierarchy(res, dend)
    dev.off()

    writeLines(c(
        '"BIOC_GLOBALANCOVA_GENERALIZED_AND_HIERARCHICAL_TESTING":',
        paste0('    GlobalAncova: ', as.character(packageVersion('GlobalAncova')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_generalized_and_hierarchical_testing.csv versions.yml
    """
}

workflow BIOC_GLOBALANCOVA_GENERALIZED_AND_HIERARCHICAL_TESTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ variable_matrix.csv, phenotype_data.csv ] ]

    main:
    BIOC_GLOBALANCOVA_GENERALIZED_AND_HIERARCHICAL_TESTING(ch_input)

    emit:
    tables   = BIOC_GLOBALANCOVA_GENERALIZED_AND_HIERARCHICAL_TESTING.out.tables
    plots    = BIOC_GLOBALANCOVA_GENERALIZED_AND_HIERARCHICAL_TESTING.out.plots
    objects  = BIOC_GLOBALANCOVA_GENERALIZED_AND_HIERARCHICAL_TESTING.out.objects
    versions = BIOC_GLOBALANCOVA_GENERALIZED_AND_HIERARCHICAL_TESTING.out.versions
}
