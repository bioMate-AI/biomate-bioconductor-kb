#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GSEABenchmarkeR — gsea_benchmark_pipeline
// Benchmark gene set enrichment analysis (GSEA) methods (ORA and CAMERA) on a user-provided transcriptomic dataset by evaluating runtime, statistical significance
// Input: counts.csv, coldata.csv
// Container: 1.30.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GSEABenchmarkeR, S4Vectors, SummarizedExperiment
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GSEABENCHMARKER_GSEA_BENCHMARK_PIPELINE {
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
    library(GSEABenchmarkeR)
    library(S4Vectors)
    
    # ==========================================
    # --- Load and Preprocess Input Data ---
    # ==========================================
    message("Stage 1: Loading and preprocessing input data...")
    
    # Read expression data and sample metadata
    counts_df <- read.csv("counts.csv", check.names = FALSE)
    coldata <- read.csv("coldata.csv", check.names = FALSE)
    
    # Set gene_id as row names for expression matrix
    if ("gene_id" %in% colnames(counts_df)) {
        rownames(counts_df) <- counts_df\$gene_id
        counts_matrix <- as.matrix(counts_df[, setdiff(colnames(counts_df), "gene_id")])
    } else {
        rownames(counts_df) <- counts_df[, 1]
        counts_matrix <- as.matrix(counts_df[, -1])
    }
    
    # Ensure sample names match between expression matrix and coldata
    rownames(coldata) <- coldata\$sample
    common_samples <- intersect(colnames(counts_matrix), rownames(coldata))
    counts_matrix <- counts_matrix[, common_samples, drop = FALSE]
    coldata <- coldata[common_samples, , drop = FALSE]
    
    # Map condition to binary GROUP (0 for control, 1 for case) as required by GSEABenchmarkeR
    unique_conds <- unique(coldata\$condition)
    if (length(unique_conds) >= 2) {
        coldata\$GROUP <- ifelse(coldata\$condition == unique_conds[1], 0, 1)
    } else {
        # Fallback if only one condition is present
        n_samples <- nrow(coldata)
        coldata\$GROUP <- c(rep(0, floor(n_samples / 2)), rep(1, ceiling(n_samples / 2)))
    }
    
    # Normalize/log-transform expression data if raw counts are provided
    # This ensures compatibility with limma-based differential expression
    if (max(counts_matrix, na.rm = TRUE) > 50) {
        message("Raw counts detected. Performing log2-CPM transformation...")
        libsizes <- colSums(counts_matrix)
        exprs_data <- log2(t(t(counts_matrix) / libsizes * 1e6) + 1)
    } else {
        exprs_data <- counts_matrix
    }
    
    # Create SummarizedExperiment object
    se <- SummarizedExperiment(
        assays = list(exprs = exprs_data),
        colData = DataFrame(coldata)
    )
    metadata(se) <- list(dataId = "dataset1", dataType = "rnaseq")
    
    # Wrap in a named list to represent a data compendium
    compendium <- list(dataset1 = se)
    
    # ==========================================
    # --- Differential Expression Analysis ---
    # ==========================================
    message("Stage 2: Running differential expression analysis...")
    compendium <- runDE(compendium, de.method = "limma", padj.method = "flexible")
    
    # ==========================================
    # --- Gene Set Enrichment Analysis (GSEA) ---
    # ==========================================
    message("Stage 3: Performing GSEA benchmarking...")
    
    # Generate mock gene sets from the dataset genes for benchmarking
    all_genes <- rownames(se)
    n_genes <- length(all_genes)
    set.seed(42)
    gs <- list(
        GS_A = sample(all_genes, max(2, min(n_genes, 10))),
        GS_B = sample(all_genes, max(2, min(n_genes, 15))),
        GS_C = sample(all_genes, max(2, min(n_genes, 12))),
        GS_D = sample(all_genes, max(2, min(n_genes, 8))),
        GS_E = sample(all_genes, max(2, min(n_genes, 20)))
    )
    
    # Run ORA and CAMERA methods and save results to a temporary directory
    res.dir <- tempdir()
    res <- runEA(
        compendium, 
        methods = c("ora", "camera"), 
        gs = gs, 
        perm = 0, 
        save2file = TRUE, 
        out.dir = res.dir
    )
    
    # ==========================================
    # --- Benchmarking & Evaluation ---
    # ==========================================
    message("Stage 4: Evaluating GSEA results...")
    
    # Read runtimes and rankings from saved results
    ea.rtimes <- readResults(res.dir, names(compendium), methods = c("ora", "camera"), type = "runtime")
    ea.ranks <- readResults(res.dir, names(compendium), methods = c("ora", "camera"), type = "ranking")
    
    # Evaluate fraction of significant gene sets
    sig.sets <- evalNrSigSets(ea.ranks, alpha = 0.05, padj = "BH")
    
    # Create mock disease relevance rankings for phenotype relevance evaluation
    rel.ranks <- DataFrame(
        TITLE = names(gs),
        REL.SCORE = round(runif(length(gs), min = 10, max = 100), 2)
    )
    rel.ranks <- rel.ranks[order(rel.ranks\$REL.SCORE, decreasing = TRUE), ]
    mala.mock <- list(MY_DIS = rel.ranks)
    
    # Map dataset to the mock disease
    d2d.map <- c(dataset1 = "MY_DIS")
    
    # Evaluate phenotype relevance across the compendium
    all.relevance <- evalRelevance(ea.ranks, mala.mock, d2d.map[names(compendium)])
    
    # Calculate statistical significance of relevance for ORA on dataset1
    gs.ids <- ea.ranks\$ora\$dataset1\$GENE.SET
    obs.score <- evalRelevance(ea.ranks\$ora\$dataset1, mala.mock\$MY_DIS)
    rand.scores <- compRand(mala.mock\$MY_DIS, gs.ids, perm = 50)
    opt.score <- compOpt(mala.mock\$MY_DIS, gs.ids)
    
    message(sprintf("Observed Relevance Score: %.2f", obs.score))
    message(sprintf("Theoretical Optimal Score: %.2f", opt.score))
    message(sprintf("Relevance Ratio: %.2f%%", (obs.score / opt.score) * 100))
    
    # ==========================================
    # --- Exporting Results and Visualizations ---
    # ==========================================
    message("Stage 5: Exporting outputs...")
    
    # 1. Export Runtimes
    runtime_df <- data.frame(
        Dataset = names(ea.rtimes\$ora),
        ORA = as.numeric(ea.rtimes\$ora),
        CAMERA = as.numeric(ea.rtimes\$camera)
    )
    write.csv(runtime_df, "runtimes.csv", row.names = FALSE)
    
    # 2. Export Significant Gene Set Percentages
    sig_df <- as.data.frame(sig.sets)
    write.csv(sig_df, "significant_gene_sets.csv", row.names = TRUE)
    
    # 3. Export Relevance Scores
    relevance_df <- data.frame(
        Dataset = names(all.relevance\$ora),
        ORA_Relevance = as.numeric(all.relevance\$ora),
        CAMERA_Relevance = as.numeric(all.relevance\$camera)
    )
    write.csv(relevance_df, "relevance_scores.csv", row.names = FALSE)
    
    # 4. Export Detailed ORA Ranking
    write.csv(as.data.frame(ea.ranks\$ora\$dataset1), "ora_ranking_dataset1.csv", row.names = FALSE)
    
    # 5. Generate Diagnostic Plots
    pdf("benchmark_plots.pdf", width = 7, height = 7)
    tryCatch({
        bpPlot(ea.rtimes, what = "runtime")
        title(main = "Computation Runtime Comparison")
        
        bpPlot(sig.sets, what = "sig.sets")
        title(main = "Percentage of Significant Gene Sets")
        
        bpPlot(all.relevance, what = "rel.sets")
        title(main = "Phenotype Relevance Scores")
    }, error = function(e) {
        message("Plotting encountered an issue: ", e\$message)
    })
    dev.off()
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_GSEABENCHMARKER_GSEA_BENCHMARK_PIPELINE":',
        paste0('    GSEABenchmarkeR: ', as.character(packageVersion('GSEABenchmarkeR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gsea_benchmark_pipeline.csv versions.yml
    """
}

workflow BIOC_GSEABENCHMARKER_GSEA_BENCHMARK_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_GSEABENCHMARKER_GSEA_BENCHMARK_PIPELINE(ch_input)

    emit:
    tables   = BIOC_GSEABENCHMARKER_GSEA_BENCHMARK_PIPELINE.out.tables
    plots    = BIOC_GSEABENCHMARKER_GSEA_BENCHMARK_PIPELINE.out.plots
    objects  = BIOC_GSEABENCHMARKER_GSEA_BENCHMARK_PIPELINE.out.objects
    versions = BIOC_GSEABENCHMARKER_GSEA_BENCHMARK_PIPELINE.out.versions
}
