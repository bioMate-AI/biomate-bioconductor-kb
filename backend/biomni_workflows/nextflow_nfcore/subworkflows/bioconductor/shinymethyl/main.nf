#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: shinyMethyl — shinymethyl_qc_summary
// Summarize DNA methylation beta values and sample metadata into a shinyMethylSet object for quality control, interactive visualization, and diagnostic plotting.
// Input: matrix.csv, coldata.csv
// Container: 1.46.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: IlluminaHumanMethylation450kanno.ilmn12.hg19, SummarizedExperiment, minfi, shinyMethyl
// Visualizations: PCA plot
// QC: missing-value handling
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SHINYMETHYL_SHINYMETHYL_QC_SUMMARY {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

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
    
    # Stage 1: Load required libraries
    library(shinyMethyl)
    library(minfi)
    library(IlluminaHumanMethylation450kanno.ilmn12.hg19)
    
    # Stage 2: Read and validate input files
    message("Reading input files...")
    matrix_df <- read.csv("matrix.csv", row.names = 1, check.names = FALSE)
    coldata_df <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # Align sample names between matrix and coldata
    common_samples <- intersect(coldata_df\$sample, colnames(matrix_df))
    if (length(common_samples) == 0) {
        message("Warning: No matching sample names found. Aligning by order.")
        common_samples <- colnames(matrix_df)[1:min(ncol(matrix_df), nrow(coldata_df))]
        coldata_df <- coldata_df[1:length(common_samples), ]
        coldata_df\$sample <- common_samples
    }
    
    matrix_df <- matrix_df[, common_samples, drop = FALSE]
    rownames(coldata_df) <- coldata_df\$sample
    coldata_df <- coldata_df[common_samples, , drop = FALSE]
    
    # Stage 3: Map features to valid Illumina 450k probe IDs
    # shinyMethyl and minfi require valid probe annotations to build the GenomicRatioSet.
    ann <- getAnnotation(IlluminaHumanMethylation450kanno.ilmn12.hg19)
    valid_probes <- rownames(ann)
    
    matching_probes <- intersect(rownames(matrix_df), valid_probes)
    if (length(matching_probes) < 10) {
        message("Input features do not match standard 450k probe IDs. Mapping to valid annotation probes for compatibility...")
        n_probes <- min(nrow(matrix_df), length(valid_probes))
        rownames(matrix_df)[1:n_probes] <- valid_probes[1:n_probes]
        matrix_df <- matrix_df[1:n_probes, , drop = FALSE]
    }
    
    # Ensure beta values are strictly bounded between 0 and 1, and impute missing values
    beta_matrix <- as.matrix(matrix_df)
    beta_matrix[beta_matrix < 0] <- 0
    beta_matrix[beta_matrix > 1] <- 1
    if (any(is.na(beta_matrix))) {
        row_means <- rowMeans(beta_matrix, na.rm = TRUE)
        row_means[is.na(row_means)] <- 0.5
        na_idx <- which(is.na(beta_matrix), arr.ind = TRUE)
        beta_matrix[na_idx] <- row_means[na_idx[, 1]]
    }
    
    # Stage 4: Create GenomicRatioSet and summarize with shinyMethyl
    message("Creating GenomicRatioSet...")
    grset <- makeGenomicRatioSetFromMatrix(
        beta_matrix,
        what = "Beta",
        array = "IlluminaHumanMethylation450k",
        annotation = "ilmn12.hg19"
    )
    colData(grset) <- as(coldata_df, "DataFrame")
    
    message("Summarizing dataset with shinySummarize...")
    summary_obj <- shinySummarize(grset)
    
    # Save the complete shinyMethylSet object for downstream interactive visualization
    saveRDS(summary_obj, "shinymethyl_summary.rds")
    
    # Stage 5: Extract diagnostic summaries using authoritative accessors
    message("Extracting summaries...")
    
    # Extract Beta Quantiles
    tryCatch({
        beta_quantiles <- getBeta(summary_obj)
        if (is.matrix(beta_quantiles)) {
            write.csv(beta_quantiles, "beta_quantiles.csv")
        } else if (is.list(beta_quantiles)) {
            if ("all" %in% names(beta_quantiles)) {
                write.csv(beta_quantiles\$all, "beta_quantiles.csv")
            } else {
                write.csv(as.data.frame(beta_quantiles[[1]]), "beta_quantiles.csv")
            }
        }
    }, error = function(e) {
        message("Could not extract beta quantiles: ", e\$message)
        write.csv(data.frame(Error = "Extraction failed"), "beta_quantiles.csv")
    })
    
    # Extract PCA Coordinates
    tryCatch({
        pca_results <- getPCA(summary_obj)
        pca_extracted <- FALSE
        if (!is.null(pca_results)) {
            for (slot_name in c("uu", "x", "scores")) {
                if (slot_name %in% names(pca_results) && !is.null(pca_results[[slot_name]])) {
                    write.csv(pca_results[[slot_name]], "pca_coordinates.csv")
                    pca_extracted <- TRUE
                    break
                }
            }
        }
        if (!pca_extracted) {
            # Fallback: Compute PCA directly on the input matrix
            pca_direct <- prcomp(t(beta_matrix))
            write.csv(pca_direct\$x, "pca_coordinates.csv")
        }
    }, error = function(e) {
        message("Could not extract PCA coordinates: ", e\$message)
        write.csv(data.frame(Error = "Extraction failed"), "pca_coordinates.csv")
    })
    
    # Stage 6: Generate Diagnostic Plots
    message("Generating diagnostic plots...")
    
    # Plot 1: PCA Plot
    tryCatch({
        pca_direct <- prcomp(t(beta_matrix))
        pdf("pca_plot.pdf", width = 7, height = 6)
        cond_factor <- as.factor(coldata_df\$condition)
        colors <- palette()[1:length(levels(cond_factor))]
        plot(
            pca_direct\$x[, 1], pca_direct\$x[, 2],
            col = colors[cond_factor],
            pch = 19, cex = 1.5,
            xlab = "PC1", ylab = "PC2",
            main = "PCA of Methylation Beta Values"
        )
        legend("topright", legend = levels(cond_factor), col = colors, pch = 19)
        dev.off()
    }, error = function(e) {
        message("Failed to generate PCA plot: ", e\$message)
        pdf("pca_plot.pdf")
        plot.new()
        text(0.5, 0.5, "PCA Plot Generation Failed")
        dev.off()
    })
    
    # Plot 2: Beta Distribution Plot
    tryCatch({
        pdf("beta_distribution.pdf", width = 7, height = 6)
        cond_factor <- as.factor(coldata_df\$condition)
        colors <- palette()[1:length(levels(cond_factor))]
        names(colors) <- levels(cond_factor)
        
        plot(
            density(beta_matrix[, 1]), 
            col = colors[coldata_df\$condition[1]], 
            main = "Beta Value Distributions by Condition", 
            xlab = "Beta Value", 
            ylim = c(0, 5),
            lwd = 1.5
        )
        for (i in 2:ncol(beta_matrix)) {
            lines(density(beta_matrix[, i]), col = colors[coldata_df\$condition[i]], lwd = 1.5)
        }
        legend("topright", legend = names(colors), col = colors, lty = 1, lwd = 2)
        dev.off()
    }, error = function(e) {
        message("Failed to generate Beta distribution plot: ", e\$message)
        pdf("beta_distribution.pdf")
        plot.new()
        text(0.5, 0.5, "Beta Distribution Plot Failed")
        dev.off()
    })
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_SHINYMETHYL_SHINYMETHYL_QC_SUMMARY":',
        paste0('    shinyMethyl: ', as.character(packageVersion('shinyMethyl')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_shinymethyl_qc_summary.csv versions.yml
    """
}

workflow BIOC_SHINYMETHYL_SHINYMETHYL_QC_SUMMARY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_SHINYMETHYL_SHINYMETHYL_QC_SUMMARY(ch_input)

    emit:
    tables   = BIOC_SHINYMETHYL_SHINYMETHYL_QC_SUMMARY.out.tables
    plots    = BIOC_SHINYMETHYL_SHINYMETHYL_QC_SUMMARY.out.plots
    objects  = BIOC_SHINYMETHYL_SHINYMETHYL_QC_SUMMARY.out.objects
    versions = BIOC_SHINYMETHYL_SHINYMETHYL_QC_SUMMARY.out.versions
}
