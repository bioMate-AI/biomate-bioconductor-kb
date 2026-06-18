#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: NetActivity — netactivity_gene_set_scores
// Compute gene set activity scores from RNA-seq count data using NetActivity's pre-trained autoencoder models and perform differential gene set activity analysis.
// Input: counts.csv, coldata.csv
// Container: 1.12.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: DESeq2, NetActivity, SummarizedExperiment, ggplot2, limma
// Visualizations: box plot
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NETACTIVITY_NETACTIVITY_GENE_SET_SCORES {
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
    .bm_deps <- c("NetActivity", "DESeq2", "limma", "ggplot2", "SummarizedExperiment")
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
     library(SummarizedExperiment)
   library(NetActivity)
    library(DESeq2)
    library(limma)
    library(ggplot2)
    
    # ==========================================
    # --- Load and Align Input Data ---
    # ==========================================
    message("Loading input datasets...")
    counts <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
    coldata <- read.csv("coldata.csv", check.names = FALSE)
    
    # Ensure sample alignment
    if (!"sample" %in% colnames(coldata) || !"condition" %in% colnames(coldata)) {
      stop("coldata.csv must contain 'sample' and 'condition' columns.")
    }
    rownames(coldata) <- coldata\$sample
    
    common_samples <- intersect(colnames(counts), rownames(coldata))
    if (length(common_samples) == 0) {
      stop("No matching samples found between counts.csv and coldata.csv.")
    }
    
    counts <- as.matrix(counts[, common_samples, drop = FALSE])
    coldata <- coldata[common_samples, , drop = FALSE]
    
    # ==========================================
    # --- Normalization (DESeq2 VST) ---
    # ==========================================
    message("Normalizing count data using Variance Stabilizing Transformation...")
    dds <- DESeqDataSetFromMatrix(
      countData = counts,
      colData = coldata,
      design = ~ condition
    )
    vst_data <- varianceStabilizingTransformation(dds, blind = TRUE)
    
    # ==========================================
    # --- Prepare SummarizedExperiment ---
    # ==========================================
    message("Preparing SummarizedExperiment for NetActivity...")
    # Using the default "gtex_gokegg" model (GO Biological Processes and KEGG pathways)
    model_name <- "gtex_gokegg"
    prepared_se <- prepareSummarizedExperiment(vst_data, model_name)
    
    # ==========================================
    # --- Compute Gene Set Scores ---
    # ==========================================
    message("Computing gene set activity scores...")
    scores_se <- computeGeneSetScores(prepared_se, model_name)
    
    # Save raw gene set scores
    write.csv(assay(scores_se), "gene_set_scores.csv", row.names = TRUE)
    message("Saved gene set scores to 'gene_set_scores.csv'.")
    
    # ==========================================
    # --- Differential Gene Set Score Analysis ---
    # ==========================================
    message("Performing differential gene set activity analysis...")
    design <- model.matrix(~ condition, data = colData(scores_se))
    fit <- lmFit(assay(scores_se), design)
    fit <- eBayes(fit)
    
    # Extract top table for the condition coefficient
    coef_name <- colnames(design)[2]
    top_tab <- topTable(fit, coef = coef_name, n = Inf)
    
    # Add descriptive gene set names from rowData
    top_tab\$GeneSetName <- rowData(scores_se)[rownames(top_tab), "Term"]
    write.csv(top_tab, "differential_gene_sets.csv", row.names = TRUE)
    message("Saved differential analysis results to 'differential_gene_sets.csv'.")
    
    # ==========================================
    # --- Visualization of Top Gene Set ---
    # ==========================================
    if (nrow(top_tab) > 0) {
      top_gs_id <- rownames(top_tab)[1]
      top_gs_name <- top_tab\$GeneSetName[1]
      message(sprintf("Plotting results for top gene set: %s (%s)", top_gs_id, top_gs_name))
      
      # 1. Boxplot of scores across conditions
      df_plot <- data.frame(
        Score = as.vector(assay(scores_se[top_gs_id, ])),
        Condition = colData(scores_se)\$condition
      )
      
      p1 <- ggplot(df_plot, aes(x = Condition, y = Score, fill = Condition)) +
        geom_boxplot(outlier.shape = NA, alpha = 0.7) +
        geom_jitter(width = 0.2, size = 2) +
        theme_bw() +
        labs(
          title = paste("Activity Scores:", top_gs_name),
          subtitle = paste("ID:", top_gs_id),
          y = "NetActivity Score",
          x = "Condition"
        ) +
        theme(legend.position = "none")
      
      ggsave("top_geneset_boxplot.pdf", plot = p1, width = 7, height = 5)
      
      # 2. Barplot of gene weights contributing to this gene set
      weights <- rowData(scores_se)[top_gs_id, ]\$Weights_SYMBOL[[1]]
      if (!is.null(weights) && length(weights) > 0) {
        df_weights <- data.frame(
          Weight = weights,
          Gene = names(weights)
        )
        df_weights\$Direction <- ifelse(df_weights\$Weight > 0, "Positive", "Negative")
        
        # Limit to top 30 genes by absolute weight for readability if there are too many
        if (nrow(df_weights) > 30) {
          df_weights <- df_weights[order(-abs(df_weights\$Weight)), ][1:30, ]
        }
        
        p2 <- ggplot(df_weights, aes(x = reorder(Gene, abs(Weight)), y = abs(Weight), fill = Direction)) +
          geom_bar(stat = "identity", width = 0.7) +
          coord_flip() +
          theme_bw() +
          labs(
            title = "Gene Weights Contribution",
            subtitle = paste("Gene Set:", top_gs_name),
            x = "Gene",
            y = "Absolute Weight"
          ) +
          scale_fill_manual(values = c("Positive" = "#377eb8", "Negative" = "#e41a1c"))
        
        ggsave("top_geneset_weights.pdf", plot = p2, width = 8, height = 6)
      } else {
        # Fallback empty plot if weights are unavailable
        pdf("top_geneset_weights.pdf")
        plot(1, type = "n", axes = FALSE, xlab = "", ylab = "")
        text(1, 1, "No gene weights available for this gene set")
        dev.off()
      }
    } else {
      message("No differential gene sets found to plot.")
    }
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_NETACTIVITY_NETACTIVITY_GENE_SET_SCORES":',
        paste0('    NetActivity: ', as.character(packageVersion('NetActivity')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_netactivity_gene_set_scores.csv versions.yml
    """
}

workflow BIOC_NETACTIVITY_NETACTIVITY_GENE_SET_SCORES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_NETACTIVITY_NETACTIVITY_GENE_SET_SCORES(ch_input)

    emit:
    tables   = BIOC_NETACTIVITY_NETACTIVITY_GENE_SET_SCORES.out.tables
    plots    = BIOC_NETACTIVITY_NETACTIVITY_GENE_SET_SCORES.out.plots
    objects  = BIOC_NETACTIVITY_NETACTIVITY_GENE_SET_SCORES.out.objects
    versions = BIOC_NETACTIVITY_NETACTIVITY_GENE_SET_SCORES.out.versions
}
