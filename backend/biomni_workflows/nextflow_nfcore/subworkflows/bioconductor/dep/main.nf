#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DEP
// This package provides an integrated analysis workflow for robust and reproducible analysis of mass s
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DEP/inst/doc/DEP.R
// Upstream  : BiocStyle, SummarizedExperiment, dplyr, ggplot2, purrr
// Downstream: none
//
// Install: BiocManager::install("DEP")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DEP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-dep"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-dep:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-dep:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_dep_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_dep_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_dep_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DEP)
    library(jsonlite)


    # --- Required Packages [] ---
    # Key functions: suppressPackageStartupMessages, dplyr, filter, group_by, summarize, arrange, desc
    suppressPackageStartupMessages({
      library("BiocStyle")
      library("DEP")
      library("dplyr")
    })
    # Loading a package required for data handling
    library("dplyr")

    # The data is provided with the package
    data <- UbiLength

    # We filter for contaminant proteins and decoy database hits, which are indicated by "+" in the columns "Potential.contaminants" and "Reverse", respectively. 
    data <- filter(data, Reverse != "+", Potential.contaminant != "+")
    dim(data)
    colnames(data)
    # Are there any duplicated gene names?
    data$Gene.names %>% duplicated() %>% any()

    # Make a table of duplicated gene names
    data %>% group_by(Gene.names) %>% summarize(frequency = n()) %>% 

    # --- Unique Names [] ---
    # Key functions: make_unique, make_se, make_se_parse, plot_frequency, filter_missval
    # Make unique names using the annotation in the "Gene.names" column as primary names and the annotation in "Protein.IDs" as name for those that do not have an gene name.
    data_unique <- make_unique(data, "Gene.names", "Protein.IDs", delim = ";")

    # Are there any duplicated names?
    data$name %>% duplicated() %>% any()
    # Display experimental design
    knitr::kable(UbiLength_ExpDesign)
    # Generate a SummarizedExperiment object using an experimental design
    LFQ_columns <- grep("LFQ.", colnames(data_unique)) # get LFQ column numbers
    experimental_design <- UbiLength_ExpDesign
    data_se <- make_se(data_unique, LFQ_columns, experimental_design)

    # Generate a SummarizedExperiment object by parsing condition information from the column names
    LFQ_columns <- grep("LFQ.", colnames(data_unique)) # get LFQ column numbers
    data_se_parsed <- make_se_parse(data_unique, LFQ_columns)

    # Let's have a look at the SummarizedExperiment object
    # Plot a barplot of the protein identification overlap between samples
    plot_frequency(data_se)
    # Filter for proteins that are identified in all replicates of at least one condition

    # --- Plot Data [] ---
    # Key functions: plot_numbers, plot_coverage, normalize_vsn, plot_normalization, plot_missval
    # Plot a barplot of the number of identified proteins per samples
    plot_numbers(data_filt)
    # Plot a barplot of the protein identification overlap between samples
    plot_coverage(data_filt)
    # Normalize the data
    data_norm <- normalize_vsn(data_filt)
    # Visualize normalization by boxplots for all samples before and after normalization
    plot_normalization(data_filt, data_norm)
    # Plot a heatmap of proteins with missing values
    plot_missval(data_filt)

    # --- Plot Detect [] ---
    # Key functions: plot_detect, impute, value, distribution, approach, man, knn, plot_imputation
    # Plot intensity distributions and cumulative fraction of proteins with and without missing values
    plot_detect(data_filt)
    # All possible imputation methods are printed in an error, if an invalid function name is given.
    impute(data_norm, fun = "")

    # Impute missing data using random draws from a Gaussian distribution centered around a minimal value (for MNAR)
    data_imp <- impute(data_norm, fun = "MinProb", q = 0.01)

    # Impute missing data using random draws from a manually defined left-shifted Gaussian distribution (for MNAR)
    data_imp_man <- impute(data_norm, fun = "man", shift = 1.8, scale = 0.3)

    # Impute missing data using the k-nearest neighbour approach (for MAR)
    # Plot intensity distributions before and after imputation
    plot_imputation(data_norm, data_imp)
    # Differential enrichment analysis  based on linear models and empherical Bayes statistics

    # Test every sample versus control
    data_diff <- test_diff(data_imp, type = "control", control = "Ctrl")

    # Test all possible comparisons of samples

    # --- PCA [] ---
    # Key functions: plot_pca, plot_cor, plot_heatmap, centered, condition, replicate, proteins, contrasts
    # Plot the first and second principal components
    plot_pca(dep, x = 1, y = 2, n = 500, point_size = 4)
    # Plot the Pearson correlation matrix
    plot_cor(dep, significant = TRUE, lower = 0, upper = 1, pal = "Reds")
    # Plot a heatmap of all significant proteins with the data centered per protein
    plot_heatmap(dep, type = "centered", kmeans = TRUE, 
                 k = 6, col_limit = 4, show_row_names = FALSE,
                 indicate = c("condition", "replicate"))
    # Plot a heatmap of all significant proteins (rows) and the tested contrasts (columns)
    plot_heatmap(dep, type = "contrast", kmeans = TRUE, 
                 k = 6, col_limit = 10, show_row_names = FALSE)
    # Plot a volcano plot for the contrast "Ubi6 vs Ctrl""
    plot_volcano(dep, contrast = "Ubi6_vs_Ctrl", label_size = 2, add_names = TRUE)

    # --- Bar [] ---
    # Key functions: plot_single, centered, plot_cond, get_results, filter, get_df_wide, get_df_long
    # Plot a barplot for USP15 and IKBKG
    plot_single(dep, proteins = c("USP15", "IKBKG"))

    # Plot a barplot for the protein USP15 with the data centered
    plot_single(dep, proteins = "USP15", type = "centered")
    # Plot a frequency plot of significant proteins for the different conditions
    plot_cond(dep)
    # Generate a results table
    data_results <- get_results(dep)

    # Number of significant proteins
    data_results %>% filter(significant) %>% nrow()
    # Column names of the results table
    colnames(data_results)
    # Generate a wide data.frame
    df_wide <- get_df_wide(dep)
    # Generate a long data.frame
    df_long <- get_df_long(dep)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_dep_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_dep_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_dep_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DEP:", paste0("    dep: ", packageVersion("DEP"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dep_results.csv
    touch ${prefix}_dep_output.rds
    echo "BIOC_DEP:" > versions.yml
    echo "    dep: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DEP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DEP(ch_input)

    emit:
    results  = BIOC_DEP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DEP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DEP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DEP.out.versions  // channel: path(versions.yml)
}
