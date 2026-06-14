#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: proDA — differential_abundance_analysis
// Identify differentially abundant proteins in label-free mass spectrometry data by fitting a probabilistic dropout model without imputation.
// Input: proteinGroups.txt
// Container: quay.io/biocontainers/bioconductor-proda:1.24.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: pheatmap, proDA
// Visualizations: heatmap, heatmap (ComplexHeatmap), box plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the protein intensity data and convert zero values to NA
//  * 2. [Core Analysis] Log2-transform the intensities
//  * 3. [Core Analysis] Perform median normalization using median_normalization()
//  * 4. [Core Analysis] Estimate sample distances using dist_approx()
//  * 5. [Core Analysis] Fit the probabilistic dropout model using proDA()
//  * 6. [Core Analysis] Test for differential abundance using test_diff()

nextflow.enable.dsl = 2

process BIOC_PRODA_DIFFERENTIAL_ABUNDANCE_ANALYSIS {
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
    .bm_deps <- c("proDA")
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
        library(proDA)
        
        # 1. Load the protein intensity data from the working directory
        # The user input file 'proteinGroups.txt' must be present in the working directory.
        maxquant_protein_table <- read.delim(
            "proteinGroups.txt",
            stringsAsFactors = FALSE
        )
        
        # Extract the intensity columns
        intensity_colnames <- grep("^LFQ\\\\.intensity\\\\.", colnames(maxquant_protein_table), value=TRUE)
        abundance_matrix <- as.matrix(maxquant_protein_table[, intensity_colnames])
        colnames(abundance_matrix) <- sub("^LFQ\\\\.intensity\\\\.", "", intensity_colnames)
        rownames(abundance_matrix) <- maxquant_protein_table\$Protein.IDs
        
        # Convert zero values to NA
        abundance_matrix[abundance_matrix == 0] <- NA
        
        # 2. Log2-transform the intensities
        abundance_matrix <- log2(abundance_matrix)
        
        # 3. Perform median normalization using median_normalization()
        normalized_abundance_matrix <- median_normalization(abundance_matrix)
        
        # 4. Estimate sample distances using dist_approx()
        da <- dist_approx(normalized_abundance_matrix)
        
        # Create sample information data frame
        sample_info_df <- data.frame(name = colnames(normalized_abundance_matrix),
                                     stringsAsFactors = FALSE)
        sample_info_df\$condition <- sub("\\\\.\\\\d+\$", "", sample_info_df\$name)
        sample_info_df\$replicate <- suppressWarnings(as.numeric(sub("^.*\\\\.", "", sample_info_df\$name)))
        
        # Determine reference and test conditions dynamically
        unique_conditions <- unique(sample_info_df\$condition)
        ref_condition <- unique_conditions[1]
        
        # 5. Fit the probabilistic dropout model using proDA()
        fit <- proDA(normalized_abundance_matrix, design = ~ condition, 
                     col_data = sample_info_df, reference_level = ref_condition)
        
        # 6. Test for differential abundance using test_diff()
        if (length(unique_conditions) > 1) {
          test_condition <- unique_conditions[2]
          contrast_name <- paste0("condition", test_condition)
          test_res <- test_diff(fit, contrast_name)
        } else {
          test_res <- test_diff(fit, "(Intercept)")
        }
        
        # --- Write Output Files ---
        
        # Save the differential abundance test results as a CSV table
        write.csv(test_res, "differential_abundance_results.csv", row.names = FALSE)
        
        # Save the normalized abundance matrix as a CSV table
        write.csv(normalized_abundance_matrix, "normalized_abundance_matrix.csv", row.names = TRUE)
        
        # Save the fitted proDA model object as an RDS file
        saveRDS(fit, "proda_fit.rds")
        
        # Save the estimated sample distances as an RDS file
        saveRDS(da, "sample_distances.rds")
        
        # Generate and save a diagnostic plot of the sample distances
        pdf("sample_distance_heatmap.pdf", width = 8, height = 8)
        tryCatch({
          if (requireNamespace("pheatmap", quietly = TRUE)) {
            plot_mat <- as.matrix(da\$mean)
            diag(plot_mat) <- NA
            pheatmap::pheatmap(plot_mat, 
                               cluster_rows = FALSE, 
                               cluster_cols = FALSE, 
                               main = "Sample Distance Heatmap (Expected Distance)")
          } else {
            plot_mat <- as.matrix(da\$mean)
            diag(plot_mat) <- NA
            heatmap(plot_mat, Rowv = NA, Colv = NA, main = "Sample Distance Heatmap")
          }
        }, error = function(e) {
          warning("Could not generate heatmap plot: ", e\$message)
        })
        dev.off()
        
        # Generate and save a boxplot of the normalized intensity distributions
        pdf("normalized_intensity_boxplot.pdf", width = 10, height = 6)
        boxplot(normalized_abundance_matrix, 
                las = 2, 
                main = "Normalized Intensity Distribution per Sample", 
                ylab = "Log2 Intensity")
        dev.off()

    writeLines(c(
        '"BIOC_PRODA_DIFFERENTIAL_ABUNDANCE_ANALYSIS":',
        paste0('    proDA: ', as.character(packageVersion('proDA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_abundance_analysis.csv versions.yml
    """
}

workflow BIOC_PRODA_DIFFERENTIAL_ABUNDANCE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ proteinGroups.txt ] ]

    main:
    BIOC_PRODA_DIFFERENTIAL_ABUNDANCE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_PRODA_DIFFERENTIAL_ABUNDANCE_ANALYSIS.out.tables
    plots    = BIOC_PRODA_DIFFERENTIAL_ABUNDANCE_ANALYSIS.out.plots
    objects  = BIOC_PRODA_DIFFERENTIAL_ABUNDANCE_ANALYSIS.out.objects
    versions = BIOC_PRODA_DIFFERENTIAL_ABUNDANCE_ANALYSIS.out.versions
}
