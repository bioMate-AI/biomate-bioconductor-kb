#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BioTIP — biotip_tipping_point_analysis
// Identify biological tipping points and critical transition signals (CTS) from gene expression profiles across ordered states or conditions.
// Input: counts.csv, coldata.csv
// Container: 1.24.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BioTIP, GenomicRanges, cluster, igraph, psych, stringr
// Visualizations: trajectory plot
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIOTIP_BIOTIP_TIPPING_POINT_ANALYSIS {
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
    library(BioTIP)
    library(cluster)
    library(GenomicRanges)
    library(MASS)
    library(stringr)
    library(psych)
    library(igraph)
    
    # ==========================================
    # Stage 1: Load and Preprocess Input Data
    # ==========================================
    
    # Read expression matrix (probe/gene-by-sample)
    if (!file.exists("counts.csv") || !file.exists("coldata.csv")) {
      stop("Required input files 'counts.csv' and/or 'coldata.csv' are missing.")
    }
    
    counts <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # Ensure data is numeric matrix
    df <- as.matrix(counts)
    
    # Apply log2 transformation if data is not already log-transformed
    if (max(df, na.rm = TRUE) > 20) {
      df <- log2(df + 1)
    }
    
    # Align samples between expression matrix and metadata
    common_samples <- intersect(colnames(df), coldata\$sample)
    if (length(common_samples) == 0) {
      stop("No matching samples found between counts.csv and coldata.csv.")
    }
    
    df <- df[, common_samples, drop = FALSE]
    coldata <- coldata[coldata\$sample %in% common_samples, ]
    
    # Group samples by condition/state (preserving order of conditions)
    coldata\$condition <- factor(coldata\$condition, levels = unique(coldata\$condition))
    samplesL <- split(coldata\$sample, f = coldata\$condition)
    
    message("Successfully loaded ", nrow(df), " genes and ", ncol(df), " samples across ", length(samplesL), " states.")
    
    # ==========================================
    # Stage 2: Gene Pre-selection
    # ==========================================
    
    # Select highly oscillating transcripts using standard deviation selection
    # We use a starting cutoff of 0.05. If too few genes are selected, we dynamically relax it.
    cutoff <- 0.05
    test <- sd_selection(df, samplesL, cutoff)
    
    # Robustness check: Ensure we have enough genes per state for network construction
    gene_counts <- sapply(test, nrow)
    if (any(gene_counts < 10)) {
      message("Low gene count detected with cutoff 0.05. Relaxing cutoff to 0.2...")
      test <- sd_selection(df, samplesL, 0.2)
      gene_counts <- sapply(test, nrow)
    }
    
    # Ultimate fallback: If still too few genes, select top highly variable genes globally
    if (any(gene_counts < 5)) {
      message("Using global highly variable genes fallback due to small sample size.")
      vars <- apply(df, 1, var)
      top_genes <- names(sort(vars, decreasing = TRUE)[1:min(100, nrow(df))])
      test <- lapply(samplesL, function(s) df[top_genes, s, drop = FALSE])
    }
    
    # ==========================================
    # Stage 3: Network Partitioning
    # ==========================================
    
    # Build co-expression networks for each state
    igraphL <- getNetwork(test, fdr = 1)
    
    # Partition networks into modules using random walk
    cluster <- getCluster_methods(igraphL)
    
    # ==========================================
    # Stage 4: Identify Putative Critical Transition Signals (CTS)
    # ==========================================
    
    # Calculate Module-Criticality Index (MCI) for each module
    membersL_noweight <- getMCI(cluster, test)
    
    # Plot MCI scores across all modules and states
    pdf("mci_scores_bar.pdf", width = 8, height = 6)
    plotBar_MCI(membersL_noweight, ylim = c(0, 10))
    dev.off()
    
    # Identify modules with the highest MCI at each stage
    min_size <- min(5, min(sapply(test, nrow)))
    maxMCIms <- getMaxMCImember(membersL_noweight[['members']], membersL_noweight[['MCI']], min = min_size)
    
    # Extract biomodule statistics
    biomodules <- getMaxStats(membersL_noweight[['members']], maxMCIms[[1]])
    maxMCI <- getMaxStats(membersL_noweight[['MCI']], maxMCIms[[1]])
    topMCI <- getTopMCI(membersL_noweight[['members']], membersL_noweight[['MCI']], membersL_noweight[['MCI']], min = min_size)
    
    # Extract the Critical Transition Signal (CTS) genes
    CTS <- getCTS(topMCI, maxMCIms[[2]])
    
    # Plot the maximum MCI trajectory across states
    pdf("max_mci_trajectory.pdf", width = 8, height = 6)
    par(mar = c(10, 5, 3, 2))
    plotMaxMCI(maxMCIms, membersL_noweight[['MCI']], states = names(samplesL), las = 2)
    dev.off()
    
    # ==========================================
    # Stage 5: Tipping Point Evaluation (Ic Score)
    # ==========================================
    
    if (length(CTS) > 0 && length(CTS[[1]]) > 0) {
      # Calculate Index of Critical Transition (Ic) score
      IC <- getIc(df, samplesL, CTS[[1]], PCC_sample.target = 'average')
    
      # Plot observed Ic scores
      pdf("ic_scores_line.pdf", width = 8, height = 6)
      par(mar = c(10, 5, 3, 2))
      plotIc(IC, las = 2)
      dev.off()
    
      # Evaluate significance using gene-shuffling simulation (B=50 for speed/stability)
      simuIC <- simulation_Ic(length(CTS[[1]]), samplesL, df, B = 50)
    
      # Plot simulation comparison
      pdf("ic_simulation.pdf", width = 8, height = 6)
      par(mar = c(10, 5, 3, 2))
      plot_Ic_Simulation(IC, simuIC, las = 2)
      dev.off()
    
      # Save CTS genes to CSV
      cts_df <- data.frame(
        gene_id = CTS[[1]],
        module = names(CTS)[1],
        stringsAsFactors = FALSE
      )
      write.csv(cts_df, "cts_genes.csv", row.names = FALSE)
    
      # Save tipping point statistics
      stats_df <- data.frame(
        state = names(IC),
        Ic_score = as.numeric(IC),
        max_MCI = as.numeric(maxMCI[names(IC)]),
        stringsAsFactors = FALSE
      )
      write.csv(stats_df, "tipping_point_stats.csv", row.names = FALSE)
      
      message("BioTIP analysis completed successfully. Outputs generated.")
    } else {
      warning("No significant CTS modules identified. Writing fallback empty outputs.")
      
      # Write fallback empty files to satisfy declared outputs
      write.csv(data.frame(Message = "No CTS modules identified with the given criteria"), "cts_genes.csv", row.names = FALSE)
      write.csv(data.frame(Message = "No Tipping Point stats available"), "tipping_point_stats.csv", row.names = FALSE)
      
      pdf("ic_scores_line.pdf")
      plot(1, 1, type = "n", main = "No CTS identified")
      dev.off()
      
      pdf("ic_simulation.pdf")
      plot(1, 1, type = "n", main = "No CTS identified")
      dev.off()
    }

    writeLines(c(
        '"BIOC_BIOTIP_BIOTIP_TIPPING_POINT_ANALYSIS":',
        paste0('    BioTIP: ', as.character(packageVersion('BioTIP')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biotip_tipping_point_analysis.csv versions.yml
    """
}

workflow BIOC_BIOTIP_BIOTIP_TIPPING_POINT_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_BIOTIP_BIOTIP_TIPPING_POINT_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_BIOTIP_BIOTIP_TIPPING_POINT_ANALYSIS.out.tables
    plots    = BIOC_BIOTIP_BIOTIP_TIPPING_POINT_ANALYSIS.out.plots
    objects  = BIOC_BIOTIP_BIOTIP_TIPPING_POINT_ANALYSIS.out.objects
    versions = BIOC_BIOTIP_BIOTIP_TIPPING_POINT_ANALYSIS.out.versions
}
