#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: coseq — deseq2_integrated_coexpression
// Run co-expression analysis directly on a DESeq2 pipeline output to cluster differentially expressed genes.
// Input: counts, conds
// Container: quay.io/biocontainers/bioconductor-coseq:1.34.0--r45hdfd78af_0
// R packages: DESeq2, coseq, ggplot2
// Bioconductor: 3.20 | R: 4.4
// Requires: DESeq2, coseq, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create a DESeqDataSet and run differential expression analysis using DESeq
//  * 2. [Core Analysis] Run coseq directly on the DESeqDataSet object, specifying the range of clusters K and significance threshold alpha or passing a su

nextflow.enable.dsl = 2

process BIOC_COSEQ_DESEQ2_INTEGRATED_COEXPRESSION {
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
    .bm_deps <- c("DESeq2", "coseq", "ggplot2", "SummarizedExperiment")
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
        library(SummarizedExperiment)
        library(DESeq2)
        library(coseq)
        library(ggplot2)
        
        # Read user inputs from the working directory
        if (file.exists("counts.csv")) {
          counts <- as.matrix(read.csv("counts.csv", row.names = 1, check.names = FALSE))
        } else if (file.exists("counts.tsv")) {
          counts <- as.matrix(read.delim("counts.tsv", row.names = 1, check.names = FALSE))
        } else {
          stop("Error: counts.csv or counts.tsv not found in the working directory.")
        }
        
        if (file.exists("conds.csv")) {
          conds <- read.csv("conds.csv", header = FALSE)[[1]]
        } else if (file.exists("conds.txt")) {
          conds <- readLines("conds.txt")
        } else {
          stop("Error: conds.csv or conds.txt not found in the working directory.")
        }
        
        # Validate inputs
        if (length(conds) != ncol(counts)) {
          stop(paste("Error: Number of conditions (", length(conds), 
                     ") does not match the number of columns in counts (", ncol(counts), ")."))
        }
        
        # Set seed for reproducibility
        set.seed(12345)
        
        # Stage 1: Create a DESeqDataSet and run differential expression analysis using DESeq
        dds <- DESeqDataSetFromMatrix(counts, DataFrame(group=factor(conds)), ~group)
        dds <- DESeq(dds, test="LRT", reduced = ~1)
        res <- results(dds)
        summary(res)
        
        # Stage 2: Run coseq directly on the DESeqDataSet object
        message("Running coseq...")
        run <- coseq(dds, K=2:15, alpha=0.05)
        
        # Save the final coseqResults object
        saveRDS(run, "coseq_results.rds")
        
        # Extract and save cluster assignments
        clust_labels <- clusters(run)
        clust_df <- data.frame(Gene = names(clust_labels), Cluster = clust_labels, row.names = NULL)
        write.csv(clust_df, "cluster_assignments.csv", row.names = FALSE)
        
        # Extract and save conditional probabilities of cluster membership
        prob_df <- as.data.frame(assay(run))
        write.csv(prob_df, "conditional_probabilities.csv", row.names = TRUE)
        
        # Extract and save normalized profiles
        norm_prof <- as.data.frame(profiles(run))
        write.csv(norm_prof, "normalized_profiles.csv", row.names = TRUE)
        
        # Generate and save plots
        message("Generating diagnostic and profile plots...")
        pdf("coseq_plots.pdf", width = 10, height = 8)
        tryCatch({
          # Generate default plots using the experimental conditions
          p <- plot(run, conds = conds)
          for (graph_name in names(p)) {
            print(p[[graph_name]])
          }
        }, error = function(e) {
          warning("Could not generate all plots: ", e\$message)
        })
        dev.off()
        
        message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_COSEQ_DESEQ2_INTEGRATED_COEXPRESSION":',
        paste0('    coseq: ', as.character(packageVersion('coseq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_deseq2_integrated_coexpression.csv versions.yml
    """
}

workflow BIOC_COSEQ_DESEQ2_INTEGRATED_COEXPRESSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ counts, conds ] ]

    main:
    BIOC_COSEQ_DESEQ2_INTEGRATED_COEXPRESSION(ch_input)

    emit:
    tables   = BIOC_COSEQ_DESEQ2_INTEGRATED_COEXPRESSION.out.tables
    plots    = BIOC_COSEQ_DESEQ2_INTEGRATED_COEXPRESSION.out.plots
    objects  = BIOC_COSEQ_DESEQ2_INTEGRATED_COEXPRESSION.out.objects
    versions = BIOC_COSEQ_DESEQ2_INTEGRATED_COEXPRESSION.out.versions
}
