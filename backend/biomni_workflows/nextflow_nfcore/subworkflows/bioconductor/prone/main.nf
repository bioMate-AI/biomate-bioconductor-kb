#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PRONE — proteomics_normalization_evaluation
// Preprocess, normalize, evaluate, and impute proteomics data (TMT or LFQ) stored in a SummarizedExperiment object.
// Input: tuberculosis_protein_intensities.csv, tuberculosis_metadata.csv
// Container: quay.io/biocontainers/bioconductor-prone:1.4.0--r45h575d39b_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: PRONE, SummarizedExperiment, stringr
// Visualizations: plot (ggplot/base)
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load data into a SummarizedExperiment object
//  * 2. [Core Analysis] Filter out low-quality proteins and contaminants
//  * 3. [Core Analysis] Perform sample quality control and outlier detection
//  * 4. [Core Analysis] Apply multiple normalization and batch correction methods
//  * 5. [Core Analysis] Evaluate normalization performance qualitatively and quantitatively
//  * 6. [Core Analysis] Perform missing value imputation
//  * 7. [Visualization & Output] Export the normalized and processed datasets

nextflow.enable.dsl = 2

process BIOC_PRONE_PROTEOMICS_NORMALIZATION_EVALUATION {
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
    .bm_deps <- c("PRONE", "stringr", "SummarizedExperiment")
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
        library(PRONE)
        library(SummarizedExperiment)
        library(stringr)
        
        # Helper function to safely print plots to PDF
        safe_print <- function(x) {
          if (is.null(x)) return(NULL)
          if (inherits(x, "ggplot") || inherits(x, "gtable") || inherits(x, "Heatmap") || inherits(x, "gg")) {
            print(x)
          } else if (is.list(x)) {
            for (item in x) {
              if (inherits(item, "ggplot") || inherits(item, "gtable") || inherits(item, "Heatmap") || inherits(item, "gg")) {
                print(item)
              }
            }
          } else {
            try(print(x), silent = TRUE)
          }
        }
        
        # 1. Load data into a SummarizedExperiment object
        data <- read.csv("tuberculosis_protein_intensities.csv")
        md <- read.csv("tuberculosis_metadata.csv")
        md\$Column <- stringr::str_replace_all(md\$Column, " ", ".")
        ref_samples <- md[md\$Group == "ref",]\$Column
        
        se <- load_data(data, md, protein_column = "Protein.IDs", gene_column = "Gene.names", ref_samples = ref_samples, batch_column = "Pool", condition_column = "Group", label_column = "Label")
        se <- subset_SE_by_norm(se, ain = c("raw", "log2"))
        
        # Save NA overview
        na_overview <- get_NA_overview(se, ain = "log2")
        write.csv(na_overview, "NA_overview.csv", row.names = FALSE)
        
        # Open PDF device to capture all plots
        pdf("PRONE_plots.pdf", width = 11, height = 8)
        
        # Exploratory plots
        tryCatch({ safe_print(plot_condition_overview(se, condition = NULL)) }, error = function(e) message("plot_condition_overview failed: ", e\$message))
        tryCatch({ safe_print(plot_heatmap(se, ain = "log2", color_by = c("Pool", "Group"), label_by = NULL, only_refs = FALSE)) }, error = function(e) message("plot_heatmap failed: ", e\$message))
        tryCatch({ safe_print(plot_upset(se, color_by = NULL, label_by = NULL, mb.ratio = c(0.7,0.3), only_refs = FALSE)) }, error = function(e) message("plot_upset failed: ", e\$message))
        
        # Dynamically select markers to avoid hardcoding
        markers_to_plot <- head(rowData(se)\$Protein.IDs, 2)
        tryCatch({ safe_print(plot_markers_boxplots(se, markers = markers_to_plot, ain = "log2", id_column = "Protein.IDs", facet_norm = FALSE, facet_marker = TRUE)) }, error = function(e) message("plot_markers_boxplots failed: ", e\$message))
        
        # 2. Filter out low-quality proteins and contaminants
        se <- filter_out_complete_NA_proteins(se)
        se <- filter_out_proteins_by_value(se, "Reverse", "+")
        se <- filter_out_proteins_by_value(se, "Only.identified.by.site", "+")
        pot_contaminants <- get_proteins_by_value(se, "Potential.contaminant", "+")
        se <- filter_out_proteins_by_ID(se, pot_contaminants)
        
        # Missing value pattern plots
        tryCatch({ safe_print(plot_NA_heatmap(se, color_by = NULL, label_by = NULL, cluster_samples = TRUE, cluster_proteins = TRUE)) }, error = function(e) message("plot_NA_heatmap failed: ", e\$message))
        tryCatch({ safe_print(plot_NA_density(se)) }, error = function(e) message("plot_NA_density failed: ", e\$message))
        tryCatch({ safe_print(plot_NA_frequency(se)) }, error = function(e) message("plot_NA_frequency failed: ", e\$message))
        
        # Filter by threshold
        se <- filter_out_NA_proteins_by_threshold(se, thr = 0.7)
        
        # 3. Perform sample quality control and outlier detection
        tryCatch({ safe_print(plot_nr_prot_samples(se, color_by = NULL, label_by = NULL)) }, error = function(e) message("plot_nr_prot_samples failed: ", e\$message))
        tryCatch({ safe_print(plot_tot_int_samples(se, color_by = NULL, label_by = NULL)) }, error = function(e) message("plot_tot_int_samples failed: ", e\$message))
        
        se_no_refs <- remove_reference_samples(se)
        
        poma_res <- detect_outliers_POMA(se, ain = "log2")
        write.csv(poma_res\$outliers, "POMA_outliers.csv", row.names = FALSE)
        tryCatch({ safe_print(poma_res\$polygon_plot) }, error = function(e) message("poma polygon_plot failed: ", e\$message))
        tryCatch({ safe_print(poma_res\$distance_boxplot) }, error = function(e) message("poma distance_boxplot failed: ", e\$message))
        
        se <- remove_POMA_outliers(se, poma_res\$outliers)
        
        # 4. Apply multiple normalization and batch correction methods
        get_normalization_methods()
        se_norm <- normalize_se(se, c("RobNorm", "Mean", "Median", "IRS_on_RobNorm", "IRS_on_Mean", "IRS_on_Median"), combination_pattern = "_on_")
        se_norm <- medianNorm(se_norm, ain = "log2", aout = "Median")
        names(assays(se_norm))
        
        # 5. Evaluate normalization performance qualitatively and quantitatively
        tryCatch({ safe_print(plot_boxplots(se_norm, ain = NULL, color_by = NULL, label_by = NULL, ncol = 3, facet_norm = TRUE)) }, error = function(e) message("plot_boxplots failed: ", e\$message))
        tryCatch({ safe_print(plot_densities(se_norm, ain = c("IRS_on_RobNorm", "IRS_on_Median"), color_by = NULL, facet_norm = TRUE)) }, error = function(e) message("plot_densities failed: ", e\$message))
        tryCatch({ safe_print(plot_PCA(se_norm, ain = c("IRS_on_RobNorm", "IRS_on_Median"), color_by = "Group", label_by = "No", shape_by = "Pool", facet_norm = FALSE, facet_by = "Group")) }, error = function(e) message("plot_PCA failed: ", e\$message))
        tryCatch({ safe_print(plot_intragroup_correlation(se_norm, ain = NULL, condition = NULL, method = "pearson")) }, error = function(e) message("plot_intragroup_correlation failed: ", e\$message))
        tryCatch({ safe_print(plot_intragroup_PCV(se_norm, ain = NULL, condition = NULL, diff = FALSE)) }, error = function(e) message("plot_intragroup_PCV failed: ", e\$message))
        tryCatch({ safe_print(plot_intragroup_PEV(se_norm, ain = NULL, condition = NULL, diff = FALSE)) }, error = function(e) message("plot_intragroup_PEV failed: ", e\$message))
        tryCatch({ safe_print(plot_intragroup_PMAD(se_norm, ain = NULL, condition = NULL, diff = FALSE)) }, error = function(e) message("plot_intragroup_PMAD failed: ", e\$message))
        tryCatch({ safe_print(plot_intragroup_PCV(se_norm, ain = NULL, condition = NULL, diff = TRUE)) }, error = function(e) message("plot_intragroup_PCV diff failed: ", e\$message))
        
        dev.off()
        
        # Subset assays
        se_no_MAD <- remove_assays_from_SE(se_norm, assays_to_remove = c("Mean"))
        se_subset <- subset_SE_by_norm(se_norm, ain = c("IRS_on_RobNorm", "IRS_on_Median"))
        
        # 6. Perform missing value imputation on the normalized object
        se_final <- impute_se(se_norm, ain = NULL)
        
        # 7. Export the normalized and processed datasets
        if(!dir.exists("output/")) dir.create("output/")
        tryCatch({
          export_data(se_final, out_dir = "output/", ain = c("log2", "Median", "RobNorm"))
        }, error = function(e) {
          message("export_data failed with default ain, trying with available assays: ", e\$message)
          available_ains <- intersect(c("log2", "Median", "RobNorm"), names(assays(se_final)))
          if (length(available_ains) > 0) {
            export_data(se_final, out_dir = "output/", ain = available_ains)
          } else {
            export_data(se_final, out_dir = "output/", ain = names(assays(se_final)))
          }
        })
        
        # Save final RDS objects for downstream analysis
        saveRDS(se_final, "output/se_final.rds")
        saveRDS(se_norm, "output/se_norm.rds")
        saveRDS(se_subset, "output/se_subset.rds")
        
        message("PRONE pipeline completed successfully.")

    writeLines(c(
        '"BIOC_PRONE_PROTEOMICS_NORMALIZATION_EVALUATION":',
        paste0('    PRONE: ', as.character(packageVersion('PRONE')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_proteomics_normalization_evaluation.csv versions.yml
    """
}

workflow BIOC_PRONE_PROTEOMICS_NORMALIZATION_EVALUATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ tuberculosis_protein_intensities.csv, tuberculosis_metadata.csv ] ]

    main:
    BIOC_PRONE_PROTEOMICS_NORMALIZATION_EVALUATION(ch_input)

    emit:
    tables   = BIOC_PRONE_PROTEOMICS_NORMALIZATION_EVALUATION.out.tables
    plots    = BIOC_PRONE_PROTEOMICS_NORMALIZATION_EVALUATION.out.plots
    objects  = BIOC_PRONE_PROTEOMICS_NORMALIZATION_EVALUATION.out.objects
    versions = BIOC_PRONE_PROTEOMICS_NORMALIZATION_EVALUATION.out.versions
}
