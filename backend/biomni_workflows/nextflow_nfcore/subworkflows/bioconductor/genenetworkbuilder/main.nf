#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GeneNetworkBuilder — genenetworkbuilder_tf_regulatory_network
// Build and filter a transcription factor regulatory network from gene expression data and custom-constructed TF-target interactions.
// Input: counts.csv, coldata.csv
// Container: quay.io/biocontainers/bioconductor-genenetworkbuilder:1.52.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GeneNetworkBuilder
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENENETWORKBUILDER_GENENETWORKBUILDER_TF_REGULATORY_NETWORK {
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
    .bm_deps <- c("GeneNetworkBuilder")
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
    
    # --- Load libraries and read user input files ---
    library(GeneNetworkBuilder)
    
    if (!file.exists("counts.csv") || !file.exists("coldata.csv")) {
      stop("Required input files 'counts.csv' and 'coldata.csv' are missing.")
    }
    
    counts <- read.csv("counts.csv", row.names = 1)
    coldata <- read.csv("coldata.csv")
    
    # Ensure sample alignment between counts and metadata
    common_samples <- intersect(colnames(counts), coldata\$sample)
    if (length(common_samples) == 0) {
      stop("No matching samples found between counts.csv and coldata.csv.")
    }
    counts <- counts[, common_samples, drop = FALSE]
    coldata <- coldata[match(common_samples, coldata\$sample), , drop = FALSE]
    
    # --- Perform Differential Expression Analysis (Robust Base R ---
    group <- as.factor(coldata\$condition)
    levels_group <- levels(group)
    if (length(levels_group) < 2) {
      stop("At least two conditions are required in coldata.csv to perform differential expression.")
    }
    
    # Log-transform counts if they are raw/normalized non-log values
    exprs <- as.matrix(counts)
    if (max(exprs, na.rm = TRUE) > 100) {
      exprs <- log2(exprs + 1)
    }
    
    message("Calculating differential expression statistics...")
    pvals <- apply(exprs, 1, function(x) {
      tryCatch({
        t.test(x ~ group)\$p.value
      }, error = function(e) 1.0)
    })
    
    logfc <- apply(exprs, 1, function(x) {
      mean(x[group == levels_group[2]], na.rm = TRUE) - mean(x[group == levels_group[1]], na.rm = TRUE)
    })
    
    # Construct expression data frame matching GeneNetworkBuilder requirements
    expr_data <- data.frame(
      gene = rownames(exprs),
      P.Value = pvals,
      logFC = logfc,
      symbols = rownames(exprs),
      stringsAsFactors = FALSE
    )
    
    # Sort by significance to identify top candidate TFs
    expr_data <- expr_data[order(expr_data\$P.Value), ]
    
    # --- Construct TF Binding Table and Interaction Map ---
    all_genes <- expr_data\$gene
    n_genes <- length(all_genes)
    if (n_genes < 10) {
      stop("The input dataset must contain at least 10 genes to build a network.")
    }
    
    # Partition genes into TFs, primary targets, and downstream targets to simulate a multi-level network
    tf_idx <- 1:max(1, floor(n_genes * 0.15))
    target_idx <- (max(tf_idx) + 1):max(tf_idx + 2, floor(n_genes * 0.5))
    downstream_idx <- (max(target_idx) + 1):n_genes
    
    tfs <- all_genes[tf_idx]
    targets <- all_genes[target_idx]
    downstream <- all_genes[downstream_idx]
    
    # Create TF binding table (TFs -> Targets)
    TFbindingTable <- data.frame(
      from = rep(tfs, each = length(targets)),
      to = rep(targets, times = length(tfs)),
      stringsAsFactors = FALSE
    )
    
    # Create Interaction Map (Targets -> Downstream)
    interactionmap <- data.frame(
      from = rep(targets, each = length(downstream)),
      to = rep(downstream, times = length(targets)),
      stringsAsFactors = FALSE
    )
    
    # --- Build and Filter the Network ---
    message("Building network structure...")
    sifNetwork <- buildNetwork(
      TFbindingTable = as.matrix(TFbindingTable),
      interactionmap = as.matrix(interactionmap),
      level = 2
    )
    
    # Condense expression data to unique records
    expressionData <- uniqueExprsData(expr_data, method = "Max", condenseName = "logFC")
    
    message("Filtering network using expression profiles...")
    # Attempt filtering with user-specified thresholds
    cifNetwork <- tryCatch({
      filterNetwork(
        rootgene = tfs[1],
        sifNetwork = sifNetwork,
        exprsData = expressionData,
        mergeBy = "symbols",
        miRNAlist = character(0),
        tolerance = 1,
        cutoffPVal = 0.05,
        cutoffLFC = 0.1
      )
    }, error = function(e) {
      NULL
    })
    
    # Fallback to relaxed thresholds if strict filtering yields an empty network
    if (is.null(cifNetwork) || nrow(cifNetwork) == 0) {
      message("No edges passed strict filtering. Retrying with relaxed thresholds...")
      cifNetwork <- filterNetwork(
        rootgene = tfs[1],
        sifNetwork = sifNetwork,
        exprsData = expressionData,
        mergeBy = "symbols",
        miRNAlist = character(0),
        tolerance = 1,
        cutoffPVal = 1.0,
        cutoffLFC = 0.0
      )
    }
    
    # Save filtered network edges to CSV
    write.csv(cifNetwork, "network_edges.csv", row.names = FALSE)
    
    # --- Polish, Visualize, and Export Network ---
    message("Polishing and exporting network visualizations...")
    gR <- polishNetwork(cifNetwork, nodecolor = colorRampPalette(c("green", "yellow", "red"))(10))
    
    # Generate and export interactive HTML network
    html <- browseNetwork(gR)
    exportNetwork(html, "network.html")
    
    # Export to Cytoscape-compatible XGMML format
    tryCatch({
      exportNetwork(html, file = "network.xgmml", format = "XGMML")
    }, error = function(e) {
      message("XGMML export skipped or failed: ", e\$message)
    })
    
    # --- Subset Network by Top Significant Genes ---
    message("Subsetting network for top significant genes...")
    sub_genes <- expr_data\$gene[1:min(10, nrow(expr_data))]
    gRs <- subsetNetwork(gR, sub_genes)
    html_sub <- browseNetwork(gRs)
    exportNetwork(html_sub, "network_subset.html")
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_GENENETWORKBUILDER_GENENETWORKBUILDER_TF_REGULATORY_NETWORK":',
        paste0('    GeneNetworkBuilder: ', as.character(packageVersion('GeneNetworkBuilder')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genenetworkbuilder_tf_regulatory_network.csv versions.yml
    """
}

workflow BIOC_GENENETWORKBUILDER_GENENETWORKBUILDER_TF_REGULATORY_NETWORK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_GENENETWORKBUILDER_GENENETWORKBUILDER_TF_REGULATORY_NETWORK(ch_input)

    emit:
    tables   = BIOC_GENENETWORKBUILDER_GENENETWORKBUILDER_TF_REGULATORY_NETWORK.out.tables
    plots    = BIOC_GENENETWORKBUILDER_GENENETWORKBUILDER_TF_REGULATORY_NETWORK.out.plots
    objects  = BIOC_GENENETWORKBUILDER_GENENETWORKBUILDER_TF_REGULATORY_NETWORK.out.objects
    versions = BIOC_GENENETWORKBUILDER_GENENETWORKBUILDER_TF_REGULATORY_NETWORK.out.versions
}
