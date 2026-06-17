#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SplicingFactory — splicing_diversity_and_differential_analysis
// Calculate transcript isoform diversity (Laplace entropy and Gini index) from transcript expression data and identify genes with significant diversity changes be
// Input: transcript_expression.tsv, gene_vector.tsv, sample_metadata.tsv
// Container: quay.io/biocontainers/bioconductor-splicingfactory:1.18.0--r45hdfd78af_2
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SplicingFactory, SummarizedExperiment, ggplot2, tibble, tidyr
// Visualizations: density plot, diversity plot, violin plot, MA plot, volcano plot
// QC: low-count filtering
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter out low-expression transcripts to reduce variability
//  * 2. [Core Analysis] Calculate gene-level splicing diversity using calculate_diversity()
//  * 3. [Visualization & Output] Append sample condition metadata to the resulting SummarizedExperiment object
//  * 4. [Core Analysis] Perform differential diversity analysis between conditions using calculate_difference()

nextflow.enable.dsl = 2

process BIOC_SPLICINGFACTORY_SPLICING_DIVERSITY_AND_DIFFERENTIAL_ANALYSIS {
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
    .bm_deps <- c("SplicingFactory", "SummarizedExperiment", "tidyr", "ggplot2", "tibble")
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
        library("SplicingFactory")
        library("SummarizedExperiment")
        library("tidyr")
        library("ggplot2")
        library("tibble")
        
        # --------------------------------------------------------------------------
        # 1. Load and preprocess user input files
        # --------------------------------------------------------------------------
        
        # Read transcript expression matrix
        readcounts <- read.table("transcript_expression.tsv", header = TRUE, sep = "\t", row.names = 1, check.names = FALSE)
        
        # Read gene vector mapping
        genes_df <- read.table("gene_vector.tsv", header = FALSE, sep = "\t", stringsAsFactors = FALSE)
        genes <- as.character(genes_df[[1]])
        
        # Read sample metadata
        metadata <- read.table("sample_metadata.tsv", header = TRUE, sep = "\t", stringsAsFactors = FALSE, check.names = FALSE)
        
        # Align metadata to readcounts columns
        sample_col <- colnames(metadata)[1]
        cond_col <- colnames(metadata)[2]
        metadata <- metadata[match(colnames(readcounts), metadata[[sample_col]]), ]
        
        # Create a mapping from sample to condition
        sample_to_condition <- setNames(metadata[[cond_col]], metadata[[sample_col]])
        
        # Identify control condition for differential analysis
        conds <- unique(metadata[[cond_col]])
        control_cond <- conds[tolower(conds) %in% c("normal", "control", "n", "wt", "wildtype")]
        if (length(control_cond) == 0) {
          control_cond <- conds[1]
        } else {
          control_cond <- control_cond[1]
        }
        
        # --------------------------------------------------------------------------
        # 2. Data filtering and preprocessing
        # --------------------------------------------------------------------------
        tokeep <- rowSums(readcounts > 5) > 5
        readcounts <- readcounts[tokeep, ]
        genes      <- genes[tokeep]
        
        # --------------------------------------------------------------------------
        # 3. Transcript diversity calculation
        # --------------------------------------------------------------------------
        laplace_entropy <- calculate_diversity(readcounts, genes,  method = "laplace",
                                               norm = TRUE, verbose = TRUE)
        
        gini_index <- calculate_diversity(readcounts, genes, method = "gini",
                                          verbose = TRUE)
        
        # Save diversity matrices and objects
        saveRDS(laplace_entropy, "laplace_entropy.rds")
        saveRDS(gini_index, "gini_index.rds")
        write.csv(assay(laplace_entropy), "laplace_entropy_matrix.csv", row.names = TRUE)
        write.csv(assay(gini_index), "gini_index_matrix.csv", row.names = TRUE)
        
        # --------------------------------------------------------------------------
        # 4. Plotting Splicing Diversity Distributions
        # --------------------------------------------------------------------------
        # Construct data.frame from SummarizedExperiment result
        laplace_data <- data.frame(assay(laplace_entropy),
                                   Gene = rowData(laplace_entropy)\$genes,
                                   check.names = FALSE)
        
        # Reshape data.frame
        laplace_data <- pivot_longer(laplace_data, -Gene, names_to = "sample",
                                     values_to = "entropy")
        
        # Add sample type information
        laplace_data\$sample_type <- unname(sample_to_condition[laplace_data\$sample])
        
        # Filter genes with NA entropy values
        laplace_data <- drop_na(laplace_data)
        
        # Update gene names and add diversity type column
        laplace_data\$Gene <- paste0(laplace_data\$Gene, "_", laplace_data\$sample_type)
        laplace_data\$diversity <-  "Normalized Laplace entropy"
        
        # Construct data.frame from SummarizedExperiment result
        gini_data <- data.frame(assay(gini_index), 
                                Gene = rowData(gini_index)\$genes,
                                check.names = FALSE)
        
        # Reshape data.frame
        gini_data <- pivot_longer(gini_data, -Gene, names_to = "sample",
                                  values_to = "gini")
        
        # Add sample type information
        gini_data\$sample_type <- unname(sample_to_condition[gini_data\$sample])
        
        # Filter genes with NA gini values
        gini_data <- drop_na(gini_data)
        
        # Update gene names and add diversity type column
        gini_data\$Gene <- paste0(gini_data\$Gene, "_", gini_data\$sample_type)
        gini_data\$diversity <-  "Gini index"
        
        # Plot density data
        pdf("diversity_density_plots.pdf", width = 8, height = 6)
        p1 <- ggplot() +
          geom_density(data = laplace_data, alpha = 0.3,
                       aes(x = entropy, group = sample, color = diversity)) +
          geom_density(data = gini_data, alpha = 0.3,
                       aes(x = gini, group = sample, color = diversity)) +
          facet_grid(. ~ sample_type) +
          scale_color_manual(values = c("black", "darkorchid4")) +
          guides(color = "none") +
          theme_minimal() +
          labs(x = "Diversity values",
               y = "Density")
        print(p1)
        dev.off()
        
        # Mean entropy calculation across samples for each gene/sample type combination
        laplace_entropy_mean <- aggregate(laplace_data\$entropy,
                                          by = list(laplace_data\$Gene), mean)
        colnames(laplace_entropy_mean)[2] <- "mean_entropy"
        laplace_entropy_mean <- as_tibble(laplace_entropy_mean)
        
        # Add sample type information
        laplace_entropy_mean\$sample_type <- sapply(laplace_entropy_mean[[1]], function(x) {
          x_str <- as.character(x)
          matches <- conds[sapply(conds, function(cond) endsWith(x_str, paste0("_", cond)))]
          if (length(matches) > 0) {
            return(matches[which.max(nchar(matches))])
          }
          return(NA)
        })
        
        # Add diversity type column
        laplace_entropy_mean\$diversity <-  "Normalized Laplace entropy"
        
        # Mean gini calculation across samples for each gene/sample type combination
        gini_mean <- aggregate(gini_data\$gini, by = list(gini_data\$Gene), mean)
        colnames(gini_mean)[2] <- "mean_gini"
        gini_mean <- as_tibble(gini_mean)
        
        # Add sample type information
        gini_mean\$sample_type <- sapply(gini_mean[[1]], function(x) {
          x_str <- as.character(x)
          matches <- conds[sapply(conds, function(cond) endsWith(x_str, paste0("_", cond)))]
          if (length(matches) > 0) {
            return(matches[which.max(nchar(matches))])
          }
          return(NA)
        })
        
        # Add diversity type column
        gini_mean\$diversity <-  "Gini index"
        
        pdf("diversity_violin_plots.pdf", width = 8, height = 6)
        p2 <- ggplot() +
          geom_violin(data = laplace_entropy_mean, aes(x = sample_type, y = mean_entropy,
                                                       fill = diversity),
                      alpha = 0.6) +
          geom_violin(data = gini_mean, aes(x = sample_type, y = mean_gini,
                                            fill = diversity),
                      alpha = 0.6) +
          scale_fill_viridis_d(name = "Diversity") +
          coord_flip() +
          theme_minimal() +
          labs(x = "Samples",
               y = "Diversity")
        print(p2)
        dev.off()
        
        # --------------------------------------------------------------------------
        # 5. Differential Splicing Diversity Analysis
        # --------------------------------------------------------------------------
        
        # Update the SummarizedExperiment object with a new sample metadata column for
        # sample types, as the the object returned by calculate_diversity does not
        # contain this information.
        colData(laplace_entropy) <- cbind(colData(laplace_entropy),
                                              sample_type = unname(sample_to_condition[colnames(laplace_entropy)]))
        
        # Calculate significant entropy changes
        entropy_significance <- calculate_difference(x = laplace_entropy, samples = "sample_type",
                                                     control = control_cond,
                                                     method = "mean", test = "wilcoxon",
                                                     verbose = TRUE)
        
        # Save significance results
        write.csv(entropy_significance, "entropy_significance.csv", row.names = FALSE)
        
        # --------------------------------------------------------------------------
        # 6. Plotting Differential Analysis Results
        # --------------------------------------------------------------------------
        entropy_significance\$label <- apply(entropy_significance[, c(4, 7)], 1,
                                            function(x) ifelse(abs(x[1]) >= 0.1 & x[2] < 0.05,
                                                               "significant", "non-significant"))
        
        entropy_significance\$mean <- apply(entropy_significance[, c(2, 3)], 1,
                                           function(x) (x[1] + x[2]) / 2)
        
        pdf("ma_plot.pdf", width = 6, height = 6)
        p3 <- ggplot(entropy_significance, aes(x = mean, y = mean_difference)) +
          geom_point(color = "lightgrey", size = 1) +
          geom_point(data = entropy_significance[which(entropy_significance\$label == "significant"), ],
                     color = "red", size = 1) +
          theme_minimal() +
          labs(title = "Normalized Laplace entropy",
               subtitle = "Wilcoxon signed rank test",
               x = "Mean entropy",
               y = "Mean difference")
        print(p3)
        dev.off()
        
        pdf("volcano_plot.pdf", width = 6, height = 6)
        p4 <- ggplot(entropy_significance, aes(x = mean_difference,
                                         y = -log10(adjusted_p_values),
                                         color = label)) +
          geom_point() +
          scale_color_manual(values = c("grey", "red"), guide = "none") +
          geom_hline(yintercept = -log10(0.05), color = "red") +
          geom_vline(xintercept = c(0.1, -0.1)) +
          theme_minimal() +
          labs(title = "Normalized Laplace entropy",
               subtitle = "Wilcoxon signed rank test",
               x = "Mean difference of entropy values",
               y = "-Log10(adjusted p-value)")
        print(p4)
        dev.off()

    writeLines(c(
        '"BIOC_SPLICINGFACTORY_SPLICING_DIVERSITY_AND_DIFFERENTIAL_ANALYSIS":',
        paste0('    SplicingFactory: ', as.character(packageVersion('SplicingFactory')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_splicing_diversity_and_differential_analysis.csv versions.yml
    """
}

workflow BIOC_SPLICINGFACTORY_SPLICING_DIVERSITY_AND_DIFFERENTIAL_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ transcript_expression.tsv, gene_vector.tsv, sample_metadata.tsv ] ]

    main:
    BIOC_SPLICINGFACTORY_SPLICING_DIVERSITY_AND_DIFFERENTIAL_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SPLICINGFACTORY_SPLICING_DIVERSITY_AND_DIFFERENTIAL_ANALYSIS.out.tables
    plots    = BIOC_SPLICINGFACTORY_SPLICING_DIVERSITY_AND_DIFFERENTIAL_ANALYSIS.out.plots
    objects  = BIOC_SPLICINGFACTORY_SPLICING_DIVERSITY_AND_DIFFERENTIAL_ANALYSIS.out.objects
    versions = BIOC_SPLICINGFACTORY_SPLICING_DIVERSITY_AND_DIFFERENTIAL_ANALYSIS.out.versions
}
