#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: pairkat — pairkat_pathway_association
// Align metabolomics intensity data with sample metadata, build KEGG-based pathway networks, and perform pathway-integrated kernel association testing against a p
// Input: intensity.csv, coldata.csv
// Container: 1.16.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, dplyr, pairkat
// Visualizations: network plot
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PAIRKAT_PAIRKAT_PATHWAY_ASSOCIATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metabolomics:3.20-deps"

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
    .bm_deps <- c("pairkat", "dplyr", "SummarizedExperiment")
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
    
    # Load required librari    library(SummarizedExperiment)
es
    library(pairkat)
    library(dplyr)
    
    # ==========================================
    # --- Load and Preprocess Input Data ---
    # ==========================================
    
    message("Loading input files...")
    intensity_df <- read.csv("intensity.csv", check.names = FALSE)
    coldata_df <- read.csv("coldata.csv", check.names = FALSE)
    
    # Ensure feature_id is present and set as row names
    if (!"feature_id" %in% colnames(intensity_df)) {
      stop("intensity.csv must contain a 'feature_id' column.")
    }
    rownames(intensity_df) <- intensity_df\$feature_id
    intensity_matrix <- as.matrix(intensity_df[, -which(names(intensity_df) == "feature_id"), drop = FALSE])
    
    # Ensure sample column is present in coldata
    if (!"sample" %in% colnames(coldata_df)) {
      stop("coldata.csv must contain a 'sample' column.")
    }
    rownames(coldata_df) <- coldata_df\$sample
    
    # Align samples between intensity matrix and coldata
    common_samples <- intersect(colnames(intensity_matrix), rownames(coldata_df))
    if (length(common_samples) == 0) {
      stop("No matching sample IDs found between intensity.csv and coldata.csv.")
    }
    message(paste("Aligned", length(common_samples), "samples for analysis."))
    
    intensity_matrix <- intensity_matrix[, common_samples, drop = FALSE]
    coldata_df <- coldata_df[common_samples, , drop = FALSE]
    
    # Ensure the phenotype/condition variable is numeric (binary 0/1 or continuous)
    if ("condition" %in% colnames(coldata_df)) {
      if (is.character(coldata_df\$condition) || is.factor(coldata_df\$condition)) {
        coldata_df\$condition <- as.numeric(as.factor(coldata_df\$condition)) - 1
        message("Converted categorical 'condition' to numeric dummy variable.")
      }
    } else {
      stop("coldata.csv must contain a 'condition' column representing the phenotype.")
    }
    
    # ==========================================
    # --- Construct SummarizedExperiment ---
    # ==========================================
    
    message("Constructing SummarizedExperiment object...")
    # Create rowData mapping features to KEGG IDs (assuming feature_ids are KEGG IDs)
    row_data <- data.frame(
      kegg_id = rownames(intensity_matrix),
      row.names = rownames(intensity_matrix),
      stringsAsFactors = FALSE
    )
    
    se <- SummarizedExperiment::SummarizedExperiment(
      assays = list(metabolomics = intensity_matrix),
      rowData = row_data,
      colData = coldata_df
    )
    
    # ==========================================
    # --- Query KEGG and Build Networks ---
    # ==========================================
    
    message("Querying KEGG database to build networks...")
    networks <- tryCatch({
      GatherNetworks(
        SE = se,
        keggID = "kegg_id",
        species = "hsa",
        minPathwaySize = 5
      )
    }, error = function(e) {
      message("Warning: GatherNetworks failed. Attempting with minPathwaySize = 2...")
      tryCatch({
        GatherNetworks(
          SE = se,
          keggID = "kegg_id",
          species = "hsa",
          minPathwaySize = 2
        )
      }, error = function(err) {
        message("Error: Network gathering failed completely: ", err\$message)
        NULL
      })
    })
    
    # ==========================================
    # --- Run PaIRKAT Association Testing ---
    # ==========================================
    
    results_df <- data.frame(pathway = character(), Q.adj = numeric(), p.value = numeric())
    output <- NULL
    
    if (!is.null(networks) && length(networks) > 0) {
      message("Running PaIRKAT kernel association test...")
      output <- tryCatch({
        PaIRKAT(formula.H0 = condition ~ 1, networks = networks)
      }, error = function(e) {
        message("Error running PaIRKAT: ", e\$message)
        NULL
      })
    } else {
      message("No valid networks were constructed. Skipping PaIRKAT.")
    }
    
    # ==========================================
    # --- Export Results and Visualizations ---
    # ==========================================
    
    if (!is.null(output) && !is.null(output\$results) && nrow(output\$results) > 0) {
      message("Processing and saving results...")
      results_df <- dplyr::arrange(output\$results, p.value)
      write.csv(results_df, "pairkat_results.csv", row.names = FALSE)
      
      # Plot the top significant pathway network
      top_pathway <- results_df\$pathway[1]
      message(paste("Plotting network for top pathway:", top_pathway))
      
      pdf("pathway_network.pdf", width = 8, height = 8)
      tryCatch({
        plotNetworks(networks = networks, pathway = top_pathway)
      }, error = function(e) {
        plot.new()
        text(0.5, 0.5, paste("Failed to plot pathway:\n", top_pathway, "\nError:", e\$message), cex = 0.8)
      })
      dev.off()
    } else {
      message("Writing empty fallback outputs due to lack of results.")
      write.csv(results_df, "pairkat_results.csv", row.names = FALSE)
      
      pdf("pathway_network.pdf", width = 8, height = 8)
      plot.new()
      text(0.5, 0.5, "No pathways or networks available to plot.", cex = 1.2)
      dev.off()
    }
    
    message("Pipeline complete.")

    writeLines(c(
        '"BIOC_PAIRKAT_PAIRKAT_PATHWAY_ASSOCIATION":',
        paste0('    pairkat: ', as.character(packageVersion('pairkat')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pairkat_pathway_association.csv versions.yml
    """
}

workflow BIOC_PAIRKAT_PAIRKAT_PATHWAY_ASSOCIATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_PAIRKAT_PAIRKAT_PATHWAY_ASSOCIATION(ch_input)

    emit:
    tables   = BIOC_PAIRKAT_PAIRKAT_PATHWAY_ASSOCIATION.out.tables
    plots    = BIOC_PAIRKAT_PAIRKAT_PATHWAY_ASSOCIATION.out.plots
    objects  = BIOC_PAIRKAT_PAIRKAT_PATHWAY_ASSOCIATION.out.objects
    versions = BIOC_PAIRKAT_PAIRKAT_PATHWAY_ASSOCIATION.out.versions
}
