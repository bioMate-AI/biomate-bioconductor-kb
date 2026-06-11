#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ArrayExpress — arrayexpress_local_magetab
// Build a Bioconductor ExpressionSet from local MAGE-TAB files generated from input expression and metadata, and perform differential expression analysis using li
// Input: counts.csv, coldata.csv
// Container: 1.70.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ArrayExpress, Biobase, limma
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ARRAYEXPRESS_ARRAYEXPRESS_LOCAL_MAGETAB {
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
    library(ArrayExpress)
    library(Biobase)
    library(limma)
    
    # --- Read input files from the working directory ---
    if (!file.exists("counts.csv") || !file.exists("coldata.csv")) {
      stop("Required input files 'counts.csv' and 'coldata.csv' are missing.")
    }
    
    counts <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
    coldata <- read.csv("coldata.csv", check.names = FALSE)
    
    # Ensure sample names match between coldata and counts
    sample_names <- coldata\$sample
    counts <- counts[, sample_names, drop = FALSE]
    
    # --- Generate local MAGE-TAB files to simulate an ArrayExpress ---
    message("Generating local MAGE-TAB files...")
    
    # 1. Create the Processed Data File (processed.txt)
    # Columns: Composite Element REF, and SampleName:Intensity for each sample
    proc_data <- data.frame(`Composite Element REF` = rownames(counts), check.names = FALSE)
    for (sample in sample_names) {
      proc_data[[paste0(sample, ":Intensity")]] <- counts[[sample]]
    }
    write.table(proc_data, "processed.txt", sep = "\t", row.names = FALSE, quote = FALSE)
    
    # 2. Create the SDRF (Sample and Data Relationship Format) File
    sdrf_data <- data.frame(
      `Source Name` = sample_names,
      `Assay Name` = sample_names,
      `Hybridization Name` = sample_names,
      `Derived Data File` = "processed.txt",
      `Factor Value[condition]` = coldata\$condition,
      check.names = FALSE
    )
    write.table(sdrf_data, "sdrf.txt", sep = "\t", row.names = FALSE, quote = FALSE)
    
    # 3. Create a minimal IDF (Investigation Description Format) File
    idf_data <- data.frame(
      MAGE_TAB_Version = "1.1",
      Investigation_Title = "Local Pipeline Study"
    )
    write.table(t(idf_data), "idf.txt", sep = "\t", col.names = FALSE, quote = FALSE)
    
    # 4. Create a minimal ADF (Array Design Format) File
    adf_data <- data.frame(
      `Block` = 1,
      `Row` = 1:nrow(counts),
      `Column` = 1,
      `Reporter Identifier` = rownames(counts),
      check.names = FALSE
    )
    write.table(adf_data, "adf.txt", sep = "\t", row.names = FALSE, quote = FALSE)
    
    # --- Build Bioconductor ExpressionSet using ArrayExpress ---
    message("Building ExpressionSet using ArrayExpress...")
    mageFiles <- list(
      procfile = "processed.txt",
      sdrf = "sdrf.txt",
      idf = "idf.txt",
      adf = "adf.txt",
      path = "."
    )
    
    proset <- tryCatch({
      # Identify available processed columns
      cn <- getcolproc(mageFiles)
      message("Identified processed columns: ", paste(cn, collapse = ", "))
      
      # Select the target intensity column
      target_col <- grep("Intensity", cn, value = TRUE)[1]
      if (is.na(target_col)) target_col <- cn[1]
      
      # Build the ExpressionSet
      procset(mageFiles, target_col)
    }, error = function(e) {
      message("ArrayExpress parsing failed: ", e\$message)
      message("Falling back to manual ExpressionSet construction...")
      
      # Fallback manual construction
      exprs_mat <- as.matrix(counts)
      pheno_df <- AnnotatedDataFrame(coldata)
      rownames(pheno_df) <- coldata\$sample
      ExpressionSet(assayData = exprs_mat, phenoData = pheno_df)
    })
    
    # --- Differential Expression Analysis using limma ---
    message("Performing differential expression analysis...")
    
    # Extract experimental factor
    pheno <- pData(proset)
    factor_col <- grep("condition|Factor", colnames(pheno), ignore.case = TRUE, value = TRUE)[1]
    
    if (length(factor_col) > 0 && !is.na(factor_col)) {
      design_factor <- pheno[[factor_col]]
    } else {
      design_factor <- coldata\$condition
    }
    
    f <- factor(design_factor)
    design <- model.matrix(~0 + f)
    colnames(design) <- levels(f)
    
    fit <- lmFit(proset, design)
    
    # Create contrasts if there are at least 2 levels
    levels_f <- levels(f)
    if (length(levels_f) >= 2) {
      contrast_formula <- paste0(levels_f[2], " - ", levels_f[1])
      cont_matrix <- makeContrasts(contrasts = contrast_formula, levels = design)
      fit2 <- contrasts.fit(fit, cont_matrix)
      fit2 <- eBayes(fit2)
      res <- topTable(fit2, coef = 1, number = Inf, adjust.method = "BH")
    } else {
      message("Fewer than 2 conditions found. Fitting intercept-only model.")
      fit2 <- eBayes(fit)
      res <- topTable(fit2, coef = 1, number = Inf, adjust.method = "BH")
    }
    
    # Save results
    write.csv(res, "differential_expression_results.csv", row.names = TRUE)
    message("Results written to 'differential_expression_results.csv'")
    
    # --- Visualization and Diagnostics ---
    message("Generating diagnostic plots...")
    pdf("analysis_plots.pdf", width = 8, height = 6)
    
    # Volcano Plot
    if ("logFC" %in% colnames(res) && "adj.P.Val" %in% colnames(res)) {
      plot(res\$logFC, -log10(res\$adj.P.Val),
           main = "Volcano Plot of Differential Expression",
           xlab = "Log2 Fold Change",
           ylab = "-Log10 Adjusted P-value",
           col = ifelse(res\$adj.P.Val < 0.05, "red", "black"),
           pch = 20)
      abline(h = -log10(0.05), col = "blue", lty = 2)
      legend("topright", legend = c("FDR < 0.05", "Not Significant"), col = c("red", "black"), pch = 20)
    } else {
      plot(1, type = "n", xlab = "", ylab = "", main = "No Contrast Available for Volcano Plot")
    }
    
    dev.off()
    message("Plots saved to 'analysis_plots.pdf'")

    writeLines(c(
        '"BIOC_ARRAYEXPRESS_ARRAYEXPRESS_LOCAL_MAGETAB":',
        paste0('    ArrayExpress: ', as.character(packageVersion('ArrayExpress')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_arrayexpress_local_magetab.csv versions.yml
    """
}

workflow BIOC_ARRAYEXPRESS_ARRAYEXPRESS_LOCAL_MAGETAB_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_ARRAYEXPRESS_ARRAYEXPRESS_LOCAL_MAGETAB(ch_input)

    emit:
    tables   = BIOC_ARRAYEXPRESS_ARRAYEXPRESS_LOCAL_MAGETAB.out.tables
    plots    = BIOC_ARRAYEXPRESS_ARRAYEXPRESS_LOCAL_MAGETAB.out.plots
    objects  = BIOC_ARRAYEXPRESS_ARRAYEXPRESS_LOCAL_MAGETAB.out.objects
    versions = BIOC_ARRAYEXPRESS_ARRAYEXPRESS_LOCAL_MAGETAB.out.versions
}
